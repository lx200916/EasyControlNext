//! Node-API surface for the HarmonyOS controller.
//!
//! Keep exports coarse and binary-safe. Live ADB session multiplexing stays in Rust
//! (`easycontrol-adb-client`) and is not driven packet-by-packet from ArkTS.

use std::time::Duration;

use base64::Engine;
use easycontrol_adb_client::{
  build_sync_push, connect_tcp, normalize_pair_code, pair_wireless, AdbSession, RsaAdbSigner,
  SessionIo, SessionState,
};
use easycontrol_protocol::adb;
use easycontrol_protocol::control;
use easycontrol_protocol::video;
use easycontrol_protocol::PROTOCOL_VERSION;
use napi_derive_ohos::napi;
use napi_ohos::bindgen_prelude::*;

#[cfg(target_env = "ohos")]
mod ohos_vdec;
#[cfg(target_env = "ohos")]
mod ohos_adec;

mod live_session;

/// Diagnostic version string (`protocol` crate version).
#[napi]
pub fn native_version() -> String {
  PROTOCOL_VERSION.to_string()
}

/// Coarse capability banner for ArkTS diagnostics.
#[napi]
pub fn native_capabilities() -> String {
  "protocol+adb_client_session+oh_videodecoder+oh_audiodecoder+live_gate_d+adb_screencap+adb_shell+adb_sync_pull+adb_pair_wireless+adb_stls_tls+live_pts_fix+vdec_render_at_time; rsa_pem_napi; spake2_boringssl; test_signer=deterministic"
    .to_string()
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

/// Parse EasyControl video stream header + CSD frames (length-prefixed, BE).
#[napi]
pub fn parse_video_stream_header(input: Buffer) -> Result<VideoHeaderJs> {
  let (hdr, consumed) = video::parse_video_stream_header(input.as_ref())
    .map_err(|e| Error::from_reason(e.to_string()))?;
  let csd0_payload = video::strip_pts_prefix(&hdr.csd0)
    .map_err(|e| Error::from_reason(e.to_string()))?
    .to_vec();
  let csd0_annex_b = video::looks_like_annex_b(&csd0_payload);
  let csd1_payload = match &hdr.csd1 {
    Some(raw) => Some(
      video::strip_pts_prefix(raw)
        .map_err(|e| Error::from_reason(e.to_string()))?
        .to_vec(),
    ),
    None => None,
  };
  Ok(VideoHeaderJs {
    use_h265: hdr.use_h265,
    width: hdr.width,
    height: hdr.height,
    csd0: Buffer::from(csd0_payload),
    csd1: csd1_payload.map(Buffer::from),
    csd0_annex_b,
    consumed: consumed as u32,
  })
}

#[napi(object)]
pub struct VideoHeaderJs {
  pub use_h265: bool,
  pub width: u32,
  pub height: u32,
  /// CSD0 NAL bytes with PTS prefix stripped.
  pub csd0: Buffer,
  /// CSD1 NAL bytes with PTS prefix stripped (AVC only).
  pub csd1: Option<Buffer>,
  pub csd0_annex_b: bool,
  pub consumed: u32,
}

/// Parse one length-prefixed H.264/H.265 access unit (`len` + `pts` + NAL payload).
#[napi]
pub fn parse_video_access_unit(input: Buffer) -> Result<VideoAccessUnitJs> {
  let (au, consumed) = video::parse_video_access_unit(input.as_ref())
    .map_err(|e| Error::from_reason(e.to_string()))?;
  Ok(VideoAccessUnitJs {
    pts_us: au.pts_us,
    payload: Buffer::from(au.payload.clone()),
    annex_b: video::looks_like_annex_b(&au.payload),
    consumed: consumed as u32,
  })
}

#[napi(object)]
pub struct VideoAccessUnitJs {
  pub pts_us: i64,
  pub payload: Buffer,
  pub annex_b: bool,
  pub consumed: u32,
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

#[napi(object)]
pub struct VideoDecoderStatusJs {
  pub started: bool,
  pub first_frame_rendered: bool,
  pub input_queued: u32,
  pub output_frames: u32,
  pub stream_changed: u32,
  pub last_error: i32,
  pub width: u32,
  pub height: u32,
  pub use_h265: bool,
  pub surface_id: String,
  pub detail: String,
}

fn status_from_snapshot(s: ohos_vdec_stub::StatusSnapshot) -> VideoDecoderStatusJs {
  VideoDecoderStatusJs {
    started: s.started,
    first_frame_rendered: s.first_frame_rendered,
    input_queued: s.input_queued,
    output_frames: s.output_frames,
    stream_changed: s.stream_changed,
    last_error: s.last_error,
    width: s.width,
    height: s.height,
    use_h265: s.use_h265,
    surface_id: s.surface_id,
    detail: s.detail,
  }
}

/// Start OH_VideoDecoder against an XComponent surfaceId and feed an EasyControl bitstream
/// (header + CSD + AUs). Returns immediate start status; poll / wait for first frame.
#[napi]
pub fn video_decoder_play_bitstream(
  surface_id: String,
  bitstream: Buffer,
) -> Result<VideoDecoderStatusJs> {
  #[cfg(target_env = "ohos")]
  {
    let snap = ohos_vdec::play_easycontrol_bitstream(&surface_id, bitstream.as_ref())
      .map_err(Error::from_reason)?;
    return Ok(status_from_snapshot(snap));
  }
  #[cfg(not(target_env = "ohos"))]
  {
    let _ = (surface_id, bitstream);
    Err(Error::from_reason(
      "video_decoder_play_bitstream requires OHOS target",
    ))
  }
}

/// Block up to `timeout_ms` waiting for first rendered output buffer (decoder callbacks).
#[napi]
pub fn video_decoder_wait_first_frame(timeout_ms: u32) -> VideoDecoderStatusJs {
  #[cfg(target_env = "ohos")]
  {
    return status_from_snapshot(ohos_vdec::wait_first_frame(timeout_ms));
  }
  #[cfg(not(target_env = "ohos"))]
  {
    let _ = timeout_ms;
    status_from_snapshot(ohos_vdec_stub::StatusSnapshot::default_idle(
      "host stub: no OH_VideoDecoder",
    ))
  }
}

#[napi]
pub fn video_decoder_status() -> VideoDecoderStatusJs {
  #[cfg(target_env = "ohos")]
  {
    return status_from_snapshot(ohos_vdec::snapshot());
  }
  #[cfg(not(target_env = "ohos"))]
  {
    status_from_snapshot(ohos_vdec_stub::StatusSnapshot::default_idle("host stub"))
  }
}

#[napi]
pub fn video_decoder_release() {
  #[cfg(target_env = "ohos")]
  {
    ohos_vdec::release();
  }
}

#[napi(object)]
pub struct DecoderCapsJs {
  pub avc: bool,
  pub hevc: bool,
  pub opus: bool,
  pub aac: bool,
  pub detail: String,
}

fn probe_label(ok: std::result::Result<(), String>) -> (bool, String) {
  match ok {
    Ok(()) => (true, "ok".into()),
    Err(e) => (false, e),
  }
}

/// JS-thread probe: `OH_VideoDecoder` / `OH_AudioCodec` CreateByMime + Destroy.
/// Independent of a live session (does not bind a surface or replace STATE).
#[napi]
pub fn probe_decoder_caps() -> DecoderCapsJs {
  #[cfg(target_env = "ohos")]
  {
    let (avc, avc_d) = probe_label(ohos_vdec::probe_create(false));
    let (hevc, hevc_d) = probe_label(ohos_vdec::probe_create(true));
    let (opus, opus_d) = probe_label(ohos_adec::probe_create(true));
    let (aac, aac_d) = probe_label(ohos_adec::probe_create(false));
    let detail = format!("avc={avc_d}; hevc={hevc_d}; opus={opus_d}; aac={aac_d}");
    return DecoderCapsJs {
      avc,
      hevc,
      opus,
      aac,
      detail,
    };
  }
  #[cfg(not(target_env = "ohos"))]
  {
    DecoderCapsJs {
      avc: false,
      hevc: false,
      opus: false,
      aac: false,
      detail: "host stub: no OH_VideoDecoder".into(),
    }
  }
}

/// Rebind OH_VideoDecoder to a new XComponent surfaceId after fold/layout recreate.
/// Keeps the live AU feed / ADB session intact — media surface only.
#[napi]
pub fn video_decoder_rebind_surface(surface_id: String) -> Result<VideoDecoderStatusJs> {
  #[cfg(target_env = "ohos")]
  {
    let snap = ohos_vdec::rebind_surface(&surface_id).map_err(Error::from_reason)?;
    return Ok(status_from_snapshot(snap));
  }
  #[cfg(not(target_env = "ohos"))]
  {
    let _ = surface_id;
    Err(Error::from_reason(
      "video_decoder_rebind_surface requires OHOS target",
    ))
  }
}

#[napi(object)]
pub struct LiveSessionStartJs {
  pub host: String,
  pub adb_port: u32,
  pub server_port: u32,
  pub surface_id: String,
  pub jar_bytes: Buffer,
  pub private_key_pem: String,
  pub public_key_line: Option<Buffer>,
  pub app_version_code: u32,
  pub max_size: u32,
  pub max_fps: u32,
  pub max_video_bit: u32,
  pub listen_clip: bool,
  pub is_audio: bool,
  pub keep_awake: bool,
  pub support_h265: bool,
  pub virtual_width: u32,
  pub virtual_height: u32,
  pub virtual_dpi: u32,
}

#[napi(object)]
pub struct LiveSessionStatusJs {
  pub phase: String,
  pub detail: String,
  pub mode: String,
  pub width: u32,
  pub height: u32,
  pub use_h265: bool,
  pub aus_fed: u32,
  pub first_frame: bool,
  pub live: bool,
  pub can_audio: bool,
  pub use_opus: bool,
  pub audio_started: bool,
  pub audio_frames: u32,
  pub audio_detail: String,
}

fn live_status_js(s: live_session::LiveStatus) -> LiveSessionStatusJs {
  LiveSessionStatusJs {
    phase: s.phase.as_str().to_string(),
    detail: s.detail,
    mode: s.mode,
    width: s.width,
    height: s.height,
    use_h265: s.use_h265,
    aus_fed: s.aus_fed,
    first_frame: s.first_frame,
    live: s.live,
    can_audio: s.can_audio,
    use_opus: s.use_opus,
    audio_started: s.audio_started,
    audio_frames: s.audio_frames,
    audio_detail: s.audio_detail,
  }
}

/// Start on-device Gate D live mirror (background thread). Poll [`live_session_status`].
///
/// `video_source` / `camera_facing` / `start_app` are **separate string args** (not object
/// fields): ArkTS→ohos-rs object binding was dropping those properties (server always got
/// `startApp=` empty / `videoSource=display` defaults).
#[napi]
pub fn live_session_start(
  opts: LiveSessionStartJs,
  video_source: String,
  camera_facing: String,
  start_app: String,
) -> Result<LiveSessionStatusJs> {
  let pub_line = opts.public_key_line.map(|b| b.to_vec());
  let video_source = {
    let v = video_source.trim();
    if v.is_empty() {
      "display".into()
    } else {
      v.to_string()
    }
  };
  let camera_facing = {
    let v = camera_facing.trim();
    if v.is_empty() {
      "back".into()
    } else {
      v.to_string()
    }
  };
  let start_app = start_app.trim().to_string();
  eprintln!(
    "[napi live_session_start] src={video_source} facing={camera_facing} start_app='{start_app}' vd={}x{}@{}",
    opts.virtual_width, opts.virtual_height, opts.virtual_dpi
  );
  let req = live_session::LiveStartRequest {
    host: opts.host,
    adb_port: opts.adb_port as u16,
    server_port: opts.server_port as u16,
    surface_id: opts.surface_id,
    jar_bytes: opts.jar_bytes.to_vec(),
    private_key_pem: opts.private_key_pem,
    public_key_line: pub_line,
    app_version_code: opts.app_version_code,
    max_size: if opts.max_size > 0 { opts.max_size } else { 1600 },
    max_fps: if opts.max_fps > 0 { opts.max_fps } else { 60 },
    max_video_bit: if opts.max_video_bit > 0 {
      opts.max_video_bit
    } else {
      4
    },
    listen_clip: opts.listen_clip,
    is_audio: opts.is_audio,
    keep_awake: opts.keep_awake,
    support_h265: opts.support_h265,
    video_source,
    camera_facing,
    virtual_width: opts.virtual_width,
    virtual_height: opts.virtual_height,
    virtual_dpi: opts.virtual_dpi,
    start_app,
  };
  let st = live_session::start(req).map_err(Error::from_reason)?;
  Ok(live_status_js(st))
}

#[napi]
pub fn live_session_status() -> LiveSessionStatusJs {
  live_status_js(live_session::status())
}

/// Create OH_VideoDecoder on the JS/NAPI thread after live session reaches `configuring`.
#[napi]
pub fn live_session_attach_decoder() -> Result<LiveSessionStatusJs> {
  let st = live_session::attach_decoder().map_err(Error::from_reason)?;
  Ok(live_status_js(st))
}

/// Write a control packet (touch/keepalive) on the live main TCP socket.
#[napi]
pub fn live_session_write_control(packet: Buffer) -> Result<bool> {
  live_session::write_control(packet.as_ref()).map_err(Error::from_reason)?;
  Ok(true)
}

#[napi]
pub fn live_session_stop() {
  live_session::stop();
}

#[napi(object)]
pub struct AdbAuthOptsJs {
  pub host: String,
  pub adb_port: u32,
  pub private_key_pem: String,
  pub public_key_line: Option<Buffer>,
}

fn adb_connect_authed(opts: &AdbAuthOptsJs) -> Result<AdbSession<SessionIo>> {
  let port = opts.adb_port as u16;
  if opts.host.is_empty() || port == 0 {
    return Err(Error::from_reason("host/adbPort required"));
  }
  let pub_line = opts.public_key_line.as_ref().map(|b| b.to_vec());
  let signer = RsaAdbSigner::from_pkcs8_pem_and_pub(
    &opts.private_key_pem,
    pub_line.as_deref(),
    "easycontrol@harmonyos",
  )
  .map_err(|e| Error::from_reason(e.to_string()))?;
  let stream = connect_tcp(&opts.host, port, Duration::from_secs(8))
    .map_err(|e| Error::from_reason(e.to_string()))?;
  let session = AdbSession::connect_with_key(
    stream,
    &signer,
    &opts.private_key_pem,
    &opts.host,
    Duration::from_secs(20),
  )
  .map_err(|e| Error::from_reason(e.to_string()))?;
  if session.state() != SessionState::Connected {
    return Err(Error::from_reason("adb not connected"));
  }
  Ok(session)
}

fn shell_cmd_safe(cmd: &str) -> Result<()> {
  if cmd.is_empty() || cmd.len() > 4000 {
    return Err(Error::from_reason("shell command empty or too long"));
  }
  // Reject obvious chaining / redirection injection for picker/launch helpers.
  if cmd.contains('\0') || cmd.contains('\n') || cmd.contains('\r') {
    return Err(Error::from_reason("shell command has illegal newlines"));
  }
  Ok(())
}

/// Short-lived ADB `shell:<cmd>` (separate TCP from Gate D live session).
/// Used for list packages / monkey launch / similar controller helpers.
#[napi]
pub fn adb_shell_exec(opts: AdbAuthOptsJs, command: String) -> Result<String> {
  shell_cmd_safe(&command)?;
  let mut session = adb_connect_authed(&opts)?;
  let out = session
    .shell(&command)
    .map_err(|e| Error::from_reason(e.to_string()))?;
  Ok(String::from_utf8_lossy(&out).into_owned())
}

/// Short-lived ADB connect → `screencap -p` via base64 (avoids PTY CRLF mangling).
/// Does not touch the live Gate D session. Returns PNG bytes or an error reason.
#[napi]
pub fn adb_screencap_png(opts: AdbAuthOptsJs) -> Result<Buffer> {
  let mut session = adb_connect_authed(&opts)?;
  // base64 avoids shell PTY turning PNG 0x0A into 0x0D 0x0A.
  let out = session
    .shell("screencap -p 2>/dev/null | base64")
    .map_err(|e| Error::from_reason(e.to_string()))?;
  let text = String::from_utf8_lossy(&out);
  let cleaned: String = text.chars().filter(|c| !c.is_whitespace()).collect();
  if cleaned.is_empty() {
    return Err(Error::from_reason("screencap empty (shell/base64)"));
  }
  let png = base64::engine::general_purpose::STANDARD
    .decode(cleaned.as_bytes())
    .map_err(|e| Error::from_reason(format!("base64 decode: {e}")))?;
  if png.len() < 8 || &png[0..8] != b"\x89PNG\r\n\x1a\n" {
    return Err(Error::from_reason(format!(
      "not a PNG ({} bytes) — screencap may be denied",
      png.len()
    )));
  }
  Ok(Buffer::from(png))
}

#[napi(object)]
pub struct SyncPullResultJs {
  pub data: Buffer,
  pub sha256_hex: String,
  pub remote_path: String,
  pub mtime: u32,
  pub byte_len: u32,
}

/// Short-lived ADB `sync:` RECV pull. Separate TCP from Gate D live session.
/// Caps at 32 MiB. `remote_path` must be absolute (e.g. `/sdcard/Download/a.png`).
#[napi]
pub fn adb_sync_pull(opts: AdbAuthOptsJs, remote_path: String) -> Result<SyncPullResultJs> {
  let mut session = adb_connect_authed(&opts)?;
  let pulled = session
    .sync_pull(&remote_path)
    .map_err(|e| Error::from_reason(e.to_string()))?;
  let byte_len = pulled.data.len() as u32;
  Ok(SyncPullResultJs {
    data: Buffer::from(pulled.data),
    sha256_hex: pulled.sha256_hex,
    remote_path: pulled.remote_path,
    mtime: pulled.mtime,
    byte_len,
  })
}

#[napi(object)]
pub struct AdbPairOptsJs {
  pub host: String,
  pub pair_port: u32,
  pub pair_code: String,
  pub private_key_pem: String,
  pub public_key_line: Option<Buffer>,
  pub device_name: Option<String>,
  /// Timeout seconds (default 20).
  pub timeout_sec: Option<u32>,
}

#[napi(object)]
pub struct AdbPairResultJs {
  pub ok: bool,
  pub host: String,
  pub pair_port: u32,
  pub detail: String,
}

/// Android 11+ wireless debugging pairing (TLS 1.3 + SPAKE2-25519 + peer-info).
/// Manual path: host + temporary pairing port + 6-digit code.
#[napi]
pub fn adb_pair_wireless(opts: AdbPairOptsJs) -> Result<AdbPairResultJs> {
  let port = opts.pair_port as u16;
  if opts.host.trim().is_empty() || port == 0 {
    return Err(Error::from_reason("host/pairPort required"));
  }
  let code = normalize_pair_code(&opts.pair_code);
  if code.is_empty() {
    return Err(Error::from_reason("pairing code empty"));
  }
  let pub_line = opts.public_key_line.map(|b| b.to_vec());
  let name = opts
    .device_name
    .filter(|s| !s.trim().is_empty())
    .unwrap_or_else(|| "EasyControlNext".to_string());
  let timeout_sec = opts.timeout_sec.unwrap_or(20).max(5) as u64;
  match pair_wireless(
    opts.host.trim(),
    port,
    &code,
    &opts.private_key_pem,
    pub_line.as_deref(),
    &name,
    Duration::from_secs(timeout_sec),
  ) {
    Ok(r) => Ok(AdbPairResultJs {
      ok: true,
      host: r.host,
      pair_port: r.pair_port as u32,
      detail: r.detail,
    }),
    Err(e) => Err(Error::from_reason(e.to_string())),
  }
}

/// Normalize pairing code (strip whitespace) — mirrors Android `AdbTools.normalizePairCode`.
#[napi]
pub fn adb_normalize_pair_code(pair_code: String) -> String {
  normalize_pair_code(&pair_code)
}

/// Tiny host-compile shim so `StatusSnapshot` typing works in cfg stubs.
mod ohos_vdec_stub {
  #[cfg(target_env = "ohos")]
  pub use super::ohos_vdec::StatusSnapshot;

  #[cfg(not(target_env = "ohos"))]
  #[derive(Clone, Debug)]
  pub struct StatusSnapshot {
    pub started: bool,
    pub first_frame_rendered: bool,
    pub input_queued: u32,
    pub output_frames: u32,
    pub stream_changed: u32,
    pub last_error: i32,
    pub width: u32,
    pub height: u32,
    pub use_h265: bool,
    pub surface_id: String,
    pub detail: String,
  }

  #[cfg(not(target_env = "ohos"))]
  impl StatusSnapshot {
    pub fn default_idle(detail: &str) -> Self {
      Self {
        started: false,
        first_frame_rendered: false,
        input_queued: 0,
        output_frames: 0,
        stream_changed: 0,
        last_error: 0,
        width: 0,
        height: 0,
        use_h265: false,
        surface_id: String::new(),
        detail: detail.to_string(),
      }
    }
  }
}
