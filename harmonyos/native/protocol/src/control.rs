//! EasyControl control-channel packets (big-endian).
//!
//! Golden reference: `app/.../client/tools/ControlPacket.java`
//! Java `ByteBuffer` defaults to big-endian; do not use little-endian here.

use crate::error::{ProtocolError, ProtocolResult};

/// Android `MotionEvent.ACTION_UP`
pub const MOTION_ACTION_UP: u8 = 1;

pub const EVENT_TOUCH: u8 = 1;
pub const EVENT_KEY: u8 = 2;
pub const EVENT_CLIPBOARD: u8 = 3;
pub const EVENT_KEEPALIVE: u8 = 4;
pub const EVENT_CHANGE_RESOLUTION_FLOAT: u8 = 5;
pub const EVENT_ROTATE: u8 = 6;
pub const EVENT_LIGHT: u8 = 7;
pub const EVENT_POWER: u8 = 8;
pub const EVENT_CHANGE_RESOLUTION_WH: u8 = 9;

pub const CLIPBOARD_MAX_UTF8_BYTES: usize = 5000;

fn put_f32_be(buf: &mut Vec<u8>, v: f32) {
  buf.extend_from_slice(&v.to_bits().to_be_bytes());
}

fn put_i32_be(buf: &mut Vec<u8>, v: i32) {
  buf.extend_from_slice(&v.to_be_bytes());
}

fn put_u32_be(buf: &mut Vec<u8>, v: u32) {
  buf.extend_from_slice(&v.to_be_bytes());
}

/// Touch event (15 bytes). Out-of-range x/y are clamped and forced to ACTION_UP.
pub fn create_touch_event(action: u8, pointer_id: u8, x: f32, y: f32, offset_time: i32) -> Vec<u8> {
  let mut action = action;
  let mut x = x;
  let mut y = y;
  if !(0.0..=1.0).contains(&x) || !(0.0..=1.0).contains(&y) {
    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
    action = MOTION_ACTION_UP;
  }
  let mut buf = Vec::with_capacity(15);
  buf.push(EVENT_TOUCH);
  buf.push(action);
  buf.push(pointer_id);
  put_f32_be(&mut buf, x);
  put_f32_be(&mut buf, y);
  put_i32_be(&mut buf, offset_time);
  buf
}

pub fn create_key_event(key: i32, meta: i32) -> Vec<u8> {
  let mut buf = Vec::with_capacity(9);
  buf.push(EVENT_KEY);
  put_i32_be(&mut buf, key);
  put_i32_be(&mut buf, meta);
  buf
}

pub fn create_clipboard_event(text: &str) -> ProtocolResult<Vec<u8>> {
  let bytes = text.as_bytes();
  if bytes.is_empty() {
    return Err(ProtocolError::ClipboardEmpty);
  }
  if bytes.len() > CLIPBOARD_MAX_UTF8_BYTES {
    return Err(ProtocolError::ClipboardTooLarge {
      length: bytes.len(),
    });
  }
  let mut buf = Vec::with_capacity(5 + bytes.len());
  buf.push(EVENT_CLIPBOARD);
  put_u32_be(&mut buf, bytes.len() as u32);
  buf.extend_from_slice(bytes);
  Ok(buf)
}

pub fn create_keep_alive() -> Vec<u8> {
  vec![EVENT_KEEPALIVE]
}

pub fn create_change_resolution_float(new_size: f32) -> Vec<u8> {
  let mut buf = Vec::with_capacity(5);
  buf.push(EVENT_CHANGE_RESOLUTION_FLOAT);
  put_f32_be(&mut buf, new_size);
  buf
}

pub fn create_change_resolution_wh(width: i32, height: i32) -> Vec<u8> {
  let mut buf = Vec::with_capacity(9);
  buf.push(EVENT_CHANGE_RESOLUTION_WH);
  put_i32_be(&mut buf, width);
  put_i32_be(&mut buf, height);
  buf
}

pub fn create_rotate_event() -> Vec<u8> {
  vec![EVENT_ROTATE]
}

