//! End-to-end wireless pairing client (TLS 1.3 + SPAKE2 + peer-info).

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;
use std::time::Duration;

use rcgen::{CertificateParams, DistinguishedName, DnType, KeyPair};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::{ClientConfig, ClientConnection, DigitallySignedStruct, Error as TlsError, SignatureScheme,
             StreamOwned};
use zeroize::Zeroize;

use crate::signer::{AdbSigner, RsaAdbSigner};

use super::auth::PairingAuthCtx;
use super::framing::{
  encode_peer_info, PairingPacketHeader, EXPORTED_KEY_LABEL, EXPORT_KEY_SIZE, HEADER_SIZE,
  MAX_PEER_INFO_SIZE, TYPE_PEER_INFO, TYPE_SPAKE2_MSG,
};
use super::{PairingError, PairingResult};

#[derive(Debug, Clone)]
pub struct PairResult {
  pub host: String,
  pub pair_port: u16,
  pub detail: String,
}

/// Strip whitespace from Android wireless-debug pairing codes.
pub fn normalize_pair_code(pair_code: &str) -> String {
  pair_code.chars().filter(|c| !c.is_whitespace()).collect()
}

/// Pair with Android 11+ wireless debugging (manual IP + pairing port + code).
pub fn pair_wireless(
  host: &str,
  pair_port: u16,
  pair_code: &str,
  private_key_pem: &str,
  public_key_line: Option<&[u8]>,
  device_name: &str,
  timeout: Duration,
) -> PairingResult<PairResult> {
  let code = normalize_pair_code(pair_code);
  if host.trim().is_empty() {
    return Err(PairingError::InvalidInput("host required"));
  }
  if pair_port == 0 {
    return Err(PairingError::InvalidInput("pairing port invalid"));
  }
  if code.is_empty() {
    return Err(PairingError::InvalidInput("pairing code empty"));
  }

  let signer = RsaAdbSigner::from_pkcs8_pem_and_pub(
    private_key_pem,
    public_key_line,
    if device_name.is_empty() {
      "EasyControlNext"
    } else {
      device_name
    },
  )
  .map_err(|e| PairingError::Crypto(e.to_string()))?;
  let pubkey_payload = signer
    .public_key_payload()
    .map_err(|e| PairingError::Crypto(e.to_string()))?;

  let (cert_der, key_der) = make_client_cert(private_key_pem)?;
  let sock = TcpStream::connect((host.trim(), pair_port))?;
  sock.set_read_timeout(Some(timeout))?;
  sock.set_write_timeout(Some(timeout))?;
  sock.set_nodelay(true)?;

  let config = build_tls_config(cert_der, key_der)?;
  let server_name = ServerName::try_from(host.trim().to_string())
    .map_err(|_| PairingError::InvalidInput("invalid TLS server name"))?;
  let conn = ClientConnection::new(config, server_name)
    .map_err(|e| PairingError::Tls(e.to_string()))?;
  let mut tls = StreamOwned::new(conn, sock);

  // Complete handshake by forcing a write/read round (StreamOwned does this lazily).
  tls.flush().map_err(|e| PairingError::Tls(e.to_string()))?;

  let mut exporter = vec![0u8; EXPORT_KEY_SIZE];
  tls
    .conn
    .export_keying_material(&mut exporter, EXPORTED_KEY_LABEL.as_bytes(), None)
    .map_err(|e| PairingError::Tls(format!("export_keying_material: {e}")))?;

  let mut password = Vec::with_capacity(code.len() + exporter.len());
  password.extend_from_slice(code.as_bytes());
  password.extend_from_slice(&exporter);
  exporter.zeroize();

  let mut auth = PairingAuthCtx::create_alice(&password)?;
  password.zeroize();

  // SPAKE2 exchange
  write_packet(&mut tls, TYPE_SPAKE2_MSG, auth.msg())?;
  let (hdr, their_spake) = read_packet(&mut tls)?;
  if hdr.typ != TYPE_SPAKE2_MSG {
    return Err(PairingError::Protocol(format!(
      "expected SPAKE2_MSG, got {}",
      hdr.typ
    )));
  }
  auth.init_cipher(&their_spake)?;

  // PeerInfo exchange
  let peer_plain = encode_peer_info(&pubkey_payload);
  let peer_enc = auth.encrypt(&peer_plain)?;
  write_packet(&mut tls, TYPE_PEER_INFO, &peer_enc)?;
  let (hdr2, their_peer_enc) = read_packet(&mut tls)?;
  if hdr2.typ != TYPE_PEER_INFO {
    return Err(PairingError::Protocol(format!(
      "expected PEER_INFO, got {}",
      hdr2.typ
    )));
  }
  let their_peer = auth.decrypt(&their_peer_enc)?;
  if their_peer.len() != MAX_PEER_INFO_SIZE {
    return Err(PairingError::Protocol(format!(
      "peer info size {} != {MAX_PEER_INFO_SIZE}",
      their_peer.len()
    )));
  }

  let _ = tls.sock.shutdown(std::net::Shutdown::Both);

  Ok(PairResult {
    host: host.trim().to_string(),
    pair_port,
    detail: format!(
      "paired ok; peer_info_type={}; next: discover _adb-tls-connect._tcp or fill ADB port",
      their_peer[0]
    ),
  })
}

