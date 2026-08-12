//! Deterministic fake ADB daemon for host integration tests (already-authorized path).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use easycontrol_protocol::adb::{
  self, AdbMessage, AUTH_TYPE_RSA_PUBLIC, AUTH_TYPE_SIGNATURE, AUTH_TYPE_TOKEN, CMD_AUTH, CMD_CLSE,
  CMD_CNXN, CMD_OKAY, CMD_OPEN, CMD_WRTE, CONNECT_MAXDATA, CONNECT_VERSION, ADB_HEADER_LENGTH,
};
use easycontrol_protocol::sync::{self, ID_DATA, ID_DONE, ID_QUIT, ID_SEND};
use sha2::{Digest, Sha256};

use crate::signer::DeterministicTestSigner;
use crate::sync_push::{PUSH_DONE_MTIME, PUSH_FILE_MODE};

#[derive(Debug, Default, Clone)]
pub struct FakeDaemonState {
  pub pushed_files: HashMap<String, Vec<u8>>,
  pub last_shell_cmd: Option<String>,
  pub connections: u32,
}

pub struct FakeDaemon {
  addr: String,
  join: Option<JoinHandle<()>>,
  state: Arc<Mutex<FakeDaemonState>>,
  stop: Arc<Mutex<bool>>,
}

impl FakeDaemon {
  /// Bind `127.0.0.1:0`, spawn accept loop. Auth accepts [`DeterministicTestSigner`] signatures.
  pub fn start() -> std::io::Result<Self> {
    let listener = TcpListener::bind("127.0.0.1:0")?;
    listener.set_nonblocking(false)?;
    let addr = listener.local_addr()?.to_string();
    let state = Arc::new(Mutex::new(FakeDaemonState::default()));
    let stop = Arc::new(Mutex::new(false));
    let state_t = Arc::clone(&state);
    let stop_t = Arc::clone(&stop);
    let join = thread::spawn(move || {
      listener
        .set_nonblocking(true)
        .expect("set nonblocking");
      while !*stop_t.lock().unwrap() {
        match listener.accept() {
          Ok((stream, _)) => {
            let st = Arc::clone(&state_t);
            thread::spawn(move || {
              let _ = handle_client(stream, st);
            });
          }
          Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
            thread::sleep(Duration::from_millis(10));
          }
          Err(_) => break,
        }
      }
    });
    // Give listener thread a moment.
    thread::sleep(Duration::from_millis(20));
    Ok(Self {
      addr,
      join: Some(join),
      state,
      stop,
    })
  }

  pub fn address(&self) -> &str {
    &self.addr
  }

  pub fn port(&self) -> u16 {
    self.addr.split(':').next_back().unwrap().parse().unwrap()
  }

  pub fn state(&self) -> FakeDaemonState {
    self.state.lock().unwrap().clone()
  }

  pub fn pushed_sha256(&self, path: &str) -> Option<String> {
    let st = self.state.lock().unwrap();
    st.pushed_files.get(path).map(|d| {
      let mut h = Sha256::new();
      h.update(d);
      hex_encode(&h.finalize())
    })
  }
}

impl Drop for FakeDaemon {
  fn drop(&mut self) {
    *self.stop.lock().unwrap() = true;
    // Wake accept via connect attempt.
    let _ = TcpStream::connect(&self.addr);
    if let Some(j) = self.join.take() {
      let _ = j.join();
    }
  }
}

