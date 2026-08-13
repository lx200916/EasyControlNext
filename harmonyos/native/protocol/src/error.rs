use core::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProtocolError {
  BufferTooShort { need: usize, got: usize },
  InvalidMagic { command: u32, magic: u32 },
  ChecksumMismatch { expected: u32, actual: u32 },
  PayloadTooLarge { length: usize, max: usize },
  InvalidUtf8,
  ClipboardEmpty,
  ClipboardTooLarge { length: usize },
  InvalidSyncId,
  MalformedMessage(&'static str),
}

impl fmt::Display for ProtocolError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::BufferTooShort { need, got } => {
        write!(f, "buffer too short: need {need}, got {got}")
      }
      Self::InvalidMagic { command, magic } => {
        write!(f, "invalid ADB magic: cmd={command:#010x} magic={magic:#010x}")
      }
      Self::ChecksumMismatch { expected, actual } => {
        write!(f, "checksum mismatch: expected {expected}, actual {actual}")
      }
      Self::PayloadTooLarge { length, max } => {
        write!(f, "payload too large: {length} > max {max}")
      }
      Self::InvalidUtf8 => write!(f, "invalid UTF-8"),
      Self::ClipboardEmpty => write!(f, "clipboard text empty"),
      Self::ClipboardTooLarge { length } => {
        write!(f, "clipboard too large: {length} > 5000")
      }
      Self::InvalidSyncId => write!(f, "sync id must be exactly 4 ASCII bytes"),
      Self::MalformedMessage(msg) => write!(f, "malformed message: {msg}"),
    }
  }
}

impl std::error::Error for ProtocolError {}

pub type ProtocolResult<T> = Result<T, ProtocolError>;
