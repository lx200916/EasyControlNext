//! Unified ADB session: CNXN/AUTH handshake (+ optional A_STLS/TLS) + OPEN/OKAY/WRTE/CLSE multiplexer.

use std::collections::{HashMap, VecDeque};
use std::net::TcpStream;
use std::time::Duration;

use easycontrol_protocol::adb::{
  self, AdbMessage, AUTH_TYPE_RSA_PUBLIC, AUTH_TYPE_SIGNATURE, CMD_AUTH, CMD_CLSE, CMD_CNXN,
  CMD_OKAY, CMD_OPEN, CMD_STLS, CMD_WRTE, ADB_HEADER_LENGTH,
};

use crate::error::{AdbError, AdbResult};
use crate::signer::AdbSigner;
use crate::sync_pull::{build_quit, build_recv_request, PullStreamParser, SyncPullResult};
use crate::sync_push::{build_sync_push, SyncPushPlan};
use crate::tls_client::upgrade_tcp_to_tls;
use crate::transport::{AdbTransport, SessionIo};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
  Connected,
  Closed,
}

#[derive(Debug)]
struct StreamState {
  remote_id: u32,
  /// Credits: number of OKAYs received that allow WRTE (open grants 1).
  write_credits: u32,
  closed: bool,
  incoming: VecDeque<u8>,
}

/// Single-connection ADB client session with logical stream multiplexing.
pub struct AdbSession<T: AdbTransport> {
  transport: T,
  state: SessionState,
  max_data: u32,
  next_local_id: u32,
  streams: HashMap<u32, StreamState>,
  /// Pending OPEN local_ids waiting for first OKAY.
  pending_open: HashMap<u32, ()>,
  /// Bytes already pulled from the socket but not yet consumed by a message parse.
  /// Critical with short read timeouts / TLS: `read_exact` timeout must not drop
  /// a partial ADB header or the stream desyncs and video freezes after first AUs.
  rx_stash: Vec<u8>,
}

impl AdbSession<SessionIo> {
  /// Production connect: handles classic AUTH and wireless A_STLS → TLS 1.3 → CNXN.
  ///
  /// AOSP wireless (`_adb-tls-connect._tcp`): client CNXN → server STLS → client STLS →
  /// TLS handshake (client cert = pairing key) → server CNXN over TLS (no RSA AUTH).
  pub fn connect_with_key(
    stream: TcpStream,
    signer: &dyn AdbSigner,
    private_key_pem: &str,
    server_name: &str,
    io_timeout: Duration,
  ) -> AdbResult<Self> {
    let mut transport = SessionIo::Plain(stream);
    transport.set_read_timeout(Some(io_timeout))?;
    transport.set_write_timeout(Some(io_timeout))?;
    transport.write_all(&adb::generate_connect())?;

    let mut msg = Self::read_message_raw(&mut transport, true)?;

    if msg.header.command == CMD_STLS {
      if private_key_pem.trim().is_empty() {
        let _ = transport.close();
        return Err(AdbError::Tls(
          "device requires A_STLS (wireless TLS ADB); missing private key PEM".into(),
        ));
      }
      transport.write_all(&adb::generate_stls())?;
      let sock = match transport {
        SessionIo::Plain(s) => s,
        SessionIo::Tls(_) => {
          return Err(AdbError::InvalidState("expected plaintext before STLS upgrade"));
        }
      };
      let tls = upgrade_tcp_to_tls(sock, private_key_pem, server_name).map_err(|e| {
        AdbError::Tls(format!(
          "{e} (pair wireless debugging first; use _adb-tls-connect port, not pairing port)"
        ))
      })?;
      transport = SessionIo::Tls(Box::new(tls));
      transport.set_read_timeout(Some(io_timeout))?;
      transport.set_write_timeout(Some(io_timeout))?;
      // AOSP: after TLS success the server speaks first with CNXN (cert replaces AUTH).
      msg = Self::read_message_raw(&mut transport, true)?;
      // Some stacks may still challenge; handle AUTH over TLS like classic path.
      if msg.header.command == CMD_AUTH {
        msg = Self::complete_auth(&mut transport, signer, msg)?;
      }
      if msg.header.command != CMD_CNXN {
        let got = msg.header.command;
        let _ = transport.close();
        return Err(AdbError::UnexpectedCommand {
          expected: "CNXN (after STLS/TLS)",
          got,
        });
      }
      return Ok(Self::from_cnxn(transport, msg));
    }

    if msg.header.command == CMD_AUTH {
      msg = Self::complete_auth(&mut transport, signer, msg)?;
    }

    if msg.header.command != CMD_CNXN {
      let got = msg.header.command;
      let _ = transport.close();
      if got == CMD_STLS {
        return Err(AdbError::Tls(
          "unexpected STLS after AUTH path".into(),
        ));
      }
      return Err(AdbError::UnexpectedCommand {
        expected: "CNXN",
        got,
      });
    }

    Ok(Self::from_cnxn(transport, msg))
  }

