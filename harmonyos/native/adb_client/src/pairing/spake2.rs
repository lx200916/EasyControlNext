//! BoringSSL / AOSP SPAKE2-25519 (adb pairing-auth compatible).
//!
//! Ported from BoringSSL `crypto/curve25519/spake25519.cc` and verified against
//! Flyfish233/spake2-java BoringSSL oracle vectors. Uses curve25519-dalek for
//! Edwards arithmetic plus a raw 256-bit scalar multiply that preserves bit 255
//! after the AOSP cofactor `left_shift3` (RustCrypto `spake2` is NOT wire-compatible).

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::{CompressedEdwardsY, EdwardsPoint};
use curve25519_dalek::scalar::Scalar;
use curve25519_dalek::traits::Identity;
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha512};
use zeroize::{Zeroize, ZeroizeOnDrop};

use super::{PairingError, PairingResult};

pub const MAX_MSG_SIZE: usize = 32;
pub const MAX_KEY_SIZE: usize = 64;

/// BoringSSL M point (compressed Edwards Y).
const M_POINT_ENCODED: [u8; 32] = [
  0x5a, 0xda, 0x7e, 0x4b, 0xf6, 0xdd, 0xd9, 0xad, 0xb6, 0x62, 0x6d, 0x32, 0x13, 0x1c, 0x6b, 0x5c,
  0x51, 0xa1, 0xe3, 0x47, 0xa3, 0x47, 0x8f, 0x53, 0xcf, 0xcf, 0x44, 0x1b, 0x88, 0xee, 0xd1, 0x2e,
];
/// BoringSSL N point (compressed Edwards Y).
const N_POINT_ENCODED: [u8; 32] = [
  0x10, 0xe3, 0xdf, 0x0a, 0xe3, 0x7d, 0x8e, 0x7a, 0x99, 0xb5, 0xfe, 0x74, 0xb4, 0x46, 0x72, 0x10,
  0x3d, 0xbd, 0xdc, 0xbd, 0x06, 0xaf, 0x68, 0x0d, 0x71, 0x32, 0x9a, 0x11, 0x69, 0x3b, 0xc7, 0x78,
];
/// Ed25519 prime-order subgroup order L (little-endian).
const GROUP_ORDER: [u8; 32] = [
  0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Spake2Role {
  Alice,
  Bob,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
  Init,
  MsgGenerated,
}

#[derive(Zeroize, ZeroizeOnDrop)]
pub struct Spake2Context {
  my_name: Vec<u8>,
  their_name: Vec<u8>,
  #[zeroize(skip)]
  role: Spake2Role,
  private_key: [u8; 32],
  my_msg: [u8; 32],
  password_scalar: [u8; 32],
  password_hash: [u8; 64],
  #[zeroize(skip)]
  state: State,
  #[zeroize(skip)]
  disable_password_scalar_hack: bool,
}

impl Spake2Context {
  pub fn new(role: Spake2Role, my_name: &[u8], their_name: &[u8]) -> PairingResult<Self> {
    if my_name.is_empty() || their_name.is_empty() {
      return Err(PairingError::InvalidInput("SPAKE2 participant names required"));
    }
    if my_name.len() > 4096 || their_name.len() > 4096 {
      return Err(PairingError::InvalidInput("SPAKE2 participant name too large"));
    }
    Ok(Self {
      my_name: my_name.to_vec(),
      their_name: their_name.to_vec(),
      role,
      private_key: [0u8; 32],
      my_msg: [0u8; 32],
      password_scalar: [0u8; 32],
      password_hash: [0u8; 64],
      state: State::Init,
      disable_password_scalar_hack: false,
    })
  }

  pub fn generate_message(&mut self, password: &[u8]) -> PairingResult<[u8; 32]> {
    let mut private_tmp = [0u8; 64];
    OsRng.fill_bytes(&mut private_tmp);
    let out = self.generate_message_with_private(password, &private_tmp);
    private_tmp.zeroize();
    out
  }

  /// Deterministic path for oracle-vector tests (`private_tmp` = 64 random bytes).
  pub fn generate_message_with_private(
    &mut self,
    password: &[u8],
    private_tmp: &[u8; 64],
  ) -> PairingResult<[u8; 32]> {
    if password.is_empty() {
      return Err(PairingError::InvalidInput("SPAKE2 password empty"));
    }
    if self.state != State::Init {
      return Err(PairingError::Protocol("SPAKE2 message already generated".into()));
    }

    let mut reduced_private = Scalar::from_bytes_mod_order_wide(private_tmp).to_bytes();
    left_shift3(&mut reduced_private);
    self.private_key = reduced_private;

    let native_p = multiply_by_raw_scalar(&ED25519_BASEPOINT_POINT, &self.private_key);

    let mut password_tmp = Sha512::digest(password);
    self.password_hash.copy_from_slice(&password_tmp);
    let mut reduced_pw = Scalar::from_bytes_mod_order_wide(password_tmp.as_ref()).to_bytes();
    password_tmp.zeroize();
    let hardened = harden_password_scalar(&reduced_pw, self.disable_password_scalar_hack);
    reduced_pw.zeroize();
    self.password_scalar = hardened;

    let mask_base = match self.role {
      Spake2Role::Alice => decompress_point(&M_POINT_ENCODED)?,
      Spake2Role::Bob => decompress_point(&N_POINT_ENCODED)?,
    };
    let native_mask = multiply_by_raw_scalar(&mask_base, &self.password_scalar);
    let native_p_star = native_p + native_mask;
    self.my_msg = native_p_star.compress().to_bytes();
    self.state = State::MsgGenerated;
    Ok(self.my_msg)
  }

  pub fn msg(&self) -> &[u8; 32] {
    &self.my_msg
  }

  pub fn process_message(&mut self, their_msg: &[u8]) -> PairingResult<[u8; 64]> {
    if self.state != State::MsgGenerated {
      return Err(PairingError::Protocol("SPAKE2 process before generate".into()));
    }
    if their_msg.len() != MAX_MSG_SIZE {
      return Err(PairingError::InvalidInput("SPAKE2 peer message must be 32 bytes"));
    }
    let peer_msg: [u8; 32] = their_msg.try_into().unwrap();
    let native_q_star = decompress_point(&peer_msg)?;
    let peers_mask_base = match self.role {
      Spake2Role::Alice => decompress_point(&N_POINT_ENCODED)?,
      Spake2Role::Bob => decompress_point(&M_POINT_ENCODED)?,
    };
    let native_peers_mask = multiply_by_raw_scalar(&peers_mask_base, &self.password_scalar);
    let native_q_ext = native_q_star - native_peers_mask;
    let mut dh_shared = multiply_by_raw_scalar(&native_q_ext, &self.private_key)
      .compress()
      .to_bytes();

    let mut sha = Sha512::new();
    match self.role {
      Spake2Role::Alice => {
        update_with_length_prefix(&mut sha, &self.my_name);
        update_with_length_prefix(&mut sha, &self.their_name);
        update_with_length_prefix(&mut sha, &self.my_msg);
        update_with_length_prefix(&mut sha, &peer_msg);
      }
      Spake2Role::Bob => {
        update_with_length_prefix(&mut sha, &self.their_name);
        update_with_length_prefix(&mut sha, &self.my_name);
        update_with_length_prefix(&mut sha, &peer_msg);
        update_with_length_prefix(&mut sha, &self.my_msg);
      }
    }
    update_with_length_prefix(&mut sha, &dh_shared);
    update_with_length_prefix(&mut sha, &self.password_hash);
    dh_shared.zeroize();

    let key_bytes = sha.finalize();
    let mut key = [0u8; 64];
    key.copy_from_slice(&key_bytes);
    // Wipe secrets after successful derivation (BoringSSL frees the CTX).
    self.private_key.zeroize();
    self.password_scalar.zeroize();
    self.password_hash.zeroize();
    Ok(key)
  }
}

fn decompress_point(encoded: &[u8; 32]) -> PairingResult<EdwardsPoint> {
  CompressedEdwardsY(*encoded)
    .decompress()
    .ok_or_else(|| PairingError::Crypto("SPAKE2 point not on curve".into()))
}

fn left_shift3(n: &mut [u8; 32]) {
  let mut carry = 0u8;
  for b in n.iter_mut() {
    let next_carry = *b >> 5;
    *b = (*b << 3) | carry;
    carry = next_carry;
  }
}

fn add_le32(a: &mut [u8; 32], b: &[u8; 32]) {
  let mut carry = 0u16;
  for i in 0..32 {
    let sum = a[i] as u16 + b[i] as u16 + carry;
    a[i] = sum as u8;
    carry = sum >> 8;
  }
}

fn dbl_le32(n: &mut [u8; 32]) {
  let mut carry = 0u8;
  for b in n.iter_mut() {
    let next = *b >> 7;
    *b = (*b << 1) | carry;
    carry = next;
  }
}

/// BoringSSL password-scalar hack: clear low 3 bits by adding L / 2L / 4L.
fn harden_password_scalar(reduced: &[u8; 32], disable: bool) -> [u8; 32] {
  let mut password_scalar = *reduced;
  if disable {
    return password_scalar;
  }
  let mut order = GROUP_ORDER;
  let mut tmp = [0u8; 32];
  if password_scalar[0] & 1 == 1 {
    tmp = order;
  }
  add_le32(&mut password_scalar, &tmp);
  dbl_le32(&mut order);
  tmp = [0u8; 32];
  if password_scalar[0] & 2 == 2 {
    tmp = order;
  }
  add_le32(&mut password_scalar, &tmp);
  dbl_le32(&mut order);
  tmp = [0u8; 32];
  if password_scalar[0] & 4 == 4 {
    tmp = order;
  }
  add_le32(&mut password_scalar, &tmp);
  password_scalar
}

/// Multiply Edwards point by a raw 256-bit LE scalar (preserves bit 255).
fn multiply_by_raw_scalar(point: &EdwardsPoint, scalar: &[u8; 32]) -> EdwardsPoint {
  let mut table = [EdwardsPoint::identity(); 16];
  table[0] = EdwardsPoint::identity();
  for i in 1..16 {
    table[i] = table[i - 1] + *point;
  }
  let mut result = EdwardsPoint::identity();
  for byte_index in (0..32).rev() {
    let value = scalar[byte_index];
    result = multiply_by_16(result);
    result += select_point(&table, (value >> 4) & 0x0f);
    result = multiply_by_16(result);
    result += select_point(&table, value & 0x0f);
  }
  result
}

fn multiply_by_16(point: EdwardsPoint) -> EdwardsPoint {
  let mut result = point;
  for _ in 0..4 {
    result = result + result;
  }
  result
}

fn select_point(table: &[EdwardsPoint; 16], digit: u8) -> EdwardsPoint {
  // Variable-time select is fine for pairing (password already low-entropy).
  table[digit as usize]
}

fn update_with_length_prefix(sha: &mut Sha512, data: &[u8]) {
  let len = data.len() as u64;
  sha.update(&len.to_le_bytes());
  sha.update(data);
}

#[cfg(test)]
mod tests {
  use super::*;

  fn hex_to_bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
      .step_by(2)
      .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
      .collect()
  }

  fn hex32(hex: &str) -> [u8; 32] {
    let v = hex_to_bytes(hex);
    let mut out = [0u8; 32];
    out.copy_from_slice(&v);
    out
  }

  fn hex64(hex: &str) -> [u8; 64] {
    let v = hex_to_bytes(hex);
    let mut out = [0u8; 64];
    out.copy_from_slice(&v);
    out
  }

  /// BoringSSL oracle vector `normal` from Flyfish233/spake2-java.
  #[test]
  fn boringssl_oracle_normal_exchange() {
    let password = hex_to_bytes("353135313039");
    let alice_priv = hex64(
      "01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    );
    let bob_priv = hex64(
      "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f0000000000000000000000000000000000000000000000000000000000000000",
    );

    let mut alice = Spake2Context::new(Spake2Role::Alice, b"alice", b"bob").unwrap();
    let alice_msg = alice
      .generate_message_with_private(&password, &alice_priv)
      .unwrap();
    assert_eq!(
      alice_msg,
      hex32("1876811ed2c78beb885abcfeee9174e822e056d67474d7f924e5c019d087dc71")
    );

    let mut bob = Spake2Context::new(Spake2Role::Bob, b"bob", b"alice").unwrap();
    let bob_msg = bob
      .generate_message_with_private(&password, &bob_priv)
      .unwrap();
    assert_eq!(
      bob_msg,
      hex32("e814a51e5e1032ce32bd9e47f74fb58a42f02b61b355e062a36836dbd8de35c5")
    );

    let alice_key = alice.process_message(&bob_msg).unwrap();
    let bob_key = bob.process_message(&alice_msg).unwrap();
    let expected = hex64(
      "f1e5cb026ca1dc0780d629cd1747b834bceed4b05417b80f2133a2bd0a0e8b21c1467782f8cab09ba0a20c4a785029dc95c028e20deff35812c01a3a0d8e9cb2",
    );
    assert_eq!(alice_key, expected);
    assert_eq!(bob_key, expected);
  }

  #[test]
  fn adb_names_roundtrip_random() {
    let pw = b"123456\0extra";
    let mut alice =
      Spake2Context::new(Spake2Role::Alice, b"adb pair client\0", b"adb pair server\0").unwrap();
    let mut bob =
      Spake2Context::new(Spake2Role::Bob, b"adb pair server\0", b"adb pair client\0").unwrap();
    let a_msg = alice.generate_message(pw).unwrap();
    let b_msg = bob.generate_message(pw).unwrap();
    let a_key = alice.process_message(&b_msg).unwrap();
    let b_key = bob.process_message(&a_msg).unwrap();
    assert_eq!(a_key, b_key);
  }
}
