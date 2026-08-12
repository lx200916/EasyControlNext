//! OH_VideoDecoder + NativeWindow surface path (API 12+/24), tuned for live mirror latency.
//!
//! Critical vs Android `VideoDecode`: keep free input-buffer indices when the AU queue is empty
//! (LinkedBlockingQueue pattern). Dropping `onNeedInput` without stashing the slot starves the
//! decoder until the next (often rare) callback — feels like “decoding is very slow”.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use easycontrol_protocol::video;

const FLAG_EOS: u32 = 1 << 0;
const FLAG_SYNC: u32 = 1 << 1;
const FLAG_CODEC_DATA: u32 = 1 << 3;
const AV_ERR_OK: i32 = 0;
/// Live mirror: keep few AUs queued so we chase the live edge instead of decoding history.
const LIVE_MAX_PENDING_AUS: usize = 6;

#[repr(C)]
struct OH_AVCodec {
  _private: [u8; 0],
}

#[repr(C)]
struct OHNativeWindow {
  _private: [u8; 0],
}

#[repr(C)]
struct OH_AVFormat {
  _private: [u8; 0],
}

#[repr(C)]
struct OH_AVBuffer {
  _private: [u8; 0],
}

#[repr(C)]
struct OH_AVCodecBufferAttr {
  pts: i64,
  size: i32,
  offset: i32,
  flags: u32,
}

#[repr(C)]
struct OH_AVCodecCallback {
  on_error: Option<extern "C" fn(*mut OH_AVCodec, i32, *mut c_void)>,
  on_stream_changed: Option<extern "C" fn(*mut OH_AVCodec, *mut OH_AVFormat, *mut c_void)>,
  on_need_input_buffer: Option<extern "C" fn(*mut OH_AVCodec, u32, *mut OH_AVBuffer, *mut c_void)>,
  on_new_output_buffer: Option<extern "C" fn(*mut OH_AVCodec, u32, *mut OH_AVBuffer, *mut c_void)>,
}

#[link(name = "native_media_vdec")]
extern "C" {
  fn OH_VideoDecoder_CreateByMime(mime: *const c_char) -> *mut OH_AVCodec;
  fn OH_VideoDecoder_Destroy(codec: *mut OH_AVCodec) -> i32;
  fn OH_VideoDecoder_RegisterCallback(
    codec: *mut OH_AVCodec,
    callback: OH_AVCodecCallback,
    user_data: *mut c_void,
  ) -> i32;
  fn OH_VideoDecoder_SetSurface(codec: *mut OH_AVCodec, window: *mut OHNativeWindow) -> i32;
  fn OH_VideoDecoder_Configure(codec: *mut OH_AVCodec, format: *mut OH_AVFormat) -> i32;
  fn OH_VideoDecoder_Prepare(codec: *mut OH_AVCodec) -> i32;
  fn OH_VideoDecoder_Start(codec: *mut OH_AVCodec) -> i32;
  fn OH_VideoDecoder_Stop(codec: *mut OH_AVCodec) -> i32;
  fn OH_VideoDecoder_PushInputBuffer(codec: *mut OH_AVCodec, index: u32) -> i32;
  fn OH_VideoDecoder_RenderOutputBuffer(codec: *mut OH_AVCodec, index: u32) -> i32;
  fn OH_VideoDecoder_FreeOutputBuffer(codec: *mut OH_AVCodec, index: u32) -> i32;
}

#[link(name = "native_media_core")]
extern "C" {
  fn OH_AVFormat_CreateVideoFormat(
    mime_type: *const c_char,
    width: i32,
    height: i32,
  ) -> *mut OH_AVFormat;
  fn OH_AVFormat_Destroy(format: *mut OH_AVFormat);
  fn OH_AVFormat_SetIntValue(format: *mut OH_AVFormat, key: *const c_char, value: i32) -> bool;
  fn OH_AVBuffer_GetAddr(buffer: *mut OH_AVBuffer) -> *mut u8;
  fn OH_AVBuffer_GetCapacity(buffer: *mut OH_AVBuffer) -> i32;
  fn OH_AVBuffer_SetBufferAttr(buffer: *mut OH_AVBuffer, attr: *const OH_AVCodecBufferAttr) -> i32;
}

