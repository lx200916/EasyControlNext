//! OH_AudioCodec (HW) + OH_AudioRenderer path for EasyControl main-socket audio relay.
//!
//! Mirrors Android `AudioDecode`: Opus or AAC @ 48 kHz stereo → PCM S16LE → AudioTrack/renderer.
//! Prefer hardware decode via `OH_AudioCodec_CreateByMime`; surface status when unavailable.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, Ordering};
use std::sync::Mutex;

const FLAG_CODEC_DATA: u32 = 1 << 3;
const AV_ERR_OK: i32 = 0;
const SAMPLE_RATE: i32 = 48000;
const CHANNELS: i32 = 2;
const BIT_RATE: i64 = 128_000;
const SAMPLE_S16LE: i32 = 1;
const AUDIO_PACKET_SIZE: i32 = SAMPLE_RATE * CHANNELS * 2 * 40 / 1000; // 40ms
/// ~240ms of PCM; drop oldest when full so live audio chases the edge.
const PCM_MAX_BYTES: usize = (SAMPLE_RATE as usize) * (CHANNELS as usize) * 2 * 240 / 1000;
const LIVE_MAX_PENDING: usize = 24;
const CH_LAYOUT_STEREO: i64 = 0x3; // FRONT_LEFT | FRONT_RIGHT

const KEY_AUD_CHANNEL_COUNT: &[u8] = b"OH_MD_KEY_AUD_CHANNEL_COUNT\0";
const KEY_AUD_SAMPLE_RATE: &[u8] = b"OH_MD_KEY_AUD_SAMPLE_RATE\0";
const KEY_BITRATE: &[u8] = b"OH_MD_KEY_BITRATE\0";
const KEY_MAX_INPUT_SIZE: &[u8] = b"OH_MD_KEY_MAX_INPUT_SIZE\0";
const KEY_AUDIO_SAMPLE_FORMAT: &[u8] = b"OH_MD_KEY_AUDIO_SAMPLE_FORMAT\0";
const KEY_CODEC_CONFIG: &[u8] = b"OH_MD_KEY_CODEC_CONFIG\0";
const KEY_CHANNEL_LAYOUT: &[u8] = b"OH_MD_KEY_CHANNEL_LAYOUT\0";
const KEY_AAC_IS_ADTS: &[u8] = b"OH_MD_KEY_AAC_IS_ADTS\0";

