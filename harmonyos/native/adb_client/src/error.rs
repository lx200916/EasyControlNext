use core::fmt;
use std::io;

use easycontrol_protocol::ProtocolError;

#[derive(Debug)]
pub enum AdbError {
  Io(io::Error),
  Protocol(ProtocolError),
  UnexpectedCommand { expected: &'static str, got: u32 },
  AuthFailed(&'static str),
  /// Production RSA/ADB key encoding is not wired yet — use DeterministicTestSigner in tests only.
  ProductionSignerPending,
  StreamClosed,
  StreamNotFound(u32),
  FlowControl,
  Timeout,
  RemoteFail(String),
  InvalidState(&'static str),
  PayloadTooLarge { length: usize, max: usize },
}

impl fmt::Display for AdbError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::Io(e) => write!(f, "io error: {e}"),
      Self::Protocol(e) => write!(f, "protocol error: {e}"),
      Self::UnexpectedCommand { expected, got } => {
        write!(f, "unexpected ADB command: expected {expected}, got {got:#010x}")
      }
      Self::AuthFailed(msg) => write!(f, "adb auth failed: {msg}"),
      Self::ProductionSignerPending => write!(
        f,
        "production ADB RSA signer pending (HUKS-backed key + ADB public-key encoding)"
      ),
      Self::StreamClosed => write!(f, "adb stream closed"),
      Self::StreamNotFound(id) => write!(f, "adb stream not found: local_id={id}"),
      Self::FlowControl => write!(f, "adb flow control: write without OKAY credit"),
      Self::Timeout => write!(f, "adb operation timed out"),
      Self::RemoteFail(msg) => write!(f, "remote failure: {msg}"),
      Self::InvalidState(msg) => write!(f, "invalid session state: {msg}"),
      Self::PayloadTooLarge { length, max } => {
        write!(f, "payload too large for maxdata: {length} > {max}")
      }
    }
  }
}

impl std::error::Error for AdbError {
  fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
    match self {
      Self::Io(e) => Some(e),
      Self::Protocol(e) => Some(e),
      _ => None,
    }
  }
}

impl From<io::Error> for AdbError {
  fn from(value: io::Error) -> Self {
    if value.kind() == io::ErrorKind::TimedOut || value.kind() == io::ErrorKind::WouldBlock {
      Self::Timeout
    } else {
      Self::Io(value)
    }
  }
}

impl From<ProtocolError> for AdbError {
  fn from(value: ProtocolError) -> Self {
    Self::Protocol(value)
  }
}

pub type AdbResult<T> = Result<T, AdbError>;
