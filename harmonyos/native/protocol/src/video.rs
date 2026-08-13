//! EasyControl video stream framing (big-endian).
//!
//! Wire shape matches Android `ClientPlayer.videoStreamIn` / `ClientStream.readFrameFromVideo`:
//! 1. Header: `useH265:u8` + `width:u32 BE` + `height:u32 BE`
//! 2. Length-prefixed CSD0 (+ CSD1 when AVC)
//! 3. Length-prefixed access units forever
//!
//! Each length-prefixed frame payload is: `pts:i64 BE` + Annex-B (or AVCC) NAL bytes.
//! Android `VideoDecode` skips the first 8 bytes when installing CSD and when queueing
//! input (`data.getLong()` then remainder).

use crate::error::{ProtocolError, ProtocolResult};

/// Hard cap for CSD / early frames (plan security constraint).
pub const MAX_CSD_BYTES: usize = 2 * 1024 * 1024;
/// Hard cap for a single video access unit after the length prefix.
pub const MAX_AU_BYTES: usize = 8 * 1024 * 1024;
/// PTS prefix inside each length-prefixed frame.
pub const PTS_PREFIX_BYTES: usize = 8;

/// Video stream preamble after both sockets are accepted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoStreamHeader {
  pub use_h265: bool,
  pub width: u32,
  pub height: u32,
  /// Raw CSD0 frame including 8-byte PTS prefix (same as wire).
  pub csd0: Vec<u8>,
  /// Raw CSD1 frame including PTS prefix when AVC; `None` for HEVC.
  pub csd1: Option<Vec<u8>>,
}

/// One length-prefixed video access unit after PTS strip.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoAccessUnit {
  pub pts_us: i64,
  /// NAL payload after the 8-byte PTS prefix (typically Annex-B start codes).
  pub payload: Vec<u8>,
}

/// Parse big-endian EasyControl video header + CSD frames from a byte buffer.
pub fn parse_video_stream_header(buf: &[u8]) -> ProtocolResult<(VideoStreamHeader, usize)> {
  if buf.len() < 9 {
    return Err(ProtocolError::BufferTooShort {
      need: 9,
      got: buf.len(),
    });
  }
  let use_h265 = buf[0] != 0;
  let width = u32::from_be_bytes([buf[1], buf[2], buf[3], buf[4]]);
  let height = u32::from_be_bytes([buf[5], buf[6], buf[7], buf[8]]);
  let mut off = 9usize;
  let (csd0, n0) = read_be_length_prefixed(buf, off, MAX_CSD_BYTES)?;
  off += n0;
  let csd1 = if use_h265 {
    None
  } else {
    let (frame, n1) = read_be_length_prefixed(buf, off, MAX_CSD_BYTES)?;
    off += n1;
    Some(frame)
  };
  if width == 0 || height == 0 {
    return Err(ProtocolError::MalformedMessage("video size is zero"));
  }
  if csd0.len() <= PTS_PREFIX_BYTES {
    return Err(ProtocolError::MalformedMessage("empty csd0 payload"));
  }
  Ok((
    VideoStreamHeader {
      use_h265,
      width,
      height,
      csd0,
      csd1,
    },
    off,
  ))
}

/// Parse one length-prefixed access unit (`len:u32 BE` + `pts:i64 BE` + NAL bytes).
pub fn parse_video_access_unit(buf: &[u8]) -> ProtocolResult<(VideoAccessUnit, usize)> {
  let (frame, consumed) = read_be_length_prefixed(buf, 0, MAX_AU_BYTES)?;
  if frame.len() < PTS_PREFIX_BYTES {
    return Err(ProtocolError::MalformedMessage("AU shorter than PTS prefix"));
  }
  let pts_us = i64::from_be_bytes([
    frame[0], frame[1], frame[2], frame[3], frame[4], frame[5], frame[6], frame[7],
  ]);
  let payload = frame[PTS_PREFIX_BYTES..].to_vec();
  Ok((VideoAccessUnit { pts_us, payload }, consumed))
}

