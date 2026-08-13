//! Pairing packet framing (big-endian headers) — AOSP / muntashirakon.

use super::{PairingError, PairingResult};

/// Conscrypt / AOSP TLS exporter label including trailing NUL.
pub const EXPORTED_KEY_LABEL: &str = "adb-label\0";
pub const EXPORT_KEY_SIZE: usize = 64;

pub const HEADER_VERSION: u8 = 1;
pub const HEADER_SIZE: usize = 6;
pub const MAX_PEER_INFO_SIZE: usize = 1 << 13;
pub const MAX_PAYLOAD_SIZE: usize = 2 * MAX_PEER_INFO_SIZE;

pub const TYPE_SPAKE2_MSG: u8 = 0;
pub const TYPE_PEER_INFO: u8 = 1;

#[derive(Clone, Copy, Debug)]
pub struct PairingPacketHeader {
  pub version: u8,
  pub typ: u8,
  pub payload_size: u32,
}

impl PairingPacketHeader {
  pub fn new(typ: u8, payload_size: usize) -> Self {
    Self {
      version: HEADER_VERSION,
      typ,
      payload_size: payload_size as u32,
    }
  }

  pub fn write_to(&self, out: &mut [u8; HEADER_SIZE]) {
    out[0] = self.version;
    out[1] = self.typ;
    out[2..6].copy_from_slice(&self.payload_size.to_be_bytes());
  }

  pub fn read_from(buf: &[u8]) -> PairingResult<Self> {
    if buf.len() < HEADER_SIZE {
      return Err(PairingError::Protocol("pairing header truncated".into()));
    }
    let version = buf[0];
    let typ = buf[1];
    let payload_size = u32::from_be_bytes([buf[2], buf[3], buf[4], buf[5]]);
    if version != HEADER_VERSION {
      return Err(PairingError::Protocol(format!(
        "pairing header version mismatch: {version}"
      )));
    }
    if typ != TYPE_SPAKE2_MSG && typ != TYPE_PEER_INFO {
      return Err(PairingError::Protocol(format!("unknown pairing type {typ}")));
    }
    if payload_size == 0 || payload_size as usize > MAX_PAYLOAD_SIZE {
      return Err(PairingError::Protocol(format!(
        "unsafe pairing payload size {payload_size}"
      )));
    }
    Ok(Self {
      version,
      typ,
      payload_size,
    })
  }
}

/// PeerInfo: 1 byte type + (MAX_PEER_INFO_SIZE-1) data, big-endian layout in buffer.
pub const PEER_INFO_TYPE_ADB_RSA_PUB_KEY: u8 = 0;

pub fn encode_peer_info(pubkey_payload: &[u8]) -> Vec<u8> {
  let mut buf = vec![0u8; MAX_PEER_INFO_SIZE];
  buf[0] = PEER_INFO_TYPE_ADB_RSA_PUB_KEY;
  let n = pubkey_payload.len().min(MAX_PEER_INFO_SIZE - 1);
  buf[1..1 + n].copy_from_slice(&pubkey_payload[..n]);
  buf
}
