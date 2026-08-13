# EasyControlNext · HarmonyOS Controller Implementation Plan

**Status:** Active  
**Owner:** HarmonyOS implementation track  
**Production baseline:** HarmonyOS 6.1.1 / API 24 Release  
**Scope:** HarmonyOS is **controller-only**. Controlled devices remain Android.  
**Native policy:** Rust + ohos-rs (`napi-ohos` / `napi-derive-ohos` / `ohrs`). No handwritten C++ NAPI.

This document is the living plan. Checkboxes are updated as work lands. Do **not** treat unchecked items as implemented.

---

## 0. Concurrent-work constraints

Another worker may be upgrading the HarmonyOS scaffold to API 24 Release.

| Do touch | Do not overwrite without coordination |
|---|---|
| `IMPLEMENTATION_PLAN.md` | Root / entry `build-profile.json5` |
| `native/**` Rust workspace | `hvigor/hvigor-config.json5` |
| `scripts/**` | `oh-package.json5` / lock unless needed for native packaging |
| ArkTS app/protocol/data layers under `entry/src/main/ets/**` (non-scaffold) | `local.properties` |
| `entry/src/main/resources/rawfile/**` (server jar copy target) | Unrelated Android tree changes |
| Docs under `native/README.md`, notices | User/uncommitted Android Compose work |

Inspect `git status` / `git diff` before editing shared scaffold files.

---

## 1. Product / architecture summary

```
┌──────────────────────────────── HarmonyOS (controller) ────────────────────────────────┐
│  entry (ArkUI)                                                                          │
│   Navigation / device list / editor / presets / settings / fullscreen session           │
│   XComponent surface · AVCodec H.264 decode · mDNS (_adb-tls-*) · permissions           │
│                                        │                                                │
│   ArkTS data/session layer                                                              │
│   typed Device/Preset · relationalStore · preferences · DTOs · diagnostics              │
│                                        │ Node-API (coarse, binary-safe)                 │
│   native/adb_core (Rust cdylib via ohos-rs)                                             │
│   ADB framing · transport/session FSM · crypto/pairing · control encode · sync push/pull │
└────────────────────────────────────────┼────────────────────────────────────────────────┘
                                         │ ADB / TLS / TCP
                                         ▼
                              Android device + existing server.jar
                              (easycontrolnext_server_<version>.jar via app_process)
```

**Non-goals for MVP**

- Porting or rewriting the Android `server` module
- Floating window / mini view (API 26 `floatView` optional later)
- USB ADB via DriverExtensionAbility / USB DDK
- Audio / H.265 until H.264 + touch are stable
- Reproducing Android’s dual-stack `ManagerChannel` / `Ctop` bridge

---

## 2. Module / file layout (target)

```
harmonyos/
├── IMPLEMENTATION_PLAN.md          ← this file
├── README.md
├── NOTICE.THIRD_PARTY.md           ← server + Rust crate notices (Phase 4/7)
├── AppScope/                       ← scaffold (coordinate API 24 bump)
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/
│   │   │   ├── pages/              ← Index shell + Navigation destinations
│   │   │   ├── model/              ← Device, Preset, SessionState (typed)
│   │   │   ├── data/               ← relationalStore / preferences repos
│   │   │   ├── session/            ← session orchestration (ArkTS side)
│   │   │   ├── media/              ← AVCodec + XComponent glue
│   │   │   ├── net/                ← mDNS discovery (@ohos.net.mdns)
│   │   │   └── native/             ← thin ArkTS wrappers over libadb_core.so
│   │   ├── module.json5
│   │   └── resources/
│   │       ├── base/
│   │       └── rawfile/
│   │           └── easycontrolnext_server.jar   ← copied, not hand-edited
│   └── libs/                       ← optional staged .so from ohrs dist
├── native/
│   ├── Cargo.toml                  ← workspace
│   ├── README.md                   ← host test + OHOS arm64 build
│   ├── protocol/                   ← pure Rust framing, host-testable
│   ├── adb_client/                 ← TCP session / multiplexer + fake daemon tests
│   └── adb_core/                   ← napi-ohos cdylib (coarse exports)
└── scripts/
    ├── build_native_ohos.sh        ← reproducible ohrs/cargo OHOS build
    ├── copy_server_jar.sh          ← Gradle server → rawfile
    └── run_host_tests.sh
```