/// Strip the 8-byte PTS prefix from a raw CSD/AU frame body (no length prefix).
pub fn strip_pts_prefix(frame: &[u8]) -> ProtocolResult<&[u8]> {
  if frame.len() < PTS_PREFIX_BYTES {
    return Err(ProtocolError::MalformedMessage("frame shorter than PTS prefix"));
  }
  Ok(&frame[PTS_PREFIX_BYTES..])
}

/// True when payload starts with Annex-B start code `00 00 00 01` or `00 00 01`.
pub fn looks_like_annex_b(payload: &[u8]) -> bool {
  if payload.len() >= 4 && payload[0] == 0 && payload[1] == 0 && payload[2] == 0 && payload[3] == 1 {
    return true;
  }
  if payload.len() >= 3 && payload[0] == 0 && payload[1] == 0 && payload[2] == 1 {
    return true;
  }
  false
}

fn read_be_length_prefixed(
  buf: &[u8],
  off: usize,
  max_len: usize,
) -> ProtocolResult<(Vec<u8>, usize)> {
  if buf.len() < off + 4 {
    return Err(ProtocolError::BufferTooShort {
      need: off + 4,
      got: buf.len(),
    });
  }
  let len = u32::from_be_bytes([buf[off], buf[off + 1], buf[off + 2], buf[off + 3]]) as usize;
  if len > max_len {
    return Err(ProtocolError::PayloadTooLarge {
      length: len,
      max: max_len,
    });
  }
  let start = off + 4;
  let end = start
    .checked_add(len)
    .ok_or(ProtocolError::MalformedMessage("frame length overflow"))?;
  if buf.len() < end {
    return Err(ProtocolError::BufferTooShort {
      need: end,
      got: buf.len(),
    });
  }
  Ok((buf[start..end].to_vec(), 4 + len))
}

#[cfg(test)]
mod tests {
  use super::*;

  fn push_frame(buf: &mut Vec<u8>, pts: i64, nal: &[u8]) {
    let mut body = Vec::new();
    body.extend_from_slice(&pts.to_be_bytes());
    body.extend_from_slice(nal);
    buf.extend_from_slice(&(body.len() as u32).to_be_bytes());
    buf.extend_from_slice(&body);
  }

  #[test]
  fn parse_header_and_access_unit_avc() {
    let mut buf = vec![0u8]; // AVC
    buf.extend_from_slice(&1280u32.to_be_bytes());
    buf.extend_from_slice(&720u32.to_be_bytes());
    let sps = [0x00, 0x00, 0x00, 0x01, 0x67, 0x42];
    let pps = [0x00, 0x00, 0x00, 0x01, 0x68, 0xce];
    push_frame(&mut buf, 0, &sps);
    push_frame(&mut buf, 0, &pps);
    let idr = [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00];
    push_frame(&mut buf, 33_000, &idr);

    let (hdr, consumed) = parse_video_stream_header(&buf).unwrap();
    assert!(!hdr.use_h265);
    assert_eq!((hdr.width, hdr.height), (1280, 720));
    assert!(looks_like_annex_b(strip_pts_prefix(&hdr.csd0).unwrap()));
    assert!(looks_like_annex_b(
      strip_pts_prefix(hdr.csd1.as_ref().unwrap()).unwrap()
    ));

    let (au, au_consumed) = parse_video_access_unit(&buf[consumed..]).unwrap();
    assert_eq!(au.pts_us, 33_000);
    assert_eq!(au.payload, idr);
    assert!(looks_like_annex_b(&au.payload));
    assert_eq!(consumed + au_consumed, buf.len());
  }

  #[test]
  fn rejects_oversized_au() {
    let mut buf = Vec::new();
    buf.extend_from_slice(&((MAX_AU_BYTES as u32) + 1).to_be_bytes());
    let err = parse_video_access_unit(&buf).unwrap_err();
    match err {
      ProtocolError::PayloadTooLarge { .. } => {}
      other => panic!("unexpected {other:?}"),
    }
  }
}
