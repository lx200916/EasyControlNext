# Testing, UiTest, and Stability

## Stability — crash types and error handling

| Type | Description |
|---|---|
| **JS_ERROR** | ArkTS/JS runtime exceptions (most common) — `TypeError: Cannot read property 'x' of undefined` |
| **CPP_CRASH** | Native C/C++ crash (SIGSEGV, SIGABRT) |
| **APP_FREEZE** | Main thread blocked >6s (ANR equivalent). Root causes: thread locks (57%), system resources (14%), heavy main-thread work (9%) |
| **OOM** | Out-of-memory kill |

**Global error handler:**
```ts
import { errorManager } from '@kit.AbilityKit';

const observer: errorManager.ErrorObserver = {
  onUnhandledException(errMsg: string): void {
    console.error('Uncaught: ' + errMsg);
  },
  onException?(errObject: Error): void {  // API 10+
    console.error(errObject.name + ': ' + errObject.message);
  }
};
const observerId = errorManager.on('error', observer);
```

**Crash event subscription (HiAppEvent):**
```ts
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';

hiAppEvent.addWatcher({
  name: "crashWatcher",
  appEventFilters: [{
    domain: hiAppEvent.domain.OS,
    names: [hiAppEvent.event.APP_CRASH]
  }],
  onReceive: (domain, appEventGroups) => { /* process crash */ }
});
```

## Testing — arkxtest framework

Package: `@ohos/hypium` (Mocha-style). Three sub-frameworks: **JsUnit** (unit), **UiTest** (UI automation), **PerfTest** (performance).

### JsUnit

```ts
import { describe, it, expect, beforeAll, beforeEach, afterEach, afterAll } from '@ohos/hypium';

export default function abilityTest() {
  describe('MyTestSuite', () => {
    beforeAll(() => { /* once before all */ });
    beforeEach(() => { /* before each */ });
    afterEach(() => { /* after each */ });
    afterAll(() => { /* once after all */ });

    it('sync_test', 0, () => {
      expect(1 + 1).assertEqual(2);
    });

    it('async_test', 0, async (done: Function) => {
      let result = await someAsyncOp();
      expect(result).assertContain('expected');
      done();
    });
  });
}
```

**Key assertions:** `assertEqual(v)` · `assertContain(v)` · `assertTrue()` · `assertFalse()` · `assertNull()` · `assertUndefined()` · `assertNaN()` · `assertInstanceOf(type)` · `assertThrowError(fn)` · `assertDeepEquals(v)` · `assertClose(v, tolerance)` · `assertLarger(v)` · `assertLess(v)` · `not()` (negation) · `assertPromiseIsResolved()` · `assertPromiseIsRejected()`

Test files in `entry/src/ohosTest/ets/test/`. For UI automation, see the **UiTest** section below.

**仓颉 (Cangjie)** is Huawei's new language (beta) — use ArkTS for all production apps until Cangjie is stable.

## UiTest — common patterns (arkxtest)

```ts
import { Driver, ON, Component } from '@ohos.UiTest'
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry'

const DELEGATOR = AbilityDelegatorRegistry.getAbilityDelegator()

// Launch app before tests
beforeAll(async (done: Function) => {
  await DELEGATOR.startAbility({ bundleName: 'com.example.app', abilityName: 'EntryAbility' })
  await new Promise(r => setTimeout(r, 2000))  // wait for UI to render
  done()
})

it('example', 0, async (done: Function) => {
  const driver = Driver.create()
  
  // Find by text / type / content description
  const btn = await driver.findComponent(ON.text('发布'))
  const input = await driver.findComponent(ON.type('TextInput'))
  const items = await driver.findComponents(ON.type('SymbolGlyph'))
  
  // Actions — ALL must be awaited
  await btn.click()
  await input.inputText('hello')
  
  // Wait after state-changing actions
  await new Promise(r => setTimeout(r, 800))
  
  // Component refs become stale after state changes — re-find
  const btnAfter = await driver.findComponent(ON.text('发布'))
  
  // Get bounds for position-based selection
  const bounds = await btn.getBounds()  // { top, left, right, bottom }
  
  // Navigate back
  await driver.pressBack()
  
  done()
})
```

Key rules:
- Every UiTest API call inside `it()` must be `await`ed
- After any click/input that changes state, component references may be stale — always re-`findComponent`
- Tests only run on real device or emulator — **Previewer does not support UiTest**
- `Driver.create()` fresh per `it` block (don't share across tests)
- Use `sleep` / `setTimeout` after navigation to let the new page render before asserting
