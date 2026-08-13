# ArkUI Components Reference

Use this reference when the user asks about ArkUI layout, components, rendering, interaction, or page implementation.

## Defaults

- Prefer declarative ArkUI component examples in `.ets` files.
- Use HarmonyOS-native components and APIs instead of React, DOM, Android View, or Jetpack Compose patterns.
- State the target SDK assumption when behavior depends on SDK version.

## Component guidance

| Need | Prefer |
|---|---|
| Vertical layout | `Column` |
| Horizontal layout | `Row` |
| Overlay / layered layout | `Stack` |
| Flexible wrapping layout | `Flex` |
| Large lists | `List` + `LazyForEach` |
| Grid content | `Grid` / `GridItem` |
| Layout that responds to its containing component | `ContainerReader` container breakpoints |
| Paged tabs | `Tabs` / `TabContent` |
| Swipe carousel | `Swiper` |
| Navigation shell | `Navigation` / `NavDestination` |

## Review checklist

- Keep layout nesting reasonable.
- Avoid heavy computation inside `build()`.
- Use stable keys for dynamic list rendering.
- Keep component state ownership clear.
- Include permission, routing, or module configuration when the component depends on it.

## Container-responsive layout

Use `ContainerReader` when a reusable component must change layout according to its own container instead of the application window. This is more precise than a window breakpoint for sidebars, split views, nested panes, and reusable cards.

Do not replace `ContainerReader` with a one-time window-width query. Keep the breakpoint decision attached to the container so it updates when the parent layout changes.

## Global component reuse

API 26 documentation adds centralized global reuse pools for `@Reusable` and `@ReusableV2` components. Use them only for components whose lifecycle and state-reset behavior are designed for reuse:

- release heavy resources in the recycle lifecycle;
- reset transient state before reused content becomes visible;
- keep reuse identifiers stable and compatible with the target SDK;
- profile first, because reuse adds lifecycle complexity and is not automatically faster for small pages.

Official update summary: https://developer.huawei.com/consumer/cn/monthly/202606

---

## Detailed reference

## ArkUI — declarative UI

### Custom component basics

```ts
@Entry                      // marks route/page entry
@Component
struct Index {
  @State count: number = 0;

  build() {
    Column({ space: 12 }) {
      Text(`Count: ${this.count}`)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
      Button('Increment')
        .onClick(() => { this.count++; })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
```

### Component lifecycle callbacks

**All `@Component`:**

| Callback | When | Notes |
|---|---|---|
| `aboutToAppear()` | After created, BEFORE `build()` | Can change state here; changes apply in first `build()` |
| `onDidBuild()` | After `build()` completes | Do NOT change state or call `animateTo()`. API 12+ |
| `aboutToDisappear()` | Before destruction | Do NOT change state (especially `@Link`). No async/await |
| `aboutToReuse(params)` | Reusable component re-added from cache | Update state with new params. API 10+ |
| `aboutToRecycle()` | Component moving to reuse cache | Release heavy resources. API 10+ |

**Only `@Entry`:**

| Callback | When |
|---|---|
| `onPageShow()` | Each time page is displayed |
| `onPageHide()` | Each time page is hidden |
| `onBackPress(): boolean` | User taps Back. Return `true` to override default |

**Execution order (cold start):**
`Parent aboutToAppear → Parent build → Parent onDidBuild → Child aboutToAppear → Child build → Child onDidBuild → onPageShow`

### Layout containers

| Container | When to use | Performance |
|---|---|---|
| `Column` / `Row` | Linear arrangement | **Best** — single-pass layout |
| `Stack` | Overlapping / stacking | Good |
| `Flex` | Items need stretch/shrink | **Slower** — extra pass for flexGrow/flexShrink |
| `RelativeContainer` | Complex layouts, avoid deep nesting | Good — flat structure |
| `GridRow` / `GridCol` | Responsive multi-device grids | Good |
| `List` | Scrollable list with recycling | Best for long lists (with `LazyForEach`) |

**Column/Row alignment:**
- Main axis: `justifyContent(FlexAlign.Start | .Center | .End | .SpaceBetween | .SpaceAround | .SpaceEvenly)`
- Cross axis: Column → `alignItems(HorizontalAlign.Start | .Center | .End)`, Row → `alignItems(VerticalAlign.Top | .Center | .Bottom)`

**Stack:** `alignContent` takes 9 positions (TopStart, Top, TopEnd, Start, Center, End, BottomStart, Bottom, BottomEnd). `zIndex` controls layer order.

**Flex vs Column/Row:** Flex requires re-layout for `flexShrink`/`flexGrow`. Always prefer `Column`/`Row` when you don't need flex behavior.

