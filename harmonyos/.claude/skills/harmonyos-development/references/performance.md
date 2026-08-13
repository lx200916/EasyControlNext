# HarmonyOS Performance Reference

Use this file for ArkUI performance, large lists, rendering, memory, and startup reviews.

## Checklist

- Prefer `LazyForEach` for large or dynamic lists.
- Use stable keys for list items.
- Avoid excessive nested layout containers.
- Avoid heavy work in render/build functions.
- Move IO, parsing, and expensive computation out of UI rendering.
- Use component reuse only when it matches the target SDK and the page pattern.
- Check image size, decode cost, cache policy, and lazy loading.
- Check ability lifecycle side effects and resource cleanup.

## Debug questions

Ask for:

- target SDK
- device model or emulator
- page route
- reproduction steps
- HiLog / AppFreeze / performance report
- screenshot or screen recording when UI jank is visual

## Memory-leak diagnostics

Use the smallest tool that can identify the suspected leak:

| Suspected area | Prefer |
|---|---|
| ArkTS component or lifecycle object | `@ohos.hiviewdfx.jsLeakWatcher` during development |
| ArkTS heap retention path | DevEco Studio JS Heap / heap snapshot |
| Native allocation or free error | HWASan / AddrSanitizer in development or test |
| Runtime freeze or resource pressure | AppFreeze, HiAppEvent, HiLog, DevEco Testing |

`jsLeakWatcher` periodically checks whether registered lifecycle objects remain alive after they should be collectible. It is intended primarily for development. If production diagnosis is unavoidable, use a small gray-release population rather than enabling it permanently for all users.

Do not claim a leak is fixed from one heap snapshot. Reproduce the lifecycle, force or wait for collection as appropriate, compare retained objects, fix the ownership path, and repeat the same scenario.

Official reference: https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-stability-memleak-detection-overview

## Output rule

Give prioritized fixes: quick wins first, then structural changes, then SDK/tooling checks.

---

## Detailed reference

## ArkCompiler — runtime details

- **AOT mode** — static type info generates optimized native machine code; no JIT warm-up
- **LiteActor concurrency** — Actor model with isolated memory per thread; communication via message passing

### TaskPool vs Worker

| Feature | TaskPool | Worker |
|---|---|---|
| Thread management | Automatic (create/reuse/destroy) | Manual lifecycle |
| Max threads | Auto-scaled to physical cores | Max 64 per process |
| Task duration limit | **3 minutes** (excluding async I/O) | Unlimited |
| Priority | HIGH / MEDIUM / LOW / IDLE | API 18+ only |
| Cancellation | Supported | Not supported |
| Thread reuse | Yes | No |
| Task groups | Yes | No |
| Delayed/periodic | Yes | No |

**Use Worker when:** tasks exceed 3 minutes, need persistent state, or strongly associated synchronous tasks.

### @Concurrent rules
- **Required** on all TaskPool functions, **only in `.ets` files**
- Allowed: regular functions, async functions
- **Prohibited:** arrow functions, class methods, anonymous functions, generator functions
- **No closure variables** — cannot reference outer scope; only local vars, params, and imports
- Cannot call other same-file functions (closure violation) — must import them

```ts
import { taskpool } from '@kit.ArkTS';

@Concurrent
function heavyCalc(n: number): number { return n * n; }

const result = await taskpool.execute(heavyCalc, 42);

// With priority
const task = new taskpool.Task(heavyCalc, 42);
await taskpool.execute(task, taskpool.Priority.HIGH);

// Delayed and periodic
taskpool.executeDelayed(heavyCalc, 2000, 42);      // after 2s
taskpool.executePeriodically(heavyCalc, 5000, 42);  // every 5s

// TaskGroup — execute multiple tasks as a group
const group = new taskpool.TaskGroup();
group.addTask(heavyCalc, 10);
group.addTask(heavyCalc, 20);
group.addTask(heavyCalc, 30);
const results = await taskpool.execute(group);  // returns array of results
```

**Long-time tasks:** async code (Promise/IO) in TaskPool has NO time limit (only CPU-bound sync code is capped at 3 minutes). HarmonyOS 6.0 officially supports long-running async tasks in TaskPool.