  fn from_cnxn(transport: SessionIo, msg: AdbMessage) -> Self {
    Self {
      transport,
      state: SessionState::Connected,
      max_data: if msg.header.arg1 == 0 {
        adb::CONNECT_MAXDATA
      } else {
        msg.header.arg1
      },
      next_local_id: 1,
      streams: HashMap::new(),
      pending_open: HashMap::new(),
      rx_stash: Vec::new(),
    }
  }

  fn complete_auth(
    transport: &mut SessionIo,
    signer: &dyn AdbSigner,
    mut msg: AdbMessage,
  ) -> AdbResult<AdbMessage> {
    if msg.header.arg0 != adb::AUTH_TYPE_TOKEN {
      return Err(AdbError::AuthFailed("expected AUTH token"));
    }
    let sig = signer.sign_token(&msg.payload)?;
    transport.write_all(&adb::generate_auth(AUTH_TYPE_SIGNATURE, &sig))?;
    msg = Self::read_message_raw(transport, true)?;
    if msg.header.command == CMD_AUTH {
      let pub_key = signer.public_key_payload()?;
      transport.write_all(&adb::generate_auth(AUTH_TYPE_RSA_PUBLIC, &pub_key))?;
      msg = Self::read_message_raw(transport, true)?;
    }
    Ok(msg)
  }
}

impl<T: AdbTransport> AdbSession<T> {
  /// Perform CNXN + AUTH (authorized-device / FakeDaemon path) and return a live session.
  /// For wireless `_adb-tls-connect._tcp` (A_STLS), use [`Self::connect_with_key`] instead.
  pub fn connect(mut transport: T, signer: &dyn AdbSigner, io_timeout: Duration) -> AdbResult<Self> {
    transport.set_read_timeout(Some(io_timeout))?;
    transport.set_write_timeout(Some(io_timeout))?;
    transport.write_all(&adb::generate_connect())?;

    let mut msg = Self::read_message_raw(&mut transport, true)?;
    if msg.header.command == CMD_STLS {
      let _ = transport.close();
      return Err(AdbError::Tls(
        "got A_STLS (0x534c5453): wireless TLS ADB requires connect_with_key / pairing RSA cert"
          .into(),
      ));
    }
    if msg.header.command == CMD_AUTH {
      if msg.header.arg0 != adb::AUTH_TYPE_TOKEN {
        return Err(AdbError::AuthFailed("expected AUTH token"));
      }
      let sig = signer.sign_token(&msg.payload)?;
      transport.write_all(&adb::generate_auth(AUTH_TYPE_SIGNATURE, &sig))?;
      msg = Self::read_message_raw(&mut transport, true)?;
      if msg.header.command == CMD_AUTH {
        let pub_key = signer.public_key_payload()?;
        transport.write_all(&adb::generate_auth(AUTH_TYPE_RSA_PUBLIC, &pub_key))?;
        msg = Self::read_message_raw(&mut transport, true)?;
      }
    }

    if msg.header.command != CMD_CNXN {
      let _ = transport.close();
      return Err(AdbError::UnexpectedCommand {
        expected: "CNXN",
        got: msg.header.command,
      });
    }

    Ok(Self {
      transport,
      state: SessionState::Connected,
      max_data: if msg.header.arg1 == 0 {
        adb::CONNECT_MAXDATA
      } else {
        msg.header.arg1
      },
      next_local_id: 1,
      streams: HashMap::new(),
      pending_open: HashMap::new(),
      rx_stash: Vec::new(),
    })
  }

  pub fn state(&self) -> SessionState {
    self.state
  }

  pub fn max_data(&self) -> u32 {
    self.max_data
  }

  /// Adjust transport read/write timeouts after connect (e.g. short polls during Gate D retries).
  pub fn set_io_timeout(&mut self, timeout: Duration) -> AdbResult<()> {
    self.transport.set_read_timeout(Some(timeout))?;
    self.transport.set_write_timeout(Some(timeout))?;
    Ok(())
  }

  pub fn close(&mut self) -> AdbResult<()> {
    self.state = SessionState::Closed;
    self.streams.clear();
    self.pending_open.clear();
    self.transport.close()
  }

