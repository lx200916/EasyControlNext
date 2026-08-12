//! Dual main+video socket bring-up (direct TCP preferred, ADB `tcp:<port>` fallback).
//! Shared by host `gate_d` and on-device live session.

use std::io::Read;
use std::net::TcpStream;
use std::thread;
use std::time::{Duration, Instant};

use crate::error::{AdbError, AdbResult};
use crate::session::AdbSession;
use crate::transport::AdbTransport;
use easycontrol_protocol::video::{parse_video_stream_header, VideoStreamHeader};

/// How the client reached the EasyControl server ports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectMode {
  Direct,
  AdbTcp,
}

impl ConnectMode {
  pub fn as_str(self) -> &'static str {
    match self {
      ConnectMode::Direct => "direct",
      ConnectMode::AdbTcp => "adb-tcp",
    }
  }
}

/// Opened main + video channels after server accept.
pub struct DualSockets {
  pub mode: ConnectMode,
  pub main_tcp: Option<TcpStream>,
  pub video_tcp: Option<TcpStream>,
  pub main_adb: Option<u32>,
  pub video_adb: Option<u32>,
}

/// True when shell stderr indicates the server process actually failed (not MIUI noise).
fn shell_output_looks_fatal(text: &str) -> bool {
  let lower = text.to_lowercase();
  lower.contains("error app:")
    || lower.contains("single-app virtual display requires")
    || lower.contains("class not found")
    || lower.contains("could not find class")
    || lower.contains("unable to locate")
    || lower.contains("java.lang.exceptionininitializererror")
    || lower.contains("exception in thread \"main\"")
}

/// Prefer direct TCP to `host:server_port` (main then video); fall back to ADB `tcp:<port>`.
pub fn connect_dual<T: AdbTransport>(
  session: &mut AdbSession<T>,
  host: &str,
  server_port: u16,
  timeout: Duration,
  shell_id: u32,
) -> AdbResult<DualSockets> {
  let start = Instant::now();
  let mut last_err = String::from("not attempted");
  while start.elapsed() < timeout {
    match try_direct(host, server_port) {
      Ok((main, video)) => {
        return Ok(DualSockets {
          mode: ConnectMode::Direct,
          main_tcp: Some(main),
          video_tcp: Some(video),
          main_adb: None,
          video_adb: None,
        });
      }
      Err(e) => last_err = e,
    }
    let _ = session.pump();
    let shell_out = session.read_stream_buf(shell_id).unwrap_or_default();
    if session.is_stream_closed(shell_id) {
      let text = String::from_utf8_lossy(&shell_out);
      return Err(AdbError::Io(std::io::Error::new(
        std::io::ErrorKind::Other,
        format!("server shell closed before accept; shell={text}; last_direct={last_err}"),
      )));
    }
    if !shell_out.is_empty() {
      let text = String::from_utf8_lossy(&shell_out);
      // MIUI dumps a non-fatal FileNotFoundException (theme_compatibility.xml) while
      // FakeContext/createVirtualDisplay runs — do NOT treat generic "exception" as death.
      if shell_output_looks_fatal(&text) {
        return Err(AdbError::Io(std::io::Error::new(
          std::io::ErrorKind::Other,
          format!("server exited before accept; shell={text}; last_direct={last_err}"),
        )));
      }
    }
    // Android ClientStream retries ~every 50ms; avoid 250ms stalls between attempts.
    thread::sleep(Duration::from_millis(50));
  }

  let start2 = Instant::now();
  let mut main_id = None;
  let mut video_id = None;
  while start2.elapsed() < timeout {
    let _ = session.pump();
    let shell_out = session.read_stream_buf(shell_id).unwrap_or_default();
    if !shell_out.is_empty() {
      let text = String::from_utf8_lossy(&shell_out);
      if shell_output_looks_fatal(&text) {
        last_err = format!("server shell error: {text}");
      }
    }
    if main_id.is_none() {
      match session.open_tcp(server_port) {
        Ok(id) => main_id = Some(id),
        Err(e) => last_err = format!("adb tcp main: {e}"),
      }
    }
    if main_id.is_some() && video_id.is_none() {
      match session.open_tcp(server_port) {
        Ok(id) => {
          video_id = Some(id);
          return Ok(DualSockets {
            mode: ConnectMode::AdbTcp,
            main_tcp: None,
            video_tcp: None,
            main_adb: main_id,
            video_adb: video_id,
          });
        }
        Err(e) => last_err = format!("adb tcp video: {e}"),
      }
    }
    thread::sleep(Duration::from_millis(80));
  }

  let shell_dump = session.read_stream_buf(shell_id).unwrap_or_default();
  let shell_text = String::from_utf8_lossy(&shell_dump);
  Err(AdbError::Io(std::io::Error::new(
    std::io::ErrorKind::TimedOut,
    format!(
      "could not open main+video on {host}:{server_port} (direct then adb-tcp). last_err={last_err}; shell={shell_text}"
    ),
  )))
}

