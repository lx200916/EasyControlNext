//! ADB binary protocol (24-byte little-endian headers).
//!
//! Golden reference:
//! - `easycontrolnext/app/.../adb/AdbProtocol.java`
//! - `easycontrolnext/app/.../io/github/muntashirakon/adb/AdbProtocol.java`

use crate::error::{ProtocolError, ProtocolResult};

pub const ADB_HEADER_LENGTH: usize = 24;

pub const CMD_SYNC: u32 = 0x434e_5953;
pub const CMD_CNXN: u32 = 0x4e58_4e43;
pub const CMD_AUTH: u32 = 0x4854_5541;
pub const CMD_OPEN: u32 = 0x4e45_504f;
pub const CMD_OKAY: u32 = 0x5941_4b4f;
pub const CMD_CLSE: u32 = 0x4553_4c43;
pub const CMD_WRTE: u32 = 0x4554_5257;
pub const CMD_STLS: u32 = 0x534c_5453;

pub const AUTH_TYPE_TOKEN: u32 = 1;
pub const AUTH_TYPE_SIGNATURE: u32 = 2;
pub const AUTH_TYPE_RSA_PUBLIC: u32 = 3;

pub const CONNECT_VERSION: u32 = 0x0100_0000;
pub const CONNECT_VERSION_SKIP_CHECKSUM: u32 = 0x0100_0001;
/// Matches EasyControl Android client (`15 * 1024`) for USB-safe maxdata.
pub const CONNECT_MAXDATA: u32 = 15 * 1024;
pub const MAX_PAYLOAD_V1: u32 = 4 * 1024;
pub const MAX_PAYLOAD_V2: u32 = 256 * 1024;
pub const MAX_PAYLOAD_V3: u32 = 1024 * 1024;
pub const STLS_VERSION: u32 = 0x0100_0000;

pub const CONNECT_PAYLOAD: &[u8] = b"host::\0";