pub fn create_light_event(mode: u8) -> Vec<u8> {
  vec![EVENT_LIGHT, mode]
}

pub fn create_power_event(mode: i32) -> Vec<u8> {
  let mut buf = Vec::with_capacity(5);
  buf.push(EVENT_POWER);
  put_i32_be(&mut buf, mode);
  buf
}

#[derive(Debug, Clone, PartialEq)]
pub enum ControlEvent {
  Touch {
    action: u8,
    pointer_id: u8,
    x: f32,
    y: f32,
    offset_time: i32,
  },
  Key {
    key: i32,
    meta: i32,
  },
  Clipboard {
    text: String,
  },
  KeepAlive,
  ChangeResolutionFloat(f32),
  Rotate,
  Light(u8),
  Power(i32),
  ChangeResolutionWh {
    width: i32,
    height: i32,
  },
}

pub fn decode_control_event(buf: &[u8]) -> ProtocolResult<ControlEvent> {
  if buf.is_empty() {
    return Err(ProtocolError::BufferTooShort { need: 1, got: 0 });
  }
  match buf[0] {
    EVENT_TOUCH => {
      if buf.len() < 15 {
        return Err(ProtocolError::BufferTooShort {
          need: 15,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::Touch {
        action: buf[1],
        pointer_id: buf[2],
        x: f32::from_bits(u32::from_be_bytes(buf[3..7].try_into().unwrap())),
        y: f32::from_bits(u32::from_be_bytes(buf[7..11].try_into().unwrap())),
        offset_time: i32::from_be_bytes(buf[11..15].try_into().unwrap()),
      })
    }
    EVENT_KEY => {
      if buf.len() < 9 {
        return Err(ProtocolError::BufferTooShort {
          need: 9,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::Key {
        key: i32::from_be_bytes(buf[1..5].try_into().unwrap()),
        meta: i32::from_be_bytes(buf[5..9].try_into().unwrap()),
      })
    }
    EVENT_CLIPBOARD => {
      if buf.len() < 5 {
        return Err(ProtocolError::BufferTooShort {
          need: 5,
          got: buf.len(),
        });
      }
      let len = u32::from_be_bytes(buf[1..5].try_into().unwrap()) as usize;
      if len == 0 {
        return Err(ProtocolError::ClipboardEmpty);
      }
      if len > CLIPBOARD_MAX_UTF8_BYTES {
        return Err(ProtocolError::ClipboardTooLarge { length: len });
      }
      let need = 5 + len;
      if buf.len() < need {
        return Err(ProtocolError::BufferTooShort {
          need,
          got: buf.len(),
        });
      }
      let text = std::str::from_utf8(&buf[5..need])
        .map_err(|_| ProtocolError::InvalidUtf8)?
        .to_string();
      Ok(ControlEvent::Clipboard { text })
    }
    EVENT_KEEPALIVE => Ok(ControlEvent::KeepAlive),
    EVENT_CHANGE_RESOLUTION_FLOAT => {
      if buf.len() < 5 {
        return Err(ProtocolError::BufferTooShort {
          need: 5,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::ChangeResolutionFloat(f32::from_bits(
        u32::from_be_bytes(buf[1..5].try_into().unwrap()),
      )))
    }
    EVENT_ROTATE => Ok(ControlEvent::Rotate),
    EVENT_LIGHT => {
      if buf.len() < 2 {
        return Err(ProtocolError::BufferTooShort {
          need: 2,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::Light(buf[1]))
    }
    EVENT_POWER => {
      if buf.len() < 5 {
        return Err(ProtocolError::BufferTooShort {
          need: 5,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::Power(i32::from_be_bytes(
        buf[1..5].try_into().unwrap(),
      )))
    }
    EVENT_CHANGE_RESOLUTION_WH => {
      if buf.len() < 9 {
        return Err(ProtocolError::BufferTooShort {
          need: 9,
          got: buf.len(),
        });
      }
      Ok(ControlEvent::ChangeResolutionWh {
        width: i32::from_be_bytes(buf[1..5].try_into().unwrap()),
        height: i32::from_be_bytes(buf[5..9].try_into().unwrap()),
      })
    }
    _ => Err(ProtocolError::MalformedMessage("unknown control event type")),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn keepalive_and_rotate_single_byte() {
    assert_eq!(create_keep_alive(), vec![4]);
    assert_eq!(create_rotate_event(), vec![6]);
    assert_eq!(decode_control_event(&[4]).unwrap(), ControlEvent::KeepAlive);
  }

  #[test]
  fn touch_big_endian_layout() {
    let pkt = create_touch_event(0, 3, 0.5, 0.25, 0x01020304);
    assert_eq!(pkt.len(), 15);
    assert_eq!(pkt[0], 1);
    assert_eq!(pkt[1], 0);
    assert_eq!(pkt[2], 3);
    // 0.5f BE = 0x3f000000
    assert_eq!(&pkt[3..7], &[0x3f, 0x00, 0x00, 0x00]);
    // 0.25f BE = 0x3e800000
    assert_eq!(&pkt[7..11], &[0x3e, 0x80, 0x00, 0x00]);
    assert_eq!(&pkt[11..15], &[0x01, 0x02, 0x03, 0x04]);
    match decode_control_event(&pkt).unwrap() {
      ControlEvent::Touch {
        action,
        pointer_id,
        x,
        y,
        offset_time,
      } => {
        assert_eq!(action, 0);
        assert_eq!(pointer_id, 3);
        assert_eq!(x, 0.5);
        assert_eq!(y, 0.25);
        assert_eq!(offset_time, 0x01020304);
      }
      other => panic!("unexpected {other:?}"),
    }
  }

  #[test]
  fn touch_out_of_range_becomes_up() {
    let pkt = create_touch_event(0, 0, -0.1, 1.5, 0);
    assert_eq!(pkt[1], MOTION_ACTION_UP);
    assert_eq!(&pkt[3..7], &0.0f32.to_bits().to_be_bytes());
    assert_eq!(&pkt[7..11], &1.0f32.to_bits().to_be_bytes());
  }

  #[test]
  fn key_power_resolution_events() {
    let key = create_key_event(4, 0);
    assert_eq!(key[0], 2);
    assert_eq!(&key[1..5], &4i32.to_be_bytes());
    let power = create_power_event(1);
    assert_eq!(power, {
      let mut v = vec![8];
      v.extend_from_slice(&1i32.to_be_bytes());
      v
    });
    let res = create_change_resolution_wh(1080, 1920);
    assert_eq!(res[0], 9);
    let f = create_change_resolution_float(0.8);
    assert_eq!(f[0], 5);
    assert_eq!(create_light_event(2), vec![7, 2]);
  }

  #[test]
  fn clipboard_limits() {
    assert_eq!(
      create_clipboard_event(""),
      Err(ProtocolError::ClipboardEmpty)
    );
    let ok = create_clipboard_event("hi").unwrap();
    assert_eq!(ok[0], 3);
    assert_eq!(&ok[1..5], &2u32.to_be_bytes());
    assert_eq!(&ok[5..], b"hi");
    let big = "a".repeat(CLIPBOARD_MAX_UTF8_BYTES + 1);
    assert!(matches!(
      create_clipboard_event(&big),
      Err(ProtocolError::ClipboardTooLarge { .. })
    ));
    let max_ok = create_clipboard_event(&"b".repeat(CLIPBOARD_MAX_UTF8_BYTES)).unwrap();
    assert_eq!(max_ok.len(), 5 + CLIPBOARD_MAX_UTF8_BYTES);
  }

  #[test]
  fn decode_rejects_truncated_clipboard() {
    let mut pkt = create_clipboard_event("hello").unwrap();
    pkt.pop();
    assert!(matches!(
      decode_control_event(&pkt),
      Err(ProtocolError::BufferTooShort { .. })
    ));
  }

  #[test]
  fn unknown_type_rejected() {
    assert!(matches!(
      decode_control_event(&[99]),
      Err(ProtocolError::MalformedMessage(_))
    ));
  }
}
