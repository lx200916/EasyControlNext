# API 26 Preview Boundary

This reference is for preview adaptation only.

Use it only when the user explicitly targets HarmonyOS 7, API 26, DevEco Studio 26 Beta, preview adaptation, or Beta SDK compatibility.

## Rule

Do not use API 26-only APIs, SDK versions, behavior changes, or DevEco 26-only tooling in API 24 production answers.

## How to answer preview questions

1. State that the capability is preview or Beta unless it has been promoted to Release.
2. Separate migration risks from implementation steps.
3. Call out SDK, toolchain, permission, and UX behavior changes.
4. If an API signature is uncertain, mark the code as conceptual and ask the user to verify against the installed SDK docs.

---

## Detailed reference

### HarmonyOS 7 / API 26 Beta1 preview (2026/06/12)

**Status (checked 2026/07/25):** developer Beta, not the default production baseline. Huawei has not published API 26 Beta2, RC, or Release. Mention API 26 features only when the user asks about HarmonyOS 7, API 26, HDC 2026, preview adaptation, or Beta1 capabilities. For production code, prefer API 24 Release unless the project explicitly targets API 26 preview.

**Developer kit baseline:** HarmonyOS SDK **26.0.0 Beta1** (OpenHarmony SDK `Ohos_sdk_public 26.0.0.23`, API Version 26.0.0 Beta1) and DevEco Studio **26.0.0 Beta1 (26.0.0.461)**. Toolchain: HarmonyOS Emulator **26.0.0.200**, Hvigor/hvigorw **6.26.1**, ohpm **26.0.0.410**, Node.js **24.14.1**, hstack **6.0.0**, `compileSdkVersion: "26.0.0"`, `targetSdkVersion: "4.0.0(10)~26.0.0"`.

**Version-number rule:** Starting with API **26.0.0**, HarmonyOS developer kit API versions use SemVer (`X.Y.Z`) instead of the legacy `X.Y.Z(N)` format. `X` means a major version with substantial capabilities or adaptation-impacting changes, `Y` means a minor version with new capabilities, and `Z` means compatible fixes/small improvements.