  /// OPEN a service destination; returns local_id after OKAY.
  pub fn open(&mut self, destination: &str) -> AdbResult<u32> {
    self.ensure_connected()?;
    let local_id = self.alloc_local_id();
    self.pending_open.insert(local_id, ());
    self.transport
      .write_all(&adb::generate_open(local_id, destination))?;
    self.wait_until(|s| s.streams.contains_key(&local_id))?;
    Ok(local_id)
  }

  pub fn write_stream(&mut self, local_id: u32, data: &[u8]) -> AdbResult<()> {
    self.ensure_connected()?;
    if data.is_empty() {
      return Ok(());
    }
    let max = self.max_data as usize;
    let mut offset = 0usize;
    while offset < data.len() {
      self.wait_until(|s| {
        s.streams
          .get(&local_id)
          .map(|st| st.closed || st.write_credits > 0)
          .unwrap_or(true)
      })?;
      let (remote_id, chunk) = {
        let st = self
          .streams
          .get_mut(&local_id)
          .ok_or(AdbError::StreamNotFound(local_id))?;
        if st.closed {
          return Err(AdbError::StreamClosed);
        }
        if st.write_credits == 0 {
          return Err(AdbError::FlowControl);
        }
        let end = (offset + max).min(data.len());
        let chunk = data[offset..end].to_vec();
        if chunk.len() > max {
          return Err(AdbError::PayloadTooLarge {
            length: chunk.len(),
            max,
          });
        }
        st.write_credits -= 1;
        let remote_id = st.remote_id;
        offset = end;
        (remote_id, chunk)
      };
      self.transport
        .write_all(&adb::generate_write(local_id, remote_id, &chunk))?;
    }
    Ok(())
  }

  /// Read currently buffered stream bytes.
  pub fn read_stream_buf(&mut self, local_id: u32) -> AdbResult<Vec<u8>> {
    self.pump()?;
    let st = self
      .streams
      .get_mut(&local_id)
      .ok_or(AdbError::StreamNotFound(local_id))?;
    Ok(st.incoming.drain(..).collect())
  }

  /// Block until at least `min_len` bytes available or stream closed.
  pub fn read_stream_at_least(&mut self, local_id: u32, min_len: usize) -> AdbResult<Vec<u8>> {
    self.wait_until(|s| {
      s.streams
        .get(&local_id)
        .map(|st| st.incoming.len() >= min_len || st.closed)
        .unwrap_or(true)
    })?;
    let st = self
      .streams
      .get_mut(&local_id)
      .ok_or(AdbError::StreamNotFound(local_id))?;
    Ok(st.incoming.drain(..).collect())
  }

  pub fn close_stream(&mut self, local_id: u32) -> AdbResult<()> {
    self.ensure_connected()?;
    let remote_id = {
      let st = self
        .streams
        .get(&local_id)
        .ok_or(AdbError::StreamNotFound(local_id))?;
      if st.closed {
        return Ok(());
      }
      st.remote_id
    };
    self.transport
      .write_all(&adb::generate_close(local_id, remote_id))?;
    if let Some(st) = self.streams.get_mut(&local_id) {
      st.closed = true;
    }
    Ok(())
  }

  pub fn is_stream_closed(&self, local_id: u32) -> bool {
    self.streams.get(&local_id).map(|s| s.closed).unwrap_or(true)
  }

  /// `shell:<cmd>` then read until remote CLSE.
  pub fn shell(&mut self, cmd: &str) -> AdbResult<Vec<u8>> {
    let dest = format!("shell:{cmd}");
    let id = self.open(&dest)?;
    let mut out = Vec::new();
    loop {
      self.wait_until(|s| {
        s.streams
          .get(&id)
          .map(|st| !st.incoming.is_empty() || st.closed)
          .unwrap_or(true)
      })?;
      let chunk = {
        let st = self
          .streams
          .get_mut(&id)
          .ok_or(AdbError::StreamNotFound(id))?;
        st.incoming.drain(..).collect::<Vec<_>>()
      };
      out.extend(chunk);
      if self.is_stream_closed(id) {
        break;
      }
    }
    let _ = self.streams.remove(&id);
    Ok(out)
  }

  /// Sync push file bytes to `remote_path`; returns push plan metadata (incl. sha256).
  pub fn sync_push(&mut self, remote_path: &str, file_data: &[u8]) -> AdbResult<SyncPushPlan> {
    let plan = build_sync_push(remote_path, file_data)?;
    let id = self.open("sync:")?;
    self.write_stream(id, &plan.bytes)?;
    self.wait_until(|s| s.streams.get(&id).map(|st| st.closed).unwrap_or(true))?;
    let _ = self.streams.remove(&id);
    Ok(plan)
  }

