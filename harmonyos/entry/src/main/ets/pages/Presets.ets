/**
 * Connection preset manager — edit, duplicate, set default, reset/delete.
 * Apply-to-device lives on DeviceEditor; Manage → Apply preset is session-only.
 */

import { PresetListPanel } from '../components/PresetListPanel';

@Component
export struct Presets {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('safeBottomVp') safeBottomVp: number;

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            PresetListPanel()
          }
          .width('100%')
          .padding({
            left: $r('app.float.space_page_h'),
            right: $r('app.float.space_page_h'),
            top: 8,
            bottom: 24 + this.safeBottomVp,
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .title({
      main: $r('app.string.presets_title'),
      sub: $r('app.string.presets_subtitle'),
    })
    .hideTitleBar(false)
    .backgroundColor($r('app.color.page_background'))
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
