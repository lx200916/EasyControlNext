/**
 * Entry page — thin shell. Product UI lives in AppShell; Gate B probe is a Home debug strip.
 */

import { AppShell } from '../shell/AppShell';

@Entry
@Component
struct Index {
  build() {
    Column() {
      AppShell()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