#[link(name = "native_window")]
extern "C" {
  fn OH_NativeWindow_CreateNativeWindowFromSurfaceId(
    surface_id: u64,
    window: *mut *mut OHNativeWindow,
  ) -> i32;
  fn OH_NativeWindow_DestroyNativeWindow(window: *mut OHNativeWindow);
}

// SDK headers declare `extern const char *OH_MD_KEY_*`, but aarch64 codecbase exports
// them as tiny DF stubs. Pass the documented key strings directly (values match .so .rodata).
const KEY_VIDEO_ENABLE_LOW_LATENCY: &[u8] = b"OH_MD_KEY_VIDEO_ENABLE_LOW_LATENCY\0";
const KEY_FRAME_RATE: &[u8] = b"OH_MD_KEY_FRAME_RATE\0";

struct PendingPacket {
  pts_us: i64,
  data: Vec<u8>,
  flags: u32,
}

struct FreeInput {
  index: u32,
  buffer: *mut OH_AVBuffer,
}

struct DecoderState {
  codec: *mut OH_AVCodec,
  window: *mut OHNativeWindow,
  pending: VecDeque<PendingPacket>,
  free_inputs: VecDeque<FreeInput>,
  /// Cached CSD for surface rebind (fold / XComponent recreate) without ADB teardown.
  csd0: Vec<u8>,
  csd1: Option<Vec<u8>>,
  width: u32,
  height: u32,
  use_h265: bool,
  surface_id: u64,
  live: bool,
}

unsafe impl Send for DecoderState {}

static STATE: Mutex<Option<DecoderState>> = Mutex::new(None);
static STARTED: AtomicBool = AtomicBool::new(false);
/// True while Stop→SetSurface→Start runs. AU feed / try_feed / render must not touch the codec.
static REBINDING: AtomicBool = AtomicBool::new(false);
/// Guards against overlapping release() from ArkTS destroy + rebind failure paths.
static RELEASING: AtomicBool = AtomicBool::new(false);
static FIRST_FRAME: AtomicBool = AtomicBool::new(false);
static INPUT_QUEUED: AtomicU32 = AtomicU32::new(0);
static OUTPUT_FRAMES: AtomicU32 = AtomicU32::new(0);
static STREAM_CHANGED: AtomicU32 = AtomicU32::new(0);
static LAST_ERROR: AtomicI32 = AtomicI32::new(0);
static DROPPED_AUS: AtomicU32 = AtomicU32::new(0);
static LAST_DETAIL: Mutex<String> = Mutex::new(String::new());

fn feed_allowed() -> bool {
  STARTED.load(Ordering::SeqCst)
    && !REBINDING.load(Ordering::SeqCst)
    && !RELEASING.load(Ordering::SeqCst)
}

fn set_detail(msg: impl Into<String>) {
  if let Ok(mut g) = LAST_DETAIL.lock() {
    *g = msg.into();
  }
}

fn mime_for(use_h265: bool) -> &'static [u8] {
  if use_h265 {
    b"video/hevc\0"
  } else {
    b"video/avc\0"
  }
}

extern "C" fn on_error(_codec: *mut OH_AVCodec, error_code: i32, _user: *mut c_void) {
  LAST_ERROR.store(error_code, Ordering::SeqCst);
  set_detail(format!("decoder onError code={error_code}"));
}

extern "C" fn on_stream_changed(
  _codec: *mut OH_AVCodec,
  _format: *mut OH_AVFormat,
  _user: *mut c_void,
) {
  STREAM_CHANGED.fetch_add(1, Ordering::SeqCst);
}

struct SubmitJob {
  codec: *mut OH_AVCodec,
  index: u32,
  buffer: *mut OH_AVBuffer,
  pts_us: i64,
  data: Vec<u8>,
  flags: u32,
}

/// Take (free slot, pending AU) pairs under the lock; never call codec APIs while locked
/// (PushInputBuffer may re-enter on_need_input on some devices → Mutex deadlock).
fn take_submit_jobs(state: &mut DecoderState) -> Vec<SubmitJob> {
  let mut jobs = Vec::new();
  while !state.free_inputs.is_empty() && !state.pending.is_empty() {
    let free = state.free_inputs.pop_front().unwrap();
    let packet = state.pending.pop_front().unwrap();
    let pts_us = if state.live { 0 } else { packet.pts_us };
    jobs.push(SubmitJob {
      codec: state.codec,
      index: free.index,
      buffer: free.buffer,
      pts_us,
      data: packet.data,
      flags: packet.flags,
    });
  }
  jobs
}

