//! ADB AUTH signing abstraction.
//!
//! Real Android ADB uses RSA-2048 PKCS#1 v1.5 signatures over the AUTH token plus
//! ADB-encoded public key bytes. That production path is **pending** (HUKS / Asset Store
//! wrapping + ADB key encoding). Tests use [`DeterministicTestSigner`].

use crate::error::{AdbError, AdbResult};

/// Signs ADB AUTH tokens and exposes the public-key payload for AUTH type 3.
pub trait AdbSigner: Send {
  /// Produce AUTH_TYPE_SIGNATURE payload for the device token.
  fn sign_token(&self, token: &[u8]) -> AdbResult<Vec<u8>>;

  /// ADB `AUTH_TYPE_RSA_PUBLIC` payload (Android wire format). Production encoding pending.
  fn public_key_payload(&self) -> AdbResult<Vec<u8>>;
}

/// Deterministic, non-cryptographic signer for host tests / fake daemon.
///
/// Signature = `b"TEST-SIG:"` + token. This is **not** RSA and must never ship as production auth.
pub struct DeterministicTestSigner {
  pub key_id: Vec<u8>,
}

impl DeterministicTestSigner {
  pub fn new(key_id: impl Into<Vec<u8>>) -> Self {
    Self {
      key_id: key_id.into(),
    }
  }

  pub fn default_test() -> Self {
    Self::new(b"easycontrol-test-key".to_vec())
  }

  pub fn expected_signature(token: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + token.len());
    out.extend_from_slice(b"TEST-SIG:");
    out.extend_from_slice(token);
    out
  }
}

impl AdbSigner for DeterministicTestSigner {
  fn sign_token(&self, token: &[u8]) -> AdbResult<Vec<u8>> {
    Ok(Self::expected_signature(token))
  }

  fn public_key_payload(&self) -> AdbResult<Vec<u8>> {
    // Not ADB RSA wire format — fake daemon accepts this marker for "offer public key" path.
    let mut out = b"TEST-PUB:".to_vec();
    out.extend_from_slice(&self.key_id);
    out.push(0);
    Ok(out)
  }
}

/// Placeholder for production HUKS-backed RSA ADB keys.
///
/// All methods return [`AdbError::ProductionSignerPending`] until Phase 2 crypto lands.
pub struct PendingProductionSigner;

impl AdbSigner for PendingProductionSigner {
  fn sign_token(&self, _token: &[u8]) -> AdbResult<Vec<u8>> {
    Err(AdbError::ProductionSignerPending)
  }

  fn public_key_payload(&self) -> AdbResult<Vec<u8>> {
    Err(AdbError::ProductionSignerPending)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn deterministic_signature_is_stable() {
    let s = DeterministicTestSigner::default_test();
    let token = [1u8, 2, 3, 4, 5];
    assert_eq!(s.sign_token(&token).unwrap(), b"TEST-SIG:\x01\x02\x03\x04\x05");
  }

  #[test]
  fn production_signer_is_explicitly_pending() {
    let s = PendingProductionSigner;
    assert!(matches!(
      s.sign_token(&[0u8; 20]),
      Err(AdbError::ProductionSignerPending)
    ));
  }
}
