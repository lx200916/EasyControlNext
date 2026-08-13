//! Gate D: push EasyControl server.jar, launch via app_process, open main+video sockets.
//!
//! Usage:
//!   cargo run -p easycontrol-adb-client --bin gate_d -- \
//!     192.168.31.60 5555 [--server-port 25166] [--jar PATH]
//!
//! Reuses Gate C RSA keys under `native/.adb-keys/easycontrol_gate_c`.
//! Prefer direct TCP to the Android device IP; falls back to ADB `tcp:<port>`.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use easycontrol_adb_client::{
  connect_dual, connect_tcp, ensure_server_jar, load_server_jar_meta, read_adb_at_least,
  read_exact_timeout, read_video_header_adb, read_video_header_tcp, sha256_hex, start_server_shell,
  stop_existing_server, AdbSession, RsaAdbSigner, ServerLaunchOptions, SessionState,
  DEFAULT_APP_VERSION_CODE, DEFAULT_SERVER_PORT,
};
use easycontrol_protocol::control;

fn main() {
  if let Err(e) = run() {
    eprintln!("gate_d FAILED: {e}");
    std::process::exit(1);
  }
}

struct Cli {
  host: String,
  adb_port: u16,
  server_port: u16,
  jar_path: Option<PathBuf>,
  start_app: String,
}

fn parse_cli() -> Result<Cli, String> {
  let mut host = "192.168.31.60".to_string();
  let mut adb_port: u16 = 5555;
  let mut server_port: u16 = DEFAULT_SERVER_PORT;
  let mut jar_path: Option<PathBuf> = None;
  let mut start_app = String::new();
  let mut positionals: Vec<String> = Vec::new();

  let mut args = std::env::args().skip(1).peekable();
  while let Some(a) = args.next() {
    match a.as_str() {
      "--server-port" => {
        server_port = args
          .next()
          .ok_or("--server-port needs value")?
          .parse()
          .map_err(|e| format!("server-port: {e}"))?;
      }
      "--jar" => {
        jar_path = Some(PathBuf::from(args.next().ok_or("--jar needs value")?));
      }
      "--start-app" => {
        start_app = args.next().ok_or("--start-app needs package name")?;
      }
      flag if flag.starts_with('-') => return Err(format!("unknown flag: {flag}")),
      other => positionals.push(other.to_string()),
    }
  }
  if let Some(h) = positionals.get(0) {
    host = h.clone();
  }
  if let Some(p) = positionals.get(1) {
    adb_port = p.parse().map_err(|e| format!("adb port: {e}"))?;
  }
  Ok(Cli {
    host,
    adb_port,
    server_port,
    jar_path,
    start_app,
  })
}