**High-value API 26 Beta1 changes:**
- **Ability Kit** — AgentCard support; ArkTS script-based app Skill development; package-name + clone-index app name lookup; ArkTS APIs for script management; C APIs for `ModularObjectExtensionAbility`.
- **Accessibility Kit** — system care mode integration for elder-friendly app experiences.
- **Accessory Kit** — new Kit for accessory wake-up, system service linkage, on-demand scheduling, and secure trust management.
- **Account Kit** — `LoginWithHuaweiIDButton` supports custom multilingual text and loading animation.
- **AR Engine** — C API camera flash control; ArkTS preview stream image access; 3D Gaussian model loading; ArkTS/C APIs for external camera and sensor data.
- **ArkUI / UI Design** — system material configuration for Toggle, Tips, Toast, dialogs, menus, popups, custom dialogs, half modals, and Popup; component-level immersive light perception; global reuse pools for `@Reusable` / `@ReusableV2`; standard floating windows; title-area customization updates.
- **ArkWeb** — Chromium kernel upgraded from 132 to 144; new security configuration options.
- **AVCodec Kit** — H.265 hardware encoder CBRHQ mode; Audio Vivid encoding and C APIs.
- **AVSession Kit** — new extra-key enum values for scenario-specific AVSession metadata.
- **Background Tasks Kit** — reminder countdown instances add `repeatInterval` and `repeatCount`.
- **Core File Kit** — `UNCACHE` open option, recursive `listFileExt`, mmap-based file mapping, and sharing an app sandbox directory as system-visible.
- **Core Vision Kit** — image super-resolution and semantic text search over images.
- **Data Augmentation Kit** — mail intelligence handler for classification, summarization, and todo extraction.
- **Device Security Kit** — enhanced Star Shield confidential risk-control engine, unified risk-control credentials, privacy policy controls for camera/microphone/location, and file-event subscription/filtering.
- **Driver Development Kit** — query external USB hubs and develop user-mode drivers.
- **Enterprise Data Guard Kit** — file classification policy APIs `getPolicy` and `isKia`.
- **Enterprise Space Kit** — query dual-space state and determine whether the workspace is enterprise space.
- **FAST Kit** — real-number FFT and inverse FFT; intelligent sequence prediction.
- **Graphics Accelerate Kit** — game prelaunch feature to improve startup experience.
- **Image Kit** — metadata classes for GIF/JFIF/TIFF/PNG/AVIS plus XMP metadata.
- **Input Kit** — keyboard and mouse input event injection.
- **Live View Kit** — auxiliary-area template with percentage progress ring.
- **NDK / JSVM** — create `ArrayBuffer` from external memory.
- **NearLink Kit** — `startScan` scans all discoverable nearby NearLink devices.
- **Network Boost Kit** — `netBoost.setDataFlowDesc` sets flow descriptions from five-tuple data.
- **Notification Kit** — stronger notification management/display, including half-modal notification settings entry.
- **Online Authentication Kit** — DID (Decentralized Identifier) key generation, credential import/query/delete, and data signing.
- **PDF Kit** — convert specified regions across multiple pages into one image.
- **Performance Analysis Kit** — gray release fault-log collection and HiAppEvent app-freeze warning subscriptions.
- **Preview Kit** — file acceleration scanning, preload strategy customization, availability query, and file-operation event reporting.
- **Push Kit** — Live View push messages support Wearable devices.
- **Remote Communication Kit** — `HttpVersionSelectCallback` for HTTP version selection, `HMS_Rcp_SetRequestGetDataCallback()` for streaming upload, `HMS_Rcp_SetFormOrder()` for ordered forms, and QUIC C API.
- **Scenario Fusion Kit** — scenario sharing Button supports image, video, and text.
- **Share Kit** — phone-to-PC/2in1/tablet tap sharing can expose tap position on the receiving side.
- **Spatial Recon Kit** — 3DGS gaussian editing and spatial photo generation from a single photo.
- **Scan Kit** — query support for default/custom scan UI on the current device.

**API 26 behavior and UX changes to watch during adaptation:**
- **Ability Kit** — public package-change common events (`COMMON_EVENT_PACKAGE_ADDED`, `REMOVED`, `CHANGED`, `CACHE_CLEARED`) add controls for In-House apps when `targetSdkVersion >= 26.0.0`; In-House apps must configure `allowListenBundleChangedEvent` in `app.json5` for third-party listeners.
- **ArkTS / JSVM** — Chromium/V8 core upgrades 132 → 144; async function type detection is fixed; Wasm jitless default behavior changes; `fastConvertToJSObject` now preserves sibling text nodes when parsing XML.
- **ArkUI** — `NodeAdapter.onAttachToNode`, mouse `rawDeltaX/rawDeltaY`, `LayoutPolicy.matchParent`, `EmbeddedComponent` focus, `WithTheme`, `queryNavDestinationInfo` / `onResult` on the home `NavDestination`, `NODE_SWIPER_EVENT_ON_CONTENT_DID_SCROLL`, and shadow blur radius behavior have adaptation-impacting changes.
- **Permissions** — `ohos.permission.READ_IMAGEVIDEO`, `getUidRxBytes`, `getUidTxBytes`, and general permission policy behavior change under API 26 rules.
- **UX** — form controls minimum touch target changes from 28vp to 32vp for Button/Button-style Toggle/Select/Chip/ChipGroup; built-in text line breaking and small-language line height are optimized; Dialog, Toast, AlphabetIndexer, and text selection menu enable immersive system material by default. Disable globally with `metadata` name `ohos.arkui.UIMaterial.state` value `disable`, or per component with `uiMaterial.Material.empty`.

