use core::fmt;
use std::io;

use easycontrol_protocol::adb::{
  CMD_AUTH, CMD_CLSE, CMD_CNXN, CMD_OKAY, CMD_OPEN, CMD_STLS, CMD_WRTE,
};
use easycontrol_protocol::ProtocolError;

#[derive(Debug)]
pub enum AdbError {
  Io(io::Error),
  Protocol(ProtocolError),
  UnexpectedCommand { expected: &'static str, got: u32 },
  AuthFailed(&'static str),
  /// Deprecated placeholder error — prefer [`crate::signer::RsaAdbSigner`].
  ProductionSignerPending,
  Crypto(String),
  /// A_STLS / TLS 1.3 session upgrade (wireless `_adb-tls-connect._tcp`).
  Tls(String),
  StreamClosed,
  StreamNotFound(u32),
  FlowControl,
  Timeout,
  RemoteFail(String),
  InvalidState(&'static str),
  PayloadTooLarge { length: usize, max: usize },
}

fn adb_cmd_tag(cmd: u32) -> &'static str {
  match cmd {
    CMD_CNXN => "CNXN",
    CMD_AUTH => "AUTH",
    CMD_OPEN => "OPEN",
    CMD_OKAY => "OKAY",
    CMD_CLSE => "CLSE",
    CMD_WRTE => "WRTE",
    CMD_STLS => "STLS",
    _ => "????",
  }
}

impl fmt::Display for AdbError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::Io(e) => write!(f, "io error: {e}"),
      Self::Protocol(e) => write!(f, "protocol error: {e}"),
      Self::UnexpectedCommand { expected, got } => {
        write!(
          f,
          "expected {expected}, got {got:#010x} ({})",
          adb_cmd_tag(*got)
        )
      }
      Self::AuthFailed(msg) => write!(f, "adb auth failed: {msg}"),
      Self::ProductionSignerPending => write!(
        f,
        "production ADB RSA signer pending (HUKS-backed key + ADB public-key encoding)"
      ),
      Self::Crypto(msg) => write!(f, "crypto error: {msg}"),
      Self::Tls(msg) => write!(f, "adb tls: {msg}"),
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
