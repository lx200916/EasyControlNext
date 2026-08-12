//! ADB sync pull (RECV/DATA/DONE/FAIL/QUIT) matching AOSP `sync:` service.

use easycontrol_protocol::sync::{
  self, generate_sync_header, ID_DATA, ID_DONE, ID_FAIL, ID_QUIT, ID_RECV, SYNC_HEADER_LENGTH,
};

use crate::error::{AdbError, AdbResult};
use crate::sync_push::{sha256_hex, PUSH_DATA_CHUNK};

/// Hard cap for a single pulled file (controller sandbox).
pub const MAX_PULL_BYTES: usize = 32 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncPullResult {
  pub data: Vec<u8>,
  pub sha256_hex: String,
  pub remote_path: String,
  pub mtime: u32,
}

/// Build the client → daemon RECV request (path only; no trailing NUL).
pub fn build_recv_request(remote_path: &str) -> AdbResult<Vec<u8>> {
  validate_remote_path(remote_path)?;
  let path_bytes = remote_path.as_bytes();
  let mut bytes = Vec::with_capacity(SYNC_HEADER_LENGTH + path_bytes.len());
  bytes.extend_from_slice(&generate_sync_header("RECV", path_bytes.len() as u32)?);
  bytes.extend_from_slice(path_bytes);
  Ok(bytes)
}

/// Build QUIT trailer (sent after DONE/FAIL).
pub fn build_quit() -> AdbResult<[u8; SYNC_HEADER_LENGTH]> {
  Ok(generate_sync_header("QUIT", 0)?)
}

/// Parse daemon → client sync-pull response buffer into file bytes.
/// Accepts a complete response ending at DONE or FAIL (QUIT optional / ignored).
pub fn parse_pull_response(payload: &[u8], remote_path: &str) -> AdbResult<SyncPullResult> {
  let mut i = 0usize;
  let mut file = Vec::new();
  let mtime: u32;

  loop {
    if payload.len() < i + SYNC_HEADER_LENGTH {
      return Err(AdbError::Protocol(
        easycontrol_protocol::ProtocolError::BufferTooShort {
          need: i + SYNC_HEADER_LENGTH,
          got: payload.len(),
        },
      ));
    }
    let hdr = sync::SyncHeader::decode(&payload[i..])?;
    i += SYNC_HEADER_LENGTH;

    if &hdr.id == ID_DATA {
      let end = i + hdr.arg as usize;
      if payload.len() < end {
        return Err(AdbError::Protocol(
          easycontrol_protocol::ProtocolError::BufferTooShort {
            need: end,
            got: payload.len(),
          },
        ));
      }
      if file.len() + hdr.arg as usize > MAX_PULL_BYTES {
        return Err(AdbError::RemoteFail(format!(
          "pull exceeds {MAX_PULL_BYTES} bytes"
        )));
      }
      file.extend_from_slice(&payload[i..end]);
      i = end;
    } else if &hdr.id == ID_DONE {
      // DONE.arg is mtime — no body follows.
      mtime = hdr.arg;
      break;
    } else if &hdr.id == ID_FAIL {
      let end = i + hdr.arg as usize;
      if payload.len() < end {
        return Err(AdbError::Protocol(
          easycontrol_protocol::ProtocolError::BufferTooShort {
            need: end,
            got: payload.len(),
          },
        ));
      }
      let msg = String::from_utf8_lossy(&payload[i..end]).into_owned();
      return Err(AdbError::RemoteFail(format!("sync FAIL: {msg}")));
    } else if &hdr.id == ID_QUIT {
      // Unexpected early QUIT
      return Err(AdbError::RemoteFail("unexpected QUIT before DONE".into()));
    } else {
      return Err(AdbError::RemoteFail(format!(
        "unexpected sync id {:?}",
        String::from_utf8_lossy(&hdr.id)
      )));
    }
  }

  // Optional trailing QUIT from some clients' mirrored dumps — ignore if present.
  if payload.len() >= i + SYNC_HEADER_LENGTH {
    let maybe = sync::SyncHeader::decode(&payload[i..]);
    if let Ok(q) = maybe {
      if &q.id == ID_QUIT {
        i += SYNC_HEADER_LENGTH;
      }
    }
  }
  let _ = i;

  Ok(SyncPullResult {
    sha256_hex: sha256_hex(&file),
    data: file,
    remote_path: remote_path.to_string(),
    mtime,
  })
}

/// Encode a fake-daemon style pull response for `data` (chunked DATA + DONE).
pub fn encode_pull_response(data: &[u8], mtime: u32) -> AdbResult<Vec<u8>> {
  if data.len() > MAX_PULL_BYTES {
    return Err(AdbError::RemoteFail(format!(
      "pull exceeds {MAX_PULL_BYTES} bytes"
    )));
  }
  let mut bytes = Vec::new();
  let mut offset = 0usize;
  while offset < data.len() {
    let end = (offset + PUSH_DATA_CHUNK).min(data.len());
    let chunk = &data[offset..end];
    bytes.extend_from_slice(&generate_sync_header("DATA", chunk.len() as u32)?);
    bytes.extend_from_slice(chunk);
    offset = end;
  }
  // Empty file: still emit DONE with no DATA chunks (AOSP allows this).
  bytes.extend_from_slice(&generate_sync_header("DONE", mtime)?);
  Ok(bytes)
}

