//! Pure, host-testable framing for ADB and EasyControl control packets.
//!
//! Endianness contract (must match Android reference):
//! - ADB headers / sync headers: little-endian
//! - EasyControl control events: big-endian (Java `ByteBuffer` default)
//! - Wireless pairing headers (Phase 3): big-endian

#![deny(unsafe_code)]

pub mod adb;
pub mod control;
pub mod error;
pub mod sync;

pub use error::{ProtocolError, ProtocolResult};

/// Library version string for NAPI / diagnostics.
pub const PROTOCOL_VERSION: &str = env!("CARGO_PKG_VERSION");