**API 26 V2 behavior-scope notes (official docs updated 2026/06/17):**
- **Always effective:** JSVM/Chromium 132 → 144, async function type detection, `fastConvertToJSObject` sibling-text preservation, ArkUI `rawDeltaX/rawDeltaY`, Stage-only ArkUI API constraints, home `NavDestination` `queryNavDestinationInfo` / `onResult`, `@ReusableV2` dynamic reuse identifiers, ArkWeb Chromium 132 → 144, `READ_IMAGEVIDEO` permission behavior, and notofonts small-language font updates.
- **Effective only when `targetSdkVersion >= 26.0.0`:** In-House package-change event controls, JSVM Wasm jitless default behavior, `NodeAdapter.onAttachToNode`, attributed-string paragraph style with leading `CustomSpan` / `ImageAttachment`, `LayoutPolicy.matchParent`, `EmbeddedComponent` focus, `WithTheme`, `NODE_SWIPER_EVENT_ON_CONTENT_DID_SCROLL`, component shadow blur radius, `getUidRxBytes` / `getUidTxBytes`, permission policy changes, 32vp form-control touch targets, built-in text style optimization, immersive material defaults, and half-modal centered dialog max height.

**DevEco Studio 26.0.0 Beta1 additions:**
- AI coding: custom Agent token usage display, conversation rollback, project Q&A with MCP Market tools / LSP tools / ArkTS and C++ semantic code search, built-in Inline Chat commands such as File Comments and Parameter Validation, `UI Verification` tool, and custom Commands.
- Editing/debugging: API 26.0.0 projects, Load/Unload Modules, ArkUI state-variable relation viewer, Code Scanner resource-leak checks, custom Clang-Tidy, ACL permission requests, 8-breakpoint preview, Car multi-screen emulator, scenario simulation, remote emulator control, Native debug startup acceleration, device projection, SQL-highlight database debugging, dump-file stack parsing, HiLog tag filtering, AppAnalyzer report diagnosis, and diagnostics for OOM/app-freeze/resource leaks.
- Performance analysis: Memory lane adds ArkWeb PA and JS Heap sub-lanes for Malloc allocation and ArkWeb Render-process JS heap usage, plus a Statistics tab for VMA counts and PSS memory min/max/average.
- Build/release: `apiCompatibilityCheck`, `tsImportSoCheck`, module `nativeLib.enableSoDirCollection`, `syncNative`, Hvigor `getAllDependencyInfo`, AppGallery package re-signing, Linux emulator support, and ohpmrc `auto_skip_install`, `metadata_cache_effective`, `metadata_cache`, plus exact-version metadata queries.
- Compatibility changes: DevEco Studio and Command Line Tools upgrade Node.js from 18 to **24**; custom Hvigor/ohpm/ohpm-repo plugins need Node.js 24 adaptation. `ohpm-repo 5.5.1` no longer depends on `node-fetch`; plugins that relied on that bundled dependency must replace it or install `node-fetch@2.7.0` themselves.

**DevEco Testing 26.0.0 Beta1:**
- Stability testing can target specified entry points to trigger stability issues and expands memory-leak detection coverage.
- UX testing supports multi-device layout comparison across straight-screen and foldable devices.
- Test-service matrix includes local app listing precheck, performance baseline/monitoring, stability baseline, memory-leak testing, UX baseline and multi-device layout comparison, security baseline, power baseline, functional-experience baseline, exploratory testing, regression testing, device projection, UIViewer, app graph management, performance report auto-analysis, and report comparison.

