//! On-device Gate D live session: ADB RSA → push jar → app_process → main+video → OH_VideoDecoder.
//!
//! NAPI starts a background thread; ArkTS polls status and writes touch packets to the main socket.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use easycontrol_adb_client::{
  connect_dual, connect_tcp, ensure_server_jar, read_adb_at_least, read_exact_timeout,
  read_video_header_adb, read_video_header_tcp_with_leftover, start_server_shell,
  stop_existing_server, AdbSession, ConnectMode, RsaAdbSigner, ServerLaunchOptions, SessionState,
  DEFAULT_APP_VERSION_CODE,
};
use easycontrol_protocol::control;
use easycontrol_protocol::video::{self, VideoStreamHeader};

#[cfg(target_env = "ohos")]
use crate::ohos_adec;
#[cfg(target_env = "ohos")]
use crate::ohos_vdec;

const MAIN_AUDIO_EVENT: u8 = 1;
const MAIN_CLIPBOARD_EVENT: u8 = 2;
const MAIN_CHANGE_SIZE_EVENT: u8 = 3;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LivePhase {
  Idle,
  Connecting,
  Pushing,
  Launching,
  /// Video header ready — waiting for ArkTS/JS-thread `attach_decoder`.
  Configuring,
  Streaming,
  Error,
  Stopped,
}

impl LivePhase {
  pub fn as_str(&self) -> &'static str {
    match self {
      LivePhase::Idle => "idle",
      LivePhase::Connecting => "connecting",
      LivePhase::Pushing => "pushing",
      LivePhase::Launching => "launching",
      LivePhase::Configuring => "configuring",
      LivePhase::Streaming => "streaming",
      LivePhase::Error => "error",
      LivePhase::Stopped => "stopped",
    }
  }
}

/// Params for OH_VideoDecoder create — must run on the NAPI/JS thread (not live worker).
#[derive(Clone, Debug)]
struct PendingDecoder {
  surface_id: String,
  use_h265: bool,
  width: u32,
  height: u32,
  csd0: Vec<u8>,
  csd1: Option<Vec<u8>>,
}

enum DecoderAttachState {
  Waiting,
  Ready,
  Failed(String),
}

