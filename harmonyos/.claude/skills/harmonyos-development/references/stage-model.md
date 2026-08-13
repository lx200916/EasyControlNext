# Stage Model Reference

Use this reference for HarmonyOS application model, lifecycle, UIAbility, ExtensionAbility, AbilityStage, and migration from FA model.

## Defaults

- New HarmonyOS NEXT applications should use the Stage model.
- FA model is legacy and should only be recommended for migration context or legacy maintenance.
- Explain lifecycle and context usage in HarmonyOS terms, not Android Activity terms.

## Core concepts

- `AbilityStage`: application process-level initialization and callbacks.
- `UIAbility`: page window entry and foreground UI lifecycle.
- `WindowStage`: window creation and page loading.
- `ExtensionAbility`: background or system integration capability, depending on extension type.
- `module.json5`: declares abilities, permissions, and module metadata.

## Review checklist

- Correct ability type for the requested feature.
- No FA-model recommendation for new projects.
- Proper context passed to APIs that require ability context.
- Lifecycle side effects are placed in safe callbacks.
- Module configuration matches implementation code.

---

## Detailed reference

## Project layout (Stage model)

```
MyApp/
├─ AppScope/
│  ├─ app.json5                 # global app config (bundleName, icon, label)
│  └─ resources/                # shared resources
├─ entry/                       # main HAP (entry module)
│  ├─ src/main/
│  │  ├─ ets/
│  │  │  ├─ entryability/EntryAbility.ets   # UIAbility subclass
│  │  │  ├─ entrybackupability/
│  │  │  └─ pages/Index.ets                 # ArkUI pages
│  │  ├─ resources/              # strings, colors, media, profiles
│  │  └─ module.json5            # module config, abilities, permissions
│  └─ build-profile.json5
├─ oh-package.json5              # ohpm dependencies
└─ build-profile.json5           # project-level
```

## The Stage model — core concepts

### Component types

- **UIAbility** — has UI, handles user interaction. Entry points. One instance per task.
- **ExtensionAbility** — background / extension scenarios:
  - `ServiceExtensionAbility` — background services (system apps)
  - `FormExtensionAbility` — home-screen widget (服务卡片)
  - `WorkSchedulerExtensionAbility` — deferred tasks
  - `InputMethodExtensionAbility`, `WallpaperExtensionAbility`, `BackupExtensionAbility`, etc.
- **AbilityStage** — module-level lifecycle container (one per HAP)
- **WindowStage** — window container scoped to a UIAbility

### UIAbility lifecycle

```ts
import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void { }
  onDestroy(): void { }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => { /* ... */ });
  }
  onWindowStageDestroy(): void { }
  onForeground(): void { }
  onBackground(): void { }
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void { }
}
```

### Launching another ability

```ts
import { common, Want } from '@kit.AbilityKit';

const ctx = getContext(this) as common.UIAbilityContext;
const want: Want = {
  bundleName: 'com.example.app',
  abilityName: 'DetailAbility',
  parameters: { id: 42 }
};
ctx.startAbility(want);
// or startAbilityForResult for a return value
```

### module.json5 essentials

```json5
{
  "module": {
    "name": "entry",
    "type": "entry",                // entry | feature | shared
    "srcEntry": "./ets/entryability/EntryAbility.ets",
    "deviceTypes": ["phone", "tablet", "2in1"],
    "abilities": [{
      "name": "EntryAbility",
      "srcEntry": "./ets/entryability/EntryAbility.ets",
      "startWindowIcon": "$media:startIcon",
      "startWindowBackground": "$color:start_window_background",
      "skills": [{
        "actions": ["action.system.home"],
        "entities": ["entity.system.home"]
      }]
    }],
    "requestPermissions": [
      { "name": "ohos.permission.INTERNET" }
    ]
  }
}
```

## Atomic Services / Meta-Services (原子化服务 / 元服务)

Installation-free, small (≤10MB) apps launched from:
- Service cards (home-screen widgets built with `FormExtensionAbility`)
- Search, scan, NFC, cross-device continuation

Configured via `module.json5` with `"installationFree": true`. Build-time they produce `.app` packages containing multiple HAPs.

## Distributed features

- **Cross-device continuation** (流转) — `continueAbility` / `onContinue`/`onNewWant` lifecycle
- **Distributed data object** — synced state across devices
- **Distributed file system** — shared sandbox
- **Device manager** — discover trusted devices

## Packaging types

| Type | Purpose |
|---|---|
| **HAP** (Harmony Ability Package) | Runnable module: `entry` or `feature` type |
| **HSP** (Harmony Shared Package) | In-app shared module, dynamic-linked at runtime |
| **HAR** (Harmony Archive) | Static library, packaged into HAP at build time |

Distribute via AppGallery Connect (华为应用市场).

Official samples: https://developer.huawei.com/consumer/cn/samples/

## Background Tasks — 4 types

| Type | API | Duration | Use case |
|---|---|---|---|
| **Transient** | `requestSuspendDelay` | ~3 min max | Save data, upload logs |
| **Continuous** | `startBackgroundRunning` | Unlimited (needs notification) | Music, navigation, recording |
| **Deferred** | `workScheduler.startWork` | System-determined | Timed sync, cleanup |
| **Agent Reminders** | `ReminderRequestTimer` | System-managed | Alarms, timers |

**Continuous task example:**
```ts
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';

// module.json5: "abilities": [{ "backgroundModes": ["audioRecording"] }]
// permission: ohos.permission.KEEP_BACKGROUND_RUNNING

const info: wantAgent.WantAgentInfo = {
  wants: [{ bundleName: 'com.example.app', abilityName: 'MainAbility' }],
  actionType: wantAgent.OperationType.START_ABILITY,
  requestCode: 0, actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
};
const agent = await wantAgent.getWantAgent(info);
backgroundTaskManager.startBackgroundRunning(
  this.context, backgroundTaskManager.BackgroundMode.AUDIO_RECORDING, agent
);
```

9 background modes: `dataTransfer` · `audioPlayback` · `audioRecording` · `location` · `bluetoothInteraction` · `multiDeviceConnection` · `taskKeeping` (2-in-1 only)

**Deferred task frequency by user activity:** Active=2h, Frequent=4h, Regular=24h, Rare=48h, Never used=prohibited.

## Desktop shortcuts (桌面快捷方式)

### 1. Create `resources/base/profile/shortcuts_config.json`

```json
{
  "shortcuts": [
    {
      "shortcutId": "id_scan",
      "label": "$string:shortcut_scan",
      "icon": "$media:ic_scan",
      "wants": [{
        "bundleName": "com.example.myapp",
        "moduleName": "entry",
        "abilityName": "EntryAbility",
        "parameters": { "shortcutKey": "ScanPage" }
      }]
    }
  ]
}
```

### 2. Register in module.json5

```json5
"abilities": [{
  "name": "EntryAbility",
  "metadata": [{
    "name": "ohos.ability.shortcuts",
    "resource": "$profile:shortcuts_config"
  }]
}]
```

### 3. Route based on shortcut parameter

```ts
// In EntryAbility — onCreate / onNewWant
const shortcutKey = want?.parameters?.shortcutKey as string;
if (shortcutKey === 'ScanPage') {
  AppStorage.setOrCreate('targetPage', 'pages/Scan');
}
```

Page reads `@StorageProp('targetPage')` and navigates accordingly.