---

## 3. Phase sequence and progress

### Phase 0 — Repository and toolchain foundation

- [x] Inspect HarmonyOS scaffold, git status/diff, Rust 1.88, OHOS NDK paths
- [x] Add this plan; avoid conflicting with concurrent API 24 scaffold edits
- [x] Add Rust workspace layout (`native/protocol`, `native/adb_core`)
- [x] ohos-rs Node-API hello / binary-safe Buffer round-trip exports in source
- [x] Host Rust unit-test entry points + reproducible build scripts/docs
- [x] Produce `aarch64-unknown-linux-ohos` `libadb_core.so` via cargo + OHOS NDK fallback (`ohrs` global install blocked in this environment)
- [x] On-device/emulator ArkTS call of binary-safe export (Gate B) — foldable emu `127.0.0.1:5559` (API 24, arm64, EXPAND): `nativeVersion=0.1.0`, `nativeCapabilities`, `roundTripBytes` PASS; auto-signing via product `signingConfig: "default"`; probe in `entry/src/main/ets/native/AdbCore.ets`

**Toolchain notes (observed 2026-08-12)**

| Item | Value |
|---|---|
| `rustc` | 1.88.0 |
| Installed Rust OHOS targets | `aarch64-unknown-linux-ohos` (+ armv7/x86_64/loongarch64) |
| DevEco SDK path | `/Applications/DevEco-Studio.app/Contents/sdk` |
| `OHOS_NDK_HOME` (5.0+) | `.../sdk/default/openharmony` |
| Project `build-profile.json5` | **reconciled:** `compileSdkVersion` / `targetSdkVersion` = `6.1.1(24)` (left untouched this run) |
| `ohrs` | not installed globally at start of this run |
| Crates | `napi-ohos` / `napi-derive-ohos` / `ohrs` 1.x on crates.io |

### Phase 1 — Protocol-first Rust core

- [x] Port golden-byte-safe helpers for ADB 24-byte headers + EasyControl control events 1–9
- [x] Endianness: ADB LE; EasyControl control BE; document pairing BE for Phase 3
- [x] Sync SEND/DATA/DONE/QUIT 8-byte framing helpers
- [x] A_STLS constant + encoder stub (TLS handshake body is Phase 3)
- [x] Exhaustive host unit tests (golden vectors, checksum, clipboard limit, malformed lengths)
- [ ] Keep high-frequency parse/state native; only coarse NAPI surface to ArkTS (ongoing)

### Phase 2 — ADB connection MVP (pre-authorized device)

- [x] TCP ADB transport trait + `TcpStream` impl; unified stream multiplexer (`AdbSession`)
- [x] CNXN / AUTH handshake + OPEN / OKAY / WRTE / CLSE + write-credit flow control
- [x] shell, sync push framing/service, `tcp:<port>` abstractions
- [x] sync pull (RECV/DATA/DONE/FAIL) + FakeDaemon + host integration tests; NAPI `adbSyncPull` + Session UI (≤32 MiB, separate TCP from Gate D)
- [x] `AdbSigner` trait + `DeterministicTestSigner` (host) + `RsaAdbSigner` (RSA-2048 ADB wire format)
- [x] Host fake daemon + integration tests (handshake, shell echo, sync push/pull, tcp echo, flow control, malformed, timeout, close, bad auth)
- [x] Gate C on real Android device (`gate_c` bin vs `192.168.31.60:5555`: AUTH+CNXN, shell, sync push+sha256, tcp echo)
- [x] HUKS AES-256-GCM wrapping for on-device ADB RSA (`AdbHuksWrap` + `AdbKeyAssets`; AUTH sign remains Rust SHA-1). Host PEM path kept for Gate C/D.

### Phase 3 — TLS connect and wireless pairing

