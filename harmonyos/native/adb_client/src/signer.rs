//! ADB AUTH signing abstraction.
//!
//! Real Android ADB uses RSA-2048 with PKCS#1 v1.5 / SHA-1 DigestInfo padding over the
//! 20-byte AUTH token, plus ADB mini-RSA public-key encoding (base64 + user@host + NUL).

use std::fs;
use std::path::Path;

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use num_bigint_dig::traits::ModInverse;
use num_bigint_dig::BigUint;
use num_traits::One;
use rand::rngs::OsRng;
use rsa::pkcs1v15::Pkcs1v15Sign;
use rsa::pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding};
use rsa::traits::PublicKeyParts;
use rsa::{RsaPrivateKey, RsaPublicKey};
use sha1::Sha1;

use crate::error::{AdbError, AdbResult};

const KEY_LENGTH_BITS: usize = 2048;
const KEY_LENGTH_BYTES: usize = KEY_LENGTH_BITS / 8;
const KEY_LENGTH_WORDS: usize = KEY_LENGTH_BYTES / 4;

/// Signs ADB AUTH tokens and exposes the public-key payload for AUTH type 3.
pub trait AdbSigner: Send {
  /// Produce AUTH_TYPE_SIGNATURE payload for the device token.
  fn sign_token(&self, token: &[u8]) -> AdbResult<Vec<u8>>;

  /// ADB `AUTH_TYPE_RSA_PUBLIC` payload (Android wire format, trailing NUL).
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

/// RSA-2048 ADB signer matching EasyControl Android `AdbKeyPair` / AOSP adbd.
pub struct RsaAdbSigner {
  private_key: RsaPrivateKey,
  /// Wire payload: `base64(adb-rsa) + " " + comment + "\0"`.
  public_key_payload: Vec<u8>,
}

impl RsaAdbSigner {
  pub fn generate(comment: &str) -> AdbResult<Self> {
    let mut rng = OsRng;
    let private_key = RsaPrivateKey::new(&mut rng, KEY_LENGTH_BITS)
      .map_err(|e| AdbError::Crypto(format!("rsa generate: {e}")))?;
    Self::from_private_key(private_key, comment)
  }

  pub fn from_private_key(private_key: RsaPrivateKey, comment: &str) -> AdbResult<Self> {
    let public_key = RsaPublicKey::from(&private_key);
    let adb_bin = convert_rsa_public_key_to_adb_format(&public_key)?;
    let mut public_key_payload = B64.encode(&adb_bin).into_bytes();
    public_key_payload.push(b' ');
    public_key_payload.extend_from_slice(comment.as_bytes());
    public_key_payload.push(0);
    Ok(Self {
      private_key,
      public_key_payload,
    })
  }

  /// Parse PKCS#8 PEM from memory (HarmonyOS rawfile → filesDir → NAPI Buffer path).
  pub fn from_pkcs8_pem_str(pem: &str, comment: &str) -> AdbResult<Self> {
    let private_key = RsaPrivateKey::from_pkcs8_pem(pem)
      .map_err(|e| AdbError::Crypto(format!("parse pkcs8 pem: {e}")))?;
    Self::from_private_key(private_key, comment)
  }

  /// Parse PKCS#8 PEM + optional ADB public-key line (`base64 … comment`, optional trailing NUL).
  pub fn from_pkcs8_pem_and_pub(pem: &str, pub_line: Option<&[u8]>, comment: &str) -> AdbResult<Self> {
    let private_key = RsaPrivateKey::from_pkcs8_pem(pem)
      .map_err(|e| AdbError::Crypto(format!("parse pkcs8 pem: {e}")))?;
    if let Some(line) = pub_line {
      let mut bytes = line.to_vec();
      // Strip trailing newline(s) then ensure single NUL.
      while bytes.last().copied() == Some(b'\n') || bytes.last().copied() == Some(b'\r') {
        bytes.pop();
      }
      if !bytes.ends_with(&[0]) {
        bytes.push(0);
      }
      return Ok(Self {
        private_key,
        public_key_payload: bytes,
      });
    }
    Self::from_private_key(private_key, comment)
  }

  /// Load PKCS#8 PEM private key + companion `.pub` ADB public line (or rebuild from private).
  pub fn load_pem(private_pem_path: &Path, comment: &str) -> AdbResult<Self> {
    let pem = fs::read_to_string(private_pem_path).map_err(AdbError::Io)?;
    let pub_path = private_pem_path.with_extension("pub");
    if pub_path.is_file() {
      let bytes = fs::read(&pub_path).map_err(AdbError::Io)?;
      return Self::from_pkcs8_pem_and_pub(&pem, Some(&bytes), comment);
    }
    Self::from_pkcs8_pem_str(&pem, comment)
  }

  /// Write PKCS#8 PEM + ADB `.pub` (without trailing NUL in file, matching Android generate()).
  pub fn save_pem(&self, private_pem_path: &Path) -> AdbResult<()> {
    if let Some(parent) = private_pem_path.parent() {
      fs::create_dir_all(parent).map_err(AdbError::Io)?;
    }
    let pem = self
      .private_key
      .to_pkcs8_pem(LineEnding::LF)
      .map_err(|e| AdbError::Crypto(format!("encode pkcs8 pem: {e}")))?;
    fs::write(private_pem_path, pem.as_bytes()).map_err(AdbError::Io)?;
    let pub_path = private_pem_path.with_extension("pub");
    let line = &self.public_key_payload[..self.public_key_payload.len().saturating_sub(1)];
    fs::write(pub_path, line).map_err(AdbError::Io)?;
    Ok(())
  }

