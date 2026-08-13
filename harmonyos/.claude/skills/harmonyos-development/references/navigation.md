# Navigation Reference

Use this reference when the user asks about routing, page stacks, Navigation, NavDestination, NavPathStack, or replacing legacy router patterns.

## Defaults

- Prefer Navigation and NavPathStack for new HarmonyOS NEXT applications.
- Keep route names, parameters, and page registration explicit.
- Mention SDK version assumptions when using newer Navigation behavior.

## Guidance

- Use a single source of truth for the navigation stack when possible.
- Avoid mixing unrelated routing approaches in one page tree.
- Keep page parameters typed and serializable.
- For nested navigation, explain stack ownership and back behavior clearly.

## Review checklist

- The navigation stack is owned by the right component or page shell.
- Back navigation is predictable.
- Parameters are typed and validated.
- Destination pages have clear names and lifecycle assumptions.

---

## Detailed reference

### Navigation (recommended: Navigation component, not Router)

```ts
@Entry @Component struct App {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  build() {
    Navigation(this.pathStack) {
      Button('Go').onClick(() => this.pathStack.pushPath({ name: 'Detail', param: 42 }))
    }
    .navDestination((name: string, param: Object) => {
      if (name === 'Detail') Detail({ id: param as number })
    })
  }
}
```

The older `router` module (`@ohos.router`) still works but **is being phased out** — `Navigation` + `NavPathStack` is the official replacement since API 12+. Huawei publishes a [transition guide](https://device.harmonyos.com/en/docs/apiref/harmonyos-guides/arkts-router-to-navigation) for migrating from router to Navigation. For new projects, always use Navigation; for legacy code, migrate when convenient.

**NavPathStack full API:**
```ts
// Push
pathStack.pushPath({ name: 'Page', param: data });
pathStack.pushPathByName('Page', data);
pathStack.pushPathByName('Page', data, (popInfo) => {
  console.info('Pop result: ' + JSON.stringify(popInfo.result));
});

// Pop, Replace, Remove
pathStack.pop();
pathStack.replacePath({ name: 'Page', param: data });
pathStack.removeIndex(0);
pathStack.movePageToTop('Page');

// Query
pathStack.getParamByIndex(index);
pathStack.getParamByName('Page');
pathStack.getAllPathName();
pathStack.size();
```

**Route interception:**
```ts
pathStack.setInterception({
  willShow: (from, to, operation) => { /* validate/redirect */ },
  didShow: (from, to, operation) => { /* analytics */ }
});
```

Display modes: **Stack** (single column), **Split** (two columns), **Auto** (adaptive, 600vp threshold).
