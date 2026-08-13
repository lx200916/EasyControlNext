//! ADB sync push framing helpers (SEND/DATA/DONE/QUIT) matching Android `Adb.pushFile`.

use easycontrol_protocol::sync::{self, generate_sync_header, ID_DATA, ID_DONE, ID_QUIT, ID_SEND};
use sha2::{Digest, Sha256};

use crate::error::{AdbError, AdbResult};

/// Matches EasyControl Android client (`remotePath + ",33206"`).
pub const PUSH_FILE_MODE: u32 = 33206;

/// Matches EasyControl Android client DONE mtime (2024-01-01 00:00:00 UTC).
pub const PUSH_DONE_MTIME: u32 = 1_704_038_400;

/// DATA payload chunk size used by Android client (`10240 - 8`).
pub const PUSH_DATA_CHUNK: usize = 10_240 - 8;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncPushPlan {
  /// Complete sync-stream payload (headers + bodies), excluding ADB WRTE wrappers.
  pub bytes: Vec<u8>,
  pub sha256_hex: String,
  pub file_len: usize,
  pub data_chunks: usize,
}

/// Build the sync push byte sequence for `remote_path` and `file_data`.
pub fn build_sync_push(remote_path: &str, file_data: &[u8]) -> AdbResult<SyncPushPlan> {
  let send_body = sync::encode_send_path(remote_path, PUSH_FILE_MODE);
  let mut bytes = Vec::new();
  bytes.extend_from_slice(&generate_sync_header("SEND", send_body.len() as u32)?);
  bytes.extend_from_slice(&send_body);

  let mut data_chunks = 0usize;
  let mut offset = 0usize;
  while offset < file_data.len() {
    let end = (offset + PUSH_DATA_CHUNK).min(file_data.len());
    let chunk = &file_data[offset..end];
    bytes.extend_from_slice(&generate_sync_header("DATA", chunk.len() as u32)?);
    bytes.extend_from_slice(chunk);
    data_chunks += 1;
    offset = end;
  }
  bytes.extend_from_slice(&generate_sync_header("DONE", PUSH_DONE_MTIME)?);
  bytes.extend_from_slice(&generate_sync_header("QUIT", 0)?);

  Ok(SyncPushPlan {
    bytes,
    sha256_hex: sha256_hex(file_data),
    file_len: file_data.len(),
    data_chunks,
  })
}

pub fn sha256_hex(data: &[u8]) -> String {
  let mut hasher = Sha256::new();
  hasher.update(data);
  hex_encode(&hasher.finalize())
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

/// Validate a captured sync push payload against expected path/data (for fixtures).
pub fn parse_and_hash_push(payload: &[u8], expected_path: &str) -> AdbResult<String> {
  let mut i = 0usize;
  if payload.len() < 8 {
    return Err(AdbError::Protocol(
      easycontrol_protocol::ProtocolError::BufferTooShort {
        need: 8,
        got: payload.len(),
      },
    ));
  }
  let send_hdr = sync::SyncHeader::decode(&payload[i..])?;
  if &send_hdr.id != ID_SEND {
    return Err(AdbError::RemoteFail("expected SEND".into()));
  }
  i += 8;
  let send_end = i + send_hdr.arg as usize;
  if payload.len() < send_end {
    return Err(AdbError::Protocol(
      easycontrol_protocol::ProtocolError::BufferTooShort {
        need: send_end,
        got: payload.len(),
      },
    ));
  }
  let send_body = std::str::from_utf8(&payload[i..send_end])
    .map_err(|_| AdbError::Protocol(easycontrol_protocol::ProtocolError::InvalidUtf8))?;
  let expected_prefix = format!("{expected_path},{PUSH_FILE_MODE}");
  if send_body != expected_prefix {
    return Err(AdbError::RemoteFail(format!(
      "SEND path mismatch: {send_body} != {expected_prefix}"
    )));
  }
  i = send_end;

  let mut file = Vec::new();
  loop {
    if payload.len() < i + 8 {
      return Err(AdbError::Protocol(
        easycontrol_protocol::ProtocolError::BufferTooShort {
          need: i + 8,
          got: payload.len(),
        },
      ));
    }
    let hdr = sync::SyncHeader::decode(&payload[i..])?;
    i += 8;
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
      file.extend_from_slice(&payload[i..end]);
      i = end;
    } else if &hdr.id == ID_DONE {
      if hdr.arg != PUSH_DONE_MTIME {
        return Err(AdbError::RemoteFail(format!(
          "DONE mtime mismatch: {} != {PUSH_DONE_MTIME}",
          hdr.arg
        )));
      }
      break;
    } else {
      return Err(AdbError::RemoteFail(format!(
        "unexpected sync id {:?}",
        &hdr.id
      )));
    }
  }
  if payload.len() < i + 8 {
    return Err(AdbError::RemoteFail("missing QUIT".into()));
  }
  let quit = sync::SyncHeader::decode(&payload[i..])?;
  if &quit.id != ID_QUIT {
    return Err(AdbError::RemoteFail("expected QUIT".into()));
  }
  Ok(sha256_hex(&file))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn push_plan_empty_and_chunked() {
    let empty = build_sync_push("/data/local/tmp/x", &[]).unwrap();
    assert_eq!(empty.data_chunks, 0);
    assert_eq!(empty.file_len, 0);
    let hash = parse_and_hash_push(&empty.bytes, "/data/local/tmp/x").unwrap();
    assert_eq!(hash, empty.sha256_hex);

    let big = vec![0xABu8; PUSH_DATA_CHUNK + 10];
    let plan = build_sync_push("/tmp/y", &big).unwrap();
    assert_eq!(plan.data_chunks, 2);
    assert_eq!(
      parse_and_hash_push(&plan.bytes, "/tmp/y").unwrap(),
      plan.sha256_hex
    );
  }
}
