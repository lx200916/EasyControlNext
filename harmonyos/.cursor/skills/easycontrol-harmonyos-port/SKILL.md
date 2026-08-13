---
name: easycontrol-harmonyos-port
description: >
  EasyControlNext HarmonyOS controller port notes: ADB wireless QR pairing (HO shows /
  Android scans), A_STLS TLS connect, live session first-frame PTS/OH_VideoDecoder,
  HdsTabs safe area, DeviceStore preferences, stale libadb_core.so packaging.
  Use when working on pairing, live mirror, Session decode, native Rust NAPI, or
  Android parity under harmonyos/.
---

# EasyControlNext HarmonyOS port

Project rules: `[../../AGENTS.md](../../AGENTS.md)`. HarmonyOS encyclopedia: `harmonyos-development` skill references. This skill is **parity / footgun notes only**.

Peer Android app: `../easycontrolnext/` (Compose). Controlled device stays Android (`server` JAR).

## QR pairing (HO shows / Android scans)

Direction is **opposite** a typical “scan to pair” app: the **HarmonyOS controller displays** `WIFI:T:ADB;S:<service>;P:<password>;;` (`AdbQrPairing` + Scan Kit `generateBarcode` / `QRCode`). The **Android phone scans** with wireless-debugging QR.

Flow (`AdbPairing.ets` / `DeviceEditor.ets`):

1. Generate credentials → show QR + status `等待被控机扫描…`
2. mDNS wait `_adb-tls-pairing._tcp` matching service name (**no trailing `.`** — OHOS quirk)
3. `adbPairWireless` NAPI → fill pair host/port; optional “配对并填充 ADB 端口” via `_adb-tls-connect._tcp`
4. Dismissing the dialog must not drop an in-flight success (apply even if UI closed; ignore late failures after cancel)

Do not invert the flow (do not make HO scan Android’s QR unless explicitly adding that mode). mDNS service types: `_adb-tls-pairing._tcp` / `_adb-tls-connect._tcp` with **no trailing `.`**.

## A_STLS / TLS connect

After pairing, ADB session connect uses **A_STLS + TLS 1.3** (`AdbSession::connect_with_key` / `tls_client::upgrade_tcp_to_tls`). Requires a **rebuilt** `libadb_core.so`. Host tests ≠ on-device TLS.

Pairing TLS (SPAKE2 + rustls) is separate from session TLS. Live LAN pair vs Android 11+ wireless debugging is the real gate.

## First-frame / PTS

`protocol::video`: header + length-prefixed CSD; each AU = `pts:i64 BE` + Annex-B. NAPI parse helpers + `OH_VideoDecoder` (`ohos_vdec.rs`).

- Surface display: `OH_VideoDecoder_RenderOutputBufferAtTime` with **CLOCK_MONOTONIC now (ns)**, strictly increasing. Do **not** pass encoder PTS (µs) as Surface ns — first frame shows, later frames freeze.
- Live AU PTS 0 / duplicate: synthesize `+16667µs` (~60fps) on decoder **input**. Input PTS is still microseconds (`OH_AVCodecBufferAttr`).
- Fixture path: `rawfile/fixture_avc_easycontrol.bin` on XComponent `onLoad` → HiLog `SessionDecode FIRST_FRAME_OK`
- Live: `liveSessionStart({ host, adbPort, serverPort, surfaceId, jarBytes, … })`; poll `liveSessionStatus()` for `firstFrame`
- Emu↔LAN RTT can be multi-second; Session may fall back to fixture. Prefer same-LAN HarmonyOS device for live pixels.
- Touch: `liveSessionWriteControl` on **direct** main TCP
- Frozen lock-wallpaper with dead touch: `wakeOnConnect` sends power mode 1 → server `KEYCODE_WAKEUP` (no-op if already lit; does not unlock Keyguard). `lockOnClose` defaults **off**; when on, disconnect sends POWER off.

## Tab bar / safe area

Home **HdsTabs** floating pill uses `safeBottomVp` as `barFloatingStyle.barBottomMargin`. Ignoring layout safe areas on real devices **pushes HdsTabs off-screen** and puts system back under the status bar (`SystemInsets.ets`). Session may still go edge-to-edge.

## DeviceStore

Preferences JSON (`DevicePrefs`), not RDB. No mock seed when empty. Strip `mock-pixel` / `mock-lab` on load. Optional one-time import from legacy `app.db`. Home waits `DeviceStore.isReady()` + `deviceStoreRevision`.

## Native `.so` stale packaging

`libadb_core.so` is Rust (ohos-rs), gitignored under `entry/libs/arm64-v8a/`. Assemble only packages what is already staged unless `entry/hvigorfile.ts` `buildNativeOhos` runs `--if-needed` **before** `ProcessLibs`.

If live pairing/TLS/decode “doesn’t match source”: rebuild with `./scripts/build_native_ohos.sh --force` then Assemble. Skip hook only with `SKIP_NATIVE_OHOS=1` when a known-good `.so` is already staged.

## Android parity map (quick)


| Android (`easycontrolnext/`)      | HarmonyOS                                                                                     |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| `AdbQrPairing.kt` (phone scans)   | Controller **shows** QR; Android scans                                                        |
| Device Room / DataStore           | `DevicePrefs` preferences                                                                     |
| Compose `DeviceEditorScreen`      | ArkUI `DeviceEditor.ets`                                                                      |
| Floating `SmallView` / `MiniView` | Not ported (WindowManager exception on Android)                                               |
| scrcpy-style server JAR           | `scripts/copy_server_jar.sh` → rawfile                                                        |
| ADB RSA / HUKS                    | Per-install RSA, HUKS AES-GCM wrap in filesDir; AUTH sign in Rust. Host Gate C PEM unchanged. |


Worker: `AdbProbeWorker.ets` dlopens `libadb_core.so` off the UI thread — keep it that way.

Do not copy Compose or XML into `harmonyos/`.