**RelativeContainer:** Use `__container__` as anchor ID for the container itself. Each child needs `.id()`. Set `.alignRules({ top: { anchor: 'id', align: VerticalAlign.Bottom } })`.

**Blank():** Fills remaining space in Row/Column — use for "label ... value" layouts: `Row() { Text('Name'); Blank(); Text('Value') }`.

**displayPriority:** Lower-priority children auto-hide when container shrinks. `Row() { A().displayPriority(1); B().displayPriority(3); C().displayPriority(1) }` — A and C hide first.

**layoutWeight:** Proportional sizing — `Row() { Column().layoutWeight(1); Column().layoutWeight(2) }` gives 1:2 ratio.

**AttributeModifier** — reusable style object:
```ts
class PrimaryButtonModifier implements AttributeModifier<ButtonAttribute> {
  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.width('100%').height(48).fontSize(16).fontColor(Color.White).backgroundColor('#007DFF');
  }
  applyPressedAttribute(instance: ButtonAttribute): void {
    instance.backgroundColor('#0056B3');
  }
}
// Usage:
Button('Submit').attributeModifier(new PrimaryButtonModifier())
```

### Performance-critical patterns

**`LazyForEach` for large lists** (only renders visible items):
```ts
class MyDataSource implements IDataSource {
  private data: string[] = []
  totalCount(): number { return this.data.length }
  getData(index: number): string { return this.data[index] }
  registerDataChangeListener(listener: DataChangeListener): void { /* ... */ }
  unregisterDataChangeListener(listener: DataChangeListener): void { /* ... */ }
}

List() {
  LazyForEach(this.dataSource, (item: string, index: number) => {
    ListItem() { Text(item) }
  }, (item: string) => item)  // key generator — MUST produce unique keys
}
.cachedCount(5)  // preload 5 items off-screen
```

**`@Reusable` components** (69% faster component creation):
```ts
@Reusable
@Component
struct MyListItem {
  @State message: Message = new Message('default')

  aboutToReuse(params: Record<string, ESObject>) {
    this.message = params.message as Message
  }
  aboutToRecycle() { /* release heavy resources */ }
  build() { Text(this.message.value) }
}
```
Rules: only works within same parent; don't nest `@Reusable` inside `@Reusable`; combine with `LazyForEach`.

**Layout performance rules:**
- Max 3 levels of nesting — each level adds layout cost
- Use `if/else` over `.visibility()` — hidden components still participate in layout
- Use `RelativeContainer` to flatten deep Row/Column/Flex hierarchies (documented 26% improvement)
- Set explicit dimensions on `List` inside `Scroll` — without them ALL children load at once
- Avoid `@StorageLink` for frequently-changing data — propagates to all subscribers

**onVisibleAreaChange** — trigger logic when component enters/leaves viewport:
```ts
Image(item.url)
  .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
    if (isVisible && currentRatio >= 1.0) { this.loadHighRes(); }    // fully visible
    if (!isVisible) { this.releaseImage(); }                          // off screen
  })
```
Use cases: lazy image loading, video auto-play/pause on scroll, exposure analytics.

### Animation

**Explicit animation (`animateTo`)** — state changes in closure animate:
```ts
this.getUIContext()?.animateTo({
  duration: 300,
  curve: Curve.EaseOut,
  onFinish: () => { console.info('done') }
}, () => {
  this.width = 200  // this change animates
})
```

**Property animation (`.animation()`)** — implicit, applied to preceding attributes:
```ts
Text('Hello')
  .width(this.myWidth)
  .animation({ duration: 500, curve: Curve.EaseIn })
```

**Curve values:** `Curve.Linear | .Ease | .EaseIn | .EaseOut | .EaseInOut | .FastOutSlowIn | .Friction | .Sharp | .Smooth`

**Spring curves (string):** `'spring(velocity,mass,stiffness,damping)'`, `'springMotion(response,dampingFraction)'`, `'responsiveSpringMotion(response,dampingFraction)'`

**Shared element transition:**
```ts
// Bind same geometryTransition ID on source and target
Image($r('app.media.photo')).geometryTransition('picture')
// Wrap state change in animateTo
this.getUIContext()?.animateTo({ duration: 300 }, () => { this.isExpanded = !this.isExpanded })
```

**Keyframe animation (`keyframeAnimateTo`)** — multi-step sequences:
```ts
this.getUIContext()?.keyframeAnimateTo({ iterations: 2 }, [
  { duration: 100, event: () => { this.translateX = 10; } },
  { duration: 100, event: () => { this.translateX = -10; } },
  { duration: 100, event: () => { this.translateX = 0; } },
]);
```

**Animation performance tips:** Prefer transform properties (`scale`/`translate`/`rotate`/`opacity`) over layout properties (`width`/`height`/`margin`) — transforms skip re-layout.