- [x] A_STLS + TLS 1.3 for **ADB session** connect after pairing (`AdbSession::connect_with_key` + `tls_client::upgrade_tcp_to_tls`; requires rebuilt `libadb_core.so`)
- [x] Pairing TLS 1.3 (`rustls` + accept-any server cert) + client RSA/X.509 from PEM (`rcgen`) for wireless pairing handshake
- [x] Pairing framing, exporter `adb-label\0` (64 B), HKDF-SHA256, AES-128-GCM, peer-info (`native/adb_client/src/pairing/`)
- [x] **CRITICAL:** AOSP/BoringSSL-compatible SPAKE2-25519 via `curve25519-dalek` + custom scalar multiply (preserves AOSP bit-255 / `left_shift3`); host tests vs BoringSSL oracle + Alice/Bob roundtrip — **not** RustCrypto `spake2`. Live Android 11+ wireless pair **not yet verified** on-device
- [ ] Negative tests: wrong code, expired port, bad cert, altered transcript, truncated, reconnect (partial host coverage only)
- [x] mDNS via ArkTS `@ohos.net.mdns`: `_adb-tls-pairing._tcp` / `_adb-tls-connect._tcp` (no trailing `.` — OHOS quirk) + DeviceEditor manual/QR UI (`仅配对` / `配对并填充 ADB 端口`); live LAN discovery unverified on emu

### Phase 4 — Existing server artifact and session transport

- [x] Reproduce `ClientStream.startServer()` path/versioning/rm/push/`app_process` options (`adb_client::server_launch`)
- [x] `scripts/copy_server_jar.sh` from Android Gradle/`res/raw` → `rawfile/` + `easycontrolnext_server.version` (app `versionCode`)
- [x] Dual TCP main+video, 15s timeout/retry; ADB `tcp:<serverPort>` fallback (`gate_d` host binary)
- [x] Main/video framing parsers (video header + length-prefixed CSD; control keepalive write)
- [ ] Fake-server integration test (no phone)
- [x] ArkTS session orchestration wiring (`LiveMirror.ets` + Session live-or-fixture; Gate B strip unchanged)

### Phase 5 — Media and control UI

- [x] Video stream framing (Rust `protocol::video` + NAPI): header + length-prefixed CSD + PTS-prefixed AUs; host tests + synthetic fixture inject
- [x] **U5** Session fullscreen shell: black + XComponent; folded bottom bar / expanded side rail; Home Connect → Session
- [x] Touch → `encode_control_touch` + live main-socket write when streaming (`liveSessionWriteControl`)
- [x] AVCodec Kit + XComponent H.264 low-latency **decode to pixels** — Rust `ohos_vdec` FFI (`OH_VideoDecoder` + `OH_NativeWindow_CreateNativeWindowFromSurfaceId`); Session injects `rawfile/fixture_avc_easycontrol.bin`; first frame PASS on foldable emu (HiLog `FIRST_FRAME_OK`, UI `首帧已渲染 · 320x180`)
- [ ] Full-screen session metrics: first frame, e2e latency, drops, orientation, 30 min
- [x] Live main/video sockets from HarmonyOS (Gate D on-device) feeding the decoder — NAPI `liveSessionStart/Status/WriteControl/Stop`; streaming `ohos_vdec::start_live_stream` + `push_access_unit`; **emu cannot reach LAN Android** (see Gate E / run log)
- [x] Session extras polish: screenshot (`adbScreencapPng`), app picker (`adbShellExec` + monkey), ADB sync file pull (`adbSyncPull` → app `filesDir`)
- [ ] Keys/keepalive/resolution/rotation/backlight/power/clipboard via control contract (keepalive+touch+power/rotate/light/clipboard wired; full metrics still open)
- [ ] H.265 Main/Main10 negotiation only after H.264 stable
- [ ] Opus/AAC later; AVSession only if background audio is actually supported

### Phase 6 — ArkUI product parity

