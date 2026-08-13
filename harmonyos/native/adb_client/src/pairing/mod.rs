//! Android 11+ wireless debugging pairing (AOSP / muntashirakon-compatible).
//!
//! Flow (client / Alice):
//! 1. TCP → TLS 1.3 (client RSA cert, accept any peer cert)
//! 2. Export keying material label `adb-label\0` (64 B)
//! 3. SPAKE2-25519 password = pairing_code_bytes ‖ exporter
//! 4. Exchange SPAKE2 msgs (BE pairing headers) → HKDF → AES-128-GCM
//! 5. Exchange encrypted PeerInfo (ADB RSA pubkey)

mod auth;
mod connection;
mod framing;
mod spake2;

pub use connection::{normalize_pair_code, pair_wireless, PairResult};
pub use framing::{EXPORTED_KEY_LABEL, EXPORT_KEY_SIZE};

use core::fmt;

#[derive(Debug)]
pub enum PairingError {
  Io(std::io::Error),
  Tls(String),
  Crypto(String),
  Protocol(String),
  InvalidInput(&'static str),
}

impl fmt::Display for PairingError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      Self::Io(e) => write!(f, "pairing io: {e}"),
      Self::Tls(m) => write!(f, "pairing tls: {m}"),
      Self::Crypto(m) => write!(f, "pairing crypto: {m}"),
      Self::Protocol(m) => write!(f, "pairing protocol: {m}"),
      Self::InvalidInput(m) => write!(f, "pairing input: {m}"),
    }
  }
}

impl std::error::Error for PairingError {
  fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
    match self {
      Self::Io(e) => Some(e),
      _ => None,
    }
  }
}

impl From<std::io::Error> for PairingError {
  fn from(value: std::io::Error) -> Self {
    Self::Io(value)
  }
}

pub type PairingResult<T> = Result<T, PairingError>;