#[repr(C)]
struct OH_AVCodec {
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

#[repr(C)]
struct OH_AudioStreamBuilder {
  _private: [u8; 0],
}

#[repr(C)]
struct OH_AudioRenderer {
  _private: [u8; 0],
}

#[link(name = "native_media_acodec")]
extern "C" {
  fn OH_AudioCodec_CreateByMime(mime: *const c_char, is_encoder: bool) -> *mut OH_AVCodec;
  fn OH_AudioCodec_Destroy(codec: *mut OH_AVCodec) -> i32;
  fn OH_AudioCodec_RegisterCallback(
    codec: *mut OH_AVCodec,
    callback: OH_AVCodecCallback,
    user_data: *mut c_void,
  ) -> i32;
  fn OH_AudioCodec_Configure(codec: *mut OH_AVCodec, format: *const OH_AVFormat) -> i32;
  fn OH_AudioCodec_Prepare(codec: *mut OH_AVCodec) -> i32;
  fn OH_AudioCodec_Start(codec: *mut OH_AVCodec) -> i32;
  fn OH_AudioCodec_Stop(codec: *mut OH_AVCodec) -> i32;
  fn OH_AudioCodec_PushInputBuffer(codec: *mut OH_AVCodec, index: u32) -> i32;
  fn OH_AudioCodec_FreeOutputBuffer(codec: *mut OH_AVCodec, index: u32) -> i32;
}

#[link(name = "native_media_core")]
extern "C" {
  fn OH_AVFormat_Create() -> *mut OH_AVFormat;
  fn OH_AVFormat_Destroy(format: *mut OH_AVFormat);
  fn OH_AVFormat_SetIntValue(format: *mut OH_AVFormat, key: *const c_char, value: i32) -> bool;
  fn OH_AVFormat_SetLongValue(format: *mut OH_AVFormat, key: *const c_char, value: i64) -> bool;
  fn OH_AVFormat_SetBuffer(
    format: *mut OH_AVFormat,
    key: *const c_char,
    addr: *const u8,
    size: usize,
  ) -> bool;
  fn OH_AVBuffer_GetAddr(buffer: *mut OH_AVBuffer) -> *mut u8;
  fn OH_AVBuffer_GetCapacity(buffer: *mut OH_AVBuffer) -> i32;
  fn OH_AVBuffer_SetBufferAttr(buffer: *mut OH_AVBuffer, attr: *const OH_AVCodecBufferAttr) -> i32;
  fn OH_AVBuffer_GetBufferAttr(buffer: *mut OH_AVBuffer, attr: *mut OH_AVCodecBufferAttr) -> i32;
}

#[link(name = "ohaudio")]
extern "C" {
  fn OH_AudioStreamBuilder_Create(builder: *mut *mut OH_AudioStreamBuilder, typ: i32) -> i32;
  fn OH_AudioStreamBuilder_Destroy(builder: *mut OH_AudioStreamBuilder) -> i32;
  fn OH_AudioStreamBuilder_SetSamplingRate(builder: *mut OH_AudioStreamBuilder, rate: i32) -> i32;
  fn OH_AudioStreamBuilder_SetChannelCount(builder: *mut OH_AudioStreamBuilder, count: i32) -> i32;
  fn OH_AudioStreamBuilder_SetSampleFormat(builder: *mut OH_AudioStreamBuilder, format: i32) -> i32;
  fn OH_AudioStreamBuilder_SetEncodingType(builder: *mut OH_AudioStreamBuilder, encoding: i32) -> i32;
  fn OH_AudioStreamBuilder_SetRendererInfo(builder: *mut OH_AudioStreamBuilder, usage: i32) -> i32;
  fn OH_AudioStreamBuilder_SetRendererWriteDataCallback(
    builder: *mut OH_AudioStreamBuilder,
    callback: Option<
      extern "C" fn(*mut OH_AudioRenderer, *mut c_void, *mut c_void, i32) -> i32,
    >,
    user_data: *mut c_void,
  ) -> i32;
  fn OH_AudioStreamBuilder_GenerateRenderer(
    builder: *mut OH_AudioStreamBuilder,
    renderer: *mut *mut OH_AudioRenderer,
  ) -> i32;
  fn OH_AudioRenderer_Start(renderer: *mut OH_AudioRenderer) -> i32;
  fn OH_AudioRenderer_Stop(renderer: *mut OH_AudioRenderer) -> i32;
  fn OH_AudioRenderer_Release(renderer: *mut OH_AudioRenderer) -> i32;
}

struct PendingPacket {
  data: Vec<u8>,
  flags: u32,
}

struct FreeInput {
  index: u32,
  buffer: *mut OH_AVBuffer,
}

struct DecoderState {
  codec: *mut OH_AVCodec,
  renderer: *mut OH_AudioRenderer,
  builder: *mut OH_AudioStreamBuilder,
  pending: VecDeque<PendingPacket>,
  free_inputs: VecDeque<FreeInput>,
  pcm: VecDeque<u8>,
  use_opus: bool,
}

unsafe impl Send for DecoderState {}

static STATE: Mutex<Option<DecoderState>> = Mutex::new(None);
static STARTED: AtomicBool = AtomicBool::new(false);
static RELEASING: AtomicBool = AtomicBool::new(false);
static INPUT_QUEUED: AtomicU32 = AtomicU32::new(0);
static OUTPUT_FRAMES: AtomicU32 = AtomicU32::new(0);
static PCM_WRITTEN: AtomicU32 = AtomicU32::new(0);
static LAST_ERROR: AtomicI32 = AtomicI32::new(0);
static DROPPED: AtomicU32 = AtomicU32::new(0);
static LAST_DETAIL: Mutex<String> = Mutex::new(String::new());

#[derive(Clone, Debug, Default)]
pub struct StatusSnapshot {
  pub started: bool,
  pub use_opus: bool,
  pub input_queued: u32,
  pub output_frames: u32,
  pub pcm_written: u32,
  pub last_error: i32,
  pub detail: String,
}

fn set_detail(msg: impl Into<String>) {
  if let Ok(mut g) = LAST_DETAIL.lock() {
    *g = msg.into();
  }
}

fn mime_for(use_opus: bool) -> &'static [u8] {
  if use_opus {
    b"audio/opus\0"
  } else {
    b"audio/mp4a-latm\0"
  }
}