pub fn try_direct(host: &str, port: u16) -> Result<(TcpStream, TcpStream), String> {
  let addr: std::net::SocketAddr = format!("{host}:{port}")
    .parse()
    .map_err(|e| format!("addr: {e}"))?;
  let main = TcpStream::connect_timeout(&addr, Duration::from_secs(2))
    .map_err(|e| format!("main connect: {e}"))?;
  main
    .set_read_timeout(Some(Duration::from_secs(10)))
    .map_err(|e| e.to_string())?;
  main
    .set_write_timeout(Some(Duration::from_secs(10)))
    .map_err(|e| e.to_string())?;
  let video = TcpStream::connect_timeout(&addr, Duration::from_secs(2)).map_err(|e| {
    let _ = main.shutdown(std::net::Shutdown::Both);
    format!("video connect: {e}")
  })?;
  video
    .set_read_timeout(Some(Duration::from_secs(10)))
    .map_err(|e| e.to_string())?;
  video
    .set_write_timeout(Some(Duration::from_secs(10)))
    .map_err(|e| e.to_string())?;
  Ok((main, video))
}

pub fn read_video_header_tcp(
  sock: &mut TcpStream,
  timeout: Duration,
) -> Result<VideoStreamHeader, String> {
  let start = Instant::now();
  let mut buf = Vec::new();
  let mut tmp = [0u8; 4096];
  loop {
    if start.elapsed() > timeout {
      return Err(format!(
        "timeout reading video header (got {} bytes)",
        buf.len()
      ));
    }
    match sock.read(&mut tmp) {
      Ok(0) => {
        return Err(format!(
          "video EOF after {} bytes (server died?)",
          buf.len()
        ))
      }
      Ok(n) => {
        buf.extend_from_slice(&tmp[..n]);
        if let Ok((hdr, consumed)) = parse_video_stream_header(&buf) {
          // Keep leftover AU bytes for the caller by seeking via leftover return.
          let _ = consumed;
          return Ok(hdr);
        }
      }
      Err(e)
        if e.kind() == std::io::ErrorKind::WouldBlock
          || e.kind() == std::io::ErrorKind::TimedOut =>
      {
        thread::sleep(Duration::from_millis(50));
      }
      Err(e) => return Err(e.to_string()),
    }
  }
}

/// Read video header and return leftover bytes already received after the header.
pub fn read_video_header_tcp_with_leftover(
  sock: &mut TcpStream,
  timeout: Duration,
) -> Result<(VideoStreamHeader, Vec<u8>), String> {
  let start = Instant::now();
  let mut buf = Vec::new();
  let mut tmp = [0u8; 4096];
  loop {
    if start.elapsed() > timeout {
      return Err(format!(
        "timeout reading video header (got {} bytes)",
        buf.len()
      ));
    }
    match sock.read(&mut tmp) {
      Ok(0) => {
        return Err(format!(
          "video EOF after {} bytes (server died?)",
          buf.len()
        ))
      }
      Ok(n) => {
        buf.extend_from_slice(&tmp[..n]);
        if let Ok((hdr, consumed)) = parse_video_stream_header(&buf) {
          let leftover = buf[consumed..].to_vec();
          return Ok((hdr, leftover));
        }
      }
      Err(e)
        if e.kind() == std::io::ErrorKind::WouldBlock
          || e.kind() == std::io::ErrorKind::TimedOut =>
      {
        thread::sleep(Duration::from_millis(50));
      }
      Err(e) => return Err(e.to_string()),
    }
  }
}

pub fn read_video_header_adb<T: AdbTransport>(
  session: &mut AdbSession<T>,
  id: u32,
  timeout: Duration,
) -> Result<(VideoStreamHeader, Vec<u8>), String> {
  let start = Instant::now();
  let mut buf = Vec::new();
  while start.elapsed() < timeout {
    let chunk = session.read_stream_buf(id).map_err(|e| e.to_string())?;
    buf.extend_from_slice(&chunk);
    if let Ok((hdr, consumed)) = parse_video_stream_header(&buf) {
      return Ok((hdr, buf[consumed..].to_vec()));
    }
    let _ = session.pump();
    thread::sleep(Duration::from_millis(50));
  }
  Err(format!(
    "timeout reading video header via adb-tcp (got {} bytes)",
    buf.len()
  ))
}

pub fn read_exact_timeout(sock: &mut TcpStream, n: usize, timeout: Duration) -> Result<Vec<u8>, String> {
  let start = Instant::now();
  let mut buf = vec![0u8; n];
  let mut off = 0;
  while off < n {
    if start.elapsed() > timeout {
      return Err(format!("timeout reading {n} bytes (got {off})"));
    }
    match sock.read(&mut buf[off..]) {
      Ok(0) => return Err("EOF".into()),
      Ok(k) => off += k,
      Err(e)
        if e.kind() == std::io::ErrorKind::WouldBlock
          || e.kind() == std::io::ErrorKind::TimedOut =>
      {
        thread::sleep(Duration::from_millis(20));
      }
      Err(e) => return Err(e.to_string()),
    }
  }
  Ok(buf)
}

pub fn read_adb_at_least<T: AdbTransport>(
  session: &mut AdbSession<T>,
  id: u32,
  n: usize,
  timeout: Duration,
) -> Result<Vec<u8>, String> {
  let start = Instant::now();
  let mut buf = Vec::new();
  while buf.len() < n && start.elapsed() < timeout {
    let chunk = session.read_stream_buf(id).map_err(|e| e.to_string())?;
    buf.extend_from_slice(&chunk);
    if buf.len() >= n {
      break;
    }
    let _ = session.pump();
    thread::sleep(Duration::from_millis(30));
  }
  if buf.len() < n {
    return Err(format!("adb stream short read need={n} got={}", buf.len()));
  }
  Ok(buf)
}