fn run() -> Result<(), String> {
  let cli = parse_cli()?;
  let host = cli.host;
  let adb_port = cli.adb_port;

  let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
  let harmony_root = manifest_dir.join("../..");
  let default_jar = harmony_root.join("entry/src/main/resources/rawfile/easycontrolnext_server.jar");
  let jar_path = cli.jar_path.unwrap_or(default_jar);
  if !jar_path.is_file() {
    return Err(format!(
      "server jar missing: {}\nRun: ./scripts/copy_server_jar.sh",
      jar_path.display()
    ));
  }
  let jar_bytes = std::fs::read(&jar_path).map_err(|e| e.to_string())?;
  let jar_sha = sha256_hex(&jar_bytes);

  let mut opts = ServerLaunchOptions::default();
  opts.server_port = cli.server_port;
  opts.start_app = cli.start_app.trim().to_string();
  let version_sidecar = jar_path
    .parent()
    .unwrap_or(Path::new("."))
    .join("easycontrolnext_server.version");
  if version_sidecar.is_file() {
    let meta = load_server_jar_meta(&version_sidecar).map_err(|e| e.to_string())?;
    opts.app_version_code = meta.app_version_code;
    if let Some(expected) = meta.sha256 {
      if expected != jar_sha {
        eprintln!("warn: jar sha256 mismatch vs version sidecar (jar={jar_sha} meta={expected})");
      }
    }
  } else {
    opts.app_version_code = DEFAULT_APP_VERSION_CODE;
  }

  let key_path = manifest_dir
    .join("..")
    .join(".adb-keys")
    .join("easycontrol_gate_c");
  let (signer, created) = RsaAdbSigner::load_or_generate(&key_path, "easycontrol@harmonyos")
    .map_err(|e| e.to_string())?;
  if created {
    println!("generated new ADB RSA-2048 key: {}", key_path.display());
  } else {
    println!("loaded ADB key: {}", key_path.display());
  }

  println!();
  println!(">>> Gate D target {host}:{adb_port}");
  println!(
    ">>> jar {} ({} bytes sha256={})",
    jar_path.display(),
    jar_bytes.len(),
    jar_sha
  );
  println!(
    ">>> remote {} serverPort={}",
    opts.remote_jar_path(),
    opts.server_port
  );
  println!();

  let stream = connect_tcp(&host, adb_port, Duration::from_secs(10)).map_err(|e| e.to_string())?;
  let mut session =
    AdbSession::connect(stream, &signer, Duration::from_secs(120)).map_err(|e| {
      format!(
        "handshake/auth failed: {e}\n\
         Tip: authorize RSA key on the phone if prompted."
      )
    })?;
  if session.state() != SessionState::Connected {
    return Err("session not connected".into());
  }
  println!("[1/6] AUTH+CNXN OK");

  session
    .set_io_timeout(Duration::from_secs(10))
    .map_err(|e| e.to_string())?;

  let stop_out = stop_existing_server(&mut session).map_err(|e| e.to_string())?;
  println!("[2/6] stop prior server: {stop_out}");

  let ensured = ensure_server_jar(&mut session, &opts, &jar_bytes).map_err(|e| e.to_string())?;
  if ensured.sha256_hex != jar_sha {
    return Err(format!(
      "jar sha mismatch local={jar_sha} remote={}",
      ensured.sha256_hex
    ));
  }
  let ls = session
    .shell(&format!("ls -l {}", opts.remote_jar_path()))
    .map_err(|e| e.to_string())?;
  let ls_text = String::from_utf8_lossy(&ls);
  if !ls_text.contains(&opts.remote_jar_name()) {
    return Err(format!("remote jar missing: {ls_text:?}"));
  }
  println!(
    "[3/6] jar {} (sha={}) {}",
    if ensured.pushed { "pushed" } else { "skipped (sha match)" },
    &ensured.sha256_hex[..12.min(ensured.sha256_hex.len())],
    ls_text.trim()
  );

  let shell_id = start_server_shell(&mut session, &opts).map_err(|e| e.to_string())?;
  println!("[4/6] app_process launched on shell local_id={shell_id}");
  thread::sleep(Duration::from_millis(50));

  session
    .set_io_timeout(Duration::from_millis(500))
    .map_err(|e| e.to_string())?;

  let early = session.read_stream_buf(shell_id).unwrap_or_default();
  if !early.is_empty() {
    eprintln!("server shell early: {}", String::from_utf8_lossy(&early));
  }

  let timeout = Duration::from_secs(15);
  let dual = connect_dual(&mut session, &host, opts.server_port, timeout, shell_id)
    .map_err(|e| e.to_string())?;
  let mode = dual.mode.as_str();
  println!("[5/6] dual sockets OK (main={mode}, video={mode})");

  let _ = session.read_stream_buf(shell_id);

  let header_timeout = Duration::from_secs(20);
  let mut main_tcp = dual.main_tcp;
  let mut video_tcp = dual.video_tcp;
  let main_adb = dual.main_adb;
  let video_adb = dual.video_adb;

  let video_hdr = if let Some(ref mut sock) = video_tcp {
    read_video_header_tcp(sock, header_timeout)?
  } else {
    let id = video_adb.ok_or("missing video adb stream")?;
    read_video_header_adb(&mut session, id, header_timeout)?.0
  };

  let main_audio_flag = if let Some(ref mut sock) = main_tcp {
    read_exact_timeout(sock, 1, header_timeout)?[0]
  } else {
    let id = main_adb.ok_or("missing main adb stream")?;
    let buf = read_adb_at_least(&mut session, id, 1, header_timeout)?;
    buf[0]
  };

  let ka = control::create_keep_alive();
  if let Some(ref mut sock) = main_tcp {
    sock.write_all(&ka).map_err(|e| e.to_string())?;
  } else if let Some(id) = main_adb {
    session.write_stream(id, &ka).map_err(|e| e.to_string())?;
  }

  println!(
    "[6/6] video header OK: h265={} {}x{} csd0={} csd1={} mainAudioFlag={}",
    video_hdr.use_h265,
    video_hdr.width,
    video_hdr.height,
    video_hdr.csd0.len(),
    video_hdr.csd1.as_ref().map(|v| v.len()).unwrap_or(0),
    main_audio_flag
  );

  if let Some(sock) = main_tcp.take() {
    let _ = sock.shutdown(std::net::Shutdown::Both);
  }
  if let Some(sock) = video_tcp.take() {
    let _ = sock.shutdown(std::net::Shutdown::Both);
  }
  if let Some(id) = main_adb {
    let _ = session.close_stream(id);
  }
  if let Some(id) = video_adb {
    let _ = session.close_stream(id);
  }
  let _ = session.close_stream(shell_id);
  let _ = stop_existing_server(&mut session);
  let _ = session.close();

  println!();
  println!(
    "Gate D PASS against {host}:{adb_port} (serverPort={})",
    opts.server_port
  );
  Ok(())
}