### Tabs — bottom/top navigation

```ts
@Entry @Component
struct MainPage {
  @State currentIndex: number = 0;

  @Builder tabBuilder(index: number, title: string, icon: Resource) {
    Column() {
      SymbolGlyph(icon).fontSize(24)
        .fontColor([this.currentIndex === index ? '#007DFF' : '#99000000'])
      Text(title).fontSize(10).margin({ top: 4 })
        .fontColor(this.currentIndex === index ? '#007DFF' : '#99000000')
    }.justifyContent(FlexAlign.Center).height('100%').width('100%')
  }

  build() {
    Tabs({ barPosition: BarPosition.End }) {        // BarPosition.Start for top
      TabContent() { HomePage() }
        .tabBar(this.tabBuilder(0, 'Home', $r('sys.symbol.house')))
      TabContent() { MinePage() }
        .tabBar(this.tabBuilder(1, 'Me', $r('sys.symbol.person')))
    }
    .barHeight(56)
    .onChange((index) => { this.currentIndex = index; })
    .scrollable(false)                               // disable swipe between tabs
  }
}
```

Glass-blur tab bar: `.barOverlap(true).barBackgroundBlurStyle(BlurStyle.Thin)`.

### Swiper — carousel / banner

```ts
Swiper() {
  ForEach(this.banners, (item: BannerItem) => {
    Image(item.url).width('100%').height(180).borderRadius(12)
  })
}
.loop(true)
.autoPlay(true)
.interval(3000)
.indicator(new DotIndicator()
  .color('#33000000').selectedColor('#007DFF')
  .itemWidth(8).selectedItemWidth(16))
```

### WaterFlow — Pinterest-style layout

```ts
WaterFlow({ scroller: this.scroller }) {
  LazyForEach(this.dataSource, (item: CardItem) => {
    FlowItem() {
      Column() {
        Image(item.image).width('100%').borderRadius(8)
        Text(item.title).fontSize(14).padding(8)
      }
    }
  }, (item: CardItem) => item.id)
}
.columnsTemplate('1fr 1fr')       // 2 columns
.columnsGap(8)
.rowsGap(8)
.cachedCount(10)
```

### Grid — fixed grid layout

```ts
Grid() {
  ForEach(this.items, (item: GridItemData) => {
    GridItem() {
      Column() {
        Image(item.icon).width(40).height(40)
        Text(item.name).fontSize(12).margin({ top: 4 })
      }
    }
  })
}
.columnsTemplate('1fr 1fr 1fr 1fr')   // 4 columns
.rowsGap(12)
.columnsGap(12)
.height(200)
```

### TextInput / TextArea

```ts
TextInput({ placeholder: 'Enter username' })
  .type(InputType.Normal)                          // .Email, .Number, .Password, .PhoneNumber
  .maxLength(20)
  .onChange((value: string) => { this.username = value; })
  .onSubmit((enterKey: EnterKeyType) => { /* handle submit */ })

TextArea({ placeholder: 'Enter description', text: $$this.desc })
  .maxLength(200)
  .showCounter(true)                                // character count indicator
```

Two-way binding with `$$`: `TextInput({ text: $$this.value })` — no `onChange` needed.

### Router — basic page navigation

```ts
import { router } from '@kit.ArkUI';

// Push to new page (with params)
router.pushUrl({
  url: 'pages/Detail',
  params: { id: '123', title: 'Hello' }
});

// Get params on target page
const params = router.getParams() as Record<string, string>;

// Go back
router.back();

// Replace current page (no back stack)
router.replaceUrl({ url: 'pages/Login' });
```

> **Note**: For Navigation-based apps, prefer `NavPathStack.pushPath()` over Router.

### AlertDialog / Toast

```ts
// Alert dialog
AlertDialog.show({
  title: 'Confirm',
  message: 'Delete this item?',
  primaryButton: { value: 'Cancel', action: () => {} },
  secondaryButton: { value: 'Delete', fontColor: Color.Red,
    action: () => { this.deleteItem(); }
  },
});

// Toast
this.getUIContext().getPromptAction().showToast({
  message: 'Operation successful',
  duration: 2000,
});
```

### Common form components — quick reference

