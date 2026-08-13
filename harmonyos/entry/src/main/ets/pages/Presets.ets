/**
 * Connection preset manager — edit, duplicate, set default, reset/delete.
 * Apply-to-device lives on DeviceEditor; Manage → Apply preset is session-only.
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { hdsOverlayTitleBar, HDS_MINI_TITLE_INSET_VP } from '../common/HdsTitleBar';
import { PresetListPanel } from '../components/PresetListPanel';

@Component
export struct Presets {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('safeBottomVp') safeBottomVp: number;
  private readonly pageScroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      Column() {
        Scroll(this.pageScroller) {
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
        .clip(false)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .contentStartOffset(HDS_MINI_TITLE_INSET_VP)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar(hdsOverlayTitleBar({
      title: {
        mainTitle: $r('app.string.presets_title'),
        subTitle: $r('app.string.presets_subtitle'),
      },
    }))
    .hideTitleBar(false)
    .bindToScrollable([this.pageScroller])
    .backgroundColor(Color.Transparent)
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
