//! Reproduce Android `ClientStream.startServer()` launch semantics for Gate D / session bring-up.
//!
//! Remote jar path: `/data/local/tmp/easycontrolnext_server_<app_version_code>.jar`
//! Launch: interactive `shell:` + `app_process -Djava.class.path=... / com.shiyunjin.easycontrolnext.server.Server …`
//!
//! Dual sockets: client opens **main** then **video** to `serverPort` (default 25166), matching
//! `Server.connectClient()` accept order. Direct TCP preferred; ADB `tcp:<port>` is the fallback.

#![deny(unsafe_code)]

use std::fs;
use std::path::Path;

use crate::error::{AdbError, AdbResult};
use crate::session::AdbSession;
use crate::transport::AdbTransport;

/// Default EasyControl server listen port (`Device.serverPort` / `Options.serverPort`).
pub const DEFAULT_SERVER_PORT: u16 = 25166;

/// Fallback app `versionCode` when metadata is missing (matches current easycontrolnext/app).
pub const DEFAULT_APP_VERSION_CODE: u32 = 10014;

/// Options mirrored from `ClientStream.startServer()` / `Device` defaults.
#[derive(Debug, Clone)]
pub struct ServerLaunchOptions {
  pub app_version_code: u32,
  pub server_port: u16,
  pub listen_clip: bool,
  pub is_audio: bool,
  pub max_size: u32,
  pub max_fps: u32,
  /// Megabits; server multiplies by 1_000_000 (`Options.maxVideoBit`).
  pub max_video_bit: u32,
  pub keep_awake: bool,
  pub support_h265: bool,
  /// `main10` | `main` | `0` (none / AVC).
  pub hevc_profile: String,
  pub support_opus: bool,
  pub video_source: String,
  pub camera_facing: String,
  pub virtual_width: u32,
  pub virtual_height: u32,
  pub virtual_dpi: u32,
  pub start_app: String,
}

impl Default for ServerLaunchOptions {
  fn default() -> Self {
    Self {
      app_version_code: DEFAULT_APP_VERSION_CODE,
      server_port: DEFAULT_SERVER_PORT,
      listen_clip: true,
      is_audio: false,
      max_size: 1600,
      max_fps: 60,
      max_video_bit: 4,
      keep_awake: true,
      // Gate D defaults to AVC for simpler CSD (csd0+csd1) validation.
      support_h265: false,
      hevc_profile: "0".into(),
      support_opus: false,
      video_source: "display".into(),
      camera_facing: "back".into(),
      virtual_width: 0,
      virtual_height: 0,
      virtual_dpi: 0,
      start_app: String::new(),
    }
  }
}

impl ServerLaunchOptions {
  pub fn remote_jar_name(&self) -> String {
    format!("easycontrolnext_server_{}.jar", self.app_version_code)
  }

  pub fn remote_jar_path(&self) -> String {
    format!("/data/local/tmp/{}", self.remote_jar_name())
  }

  /// Exact `app_process …` line written to interactive shell (trailing space + newline like ClientStream).
  pub fn app_process_command(&self) -> String {
    let server_name = self.remote_jar_path();
    format!(
      "app_process -Djava.class.path={server_name} / com.shiyunjin.easycontrolnext.server.Server serverPort={} listenClip={} isAudio={} maxSize={} maxFps={} maxVideoBit={} keepAwake={} supportH265={} hevcProfile={} supportOpus={} videoSource={} cameraFacing={} virtualWidth={} virtualHeight={} virtualDpi={} startApp={} \n",
      self.server_port,
      bool01(self.listen_clip),
      bool01(self.is_audio),
      self.max_size,
      self.max_fps,
      self.max_video_bit,
      bool01(self.keep_awake),
      bool01(self.support_h265),
      self.hevc_profile,
      bool01(self.support_opus),
      self.video_source,
      self.camera_facing,
      self.virtual_width,
      self.virtual_height,
      self.virtual_dpi,
      self.start_app,
    )
  }
}

fn bool01(v: bool) -> u8 {
  if v {
    1
  } else {
    0
  }
}

/// Sidecar written by `scripts/copy_server_jar.sh`.
#[derive(Debug, Clone)]
pub struct ServerJarMeta {
  pub app_version_code: u32,
  pub remote_path: String,
  pub sha256: Option<String>,
  pub size: Option<u64>,
}