- [x] **U0** Design tokens (`color.json` / `float.json` + `resources/dark`): accent `#3A70FC`, bg `#F2F3F5`, surfaces, radii 20/24vp
- [x] **U1** AppShell (`ets/shell/AppShell.ets`): Navigation + NavPathStack, no bottom Tabs; Index is thin entry
- [x] **U2** Home (`ets/pages/Home.ets`): sm list+FAB · preferSplit list|detail; mock devices; settings/add/edit → real destinations
- [x] Gate B probe migrated to `components/GateBDebugStrip.ets` (not whole Index page)
- [x] **U3** Device Editor (`ets/pages/DeviceEditor.ets`): name/host/ADB+server ports + pairing + video (maxSize/fps/H.265/fullscreen) + connect-on-start; Save → RDB `DeviceStore`; Save&Connect; sm section chips · preferSplit section nav|form
- [x] **U4** Settings lite (`ets/pages/Settings.ets`): about/version, language stub, presets → `Presets` page, logs placeholder; sm stacked · preferSplit category|content
- [x] **U5** Session fullscreen shell (XComponent + fold controls; fixture → OH_VideoDecoder first frame)
- [x] Device list persistence via `relationalStore` (`data/DeviceDb.ets` + `DeviceStore`); presets lite + session app picker wired; diagnostics still open
- [x] Home manage sheet (Android parity): Connect / Apply preset (session-only) / Temp start app → virtual display `startApp` / Use camera → `videoSource=camera` / Edit / Delete
- [x] Presets lite (`ets/pages/Presets.ets` + `ConnectionPreset`/`PresetStore`): 3 built-ins; apply links `presetId` + stream fields to device
- [x] Navigation/NavPathStack shell + typed Device model + shared `DeviceStore`
- [x] relationalStore device wiring (`DevicesDb` + `presetId`/`connectOnStart`/`changeToFullOnConnect`, `deviceStoreRevision`); preferences still open
- [ ] Responsive phone/tablet/2in1 polish beyond foldable Home; no floatView/USB blockers for MVP
- [x] Foldable-first layout helper (`entry/.../common/Breakpoint.ets`: sm/md/lg + fold posture + preferSplit)
- [x] Home reacts to fold/unfold via `startLayoutWatch` / `preferSplit` if/else (verify on foldable emulator `127.0.0.1:5559`)
- [x] Desktop service card (`EntryFormAbility` + `deviceList` 2*2/2*4): device names, tap → Session/Home

**Android UI reference (for ArkUI parity)**

- Product: 易控•远程控制Next — **no bottom tabs**; Compose `NavHost` stack + out-of-stack session.
- Screens: Home (list/detail) · Device editor · Settings · Presets · Error logs · Full session · Small/Mini float (defer on Harmony).
- Theme: M3, accent `#3A70FC`, soft gray bg `#F2F3F5`, cards 20–24dp radius; session chrome near-black.
- Adaptive already on Android: Compact single-column ↔ Medium+ panes — map to foldable folded/expanded.
- Living inventory: Cursor canvas tab **Android UI** (`harmony-controller-port-analysis.canvas.tsx`). Device-mgmt: manage sheet, editor video/startup, presets lite, camera + VD temp-app wired; still open: custom preset CRUD, full stream/options parity, error logs, float views.

**Foldable UI rules (binding constraint — primary test device is a foldable emulator)**

| Rule | Detail |
|---|---|
| Primary device | Foldable emulator (`hdc` `127.0.0.1:5559`, API 24); current posture often `EXPAND` |
| Layout switch | `if/else` on breakpoint / fold posture — **not** `.visibility(None)` |
| Folded (`sm` / FOLDED) | Single column: device list → push detail/session |
| Expanded / half | Prefer split or master–detail when `preferSplit`; session can share width with device list |
| Listeners | `display.on('change')` + `foldStatusChange`; unregister in `aboutToDisappear` |
| Session page | Video surface + controls must reflow on fold without tearing down ADB session |
| Navigation | Prefer `Navigation` Auto/Split over fixed phone-only stacks |

### Phase 7 — Hardening and parity

- [ ] Reconnect/backoff, capability downgrade, cancellation, cleanup, HiLog, lifecycle, codec reset
- [ ] Security length caps, zero secrets, no key/code/clipboard logs, target restrictions
- [ ] License inventory (GPLv3 root + embedded server + Rust crates); `NOTICE.THIRD_PARTY.md`

---

## 4. Dependencies

### HarmonyOS / DevEco

- DevEco Studio 6.1.1 Release (API 24 production)
- HarmonyOS SDK 6.1.1 Release
- Hvigor / ohpm versions matching DevEco-generated scaffold after API 24 bump
- Node.js matching Command Line Tools for the chosen SDK

### Rust / native

