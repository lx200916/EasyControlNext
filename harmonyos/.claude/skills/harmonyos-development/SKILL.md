---
name: harmonyos-development
description: >
  Use when developing, reviewing, debugging, or migrating HarmonyOS NEXT native apps
  with ArkTS, ArkUI, DevEco Studio, DevEco Code, DevEco CLI, Agent Framework Kit,
  Stage model, UIAbility, .ets, module.json5, oh-package.json5, HAP/HSP/HAR,
  API 22-24, API 26 Beta1, HarmonyOS 6.1, HarmonyOS 6.1.1 Release, HarmonyOS 7 preview,
  HarmonyOS 26.0.0 Beta1, state management, Navigation/NavPathStack, ArkTS concurrency,
  permissions, persistence, networking, media, Camera Kit, Scan Kit, Map Kit, Push Kit,
  Payment Kit, App Linking, Share Kit, Weather Service Kit, ArkGuard, APIAVAILABLE,
  ContainerReader, jsLeakWatcher, Linux CI, testing, performance, or common 鸿蒙开发 workflows.
---

# HarmonyOS (鸿蒙) Development

HarmonyOS NEXT native apps (AOSP-free). Primary language **ArkTS**; UI **ArkUI**; app model **Stage**.

This SKILL.md is a **router**, not an encyclopedia. Load files under `references/`, `recipes/`, and `examples/` on demand. Do **not** dump kit catalogs, API changelogs, or long samples into answers or into always-on rules (`AGENTS.md`, `.mdc`).

**EasyControlNext first:** project constraints (controller vs Android peer, DeviceStore preferences, `libadb_core.so`, fold/split, HdsTabs safe area) live in `harmonyos/AGENTS.md`. Read that before any reference file. Pairing/live/native footguns: `harmonyos/.cursor/skills/easycontrol-harmonyos-port/SKILL.md`.

### How to load (do not skip)

1. Match the user intent to **one row** in the table below.
2. `Read` that file (and the “Then” column only if still blocked).
3. Answer with the smallest relevant excerpt. Never paste a whole reference.
4. If the question is project-specific and `AGENTS.md` already answers it, do not open the encyclopedia.

## Production default

| Item | Value |
|---|---|
| Production SDK | **HarmonyOS 6.1.1 Release / API 24** |
| Preview only | HarmonyOS 7 / API 26 Beta1 — only when the user asks |
| App model | Stage (`UIAbility`). FA is legacy |
| IDE / toolchain (API 24) | DevEco Studio 6.1.1.280, Hvigor 6.24.2, ohpm 6.1.2, Node.js 18.20.1 |

Do not mix API 26-only APIs, UX defaults, or toolchain (Node 24 / DevEco 26) into API 24 production code.

## When to use this skill

- Writing or reviewing `.ets`, `module.json5`, `app.json5`, `oh-package.json5`, `build-profile.json5`
- Stage model, Navigation, ArkUI, permissions, media, network, persistence
- HAP/HAR/HSP build, signing, native NAPI / C API compatibility
- HarmonyOS 7 / API 26 preview adaptation (mark as preview)

## Intent routing — read only what you need

Paths are relative to this skill directory.

| User intent | Read first | Then |
|---|---|---|
| SDK / DevEco / API baseline | `references/platform-baseline.md` | `references/api26-preview.md` if preview |
| DevEco Code/CLI, Agent Framework, Intents, A2A | `references/ai-development-tools.md` | `references/api26-preview.md` |
| ArkTS syntax, `any`, compiler errors | `references/arkts-rules.md` | `examples/lazyforeach-list.ets` |
| ArkUI layout, HdsTabs, liquid glass, lists | `references/arkui-components.md` | `references/state-management.md` |
| Foldable / split / window vs display | `references/foldable-multidevice.md` | `references/arkui-components.md` |
| Native C/C++ `APIAVAILABLE` / weak libs | `references/native-api-compatibility.md` | `references/build-sign-release.md` |
| Stage model / Ability / background tasks | `references/stage-model.md` | `recipes/debug-build-error.md` |
| Navigation / NavPathStack | `references/navigation.md` | `references/state-management.md` |
| `@State` / V2 / StateStore | `references/state-management.md` | `references/arkts-rules.md` |
| Permissions | `references/permissions.md` | `examples/permission-request.ets` |
| Build, CI, signing, ArkGuard, OHPM | `references/build-sign-release.md` | `references/platform-baseline.md` |
| Perf, TaskPool/Worker, cold start | `references/performance.md` | `examples/lazyforeach-list.ets` |
| Kit catalog / GitCode samples | `references/kits-catalog.md` | kit file below |
| Camera / Audio / AVPlayer / Scan QR / Image | `references/media-camera-audio.md` | — |
| HTTP / WebSocket / ArkWeb / Share | `references/network-web.md` | — |
| preferences / RDB / fileIo | `references/data-storage.md` | — |
| Account / Push / Payment / Map / Form | `references/kits-services.md` | — |
| UiTest / arkxtest / crashes | `references/testing.md` | `recipes/debug-build-error.md` |
| Build error | `recipes/debug-build-error.md` | `references/build-sign-release.md` |
| Code review | `recipes/review-arkts-code.md` | `references/arkts-rules.md` |

Full table: `references/README.md`.

## Answer rules

1. **API 24 production unless the user names API 26 / HarmonyOS 7.**
2. **Do not inline this encyclopedia.** Quote the smallest snippet that unblocks the task.
3. Prefer `@kit.*` imports and `.ets` examples. No React / Android View / Compose advice unless comparing to the Android peer app.
4. `navDestination` must be a `@Builder` function reference, not an inline lambda.
5. `getContext(this)` is deprecated — use `this.getUIContext().getHostContext()`.
6. User-grant permissions need `reason` + `usedScene` in `module.json5` **and** a runtime request.
7. Large lists: `List` + `LazyForEach` + stable keys. Prefer `if/else` over `.visibility()`.
8. Compilation is not proof of native API compatibility — see `references/native-api-compatibility.md`.

## Do not dump encyclopedia

Never copy `references/kits-catalog.md`, API 23–26 changelogs, or full Kit sample pages into:

- `harmonyos/AGENTS.md`
- `.cursor/rules/*.mdc`
- chat replies “for completeness”

Those files exist so they can stay **out** of always-on context.

## HarmonyOS 7 / API 26

Treat as **developer preview**. Separate migration risks from implementation. Verify signatures against the installed API 26 SDK. Details: `references/api26-preview.md`.

Canonical tree: this directory. Cursor discovery: `harmonyos/.cursor/skills/harmonyos-development/` (thin SKILL + symlinked `references/` / `recipes/` / `examples/`).
