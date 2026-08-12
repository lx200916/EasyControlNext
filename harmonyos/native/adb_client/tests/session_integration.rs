//! Integration tests against [`easycontrol_adb_client::FakeDaemon`] (no physical device).

use std::io::Read;
use std::net::TcpStream;
use std::time::Duration;

use easycontrol_adb_client::{
  connect_tcp, AdbError, AdbSession, AdbSigner, DeterministicTestSigner, FakeDaemon,
  PendingProductionSigner, SessionState,
};
use easycontrol_protocol::adb::{self, ADB_HEADER_LENGTH};

fn connect_session(daemon: &FakeDaemon) -> AdbSession<TcpStream> {
  let stream = connect_tcp("127.0.0.1", daemon.port(), Duration::from_secs(3)).unwrap();
  let signer = DeterministicTestSigner::default_test();
  AdbSession::connect(stream, &signer, Duration::from_secs(3)).unwrap()
}

#[test]
fn handshake_authorized_path() {
  let daemon = FakeDaemon::start().unwrap();
  let session = connect_session(&daemon);
  assert_eq!(session.state(), SessionState::Connected);
  assert_eq!(session.max_data(), easycontrol_protocol::adb::CONNECT_MAXDATA);
  assert_eq!(daemon.state().connections, 1);
}

#[test]
fn shell_echo() {
  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  let out = session.shell("echo EASYCONTROL_TEST").unwrap();
  assert_eq!(String::from_utf8_lossy(&out).trim(), "EASYCONTROL_TEST");
  assert_eq!(
    daemon.state().last_shell_cmd.as_deref(),
    Some("echo EASYCONTROL_TEST")
  );
}

#[test]
fn sync_push_sequence_and_hash() {
  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  let payload = b"hello-easycontrol-sync-push";
  let path = "/data/local/tmp/easycontrol_test.bin";
  let plan = session.sync_push(path, payload).unwrap();
  assert_eq!(plan.file_len, payload.len());
  assert_eq!(
    daemon.pushed_sha256(path).as_deref(),
    Some(plan.sha256_hex.as_str())
  );
  assert_eq!(
    daemon.state().pushed_files.get(path).map(|v| v.as_slice()),
    Some(payload.as_slice())
  );
}

#[test]
fn tcp_echo_bidirectional() {
  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  let id = session.open_tcp(9).unwrap();
  session.write_stream(id, b"ping").unwrap();
  let echoed = session.read_stream_at_least(id, 4).unwrap();
  assert_eq!(echoed, b"ping");
}

#[test]
fn stream_flow_control_multi_write() {
  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  let id = session.open_tcp(9).unwrap();
  session.write_stream(id, b"ab").unwrap();
  session.write_stream(id, b"cd").unwrap();
  let mut got = Vec::new();
  while got.len() < 4 {
    got.extend(session.read_stream_at_least(id, 1).unwrap());
  }
  assert_eq!(&got[..4], b"abcd");
}

#[test]
fn malformed_header_magic_rejected() {
  let err = {
    let mut bad = adb::generate_okay(1, 1);
    bad[20] ^= 0xff;
    adb::decode_message(&bad, true).unwrap_err()
  };
  assert!(matches!(
    err,
    easycontrol_protocol::ProtocolError::InvalidMagic { .. }
  ));

  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  let err = session.write_stream(1, b"x").unwrap_err();
  assert!(matches!(err, AdbError::StreamNotFound(1)));
}

#[test]
fn auth_rejects_wrong_signature() {
  let daemon = FakeDaemon::start().unwrap();
  let stream = connect_tcp("127.0.0.1", daemon.port(), Duration::from_secs(3)).unwrap();

  struct BadSigner;
  impl AdbSigner for BadSigner {
    fn sign_token(&self, token: &[u8]) -> easycontrol_adb_client::AdbResult<Vec<u8>> {
      Ok(vec![0xFF; token.len()])
    }
    fn public_key_payload(&self) -> easycontrol_adb_client::AdbResult<Vec<u8>> {
      Ok(b"NOT-TEST-PUB\0".to_vec())
    }
  }

  let result = AdbSession::connect(stream, &BadSigner, Duration::from_secs(2));
  assert!(
    matches!(
      result,
      Err(
        AdbError::UnexpectedCommand { .. }
          | AdbError::Timeout
          | AdbError::Io(_)
          | AdbError::AuthFailed(_)
      )
    ),
    "expected auth failure, got success"
  );
}

#[test]
fn production_signer_pending_is_explicit() {
  let daemon = FakeDaemon::start().unwrap();
  let stream = connect_tcp("127.0.0.1", daemon.port(), Duration::from_secs(3)).unwrap();
  let result = AdbSession::connect(stream, &PendingProductionSigner, Duration::from_secs(2));
  assert!(matches!(result, Err(AdbError::ProductionSignerPending)));
}

#[test]
fn timeout_behavior_raw_transport() {
  let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
  let port = listener.local_addr().unwrap().port();
  let accept = std::thread::spawn(move || {
    let (mut s, _) = listener.accept().unwrap();
    let mut buf = [0u8; ADB_HEADER_LENGTH];
    let _ = s.set_read_timeout(Some(Duration::from_millis(200)));
    let _ = s.read(&mut buf);
    std::thread::sleep(Duration::from_millis(300));
  });
  let mut stream = connect_tcp("127.0.0.1", port, Duration::from_millis(200)).unwrap();
  stream
    .set_read_timeout(Some(Duration::from_millis(50)))
    .unwrap();
  let mut buf = [0u8; 4];
  let err = std::io::Read::read_exact(&mut stream, &mut buf).unwrap_err();
  assert!(
    err.kind() == std::io::ErrorKind::TimedOut
      || err.kind() == std::io::ErrorKind::WouldBlock
      || err.kind() == std::io::ErrorKind::UnexpectedEof
  );
  let _ = accept.join();
}

#[test]
fn close_session_rejects_further_ops() {
  let daemon = FakeDaemon::start().unwrap();
  let mut session = connect_session(&daemon);
  session.close().unwrap();
  assert_eq!(session.state(), SessionState::Closed);
  assert!(session.shell("echo x").is_err());
}