| Dep | Role |
|---|---|
| Rust 1.88+ (MSRV aligned with ohos-rs) | toolchain |
| `aarch64-unknown-linux-ohos` | OHOS arm64 target |
| `napi-ohos` / `napi-derive-ohos` / `napi-build-ohos` | Node-API bindings |
| `ohrs` | build/dist helper |
| OHOS NDK (`OHOS_NDK_HOME`) | link/sysroot |
| Phase 2+: `rsa`, `sha1`, `sha2`, `rand`, tokio or ohos sockets | ADB auth/transport |
| Phase 3+: `rustls` (preferred), HKDF, AES-GCM, curve25519-dalek / audited SPAKE2 | TLS + pairing |

### Android artifact

- Existing `easycontrolnext` Gradle `server` module output JAR
- Copied byte-for-byte into HarmonyOS `rawfile`
- Do not modify server internals unless a proven protocol defect

### ArkTS / Kits (production path, API 24)

- Ability Kit, ArkUI (Navigation), ArkData (relationalStore/preferences)
- Network Kit / `@ohos.net.mdns`
- AVCodec Kit, Audio Kit (later), XComponent
- Asset Store Kit / HUKS for key wrapping
- Performance Analysis Kit (hilog)

---

## 5. Test gates

| Gate | Criteria | Status |
|---|---|---|
| **A** | `cargo test` in `native/` (host) passes | **PASS** (protocol 22 + adb_client unit/integration incl. RSA) |
| **B** | Rust OHOS arm64 `.so` builds; ArkTS calls binary-safe export on device/emulator | **PASS** (foldable emu `127.0.0.1:5559`) |
| **C** | ADB interop: shell, push/hash, tcp service vs Android | **PASS** (2026-08-12, RSA new key + real marble device TCP 5555) |
| **D** | Existing Android server launches; accepts main+video sockets | **PASS** (host `gate_d` re-verified 2026-08-12 vs `192.168.31.60:5555`). On-device path wired via `liveSession*` NAPI + Session UX. |
| **E** | H.264 first frame + touch control | **PARTIAL** — fixture first-frame PASS. **Live path code complete** + on-emu bring-up reached `streaming 720x1600 via direct` (HiLog `LiveMirror` → status streaming) against LAN `192.168.31.60`, but **live first-frame pixels not confirmed** within poll window (emu↔LAN RTT can be multi-second; then Session fell back to fixture `FIRST_FRAME_OK`). Touch write wired for direct main TCP. Prefer same-LAN HarmonyOS device for Gate E full PASS; optional host relay if emu path stays lossy. |
| **F** | Pairing code flow Android 11+; survives reconnect | Phase 3 |
| **G** | 30-minute stability; no leaked sockets/decoder/session | Phase 5/7 |

---

## 6. Security constraints

1. Validate all framed lengths; reject oversized ADB payloads and control clipboard (>5000 UTF-8 bytes).
2. Cap video frame / CSD sizes before decoder handoff.
3. Zeroize pairing secrets and sensitive buffers after use.
4. Never log private keys, pairing codes, or clipboard contents.
5. Restrict network targets to user-configured hosts/ports; fail closed on malformed addresses.
6. Document that **post-server-launch media/control streams follow the existing plaintext EasyControl protocol**.
7. Private keys: prefer HUKS / Asset Store wrapping; any file-based dev store must be compile-time gated and warned.
8. Pairing SPAKE2 must match AOSP/BoringSSL transcripts — compatibility before convenience crates.

---

## 7. Licensing

- Root project: **GPLv3** (`../LICENSE`).
- HarmonyOS `oh-package.json5` currently says Apache-2.0 — align packaging metadata with GPLv3 before distribution (tracked).
- Embedded Android server JAR and its third-party deps require source availability / notices.
- Inventory all Rust crate licenses before AppGallery / binary distribution (`NOTICE.THIRD_PARTY.md`).
- `io.github.muntashirakon.adb` is BSD-3-Clause AND (GPL-3.0-or-later OR Apache-2.0); preserve attribution when porting protocol logic.

---

## 8. Rollback / fallback behavior