**HarmonyOS AI development tools and capability highlights (officially surfaced 2026/06):**
- **DevEco Code** — a HarmonyOS-focused AI coding Agent for planning, code generation, build/run, device logs, UI verification, ArkTS checking, knowledge lookup, debugging, and iterative repair. It complements DevEco Studio rather than replacing the SDK/toolchain.
- **DevEco CLI** — Agent-friendly command-line access to project creation, syntax checks, build, device run/debug, and other HarmonyOS engineering actions; use it for third-party coding Agents, automation, and CI/CD integration.
- **CodeGenie** — the DevEco Studio AI assistant/plugin remains a separate product surface. Huawei lists CodeGenie 6.1.1 Release, Command Line Tools 6.1.1 Release, and DevEco Studio 6.1.1 Release for the production toolchain; the API 26 toolchain remains Beta1.
- **Agent Framework Kit** — launches a combination of system Agents from an app through UI controls. Keep it distinct from Intents Kit (declaring app intents), ArkTS script-based app Skills (exposing app capabilities), and device-side A2A (Agent-to-Agent communication).
- **HarmonyOS 7 experience areas** — spatial-audio processing nodes, app/game quick start, cold-start network preconnection, QUIC and weak-network live-stream optimization, and LTPO variable frame rate are highlighted platform capabilities; confirm the installed API 26 SDK and device support before presenting them as generally available APIs.
- **API 26 cloud debugging** — AGC remote-device cloud debugging can filter devices by API 26 or system version `7.0.0.23` for early compatibility validation.

For tool selection, capability boundaries, and answer rules, read `references/ai-development-tools.md`.

### Official documentation updates (2026/06/12)

Huawei's release docs did not add a newer SDK after 26.0.0 Beta1, but the documentation change log added several developer-facing guides worth surfacing in answers:

- **Ability Kit app lifecycle** — new guides cover full app lifecycle state changes, startup configuration such as window mode and start page path, quick-start launch, user/app/system exits, and active/passive restart flows.
- **Ark Intelligence Development Framework** — new guides cover the framework overview, Intent Framework development, ArkTS script-based app Skill development, and device-side A2A framework development for exposing app capabilities to system agents such as Xiaoyi.
- **Window management** — 20+ development scenarios were reorganized and expanded, including window type, mode, layout, focus, and a new guide for locating common window logs/issues with `hidumper`.
- **ArkTS Sendable practice** — new Sendable migration/practice guide demonstrates using TurboTransJSON to operate on Sendable objects in ArkTS.
- **FA model docs moved** — FA model is no longer the recommended app model except mainly for lightweight smart wearables; general HarmonyOS app docs now retain Stage model content, while FA model guidance moved under lightweight wearable app development basics.

### Official documentation updates (2026/07)

No newer HarmonyOS 7 SDK was published, but several official guides now affect implementation and review answers:

- **Native C API compatibility** — SDK API 22+ can use weak references with `APIAVAILABLE` for APIs newer than `compatibleSdkVersion`. Correct link dependencies, weak-library configuration for libraries absent on old devices, runtime fallbacks, and tests on both the oldest compatible device and the new-API device are mandatory. Compilation alone is insufficient because a missing dependency can fail only at runtime. Read `references/native-api-compatibility.md`.
- **Linux CI pipeline** — use JDK 17 and the matching Command Line Tools, prefer their bundled Node.js, install project/module dependencies, run Hvigor with `--no-daemon`, protect signing secrets, install signed HAPs with HDC, and enable `caseSensitiveCheck` to expose filename/import mismatches hidden by Windows or macOS. Read `references/build-sign-release.md`.
- **ArkTS leak detection** — use `@ohos.hiviewdfx.jsLeakWatcher` primarily in development; production use should be limited to a small gray-release population. Combine it with JS Heap snapshots, HWASan/AddrSanitizer, AppFreeze, and HiAppEvent according to the suspected layer. Read `references/performance.md`.
- **Container-responsive ArkUI** — use `ContainerReader` when layout must react to the containing component rather than the window. API 26 also documents centralized reuse pools for `@Reusable` / `@ReusableV2`; reuse requires explicit lifecycle cleanup and state reset. Read `references/arkui-components.md`.