  /// Generate if missing, otherwise load. Returns `(signer, newly_generated)`.
  pub fn load_or_generate(private_pem_path: &Path, comment: &str) -> AdbResult<(Self, bool)> {
    if private_pem_path.is_file() {
      return Ok((Self::load_pem(private_pem_path, comment)?, false));
    }
    let signer = Self::generate(comment)?;
    signer.save_pem(private_pem_path)?;
    Ok((signer, true))
  }
}

impl AdbSigner for RsaAdbSigner {
  fn sign_token(&self, token: &[u8]) -> AdbResult<Vec<u8>> {
    if token.len() != 20 {
      return Err(AdbError::AuthFailed("AUTH token must be 20 bytes"));
    }
    // Equivalent to Android `RSA/ECB/NoPadding` over SIGNATURE_PADDING || token.
    let padding = Pkcs1v15Sign::new::<Sha1>();
    self
      .private_key
      .sign(padding, token)
      .map_err(|e| AdbError::Crypto(format!("rsa sign: {e}")))
  }

  fn public_key_payload(&self) -> AdbResult<Vec<u8>> {
    Ok(self.public_key_payload.clone())
  }
}

/// Kept for API stability; prefer [`RsaAdbSigner`].
#[deprecated(note = "use RsaAdbSigner")]
pub struct PendingProductionSigner;

#[allow(deprecated)]
impl AdbSigner for PendingProductionSigner {
  fn sign_token(&self, _token: &[u8]) -> AdbResult<Vec<u8>> {
    Err(AdbError::ProductionSignerPending)
  }

  fn public_key_payload(&self) -> AdbResult<Vec<u8>> {
    Err(AdbError::ProductionSignerPending)
  }
}

/// AOSP / EasyControl `convertRsaPublicKeyToAdbFormat` (524-byte little-endian struct).
fn convert_rsa_public_key_to_adb_format(pubkey: &RsaPublicKey) -> AdbResult<Vec<u8>> {
  let n = pubkey.n().clone();
  let e = pubkey.e().clone();
  let r32 = BigUint::one() << 32;
  let r = BigUint::one() << (KEY_LENGTH_WORDS * 32);
  let rr = r.modpow(&BigUint::from(2u32), &n);
  let rem = &n % &r32;
  let n0inv = rem
    .clone()
    .mod_inverse(&r32)
    .ok_or_else(|| AdbError::Crypto("n0inv inverse failed".into()))?;
  // Java: n0inv.negate().intValue() — two's-complement low 32 bits.
  let n0inv_u32 = biguint_lo_u32(
    &n0inv
      .to_biguint()
      .ok_or_else(|| AdbError::Crypto("n0inv not unsigned".into()))?,
  );
  let n0inv_neg = (!n0inv_u32).wrapping_add(1); // -n0inv as u32 bit pattern

  let mut n_words = [0u32; KEY_LENGTH_WORDS];
  let mut rr_words = [0u32; KEY_LENGTH_WORDS];
  let mut n_tmp = n.clone();
  let mut rr_tmp = rr;
  for i in 0..KEY_LENGTH_WORDS {
    let (nq, nr) = div_rem_u32(&n_tmp, &r32);
    let (rrq, rrr) = div_rem_u32(&rr_tmp, &r32);
    n_tmp = nq;
    rr_tmp = rrq;
    n_words[i] = nr;
    rr_words[i] = rrr;
  }

  let mut out = Vec::with_capacity(524);
  out.extend_from_slice(&(KEY_LENGTH_WORDS as u32).to_le_bytes());
  out.extend_from_slice(&n0inv_neg.to_le_bytes());
  for w in n_words {
    out.extend_from_slice(&w.to_le_bytes());
  }
  for w in rr_words {
    out.extend_from_slice(&w.to_le_bytes());
  }
  let exp = biguint_lo_u32(&e);
  out.extend_from_slice(&exp.to_le_bytes());
  if out.len() != 524 {
    return Err(AdbError::Crypto(format!(
      "adb pubkey length {} != 524",
      out.len()
    )));
  }
  Ok(out)
}

fn biguint_lo_u32(value: &BigUint) -> u32 {
  let bytes = value.to_bytes_le();
  let mut buf = [0u8; 4];
  for (i, b) in bytes.iter().take(4).enumerate() {
    buf[i] = *b;
  }
  u32::from_le_bytes(buf)
}

fn div_rem_u32(value: &BigUint, r32: &BigUint) -> (BigUint, u32) {
  let q = value / r32;
  let r = value % r32;
  (q, biguint_lo_u32(&r))
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
  fn rsa_signer_round_trip_payload_and_sign_len() {
    let s = RsaAdbSigner::generate("gate@easycontrol").unwrap();
    let payload = s.public_key_payload().unwrap();
    assert!(payload.ends_with(&[0]));
    assert!(payload.contains(&b' '));
    let token = [0x11u8; 20];
    let sig = s.sign_token(&token).unwrap();
    assert_eq!(sig.len(), 256);
    let b64 = std::str::from_utf8(&payload[..payload.len() - 1])
      .unwrap()
      .split(' ')
      .next()
      .unwrap();
    let adb = B64.decode(b64).unwrap();
    assert_eq!(adb.len(), 524);
    assert_eq!(u32::from_le_bytes(adb[0..4].try_into().unwrap()), 64);
  }

  #[test]
  fn pending_signer_still_explicit() {
    #[allow(deprecated)]
    let s = PendingProductionSigner;
    assert!(matches!(
      s.sign_token(&[0u8; 20]),
      Err(AdbError::ProductionSignerPending)
    ));
  }
}
