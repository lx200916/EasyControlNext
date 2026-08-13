//! Shared rustls client helpers for ADB wireless pairing and A_STLS session upgrade.
//!
//! Mirrors muntashirakon `SslUtils`: TLS 1.3, client RSA/X.509 from the ADB key PEM,
//! accept any server certificate (adbd uses a transient self-signed cert).

use std::sync::Arc;

use rcgen::{CertificateParams, DistinguishedName, DnType, KeyPair};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::{ClientConfig, ClientConnection, DigitallySignedStruct, Error as TlsError, SignatureScheme,
             StreamOwned};
use std::net::TcpStream;

use crate::error::{AdbError, AdbResult};

/// Build a self-signed client cert from the same PKCS#8 RSA PEM used for ADB AUTH / pairing.
pub fn make_client_cert(private_key_pem: &str) -> AdbResult<(Vec<u8>, Vec<u8>)> {
  let key_pair = KeyPair::from_pem(private_key_pem)
    .map_err(|e| AdbError::Crypto(format!("rcgen KeyPair: {e}")))?;
  let mut params = CertificateParams::new(vec!["Easy Control Next".into()])
    .map_err(|e| AdbError::Crypto(format!("cert params: {e}")))?;
  let mut dn = DistinguishedName::new();
  dn.push(DnType::CommonName, "Easy Control Next");
  params.distinguished_name = dn;
  let cert = params
    .self_signed(&key_pair)
    .map_err(|e| AdbError::Crypto(format!("self_signed: {e}")))?;
  Ok((cert.der().as_ref().to_vec(), key_pair.serialize_der()))
}

pub fn build_tls_client_config(
  cert_der: Vec<u8>,
  key_der: Vec<u8>,
) -> AdbResult<Arc<ClientConfig>> {
  let _ = rustls::crypto::ring::default_provider().install_default();
  let certs = vec![CertificateDer::from(cert_der)];
  let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key_der));
  let config = ClientConfig::builder()
    .dangerous()
    .with_custom_certificate_verifier(Arc::new(NoCertificateVerification))
    .with_client_auth_cert(certs, key)
    .map_err(|e| AdbError::Tls(format!("client auth cert: {e}")))?;
  Ok(Arc::new(config))
}

/// Upgrade an already-connected TCP stream to TLS 1.3 (after A_STLS exchange).
pub fn upgrade_tcp_to_tls(
  sock: TcpStream,
  private_key_pem: &str,
  server_name: &str,
) -> AdbResult<StreamOwned<ClientConnection, TcpStream>> {
  let (cert_der, key_der) = make_client_cert(private_key_pem)?;
  let config = build_tls_client_config(cert_der, key_der)?;
  // SNI is unused by adbd (self-signed); IP hosts must still parse as ServerName.
  let name = if server_name.trim().is_empty() {
    "localhost".to_string()
  } else {
    server_name.trim().to_string()
  };
  let server_name = match ServerName::try_from(name.as_str()) {
    Ok(n) => n.to_owned(),
    Err(_) => ServerName::try_from("localhost")
      .map_err(|_| AdbError::Tls("invalid TLS server name".into()))?
      .to_owned(),
  };
  let conn = ClientConnection::new(config, server_name)
    .map_err(|e| AdbError::Tls(format!("ClientConnection: {e}")))?;
  let mut tls = StreamOwned::new(conn, sock);
  // Drive handshake (StreamOwned is lazy until first I/O).
  use std::io::Write;
  tls
    .flush()
    .map_err(|e| AdbError::Tls(format!("TLS handshake flush: {e}")))?;
  Ok(tls)
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
