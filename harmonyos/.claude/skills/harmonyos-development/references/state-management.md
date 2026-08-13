# ArkUI State Management

Use this file for ArkUI state decorators and reactive rendering decisions.

## Decision guide

| Need | Prefer |
|---|---|
| Local primitive state | State decorator |
| Parent to child one-way value | Prop decorator |
| Parent-child two-way binding | Link decorator |
| Object item passed into child row component | ObjectLink with Observed class |
| Cross-level dependency injection | Provide and Consume decorators |
| App-level or storage-backed state | StorageLink or StorageProp |
| Page-level local storage | LocalStorageLink or LocalStorageProp |

## Rules

- Do not use ObjectLink without an Observed class.
- For list rows, prefer stable object models and stable keys.
- Explain whether changing an array element property triggers refresh in the chosen pattern.
- Avoid React hook analogies unless the user explicitly asks for comparison.

## Review checklist

- Correct decorator for ownership direction.
- No unnecessary global state.
- No accidental object identity loss.
- List updates have stable keys and predictable refresh behavior.

---

## Detailed reference

### State-management decorators

| Decorator | Scope | Purpose |
|---|---|---|
| `@State` | within component | Owned mutable state; triggers re-render |
| `@Prop` | parent → child | One-way copy (child has local copy) |
| `@Link` | parent ↔ child | Two-way binding (use `$var` to pass) |
| `@Provide` / `@Consume` | ancestor → descendant | Cross-level implicit binding by key |
| `@Observed` (class) + `@ObjectLink` (prop) | class instances | Observe changes to class properties |
| `@Watch('handler')` | any of above | Callback on value change |
| `@StorageLink` / `@StorageProp` | app-wide `AppStorage` | Global reactive state |
| `@LocalStorageLink` / `@LocalStorageProp` | page-scoped | Scoped reactive state |

**Passing `@Link`:**
```ts
@Entry @Component struct Parent {
  @State val: number = 0;
  build() { Child({ val: $val }) }     // $ prefix for @Link
}
@Component struct Child {
  @Link val: number;
  build() { Button(`${this.val}`).onClick(() => this.val++) }
}
```

**Observing class objects:**
```ts
@Observed class Task { constructor(public title: string, public done: boolean) {} }

@Component struct TaskRow {
  @ObjectLink task: Task;            // re-renders when task.title/done changes
  build() { Text(this.task.title) }
}
```

Arrays of `@Observed` instances require `@ObjectLink` in the row component — parent `@State tasks: Task[]` only reacts to array mutations (push/splice/reassign), not per-item changes.

**State management performance rules (from official docs):**
- Minimize state scope: only `@State` variables that directly affect UI
- `@Prop` creates **deep copy** on every update — for large objects, prefer `@Link` (by reference) or `@ObjectLink`
- `@Link` is preferred for inter-component communication — avoids unnecessary re-renders
- `@Observed` + `@ObjectLink` for nested objects — fine-grained property observation
- `@ObjectLink` is **READ-ONLY** — cannot reassign whole object (`this.task = new Task()` breaks binding)
- Avoid `@StorageLink` for frequently-changing data — global state changes propagate to ALL subscribers
- **Observation depth (V1):** `@State`/`@Prop`/`@Link` observe ONLY first-level properties. Nested changes are NOT detected. Array: only push/splice/reassign/length, NOT item mutations.

### V2 state decorators (API 12+, **stable since API 23** — recommended for new code)

> V2 decorators have **graduated from experimental to stable** as of HarmonyOS 6.1 (API 23). Official recommendation: migrate to V2 for new projects.

| V1 | V2 replacement | Change |
|---|---|---|
| `@Component` | `@ComponentV2` | Clearer semantics |
| `@State` | `@Local` | Cannot be initialized externally — internal state only |
| `@Prop` | `@Param` + `@Once` | Read-only inputs; `@Once` for one-time init |
| `@Link` | `@Param` + `@Event` | Two-way: input via `@Param`, output via callback `@Event` |
| `@Observed` + `@ObjectLink` | `@ObservedV2` + `@Trace` | **Deep observation** across multiple nested levels |
| `@Watch` | `@Monitor('prop')` | More precise deep listener |
| `AppStorage` | `AppStorageV2` | Unified with `@ObservedV2` + `@Trace` |
| (none) | `PersistenceV2` | Persistent storage with V2 observation; auto-saved to disk |
| `@Provide` / `@Consume` | `@Provider()` / `@Consumer()` | Renamed; same semantics |

```ts
@ObservedV2
class UserInfo {
  @Trace name: string = '';    // changes to this trigger UI refresh
  @Trace age: number = 0;     // changes to this trigger UI refresh
  address: string = '';        // NO @Trace → changes do NOT trigger refresh
}
```
Rules: `@ObservedV2` and `@Trace` must be used together (either alone has no effect). Only `@Trace`-decorated properties participate in UI rendering.

**AppStorageV2 — global reactive state:**
```ts
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
class UserState { @Trace name: string = 'Guest'; }

// Connect (creates if not exists)
const user = AppStorageV2.connect(UserState, 'user', () => new UserState())!;

// In component
@ComponentV2
struct Header {
  user: UserState = AppStorageV2.connect(UserState, 'user')!;
  build() { Text(this.user.name) }
}
```

**PersistenceV2 — auto-persisted state (survives app restart):**
```ts
import { PersistenceV2, Type } from '@kit.ArkUI';

@ObservedV2
class Settings {
  @Trace @Type(String) theme: string = 'light';
  @Trace @Type(Number) fontSize: number = 14;
}

// Connect — auto-loads from disk if exists, writes on change
const settings = PersistenceV2.connect(Settings, 'app_settings', () => new Settings())!;

// Optional: error/success callback
PersistenceV2.notifyOnError((key, reason, msg) => { console.error(reason, msg); });
```
> `@Type` decorator is required for PersistenceV2 to serialize correctly.

### StateStore — global state management (2026, officially recommended for mid-large apps)

Separates state logic from UI components entirely. Works with `@ObservedV2` + `@Trace`.

```ts
import { StateStore } from '@kit.ArkUI';

@ObservedV2
class CounterStore {
  @Trace count: number = 0;

  increment(): void {
    this.count++;
  }
}

// Create global store (do this once, e.g. in EntryAbility or top-level)
const counterStore = StateStore.createStore(new CounterStore());

// In any component — read state
@Entry
@Component
struct CounterPage {
  build() {
    Column() {
      Text(`Count: ${counterStore.getState().count}`)
      Button('Add').onClick(() => {
        counterStore.getState().increment();
      })
    }
  }
}
```

**When to use:** Multiple pages/components share the same state; state logic is complex; need thread-safe updates (TaskPool workers can safely update StateStore).

Docs: https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-global-state-management-state-store