pub fn encode_fail_response(message: &str) -> AdbResult<Vec<u8>> {
  let msg = message.as_bytes();
  let mut bytes = Vec::with_capacity(SYNC_HEADER_LENGTH + msg.len());
  bytes.extend_from_slice(&generate_sync_header("FAIL", msg.len() as u32)?);
  bytes.extend_from_slice(msg);
  Ok(bytes)
}

pub fn validate_remote_path(remote_path: &str) -> AdbResult<()> {
  if remote_path.is_empty() || remote_path.len() > 1024 {
    return Err(AdbError::RemoteFail("remote path empty or too long".into()));
  }
  if !remote_path.starts_with('/') {
    return Err(AdbError::RemoteFail("remote path must be absolute".into()));
  }
  if remote_path.contains('\0') || remote_path.contains('\n') || remote_path.contains('\r') {
    return Err(AdbError::RemoteFail("remote path has illegal characters".into()));
  }
  // Reject obvious traversal / shell metachar abuse in the path string itself.
  if remote_path.contains("..") || remote_path.contains('|') || remote_path.contains(';') {
    return Err(AdbError::RemoteFail("remote path rejected".into()));
  }
  Ok(())
}

/// Incremental parser state for streaming WRTE chunks from the daemon.
#[derive(Debug, Default)]
pub struct PullStreamParser {
  buf: Vec<u8>,
  file: Vec<u8>,
  done: bool,
  mtime: u32,
  fail: Option<String>,
}

impl PullStreamParser {
  pub fn new() -> Self {
    Self::default()
  }

  pub fn push(&mut self, chunk: &[u8]) -> AdbResult<()> {
    if self.done || self.fail.is_some() {
      return Ok(());
    }
    self.buf.extend_from_slice(chunk);
    loop {
      if self.buf.len() < SYNC_HEADER_LENGTH {
        return Ok(());
      }
      let hdr = sync::SyncHeader::decode(&self.buf)?;
      // DONE/QUIT: arg is metadata (mtime/0), not a following body length.
      let body_len = if &hdr.id == ID_DONE || &hdr.id == ID_QUIT {
        0usize
      } else {
        hdr.arg as usize
      };
      let need = SYNC_HEADER_LENGTH + body_len;
      if self.buf.len() < need {
        return Ok(());
      }
      let body = self.buf[SYNC_HEADER_LENGTH..need].to_vec();
      self.buf.drain(..need);

      if &hdr.id == ID_DATA {
        if self.file.len() + body.len() > MAX_PULL_BYTES {
          return Err(AdbError::RemoteFail(format!(
            "pull exceeds {MAX_PULL_BYTES} bytes"
          )));
        }
        self.file.extend_from_slice(&body);
      } else if &hdr.id == ID_DONE {
        self.mtime = hdr.arg;
        self.done = true;
        return Ok(());
      } else if &hdr.id == ID_FAIL {
        self.fail = Some(String::from_utf8_lossy(&body).into_owned());
        return Ok(());
      } else if &hdr.id == ID_RECV {
        return Err(AdbError::RemoteFail("unexpected RECV from daemon".into()));
      } else {
        return Err(AdbError::RemoteFail(format!(
          "unexpected sync id {:?}",
          String::from_utf8_lossy(&hdr.id)
        )));
      }
    }
  }

  pub fn is_finished(&self) -> bool {
    self.done || self.fail.is_some()
  }

  pub fn finish(self, remote_path: &str) -> AdbResult<SyncPullResult> {
    if let Some(msg) = self.fail {
      return Err(AdbError::RemoteFail(format!("sync FAIL: {msg}")));
    }
    if !self.done {
      return Err(AdbError::RemoteFail("sync pull incomplete (no DONE)".into()));
    }
    Ok(SyncPullResult {
      sha256_hex: sha256_hex(&self.file),
      data: self.file,
      remote_path: remote_path.to_string(),
      mtime: self.mtime,
    })
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn recv_request_and_round_trip() {
    let path = "/data/local/tmp/a.bin";
    let req = build_recv_request(path).unwrap();
    assert_eq!(&req[0..4], ID_RECV);
    let hdr = sync::SyncHeader::decode(&req).unwrap();
    assert_eq!(hdr.arg as usize, path.len());
    assert_eq!(&req[8..], path.as_bytes());

    let payload = b"hello-pull";
    let resp = encode_pull_response(payload, 1_704_038_400).unwrap();
    let parsed = parse_pull_response(&resp, path).unwrap();
    assert_eq!(parsed.data, payload);
    assert_eq!(parsed.mtime, 1_704_038_400);
  }

  #[test]
  fn fail_response() {
    let resp = encode_fail_response("No such file").unwrap();
    let err = parse_pull_response(&resp, "/missing").unwrap_err();
    assert!(matches!(err, AdbError::RemoteFail(_)));
  }

  #[test]
  fn stream_parser_chunked() {
    let data = vec![0xABu8; PUSH_DATA_CHUNK + 3];
    let resp = encode_pull_response(&data, 42).unwrap();
    let mut p = PullStreamParser::new();
    // Feed one byte at a time to stress framing.
    for b in &resp {
      p.push(&[*b]).unwrap();
    }
    assert!(p.is_finished());
    let out = p.finish("/x").unwrap();
    assert_eq!(out.data, data);
    assert_eq!(out.mtime, 42);
  }

  #[test]
  fn rejects_bad_path() {
    assert!(build_recv_request("relative").is_err());
    assert!(build_recv_request("/tmp/../etc/passwd").is_err());
    assert!(build_recv_request("").is_err());
  }
}
