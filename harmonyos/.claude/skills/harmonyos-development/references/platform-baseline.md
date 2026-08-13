# Platform Baseline

## Default policy

- Production default: HarmonyOS 6.1.1 Release / API 24.
- Preview-only: HarmonyOS 7 / API 26 Beta1.
- New apps should use the Stage model.
- FA model is legacy and should only appear in migration explanations.

## Answering rules

1. If the user does not provide a target SDK, assume API 24 Release for production code.
2. Do not mix API 26-only APIs into API 24 production examples.
3. When discussing API 26, clearly mark it as preview/adaptation-only.
4. For debugging, request or inspect:
   - DevEco Studio version
   - compileSdkVersion
   - compatibleSdkVersion / targetSdkVersion
   - module.json5
   - oh-package.json5
   - full build error log

## Toolchain notes

- API 24 production examples should avoid API 26 preview-only syntax, behavior, or configuration.
- API 26 examples should mention Node.js 24 / newer DevEco Studio only when the user explicitly targets preview adaptation.

---

## Detailed reference

## Platform snapshot

| Item | Value |
|---|---|
| OS | **HarmonyOS 6.1** (stable, released 2026/04/20, API 23). **HarmonyOS 6.1.1** (Release, released 2026/05/26, API 24). **HarmonyOS 7 / 26.0.0 Beta1** (developer preview, released 2026/06/12, API 26). Pure HarmonyOS, AOSP-free |
| Language | **ArkTS** (primary), **Cangjie** (beta), C/C++ via NAPI |
| UI framework | **ArkUI** declarative (ArkUI-X for cross-platform) |
| Compiler | **ArkCompiler** — AOT to native machine code; LiteActor concurrency |
| Package manager | **ohpm** — `oh-package.json5`; registry at DevEco Service (OHPM Central) |
| IDE | **DevEco Studio 6.1.1 Release** (6.1.1.280; API 24 production). **DevEco Studio 26.0.0 Beta1** (26.0.0.461; API 26 preview) |
| App model | **Stage model** (FA model is legacy — don't use in new apps) |
| Packaging | HAP (entry/feature), HSP (shared package), HAR (static archive), atomic .app |
| Recommended API | **Use API 24 Release for production. Use API 26 Beta1 only for HarmonyOS 7 preview/adaptation.** |
| Sample catalog | https://developer.huawei.com/consumer/cn/samples/ |

**Release timeline (recent):**
- HarmonyOS 6.0.1(21) — 2025/11/25 (initial stable with Mate 80 series)
- HarmonyOS 6.0.2(22) — 2026/01/23 (incremental update)
- HarmonyOS 6.0.0.328 Pollen Beta(23) — 2026/02/28 (closed beta, 25 models)
- HarmonyOS 6.1(23) — 2026/04/20 (stable general release)
- HarmonyOS 6.1.1(24) Beta 1 — 2026/04/30 (developer beta)
- HarmonyOS 6.1.1(24) Release — 2026/05/26 (API 24 Release; DevEco Studio 6.1.1.280)
- HarmonyOS 7 / 26.0.0 Beta1 — 2026/06/12 (API 26 developer preview; DevEco Studio 26.0.0.461)

### What's new in API 23 (HarmonyOS 6.1)

**ArkUI enhancements:**
- `Navigation` supports binding the routing stack to the component itself and specifying a `NavDestination` as the navigation bar (home page) — no more separate root container needed
- `Menu` adds `anchorPosition` property: control popup position relative to upper-left of anchor with horizontal/vertical offsets
- `Image` component improved SVG parsing capabilities
- Batch of new C APIs for attribute styles (Native side)

**New C-side capabilities (Native/NAPI):**
- UDMF (Unified Data Management Framework) C APIs
- Component drag-and-drop C APIs
- Cryptographic algorithm C APIs

**Data:**
- `relationalStore` enhanced `sendable` function — better cross-thread data passing

**Graphics & AI:**
- AI super frame feature in Graphics Accelerate Kit (frame interpolation for smoother animations)

**ArkWeb:** further capability enhancements (intercept/cookies)

### What's new in API 24 (HarmonyOS 6.1.1 Release)

**Version baseline:** API 24 is now a Release SDK (not only Beta). Use DevEco Studio 6.1.1 Release (6.1.1.280), HarmonyOS SDK 6.1.1 Release, Hvigor 6.24.2, ohpm 6.1.2.268, and Node.js 18.20.1 for API 24 projects.

**Release additions over Beta1:**
- **Ability Kit** — `AbilityStage` adds callbacks before the first Ability is created and when a process starts from an application snapshot.
- **ArkTS** — adds `enableLocalHandleDetection` to keep EventHandler/libuv tasks inside the intended scope and avoid leaks; XML parsing adds `XmlSAXHandler` callbacks for SAX-style parsing.
- **ArkWeb** — download completion callbacks can retrieve the original URL and referrer URL.
- **Call Service Kit** — enterprise call service lookup for incoming/outgoing phone numbers.
- **Camera Kit professional controls** — flash-state event subscribe/unsubscribe; OIS query/set; lens focal length/equivalent focal length/min focus distance/distortion/intrinsic calibration/sensor size/pixel array/color-filter data; logical camera composition; auto/manual exposure; manual focus; ISO; physical aperture.
- **CANN Kit** — large-language-model inference acceleration APIs on PC devices.
- **MDM Kit** — manage hidden settings entries for the current user.

**Beta1 additions still relevant in API 24 Release:**
- **Camera Kit "Follow the Person"** — automatic camera tracking API that keeps a person centered in frame via real-time crop/zoom. Useful for video calls, workout recording, vlogging:
  ```ts
  // Conceptual API — full signature in official docs
  cameraSession.enableSubjectTracking(camera.TrackingMode.PERSON);
  ```
- **Delayed preview output** — add delayed preview directly to the stream pipeline instead of normal preview output, and configure its Surface separately.
- **ArkTS VM diagnostics** — heap information per VM thread, heap-warning callbacks after GC, and `taskpool.execute()` timeout settings.
- **ArkUI** — parallel-window state query, custom component migration across Ability instances, dynamic layout container, root node lookup for `UIContext`, async drag-drop decisions, `onNeedSoftkeyboard`, Canvas/OffscreenCanvas `antialias`, Tabs nested scrolling, multiline ellipsis modes (`MULTILINE_START`, `MULTILINE_CENTER`).
- **ArkWeb** — User-Agent Client Hints, default context-menu switch, URL whitelist and load/jump security controls.
- **Audio Kit** — independent audio session strategy/behavior for capture/rendering, plus OH_MIDI C APIs for USB/BLE MIDI devices.
- **New/expanded Kits** — Content Embed Kit, Enterprise Threat Protection Kit, FAST Kit, NearLink Kit, Network Boost Kit, Screen Time Guard Kit, Device Security Kit, Desktop Extension Kit.
- **DevEco Studio** — API 24 projects, Hot Reload for C++ and resource edits, expanded AppFreeze parsing, ComMemory UI memory analysis, `strictCheckerOnly` for faster strict syntax checks.
