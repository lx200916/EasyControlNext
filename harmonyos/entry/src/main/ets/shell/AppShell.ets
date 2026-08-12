/**
 * Product shell: Navigation + NavPathStack.
 * Home owns 设备 | 设置 Tabs (liquid glass); add device is header "+" → DeviceEditor.
 * Owns immersive safe-area insets for Home / Settings / DeviceEditor.
 * Gate B probe lives under Settings → Diagnostics.
 */

import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  FoldPosture,
  LayoutSnapshot,
  startLayoutWatch,
  stopLayoutWatch,
} from '../common/Breakpoint';
import {
  SafeInsetsVp,
  startSafeInsetsWatch,
  stopSafeInsetsWatch,
} from '../common/SystemInsets';
import { DeviceStore } from '../model/DeviceStore';
import { Home } from '../pages/Home';
import { DeviceEditor } from '../pages/DeviceEditor';
import { Presets } from '../pages/Presets';
import { Settings } from '../pages/Settings';
import { Session } from '../pages/Session';
import { ErrorLog } from '../pages/ErrorLog';
import { AppErrorLog } from '../common/AppErrorLog';
import { AppSettings } from '../common/AppSettings';

function routeParamAsString(param: Object): string {
  if (param === undefined || param === null) {
    return 'new';
  }
  return `${param}`;
}

@Builder
function AppNavDestination(name: string, param: Object) {
  if (name === 'settings') {
    Settings()
  } else if (name === 'presets') {
    Presets()
  } else if (name === 'error_logs') {
    ErrorLog()
  } else if (name === 'device') {
    DeviceEditor({ uuid: routeParamAsString(param) })
  } else if (name === 'session') {
    Session({ uuid: routeParamAsString(param) })
  }
}

@Component
export struct AppShell {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  @Provide('preferSplit') preferSplit: boolean = false;
  /** Fold posture from Breakpoint (`folded` / `half` / `expanded` / `unknown`). */
  @Provide('foldPosture') foldPosture: FoldPosture = 'unknown';
  /** Window width in vp — half-fold may still report portrait; Session compensates. */
  @Provide('widthVp') widthVp: number = 360;
  @Provide('heightVp') heightVp: number = 780;
  /** Status / cutout inset (vp) — pad titles & headers below the system status bar. */
  @Provide('safeTopVp') safeTopVp: number = 0;
  /** Home indicator / nav inset (vp) — pad FAB, debug strip, bottom bars. */
  @Provide('safeBottomVp') safeBottomVp: number = 0;

  private mainWindow: window.Window | undefined = undefined;
  private avoidListener: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppErrorLog.init(ctx);
    void AppSettings.init(ctx);
    void DeviceStore.init(ctx);
    startLayoutWatch((snapshot: LayoutSnapshot) => {
      this.preferSplit = snapshot.preferSplit;
      this.foldPosture = snapshot.foldPosture;
      this.widthVp = snapshot.widthVp;
      this.heightVp = snapshot.heightVp;
    });
    this.bindSafeInsets();
  }

  aboutToDisappear(): void {
    stopLayoutWatch();
    stopSafeInsetsWatch(this.mainWindow, this.avoidListener);
    this.mainWindow = undefined;
    this.avoidListener = undefined;
  }

  private bindSafeInsets(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      this.mainWindow = win;
      const ui = this.getUIContext();
      this.avoidListener = startSafeInsetsWatch(win, (px: number) => ui.px2vp(px),
        (insets: SafeInsetsVp) => {
          this.safeTopVp = insets.top;
          this.safeBottomVp = insets.bottom;
        });
    }).catch(() => {
      // Window unavailable in some preview hosts — keep zero insets.
    });
  }

  build() {
    Navigation(this.pathStack) {
      Home()
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .navDestination(AppNavDestination)
    .backgroundColor($r('app.color.page_background'))
    // Draw/layout under status + home indicator; pages pad via safeTopVp/safeBottomVp.
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