| Failure | Fallback |
|---|---|
| OHOS Rust target / `ohrs` unavailable in CI/dev | Keep source complete; run host `cargo test`; document blocker; do not fake device success |
| `rustls` + RFC 5705 exporter fails on OHOS | Trait-swapped OpenSSL/`ohos-openssl` path; document native dep |
| SPAKE2 crate wire-incompatible | Custom AOSP transcript on audited primitives; block pairing ship until vectors pass |
| Direct TCP to server port fails | ADB `tcp:<serverPort>` fallback (Android `ClientStream` behavior) |
| H.265 unsupported | Negotiate H.264 only |
| Pairing port expired / wrong code | Clear error; do not retry with same secrets; require new code |
| API 26-only APIs | Not used on production path; floatView remains optional preview |

---

## 9. Explicit acceptance criteria (MVP ship)

1. Controller runs on HarmonyOS API 24 Release device/emulator.
2. Can pair or connect to an already-authorized Android device over network ADB.
3. Pushes and launches the **unmodified** versioned server JAR via `app_process` with existing option string semantics.
4. Establishes main + video sockets; decodes H.264 to fullscreen XComponent; sends touch/control packets.
5. Survives 30-minute soak without resource leaks (gate G).
6. Host protocol tests (gate A) remain green in CI.
7. Notices/licenses complete for embedded server + Rust deps.

---

## 10. Protocol endianness quick reference

| Channel | Endian | Source |
|---|---|---|
| ADB message header + sync header | Little-endian | `AdbProtocol.java` |
| EasyControl control events 1–9 | Big-endian (Java `ByteBuffer` default) | `ControlPacket.java` |
| Wireless pairing headers | Big-endian | muntashirakon / AOSP pairing |
| ADB payload checksum | Sum of unsigned bytes | AOSP / both Java copies |

Control event type bytes: `1` touch, `2` key, `3` clipboard, `4` keepalive, `5` resolution float, `6` rotate, `7` backlight, `8` power, `9` resolution WxH.

Server launch path pattern: `/data/local/tmp/easycontrolnext_server_<version>.jar`.

---

## 11. Commands (reproducible)

```bash
# Host protocol + napi crate compile checks (no device)
./scripts/run_host_tests.sh

# Optional: install CLI (network + cargo write to ~/.cargo)
cargo install ohrs --locked

# OHOS arm64 native module (requires OHOS_NDK_HOME)
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
./scripts/build_native_ohos.sh

# Copy Android server artifact into rawfile (after Gradle server build / copyRelease)
./scripts/copy_server_jar.sh

# Gate D — push/launch server + dual TCP against a real authorized Android device
cd native
export CARGO_HOME="$PWD/.cargo-home"
cargo run -p easycontrol-adb-client --bin gate_d -- 192.168.31.60 5555
# optional: --server-port 25166 --jar ../entry/src/main/resources/rawfile/easycontrolnext_server.jar
```

---

## 12. Current run log