pub fn parse_server_version_file(text: &str) -> AdbResult<ServerJarMeta> {
  let mut app_version_code = None;
  let mut remote_path = None;
  let mut sha256 = None;
  let mut size = None;
  for raw in text.lines() {
    let line = raw.trim();
    if line.is_empty() || line.starts_with('#') {
      continue;
    }
    let Some((k, v)) = line.split_once('=') else {
      continue;
    };
    match k.trim() {
      "app_version_code" => {
        app_version_code = Some(
          v.trim()
            .parse::<u32>()
            .map_err(|_| AdbError::InvalidState("bad app_version_code in version file"))?,
        );
      }
      "remote_path" => remote_path = Some(v.trim().to_string()),
      "sha256" => sha256 = Some(v.trim().to_string()),
      "size" => {
        size = Some(
          v.trim()
            .parse::<u64>()
            .map_err(|_| AdbError::InvalidState("bad size in version file"))?,
        );
      }
      _ => {}
    }
  }
  let app_version_code = app_version_code.unwrap_or(DEFAULT_APP_VERSION_CODE);
  let remote_path = remote_path.unwrap_or_else(|| {
    format!("/data/local/tmp/easycontrolnext_server_{app_version_code}.jar")
  });
  Ok(ServerJarMeta {
    app_version_code,
    remote_path,
    sha256,
    size,
  })
}

pub fn load_server_jar_meta(path: &Path) -> AdbResult<ServerJarMeta> {
  let text = fs::read_to_string(path).map_err(AdbError::Io)?;
  parse_server_version_file(&text)
}

/// Best-effort stop of a previous EasyControl server before re-launch.
///
/// Does **not** delete the versioned jar / sha sidecar — ClientStream skips re-push when the
/// remote jar name already exists; wiping every connect was a major cold-start cost.
pub fn stop_existing_server<T: AdbTransport>(session: &mut AdbSession<T>) -> AdbResult<String> {
  let out = session.shell(
    "pkill -f easycontrolnext_server_ >/dev/null 2>&1 || true; \
pkill -f com.shiyunjin.easycontrolnext.server.Server >/dev/null 2>&1 || true; \
echo STOP_DONE",
  )?;
  Ok(String::from_utf8_lossy(&out).trim().to_string())
}

/// Result of [`ensure_server_jar`]: skip push when remote sha sidecar matches local jar.
#[derive(Debug, Clone)]
pub struct EnsureJarResult {
  pub pushed: bool,
  pub sha256_hex: String,
  pub remote_path: String,
}

/// Sidecar written next to the remote jar after a successful push (`*.jar.sha256`).
pub fn remote_jar_sha_sidecar(opts: &ServerLaunchOptions) -> String {
  format!("{}.sha256", opts.remote_jar_path())
}

fn parse_remote_sha_line(text: &str) -> Option<String> {
  for raw in text.lines() {
    let line = raw.trim();
    if line.is_empty() || line == "MISSING" || line == "NOSIDE" {
      continue;
    }
    if let Some(rest) = line.strip_prefix("sha256=") {
      let v = rest.trim();
      if v.len() == 64 && v.chars().all(|c| c.is_ascii_hexdigit()) {
        return Some(v.to_ascii_lowercase());
      }
    }
    // `sha256sum` / `toybox sha256sum` → "<hex>  <path>"
    let token = line.split_whitespace().next().unwrap_or("");
    if token.len() == 64 && token.chars().all(|c| c.is_ascii_hexdigit()) {
      return Some(token.to_ascii_lowercase());
    }
  }
  None
}