/// Absolute hard cap when parsing untrusted lengths (defense in depth).
pub const ABSOLUTE_MAX_PAYLOAD: usize = MAX_PAYLOAD_V3 as usize;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdbHeader {
  pub command: u32,
  pub arg0: u32,
  pub arg1: u32,
  pub data_length: u32,
  pub data_check: u32,
  pub magic: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdbMessage {
  pub header: AdbHeader,
  pub payload: Vec<u8>,
}

impl AdbHeader {
  pub fn encode(&self) -> [u8; ADB_HEADER_LENGTH] {
    let mut out = [0u8; ADB_HEADER_LENGTH];
    out[0..4].copy_from_slice(&self.command.to_le_bytes());
    out[4..8].copy_from_slice(&self.arg0.to_le_bytes());
    out[8..12].copy_from_slice(&self.arg1.to_le_bytes());
    out[12..16].copy_from_slice(&self.data_length.to_le_bytes());
    out[16..20].copy_from_slice(&self.data_check.to_le_bytes());
    out[20..24].copy_from_slice(&self.magic.to_le_bytes());
    out
  }

  pub fn decode(buf: &[u8]) -> ProtocolResult<Self> {
    if buf.len() < ADB_HEADER_LENGTH {
      return Err(ProtocolError::BufferTooShort {
        need: ADB_HEADER_LENGTH,
        got: buf.len(),
      });
    }
    Ok(Self {
      command: u32::from_le_bytes(buf[0..4].try_into().unwrap()),
      arg0: u32::from_le_bytes(buf[4..8].try_into().unwrap()),
      arg1: u32::from_le_bytes(buf[8..12].try_into().unwrap()),
      data_length: u32::from_le_bytes(buf[12..16].try_into().unwrap()),
      data_check: u32::from_le_bytes(buf[16..20].try_into().unwrap()),
      magic: u32::from_le_bytes(buf[20..24].try_into().unwrap()),
    })
  }

  pub fn validate_magic(&self) -> ProtocolResult<()> {
    if self.magic != !self.command {
      return Err(ProtocolError::InvalidMagic {
        command: self.command,
        magic: self.magic,
      });
    }
    Ok(())
  }
}

#[inline]
pub fn payload_checksum(payload: &[u8]) -> u32 {
  let mut sum: u32 = 0;
  for b in payload {
    sum = sum.wrapping_add(u32::from(*b));
  }
  sum
}

pub fn encode_message(command: u32, arg0: u32, arg1: u32, payload: Option<&[u8]>) -> Vec<u8> {
  let (data_length, data_check, payload_bytes) = match payload {
    Some(p) => (p.len() as u32, payload_checksum(p), p),
    None => (0, 0, &[][..]),
  };
  let header = AdbHeader {
    command,
    arg0,
    arg1,
    data_length,
    data_check,
    magic: !command,
  };
  let mut out = Vec::with_capacity(ADB_HEADER_LENGTH + payload_bytes.len());
  out.extend_from_slice(&header.encode());
  out.extend_from_slice(payload_bytes);
  out
}

pub fn decode_message(buf: &[u8], verify_checksum: bool) -> ProtocolResult<AdbMessage> {
  let header = AdbHeader::decode(buf)?;
  header.validate_magic()?;
  let len = header.data_length as usize;
  if len > ABSOLUTE_MAX_PAYLOAD {
    return Err(ProtocolError::PayloadTooLarge {
      length: len,
      max: ABSOLUTE_MAX_PAYLOAD,
    });
  }
  let need = ADB_HEADER_LENGTH + len;
  if buf.len() < need {
    return Err(ProtocolError::BufferTooShort {
      need,
      got: buf.len(),
    });
  }
  let payload = buf[ADB_HEADER_LENGTH..need].to_vec();
  if verify_checksum && len > 0 {
    let actual = payload_checksum(&payload);
    if actual != header.data_check {
      return Err(ProtocolError::ChecksumMismatch {
        expected: header.data_check,
        actual,
      });
    }
  }
  Ok(AdbMessage { header, payload })
}

pub fn generate_connect() -> Vec<u8> {
  encode_message(CMD_CNXN, CONNECT_VERSION, CONNECT_MAXDATA, Some(CONNECT_PAYLOAD))
}

pub fn generate_connect_for_api(api: u32) -> Vec<u8> {
  let (version, maxdata) = if api >= 28 {
    (CONNECT_VERSION_SKIP_CHECKSUM, MAX_PAYLOAD_V3)
  } else if api >= 24 {
    (CONNECT_VERSION, MAX_PAYLOAD_V2)
  } else {
    (CONNECT_VERSION, MAX_PAYLOAD_V1)
  };
  encode_message(CMD_CNXN, version, maxdata, Some(CONNECT_PAYLOAD))
}

pub fn generate_auth(auth_type: u32, data: &[u8]) -> Vec<u8> {
  encode_message(CMD_AUTH, auth_type, 0, Some(data))
}

pub fn generate_stls() -> Vec<u8> {
  encode_message(CMD_STLS, STLS_VERSION, 0, None)
}

pub fn generate_open(local_id: u32, dest: &str) -> Vec<u8> {
  let mut payload = Vec::with_capacity(dest.len() + 1);
  payload.extend_from_slice(dest.as_bytes());
  payload.push(0);
  encode_message(CMD_OPEN, local_id, 0, Some(&payload))
}

pub fn generate_write(local_id: u32, remote_id: u32, data: &[u8]) -> Vec<u8> {
  encode_message(CMD_WRTE, local_id, remote_id, Some(data))
}

pub fn generate_close(local_id: u32, remote_id: u32) -> Vec<u8> {
  encode_message(CMD_CLSE, local_id, remote_id, None)
}

pub fn generate_okay(local_id: u32, remote_id: u32) -> Vec<u8> {
  encode_message(CMD_OKAY, local_id, remote_id, None)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn connect_payload_checksum_matches_java() {
    // 'h'+'o'+'s'+'t'+':'+':'+0 = 104+111+115+116+58+58+0
    assert_eq!(payload_checksum(CONNECT_PAYLOAD), 562);
  }

  #[test]
  fn generate_connect_golden_bytes() {
    let msg = generate_connect();
    assert_eq!(msg.len(), ADB_HEADER_LENGTH + CONNECT_PAYLOAD.len());
    // command CNXN LE
    assert_eq!(&msg[0..4], &[0x43, 0x4e, 0x58, 0x4e]);
    // version 0x01000000 LE
    assert_eq!(&msg[4..8], &[0x00, 0x00, 0x00, 0x01]);
    // maxdata 15360 LE = 0x3c00
    assert_eq!(&msg[8..12], &[0x00, 0x3c, 0x00, 0x00]);
    // length 7
    assert_eq!(&msg[12..16], &[0x07, 0x00, 0x00, 0x00]);
    // checksum 562 = 0x0232
    assert_eq!(&msg[16..20], &[0x32, 0x02, 0x00, 0x00]);
    // magic = !CNXN
    let magic = !CMD_CNXN;
    assert_eq!(&msg[20..24], &magic.to_le_bytes());
    assert_eq!(&msg[24..], CONNECT_PAYLOAD);

    let decoded = decode_message(&msg, true).unwrap();
    assert_eq!(decoded.header.command, CMD_CNXN);
    assert_eq!(decoded.payload, CONNECT_PAYLOAD);
  }

  #[test]
  fn okay_has_zero_payload_fields() {
    let msg = generate_okay(1, 2);
    assert_eq!(msg.len(), ADB_HEADER_LENGTH);
    let decoded = decode_message(&msg, true).unwrap();
    assert_eq!(decoded.header.command, CMD_OKAY);
    assert_eq!(decoded.header.arg0, 1);
    assert_eq!(decoded.header.arg1, 2);
    assert_eq!(decoded.header.data_length, 0);
    assert_eq!(decoded.header.data_check, 0);
    assert!(decoded.payload.is_empty());
  }

  #[test]
  fn open_includes_nul_terminator() {
    let msg = generate_open(7, "shell:echo hi");
    let decoded = decode_message(&msg, true).unwrap();
    assert_eq!(decoded.header.command, CMD_OPEN);
    assert_eq!(decoded.header.arg0, 7);
    assert_eq!(decoded.payload.last().copied(), Some(0));
    assert_eq!(&decoded.payload[..decoded.payload.len() - 1], b"shell:echo hi");
  }

  #[test]
  fn auth_and_stls_commands() {
    let token = [1u8, 2, 3, 4];
    let auth = generate_auth(AUTH_TYPE_TOKEN, &token);
    let d = decode_message(&auth, true).unwrap();
    assert_eq!(d.header.command, CMD_AUTH);
    assert_eq!(d.header.arg0, AUTH_TYPE_TOKEN);
    assert_eq!(d.payload, token);

    let stls = generate_stls();
    let s = decode_message(&stls, true).unwrap();
    assert_eq!(s.header.command, CMD_STLS);
    assert_eq!(s.header.arg0, STLS_VERSION);
  }

  #[test]
  fn rejects_bad_magic() {
    let mut msg = generate_okay(1, 1);
    msg[20] ^= 0xff;
    assert!(matches!(
      decode_message(&msg, true),
      Err(ProtocolError::InvalidMagic { .. })
    ));
  }

  #[test]
  fn rejects_bad_checksum() {
    let mut msg = generate_write(1, 2, b"abc");
    // flip checksum byte
    msg[16] ^= 0xff;
    assert!(matches!(
      decode_message(&msg, true),
      Err(ProtocolError::ChecksumMismatch { .. })
    ));
  }

  #[test]
  fn rejects_truncated_and_oversize() {
    assert!(matches!(
      decode_message(&[0u8; 8], true),
      Err(ProtocolError::BufferTooShort { .. })
    ));
    let mut hdr = AdbHeader {
      command: CMD_WRTE,
      arg0: 1,
      arg1: 2,
      data_length: (ABSOLUTE_MAX_PAYLOAD as u32) + 1,
      data_check: 0,
      magic: !CMD_WRTE,
    };
    let buf = hdr.encode();
    assert!(matches!(
      decode_message(&buf, true),
      Err(ProtocolError::PayloadTooLarge { .. })
    ));
    // claim length but omit payload
    hdr.data_length = 4;
    hdr.data_check = payload_checksum(&[1, 2, 3, 4]);
    let short = hdr.encode();
    assert!(matches!(
      decode_message(&short, true),
      Err(ProtocolError::BufferTooShort { need: 28, .. })
    ));
  }

  #[test]
  fn write_round_trip() {
    let payload = b"EASYCONTROL_TEST";
    let msg = generate_write(9, 11, payload);
    let d = decode_message(&msg, true).unwrap();
    assert_eq!(d.header.command, CMD_WRTE);
    assert_eq!(d.payload, payload);
  }

  #[test]
  fn skip_checksum_mode_still_checks_magic() {
    let mut msg = generate_write(1, 2, b"x");
    msg[16] ^= 0x01; // corrupt checksum
    assert!(decode_message(&msg, false).is_ok());
    msg[20] ^= 0x01;
    assert!(decode_message(&msg, false).is_err());
  }

  #[test]
  fn connect_for_api_payload_sizes() {
    let p = generate_connect_for_api(28);
    let d = decode_message(&p, true).unwrap();
    assert_eq!(d.header.arg0, CONNECT_VERSION_SKIP_CHECKSUM);
    assert_eq!(d.header.arg1, MAX_PAYLOAD_V3);
    let n = generate_connect_for_api(24);
    let dn = decode_message(&n, true).unwrap();
    assert_eq!(dn.header.arg1, MAX_PAYLOAD_V2);
  }
}
