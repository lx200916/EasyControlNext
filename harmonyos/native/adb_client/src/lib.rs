//! Host-testable ADB TCP session core for the HarmonyOS controller.
//!
//! Production path: [`signer::RsaAdbSigner`] (RSA-2048 ADB wire format).
//! Host tests use [`signer::DeterministicTestSigner`] against [`fake_daemon::FakeDaemon`].
//! HUKS / Asset Store key wrapping for on-device HarmonyOS remains a later step.

#![deny(unsafe_code)]

pub mod dual_connect;
pub mod error;
pub mod fake_daemon;
pub mod pairing;
pub mod server_launch;
pub mod session;
pub mod signer;
pub mod sync_pull;
pub mod sync_push;
pub mod tls_client;
pub mod transport;

pub use dual_connect::{
  connect_dual, read_adb_at_least, read_exact_timeout, read_video_header_adb,
  read_video_header_tcp, read_video_header_tcp_with_leftover, try_direct, ConnectMode, DualSockets,
};
pub use pairing::{
  normalize_pair_code, pair_wireless, PairResult, PairingError, EXPORTED_KEY_LABEL, EXPORT_KEY_SIZE,
};
pub use error::{AdbError, AdbResult};
pub use fake_daemon::{FakeDaemon, FakeDaemonState};
pub use server_launch::{
  ensure_server_jar, load_server_jar_meta, parse_server_version_file, parse_video_access_unit,
  parse_video_stream_header, push_server_jar, remote_jar_sha_sidecar, start_server_shell,
  stop_existing_server, EnsureJarResult, ServerJarMeta, ServerLaunchOptions, VideoAccessUnit,
  VideoStreamHeader, DEFAULT_APP_VERSION_CODE, DEFAULT_SERVER_PORT,
};
pub use session::{AdbSession, SessionState};
pub use signer::{AdbSigner, DeterministicTestSigner, RsaAdbSigner};
#[allow(deprecated)]
pub use signer::PendingProductionSigner;
pub use sync_pull::{
  build_quit, build_recv_request, encode_fail_response, encode_pull_response, parse_pull_response,
  validate_remote_path, PullStreamParser, SyncPullResult, MAX_PULL_BYTES,
};
pub use sync_push::{build_sync_push, parse_and_hash_push, sha256_hex, SyncPushPlan};
pub use transport::{connect_tcp, AdbTransport, SessionIo};