fn handle_client(mut stream: TcpStream, state: Arc<Mutex<FakeDaemonState>>) -> std::io::Result<()> {
  // Listener is nonblocking for the accept loop; accepted sockets must be blocking.
  stream.set_nonblocking(false)?;
  stream.set_read_timeout(Some(Duration::from_secs(5)))?;
  stream.set_write_timeout(Some(Duration::from_secs(5)))?;
  stream.set_nodelay(true)?;
  {
    let mut st = state.lock().unwrap();
    st.connections += 1;
  }

  // Expect CNXN
  let msg = read_msg(&mut stream)?;
  if msg.header.command != CMD_CNXN {
    return Ok(());
  }

  // Challenge with AUTH token (already-authorized devices still get token then signature).
  let token = b"FAKE_TOKEN_20_BYTES!".to_vec(); // 20 bytes
  debug_assert_eq!(token.len(), 20);
  write_all(&mut stream, &adb::generate_auth(AUTH_TYPE_TOKEN, &token))?;

  let auth = read_msg(&mut stream)?;
  if auth.header.command != CMD_AUTH || auth.header.arg0 != AUTH_TYPE_SIGNATURE {
    return Ok(());
  }
  let expected = DeterministicTestSigner::expected_signature(&token);
  if auth.payload != expected {
    // Second chance: ask for public key then fail unless TEST-PUB.
    write_all(&mut stream, &adb::generate_auth(AUTH_TYPE_TOKEN, &token))?;
    let again = read_msg(&mut stream)?;
    if again.header.command == CMD_AUTH && again.header.arg0 == AUTH_TYPE_RSA_PUBLIC {
      if !again.payload.starts_with(b"TEST-PUB:") {
        return Ok(());
      }
    } else {
      return Ok(());
    }
  }

  write_all(
    &mut stream,
    &adb::encode_message(
      CMD_CNXN,
      CONNECT_VERSION,
      CONNECT_MAXDATA,
      Some(b"device::\0"),
    ),
  )?;

  // Stream table: remote_id -> (local_id from client perspective is peer)
  // On device: OPEN arg0 = client local_id; we assign remote_id.
  let mut next_remote: u32 = 10;
  let mut streams: HashMap<u32, StreamSlot> = HashMap::new(); // key = client local_id

  loop {
    let msg = match read_msg(&mut stream) {
      Ok(m) => m,
      Err(_) => break,
    };
    match msg.header.command {
      CMD_OPEN => {
        let client_local = msg.header.arg0;
        let dest = strip_nul(&msg.payload);
        let remote_id = next_remote;
        next_remote += 1;
        write_all(&mut stream, &adb::generate_okay(remote_id, client_local))?;
        let mut slot = StreamSlot {
          remote_id,
          kind: classify_dest(&dest),
          buf: Vec::new(),
          closed: false,
        };
        // Shell with command: respond and close.
        if let StreamKind::Shell(cmd) = &slot.kind {
          state.lock().unwrap().last_shell_cmd = Some(cmd.clone());
          let output = shell_output(cmd);
          if !output.is_empty() {
            write_all(
              &mut stream,
              &adb::generate_write(remote_id, client_local, &output),
            )?;
            // Client OKAY may arrive later; do not serialize on it here.
          }
          write_all(&mut stream, &adb::generate_close(remote_id, client_local))?;
          slot.closed = true;
        }
        streams.insert(client_local, slot);
      }
      CMD_WRTE => {
        let client_local = msg.header.arg0;
        let remote_id = msg.header.arg1;
        // OKAY credit first
        write_all(&mut stream, &adb::generate_okay(remote_id, client_local))?;
        if let Some(slot) = streams.get_mut(&client_local) {
          match &slot.kind {
            StreamKind::Sync => {
              slot.buf.extend_from_slice(&msg.payload);
              if let Some((path, data)) = try_complete_sync(&slot.buf) {
                state.lock().unwrap().pushed_files.insert(path, data);
                write_all(&mut stream, &adb::generate_close(remote_id, client_local))?;
                slot.closed = true;
              }
            }
            StreamKind::TcpEcho => {
              // Echo payload back. Do not block for client OKAY — credits may
              // arrive interleaved with the next WRTE (flow-control tests).
              let payload = msg.payload.clone();
              write_all(
                &mut stream,
                &adb::generate_write(remote_id, client_local, &payload),
              )?;
            }
            StreamKind::Shell(_) | StreamKind::Other => {
              slot.buf.extend_from_slice(&msg.payload);
            }
          }
        }
      }
      CMD_OKAY => {
        // credit from client after our WRTE — ignore
      }
      CMD_CLSE => {
        let client_local = msg.header.arg0;
        if let Some(slot) = streams.get_mut(&client_local) {
          slot.closed = true;
          let _ = write_all(
            &mut stream,
            &adb::generate_close(slot.remote_id, client_local),
          );
        }
      }
      _ => break,
    }
  }
  Ok(())
}