| Component | Key Props | Example |
|---|---|---|
| `Checkbox` | `select`, `onChange((val: boolean) => {})` | `Checkbox({ name: 'agree' }).select(this.agreed)` |
| `Toggle` | `type(ToggleType.Switch)`, `isOn`, `onChange` | `Toggle({ type: ToggleType.Switch, isOn: $$this.on })` |
| `Radio` | `value`, `group`, `checked`, `onChange` | `Radio({ value: 'male', group: 'gender' }).checked(true)` |
| `Select` | `options: SelectOption[]`, `selected`, `value`, `onSelect` | `Select([{value:'A'},{value:'B'}]).selected(0)` |
| `Slider` | `value`, `min`, `max`, `step`, `onChange` | `Slider({ value: $$this.val, min: 0, max: 100 })` |
| `DatePicker` | `start`, `end`, `selected`, `onChange` | `DatePicker({ selected: this.date }).onChange((v) => {})` |
| `TimePicker` | `selected`, `useMilitaryTime`, `onChange` | `TimePicker({ selected: this.time })` |
| `Search` | `value`, `placeholder`, `onSubmit`, `onChange` | `Search({ value: $$this.keyword, placeholder: 'Search' })` |
| `Progress` | `value`, `total`, `type(ProgressType.Linear)` | `Progress({ value: 60, total: 100 })` |
| `LoadingProgress` | — | `LoadingProgress().width(48).color('#007DFF')` |

### EventHub — UIAbility ↔ page communication

```ts
// In UIAbility — emit event
this.context.eventHub.emit('dataReady', { items: [...] });

// In page — subscribe
const context = getContext(this) as common.UIAbilityContext;
context.eventHub.on('dataReady', (data: Record<string, ESObject>) => {
  this.items = data.items;
});

// Unsubscribe
context.eventHub.off('dataReady');
```

### HarmonyOS 6.0 visual effects (沉浸光感视效 / 液态玻璃)

HarmonyOS 6.0 (API 23) introduces system-level "Immersive Light Perception" visual effects. Users enable via Settings → Desktop & Personalization → Immersive Light Effect (强/均衡/弱). Developers achieve similar effects through these ArkUI attributes:

**BlurStyle enum (API 9–11):**

| Name | Since | Level |
|---|---|---|
| `Thin` / `Regular` / `Thick` | API 9 | Material blur |
| `BACKGROUND_THIN` / `BACKGROUND_REGULAR` / `BACKGROUND_THICK` / `BACKGROUND_ULTRA_THICK` | API 10 | Depth-of-field (min→max) |
| `COMPONENT_ULTRA_THIN` / `COMPONENT_THIN` / `COMPONENT_REGULAR` / `COMPONENT_THICK` / `COMPONENT_ULTRA_THICK` | API 11 | Component-level material |
| `NONE` | API 10 | No blur |

**backgroundBlurStyle (API 9+):**
```ts
Column() { /* content */ }
  .backgroundBlurStyle(BlurStyle.Thin, {
    colorMode: ThemeColorMode.LIGHT,     // SYSTEM | LIGHT | DARK
    adaptiveColor: AdaptiveColor.DEFAULT, // DEFAULT | AVERAGE
    scale: 1.0                            // 0.0–1.0 (blur intensity)
  })
```

**foregroundBlurStyle (API 10+):**
```ts
Image($r('app.media.photo'))
  .foregroundBlurStyle(BlurStyle.Regular)
```

**backgroundEffect (API 11+) — fine-grained control:**
```ts
Column() { /* content */ }
  .backgroundEffect({
    radius: 20,          // blur radius
    saturation: 15,      // [0, 50] recommended
    brightness: 0.6,     // [0, 2] recommended
    color: '#80FFFFFF'   // mask color
  })
```

**blur / backdropBlur (API 7+) — numeric radius:**
```ts
Column() { /* content */ }
  .backdropBlur(20, { grayscale: [30, 50] })  // background blur
  .blur(10)                                    // foreground blur
```

**backgroundBrightness (API 12+):**
```ts
Column() { /* content */ }
  .backgroundBrightness({ rate: 0.5, lightUpDegree: 0.2 })
```

**Visual effect filters (API 12+):**
```ts
import { uiEffect } from '@kit.ArkGraphics2D';

const blurFilter = uiEffect.createFilter().blur(10);
Column() { /* content */ }
  .backgroundFilter(blurFilter)    // background filter
  .foregroundFilter(blurFilter)    // content filter
```

**pointLight (API 11+, System API only — NOT available for third-party apps):**
```ts
// System apps only! Supports: Image, Column, Flex, Row, Stack, Button, Toggle
Flex()
  .pointLight({
    lightSource: { positionX: '50%', positionY: '50%', positionZ: 80, intensity: 2, color: Color.White },
    illuminated: IlluminatedType.BORDER,  // NONE | BORDER | CONTENT | BORDER_CONTENT
    bloom: 0.5                            // luminous intensity 0–1
  })
```
Up to 12 light sources can illuminate a single component. HarmonyOS 6.0 adds dual-edge flow light and UV background flow light effects.

