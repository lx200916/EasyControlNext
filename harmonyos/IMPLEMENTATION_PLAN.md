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
│   ADB framing · transport/session FSM · crypto/pairing · control encode · sync push     │
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
- [ ] On-device/emulator ArkTS call of binary-safe export (gate B) — `.so` built; ArkTS example under `native/arkts/`; wire into entry only after staging libs

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
- [x] `AdbSigner` trait + `DeterministicTestSigner` (host) + `PendingProductionSigner` (**production RSA/HUKS pending — not faked as success**)
- [x] Host fake daemon + integration tests (handshake, shell echo, sync hash, tcp echo, flow control, malformed, timeout, close, bad auth)
- [ ] Gate C on real pre-authorized Android device (same scenarios as fake daemon)
- [ ] Production RSA 2048 ADB key encode/sign + HUKS/Asset Store wrapping

### Phase 3 — TLS connect and wireless pairing

- [ ] A_STLS + TLS 1.3 (`rustls` first; OpenSSL trait fallback if needed)
- [ ] Client RSA key + X.509 for wireless debugging
- [ ] Pairing framing, exporter `adb-label\0` (64 B), HKDF-SHA256, AES-128-GCM, peer-info
- [ ] **CRITICAL:** AOSP/BoringSSL-compatible SPAKE2-25519 (do not assume RustCrypto `spake2` wire compat)
- [ ] Negative tests: wrong code, expired port, bad cert, altered transcript, truncated, reconnect
- [ ] mDNS via ArkTS `@ohos.net.mdns`: `_adb-tls-pairing._tcp.` / `_adb-tls-connect._tcp.`

### Phase 4 — Existing server artifact and session transport

- [ ] Reproduce `ClientStream.startServer()` path/versioning/rm/push/`app_process` options
- [ ] `scripts/copy_server_jar.sh` from Android Gradle output → `rawfile/`
- [ ] Dual TCP main+video, 15s timeout/retry; ADB `tcp:<serverPort>` fallback
- [ ] Main/video framing parsers
- [ ] Fake-server integration test (no phone)

### Phase 5 — Media and control UI

- [ ] AVCodec Kit + XComponent H.264 low-latency decode (not AVPlayer)
- [ ] Full-screen UIAbility MVP; metrics: first frame, e2e latency, drops, orientation, 30 min
- [ ] Touch/keys/keepalive/resolution/rotation/backlight/power/clipboard via control contract
- [ ] H.265 Main/Main10 negotiation only after H.264 stable
- [ ] Opus/AAC later; AVSession only if background audio is actually supported

### Phase 6 — ArkUI product parity

- [ ] Device list, editor, presets, settings, diagnostics, app picker, fullscreen controller
- [ ] Navigation/NavPathStack, typed state, relationalStore, preferences, permissions
- [ ] Responsive phone/tablet/2in1; no floatView/USB blockers for MVP

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
| **A** | `cargo test` in `native/` (host) passes | **PASS** (protocol 22 + adb_client 13 = 35, 2026-08-12) |
| **B** | Rust OHOS arm64 `.so` builds; ArkTS calls binary-safe export on device/emulator | **.so rebuildable**; ArkTS not wired into Index (API 24 device/SDK run still pending) |
| **C** | ADB interop: shell, push/hash, tcp service vs Android | **Host fake daemon PASS**; real Android device pending |
| **D** | Existing Android server launches from HarmonyOS; accepts main+video sockets | Phase 4 |
| **E** | H.264 first frame + touch control | Phase 5 |
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

# Copy Android server artifact into rawfile (after Gradle server build)
./scripts/copy_server_jar.sh
```

---

## 12. Current run log

| Date | Milestone |
|---|---|
| 2026-08-12 | Plan created; Phase 0–1 protocol + NAPI PoC; arm64 `.so` via NDK cargo fallback |
| 2026-08-12 | API 24 `build-profile` reconciled as already `6.1.1(24)` — not overwritten |
| 2026-08-12 | Phase 2 host session core: `adb_client` + fake daemon; 35 host tests PASS; arm64 `.so` rebuilt |
| 2026-08-12 | Production RSA signer explicitly `PendingProductionSigner` (not faked as success) |

**Next milestone:** Gate B on device/emulator (optional ArkTS probe from `native/arkts` after staging `.so`); Gate C on a real pre-authorized Android device; implement production RSA/ADB public-key encoding + HUKS wrapping behind `AdbSigner`.