fn run_submit_jobs(jobs: Vec<SubmitJob>) {
  for job in jobs {
    unsafe {
      let addr = OH_AVBuffer_GetAddr(job.buffer);
      let cap = OH_AVBuffer_GetCapacity(job.buffer);
      if addr.is_null() || cap <= 0 {
        LAST_ERROR.store(-100, Ordering::SeqCst);
        set_detail("input buffer null/empty");
        continue;
      }
      if job.data.len() as i32 > cap {
        LAST_ERROR.store(-101, Ordering::SeqCst);
        set_detail(format!(
          "AU {}B exceeds input capacity {cap}",
          job.data.len()
        ));
        // Return the free slot so smaller frames can still decode.
        if let Ok(mut guard) = STATE.lock() {
          if let Some(state) = guard.as_mut() {
            if state.codec == job.codec {
              state.free_inputs.push_front(FreeInput {
                index: job.index,
                buffer: job.buffer,
              });
            }
          }
        }
        continue;
      }
      std::ptr::copy_nonoverlapping(job.data.as_ptr(), addr, job.data.len());
      let attr = OH_AVCodecBufferAttr {
        pts: job.pts_us,
        size: job.data.len() as i32,
        offset: 0,
        flags: job.flags,
      };
      let set_rc = OH_AVBuffer_SetBufferAttr(job.buffer, &attr);
      let push_rc = OH_VideoDecoder_PushInputBuffer(job.codec, job.index);
      if set_rc != AV_ERR_OK || push_rc != AV_ERR_OK {
        LAST_ERROR.store(if set_rc != AV_ERR_OK { set_rc } else { push_rc }, Ordering::SeqCst);
        set_detail(format!("push input failed set={set_rc} push={push_rc}"));
        continue;
      }
    }
    INPUT_QUEUED.fetch_add(1, Ordering::SeqCst);
  }
}

fn try_feed() {
  if !feed_allowed() {
    return;
  }
  let jobs = {
    let mut guard = match STATE.lock() {
      Ok(g) => g,
      Err(_) => return,
    };
    let Some(state) = guard.as_mut() else {
      return;
    };
    take_submit_jobs(state)
  };
  // Re-check after unlocking: rebind may have started while we held jobs.
  if !feed_allowed() {
    // Return free slots so they are not leaked; buffers may still be valid if Stop not yet done.
    if let Ok(mut guard) = STATE.lock() {
      if let Some(state) = guard.as_mut() {
        for job in jobs.into_iter().rev() {
          if state.codec == job.codec {
            state.free_inputs.push_front(FreeInput {
              index: job.index,
              buffer: job.buffer,
            });
            state.pending.push_front(PendingPacket {
              pts_us: job.pts_us,
              data: job.data,
              flags: job.flags,
            });
          }
        }
      }
    }
    return;
  }
  run_submit_jobs(jobs);
}

fn drop_old_live_aus(state: &mut DecoderState) {
  if !state.live {
    return;
  }
  while state.pending.len() > LIVE_MAX_PENDING_AUS {
    let front_is_csd = state
      .pending
      .front()
      .map(|p| (p.flags & FLAG_CODEC_DATA) != 0)
      .unwrap_or(false);
    if front_is_csd {
      // Never drop CSD; drop the next oldest non-CSD if possible.
      if state.pending.len() < 2 {
        break;
      }
      let csd = state.pending.pop_front().unwrap();
      let _ = state.pending.pop_front();
      state.pending.push_front(csd);
      DROPPED_AUS.fetch_add(1, Ordering::Relaxed);
    } else {
      let _ = state.pending.pop_front();
      DROPPED_AUS.fetch_add(1, Ordering::Relaxed);
    }
  }
}

