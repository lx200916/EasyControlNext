//! ADB sync protocol 8-byte little-endian framing (SEND/DATA/DONE/QUIT/...).
//!
//! Layout: 4 ASCII id bytes + u32 LE argument.
//! Reference: `AdbProtocol.generateSyncHeader` in EasyControl Android client.

use crate::error::{ProtocolError, ProtocolResult};

pub const SYNC_HEADER_LENGTH: usize = 8;

pub const ID_SEND: &[u8; 4] = b"SEND";
pub const ID_DATA: &[u8; 4] = b"DATA";
pub const ID_DONE: &[u8; 4] = b"DONE";
pub const ID_QUIT: &[u8; 4] = b"QUIT";
pub const ID_STAT: &[u8; 4] = b"STAT";
pub const ID_RECV: &[u8; 4] = b"RECV";
pub const ID_LIST: &[u8; 4] = b"LIST";
pub const ID_OKAY: &[u8; 4] = b"OKAY";
pub const ID_FAIL: &[u8; 4] = b"FAIL";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncHeader {
  pub id: [u8; 4],
  pub arg: u32,
}

impl SyncHeader {
  pub fn new(id: &[u8; 4], arg: u32) -> Self {
    Self { id: *id, arg }
  }

  pub fn encode(&self) -> [u8; SYNC_HEADER_LENGTH] {
    let mut out = [0u8; SYNC_HEADER_LENGTH];
    out[0..4].copy_from_slice(&self.id);
    out[4..8].copy_from_slice(&self.arg.to_le_bytes());
    out
  }

  pub fn decode(buf: &[u8]) -> ProtocolResult<Self> {
    if buf.len() < SYNC_HEADER_LENGTH {
      return Err(ProtocolError::BufferTooShort {
        need: SYNC_HEADER_LENGTH,
        got: buf.len(),
      });
    }
    let mut id = [0u8; 4];
    id.copy_from_slice(&buf[0..4]);
    Ok(Self {
      id,
      arg: u32::from_le_bytes(buf[4..8].try_into().unwrap()),
    })
  }
}

pub fn generate_sync_header(id: &str, arg: u32) -> ProtocolResult<[u8; SYNC_HEADER_LENGTH]> {
  let bytes = id.as_bytes();
  if bytes.len() != 4 {
    return Err(ProtocolError::InvalidSyncId);
  }
  let mut id_arr = [0u8; 4];
  id_arr.copy_from_slice(bytes);
  Ok(SyncHeader::new(&id_arr, arg).encode())
}

/// Build SEND request path payload: `remote_path,mode` as used by adb sync.
pub fn encode_send_path(remote_path: &str, mode: u32) -> Vec<u8> {
  format!("{remote_path},{mode}").into_bytes()
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn send_header_golden() {
    let hdr = generate_sync_header("SEND", 12).unwrap();
    assert_eq!(&hdr[0..4], b"SEND");
    assert_eq!(&hdr[4..8], &12u32.to_le_bytes());
    let decoded = SyncHeader::decode(&hdr).unwrap();
    assert_eq!(&decoded.id, ID_SEND);
    assert_eq!(decoded.arg, 12);
  }

  #[test]
  fn data_done_quit_round_trip() {
    for (id, arg) in [("DATA", 65536u32), ("DONE", 1_700_000_000), ("QUIT", 0)] {
      let enc = generate_sync_header(id, arg).unwrap();
      let dec = SyncHeader::decode(&enc).unwrap();
      assert_eq!(std::str::from_utf8(&dec.id).unwrap(), id);
      assert_eq!(dec.arg, arg);
    }
  }

  #[test]
  fn rejects_bad_id_length_and_short_buffer() {
    assert_eq!(generate_sync_header("SE", 0), Err(ProtocolError::InvalidSyncId));
    assert_eq!(generate_sync_header("SENDX", 0), Err(ProtocolError::InvalidSyncId));
    assert!(matches!(
      SyncHeader::decode(&[0u8; 3]),
      Err(ProtocolError::BufferTooShort { .. })
    ));
  }

  #[test]
  fn send_path_encoding() {
    let p = encode_send_path("/data/local/tmp/x.jar", 0o644);
    assert_eq!(p, b"/data/local/tmp/x.jar,420");
  }
}