**systemMaterialEffect (HDS layer, API 23+, HarmonyOS-only SDK):**
```ts
import { hdsMaterial } from '@kit.ArkUI';

Column() { /* content */ }
  .systemMaterialEffect({
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
  })
```
Note: `hdsMaterial` is part of the closed-source HarmonyOS Design System (HDS), not OpenHarmony. Requires HarmonyOS 6.0 SDK (API 23+).

### Builders, styles, extends

```ts
@Builder function Label(text: string) { Text(text).fontSize(16) }

@Styles function Card() { .padding(12).borderRadius(12).backgroundColor('#FFF') }

@Extend(Text) function title() { .fontSize(22).fontWeight(FontWeight.Bold) }

// Usage:
Text('Hello').title()
Column() { Label('x') } .Card()
```

## sys.symbol — icon glyph system

HarmonyOS Symbol is a 1500+ vector icon font with multi-layer color and 7 animation types.

```ts
SymbolGlyph($r('sys.symbol.bell_fill'))
  .fontSize(24)
  .fontColor([Color.Blue, Color.Green])
  .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), true)
```

**Confirmed working names** (SDK 6.0.1): `xmark` · `plus` · `minus` · `checkmark` · `chevron_right` · `chevron_left` · `star` · `star_fill` · `bell` · `bell_fill` · `doc` · `video` · `mic` · `mic_fill` · `clock` · `trash` · `pencil` · `camera` · `person`

**Names that do NOT exist** (common mistakes): `photo` · `doc_richtext` · `sparkles` · `checklist` · `image` (use `doc` or `camera` instead) · `location_fill` (use text label instead)

Find valid names: https://developer.huawei.com/consumer/cn/design/harmonyos-symbol

## UIDesignKit — icon processing & HdsNavigation

Available from HarmonyOS 5.0+ (API 12+). Provides Huawei Design System components.

### `hdsDrawable` — icon adaptive processing

```ts
import { hdsDrawable } from '@kit.UIDesignKit';

// Render app icon with system-consistent adaptive shape (squircle, circle, etc.)
const drawable = new hdsDrawable.HdsAdaptiveIconDrawable(
  context,            // UIAbilityContext or ApplicationContext
  iconResource,       // Resource ($r('app.media.icon'))
  { size: 48 }        // options: size in vp
);
const pixelMap = await drawable.getPixelMap();
```

### `HdsNavigation` — system-style navigation component

```ts
import { HdsNavigation, HdsNavigationItem } from '@kit.UIDesignKit';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  private tabs: HdsNavigationItem[] = [
    { icon: $r('app.media.home'), selectedIcon: $r('app.media.home_filled'), label: '首页' },
    { icon: $r('app.media.mine'), selectedIcon: $r('app.media.mine_filled'), label: '我的' },
  ];

  build() {
    Column() {
      // Page content
      Blank()
      HdsNavigation({
        items: this.tabs,
        selectedIndex: this.currentIndex,
        onItemClick: (index: number) => { this.currentIndex = index; }
      })
    }.height('100%')
  }
}
```

`HdsNavigation` supports: dynamic blur background, custom content areas (badges, dot indicators), message count badges on items.

## Resource access — `$r()` and `$rawfile()`

### Resource directory structure

```
resources/
├─ base/                    # default resources (always matched)
│  ├─ element/              # string.json, color.json, float.json, etc.
│  ├─ media/                # images, audio, video
│  └─ profile/              # custom JSON config files
├─ zh_CN/element/           # Chinese locale override
├─ en_US/element/           # English locale override
├─ dark/element/            # dark mode override
├─ rawfile/                 # raw files (not compiled, accessed by path)
└─ resfile/                 # installed to sandbox, read-only access
```

Qualifier order: MCC_MNC → language_script_region → orientation → device → colorMode → density.

### Accessing resources

```ts
// App resources: $r('app.type.name')
Text($r('app.string.hello_world'))
  .fontSize($r('app.float.text_size_body'))
  .fontColor($r('app.color.primary'))
Image($r('app.media.app_icon'))

// With format args: $r('app.string.greeting', 'Alice', 5)
// For string "Hello, %1$s! You have %2$d messages."
Text($r('app.string.greeting', 'Alice', 5))

// Plural: $r('app.plural.item_count', count, count)
Text($r('app.plural.item_count', 2, 2))  // "2 items"

// Raw files: $rawfile('path/relative/to/rawfile/')
Image($rawfile('images/banner.png'))

// System resources: $r('sys.type.name')
Text('Hello')
  .fontColor($r('sys.color.ohos_id_color_emphasize'))
  .fontSize($r('sys.float.ohos_id_text_size_headline1'))

// Cross-HSP module resources: $r('[moduleName].type.name')
Text($r('[library].string.shared_text'))
```