/// Push jar only when missing or sha mismatch (Android ClientStream-inspired + Phase 4 sidecar).
pub fn ensure_server_jar<T: AdbTransport>(
  session: &mut AdbSession<T>,
  opts: &ServerLaunchOptions,
  jar_bytes: &[u8],
) -> AdbResult<EnsureJarResult> {
  if jar_bytes.is_empty() {
    return Err(AdbError::InvalidState("server jar is empty"));
  }
  let local_sha = crate::sha256_hex(jar_bytes);
  let jar_path = opts.remote_jar_path();
  let sidecar = remote_jar_sha_sidecar(opts);

  // Fast path: jar present + sidecar sha matches (avoid hashing ~50KB+ over shell every connect).
  let check = session.shell(&format!(
    "if [ -f '{jar_path}' ]; then cat '{sidecar}' 2>/dev/null || echo NOSIDE; else echo MISSING; fi"
  ))?;
  let check_text = String::from_utf8_lossy(&check);
  if !check_text.contains("MISSING") {
    if let Some(remote) = parse_remote_sha_line(&check_text) {
      if remote == local_sha {
        return Ok(EnsureJarResult {
          pushed: false,
          sha256_hex: local_sha,
          remote_path: jar_path,
        });
      }
    } else if check_text.contains("NOSIDE") {
      // Legacy jar without sidecar: one-shot remote hash, then write sidecar.
      let sum = session.shell(&format!(
        "toybox sha256sum '{jar_path}' 2>/dev/null || sha256sum '{jar_path}' 2>/dev/null || echo NOSUM"
      ))?;
      let sum_text = String::from_utf8_lossy(&sum);
      if let Some(remote) = parse_remote_sha_line(&sum_text) {
        if remote == local_sha {
          let _ = session.shell(&format!("printf 'sha256={local_sha}\\n' > '{sidecar}'"));
          return Ok(EnsureJarResult {
            pushed: false,
            sha256_hex: local_sha,
            remote_path: jar_path,
          });
        }
      }
    }
  }

  let plan = session.sync_push(&jar_path, jar_bytes)?;
  if plan.sha256_hex != local_sha {
    return Err(AdbError::InvalidState("push sha mismatch vs local jar"));
  }
  let _ = session.shell(&format!("printf 'sha256={local_sha}\\n' > '{sidecar}'"));
  Ok(EnsureJarResult {
    pushed: true,
    sha256_hex: plan.sha256_hex,
    remote_path: jar_path,
  })
}

/// Push jar bytes to the versioned remote path (always overwrite).
pub fn push_server_jar<T: AdbTransport>(
  session: &mut AdbSession<T>,
  opts: &ServerLaunchOptions,
  jar_bytes: &[u8],
) -> AdbResult<crate::SyncPushPlan> {
  if jar_bytes.is_empty() {
    return Err(AdbError::InvalidState("server jar is empty"));
  }
  session.sync_push(&opts.remote_jar_path(), jar_bytes)
}

/// Launch server via ADB `shell:<app_process …>` (keeps stream open while process runs).
///
/// Prefer this over interactive `shell:` + WRTE: host `adb shell app_process …` is the path
/// validated on-device, and it avoids PTY/write-credit races during Gate D bring-up.
/// Returns shell local_id — keep alive for the server process lifetime (do not wait for CLSE).
pub fn start_server_shell<T: AdbTransport>(
  session: &mut AdbSession<T>,
  opts: &ServerLaunchOptions,
) -> AdbResult<u32> {
  let mut cmd = opts.app_process_command();
  while cmd.ends_with('\n') || cmd.ends_with(' ') {
    cmd.pop();
  }
  let dest = format!("shell:{cmd}");
  session.open(&dest)
}

/// ClientStream-compatible path: interactive `shell:` then write the launch line + newline.
pub fn start_server_shell_interactive<T: AdbTransport>(
  session: &mut AdbSession<T>,
  opts: &ServerLaunchOptions,
) -> AdbResult<u32> {
  let id = session.open("shell:")?;
  let cmd = opts.app_process_command();
  session.write_stream(id, cmd.as_bytes())?;
  Ok(id)
}