fn feed_allowed() -> bool {
  STARTED.load(Ordering::SeqCst) && !RELEASING.load(Ordering::SeqCst)
}

extern "C" fn on_error(_codec: *mut OH_AVCodec, error_code: i32, _user: *mut c_void) {
  LAST_ERROR.store(error_code, Ordering::SeqCst);
  set_detail(format!("audio decoder onError code={error_code}"));
}

extern "C" fn on_stream_changed(
  _codec: *mut OH_AVCodec,
  _format: *mut OH_AVFormat,
  _user: *mut c_void,
) {
}

struct SubmitJob {
  codec: *mut OH_AVCodec,
  index: u32,
  buffer: *mut OH_AVBuffer,
  data: Vec<u8>,
  flags: u32,
}

fn take_submit_jobs(state: &mut DecoderState) -> Vec<SubmitJob> {
  let mut jobs = Vec::new();
  while !state.free_inputs.is_empty() && !state.pending.is_empty() {
    let free = state.free_inputs.pop_front().unwrap();
    let packet = state.pending.pop_front().unwrap();
    jobs.push(SubmitJob {
      codec: state.codec,
      index: free.index,
      buffer: free.buffer,
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
        LAST_ERROR.store(-200, Ordering::SeqCst);
        set_detail("audio input buffer null/empty");
        continue;
      }
      if job.data.len() as i32 > cap {
        LAST_ERROR.store(-201, Ordering::SeqCst);
        set_detail(format!(
          "audio packet {}B exceeds input capacity {cap}",
          job.data.len()
        ));
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
        pts: 0,
        size: job.data.len() as i32,
        offset: 0,
        flags: job.flags,
      };
      let set_rc = OH_AVBuffer_SetBufferAttr(job.buffer, &attr);
      let push_rc = OH_AudioCodec_PushInputBuffer(job.codec, job.index);
      if set_rc != AV_ERR_OK || push_rc != AV_ERR_OK {
        LAST_ERROR.store(
          if set_rc != AV_ERR_OK {
            set_rc
          } else {
            push_rc
          },
          Ordering::SeqCst,
        );
        set_detail(format!("audio push failed set={set_rc} push={push_rc}"));
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
  if !feed_allowed() {
    if let Ok(mut guard) = STATE.lock() {
      if let Some(state) = guard.as_mut() {
        for job in jobs.into_iter().rev() {
          if state.codec == job.codec {
            state.free_inputs.push_front(FreeInput {
              index: job.index,
              buffer: job.buffer,
            });
            state.pending.push_front(PendingPacket {
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

fn drop_old_pending(state: &mut DecoderState) {
  while state.pending.len() > LIVE_MAX_PENDING {
    let front_is_csd = state
      .pending
      .front()
      .map(|p| (p.flags & FLAG_CODEC_DATA) != 0)
      .unwrap_or(false);
    if front_is_csd {
      if state.pending.len() < 2 {
        break;
      }
      let csd = state.pending.pop_front().unwrap();
      let _ = state.pending.pop_front();
      state.pending.push_front(csd);
      DROPPED.fetch_add(1, Ordering::Relaxed);
    } else {
      let _ = state.pending.pop_front();
      DROPPED.fetch_add(1, Ordering::Relaxed);
    }
  }
}

extern "C" fn on_need_input(
  _codec: *mut OH_AVCodec,
  index: u32,
  buffer: *mut OH_AVBuffer,
  _user: *mut c_void,
) {
  if RELEASING.load(Ordering::SeqCst) {
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
    state.free_inputs.push_back(FreeInput { index, buffer });
  }
  try_feed();
}

extern "C" fn on_new_output(
  codec: *mut OH_AVCodec,
  index: u32,
  buffer: *mut OH_AVBuffer,
  _user: *mut c_void,
) {
  if RELEASING.load(Ordering::SeqCst) {
    return;
  }
  unsafe {
    let mut attr = OH_AVCodecBufferAttr {
      pts: 0,
      size: 0,
      offset: 0,
      flags: 0,
    };
    let _ = OH_AVBuffer_GetBufferAttr(buffer, &mut attr);
    if attr.size > 0 {
      let addr = OH_AVBuffer_GetAddr(buffer);
      if !addr.is_null() {
        let slice = std::slice::from_raw_parts(addr.add(attr.offset as usize), attr.size as usize);
        if let Ok(mut guard) = STATE.lock() {
          if let Some(state) = guard.as_mut() {
            if state.codec == codec {
              for b in slice {
                if state.pcm.len() >= PCM_MAX_BYTES {
                  let _ = state.pcm.pop_front();
                  DROPPED.fetch_add(1, Ordering::Relaxed);
                }
                state.pcm.push_back(*b);
              }
            }
          }
        }
        OUTPUT_FRAMES.fetch_add(1, Ordering::SeqCst);
      }
    }
    let _ = OH_AudioCodec_FreeOutputBuffer(codec, index);
  }
}

extern "C" fn on_write_data(
  _renderer: *mut OH_AudioRenderer,
  _user: *mut c_void,
  audio_data: *mut c_void,
  audio_data_size: i32,
) -> i32 {
  if audio_data.is_null() || audio_data_size <= 0 {
    return -1; // AUDIO_DATA_CALLBACK_RESULT_INVALID
  }
  let out = unsafe { std::slice::from_raw_parts_mut(audio_data as *mut u8, audio_data_size as usize) };
  let mut filled = 0usize;
  if let Ok(mut guard) = STATE.lock() {
    if let Some(state) = guard.as_mut() {
      while filled < out.len() {
        match state.pcm.pop_front() {
          Some(b) => {
            out[filled] = b;
            filled += 1;
          }
          None => break,
        }
      }
    }
  }
  if filled == 0 {
    // No PCM yet — silence rather than INVALID (keeps renderer draining).
    out.fill(0);
    return 0;
  }
  if filled < out.len() {
    out[filled..].fill(0);
  }
  PCM_WRITTEN.fetch_add(filled as u32, Ordering::Relaxed);
  0 // AUDIO_DATA_CALLBACK_RESULT_VALID
}

fn destroy_inner(state: &mut DecoderState) {
  unsafe {
    if !state.renderer.is_null() {
      let _ = OH_AudioRenderer_Stop(state.renderer);
      let _ = OH_AudioRenderer_Release(state.renderer);
      state.renderer = std::ptr::null_mut();
    }
    if !state.builder.is_null() {
      let _ = OH_AudioStreamBuilder_Destroy(state.builder);
      state.builder = std::ptr::null_mut();
    }
    if !state.codec.is_null() {
      let _ = OH_AudioCodec_Stop(state.codec);
      let _ = OH_AudioCodec_Destroy(state.codec);
      state.codec = std::ptr::null_mut();
    }
  }
  state.pending.clear();
  state.free_inputs.clear();
  state.pcm.clear();
}

pub fn release() {
  if RELEASING.swap(true, Ordering::SeqCst) {
    return;
  }
  STARTED.store(false, Ordering::SeqCst);
  if let Ok(mut guard) = STATE.lock() {
    if let Some(mut state) = guard.take() {
      destroy_inner(&mut state);
    }
  }
  RELEASING.store(false, Ordering::SeqCst);
  set_detail("audio released");
}

/// Start HW audio decode + OHAudio renderer. `csd0` is the first type-1 payload (codec config).
pub fn start(use_opus: bool, csd0: &[u8]) -> Result<StatusSnapshot, String> {
  release();
  LAST_ERROR.store(0, Ordering::SeqCst);
  INPUT_QUEUED.store(0, Ordering::SeqCst);
  OUTPUT_FRAMES.store(0, Ordering::SeqCst);
  PCM_WRITTEN.store(0, Ordering::SeqCst);
  DROPPED.store(0, Ordering::SeqCst);

  let mime = mime_for(use_opus);
  let codec = unsafe { OH_AudioCodec_CreateByMime(mime.as_ptr() as *const c_char, false) };
  if codec.is_null() {
    let msg = format!(
      "OH_AudioCodec_CreateByMime returned null mime={}",
      if use_opus { "audio/opus" } else { "audio/mp4a-latm" }
    );
    set_detail(msg.clone());
    return Err(msg);
  }

  let cb = OH_AVCodecCallback {
    on_error: Some(on_error),
    on_stream_changed: Some(on_stream_changed),
    on_need_input_buffer: Some(on_need_input),
    on_new_output_buffer: Some(on_new_output),
  };
  let rc = unsafe { OH_AudioCodec_RegisterCallback(codec, cb, std::ptr::null_mut()) };
  if rc != AV_ERR_OK {
    unsafe {
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioCodec_RegisterCallback failed rc={rc}");
    set_detail(msg.clone());
    return Err(msg);
  }

  let format = unsafe { OH_AVFormat_Create() };
  if format.is_null() {
    unsafe {
      let _ = OH_AudioCodec_Destroy(codec);
    }
    return Err("OH_AVFormat_Create failed".into());
  }
  unsafe {
    let _ = OH_AVFormat_SetIntValue(
      format,
      KEY_AUD_SAMPLE_RATE.as_ptr() as *const c_char,
      SAMPLE_RATE,
    );
    let _ = OH_AVFormat_SetIntValue(
      format,
      KEY_AUD_CHANNEL_COUNT.as_ptr() as *const c_char,
      CHANNELS,
    );
    let _ = OH_AVFormat_SetLongValue(format, KEY_BITRATE.as_ptr() as *const c_char, BIT_RATE);
    let _ = OH_AVFormat_SetIntValue(
      format,
      KEY_MAX_INPUT_SIZE.as_ptr() as *const c_char,
      AUDIO_PACKET_SIZE,
    );
    let _ = OH_AVFormat_SetIntValue(
      format,
      KEY_AUDIO_SAMPLE_FORMAT.as_ptr() as *const c_char,
      SAMPLE_S16LE,
    );
    let _ = OH_AVFormat_SetLongValue(
      format,
      KEY_CHANNEL_LAYOUT.as_ptr() as *const c_char,
      CH_LAYOUT_STEREO,
    );
    if !use_opus {
      let _ = OH_AVFormat_SetIntValue(format, KEY_AAC_IS_ADTS.as_ptr() as *const c_char, 0);
    }
    if !csd0.is_empty() {
      let _ = OH_AVFormat_SetBuffer(
        format,
        KEY_CODEC_CONFIG.as_ptr() as *const c_char,
        csd0.as_ptr(),
        csd0.len(),
      );
    }
  }

  let cfg_rc = unsafe { OH_AudioCodec_Configure(codec, format) };
  unsafe {
    OH_AVFormat_Destroy(format);
  }
  if cfg_rc != AV_ERR_OK {
    unsafe {
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioCodec_Configure failed rc={cfg_rc}");
    set_detail(msg.clone());
    return Err(msg);
  }

  let prep_rc = unsafe { OH_AudioCodec_Prepare(codec) };
  if prep_rc != AV_ERR_OK {
    unsafe {
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioCodec_Prepare failed rc={prep_rc}");
    set_detail(msg.clone());
    return Err(msg);
  }

  // OHAudio renderer (PCM S16LE stereo 48kHz).
  let mut builder: *mut OH_AudioStreamBuilder = std::ptr::null_mut();
  let create_rc = unsafe { OH_AudioStreamBuilder_Create(&mut builder, 1) }; // RENDERER
  if create_rc != 0 || builder.is_null() {
    unsafe {
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioStreamBuilder_Create failed rc={create_rc}");
    set_detail(msg.clone());
    return Err(msg);
  }
  unsafe {
    let _ = OH_AudioStreamBuilder_SetSamplingRate(builder, SAMPLE_RATE);
    let _ = OH_AudioStreamBuilder_SetChannelCount(builder, CHANNELS);
    let _ = OH_AudioStreamBuilder_SetSampleFormat(builder, 1); // S16LE
    let _ = OH_AudioStreamBuilder_SetEncodingType(builder, 0); // RAW
    let _ = OH_AudioStreamBuilder_SetRendererInfo(builder, 1); // MUSIC
    let _ = OH_AudioStreamBuilder_SetRendererWriteDataCallback(builder, Some(on_write_data), std::ptr::null_mut());
  }
  let mut renderer: *mut OH_AudioRenderer = std::ptr::null_mut();
  let gen_rc = unsafe { OH_AudioStreamBuilder_GenerateRenderer(builder, &mut renderer) };
  if gen_rc != 0 || renderer.is_null() {
    unsafe {
      let _ = OH_AudioStreamBuilder_Destroy(builder);
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioStreamBuilder_GenerateRenderer failed rc={gen_rc}");
    set_detail(msg.clone());
    return Err(msg);
  }

  let start_dec = unsafe { OH_AudioCodec_Start(codec) };
  if start_dec != AV_ERR_OK {
    unsafe {
      let _ = OH_AudioRenderer_Release(renderer);
      let _ = OH_AudioStreamBuilder_Destroy(builder);
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioCodec_Start failed rc={start_dec}");
    set_detail(msg.clone());
    return Err(msg);
  }
  let start_ren = unsafe { OH_AudioRenderer_Start(renderer) };
  if start_ren != 0 {
    unsafe {
      let _ = OH_AudioCodec_Stop(codec);
      let _ = OH_AudioRenderer_Release(renderer);
      let _ = OH_AudioStreamBuilder_Destroy(builder);
      let _ = OH_AudioCodec_Destroy(codec);
    }
    let msg = format!("OH_AudioRenderer_Start failed rc={start_ren}");
    set_detail(msg.clone());
    return Err(msg);
  }

  let state = DecoderState {
    codec,
    renderer,
    builder,
    pending: VecDeque::new(),
    free_inputs: VecDeque::new(),
    pcm: VecDeque::new(),
    use_opus,
  };
  // CSD is applied via OH_MD_KEY_CODEC_CONFIG only (Android AudioDecode parity —
  // first type-1 frame is configure-only, not also decodeIn'd).

  if let Ok(mut guard) = STATE.lock() {
    *guard = Some(state);
  }
  STARTED.store(true, Ordering::SeqCst);
  RELEASING.store(false, Ordering::SeqCst);
  let codec_name = if use_opus { "opus" } else { "aac" };
  set_detail(format!("audio HW decode started codec={codec_name}"));
  eprintln!("[LiveAudio] started HW codec={codec_name} csd0={}B", csd0.len());
  Ok(snapshot())
}

pub fn push_packet(data: &[u8]) -> Result<(), String> {
  if !feed_allowed() {
    return Err("audio decoder not started".into());
  }
  if data.is_empty() {
    return Ok(());
  }
  {
    let mut guard = STATE
      .lock()
      .map_err(|_| "audio state lock poisoned".to_string())?;
    let state = guard.as_mut().ok_or("audio decoder missing")?;
    state.pending.push_back(PendingPacket {
      data: data.to_vec(),
      flags: 0,
    });
    drop_old_pending(state);
  }
  try_feed();
  Ok(())
}

pub fn snapshot() -> StatusSnapshot {
  let use_opus = STATE
    .lock()
    .ok()
    .and_then(|g| g.as_ref().map(|s| s.use_opus))
    .unwrap_or(false);
  let detail = LAST_DETAIL.lock().map(|g| g.clone()).unwrap_or_default();
  StatusSnapshot {
    started: STARTED.load(Ordering::SeqCst),
    use_opus,
    input_queued: INPUT_QUEUED.load(Ordering::SeqCst),
    output_frames: OUTPUT_FRAMES.load(Ordering::SeqCst),
    pcm_written: PCM_WRITTEN.load(Ordering::SeqCst),
    last_error: LAST_ERROR.load(Ordering::SeqCst),
    detail,
  }
}

/// Create+destroy only — does not touch the live audio decoder STATE.
pub fn probe_create(use_opus: bool) -> Result<(), String> {
  let mime = mime_for(use_opus);
  let mime_label = if use_opus { "audio/opus" } else { "audio/mp4a-latm" };
  let codec = unsafe { OH_AudioCodec_CreateByMime(mime.as_ptr() as *const c_char, false) };
  if codec.is_null() {
    return Err(format!("CreateByMime null ({mime_label})"));
  }
  unsafe {
    OH_AudioCodec_Destroy(codec);
  }
  Ok(())
}
