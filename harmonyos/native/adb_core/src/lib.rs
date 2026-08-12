//! Node-API surface for the HarmonyOS controller.
//!
//! Keep exports coarse and binary-safe. Live ADB session multiplexing stays in Rust
//! (`easycontrol-adb-client`) and is not driven packet-by-packet from ArkTS.

use easycontrol_adb_client::build_sync_push;
use easycontrol_protocol::adb;
use easycontrol_protocol::control;
use easycontrol_protocol::PROTOCOL_VERSION;
use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::*;

/// Diagnostic version string (`protocol` crate version).
#[napi]
pub fn native_version() -> String {
  PROTOCOL_VERSION.to_string()
}

/// Coarse capability banner for ArkTS diagnostics (no live sockets).
#[napi]
pub fn native_capabilities() -> String {
  "protocol+adb_client_session; production_rsa_signer=pending; test_signer=deterministic".to_string()
}

/// Binary-safe round-trip for validating ArrayBuffer/Uint8Array bridging.
#[napi]
pub fn round_trip_bytes(input: Buffer) -> Buffer {
  Buffer::from(input.to_vec())
}

/// Encode a default EasyControl CNXN packet (LE ADB header + `host::\\0`).
#[napi]
pub fn encode_adb_connect() -> Buffer {
  Buffer::from(adb::generate_connect())
}

/// Encode ADB OKAY(local_id, remote_id).
#[napi]
pub fn encode_adb_okay(local_id: u32, remote_id: u32) -> Buffer {
  Buffer::from(adb::generate_okay(local_id, remote_id))
}

/// Encode ADB OPEN(local_id, dest) with trailing NUL.
#[napi]
pub fn encode_adb_open(local_id: u32, dest: String) -> Buffer {
  Buffer::from(adb::generate_open(local_id, &dest))
}

/// Decode one complete ADB message (header + payload). Verifies magic; checksum optional.
#[napi]
pub fn decode_adb_message(input: Buffer, verify_checksum: bool) -> Result<AdbMessageJs> {
  let msg = adb::decode_message(input.as_ref(), verify_checksum)
    .map_err(|e| Error::from_reason(e.to_string()))?;
  Ok(AdbMessageJs {
    command: msg.header.command,
    arg0: msg.header.arg0,
    arg1: msg.header.arg1,
    data_length: msg.header.data_length,
    data_check: msg.header.data_check,
    magic: msg.header.magic,
    payload: Buffer::from(msg.payload),
  })
}

#[napi(object)]
pub struct AdbMessageJs {
  pub command: u32,
  pub arg0: u32,
  pub arg1: u32,
  pub data_length: u32,
  pub data_check: u32,
  pub magic: u32,
  pub payload: Buffer,
}

/// Encode EasyControl keepalive control event (single byte `4`, big-endian channel).
#[napi]
pub fn encode_control_keep_alive() -> Buffer {
  Buffer::from(control::create_keep_alive())
}

/// Encode touch control event (normalized coords).
#[napi]
pub fn encode_control_touch(
  action: u8,
  pointer_id: u8,
  x: f64,
  y: f64,
  offset_time: i32,
) -> Buffer {
  Buffer::from(control::create_touch_event(
    action,
    pointer_id,
    x as f32,
    y as f32,
    offset_time,
  ))
}

/// Encode clipboard control event; rejects empty or >5000 UTF-8 bytes.
#[napi]
pub fn encode_control_clipboard(text: String) -> Result<Buffer> {
  control::create_clipboard_event(&text)
    .map(Buffer::from)
    .map_err(|e| Error::from_reason(e.to_string()))
}

/// Build ADB sync-push stream bytes (SEND/DATA/DONE/QUIT) and SHA-256 hex of file payload.
#[napi]
pub fn build_sync_push_plan(remote_path: String, file_data: Buffer) -> Result<SyncPushPlanJs> {
  let plan = build_sync_push(&remote_path, file_data.as_ref())
    .map_err(|e| Error::from_reason(e.to_string()))?;
  Ok(SyncPushPlanJs {
    bytes: Buffer::from(plan.bytes),
    sha256_hex: plan.sha256_hex,
    file_len: plan.file_len as u32,
    data_chunks: plan.data_chunks as u32,
  })
}

#[napi(object)]
pub struct SyncPushPlanJs {
  pub bytes: Buffer,
  pub sha256_hex: String,
  pub file_len: u32,
  pub data_chunks: u32,
}