pub use easycontrol_protocol::video::{
  parse_video_access_unit, parse_video_stream_header, VideoAccessUnit, VideoStreamHeader,
};

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn remote_path_uses_app_version_code() {
    let mut opts = ServerLaunchOptions::default();
    opts.app_version_code = 10014;
    assert_eq!(
      opts.remote_jar_path(),
      "/data/local/tmp/easycontrolnext_server_10014.jar"
    );
  }

  #[test]
  fn app_process_command_matches_client_stream_shape() {
    let opts = ServerLaunchOptions::default();
    let cmd = opts.app_process_command();
    assert!(cmd.starts_with(
      "app_process -Djava.class.path=/data/local/tmp/easycontrolnext_server_10014.jar / com.shiyunjin.easycontrolnext.server.Server "
    ));
    assert!(cmd.contains("serverPort=25166"));
    assert!(cmd.contains("listenClip=1"));
    assert!(cmd.contains("isAudio=0"));
    assert!(cmd.contains("supportH265=0"));
    assert!(cmd.contains("hevcProfile=0"));
    assert!(cmd.contains("videoSource=display"));
    assert!(cmd.ends_with("startApp= \n") || cmd.contains("startApp= \n"));
    assert!(cmd.ends_with('\n'));
  }

  #[test]
  fn app_process_command_camera_and_start_app() {
    let mut opts = ServerLaunchOptions::default();
    opts.video_source = "camera".into();
    opts.camera_facing = "front".into();
    opts.start_app = String::new();
    let cam = opts.app_process_command();
    assert!(cam.contains("videoSource=camera"));
    assert!(cam.contains("cameraFacing=front"));

    opts.video_source = "display".into();
    opts.camera_facing = "back".into();
    opts.start_app = "com.example.app".into();
    opts.virtual_width = 1080;
    opts.virtual_height = 1920;
    opts.virtual_dpi = 420;
    let app = opts.app_process_command();
    assert!(app.contains("videoSource=display"));
    assert!(app.contains("startApp=com.example.app"));
    assert!(app.contains("virtualWidth=1080"));
    assert!(app.contains("virtualHeight=1920"));
    assert!(app.contains("virtualDpi=420"));
  }

  #[test]
  fn parse_version_file() {
    let meta = parse_server_version_file(
      "# comment\napp_version_code=10014\nremote_path=/data/local/tmp/easycontrolnext_server_10014.jar\nsha256=abc\nsize=12\n",
    )
    .unwrap();
    assert_eq!(meta.app_version_code, 10014);
    assert_eq!(meta.size, Some(12));
    assert_eq!(meta.sha256.as_deref(), Some("abc"));
  }

  #[test]
  fn parse_remote_sha_sidecar_and_sum() {
    assert_eq!(
      parse_remote_sha_line("sha256=8885e98ed42bb491d3fb9bb640e874bde399dbc1bd1c2f323cb0f1adf378cb2d\n"),
      Some("8885e98ed42bb491d3fb9bb640e874bde399dbc1bd1c2f323cb0f1adf378cb2d".into())
    );
    assert_eq!(
      parse_remote_sha_line(
        "8885e98ed42bb491d3fb9bb640e874bde399dbc1bd1c2f323cb0f1adf378cb2d  /data/local/tmp/x.jar\n"
      ),
      Some("8885e98ed42bb491d3fb9bb640e874bde399dbc1bd1c2f323cb0f1adf378cb2d".into())
    );
    assert_eq!(parse_remote_sha_line("MISSING\n"), None);
  }

  fn push_pts_frame(buf: &mut Vec<u8>, nal: &[u8]) {
    let mut body = vec![0u8; 8]; // pts = 0
    body.extend_from_slice(nal);
    buf.extend_from_slice(&(body.len() as u32).to_be_bytes());
    buf.extend_from_slice(&body);
  }

  #[test]
  fn parse_video_header_avc() {
    let mut buf = vec![0u8]; // AVC
    buf.extend_from_slice(&1280u32.to_be_bytes());
    buf.extend_from_slice(&720u32.to_be_bytes());
    let sps = [0x00, 0x00, 0x00, 0x01, 0x67];
    let pps = [0x00, 0x00, 0x00, 0x01, 0x68];
    push_pts_frame(&mut buf, &sps);
    push_pts_frame(&mut buf, &pps);
    let (hdr, consumed) = parse_video_stream_header(&buf).unwrap();
    assert!(!hdr.use_h265);
    assert_eq!((hdr.width, hdr.height), (1280, 720));
    assert!(hdr.csd0.len() > 8);
    assert_eq!(&hdr.csd0[8..], &sps);
    assert_eq!(hdr.csd1.as_ref().map(|v| &v[8..]), Some(pps.as_slice()));
    assert_eq!(consumed, buf.len());
  }
}