extern "C" fn on_need_input(
  _codec: *mut OH_AVCodec,
  index: u32,
  buffer: *mut OH_AVBuffer,
  _user: *mut c_void,
) {
  if REBINDING.load(Ordering::SeqCst) || RELEASING.load(Ordering::SeqCst) {
    // Slots from a stopping/stopped codec are invalid — do not stash.
    return;
  }
  {
    let mut guard = match STATE.lock() {
      Ok(g) => g,
      Err(_) => return,
    };
    let Some(state) = guard.as_mut() else {
      return;
    };
    // Android VideoDecode: offer index into a queue; never discard the callback.
    state.free_inputs.push_back(FreeInput { index, buffer });
  }
  try_feed();
}

extern "C" fn on_new_output(
  codec: *mut OH_AVCodec,
  index: u32,
  _buffer: *mut OH_AVBuffer,
  _user: *mut c_void,
) {
  // Never render into a NativeWindow that rebind/release is tearing down.
  if REBINDING.load(Ordering::SeqCst) || RELEASING.load(Ordering::SeqCst) {
    let _ = unsafe { OH_VideoDecoder_FreeOutputBuffer(codec, index) };
    return;
  }
  // Render ASAP (no AtTime scheduling). Matches low-latency mirror intent.
  let rc = unsafe { OH_VideoDecoder_RenderOutputBuffer(codec, index) };
  if rc != AV_ERR_OK {
    let _ = unsafe { OH_VideoDecoder_FreeOutputBuffer(codec, index) };
    LAST_ERROR.store(rc, Ordering::SeqCst);
    set_detail(format!("render failed rc={rc}"));
    return;
  }
  let n = OUTPUT_FRAMES.fetch_add(1, Ordering::SeqCst) + 1;
  // Also arm after surface rebind (FIRST_FRAME cleared while OUTPUT_FRAMES may be >0).
  if !FIRST_FRAME.load(Ordering::SeqCst) {
    FIRST_FRAME.store(true, Ordering::SeqCst);
    set_detail(format!("firstFrameRendered out={n}"));
  }
}

fn reset_counters() {
  STARTED.store(false, Ordering::SeqCst);
  FIRST_FRAME.store(false, Ordering::SeqCst);
  INPUT_QUEUED.store(0, Ordering::SeqCst);
  OUTPUT_FRAMES.store(0, Ordering::SeqCst);
  STREAM_CHANGED.store(0, Ordering::SeqCst);
  LAST_ERROR.store(0, Ordering::SeqCst);
  DROPPED_AUS.store(0, Ordering::SeqCst);
  set_detail("idle");
}

pub fn release() {
  if RELEASING.swap(true, Ordering::SeqCst) {
    return;
  }
  // Pause feeders before taking STATE (callbacks may still race briefly).
  STARTED.store(false, Ordering::SeqCst);
  REBINDING.store(true, Ordering::SeqCst);
  let taken = {
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    guard.take()
  };
  if let Some(state) = taken {
    unsafe {
      if !state.codec.is_null() {
        let _ = OH_VideoDecoder_Stop(state.codec);
        let _ = OH_VideoDecoder_Destroy(state.codec);
      }
      if !state.window.is_null() {
        OH_NativeWindow_DestroyNativeWindow(state.window);
      }
    }
  }
  reset_counters();
  set_detail("released");
  REBINDING.store(false, Ordering::SeqCst);
  RELEASING.store(false, Ordering::SeqCst);
}

fn err_msg(step: &str, rc: i32) -> String {
  format!("{step} failed rc={rc}")
}

fn au_flags(payload: &[u8]) -> u32 {
  let mut flags = 0u32;
  if payload.is_empty() {
    return flags;
  }
  let nal_off = if payload.starts_with(&[0, 0, 0, 1]) {
    4
  } else if payload.starts_with(&[0, 0, 1]) {
    3
  } else {
    0
  };
  if nal_off < payload.len() {
    let nal_type = payload[nal_off] & 0x1f;
    if nal_type == 5 {
      flags |= FLAG_SYNC;
    }
  }
  flags
}

