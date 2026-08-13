# Multi-device and Foldable Adaptation

## Multi-device / foldable screen adaptation (API 21)

### Breakpoint detection

```ts
import { display } from '@kit.ArkUI'

export const BP_SM = 'sm'   // < 600 vp  — phone portrait
export const BP_MD = 'md'   // < 840 vp  — phone landscape / small tablet
export const BP_LG = 'lg'   // >= 840 vp — large tablet / foldable unfolded

export function getBreakpoint(): string {
  try {
    const d = display.getDefaultDisplaySync()
    const widthVp = d.width / d.densityPixels
    if (widthVp < 600) return BP_SM
    if (widthVp < 840) return BP_MD
    return BP_LG
  } catch (e) {
    return BP_SM
  }
}
```

### Foldable screen — listen for fold/unfold events

```ts
// display.on callback receives (id: number) — NOT empty params
private displayListener: (id: number) => void = (_id: number) => {
  this.breakpoint = getBreakpoint()
}

aboutToAppear(): void {
  this.breakpoint = getBreakpoint()
  display.on('change', this.displayListener)
}

aboutToDisappear(): void {
  display.off('change', this.displayListener)
}
```

### Responsive layout switching (if/else, not .visibility)

Always use `if/else` to switch between phone and tablet layouts. `.visibility(Visibility.None)` hides but still lays out — wastes resources and can cause measurement bugs.

```ts
if (this.breakpoint === BP_SM) {
  // Phone: single-column List + LazyForEach
  List({ space: 8 }) { LazyForEach(...) }
} else {
  // Tablet/foldable: GridRow with responsive columns
  Scroll() {
    GridRow({
      columns: { sm: 1, md: 2, lg: 3 },
      gutter: { x: 12, y: 12 },
      breakpoints: { value: ['600vp', '840vp'] }
    }) {
      ForEach(this.gridItems, (item) => { GridCol() { MyCard({ record: item }) } })
    }
  }
}
```

### `GridRow`/`GridCol` does not support `LazyForEach`

`GridRow`/`GridCol` is a responsive layout container, not a lazy loader. Use `ForEach` inside it. To keep the grid reactive to data changes, maintain a `@State gridItems: T[]` that is updated via a `DataChangeListener`:

```ts
class GridRefreshListener implements DataChangeListener {
  private updateFn: () => void
  constructor(fn: () => void) { this.updateFn = fn }
  // Must implement ALL methods — see API 21 DataChangeListener note above
  onDataReloaded(): void { this.updateFn() }
  onDataAdd(_i: number): void { this.updateFn() }
  onDataAdded(_i: number): void { this.updateFn() }
  // ... all other methods
  onDataChange(_i: number): void { /* @ObjectLink handles per-item updates */ }
  onDataChanged(_i: number): void { }
}

// In @Entry @Component:
@State gridItems: MyRecord[] = []
private gridListener = new GridRefreshListener(() => {
  this.gridItems = [...this.dataSource.getAllData()]
})
aboutToAppear() { this.dataSource.registerDataChangeListener(this.gridListener) }
aboutToDisappear() { this.dataSource.unregisterDataChangeListener(this.gridListener) }
```

### Share breakpoint via `@Provide`/`@Consume`

Declare in the `@Entry` root, consume in any `NavDestination` child:
```ts
// Root
@Provide('breakpoint') breakpoint: string = BP_SM

// Detail page (NavDestination)
@Consume('breakpoint') breakpoint: string
```
`@Provide`/`@Consume` works across `Navigation`/`NavDestination` because they are in the same component subtree.