### Programmatic access via ResourceManager

```ts
const resMgr = getContext(this).resourceManager;
const str = resMgr.getStringByNameSync('hello_world');
const rawFd = resMgr.getRawFd('data.json');  // returns {fd, offset, length}
```

### Application file paths (Context properties)

| Context property | Path | Purpose |
|---|---|---|
| `filesDir` | `base/files/` | Persistent app data (survives app updates) |
| `cacheDir` | `base/cache/` | Cache (system may auto-clean when space low) |
| `tempDir` | `base/temp/` | Temp files (cleaned on app exit) |
| `databaseDir` | `database/` | Database files (relationalStore, etc.) |
| `preferencesDir` | `base/preferences/` | Preferences KV store |
| `bundleCodeDir` | `bundle/` | Installed HAP resources (read-only) |
| `distributedFilesDir` | `distributedfiles/` | Cross-device shared files |

## Custom dialog — openCustomDialog & openBindSheet

### openCustomDialog (general-purpose modal/non-modal)

```ts
import { ComponentContent } from '@kit.ArkUI';

// 1. Define dialog content via @Builder
@Builder
function dialogContentBuilder(params: { message: string; close: () => void }) {
  Column({ space: 16 }) {
    Text(params.message).fontSize(16)
    Button('OK').onClick(() => params.close())
  }
  .padding(24)
  .backgroundColor(Color.White)
  .borderRadius(16)
}

// 2. Open dialog
const uiContext = this.getUIContext();
const contentNode = new ComponentContent(uiContext, wrapBuilder(dialogContentBuilder), {
  message: 'Hello',
  close: () => uiContext.getPromptAction().closeCustomDialog(contentNode),
});
uiContext.getPromptAction().openCustomDialog(contentNode, {
  alignment: DialogAlignment.Center,
  isModal: true,
  autoCancel: true,       // tap outside to close
});
```

### openBindSheet (bottom half-modal sheet)

```ts
const uiContext = this.getUIContext();
const sheetNode = new ComponentContent(uiContext, wrapBuilder(sheetBuilder), params);
uiContext.openBindSheet(sheetNode, {
  title: { title: 'Select Option' },
  height: SheetSize.MEDIUM,
  preferType: SheetType.BOTTOM,
  detents: [SheetSize.MEDIUM, SheetSize.LARGE, 200],   // draggable heights
  backgroundColor: '#F1F3F5',
}, targetComponentId);
```

### bindContentCover (full-screen modal overlay)

```ts
@State isPresented: boolean = false;

@Builder
fullScreenContent() {
  Column() {
    Text('Full Screen Modal').fontSize(20)
    Button('Close').onClick(() => { this.isPresented = false; })
  }.width('100%').height('100%').backgroundColor(Color.White)
}

// Trigger:
Button('Show').onClick(() => { this.isPresented = true; })
  .bindContentCover($$this.isPresented, this.fullScreenContent(), {
    modalTransition: ModalTransition.DEFAULT,   // .NONE, .ALPHA
  })
```

> **Note**: Do NOT use the deprecated `CustomDialog` or `@ohos.promptAction` — use `UIContext.getPromptAction().openCustomDialog()`, `UIContext.openBindSheet()`, and `.bindContentCover()` instead.

## Keyboard layout adaptation (软键盘适配)

### Set keyboard avoidance mode (in UIAbility)

```ts
import { KeyboardAvoidMode } from '@kit.ArkUI';

// OFFSET = page lifts up (default); RESIZE = page compresses; NONE = keyboard overlaps
windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
```

### Prevent a component from moving with keyboard

```ts
Row() { /* title bar — should stay fixed */ }
  .expandSafeArea([SafeAreaType.KEYBOARD])
  .zIndex(1)
```

### Monitor keyboard height

```ts
import { window } from '@kit.ArkUI';

window.getLastWindow(this.getUIContext().getHostContext()).then(win => {
  win.on('keyboardHeightChange', (height: number) => {
    this.keyboardHeight = this.getUIContext().px2vp(height);
  });
});
```

### Focus control

```ts
TextInput().defaultFocus(true)                                    // auto-focus on page load
this.getUIContext().getFocusController().requestFocus('inputId');  // programmatic focus
this.getUIContext().getFocusController().clearFocus();             // dismiss keyboard
```

## Dark mode adaptation (深色模式适配)

### Resource qualifier approach (recommended)

Place light-mode colors/images in `resources/base/`, dark-mode variants (same filenames) in `resources/dark/`:

```
resources/base/element/color.json    → { "color": [{ "name": "bg_color", "value": "#FFFFFF" }] }
resources/dark/element/color.json    → { "color": [{ "name": "bg_color", "value": "#1A1A1A" }] }
resources/base/media/icon.png        → light icon
resources/dark/media/icon.png        → dark icon
```

Usage: `$r('app.color.bg_color')` / `$r('app.media.icon')` — auto-switches with system theme.

### Detect & react to color mode changes

```ts
// In EntryAbility — store current mode
onCreate(): void {
  AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
}
onConfigurationUpdate(newConfig: Configuration): void {
  AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
}

// In component — watch for changes
@StorageProp('currentColorMode') @Watch('onColorModeChange')
currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

onColorModeChange(): void {
  const isDark = this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  // update status bar, custom logic, etc.
}
```

### Programmatic mode switching

```ts
this.getUIContext().getHostContext()?.getApplicationContext()
  .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);   // or COLOR_MODE_LIGHT / COLOR_MODE_NOT_SET
```

## Cross-module resource access (跨模块资源访问)

### Access HAR resources (same as local)

```ts
Text($r('app.string.string_in_har'))
Image($r('app.media.image_in_har'))
// Better performance with .id for resourceManager:
this.context.resourceManager.getStringSync($r('app.string.string_in_har').id);
```

### Access HSP resources (prefix with module name)

```ts
Text($r('[hsp1].string.string_in_hsp'))
Image($r('[hsp1].media.image_in_hsp'))
```

Or via `createModuleContext`:

```ts
import { common } from '@kit.AbilityKit';
const hspContext = await common.application.createModuleContext(this.context, 'hsp1');
const str = hspContext.resourceManager.getStringByNameSync('string_in_hsp');
```

## Custom font (自定义字体)

```ts
// 1. Register font (in EntryAbility onWindowStageCreate or component aboutToAppear)
const uiContext = windowStage.getMainWindowSync().getUIContext();
uiContext.getFont().registerFont({
  familyName: 'MyCustomFont',
  familySrc: $rawfile('MyCustomFont.ttf'),
});

// 2. Use in component
Text('Hello').fontFamily('MyCustomFont')
```

Font size follow/ignore system setting — configure in `profile/configuration.json`:

```json
{ "configuration": { "fontSizeScale": "followSystem", "fontSizeMaxScale": "2" } }
```

Reference in `app.json5`: `"configuration": "$profile:configuration"`.

## Screen orientation (横竖屏切换)

```ts
import { window } from '@kit.ArkUI';

// Get window instance
const win = await window.getLastWindow(this.context);

// Set orientation
win.setPreferredOrientation(window.Orientation.USER_ROTATION_LANDSCAPE);   // enter landscape
win.setPreferredOrientation(window.Orientation.USER_ROTATION_PORTRAIT);    // back to portrait
win.setPreferredOrientation(window.Orientation.AUTO_ROTATION);             // follow sensor

// Monitor window size for layout adaptation
win.on('windowSizeChange', (size) => {
  const orientation = display.getDefaultDisplaySync().orientation;
  this.isLandscape = (orientation === display.Orientation.LANDSCAPE ||
                      orientation === display.Orientation.LANDSCAPE_INVERTED);
});
```

Also configurable in `module.json5`: `"abilities": [{ "orientation": "portrait" }]`.
Options: `portrait`, `landscape`, `auto_rotation`, `auto_rotation_landscape`, `follow_desktop`.

## Clipboard — pasteboard read/write

```ts
import { pasteboard } from '@kit.BasicServicesKit';

// Write text to clipboard
const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, 'Hello World');
const board = pasteboard.getSystemPasteboard();
await board.setData(pasteData);

// Read from clipboard
const data = await board.getData();
if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
  const text = data.getPrimaryText();
}
```

Supported MIME types: `MIMETYPE_TEXT_PLAIN`, `MIMETYPE_TEXT_HTML`, `MIMETYPE_TEXT_URI`, `MIMETYPE_PIXELMAP`.

## Gesture conflict resolution (手势冲突处理)

### hitTestBehavior — control touch event response

```ts
Stack() {
  BottomComponent().hitTestBehavior(HitTestMode.None)       // skip self, pass to sibling
  TopComponent().hitTestBehavior(HitTestMode.Transparent)   // self responds AND passes to sibling
}
```

| Mode | Behavior |
|---|---|
| `Default` | Self responds, blocks siblings |
| `Transparent` | Self responds, does NOT block siblings |
| `None` | Skips self, passes to siblings |
| `Block` | Only self responds, stops all propagation |

### Gesture binding priority

```ts
// Parent takes priority over child for same gesture type
ParentComponent()
  .priorityGesture(TapGesture().onAction(() => { /* parent handles */ }))

// Both parent and child respond simultaneously
ParentComponent()
  .parallelGesture(PanGesture().onAction(() => { /* parent also handles */ }))

// Block child gestures entirely
ParentComponent()
  .gesture(TapGesture(), GestureMask.IgnoreInternal)
```