struct StreamSlot {
  remote_id: u32,
  kind: StreamKind,
  buf: Vec<u8>,
  closed: bool,
}

#[derive(Clone)]
enum StreamKind {
  Shell(String),
  Sync,
  TcpEcho,
  Other,
}

fn classify_dest(dest: &str) -> StreamKind {
  if let Some(cmd) = dest.strip_prefix("shell:") {
    StreamKind::Shell(cmd.to_string())
  } else if dest == "sync:" || dest.starts_with("sync:") {
    StreamKind::Sync
  } else if dest.starts_with("tcp:") {
    StreamKind::TcpEcho
  } else {
    StreamKind::Other
  }
}

fn shell_output(cmd: &str) -> Vec<u8> {
  // Support `echo …` used by Gate C.
  if let Some(rest) = cmd.strip_prefix("echo ") {
    let mut out = rest.as_bytes().to_vec();
    if !out.ends_with(&[b'\n']) {
      out.push(b'\n');
    }
    return out;
  }
  format!("ok:{cmd}\n").into_bytes()
}

fn try_complete_sync(buf: &[u8]) -> Option<(String, Vec<u8>)> {
  let mut i = 0usize;
  if buf.len() < 8 {
    return None;
  }
  let send = sync::SyncHeader::decode(&buf[i..]).ok()?;
  if &send.id != ID_SEND {
    return None;
  }
  i += 8;
  let send_end = i + send.arg as usize;
  if buf.len() < send_end {
    return None;
  }
  let send_body = std::str::from_utf8(&buf[i..send_end]).ok()?;
  let path = send_body.split(',').next()?.to_string();
  let mode: u32 = send_body.split(',').nth(1)?.parse().ok()?;
  if mode != PUSH_FILE_MODE {
    return None;
  }
  i = send_end;
  let mut data = Vec::new();
  loop {
    if buf.len() < i + 8 {
      return None;
    }
    let hdr = sync::SyncHeader::decode(&buf[i..]).ok()?;
    i += 8;
    if &hdr.id == ID_DATA {
      let end = i + hdr.arg as usize;
      if buf.len() < end {
        return None;
      }
      data.extend_from_slice(&buf[i..end]);
      i = end;
    } else if &hdr.id == ID_DONE {
      if hdr.arg != PUSH_DONE_MTIME {
        return None;
      }
      break;
    } else {
      return None;
    }
  }
  if buf.len() < i + 8 {
    return None;
  }
  let quit = sync::SyncHeader::decode(&buf[i..]).ok()?;
  if &quit.id != ID_QUIT {
    return None;
  }
  Some((path, data))
}

fn read_msg(stream: &mut TcpStream) -> std::io::Result<AdbMessage> {
  let mut header = [0u8; ADB_HEADER_LENGTH];
  stream.read_exact(&mut header)?;
  let hdr = adb::AdbHeader::decode(&header).map_err(to_io)?;
  hdr.validate_magic().map_err(to_io)?;
  let mut payload = vec![0u8; hdr.data_length as usize];
  if !payload.is_empty() {
    stream.read_exact(&mut payload)?;
  }
  let mut full = Vec::with_capacity(ADB_HEADER_LENGTH + payload.len());
  full.extend_from_slice(&header);
  full.extend_from_slice(&payload);
  adb::decode_message(&full, true).map_err(to_io)
}

fn write_all(stream: &mut TcpStream, buf: &[u8]) -> std::io::Result<()> {
  stream.write_all(buf)?;
  stream.flush()
}

fn strip_nul(bytes: &[u8]) -> String {
  let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
  String::from_utf8_lossy(&bytes[..end]).into_owned()
}

fn to_io(e: impl std::fmt::Display) -> std::io::Error {
  std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())
}

fn hex_encode(bytes: &[u8]) -> String {
  const HEX: &[u8; 16] = b"0123456789abcdef";
  let mut s = String::with_capacity(bytes.len() * 2);
  for b in bytes {
    s.push(HEX[(b >> 4) as usize] as char);
    s.push(HEX[(b & 0xf) as usize] as char);
  }
  s
}