fn make_client_cert(private_key_pem: &str) -> PairingResult<(Vec<u8>, Vec<u8>)> {
  let key_pair = KeyPair::from_pem(private_key_pem)
    .map_err(|e| PairingError::Crypto(format!("rcgen KeyPair: {e}")))?;
  let mut params = CertificateParams::new(vec!["Easy Control Next".into()])
    .map_err(|e| PairingError::Crypto(format!("cert params: {e}")))?;
  let mut dn = DistinguishedName::new();
  dn.push(DnType::CommonName, "Easy Control Next");
  params.distinguished_name = dn;
  let cert = params
    .self_signed(&key_pair)
    .map_err(|e| PairingError::Crypto(format!("self_signed: {e}")))?;
  Ok((cert.der().as_ref().to_vec(), key_pair.serialize_der()))
}

fn build_tls_config(
  cert_der: Vec<u8>,
  key_der: Vec<u8>,
) -> PairingResult<Arc<ClientConfig>> {
  let _ = rustls::crypto::ring::default_provider().install_default();
  let certs = vec![CertificateDer::from(cert_der)];
  let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key_der));
  let config = ClientConfig::builder()
    .dangerous()
    .with_custom_certificate_verifier(Arc::new(NoCertificateVerification))
    .with_client_auth_cert(certs, key)
    .map_err(|e| PairingError::Tls(format!("client auth cert: {e}")))?;
  Ok(Arc::new(config))
}

fn write_packet<S: Read + Write>(
  tls: &mut StreamOwned<ClientConnection, S>,
  typ: u8,
  payload: &[u8],
) -> PairingResult<()> {
  let header = PairingPacketHeader::new(typ, payload.len());
  let mut hdr = [0u8; HEADER_SIZE];
  header.write_to(&mut hdr);
  tls.write_all(&hdr)?;
  tls.write_all(payload)?;
  tls.flush()?;
  Ok(())
}

fn read_packet<S: Read + Write>(
  tls: &mut StreamOwned<ClientConnection, S>,
) -> PairingResult<(PairingPacketHeader, Vec<u8>)> {
  let mut hdr_buf = [0u8; HEADER_SIZE];
  tls.read_exact(&mut hdr_buf)?;
  let header = PairingPacketHeader::read_from(&hdr_buf)?;
  let mut payload = vec![0u8; header.payload_size as usize];
  tls.read_exact(&mut payload)?;
  Ok((header, payload))
}

#[derive(Debug)]
struct NoCertificateVerification;

impl ServerCertVerifier for NoCertificateVerification {
  fn verify_server_cert(
    &self,
    _end_entity: &CertificateDer<'_>,
    _intermediates: &[CertificateDer<'_>],
    _server_name: &ServerName<'_>,
    _ocsp_response: &[u8],
    _now: UnixTime,
  ) -> Result<ServerCertVerified, TlsError> {
    Ok(ServerCertVerified::assertion())
  }

  fn verify_tls12_signature(
    &self,
    _message: &[u8],
    _cert: &CertificateDer<'_>,
    _dss: &DigitallySignedStruct,
  ) -> Result<HandshakeSignatureValid, TlsError> {
    Ok(HandshakeSignatureValid::assertion())
  }

  fn verify_tls13_signature(
    &self,
    _message: &[u8],
    _cert: &CertificateDer<'_>,
    _dss: &DigitallySignedStruct,
  ) -> Result<HandshakeSignatureValid, TlsError> {
    Ok(HandshakeSignatureValid::assertion())
  }

  fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
    rustls::crypto::ring::default_provider()
      .signature_verification_algorithms
      .supported_schemes()
  }
}