### GestureGroup modes

```ts
// Sequential: all must succeed in order
GestureGroup(GestureMode.Sequence, LongPressGesture(), PanGesture())

// Parallel: all run simultaneously
GestureGroup(GestureMode.Parallel, PinchGesture(), RotationGesture())

// Exclusive: first to succeed wins
GestureGroup(GestureMode.Exclusive, TapGesture(), SwipeGesture())
```

> **Note**: System gestures (onClick, onTouch, drag, bindMenu) always win over custom gestures of the same type.

## Immersive window (沉浸式/全屏/避让区)

### Extend component into status bar & navigation bar

```ts
// Method 1 — expandSafeArea (simplest, component-level)
Column() { /* content */ }
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

// Method 2 — window-level fullscreen (affects all pages)
const win = windowStage.getMainWindowSync();
win.setWindowLayoutFullScreen(true);
```

### Get safe area dimensions for manual padding

```ts
import { window } from '@kit.ArkUI';

const win = await window.getLastWindow(context);
const systemAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
const topHeight = px2vp(systemAvoid.topRect.height);       // status bar height
const bottomHeight = px2vp(systemAvoid.bottomRect.height);  // navigation bar height

// Listen for changes (e.g. split screen, fold/unfold)
win.on('avoidAreaChange', (options: window.AvoidAreaOptions) => {
  if (options.type === window.AvoidAreaType.TYPE_SYSTEM) {
    // update top/bottom padding
  }
});
```

### Hide/show system bars

```ts
win.setSpecificSystemBarEnabled('status', false);             // hide status bar
win.setSpecificSystemBarEnabled('navigationIndicator', false); // hide nav indicator
```

### Status bar text color (light/dark content)

```ts
win.setWindowSystemBarProperties({
  statusBarContentColor: '#FFFFFF',   // white text for dark backgrounds
});
```

## Common list operations (列表常用操作)

### Swipe-to-delete (left swipe action)

```ts
ListItem() { /* content */ }
  .swipeAction({
    end: {
      builder: () => {
        Button('Delete').backgroundColor(Color.Red)
          .onClick(() => {
            animateTo({ duration: 300 }, () => {
              this.dataList.splice(index, 1);
            });
          })
      },
      actionAreaDistance: 56,
    },
    edgeEffect: SwipeEdgeEffect.Spring,
  })
```

### Drag reorder

```ts
List() {
  ForEach(this.dataList, (item: string, index: number) => {
    ListItem() { Text(item) }
  })
}
.onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
  this.dragIndex = itemIndex;
})
.onItemDragMove((event: ItemDragInfo, itemIndex: number, insertIndex: number) => {
  animateTo({ duration: 200 }, () => {
    const tmp = this.dataList.splice(this.dragIndex, 1);
    this.dataList.splice(insertIndex, 0, tmp[0]);
    this.dragIndex = insertIndex;
  });
})
```

### Pull-down refresh

```ts
Refresh({ refreshing: $$this.isRefreshing }) {
  List() { /* items */ }
}
.onRefreshing(() => {
  // fetch new data...
  this.isRefreshing = false;
})
```

### Scroll to bottom (chat-style)

```ts
const scroller = new Scroller();
List({ scroller }) { /* items */ }

// After new message:
scroller.scrollEdge(Edge.Bottom);
// Or scroll to specific index:
scroller.scrollToIndex(this.messages.length - 1);
```

### Keep scroll position on data insert (LazyForEach)

```ts
List() { LazyForEach(this.dataSource, ...) }
  .maintainVisibleContentPosition(true)   // new items at top don't shift visible content
```

### ListItemGroup + sticky header (grouped list)

```ts
@Builder sectionHeader(title: string) {
  Text(title).fontSize(14).fontColor('#99000000')
    .width('100%').padding({ left: 16, top: 8, bottom: 8 })
    .backgroundColor('#F1F3F5')
}

List() {
  ForEach(this.groups, (group: GroupData) => {
    ListItemGroup({ header: this.sectionHeader(group.title) }) {
      ForEach(group.items, (item: ItemData) => {
        ListItem() { Text(item.name) }
      })
    }
  })
}
.sticky(StickyStyle.Header)         // header sticks to top when scrolling
```

### onReachEnd — load more data

```ts
List() { LazyForEach(this.dataSource, ...) }
  .onReachEnd(() => {
    if (!this.isLoading) {
      this.isLoading = true;
      this.loadNextPage().then(() => { this.isLoading = false; });
    }
  })
```

---