| Date | Milestone |
|---|---|
| 2026-08-12 | Plan created; Phase 0–1 protocol + NAPI PoC; arm64 `.so` via NDK cargo fallback |
| 2026-08-12 | API 24 `build-profile` reconciled as already `6.1.1(24)` — not overwritten |
| 2026-08-12 | Phase 2 host session core: `adb_client` + fake daemon; 35 host tests PASS; arm64 `.so` rebuilt |
| 2026-08-12 | `RsaAdbSigner` + `gate_c` binary; Gate C PASS on real Android TCP (`192.168.31.60:5555`) |
| 2026-08-12 | Host PEM keys under `native/.adb-keys/` (gitignored); HUKS wrapping still open for HarmonyOS on-device |
| 2026-08-12 | **Gate B PASS** on foldable emulator `127.0.0.1:5559` (API 24 arm64 EXPAND): signed HAP install + launch; HiLog `GateB` `nativeVersion=0.1.0` + roundTrip OK; product `signingConfig: "default"` wired to auto-signing materials |
| 2026-08-12 | **Phase 6 U0–U2**: design tokens + AppShell Navigation + foldable Home; Gate B probe → `GateBDebugStrip`; placeholder routes for settings / device editor |
| 2026-08-12 | **Phase 6 U3–U4**: DeviceEditor form + Settings lite; `DeviceStore` in-memory upsert; Home refresh via `deviceStoreRevision`; signed HAP on foldable emu `127.0.0.1:5559` |
| 2026-08-12 | Phase 4 host path: `copy_server_jar.sh` → rawfile + version sidecar (`app_version_code=10014`); `adb_client::server_launch` + `gate_d` |
| 2026-08-12 | **Gate D PASS** (host) on marble `192.168.31.60:5555`: push `easycontrolnext_server_10014.jar` → `app_process` → direct main+video `:25166` → video header `720x1600` AVC + keepalive |
| 2026-08-12 | **Phase 5 partial / Gate E partial**: `protocol::video` AU framing + NAPI; U5 Session (XComponent, fold chrome); Home Connect → Session; synthetic fixture inject proves framing; touch→`encode_control_touch`; **no first-frame pixels** yet (OH_VideoDecoder C-only) |
| 2026-08-12 | **Gate E first-frame PASS** (fixture path): `native/adb_core/src/ohos_vdec.rs` → NAPI `videoDecoderPlayBitstream`; XComponent `surfaceId` → NativeWindow → `OH_VideoDecoder` AVC; rawfile `fixture_avc_easycontrol.bin` (libx264 320x180); HiLog `SessionDecode FIRST_FRAME_OK`; screenshot `gate_e_first_frame.jpeg` |
| 2026-08-12 | **On-device Gate D wiring**: `adb_client::dual_connect`, `adb_core::live_session` + NAPI `liveSession*`, streaming `ohos_vdec` start/push AU; rawfile jar + `adb_rsa_key.pem/.pub`; `INTERNET` permission; Session live-or-fixture + touch→main. Host `gate_d` re-PASS. Emu Connect → live `streaming 720x1600 via direct` then fixture fallback when first frame slow. |
| 2026-08-12 | **ADB sync pull**: `adb_client::sync_pull` (RECV/DATA/DONE/FAIL, 32 MiB cap) + FakeDaemon RECV + host tests; NAPI `adbSyncPull`; Session path sheet → save under `filesDir`; HAP rebuilt/installed on foldable emu `127.0.0.1:5559`. Device list still in-memory (`relationalStore` open). Phase 3 pairing untouched. |
| 2026-08-12 | **relationalStore devices**: `data/DeviceDb.ets` (`DevicesDb` CREATE IF NOT EXISTS + CRUD); `DeviceStore` cache+RDB; init in `EntryAbility`/`AppShell`; Home `deviceStoreRevision`; pairing stubs `pairPort`/`pairKey` preserved by DeviceEditor; seed mocks only when empty. Verified on foldable emu `127.0.0.1:5559`: cold restart `loaded 3 devices` (no re-seed) + Home shows `LabPersist` / `10.8.8.8:5555`. |
| 2026-08-12 | **Phase 3 pairing MVP**: BoringSSL-compatible SPAKE2 (host oracle PASS) + rustls pairing TLS/framing/HKDF/AES-GCM/peer-info; NAPI `adbPairWireless`; ArkTS mDNS + DeviceEditor「仅配对」/「配对并填充」/QR. A_STLS session TLS + live Android pair + negative tests still open. |

| 2026-08-12 | **Device-mgmt parity**: Home manage sheet (Connect/Edit/Delete/session preset/temp app/camera toast); DeviceEditor video+connectOnStart; Presets lite (3 built-ins, link `presetId`); DeviceDb columns `presetId`/`connectOnStart`/`changeToFullOnConnect`; SessionLaunch overrides. |
| 2026-08-12 | **Camera + virtual-display temp app**: Device → LiveMirror → `app_process` (`videoSource`/`cameraFacing`/`startApp`/VD size); SDK gates API 31+/30+. Fixes: NAPI passes source/`startApp` as discrete string args (object fields were dropped); `connect_dual` ignores MIUI non-fatal theme `FileNotFoundException`. Verified VD `startApp=com.kroegerama.appchecker` + `easycontrol` display on marble. |

| 2026-08-13 | **HUKS wrap + service card**: per-install RSA-2048 PKCS#8, AES-256-GCM wrap (`AdbHuksWrap`) → `filesDir/adb_rsa_huks.bin`; LiveMirror/pairing/probe stop using bundled rawfile PEM. Desktop `deviceList` Form Kit card 2*2/2*4, tap → Session/Home. |

**Next milestone:** live pair vs Android 11+ wireless debugging (e.g. `192.168.31.60`); live first-frame confirmation (Gate E); Gate G soak; license notices.