  /// Sync pull file bytes from `remote_path` (RECV/DATA/DONE). Separate from live Gate D mux.
  pub fn sync_pull(&mut self, remote_path: &str) -> AdbResult<SyncPullResult> {
    let req = build_recv_request(remote_path)?;
    let id = self.open("sync:")?;
    self.write_stream(id, &req)?;

    let mut parser = PullStreamParser::new();
    let mut spins = 0u32;
    while !parser.is_finished() {
      self.wait_until(|s| {
        s.streams
          .get(&id)
          .map(|st| !st.incoming.is_empty() || st.closed)
          .unwrap_or(true)
      })?;
      let chunk = {
        let st = self
          .streams
          .get_mut(&id)
          .ok_or(AdbError::StreamNotFound(id))?;
        st.incoming.drain(..).collect::<Vec<_>>()
      };
      if !chunk.is_empty() {
        parser.push(&chunk)?;
      }
      if parser.is_finished() {
        break;
      }
      if self.is_stream_closed(id) {
        // Flush any remaining buffered bytes before failing.
        let leftover = {
          let st = self
            .streams
            .get_mut(&id)
            .ok_or(AdbError::StreamNotFound(id))?;
          st.incoming.drain(..).collect::<Vec<_>>()
        };
        if !leftover.is_empty() {
          parser.push(&leftover)?;
        }
        if !parser.is_finished() {
          return Err(AdbError::RemoteFail(
            "sync pull stream closed before DONE".into(),
          ));
        }
        break;
      }
      spins += 1;
      if spins > 50_000 {
        return Err(AdbError::Timeout);
      }
    }

    let result = parser.finish(remote_path)?;
    // Best-effort QUIT; some daemons CLSE immediately after DONE.
    let _ = self.write_stream(id, &build_quit()?);
    let _ = self.close_stream(id);
    let _ = self.streams.remove(&id);
    Ok(result)
  }

  /// Open `tcp:<port>` and return local_id for bidirectional I/O.
  pub fn open_tcp(&mut self, port: u16) -> AdbResult<u32> {
    self.open(&format!("tcp:{port}"))
  }

  fn alloc_local_id(&mut self) -> u32 {
    let id = self.next_local_id;
    self.next_local_id = self.next_local_id.wrapping_add(1).max(1);
    id
  }

  fn ensure_connected(&self) -> AdbResult<()> {
    if self.state != SessionState::Connected {
      return Err(AdbError::InvalidState("session not connected"));
    }
    Ok(())
  }

  fn wait_until(&mut self, mut pred: impl FnMut(&Self) -> bool) -> AdbResult<()> {
    let mut spins = 0u32;
    while !pred(self) {
      self.pump()?;
      spins += 1;
      if spins > 10_000 {
        return Err(AdbError::Timeout);
      }
    }
    Ok(())
  }