### @Sendable — shared-heap reference passing
Objects on SharedHeap (process-level, all threads can access) — **100x faster** than serialization for 1MB data.

```ts
@Sendable
class SharedData {
  value: number = 0;  // must be explicitly initialized
}
```

**Constraints:** Can only inherit from Sendable classes. Property types limited to: primitives, Sendable classes, `@arkts.collections` containers. Cannot add/delete properties at runtime. No computed properties. No `#` private (use `private` keyword).

### Worker pattern
```ts
// Main thread
const worker = new worker.ThreadWorker('entry/ets/workers/myWorker.ets');
worker.postMessage({ type: 'compute', data: payload });
worker.onmessage = (e) => { /* handle result */ };
worker.terminate();

// Worker thread (myWorker.ets)
const workerPort = worker.workerPort;
workerPort.onmessage = (e) => {
  const result = processData(e.data);
  workerPort.postMessage(result);
};
```

**Both TaskPool and Worker:** Cannot access AppStorage or UI libraries from worker threads. Different thread contexts prevent context object sharing.

## Cold start optimization

HarmonyOS measures cold start as: **app launch → first frame rendered**. Target: < 1000ms on mid-range device.

### Lazy-import (`import()`)

```ts
// ❌ Eager — all modules parsed at startup even if unused
import { HeavyModule } from '../utils/HeavyModule';

// ✓ Lazy — parsed only when first used
let heavyModule: typeof import('../utils/HeavyModule') | null = null;

async function useHeavy() {
  if (!heavyModule) {
    heavyModule = await import('../utils/HeavyModule');
  }
  heavyModule.HeavyModule.doWork();
}
```

### Network requests — defer until after first frame

```ts
// EntryAbility.ets
onWindowStageCreate(windowStage: window.WindowStage) {
  windowStage.loadContent('pages/Index', (err) => {
    if (!err) {
      // First frame committed — now safe to start network
      AppStartupData.prefetch();
    }
  });
}
```

### Other cold start rules

- Avoid heavy synchronous work in `onCreate()` / `onWindowStageCreate()` — use TaskPool for >10ms tasks
- Minimize global singleton construction at module load time
- Use `@Reusable` on list item components to avoid remeasure/relayout on first display
- Avoid `hilog` calls inside tight rendering loops (I/O cost)
- Profile with DevEco Profiler → **Launch** task to see exact frame timeline

## Memory optimization

### `onMemoryLevel` callback

```ts
// AbilityStage.ets or UIAbility.ets
onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
    // Release non-essential caches immediately
    ImageCache.instance.clear();
    DataCache.instance.trimToSize(10);
  } else if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
    DataCache.instance.trimToSize(50);
  }
}
```

### LRUCache — bounded image / data cache

```ts
import { util } from '@kit.ArkTS';

class ImageCache {
  static instance = new ImageCache();
  private lru = new util.LRUCache<string, PixelMap>(50);  // max 50 entries

  put(key: string, pm: PixelMap) { this.lru.put(key, pm); }
  get(key: string): PixelMap | undefined { return this.lru.get(key); }
  clear() { this.lru.clear(); }
  trimToSize(n: number) {
    while (this.lru.length > n) {
      this.lru.afterRemoval(false, this.lru.keys()[0], undefined, undefined);
    }
  }
}
```

### Purgeable memory (large bitmaps)

```ts
import { image } from '@kit.ImageKit';

// Create PixelMap as purgeable — OS can reclaim when memory is tight,
// and will regenerate it from the source on next access
const pixelMap = await image.createPixelMap(buffer, {
  size: { width: 1920, height: 1080 },
  editable: false
});
// No extra API needed — PixelMap is automatically purgeable when editable=false
// and created from a decodable source (file path or buffer)
```

### General memory rules

- **Unregister listeners** in `aboutToDisappear()` / `onBackground()` to prevent leaks
- **Avoid capturing `this`** in long-lived closures (keeps component alive)
- **Reuse PixelMap objects** instead of recreating them for repeated renders
- Use `image.ImageSource` + lazy decode for thumbnails — don't decode full resolution
- TaskPool threads share no heap — `@Sendable` objects avoid copy but transfer ownership
