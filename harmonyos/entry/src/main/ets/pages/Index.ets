/**
 * Entry page — thin shell. Product UI lives in AppShell.
 * Do not ignore layout safe areas here: real devices need honest status / home insets
 * for NavDestination title bars and HdsTabs.
 */

import { ColdStartTrace } from '../common/ColdStartTrace';
import { AppShell } from '../shell/AppShell';

ColdStartTrace.mark('Index.module', 'evaluated');

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    ColdStartTrace.mark('Index.aboutToAppear');
  }

  build() {
    Column() {
      AppShell()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