  /// Read and dispatch one message (blocking until timeout on transport).
  pub fn pump(&mut self) -> AdbResult<()> {
    self.ensure_connected()?;
    let msg = match self.read_message(true) {
      Ok(m) => m,
      Err(AdbError::Timeout) => return Ok(()),
      Err(AdbError::Io(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
        self.state = SessionState::Closed;
        return Err(AdbError::Io(e));
      }
      Err(e) => return Err(e),
    };
    self.dispatch(msg)
  }

  /// Drain up to `max` queued ADB messages (WRTE/OKAY/CLSE). Returns how many were handled.
  /// Used by AdbTcp video feed so TLS bursts of video WRTE get OKAY'd promptly.
  pub fn pump_available(&mut self, max: usize) -> AdbResult<usize> {
    self.ensure_connected()?;
    let mut n = 0usize;
    while n < max {
      match self.read_message(true) {
        Ok(msg) => {
          self.dispatch(msg)?;
          n += 1;
        }
        Err(AdbError::Timeout) => break,
        Err(AdbError::Io(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
          self.state = SessionState::Closed;
          return Err(AdbError::Io(e));
        }
        Err(e) => return Err(e),
      }
    }
    Ok(n)
  }

  fn dispatch(&mut self, msg: AdbMessage) -> AdbResult<()> {
    match msg.header.command {
      CMD_OKAY => {
        let local_id = msg.header.arg1;
        let remote_id = msg.header.arg0;
        if self.pending_open.remove(&local_id).is_some() {
          self.streams.insert(
            local_id,
            StreamState {
              remote_id,
              write_credits: 1,
              closed: false,
              incoming: VecDeque::new(),
            },
          );
        } else if let Some(st) = self.streams.get_mut(&local_id) {
          st.remote_id = remote_id;
          st.write_credits = st.write_credits.saturating_add(1);
        }
        Ok(())
      }
      CMD_WRTE => {
        let local_id = msg.header.arg1;
        let remote_id = msg.header.arg0;
        if let Some(st) = self.streams.get_mut(&local_id) {
          st.remote_id = remote_id;
          st.incoming.extend(msg.payload.iter().copied());
        }
        let okay = adb::generate_okay(local_id, remote_id);
        self.transport.write_all(&okay)?;
        Ok(())
      }
      CMD_CLSE => {
        let local_id = msg.header.arg1;
        if let Some(st) = self.streams.get_mut(&local_id) {
          st.closed = true;
        }
        self.pending_open.remove(&local_id);
        Ok(())
      }
      CMD_AUTH => Err(AdbError::AuthFailed("unexpected AUTH after connect")),
      CMD_OPEN => Err(AdbError::UnexpectedCommand {
        expected: "client-only OPEN",
        got: CMD_OPEN,
      }),
      other => Err(AdbError::UnexpectedCommand {
        expected: "OKAY/WRTE/CLSE",
        got: other,
      }),
    }
  }

  /// Fill `buf` completely, surviving read timeouts after a partial fill (stash-safe).
  fn fill_exact(&mut self, buf: &mut [u8]) -> AdbResult<()> {
    let mut filled = 0usize;
    if !self.rx_stash.is_empty() {
      let take = self.rx_stash.len().min(buf.len());
      buf[..take].copy_from_slice(&self.rx_stash[..take]);
      self.rx_stash.drain(..take);
      filled = take;
    }
    while filled < buf.len() {
      let mut tmp = [0u8; 16 * 1024];
      match self.transport.read_some(&mut tmp) {
        Ok(0) => {
          return Err(AdbError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "adb EOF mid-message",
          )));
        }
        Ok(n) => {
          let need = buf.len() - filled;
          let copy = need.min(n);
          buf[filled..filled + copy].copy_from_slice(&tmp[..copy]);
          filled += copy;
          if copy < n {
            self.rx_stash.extend_from_slice(&tmp[copy..n]);
          }
        }
        Err(AdbError::Timeout) if filled == 0 => return Err(AdbError::Timeout),
        // Partial message already buffered in `buf` — keep waiting; never drop bytes.
        Err(AdbError::Timeout) => continue,
        Err(e) => return Err(e),
      }
    }
    Ok(())
  }

  fn read_message(&mut self, verify_checksum: bool) -> AdbResult<AdbMessage> {
    let mut header = [0u8; ADB_HEADER_LENGTH];
    self.fill_exact(&mut header)?;
    let hdr = adb::AdbHeader::decode(&header)?;
    hdr.validate_magic()?;
    let len = hdr.data_length as usize;
    if len > adb::ABSOLUTE_MAX_PAYLOAD {
      return Err(AdbError::PayloadTooLarge {
        length: len,
        max: adb::ABSOLUTE_MAX_PAYLOAD,
      });
    }
    let mut payload = vec![0u8; len];
    if len > 0 {
      self.fill_exact(&mut payload)?;
    }
    let mut full = Vec::with_capacity(ADB_HEADER_LENGTH + len);
    full.extend_from_slice(&header);
    full.extend_from_slice(&payload);
    Ok(adb::decode_message(&full, verify_checksum)?)
  }

  /// Connect-path helper before `AdbSession` owns the transport (no stash yet).
  fn read_message_raw(transport: &mut T, verify_checksum: bool) -> AdbResult<AdbMessage> {
    let mut header = [0u8; ADB_HEADER_LENGTH];
    transport.read_exact(&mut header)?;
    let hdr = adb::AdbHeader::decode(&header)?;
    hdr.validate_magic()?;
    let len = hdr.data_length as usize;
    if len > adb::ABSOLUTE_MAX_PAYLOAD {
      return Err(AdbError::PayloadTooLarge {
        length: len,
        max: adb::ABSOLUTE_MAX_PAYLOAD,
      });
    }
    let mut payload = vec![0u8; len];
    if len > 0 {
      transport.read_exact(&mut payload)?;
    }
    let mut full = Vec::with_capacity(ADB_HEADER_LENGTH + len);
    full.extend_from_slice(&header);
    full.extend_from_slice(&payload);
    Ok(adb::decode_message(&full, verify_checksum)?)
  }
}
