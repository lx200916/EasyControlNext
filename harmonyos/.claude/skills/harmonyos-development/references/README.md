# HarmonyOS Skill Reference Loading Guide

This directory contains supporting reference files for the `harmonyos-development` skill.

The root `SKILL.md` remains the discovery entry. These files are loaded **only when the user request needs deeper guidance**. Do not dump them into always-on context or into every answer.

Canonical tree: `harmonyos/.claude/skills/harmonyos-development/`.
Cursor discovers the same skill via `harmonyos/.cursor/skills/harmonyos-development/` (thin SKILL + symlinked references).

## Intent routing

| User intent | Read first | Then read |
|---|---|---|
| Version, SDK, DevEco Studio, API baseline | `platform-baseline.md` | `api26-preview.md` only for preview requests |
| DevEco Code/CLI, Agent Framework, app Skill, Intents, A2A | `ai-development-tools.md` | `api26-preview.md` for HarmonyOS 7 preview details |
| ArkTS syntax, compiler errors, TypeScript migration | `arkts-rules.md` | `../examples/*.ets` |
| ArkUI layout, components, HdsTabs, liquid glass, lists | `arkui-components.md` | `state-management.md` |
| Foldable / split-screen / window vs display width | `foldable-multidevice.md` | `arkui-components.md` |
| Native C/C++ API availability across OS versions | `native-api-compatibility.md` | `build-sign-release.md` |
| Stage model lifecycle, abilities, background tasks | `stage-model.md` | `../recipes/debug-build-error.md` |
| Navigation and page stack | `navigation.md` | `state-management.md` |
| State decorators and data flow | `state-management.md` | `arkts-rules.md` |
| Permissions and privacy prompts | `permissions.md` | `../examples/permission-request.ets` |
| Build, CI, signing, packaging, ArkGuard, OHPM | `build-sign-release.md` | `platform-baseline.md` |
| Performance, TaskPool/Worker, cold start, memory | `performance.md` | `../examples/lazyforeach-list.ets` |
| Kit catalog / GitCode samples | `kits-catalog.md` | kit-specific file below |
| Camera, Audio, AVPlayer, Scan Kit QR, Image Kit | `media-camera-audio.md` | `performance.md` |
| HTTP, WebSocket, ArkWeb, App Linking, Share | `network-web.md` | `permissions.md` |
| preferences, relationalStore, fileIo | `data-storage.md` | `permissions.md` |
| Account, Push, Payment, Map, Location, Form Kit | `kits-services.md` | `permissions.md` |
| arkxtest / UiTest / crash types | `testing.md` | `../recipes/debug-build-error.md` |
| Build error recipe | `../recipes/debug-build-error.md` | `build-sign-release.md` |
| ArkTS/ArkUI review recipe | `../recipes/review-arkts-code.md` | `arkts-rules.md` |

## Production default

Use API 24 Release as the production default unless the user explicitly targets HarmonyOS 7 / API 26 preview.

## Answer rule

Do **not** paste encyclopedia sections into replies. Read the matching file, then answer with the smallest relevant excerpt.
