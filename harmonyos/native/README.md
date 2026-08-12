# Native Rust core (`adb_core` + `protocol`)

HarmonyOS controller native stack:

| Crate | Role |
|---|---|
| `protocol` (`easycontrol-protocol`) | Pure Rust ADB / sync / EasyControl framing; host unit tests |
| `adb_client` (`easycontrol-adb-client`) | TCP session FSM, stream mux, shell/sync/tcp helpers, fake daemon tests |
| `adb_core` | ohos-rs Node-API cdylib exporting coarse binary-safe APIs |

**Signer policy:** `DeterministicTestSigner` is for host tests only. `PendingProductionSigner` returns an explicit error until HUKS-backed RSA ADB keys land — do not treat test signatures as production auth.

**No handwritten C++ NAPI.** Optional C ABI only appears inside third-party Rust crates (document if introduced).

## Prerequisites

```bash
rustc --version   # expect 1.88+
rustup target list --installed | grep ohos
# aarch64-unknown-linux-ohos should be present

# NDK (DevEco 5.0+ / 6.x layout)
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
```

Install OHOS target if missing (do not assume global tools exist in CI):

```bash
rustup target add aarch64-unknown-linux-ohos
```

Install `ohrs` (writes to `~/.cargo`):

```bash
cargo install ohrs --locked
```

## Host tests (gate A)

From repo `harmonyos/`:

```bash
./scripts/run_host_tests.sh
# runs: easycontrol-protocol + easycontrol-adb-client (incl. FakeDaemon integration tests)
```

## OHOS arm64 build (gate B)

```bash
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
./scripts/build_native_ohos.sh
```

Artifacts land under `native/adb_core/dist/` (ohrs) or `native/target/aarch64-unknown-linux-ohos/release/` (cargo fallback).

Copy the produced `libadb_core.so` into the entry module libs path used by your DevEco SDK version (commonly `entry/libs/arm64-v8a/`), then from ArkTS:

```ts
import adbCore from 'libadb_core.so';

const echoed = adbCore.roundTripBytes(new Uint8Array([1, 2, 3]).buffer);
const ver = adbCore.nativeVersion();
```

Exact import/package wiring can follow the `ohrs` dist layout for the installed CLI version.

## Exported NAPI surface (PoC / Phase 1)

- `nativeVersion(): string`
- `roundTripBytes(input: Buffer): Buffer`
- `encodeAdbConnect(): Buffer`
- `encodeAdbOkay(localId, remoteId): Buffer`
- `encodeAdbOpen(localId, dest): Buffer`
- `decodeAdbMessage(input, verifyChecksum): AdbMessageJs`
- `encodeControlKeepAlive(): Buffer`
- `encodeControlTouch(...): Buffer`
- `encodeControlClipboard(text): Buffer`

High-frequency session I/O stays inside Rust in later phases.

## Server jar + Gate D (Phase 4)

Android `ClientStream.startServer()` semantics live in `adb_client::server_launch`:

- Remote path: `/data/local/tmp/easycontrolnext_server_<app_version_code>.jar` (app module `versionCode`, currently `10014`)
- Launch: ADB `shell:app_process -Djava.class.path=… / com.shiyunjin.easycontrolnext.server.Server …`
- Dual sockets: **main** then **video** on `serverPort` (default `25166`); direct TCP preferred, ADB `tcp:<port>` fallback
- Video preamble (BE): `useH265:u8` + `width:u32` + `height:u32` + length-prefixed CSD0 (+ CSD1 if AVC)

```bash
# From harmonyos/
./scripts/copy_server_jar.sh   # → entry/.../rawfile/easycontrolnext_server.jar (+ .version sidecar)

cd native
export CARGO_HOME="$PWD/.cargo-home"
# Reuses native/.adb-keys/easycontrol_gate_c from Gate C
cargo run -p easycontrol-adb-client --bin gate_d -- 192.168.31.60 5555
```

Gate D **PASS** criteria: AUTH+CNXN, jar push, app_process up, main+video accept, parse video header (+ optional keepalive on main).

## Video framing + decode (Phase 5 / Gate E first-frame)

Pure Rust in `protocol::video` (re-exported via `adb_client` / NAPI):

- Header + length-prefixed CSD frames (each body = `pts:i64 BE` + NAL)
- Access units: same length-prefix + PTS + Annex-B payload
- NAPI: `parseVideoStreamHeader`, `parseVideoAccessUnit`, existing `encodeControlTouch`

Host: `cargo test -p easycontrol-protocol --lib video`

**OH_VideoDecoder path** (`adb_core/src/ohos_vdec.rs`, OHOS target only):

- `OH_NativeWindow_CreateNativeWindowFromSurfaceId` + `OH_VideoDecoder_*` (links `libnative_media_vdec` / `core` / `native_window`)
- NAPI: `videoDecoderPlayBitstream(surfaceId, easycontrolBytes)`, `videoDecoderWaitFirstFrame`, `videoDecoderStatus`, `videoDecoderRelease`
- Session loads `rawfile/fixture_avc_easycontrol.bin` (real baseline AVC) on XComponent `onLoad`

Verify on foldable emu: Home → Connect → Session status `首帧已渲染`; HiLog `SessionDecode FIRST_FRAME_OK`.

## Live Gate D session (on-device)

NAPI (background thread; ArkTS polls):

- `liveSessionStart({ host, adbPort, serverPort, surfaceId, jarBytes, privateKeyPem, … })`
- `liveSessionStatus()` → `{ phase, detail, mode, width, height, ausFed, firstFrame, live }`
- `liveSessionWriteControl(packet)` — touch/keepalive on **direct** main TCP
- `liveSessionStop()`

Session UX: Connect → try live (rawfile jar + Gate C RSA) → OH_VideoDecoder stream; on error/timeout → fixture toast fallback.

```bash
./scripts/build_native_ohos.sh
# DevEco / hvigorw assembleHap, then:
hdc -t 127.0.0.1:5559 file send entry/build/default/outputs/default/entry-default-signed.hap /data/local/tmp/entry.hap
hdc -t 127.0.0.1:5559 shell bm install -p /data/local/tmp/entry.hap
hdc -t 127.0.0.1:5559 shell aa start -a EntryAbility -b com.shiyunjin.easycontrolnext -m entry
```

**Network note:** Foldable emu may reach host gateway (`10.0.2.2`) and sometimes LAN Android with high RTT; if live stalls, run HAP on a HarmonyOS device on the same LAN as the Android target, or relay ADB/server ports via the host.
