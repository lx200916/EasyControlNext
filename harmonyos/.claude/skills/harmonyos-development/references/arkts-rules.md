# ArkTS Rules

Use this file for ArkTS syntax, TypeScript-to-ArkTS migration, and code review.

## Defaults

- Prefer `.ets` examples for HarmonyOS UI and ability code.
- Prefer explicit types over dynamic object shapes.
- Avoid generic TypeScript, DOM, React, Android, or Web-only advice unless the user explicitly asks for comparison.
- Include imports from `@kit.*` where possible.

## Review checklist

- Strict typing is respected.
- State is not mutated through unsupported dynamic patterns.
- Async work is not placed in unsafe lifecycle positions.
- Classes used with `@ObjectLink` are marked with `@Observed`.
- Nullability and optional values are handled explicitly.
- API version assumptions are stated.

## Common output pattern

When generating implementation code, include:

1. File path suggestion.
2. ArkTS code.
3. Required config changes.
4. Integration notes.
5. API baseline notes.

---

## Detailed reference

## ArkTS language — strictness rules

ArkTS = TypeScript MINUS dynamic patterns, PLUS stricter static typing for AOT perf.

**Prohibited / changed vs TS:**
- No `any` / `unknown` as everyday escape hatches — declare real types
- No dynamic property add/delete on objects (`obj.foo = bar` on untyped object is a compile error)
- No `Function.prototype.bind`, `call`, `apply` with reshaped `this`
- No structural typing shortcuts — use nominal classes / interfaces
- No `Object.keys`/`Object.assign` for arbitrary reshaping
- `Record<K,V>` for true dictionary maps
- Use `class` / `interface` with explicit fields

```ts
// Prefer:
class User { constructor(public id: number, public name: string) {} }
// Over:
// const user: any = { id: 1, name: 'A' }
```

### Naming conventions (official coding style guide)

| Element | Convention | Example |
|---|---|---|
| Classes, Structs, Enums | **UpperCamelCase** | `PersonInfo`, `ColorType` |
| Variables, Parameters, Methods | **lowerCamelCase** | `userName`, `getUserInfo()` |
| Constants | **UPPER_SNAKE_CASE** | `MAX_VALUE`, `DEFAULT_TIMEOUT` |
| Boolean variables | Prefix with `is`, `has`, `can` | `isVisible`, `hasPermission` |

Formatting: 2-space indent, max 120 chars/line, K&R braces, always use `{}` for if/for/while.

### High-performance ArkTS rules (from official best practices)

1. Use `const` for unchanging values — enables engine optimization
2. Never mix int and float in same variable — `let n = 1; n = 1.1;` causes boxing overhead
3. Use TypedArrays (`Int8Array`, `Float32Array`) for numerical computation
4. Avoid sparse arrays — `arr[9999] = 0` forces hash-table storage (much slower)
5. Don't mix types in arrays — `[1, "a", 2]` deoptimizes
6. Cache property lookups outside hot loops
7. Avoid exception throwing in perf-critical loops — use sentinel values
8. Minimize closures in hot paths — pass variables via function params instead
9. Use Array methods (`forEach`, `map`, `filter`, `reduce`) — internally optimized
10. Keep `build()` pure and declarative — no side effects, load data in `aboutToAppear()`
11. Use `HashMap` instead of `Record` for key-value operations — faster lookup/insert
12. Reduce multi-level indirect exports — prefer direct `export { foo } from './module'`
13. Use lazy import (`import lazy { Foo } from './heavy'`) for modules not needed at startup

## ArkTS strict-mode compiler errors (SDK 6.0.1)

### No object literals as types
```ts
// ❌
parseOutput(): { text: string; tags: string[] } { ... }
// ✅
interface ParsedOutput { text: string; tags: string[]; }
parseOutput(): ParsedOutput { ... }
```

### No `any` / `unknown`
```ts
const task = JSON.parse(rawStr) as AgentTask;  // ✅ cast immediately
```

### `navDestination` requires a `@Builder` function reference
```ts
// ❌ inline lambda
.navDestination((name, param) => { if (name==='X') MyPage() })
// ✅ top-level @Builder
@Builder function PageRouter(name: string) { if (name==='X') MyPage() }
Navigation(stack) { ... }.navDestination(PageRouter)
```

### `@Entry` build() root must be a container
Wrap in `Stack()`, `Column()`, or `Row()` — a custom component alone is not a container.

### `display.width` is pixels, not vp
```ts
function isTablet(): boolean {
  const dm = display.getDefaultDisplaySync();
  return (dm.width / dm.densityPixels) >= 840;
}
```

### All user_grant permissions need `reason` + `usedScene`
```json5
{
  "name": "ohos.permission.READ_MEDIA",
  "reason": "$string:permission_media_reason",
  "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
}
```
`INTERNET` is system_grant — no extra fields needed.

## Common gotchas

