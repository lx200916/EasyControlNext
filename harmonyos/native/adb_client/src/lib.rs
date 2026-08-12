//! Host-testable ADB TCP session core for the HarmonyOS controller.
//!
//! Production RSA key encoding / HUKS wrapping is **pending** — see [`signer::PendingProductionSigner`].
//! Host tests use [`signer::DeterministicTestSigner`] against [`fake_daemon::FakeDaemon`].

#![deny(unsafe_code)]

pub mod error;
pub mod fake_daemon;
pub mod session;
pub mod signer;
pub mod sync_push;
pub mod transport;

pub use error::{AdbError, AdbResult};
pub use fake_daemon::{FakeDaemon, FakeDaemonState};
pub use session::{AdbSession, SessionState};
pub use signer::{AdbSigner, DeterministicTestSigner, PendingProductionSigner};
pub use sync_push::{build_sync_push, parse_and_hash_push, sha256_hex, SyncPushPlan};
pub use transport::{connect_tcp, AdbTransport};