fn start_decoder_inner(
  surface_id: u64,
  use_h265: bool,
  width: u32,
  height: u32,
  pending: VecDeque<PendingPacket>,
  live: bool,
  detail_suffix: &str,
  csd0: Vec<u8>,
  csd1: Option<Vec<u8>>,
) -> Result<StatusSnapshot, String> {
  if pending.is_empty() {
    return Err("decoder pending queue empty".into());
  }

  let mime = mime_for(use_h265);
  let mime_label = if use_h265 { "video/hevc" } else { "video/avc" };
  let codec = unsafe { OH_VideoDecoder_CreateByMime(mime.as_ptr() as *const c_char) };
  if codec.is_null() {
    return Err(format!(
      "OH_VideoDecoder_CreateByMime returned null mime={mime_label} (create on JS/NAPI thread)"
    ));
  }

  let cb = OH_AVCodecCallback {
    on_error: Some(on_error),
    on_stream_changed: Some(on_stream_changed),
    on_need_input_buffer: Some(on_need_input),
    on_new_output_buffer: Some(on_new_output),
  };
  let rc = unsafe { OH_VideoDecoder_RegisterCallback(codec, cb, std::ptr::null_mut()) };
  if rc != AV_ERR_OK {
    unsafe {
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err(err_msg("RegisterCallback", rc));
  }

  let format = unsafe {
    OH_AVFormat_CreateVideoFormat(mime.as_ptr() as *const c_char, width as i32, height as i32)
  };
  if format.is_null() {
    unsafe {
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err("OH_AVFormat_CreateVideoFormat null".into());
  }
  unsafe {
    // Low-latency: hold only codec-required in/out buffers (API 12+).
    let ll = OH_AVFormat_SetIntValue(
      format,
      KEY_VIDEO_ENABLE_LOW_LATENCY.as_ptr() as *const c_char,
      1,
    );
    let fr = OH_AVFormat_SetIntValue(
      format,
      KEY_FRAME_RATE.as_ptr() as *const c_char,
      60,
    );
    if !ll || !fr {
      // Non-fatal: older devices may ignore unknown keys; still continue.
      set_detail(format!("format keys lowLatency={ll} frameRate={fr}"));
    }
  }
  let rc = unsafe { OH_VideoDecoder_Configure(codec, format) };
  unsafe { OH_AVFormat_Destroy(format) };
  if rc != AV_ERR_OK {
    unsafe {
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err(err_msg("Configure", rc));
  }

  let mut window: *mut OHNativeWindow = std::ptr::null_mut();
  let rc = unsafe { OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &mut window) };
  if rc != 0 || window.is_null() {
    unsafe {
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err(format!(
      "CreateNativeWindowFromSurfaceId failed rc={rc} surfaceId={surface_id}"
    ));
  }

  let rc = unsafe { OH_VideoDecoder_SetSurface(codec, window) };
  if rc != AV_ERR_OK {
    unsafe {
      OH_NativeWindow_DestroyNativeWindow(window);
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err(err_msg("SetSurface", rc));
  }

  let rc = unsafe { OH_VideoDecoder_Prepare(codec) };
  if rc != AV_ERR_OK {
    unsafe {
      OH_NativeWindow_DestroyNativeWindow(window);
      let _ = OH_VideoDecoder_Destroy(codec);
    }
    return Err(err_msg("Prepare", rc));
  }

  {
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    *guard = Some(DecoderState {
      codec,
      window,
      pending,
      free_inputs: VecDeque::new(),
      csd0,
      csd1,
      width,
      height,
      use_h265,
      surface_id,
      live,
    });
  }

  let rc = unsafe { OH_VideoDecoder_Start(codec) };
  if rc != AV_ERR_OK {
    release();
    return Err(err_msg("Start", rc));
  }
  STARTED.store(true, Ordering::SeqCst);
  set_detail(format!(
    "started surfaceId={surface_id} {width}x{height} h265={use_h265} lowLatency=1 {detail_suffix}"
  ));

  Ok(snapshot())
}

/// Rebind an already-running decoder to a new XComponent surfaceId.
/// Does **not** tear down the live ADB/video feed — only NativeWindow + SetSurface.
/// Typical call path: fold/unfold → XComponent onDestroy/onLoad.
///
/// Safety: AU push / try_feed / RenderOutput are gated by [`REBINDING`] for the whole
/// Stop → CreateWindow → SetSurface → Start sequence so we never feed or render against
/// a freed NativeWindow.
pub fn rebind_surface(surface_id_str: &str) -> Result<StatusSnapshot, String> {
  let trimmed = surface_id_str.trim();
  if trimmed.is_empty() || trimmed == "0" {
    return Err("rebind_surface: empty/invalid surfaceId".into());
  }
  let new_surface_id: u64 = trimmed
    .parse()
    .map_err(|_| format!("invalid surfaceId '{surface_id_str}'"))?;
  if new_surface_id == 0 {
    return Err("rebind_surface: surfaceId 0".into());
  }
  if RELEASING.load(Ordering::SeqCst) {
    return Err("rebind_surface: decoder releasing".into());
  }
  // Serialize overlapping fold/unfold rebinds.
  if REBINDING.swap(true, Ordering::SeqCst) {
    return Err("rebind_surface: already in progress".into());
  }
  let t0 = Instant::now();
  // Pause AU feed before touching the codec (push_access_unit drops while REBINDING).
  STARTED.store(false, Ordering::SeqCst);

  let rebind_result = (|| {
    let (codec, old_window, old_surface_id, csd0, csd1) = {
      let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
      let state = guard.as_mut().ok_or_else(|| {
        "rebind_surface: decoder not running (no STATE)".to_string()
      })?;
      if state.codec.is_null() {
        return Err("rebind_surface: codec null".into());
      }
      // Free-input slots become invalid at Stop — drop them before Stop.
      state.free_inputs.clear();
      // Drop stale video AUs; keep only a fresh CSD replay after Start.
      state.pending.clear();
      (
        state.codec,
        state.window,
        state.surface_id,
        state.csd0.clone(),
        state.csd1.clone(),
      )
    };

    if old_surface_id == new_surface_id {
      // Same id after XComponent destroy: still must Stop/SetSurface — NativeWindow is dead.
      set_detail(format!(
        "SURFACE_LOST→REBIND same surfaceId={new_surface_id} (window recreate)"
      ));
    } else {
      set_detail(format!(
        "SURFACE_LOST→REBIND old={old_surface_id} new={new_surface_id}"
      ));
    }
    eprintln!(
      "[ohos_vdec] SURFACE_LOST→REBIND old={old_surface_id} new={new_surface_id}"
    );

    // Stop before swapping the NativeWindow (required by AVCodec).
    let t_stop = Instant::now();
    let stop_rc = unsafe { OH_VideoDecoder_Stop(codec) };
    let stop_ms = t_stop.elapsed().as_millis();
    if stop_rc != AV_ERR_OK {
      set_detail(format!(
        "rebind Stop rc={stop_rc} continuing SetSurface anyway"
      ));
    }

    // Detach old window from STATE before destroying it.
    {
      let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
      if let Some(state) = guard.as_mut() {
        if state.codec == codec {
          state.window = std::ptr::null_mut();
          state.free_inputs.clear();
        }
      }
    }

    let mut new_window: *mut OHNativeWindow = std::ptr::null_mut();
    let create_rc =
      unsafe { OH_NativeWindow_CreateNativeWindowFromSurfaceId(new_surface_id, &mut new_window) };
    if create_rc != 0 || new_window.is_null() {
      // Old surface is already gone after XComponent onDestroy — do not restart on it.
      if !old_window.is_null() {
        unsafe {
          OH_NativeWindow_DestroyNativeWindow(old_window);
        }
      }
      return Err(format!(
        "rebind CreateNativeWindow failed rc={create_rc} surfaceId={new_surface_id}"
      ));
    }

    let set_rc = unsafe { OH_VideoDecoder_SetSurface(codec, new_window) };
    if set_rc != AV_ERR_OK {
      unsafe {
        OH_NativeWindow_DestroyNativeWindow(new_window);
      }
      if !old_window.is_null() {
        unsafe {
          OH_NativeWindow_DestroyNativeWindow(old_window);
        }
      }
      return Err(err_msg("rebind SetSurface", set_rc));
    }

    // Destroy old window only after SetSurface succeeded (codec no longer references it).
    if !old_window.is_null() {
      unsafe {
        OH_NativeWindow_DestroyNativeWindow(old_window);
      }
    }

    {
      let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
      if let Some(state) = guard.as_mut() {
        if state.codec != codec {
          unsafe {
            OH_NativeWindow_DestroyNativeWindow(new_window);
          }
          return Err("rebind_surface: codec replaced during swap".into());
        }
        state.free_inputs.clear();
        state.window = new_window;
        state.surface_id = new_surface_id;
        // Minimal CSD replay after Stop/Start (no full bitstream / fixture reinject).
        if !csd0.is_empty() {
          state.pending.push_front(PendingPacket {
            pts_us: 0,
            data: csd0,
            flags: FLAG_CODEC_DATA,
          });
          if let Some(pps) = csd1 {
            // Keep SPS then PPS order.
            if state.pending.len() >= 1 {
              let sps = state.pending.pop_front().unwrap();
              state.pending.push_front(PendingPacket {
                pts_us: 0,
                data: pps,
                flags: FLAG_CODEC_DATA,
              });
              state.pending.push_front(sps);
            }
          }
        }
      } else {
        unsafe {
          OH_NativeWindow_DestroyNativeWindow(new_window);
        }
        return Err("rebind_surface: STATE vanished during swap".into());
      }
    }

    FIRST_FRAME.store(false, Ordering::SeqCst);
    LAST_ERROR.store(0, Ordering::SeqCst);

    let t_start = Instant::now();
    let start_rc = unsafe { OH_VideoDecoder_Start(codec) };
    let start_ms = t_start.elapsed().as_millis();
    if start_rc != AV_ERR_OK {
      return Err(err_msg("rebind Start", start_rc));
    }
    let total_ms = t0.elapsed().as_millis();
    set_detail(format!(
      "SURFACE_REBOUND surfaceId={new_surface_id} (was {old_surface_id}) stop={stop_ms}ms start={start_ms}ms total={total_ms}ms"
    ));
    eprintln!(
      "[ohos_vdec] SURFACE_REBOUND new={new_surface_id} stop_ms={stop_ms} start_ms={start_ms} total_ms={total_ms}"
    );
    Ok(snapshot())
  })();

  match &rebind_result {
    Ok(_) => {
      STARTED.store(true, Ordering::SeqCst);
      REBINDING.store(false, Ordering::SeqCst);
      try_feed();
    }
    Err(e) => {
      eprintln!(
        "[ohos_vdec] SURFACE_REBIND failed +{}ms: {e}",
        t0.elapsed().as_millis()
      );
      STARTED.store(false, Ordering::SeqCst);
      REBINDING.store(false, Ordering::SeqCst);
    }
  }
  rebind_result
}

/// Live stream: configure decoder with CSD only (no EOS). Push AUs via [`push_access_unit`].
pub fn start_live_stream(
  surface_id_str: &str,
  use_h265: bool,
  width: u32,
  height: u32,
  csd0: &[u8],
  csd1: Option<&[u8]>,
) -> Result<StatusSnapshot, String> {
  release();
  reset_counters();

  let surface_id: u64 = surface_id_str
    .trim()
    .parse()
    .map_err(|_| format!("invalid surfaceId '{surface_id_str}'"))?;

  let csd0_owned = csd0.to_vec();
  let csd1_owned = csd1.map(|p| p.to_vec());
  let mut pending = VecDeque::new();
  pending.push_back(PendingPacket {
    pts_us: 0,
    data: csd0_owned.clone(),
    flags: FLAG_CODEC_DATA,
  });
  if let Some(ref pps) = csd1_owned {
    pending.push_back(PendingPacket {
      pts_us: 0,
      data: pps.clone(),
      flags: FLAG_CODEC_DATA,
    });
  }
  start_decoder_inner(
    surface_id,
    use_h265,
    width,
    height,
    pending,
    true,
    "live",
    csd0_owned,
    csd1_owned,
  )
}

/// Queue one Annex-B AU for an already-started live decoder (no EOS).
pub fn push_access_unit(pts_us: i64, payload: &[u8]) -> Result<(), String> {
  if REBINDING.load(Ordering::SeqCst) || RELEASING.load(Ordering::SeqCst) {
    // Drop during surface rebind — live edge will catch up; avoid use-after-free.
    DROPPED_AUS.fetch_add(1, Ordering::Relaxed);
    return Ok(());
  }
  if !STARTED.load(Ordering::SeqCst) {
    return Err("decoder not started".into());
  }
  {
    let mut guard = STATE.lock().map_err(|_| "decoder state lock poisoned".to_string())?;
    let state = guard.as_mut().ok_or("decoder released")?;
    state.pending.push_back(PendingPacket {
      pts_us,
      data: payload.to_vec(),
      flags: au_flags(payload),
    });
    drop_old_live_aus(state);
  }
  try_feed();
  Ok(())
}

/// Bind XComponent surfaceId, configure AVC/HEVC, queue EasyControl bitstream, start decoder.
pub fn play_easycontrol_bitstream(surface_id_str: &str, bitstream: &[u8]) -> Result<StatusSnapshot, String> {
  release();
  reset_counters();

  let surface_id: u64 = surface_id_str
    .trim()
    .parse()
    .map_err(|_| format!("invalid surfaceId '{surface_id_str}'"))?;

  let (hdr, consumed) = video::parse_video_stream_header(bitstream).map_err(|e| e.to_string())?;
  let csd0 = video::strip_pts_prefix(&hdr.csd0)
    .map_err(|e| e.to_string())?
    .to_vec();
  let csd1 = match &hdr.csd1 {
    Some(raw) => Some(video::strip_pts_prefix(raw).map_err(|e| e.to_string())?.to_vec()),
    None => None,
  };

  let mut pending = VecDeque::new();
  pending.push_back(PendingPacket {
    pts_us: 0,
    data: csd0.clone(),
    flags: FLAG_CODEC_DATA,
  });
  if let Some(ref pps) = csd1 {
    pending.push_back(PendingPacket {
      pts_us: 0,
      data: pps.clone(),
      flags: FLAG_CODEC_DATA,
    });
  }

  let mut off = consumed;
  let mut au_count = 0u32;
  while off + 4 <= bitstream.len() && au_count < 64 {
    match video::parse_video_access_unit(&bitstream[off..]) {
      Ok((au, n)) => {
        let flags = au_flags(&au.payload);
        pending.push_back(PendingPacket {
          pts_us: au.pts_us,
          data: au.payload,
          flags,
        });
        off += n;
        au_count += 1;
      }
      Err(_) => break,
    }
  }

  if pending.len() < 2 {
    return Err("bitstream missing CSD/AU for decode".into());
  }
  pending.push_back(PendingPacket {
    pts_us: 0,
    data: Vec::new(),
    flags: FLAG_EOS,
  });

  start_decoder_inner(
    surface_id,
    hdr.use_h265,
    hdr.width,
    hdr.height,
    pending,
    false,
    &format!("aus={au_count}"),
    csd0,
    csd1,
  )
}

/// Poll until first rendered frame or timeout / error.
pub fn wait_first_frame(timeout_ms: u32) -> StatusSnapshot {
  let deadline = Instant::now() + Duration::from_millis(timeout_ms as u64);
  while Instant::now() < deadline {
    if FIRST_FRAME.load(Ordering::SeqCst) {
      break;
    }
    if LAST_ERROR.load(Ordering::SeqCst) != 0 {
      break;
    }
    std::thread::sleep(Duration::from_millis(20));
  }
  snapshot()
}

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

pub fn snapshot() -> StatusSnapshot {
  let (width, height, use_h265, surface_id, pending_len, free_len) = {
    let guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    match guard.as_ref() {
      Some(s) => (
        s.width,
        s.height,
        s.use_h265,
        s.surface_id.to_string(),
        s.pending.len(),
        s.free_inputs.len(),
      ),
      None => (0, 0, false, String::new(), 0, 0),
    }
  };
  let mut detail = LAST_DETAIL
    .lock()
    .map(|g| g.clone())
    .unwrap_or_else(|_| "lock poisoned".into());
  let dropped = DROPPED_AUS.load(Ordering::Relaxed);
  if STARTED.load(Ordering::SeqCst) {
    detail = format!(
      "{detail} | q={pending_len} freeIn={free_len} drop={dropped}"
    );
  }
  StatusSnapshot {
    started: STARTED.load(Ordering::SeqCst),
    first_frame_rendered: FIRST_FRAME.load(Ordering::SeqCst),
    input_queued: INPUT_QUEUED.load(Ordering::SeqCst),
    output_frames: OUTPUT_FRAMES.load(Ordering::SeqCst),
    stream_changed: STREAM_CHANGED.load(Ordering::SeqCst),
    last_error: LAST_ERROR.load(Ordering::SeqCst),
    width,
    height,
    use_h265,
    surface_id,
    detail,
  }
}
