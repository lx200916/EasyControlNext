# EasyControlNext · HarmonyOS NEXT

Always-on project rules for this controller app. **Not** a HarmonyOS encyclopedia.

For kit APIs, ArkTS/ArkUI samples, API changelogs, and recipes, load the `harmonyos-development` skill references on demand (see [§9 Intent routing](#9-intent-routing--load-on-demand)). Do not paste those files back into this document or into answers.

## 1. Product boundary

EasyControlNext 鸿蒙端是 **控制器（controller）**，不是受控端。

| | |
|---|---|
| This project | `harmonyos/` — HarmonyOS NEXT Stage app, bundleName `com.shiyunjin.easycontrolnext` |
| Android peer | `../easycontrolnext/` — Gradle / Kotlin / Jetpack Compose |
| Controlled device | Still **Android**. Reuse existing `server` JAR (`scripts/copy_server_jar.sh` → rawfile) |
| Native stack | Rust `protocol` + `adb_client` + ohos-rs cdylib `libadb_core.so` (NAPI). No handwritten C++ NAPI |

- Protocol and product capability should track the Android controller; UI stack and build system must not.
- Do **not** put HarmonyOS modules inside the Android tree, and do **not** add Jetpack Compose / XML layouts here.
- The Compose-first Cursor rule is scoped to `easycontrolnext/**` only — it must not apply while editing `harmonyos/`.
- `deviceTypes`: `phone`, `tablet`, `2in1`. Foldables are first-class (see §5).
- Permissions today: `ohos.permission.INTERNET` + `GET_NETWORK_INFO` (system_grant). Do not add CAMERA just to show a QR — Scan Kit **generate** does not need camera; the controller **displays** QR, Android scans.

Signer policy: `DeterministicTestSigner` is host-test only. On-device ADB RSA is generated once, **HUKS AES-256-GCM wrapped** in `filesDir/adb_rsa_huks.bin` (`AdbKeyAssets` / `AdbHuksWrap`). AUTH signing stays in Rust (SHA-1 PKCS#1). `PendingProductionSigner` is deprecated. Host Gate C/D still use `native/.adb-keys/` PEM. Bundled rawfile `adb_rsa_key.pem` is no longer the live-session path.

Port footguns (QR direction, A_STLS, first-frame PTS, stale `.so`): `.cursor/skills/easycontrol-harmonyos-port/SKILL.md`.

## 2. API baseline

**Production: HarmonyOS 6.1.1 Release / API 24.**

- `build-profile.json5` product `default`: `compileSdkVersion` / `compatibleSdkVersion` / `targetSdkVersion` = `6.1.1(24)`, `runtimeOS: HarmonyOS`.
- Toolchain (API 24): DevEco Studio 6.1.1.280, Hvigor 6.24.2, ohpm 6.1.2, Node.js 18.20.1.
- Do **not** default to HarmonyOS 7 / API 26 Beta1, Node.js 24, DevEco 26, or API 26 UX defaults (32vp touch targets, immersive material `disable` metadata, etc.).
- Mention API 26 only when the user asks for HarmonyOS 7 preview / adaptation. Then read skill `references/api26-preview.md` and mark code as preview.
- Stage model only (`UIAbility` + `WindowStage`). FA model is legacy.

## 3. Repo layout

```
harmonyos/
├── AGENTS.md                    # this file (always-on)
├── IMPLEMENTATION_PLAN.md       # port phases / gates A–E
├── AppScope/app.json5           # bundleName, icon, label
├── entry/                       # HAP
│   ├── hvigorfile.ts            # buildNativeOhos before ProcessLibs
│   ├── libs/arm64-v8a/          # staged libadb_core.so (gitignored)
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   ├── shell/AppShell.ets          # Navigation + NavPathStack
│       │   ├── pages/Index.ets             # @Entry → AppShell
│       │   ├── pages/Home.ets              # HdsTabs 设备 | 设置
│       │   ├── pages/DeviceEditor.ets      # add/edit + QR pair
│       │   ├── pages/Session.ets           # XComponent + decode / live
│       │   ├── pages/Settings.ets / Presets.ets / ErrorLog.ets
│       │   ├── formability/EntryFormAbility.ets + pages/DeviceFormCard.ets
│       │   ├── model/DeviceStore.ets
│       │   ├── data/DevicePrefs.ets        # preferences backend
│       │   ├── adb/AdbPairing.ets / AdbQrPairing.ets
│       │   ├── session/LiveMirror.ets / AdbProbeHost.ets
│       │   ├── media/H264DecodeSession.ets
│       │   ├── native/AdbCore.ets          # NAPI wrapper
│       │   ├── workers/AdbProbeWorker.ets  # dlopen so off UI thread
│       │   ├── types/libadb_core.so.d.ts
│       │   └── common/Breakpoint.ets / SystemInsets.ets
│       ├── module.json5
│       └── resources/{base,dark,rawfile}/
├── native/                      # Rust: protocol, adb_client, adb_core
├── scripts/build_native_ohos.sh / run_host_tests.sh / copy_server_jar.sh
└── .claude/skills/harmonyos-development/   # encyclopedia (on demand)
```

UI entry: `pages/Index.ets` → `AppShell`. Home owns 设备 | 设置 `HdsTabs`. Add device is header `+` → `DeviceEditor`. **Session / DeviceEditor / Settings / Presets / ErrorLog are lazy imports** — they pull `libadb_core.so`; keep them off the first frame. **Form Kit cards (`formability/`) must not import `libadb_core.so`.**

Routes (`AppNavDestination`): `settings`, `presets`, `error_logs`, `device` (uuid or `new`), `session` (uuid).

## 4. ArkTS strict checklist (short)

Full compiler notes: skill `references/arkts-rules.md`. Do not copy that file here.

**Language**

- No `any` / `unknown` as escape hatches. Declare real types; `JSON.parse` immediately to an interface.
- No object-literal return types — use `interface` / `class`.
- No dynamic add/delete of properties; no `bind` / `call` / `apply` reshaping `this`.
- 2-space indent, `lowerCamelCase` methods, `UPPER_SNAKE_CASE` constants, booleans `is`/`has`/`can`.
- Arrow functions in ArkUI callbacks (keep `this`). No async in `build()` — load in `aboutToAppear()` / Ability lifecycle.
- Named `on`/`off` callbacks — anonymous listeners cannot be unregistered.
- Batch `@State` mutations: assign once (`this.list = [...this.list, a, b]`), do not `push` three times.

**Navigation / context**

- `navDestination` needs a **top-level `@Builder` function reference**, not an inline lambda.
- `@Entry` `build()` root must be a container (`Column` / `Stack` / `Row`). `Index` wraps `AppShell` in `Column`.
- `getContext(this)` is deprecated:

```ts
const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
```

```ts
@Builder
function AppNavDestination(name: string, param: Object) {
  if (name === 'device') {
    DeviceEditor({ uuid: `${param}` })
  } else if (name === 'session') {
    Session({ uuid: `${param}` })
  }
}
Navigation(this.pathStack) { Home() }
  .navDestination(AppNavDestination)
```

**API 21+ compile traps (this SDK still enforces them)**

- `DataChangeListener`: implement **both** new names (`onDataAdd`, `onDataDelete`, …) **and** deprecated aliases (`onDataAdded`, …), plus `onDatasetChange`.
- Do not `import type { Permissions } from '@ohos.bundleManager'` — use `@kit.AbilityKit` or a local union of valid permission literals.
- `requestPermissionsFromUser` may infer `void & Promise<…>`. Cast through a local `{ authResults: GrantStatus[] }` if needed.
- Omit `NotificationRequest.slotType` (old vs new `SlotType` modules are nominally incompatible). `addSlot(SlotType)` not a slot object.
- User-grant permissions need `reason` + `usedScene` in `module.json5` **and** a runtime request. `INTERNET` is system_grant — no extra fields.

**This app**

- Probe path: `AdbProbeWorker.ets` is a **Worker** (imports `libadb_core.so` so `dlopen` + connect stay off the UI thread). Do not move that import onto the first-frame Home path.
- Keep `-keep` / NAPI export names if ArkGuard is enabled (`libadb_core.so` + JSON prefs field names).

## 5. Fold / split

Source of truth: `entry/src/main/ets/common/Breakpoint.ets`. Generic foldable encyclopedia: skill `references/foldable-multidevice.md`.

- Prefer **app window width in vp**, not `display.width` (px) and not full-screen display width.
- **Split-screen ≠ unfolded.** Expanded foldable + 50/50 split must use compact chrome.
- `WindowStatusType.SPLIT_SCREEN` / `FLOATING` → `preferSplit = false` even if the pane is ≥ 600vp.
- Fold posture wins during fold/unfold animation — `windowRect` can lag hundreds of ms to seconds. `readLayoutSnapshotFromWindow` uses `foldStatusChange` and may substitute display size when posture says the active panel changed (and we are not in an intentional compact multi-window pane).
- Breakpoints (window width vp): `sm` < 600 (phone / folded outer / narrow split), `md` < 840, `lg` ≥ 840 (unfolded wide / tablet / 2in1).
- Half-fold / folded outer: **never** keep master-detail (`preferSplit` false).
- Switch layouts with **`if/else`**, not `.visibility()` (hidden nodes still layout).
- `AppShell` `@Provide`s: `pathStack`, `preferSplit`, `foldPosture`, `widthVp`, `heightVp`, `safeTopVp`, `safeBottomVp`. `@Consume` those in pages; do not re-query `display.getDefaultDisplaySync()` in every `build()`.
- Pair `startLayoutWatch` / window size+status listeners with `stopLayoutWatch` in `aboutToDisappear`. Foldable: listen to `foldStatusChange`, not only `display.on('change')`.

```ts
export function computePreferSplit(
  widthVp: number, foldPosture: FoldPosture,
  isFoldable: boolean, windowStatus?: window.WindowStatusType
): boolean {
  if (foldPosture === 'half' || foldPosture === 'folded') {
    return false
  }
  if (windowStatus !== undefined && isCompactWindowStatus(windowStatus)) {
    return false
  }
  return breakpointFromWidthVp(widthVp) === BP_LG ||
    (isFoldable && foldPosture === 'expanded' && widthVp >= 600)
}
```

## 6. UI

Skill dump for components / glass / lists: `references/arkui-components.md`. Keep answers to this app's patterns.

**Shell**

- Routing: **Navigation + `NavPathStack`**, not `router`.
- Home tabs: official **HdsTabs** floating bar + `systemMaterialEffect` (液态玻璃 / 沉浸光感). Do not reinvent a custom tab bar.
- `HdsTabs.barFloatingStyle.barBottomMargin` must include **`safeBottomVp`** (`Home.ets`). Ignoring layout safe areas pushes the pill off-screen on real devices.
- `Index` / Home / Settings / DeviceEditor must **not** ignore layout safe areas. Session may go edge-to-edge via its own expand/ignore attributes (`SESSION_FULLSCREEN_ACTIVE_KEY`).
- Add-device primary action: Navigation header `+`, not a FAB that covers the last list row.

**Sheets / dialogs / theme**

- Sheets: `bindSheet` / `openBindSheet` / `openCustomDialog` (`ComponentContent` + module-level `@Builder`). QR pair dialog follows this — builders are **not** `@State`-reactive; status goes through `AppStorage` (`qr_pair_status`).
- Do not add deprecated `CustomDialog` / `@ohos.promptAction`.
- Toast: `this.getUIContext().getPromptAction().showToast(...)`.
- Dark mode: `resources/base` + `resources/dark` (same names). Page bg `$r('app.color.page_background')`. Bars follow `ConfigurationConstant.ColorMode` (`SystemInsets.ets`: light `#FFF2F3F5`, dark `#FF121212`).
- Lists: `LazyForEach` + stable keys (device `uuid`) for long lists. Keep `build()` pure.

**HdsTabs (do not drop safe inset)**

```ts
HdsTabs({ /* 设备 | 设置 */ })
  .barFloatingStyle({
    barBottomMargin: this.safeBottomVp + /* extra floating gap */,
  })
  .barOverlap(true)
```

## 7. Data

Skill dump: `references/data-storage.md`. This app's rule is narrower:

- **DeviceStore = preferences**, not relationalStore. `DevicePrefs` store name `device_store`, key `devices_json` (full `Device` field JSON).
- In-memory cache in `DeviceStore`; Home watches `AppStorage` `deviceStoreRevision`.
- One-time best-effort import from legacy `app.db` / table `DevicesDb` when prefs are empty; then stay on prefs.
- **No mock seed on empty.** Strip legacy mock UUIDs (`mock-pixel` / `mock-lab`) on every load (`stripLegacyMockDevices`).
- Wait for `DeviceStore.isReady()` before showing empty-state (avoid flash on cold start).
- Presets: `PresetStore`. Settings: `AppSettings` preferences. Error log: `AppErrorLog`.
- Do not reintroduce Room/RDB as the live device list without an explicit migration request.

```ts
/** Idempotent: open preferences, load devices (no mock seed on empty). */
static init(context: common.Context): Promise<void> { /* DevicePrefs.open + load */ }

static bumpRevision(): void {
  const prev = AppStorage.get<number>('deviceStoreRevision')
  AppStorage.setOrCreate('deviceStoreRevision', (prev !== undefined ? prev : 0) + 1)
}
```

## 8. Build / native `.so`

Skill dump for generic Hvigor/CI: `references/build-sign-release.md`. Native C API weak refs: `references/native-api-compatibility.md`.

`libadb_core.so` is a **Rust cdylib** (ohos-rs / cargo), **not** CMake / `externalNativeOptions`.

- Hvigor only packages `entry/libs/arm64-v8a/*.so` in `default@ProcessLibs`.
- `entry/hvigorfile.ts` registers **`buildNativeOhos`** with `postDependencies: ['default@ProcessLibs']` so Assemble runs `scripts/build_native_ohos.sh --if-needed` **before** packaging.
- Do **not** assume Assemble rebuilds `.so` unless that hook is present. `entry/libs/` is gitignored — a stale prebuilt ships silently if the hook is skipped or Rust/NDK is missing.
- Escape hatches (still require an existing staged `.so`): `SKIP_NATIVE_OHOS=1` or `hvigorw assembleHap -p skipNativeOhos=true`.
- Host tests (Gate A) do not need NDK: `./scripts/run_host_tests.sh` (`easycontrol-protocol` + `easycontrol-adb-client`, including FakeDaemon).
- Target: `aarch64-unknown-linux-ohos`. `OHOS_NDK_HOME` defaults to DevEco `Contents/sdk/default/openharmony`.
- Server JAR is copied from Android Gradle output via `scripts/copy_server_jar.sh` (rawfile + sha256/version). Changing Android server without copy leaves the HAP on an old jar.

```bash
export OHOS_NDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
./scripts/build_native_ohos.sh              # always rebuild + stage
./scripts/build_native_ohos.sh --if-needed  # skip when staged .so is fresh
./scripts/build_native_ohos.sh --force
./scripts/run_host_tests.sh
./hvigorw assembleHap -p product=default    # buildNativeOhos then ProcessLibs
```

ArkTS: `import adbCore from 'libadb_core.so';` (types in `ets/types/libadb_core.so.d.ts`).

Video: `protocol::video` length-prefix + **PTS** (`pts:i64 BE`) + Annex-B; NAPI `OH_VideoDecoder` in `native/adb_core/src/ohos_vdec.rs` (`RenderOutputBufferAtTime` + monotonic ns; live duplicate PTS → +16667µs). Live: `liveSessionStart` / poll `liveSessionStatus()`; success HiLog `SessionDecode FIRST_FRAME_OK`. Fixture fallback: `rawfile/fixture_avc_easycontrol.bin`.

If pairing TLS / first-frame “doesn't match source”, rebuild `.so` with `--force` then Assemble — do not debug ArkTS first.

## 9. Intent routing — load on demand

Canonical skill: `harmonyos/.claude/skills/harmonyos-development/`.
Cursor entry: `harmonyos/.cursor/skills/harmonyos-development/SKILL.md` (same routing; `references/` / `recipes/` / `examples/` are symlinks).

Read **one** matching file. Do not load the whole tree. Do not inline these files into always-on rules.

| Need | File under `harmonyos-development/` |
|---|---|
| SDK / API 24 vs 26 | `references/platform-baseline.md` |
| HarmonyOS 7 preview | `references/api26-preview.md` |
| DevEco Code/CLI, Intents, A2A | `references/ai-development-tools.md` |
| ArkTS strict / API 21 compile errors | `references/arkts-rules.md` |
| ArkUI, HdsTabs, glass, lists, safe area | `references/arkui-components.md` |
| Fold / split / breakpoints | `references/foldable-multidevice.md` |
| Navigation | `references/navigation.md` |
| `@State` / V2 / StateStore | `references/state-management.md` |
| Stage / Ability / background tasks | `references/stage-model.md` |
| Permissions | `references/permissions.md` |
| Hvigor, OHPM, ArkGuard, CI | `references/build-sign-release.md` |
| Native C API `APIAVAILABLE` | `references/native-api-compatibility.md` |
| TaskPool / Worker / cold start | `references/performance.md` |
| Kit tables / GitCode samples | `references/kits-catalog.md` |
| Camera, Audio, AVPlayer, Scan QR | `references/media-camera-audio.md` |
| HTTP, ArkWeb, Share | `references/network-web.md` |
| preferences / fileIo | `references/data-storage.md` |
| Account / Push / Payment / Map | `references/kits-services.md` |
| UiTest / crashes | `references/testing.md` |
| Build-error recipe | `recipes/debug-build-error.md` |
| Review recipe | `recipes/review-arkts-code.md` |

Pairing / live / native port: `.cursor/skills/easycontrol-harmonyos-port/SKILL.md`.

## 10. Encyclopedia pointer

HarmonyOS kit catalogs, Camera/Payment/Account samples, API 23–26 changelogs, and long ArkUI recipes live in the `harmonyos-development` skill **references/** — not here.

| Layer | What |
|---|---|
| Always-on | this `AGENTS.md` + tiny `.cursor/rules/harmonyos.mdc` |
| On demand | skill `SKILL.md` routing table → **one** reference file |
| Never | duplicate encyclopedia into rules, or paste kit tables into replies |

If a task only needs EasyControlNext behavior, **stop at this file**. Open a reference only when a Kit API, compiler diagnostic, or generic ArkUI pattern is missing here.