#[derive(Clone, Debug)]
pub struct LiveStatus {
  pub phase: LivePhase,
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

impl Default for LiveStatus {
  fn default() -> Self {
    Self {
      phase: LivePhase::Idle,
      detail: "idle".into(),
      mode: String::new(),
      width: 0,
      height: 0,
      use_h265: false,
      aus_fed: 0,
      first_frame: false,
      live: false,
      can_audio: false,
      use_opus: false,
      audio_started: false,
      audio_frames: 0,
      audio_detail: String::new(),
    }
  }
}

pub struct LiveStartRequest {
  pub host: String,
  pub adb_port: u16,
  pub server_port: u16,
  pub surface_id: String,
  pub jar_bytes: Vec<u8>,
  pub private_key_pem: String,
  pub public_key_line: Option<Vec<u8>>,
  pub app_version_code: u32,
  pub max_size: u32,
  pub max_fps: u32,
  pub max_video_bit: u32,
  pub listen_clip: bool,
  pub is_audio: bool,
  pub keep_awake: bool,
  pub support_h265: bool,
  /// `display` | `camera` (Android ClientStream / Options.videoSource).
  pub video_source: String,
  /// `back` | `front` when video_source=camera.
  pub camera_facing: String,
  pub virtual_width: u32,
  pub virtual_height: u32,
  pub virtual_dpi: u32,
  /// Non-empty → single-app virtual display (Android Options.startApp).
  pub start_app: String,
}

struct Shared {
  status: Mutex<LiveStatus>,
  main_tcp: Mutex<Option<TcpStream>>,
  stop: AtomicBool,
  pending_decoder: Mutex<Option<PendingDecoder>>,
  decoder_attach: Mutex<DecoderAttachState>,
  decoder_cv: Condvar,
}

static SHARED: Mutex<Option<Arc<Shared>>> = Mutex::new(None);
static JOIN: Mutex<Option<JoinHandle<()>>> = Mutex::new(None);
/// Cached RSA signer (PEM parse is redundant on every Connect).
static CACHED_SIGNER: Mutex<Option<(String, Option<Vec<u8>>, Arc<RsaAdbSigner>)>> =
  Mutex::new(None);
#[cfg(target_env = "ohos")]
static FIRST_FRAME_MARKED: AtomicBool = AtomicBool::new(false);

fn set_status(shared: &Shared, mut apply: impl FnMut(&mut LiveStatus)) {
  if let Ok(mut g) = shared.status.lock() {
    apply(&mut g);
  }
}

fn mark(t0: Instant, label: &str) {
  let ms = t0.elapsed().as_millis();
  // Surfaces in HiLog via libc stderr on OHOS / host gate logs.
  eprintln!("[LiveSession] {label} +{ms}ms");
}

fn load_signer(req: &LiveStartRequest) -> Result<Arc<RsaAdbSigner>, String> {
  if let Ok(guard) = CACHED_SIGNER.lock() {
    if let Some((pem, pub_line, signer)) = guard.as_ref() {
      if pem == &req.private_key_pem && pub_line.as_deref() == req.public_key_line.as_deref() {
        return Ok(signer.clone());
      }
    }
  }
  let signer = Arc::new(
    RsaAdbSigner::from_pkcs8_pem_and_pub(
      &req.private_key_pem,
      req.public_key_line.as_deref(),
      "easycontrol@harmonyos",
    )
    .map_err(|e| e.to_string())?,
  );
  if let Ok(mut guard) = CACHED_SIGNER.lock() {
    *guard = Some((
      req.private_key_pem.clone(),
      req.public_key_line.clone(),
      signer.clone(),
    ));
  }
  Ok(signer)
}

/// Parse `ro.build.version.sdk` — first integer token, or -1 if unknown.
fn read_device_sdk(session: &mut AdbSession<std::net::TcpStream>) -> i32 {
  let out = match session.shell("getprop ro.build.version.sdk") {
    Ok(bytes) => String::from_utf8_lossy(&bytes).trim().to_string(),
    Err(_) => return -1,
  };
  let mut digits = String::new();
  for c in out.chars() {
    if c.is_ascii_digit() {
      digits.push(c);
    } else if !digits.is_empty() {
      break;
    }
  }
  if digits.is_empty() {
    return -1;
  }
  digits.parse::<i32>().unwrap_or(-1)
}

/// Mirror Android ClientStream.startServer camera / virtual-display API gates.
fn enforce_source_sdk_gates(
  session: &mut AdbSession<std::net::TcpStream>,
  opts: &ServerLaunchOptions,
) -> Result<(), String> {
  if opts.video_source.eq_ignore_ascii_case("camera") {
    let sdk = read_device_sdk(session);
    if sdk > 0 && sdk < 31 {
      return Err("相机投屏需要被控端 Android 12+".into());
    }
  } else if !opts.start_app.is_empty() {
    let sdk = read_device_sdk(session);
    if sdk > 0 && sdk < 30 {
      return Err("单应用虚拟屏需要被控端 Android 11+".into());
    }
  }
  Ok(())
}

pub fn status() -> LiveStatus {
  let guard = SHARED.lock().unwrap_or_else(|e| e.into_inner());
  match guard.as_ref() {
    Some(s) => {
      let mut st = s.status.lock().map(|g| g.clone()).unwrap_or_default();
      #[cfg(target_env = "ohos")]
      {
        let dec = ohos_vdec::snapshot();
        st.first_frame = dec.first_frame_rendered;
        if dec.width > 0 {
          st.width = dec.width;
          st.height = dec.height;
        }
        if dec.last_error != 0 && st.phase == LivePhase::Streaming {
          st.detail = format!("decode err={} {}", dec.last_error, dec.detail);
        } else if dec.first_frame_rendered && st.phase == LivePhase::Streaming {
          if !FIRST_FRAME_MARKED.swap(true, Ordering::SeqCst) {
            eprintln!(
              "[LiveSession] first_frame {}x{} aus={} out={}",
              st.width, st.height, st.aus_fed, dec.output_frames
            );
          }
          st.detail = format!(
            "live {}x{} aus={} out={}",
            st.width, st.height, st.aus_fed, dec.output_frames
          );
        }
        let aud = ohos_adec::snapshot();
        st.audio_started = aud.started;
        st.audio_frames = aud.output_frames;
        if !aud.detail.is_empty() {
          st.audio_detail = aud.detail;
        }
        if aud.started && st.use_opus != aud.use_opus {
          st.use_opus = aud.use_opus;
        }
      }
      st
    }
    None => LiveStatus::default(),
  }
}

pub fn write_control(bytes: &[u8]) -> Result<(), String> {
  let guard = SHARED.lock().map_err(|_| "session lock".to_string())?;
  let shared = guard.as_ref().ok_or("no live session")?;
  let mut main = shared
    .main_tcp
    .lock()
    .map_err(|_| "main lock".to_string())?;
  let sock = main.as_mut().ok_or("main socket not ready (direct TCP only for touch)")?;
  sock.write_all(bytes).map_err(|e| e.to_string())?;
  Ok(())
}

fn request_decoder_attach(shared: &Shared, pending: PendingDecoder) -> Result<(), String> {
  set_status(shared, |st| {
    st.phase = LivePhase::Configuring;
    st.width = pending.width;
    st.height = pending.height;
    st.use_h265 = pending.use_h265;
    st.detail = format!(
      "await JS decoder {}x{} h265={}",
      pending.width, pending.height, pending.use_h265
    );
    st.live = true;
  });
  if let Ok(mut g) = shared.pending_decoder.lock() {
    *g = Some(pending);
  } else {
    return Err("pending_decoder lock poisoned".into());
  }
  if let Ok(mut g) = shared.decoder_attach.lock() {
    *g = DecoderAttachState::Waiting;
  }
  shared.decoder_cv.notify_all();
  Ok(())
}

fn wait_decoder_attach(shared: &Shared, timeout: Duration) -> Result<(), String> {
  let deadline = Instant::now() + timeout;
  let mut guard = shared
    .decoder_attach
    .lock()
    .map_err(|_| "decoder_attach lock poisoned".to_string())?;
  loop {
    if shared.stop.load(Ordering::SeqCst) {
      return Err("stopped while waiting for decoder attach".into());
    }
    match &*guard {
      DecoderAttachState::Ready => return Ok(()),
      DecoderAttachState::Failed(msg) => return Err(format!("decoder attach: {msg}")),
      DecoderAttachState::Waiting => {}
    }
    let now = Instant::now();
    if now >= deadline {
      return Err("decoder attach timeout (JS thread did not call liveSessionAttachDecoder)".into());
    }
    let wait = deadline.saturating_duration_since(now).min(Duration::from_millis(50));
    let (g, _) = shared
      .decoder_cv
      .wait_timeout(guard, wait)
      .map_err(|_| "decoder_cv wait poisoned".to_string())?;
    guard = g;
  }
}

/// Create OH_VideoDecoder on the calling (NAPI/JS) thread using stashed CSD.
/// ArkTS must invoke this when status.phase == "configuring".
pub fn attach_decoder() -> Result<LiveStatus, String> {
  let shared = {
    let g = SHARED.lock().map_err(|_| "session lock".to_string())?;
    g.as_ref().cloned().ok_or("no live session")?
  };
  let pending = {
    let mut g = shared
      .pending_decoder
      .lock()
      .map_err(|_| "pending_decoder lock".to_string())?;
    g.take().ok_or("no pending decoder (phase not configuring)")?
  };

  #[cfg(target_env = "ohos")]
  let attach_result: Result<(), String> = ohos_vdec::start_live_stream(
    &pending.surface_id,
    pending.use_h265,
    pending.width,
    pending.height,
    &pending.csd0,
    pending.csd1.as_deref(),
  )
  .map(|_| ())
  .map_err(|e| format!("decoder start: {e}"));

  #[cfg(not(target_env = "ohos"))]
  let attach_result: Result<(), String> = {
    let _ = &pending;
    Ok(())
  };

  match attach_result {
    Ok(()) => {
      if let Ok(mut g) = shared.decoder_attach.lock() {
        *g = DecoderAttachState::Ready;
      }
      shared.decoder_cv.notify_all();
      set_status(&shared, |st| {
        st.detail = format!(
          "decoder attached {}x{} h265={}",
          pending.width, pending.height, pending.use_h265
        );
      });
      Ok(status())
    }
    Err(e) => {
      if let Ok(mut g) = shared.decoder_attach.lock() {
        *g = DecoderAttachState::Failed(e.clone());
      }
      shared.decoder_cv.notify_all();
      set_status(&shared, |st| {
        st.phase = LivePhase::Error;
        st.detail = e.clone();
        st.live = false;
      });
      Err(e)
    }
  }
}

pub fn stop() {
  let shared = {
    let g = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    g.clone()
  };
  if let Some(s) = shared {
    s.stop.store(true, Ordering::SeqCst);
    if let Ok(mut main) = s.main_tcp.lock() {
      if let Some(sock) = main.take() {
        let _ = sock.shutdown(std::net::Shutdown::Both);
      }
    }
    if let Ok(mut pend) = s.pending_decoder.lock() {
      *pend = None;
    }
    if let Ok(mut attach) = s.decoder_attach.lock() {
      *attach = DecoderAttachState::Failed("stopped".into());
    }
    s.decoder_cv.notify_all();
    set_status(&s, |st| {
      if st.phase != LivePhase::Error {
        st.phase = LivePhase::Stopped;
        st.detail = "stopped".into();
        st.live = false;
      }
    });
  }
  if let Ok(mut j) = JOIN.lock() {
    if let Some(h) = j.take() {
      let _ = h.join();
    }
  }
  let mut g = SHARED.lock().unwrap_or_else(|e| e.into_inner());
  *g = None;
  #[cfg(target_env = "ohos")]
  {
    ohos_vdec::release();
    ohos_adec::release();
  }
}

pub fn start(req: LiveStartRequest) -> Result<LiveStatus, String> {
  stop();
  #[cfg(target_env = "ohos")]
  FIRST_FRAME_MARKED.store(false, Ordering::SeqCst);

  if req.host.trim().is_empty() {
    return Err("host empty".into());
  }
  if req.jar_bytes.is_empty() {
    return Err("server jar empty".into());
  }
  if req.private_key_pem.trim().is_empty() {
    return Err("ADB private key PEM empty".into());
  }
  if req.surface_id.trim().is_empty() {
    return Err("surfaceId empty".into());
  }

  let shared = Arc::new(Shared {
    status: Mutex::new(LiveStatus {
      phase: LivePhase::Connecting,
      detail: format!("connecting {}:{}", req.host, req.adb_port),
      mode: String::new(),
      width: 0,
      height: 0,
      use_h265: false,
      aus_fed: 0,
      first_frame: false,
      live: true,
      can_audio: false,
      use_opus: false,
      audio_started: false,
      audio_frames: 0,
      audio_detail: String::new(),
    }),
    main_tcp: Mutex::new(None),
    stop: AtomicBool::new(false),
    pending_decoder: Mutex::new(None),
    decoder_attach: Mutex::new(DecoderAttachState::Waiting),
    decoder_cv: Condvar::new(),
  });

  {
    let mut g = SHARED.lock().unwrap_or_else(|e| e.into_inner());
    *g = Some(shared.clone());
  }

  let handle = thread::Builder::new()
    .name("easycontrol-live".into())
    .spawn(move || {
      if let Err(e) = run_session(shared.clone(), req) {
        let msg = e;
        set_status(&shared, |st| {
          st.phase = LivePhase::Error;
          st.detail = msg.clone();
          st.live = false;
        });
      }
    })
    .map_err(|e| format!("spawn live thread: {e}"))?;

  {
    let mut j = JOIN.lock().unwrap_or_else(|e| e.into_inner());
    *j = Some(handle);
  }

  Ok(status())
}

fn run_session(shared: Arc<Shared>, req: LiveStartRequest) -> Result<(), String> {
  let t0 = Instant::now();
  mark(t0, "connect_t0");

  let signer = load_signer(&req)?;

  let mut opts = ServerLaunchOptions::default();
  opts.app_version_code = if req.app_version_code > 0 {
    req.app_version_code
  } else {
    DEFAULT_APP_VERSION_CODE
  };
  opts.server_port = req.server_port;
  opts.max_size = req.max_size;
  opts.max_fps = req.max_fps;
  opts.max_video_bit = req.max_video_bit;
  opts.listen_clip = req.listen_clip;
  opts.is_audio = req.is_audio;
  // Advertise Opus when audio is requested so the server prefers Opus (Android ClientStream parity).
  opts.support_opus = req.is_audio;
  opts.keep_awake = req.keep_awake;
  opts.support_h265 = req.support_h265;
  if req.support_h265 {
    opts.hevc_profile = "main".into();
  } else {
    opts.hevc_profile = "0".into();
  }
  let video_source = if req.video_source.eq_ignore_ascii_case("camera") {
    "camera"
  } else {
    "display"
  };
  opts.video_source = video_source.into();
  opts.camera_facing = if req.camera_facing.eq_ignore_ascii_case("front") {
    "front".into()
  } else {
    "back".into()
  };
  opts.virtual_width = req.virtual_width;
  opts.virtual_height = req.virtual_height;
  opts.virtual_dpi = req.virtual_dpi;
  opts.start_app = req.start_app.trim().to_string();
  if video_source == "camera" {
    // Camera source ignores single-app virtual display (Android ClientStream).
    opts.start_app.clear();
  }
  eprintln!(
    "[LiveSession] source={} facing={} start_app='{}' vd={}x{}@{}",
    opts.video_source,
    opts.camera_facing,
    opts.start_app,
    opts.virtual_width,
    opts.virtual_height,
    opts.virtual_dpi
  );

  set_status(&shared, |st| {
    st.phase = LivePhase::Connecting;
    st.detail = format!("ADB {}:{}", req.host, req.adb_port);
  });

  let stream = connect_tcp(&req.host, req.adb_port, Duration::from_secs(8))
    .map_err(|e| format!("ADB TCP connect failed: {e}"))?;
  // Already-authorized devices finish AUTH quickly; 25s still covers first-time prompts.
  let mut session = AdbSession::connect(stream, signer.as_ref(), Duration::from_secs(25)).map_err(|e| {
    format!("ADB AUTH/CNXN failed: {e} (authorize RSA key on Android if prompted)")
  })?;
  if session.state() != SessionState::Connected {
    return Err("ADB session not connected".into());
  }
  mark(t0, "after_auth");
  set_status(&shared, |st| {
    st.detail = format!("AUTH OK +{}ms", t0.elapsed().as_millis());
  });
  if shared.stop.load(Ordering::SeqCst) {
    return Err("stopped".into());
  }

  session
    .set_io_timeout(Duration::from_secs(8))
    .map_err(|e| e.to_string())?;

  // Android ClientStream.startServer SDK gates (honest errors before app_process).
  enforce_source_sdk_gates(&mut session, &opts)?;

  set_status(&shared, |st| {
    st.phase = LivePhase::Pushing;
    st.detail = "stop prior server + ensure jar".into();
  });
  let _ = stop_existing_server(&mut session).map_err(|e| e.to_string())?;
  let jar = ensure_server_jar(&mut session, &opts, &req.jar_bytes).map_err(|e| e.to_string())?;
  mark(t0, if jar.pushed { "after_push" } else { "after_push_skip" });
  set_status(&shared, |st| {
    st.detail = if jar.pushed {
      format!("jar pushed +{}ms", t0.elapsed().as_millis())
    } else {
      format!("jar skip (sha match) +{}ms", t0.elapsed().as_millis())
    };
  });

  set_status(&shared, |st| {
    st.phase = LivePhase::Launching;
    st.detail = format!("app_process port={}", opts.server_port);
  });
  let shell_id = start_server_shell(&mut session, &opts).map_err(|e| e.to_string())?;
  // Match Android ClientStream.connectServer sleep(50) — do not burn 400ms before accept retries.
  thread::sleep(Duration::from_millis(50));
  session
    .set_io_timeout(Duration::from_millis(500))
    .map_err(|e| e.to_string())?;
  let _ = session.read_stream_buf(shell_id);

  let dual = connect_dual(
    &mut session,
    &req.host,
    opts.server_port,
    Duration::from_secs(12),
    shell_id,
  )
  .map_err(|e| e.to_string())?;

  let mode = dual.mode;
  mark(t0, "after_tcp");
  set_status(&shared, |st| {
    st.mode = mode.as_str().into();
    st.detail = format!("dual sockets ({}) +{}ms", mode.as_str(), t0.elapsed().as_millis());
  });

  let header_timeout = Duration::from_secs(12);
  let mut main_tcp = dual.main_tcp;
  let mut video_tcp = dual.video_tcp;
  let main_adb = dual.main_adb;
  let video_adb = dual.video_adb;

  let (hdr, leftover): (VideoStreamHeader, Vec<u8>) = if let Some(ref mut sock) = video_tcp {
    read_video_header_tcp_with_leftover(sock, header_timeout)?
  } else {
    let id = video_adb.ok_or("missing video adb stream")?;
    read_video_header_adb(&mut session, id, header_timeout)?
  };

  let can_audio_byte = if let Some(ref mut sock) = main_tcp {
    read_exact_timeout(sock, 1, header_timeout)?[0]
  } else {
    let id = main_adb.ok_or("missing main adb stream")?;
    read_adb_at_least(&mut session, id, 1, header_timeout)?[0]
  };
  let can_audio = can_audio_byte == 1;
  let use_opus = if can_audio {
    let opus_byte = if let Some(ref mut sock) = main_tcp {
      read_exact_timeout(sock, 1, header_timeout)?[0]
    } else {
      let id = main_adb.ok_or("missing main adb stream")?;
      read_adb_at_least(&mut session, id, 1, header_timeout)?[0]
    };
    opus_byte == 1
  } else {
    false
  };
  eprintln!(
    "[LiveSession] main audio handshake can_audio={} use_opus={} (requested is_audio={})",
    can_audio, use_opus, req.is_audio
  );
  set_status(&shared, |st| {
    st.can_audio = can_audio;
    st.use_opus = use_opus;
    st.audio_detail = if can_audio {
      format!(
        "server audio ok codec={}",
        if use_opus { "opus" } else { "aac" }
      )
    } else if req.is_audio {
      "server declined audio (need Android 12+ / encode init)".into()
    } else {
      "audio not requested".into()
    };
  });

  let csd0 = video::strip_pts_prefix(&hdr.csd0)
    .map_err(|e| e.to_string())?
    .to_vec();
  let csd1 = match &hdr.csd1 {
    Some(raw) => Some(video::strip_pts_prefix(raw).map_err(|e| e.to_string())?.to_vec()),
    None => None,
  };

  // OH_VideoDecoder_CreateByMime must run on the NAPI/JS thread — not this worker.
  // Stash CSD + surface; ArkTS poll calls attach_decoder() which creates the codec.
  #[cfg(target_env = "ohos")]
  {
    request_decoder_attach(
      &shared,
      PendingDecoder {
        surface_id: req.surface_id.clone(),
        use_h265: hdr.use_h265,
        width: hdr.width,
        height: hdr.height,
        csd0: csd0.clone(),
        csd1: csd1.clone(),
      },
    )?;
    wait_decoder_attach(&shared, Duration::from_secs(15))?;
    mark(t0, "after_decoder");
  }
  #[cfg(not(target_env = "ohos"))]
  {
    let _ = (&req.surface_id, &csd0, &csd1);
  }

  set_status(&shared, |st| {
    st.phase = LivePhase::Streaming;
    st.width = hdr.width;
    st.height = hdr.height;
    st.use_h265 = hdr.use_h265;
    st.detail = format!(
      "streaming {}x{} via {} +{}ms",
      hdr.width,
      hdr.height,
      mode.as_str(),
      t0.elapsed().as_millis()
    );
    st.live = true;
  });

  // Keepalive + store main for touch (direct TCP only).
  let ka = control::create_keep_alive();
  if let Some(ref mut sock) = main_tcp {
    sock.write_all(&ka).map_err(|e| e.to_string())?;
    let write_clone = sock.try_clone().map_err(|e| e.to_string())?;
    let read_clone = sock.try_clone().map_err(|e| e.to_string())?;
    if let Ok(mut g) = shared.main_tcp.lock() {
      *g = Some(write_clone);
    }
    // Main inbound demux (audio / clipboard / size) — separate from video AU feed.
    let shared_main = shared.clone();
    let _main_thread = thread::Builder::new()
      .name("easycontrol-main".into())
      .spawn(move || {
        if let Err(e) = main_demux_tcp(shared_main, read_clone, can_audio, use_opus) {
          eprintln!("[LiveSession] main demux ended: {e}");
        }
      })
      .map_err(|e| format!("spawn main demux: {e}"))?;
  } else if let Some(id) = main_adb {
    session.write_stream(id, &ka).map_err(|e| e.to_string())?;
  }

  match mode {
    ConnectMode::Direct => {
      let video = video_tcp.take().ok_or("missing video tcp")?;
      // Keepalive on shared main clone.
      let shared_ka = shared.clone();
      let _ka_thread = thread::spawn(move || keepalive_loop(shared_ka));
      feed_video_tcp(shared, video, leftover)?;
    }
    ConnectMode::AdbTcp => {
      // Pump ADB: video AUs + main demux + occasional keepalive.
      let video_id = video_adb.ok_or("missing video adb")?;
      let main_id = main_adb.ok_or("missing main adb")?;
      feed_video_adb(
        shared,
        &mut session,
        video_id,
        main_id,
        leftover,
        shell_id,
        can_audio,
        use_opus,
      )?;
    }
  }

  let _ = session.close_stream(shell_id);
  let _ = stop_existing_server(&mut session);
  let _ = session.close();
  Ok(())
}

fn keepalive_loop(shared: Arc<Shared>) {
  let ka = control::create_keep_alive();
  while !shared.stop.load(Ordering::SeqCst) {
    thread::sleep(Duration::from_secs(1));
    if let Ok(mut g) = shared.main_tcp.lock() {
      if let Some(sock) = g.as_mut() {
        if sock.write_all(&ka).is_err() {
          break;
        }
      } else {
        break;
      }
    }
  }
}

fn read_be_u32(bytes: &[u8]) -> u32 {
  ((bytes[0] as u32) << 24)
    | ((bytes[1] as u32) << 16)
    | ((bytes[2] as u32) << 8)
    | (bytes[3] as u32)
}

fn handle_audio_frame(
  shared: &Shared,
  use_opus: bool,
  started: &mut bool,
  failed: &mut bool,
  payload: &[u8],
) {
  if payload.is_empty() {
    return;
  }
  #[cfg(target_env = "ohos")]
  {
    if !*started {
      match ohos_adec::start(use_opus, payload) {
        Ok(snap) => {
          *started = true;
          set_status(shared, |st| {
            st.audio_started = true;
            st.use_opus = snap.use_opus;
            st.audio_detail = snap.detail.clone();
          });
          eprintln!(
            "[LiveSession] audio decoder started codec={} detail={}",
            if use_opus { "opus" } else { "aac" },
            snap.detail
          );
        }
        Err(e) => {
          *started = true;
          *failed = true;
          set_status(shared, |st| {
            st.audio_detail = format!("audio HW decode unavailable: {e}");
          });
          eprintln!("[LiveSession] audio start failed: {e}");
        }
      }
      return;
    }
    if *failed {
      return;
    }
    if let Err(e) = ohos_adec::push_packet(payload) {
      set_status(shared, |st| {
        st.audio_detail = format!("audio push: {e}");
      });
    }
  }
  #[cfg(not(target_env = "ohos"))]
  {
    let _ = (shared, use_opus, started, failed, payload);
  }
}

/// Android ClientPlayer.mainStreamIn parity: type-1 audio, type-2 clipboard, type-3 size.
fn main_demux_tcp(
  shared: Arc<Shared>,
  mut sock: TcpStream,
  can_audio: bool,
  use_opus: bool,
) -> Result<(), String> {
  let _ = can_audio;
  sock
    .set_read_timeout(Some(Duration::from_millis(500)))
    .map_err(|e| e.to_string())?;
  let mut audio_started = false;
  let mut audio_failed = false;
  let mut buf = Vec::new();
  let mut tmp = [0u8; 16 * 1024];
  while !shared.stop.load(Ordering::SeqCst) {
    match sock.read(&mut tmp) {
      Ok(0) => return Ok(()),
      Ok(n) => buf.extend_from_slice(&tmp[..n]),
      Err(e)
        if e.kind() == std::io::ErrorKind::WouldBlock
          || e.kind() == std::io::ErrorKind::TimedOut =>
      {
        continue;
      }
      Err(e) => {
        if shared.stop.load(Ordering::SeqCst) {
          return Ok(());
        }
        return Err(format!("main read: {e}"));
      }
    }
    while !buf.is_empty() {
      let event = buf[0];
      match event {
        MAIN_AUDIO_EVENT => {
          if buf.len() < 5 {
            break;
          }
          let size = read_be_u32(&buf[1..5]) as usize;
          if size > 2 * 1024 * 1024 {
            return Err(format!("audio frame too large: {size}"));
          }
          if buf.len() < 5 + size {
            break;
          }
          let payload = buf[5..5 + size].to_vec();
          buf.drain(..5 + size);
          handle_audio_frame(
            &shared,
            use_opus,
            &mut audio_started,
            &mut audio_failed,
            &payload,
          );
        }
        MAIN_CLIPBOARD_EVENT => {
          if buf.len() < 5 {
            break;
          }
          let size = read_be_u32(&buf[1..5]) as usize;
          if size > 5000 {
            return Err(format!("clipboard too large: {size}"));
          }
          if buf.len() < 5 + size {
            break;
          }
          // Safe ignore for MVP — do not stall the demux.
          buf.drain(..5 + size);
        }
        MAIN_CHANGE_SIZE_EVENT => {
          if buf.len() < 9 {
            break;
          }
          let w = read_be_u32(&buf[1..5]);
          let h = read_be_u32(&buf[5..9]);
          buf.drain(..9);
          if w > 0 && h > 0 {
            set_status(&shared, |st| {
              st.width = w;
              st.height = h;
            });
          }
        }
        _ => {
          // Unknown type — drop one byte to resync rather than stall forever.
          eprintln!("[LiveSession] main unknown event type={event}, skip");
          buf.drain(..1);
        }
      }
    }
  }
  Ok(())
}

fn feed_main_adb_buf(
  shared: &Shared,
  buf: &mut Vec<u8>,
  use_opus: bool,
  audio_started: &mut bool,
  audio_failed: &mut bool,
) -> Result<(), String> {
  while !buf.is_empty() {
    let event = buf[0];
    match event {
      MAIN_AUDIO_EVENT => {
        if buf.len() < 5 {
          break;
        }
        let size = read_be_u32(&buf[1..5]) as usize;
        if size > 2 * 1024 * 1024 {
          return Err(format!("audio frame too large: {size}"));
        }
        if buf.len() < 5 + size {
          break;
        }
        let payload = buf[5..5 + size].to_vec();
        buf.drain(..5 + size);
        handle_audio_frame(shared, use_opus, audio_started, audio_failed, &payload);
      }
      MAIN_CLIPBOARD_EVENT => {
        if buf.len() < 5 {
          break;
        }
        let size = read_be_u32(&buf[1..5]) as usize;
        if size > 5000 {
          return Err(format!("clipboard too large: {size}"));
        }
        if buf.len() < 5 + size {
          break;
        }
        buf.drain(..5 + size);
      }
      MAIN_CHANGE_SIZE_EVENT => {
        if buf.len() < 9 {
          break;
        }
        let w = read_be_u32(&buf[1..5]);
        let h = read_be_u32(&buf[5..9]);
        buf.drain(..9);
        if w > 0 && h > 0 {
          set_status(shared, |st| {
            st.width = w;
            st.height = h;
          });
        }
      }
      _ => {
        buf.drain(..1);
      }
    }
  }
  Ok(())
}

fn feed_video_tcp(shared: Arc<Shared>, mut video: TcpStream, mut buf: Vec<u8>) -> Result<(), String> {
  video
    .set_read_timeout(Some(Duration::from_millis(500)))
    .map_err(|e| e.to_string())?;
  let mut tmp = [0u8; 64 * 1024];
  let mut aus = 0u32;
  let mut cursor = 0usize;
  while !shared.stop.load(Ordering::SeqCst) {
    // Parse complete AUs without O(n) drain per frame (cursor + compact).
    loop {
      match video::parse_video_access_unit(&buf[cursor..]) {
        Ok((au, n)) => {
          #[cfg(target_env = "ohos")]
          {
            // Decoder drops oldest AUs when live backlog is high (chase live edge).
            let _ = ohos_vdec::push_access_unit(au.pts_us, &au.payload);
          }
          #[cfg(not(target_env = "ohos"))]
          {
            let _ = au;
          }
          cursor += n;
          aus += 1;
          if aus % 30 == 0 {
            set_status(&shared, |st| {
              st.aus_fed = aus;
            });
          }
        }
        Err(_) => break,
      }
    }
    if cursor > 0 {
      buf.drain(..cursor);
      cursor = 0;
    }
    match video.read(&mut tmp) {
      Ok(0) => {
        set_status(&shared, |st| {
          st.phase = LivePhase::Stopped;
          st.detail = format!("video EOF after {aus} AUs");
          st.aus_fed = aus;
          st.live = false;
        });
        return Ok(());
      }
      Ok(n) => buf.extend_from_slice(&tmp[..n]),
      Err(e)
        if e.kind() == std::io::ErrorKind::WouldBlock
          || e.kind() == std::io::ErrorKind::TimedOut =>
      {
        continue;
      }
      Err(e) => {
        if shared.stop.load(Ordering::SeqCst) {
          return Ok(());
        }
        return Err(format!("video read: {e}"));
      }
    }
  }
  set_status(&shared, |st| {
    st.phase = LivePhase::Stopped;
    st.aus_fed = aus;
    st.detail = "stopped".into();
    st.live = false;
  });
  Ok(())
}

fn feed_video_adb(
  shared: Arc<Shared>,
  session: &mut AdbSession<std::net::TcpStream>,
  video_id: u32,
  main_id: u32,
  mut buf: Vec<u8>,
  shell_id: u32,
  can_audio: bool,
  use_opus: bool,
) -> Result<(), String> {
  let _ = can_audio;
  let ka = control::create_keep_alive();
  let mut last_ka = Instant::now();
  let mut aus = 0u32;
  let mut cursor = 0usize;
  let mut main_buf: Vec<u8> = Vec::new();
  let mut audio_started = false;
  let mut audio_failed = false;
  while !shared.stop.load(Ordering::SeqCst) {
    let _ = session.pump();
    let chunk = session.read_stream_buf(video_id).map_err(|e| e.to_string())?;
    if !chunk.is_empty() {
      buf.extend_from_slice(&chunk);
    }
    let main_chunk = session.read_stream_buf(main_id).map_err(|e| e.to_string())?;
    if !main_chunk.is_empty() {
      main_buf.extend_from_slice(&main_chunk);
      feed_main_adb_buf(
        &shared,
        &mut main_buf,
        use_opus,
        &mut audio_started,
        &mut audio_failed,
      )?;
    }
    loop {
      match video::parse_video_access_unit(&buf[cursor..]) {
        Ok((au, n)) => {
          #[cfg(target_env = "ohos")]
          {
            let _ = ohos_vdec::push_access_unit(au.pts_us, &au.payload);
          }
          #[cfg(not(target_env = "ohos"))]
          {
            let _ = au;
          }
          cursor += n;
          aus += 1;
        }
        Err(_) => break,
      }
    }
    if cursor > 0 {
      buf.drain(..cursor);
      cursor = 0;
    }
    if last_ka.elapsed() >= Duration::from_secs(1) {
      let _ = session.write_stream(main_id, &ka);
      last_ka = Instant::now();
    }
    let _ = session.read_stream_buf(shell_id);
    if session.is_stream_closed(video_id) {
      set_status(&shared, |st| {
        st.phase = LivePhase::Stopped;
        st.aus_fed = aus;
        st.detail = format!("adb video closed after {aus} AUs");
        st.live = false;
      });
      return Ok(());
    }
    if chunk.is_empty() && main_chunk.is_empty() {
      thread::sleep(Duration::from_millis(5));
    }
    if aus > 0 && aus % 30 == 0 {
      set_status(&shared, |st| {
        st.aus_fed = aus;
      });
    }
  }
  Ok(())
}
