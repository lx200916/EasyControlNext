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