1. **Don't mix FA and Stage models** — FA is legacy; HarmonyOS NEXT only supports Stage.
2. **`this` in ArkUI callbacks** — arrow functions are required; regular `function () {}` loses `this`.
3. **`@State` on nested objects** — changes to nested props don't trigger updates; use `@Observed`/`@ObjectLink` or reassign the whole object.
4. **Array item updates** — replace the item (`arr[i] = newItem`) or use `@Observed` on the item class.
5. **Resource references** — use `$r('app.string.foo')`, `$r('app.media.icon')`, not string paths.
6. **`getContext(this)`** inside a component returns the `UIAbilityContext`; cast explicitly.
7. **Async in `build()`** is forbidden — load data in `aboutToAppear()` and store in `@State`.
8. **Permissions must be declared AND requested at runtime** for user-grant permissions.
9. **ohpm** is the package manager (similar to npm) — dependencies live in `oh-package.json5`.
10. **Preview on device** — DevEco Previewer doesn't fully simulate; always test on real HarmonyOS device or emulator.
11. **Navigation has no `hideSideBar`** — use `.hideBackButton(true)` instead.
12. **`promptAction.showToast()` is deprecated** — use `getUIContext().getPromptAction().showToast(...)` instead; wrap in try-catch for safety.
13. **Floating FAB button blocks last list item** — use `Navigation.menus()` for primary action buttons, or add bottom padding to List equal to FAB height + margin.
14. **Named callbacks for `on/off`** — anonymous functions can't be unregistered. Always store references:
    ```ts
    // BAD: can't off() an anonymous function
    session.on('stateChange', (state) => { ... });
    // GOOD: named reference
    const cb = (state: StateType) => { ... };
    session.on('stateChange', cb);
    session.off('stateChange', cb);
    ```
15. **Batch state mutations** — multiple `@State` changes trigger multiple re-renders. Accumulate in a temp variable, assign once:
    ```ts
    // BAD: 3 re-renders
    this.list.push(a); this.list.push(b); this.list.push(c);
    // GOOD: 1 re-render
    const tmp = [...this.list, a, b, c];
    this.list = tmp;
    ```
16. **State decorator selection priority** — `@State+@Prop/@Link/@ObjectLink` (parent-child) > `@Provide+@Consume` (deep nesting) > `LocalStorage` (page-level) > `AppStorage` (global). Avoid `AppStorage` for frequently-changing data.

17. **Unit conversion** — `px2vp(px)` / `vp2px(vp)` via `this.getUIContext().px2vp(value)`. Screen density: `display.getDefaultDisplaySync().densityPixels`.
18. **Keep screen on** — `win.setWindowKeepScreenOn(true)` during video playback / navigation; reset on pause.

## API 21 (SDK 6.0.1) — confirmed compile errors and fixes

These errors were verified against a real Mate 70 Pro build. All entries below caused `ArkTS Compiler Error` at `assembleDevHqf`.

### `DataChangeListener` requires both new and deprecated method names

In API 21, any class that `implements DataChangeListener` must include ALL of:
```ts
// New names (current)
onDataReloaded(): void
onDataAdd(index: number): void
onDataDelete(index: number): void
onDataChange(index: number): void
onDataMove(from: number, to: number): void
// Deprecated aliases — still required by the interface in API 21
onDataAdded(index: number): void
onDataDeleted(index: number): void
onDataChanged(index: number): void
onDataMoved(from: number, to: number): void
onDatasetChange(dataOperations: DataOperation[]): void
```
This applies to every class including test stubs (`NoopListener`, etc).

### `notificationManager.addSlot()` — pass `SlotType`, not `NotificationSlot`

```ts
// ❌ API 9 style
await notificationManager.addSlot({ type: SlotType.SOCIAL_COMMUNICATION, desc: '...' })
// ✅ API 12+ style
await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
```

Also: always annotate the constant explicitly to prevent type narrowing to literal type:
```ts
// ❌ infers as SlotType.SOCIAL_COMMUNICATION — not assignable to SlotType
const SLOT_ID = notificationManager.SlotType.SOCIAL_COMMUNICATION
// ✅
const SLOT_ID: notificationManager.SlotType = notificationManager.SlotType.SOCIAL_COMMUNICATION
```

### `NotificationRequest.slotType` — incompatible `SlotType` modules

`NotificationRequest.slotType` is typed as `@ohos.notification.SlotType` (old module), while `notificationManager.SlotType` is from `@ohos.notificationManager` (new module). They are nominally different types — assigning new to old is a compile error. **Just omit `slotType`** (it is optional):
```ts
const request: notificationManager.NotificationRequest = {
  id: NOTIFICATION_ID,
  // slotType omitted — routes to the slot created by addSlot() automatically
  content: { ... }
}
```
`NotificationSlotLevel` does not exist on `notificationManager` in API 21 — remove any usage.

### `Permissions` type — `@ohos.bundleManager` not importable

`import type { Permissions } from '@ohos.bundleManager'` fails with "Cannot find module". `bundleManager` is accessible only via `@kit.AbilityKit`. Workaround: declare a local subset type whose values are all valid `Permissions` literals:
```ts
// ✅ subtype of Permissions — assignable to the SDK's Permissions parameter
type AppPermission = 'ohos.permission.CAMERA' | 'ohos.permission.APPROXIMATELY_LOCATION'

async function hasPermission(name: AppPermission): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager()
  const bundleInfo = await bundleManager.getBundleInfoForSelf(
    bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
  const status = atManager.checkAccessTokenSync(bundleInfo.appInfo.accessTokenId, name)
  return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}
```

### `requestPermissionsFromUser` — `void & Promise` overload intersection

The function has both a callback overload (returns `void`) and a Promise overload (returns `Promise<PermissionRequestResult>`). TypeScript sometimes intersects them to `void & Promise<…>`, causing `.authResults` to not exist. Additionally, `abilityAccessCtrl.PermissionRequestResult` is **not exported** from the namespace in API 21.

Fix: declare the result interface locally and cast:
```ts
interface PermResult {
  authResults: abilityAccessCtrl.GrantStatus[]
}

async function requestPermission(ctx: common.UIAbilityContext, name: AppPermission): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager()
  const result = await (atManager.requestPermissionsFromUser(ctx, [name]) as Promise<PermResult>)
  return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
}
```

### `getContext(this)` is deprecated

Replace in all component methods:
```ts
// ❌
const ctx = getContext(this) as common.UIAbilityContext
// ✅
const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
```
Module-level (non-component) functions must receive `ctx` as a parameter instead.
