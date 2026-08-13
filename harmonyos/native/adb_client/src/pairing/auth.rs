//! PairingAuthCtx — SPAKE2 + HKDF-SHA256 + AES-128-GCM (AOSP aes_128_gcm.cpp).

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes128Gcm, Nonce};
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::{Zeroize, ZeroizeOnDrop};

use super::spake2::{Spake2Context, Spake2Role};
use super::{PairingError, PairingResult};

const CLIENT_NAME: &[u8] = b"adb pair client\0";
const SERVER_NAME: &[u8] = b"adb pair server\0";
const HKDF_INFO: &[u8] = b"adb pairing_auth aes-128-gcm key";
const HKDF_KEY_LEN: usize = 16;
const GCM_IV_LEN: usize = 12;

#[derive(ZeroizeOnDrop)]
pub struct PairingAuthCtx {
  #[zeroize(skip)]
  spake: Spake2Context,
  msg: Vec<u8>,
  secret_key: [u8; HKDF_KEY_LEN],
  #[zeroize(skip)]
  enc_iv: u64,
  #[zeroize(skip)]
  dec_iv: u64,
  #[zeroize(skip)]
  ready: bool,
}

impl PairingAuthCtx {
  pub fn create_alice(password: &[u8]) -> PairingResult<Self> {
    let mut spake = Spake2Context::new(Spake2Role::Alice, CLIENT_NAME, SERVER_NAME)?;
    let msg = spake.generate_message(password)?.to_vec();
    Ok(Self {
      spake,
      msg,
      secret_key: [0u8; HKDF_KEY_LEN],
      enc_iv: 0,
      dec_iv: 0,
      ready: false,
    })
  }

  pub fn msg(&self) -> &[u8] {
    &self.msg
  }

  pub fn init_cipher(&mut self, their_msg: &[u8]) -> PairingResult<()> {
    let mut key_material = self.spake.process_message(their_msg)?;
    let hk = Hkdf::<Sha256>::new(None, &key_material);
    key_material.zeroize();
    hk.expand(HKDF_INFO, &mut self.secret_key)
      .map_err(|_| PairingError::Crypto("HKDF expand failed".into()))?;
    self.ready = true;
    Ok(())
  }

  pub fn encrypt(&mut self, plaintext: &[u8]) -> PairingResult<Vec<u8>> {
    self.crypt(true, plaintext)
  }

  pub fn decrypt(&mut self, ciphertext: &[u8]) -> PairingResult<Vec<u8>> {
    self.crypt(false, ciphertext)
  }

  fn crypt(&mut self, for_encryption: bool, input: &[u8]) -> PairingResult<Vec<u8>> {
    if !self.ready {
      return Err(PairingError::Protocol("pairing cipher not ready".into()));
    }
    let iv_counter = if for_encryption {
      let v = self.enc_iv;
      self.enc_iv = self.enc_iv.wrapping_add(1);
      v
    } else {
      let v = self.dec_iv;
      self.dec_iv = self.dec_iv.wrapping_add(1);
      v
    };
    // AOSP: 12-byte IV = little-endian u64 counter + 4 zero bytes.
    let mut iv = [0u8; GCM_IV_LEN];
    iv[..8].copy_from_slice(&iv_counter.to_le_bytes());
    let cipher = Aes128Gcm::new_from_slice(&self.secret_key)
      .map_err(|e| PairingError::Crypto(format!("AES-GCM init: {e}")))?;
    let nonce = Nonce::from_slice(&iv);
    if for_encryption {
      cipher
        .encrypt(nonce, input)
        .map_err(|e| PairingError::Crypto(format!("AES-GCM encrypt: {e}")))
    } else {
      cipher
        .decrypt(nonce, input)
        .map_err(|e| PairingError::Crypto(format!("AES-GCM decrypt: {e}")))
    }
  }
}
