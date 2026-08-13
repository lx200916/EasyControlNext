/**
 * Product shell: Navigation + NavPathStack.
 * Home owns 设备 | 设置 Tabs (liquid glass); add device is header "+" → DeviceEditor.
 * Owns immersive safe-area insets for Home / Settings / DeviceEditor.
 * Gate B probe lives under Settings → Diagnostics.
 */

import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  FoldMeta,
  FoldPosture,
  LayoutSnapshot,
  readLayoutSnapshot,
  readLayoutSnapshotFromWindow,
  startLayoutWatch,
  stopLayoutWatch,
} from '../common/Breakpoint';
import {
  applyImmersiveSystemBarsIfIdle,
  CURRENT_COLOR_MODE_KEY,
  SafeInsetsVp,
  startSafeInsetsWatch,
  stopSafeInsetsWatch,
} from '../common/SystemInsets';
import { DeviceStore } from '../model/DeviceStore';
import { PresetStore } from '../model/PresetStore';
import { Home } from '../pages/Home';
// Deferred routes — Session/DeviceEditor pull libadb_core.so; keep them off the first frame.
import lazy { DeviceEditor } from '../pages/DeviceEditor';
import lazy { Presets } from '../pages/Presets';
import lazy { PresetEditor } from '../pages/PresetEditor';
import lazy { Settings } from '../pages/Settings';
import lazy { Session } from '../pages/Session';
import lazy { ErrorLog } from '../pages/ErrorLog';
import { AppErrorLog } from '../common/AppErrorLog';
import { AppSettings } from '../common/AppSettings';
import { ColdStartTrace } from '../common/ColdStartTrace';
import {
  formNavSessionUuid,
  isFormNavSession,
  PENDING_FORM_NAV_KEY,
} from '../common/FormNav';

// After Home static import (Session/DeviceEditor are lazy) — shell module cost only.
ColdStartTrace.mark('AppShell.module', 'evaluated');

interface WindowSizePx {
  width: number;
  height: number;
}

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
  } else if (name === 'preset') {
    PresetEditor({ presetId: routeParamAsString(param) })
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
  /** Theme — re-apply system bar colors when light/dark flips outside Session. */
  @StorageProp(CURRENT_COLOR_MODE_KEY) @Watch('onColorModeChanged')
  colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @StorageLink(PENDING_FORM_NAV_KEY) @Watch('onPendingFormNav')
  pendingFormNav: string = '';

  private mainWindow: window.Window | undefined = undefined;
  private avoidListener: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  private windowSizeListener: ((size: WindowSizePx) => void) | undefined = undefined;
  private windowStatusListener: ((status: window.WindowStatusType) => void) | undefined = undefined;
  private firstBuildMarked: boolean = false;

  aboutToAppear(): void {
    ColdStartTrace.mark('AppShell.aboutToAppear.enter');
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppErrorLog.init(ctx);
    void AppSettings.init(ctx);
    void PresetStore.init(ctx);
    void DeviceStore.init(ctx).then(() => {
      this.applyPendingFormNav();
    });
    AppStorage.setOrCreate(CURRENT_COLOR_MODE_KEY, ctx.config.colorMode);
    // Display/fold changes still matter; when a window is bound we re-read its rect
    // so expanded+split does not keep full-screen preferSplit chrome.
    // Pass fold from the watch snapshot — foldStatusChange's event status is
    // authoritative; getFoldStatus() / windowRect can lag the animation.
    startLayoutWatch((snapshot: LayoutSnapshot) => {
      const fold: FoldMeta = {
        isFoldable: snapshot.isFoldable,
        foldPosture: snapshot.foldPosture,
      };
      this.refreshLayout(fold);
    });
    this.bindMainWindow();
    ColdStartTrace.mark('AppShell.aboutToAppear.exit');
  }

  onDidBuild(): void {
    if (this.firstBuildMarked) {
      return;
    }
    this.firstBuildMarked = true;
    ColdStartTrace.mark('AppShell.onDidBuild', 'first');
  }

  aboutToDisappear(): void {
    stopLayoutWatch();
    this.unbindWindowLayoutListeners();
    stopSafeInsetsWatch(this.mainWindow, this.avoidListener);
    this.mainWindow = undefined;
    this.avoidListener = undefined;
  }

  private onPendingFormNav(): void {
    this.applyPendingFormNav();
  }

  private applyPendingFormNav(): void {
    const nav = this.pendingFormNav;
    if (nav.length === 0) {
      return;
    }
    if (!DeviceStore.isReady()) {
      return;
    }
    AppStorage.setOrCreate(PENDING_FORM_NAV_KEY, '');
    if (isFormNavSession(nav)) {
      const uuid = formNavSessionUuid(nav);
      if (uuid.length > 0) {
        this.pathStack.pushPath({ name: 'session', param: uuid });
      }
    }
  }

  private onColorModeChanged(): void {
    const win = this.mainWindow;
    if (win === undefined) {
      return;
    }
    void applyImmersiveSystemBarsIfIdle(win, this.colorMode);
  }

  private applyLayoutSnapshot(snapshot: LayoutSnapshot): void {
    // Skip no-op writes — fold expand fires foldStatusChange + display.change + window
    // resize together; redundant @Provide updates force Home/HdsTabs full rebuilds.
    if (this.preferSplit !== snapshot.preferSplit) {
      this.preferSplit = snapshot.preferSplit;
    }
    if (this.foldPosture !== snapshot.foldPosture) {
      this.foldPosture = snapshot.foldPosture;
    }
    if (this.widthVp !== snapshot.widthVp) {
      this.widthVp = snapshot.widthVp;
    }
    if (this.heightVp !== snapshot.heightVp) {
      this.heightVp = snapshot.heightVp;
    }
  }

  private refreshLayout(foldOverride?: FoldMeta): void {
    if (this.mainWindow !== undefined) {
      this.applyLayoutSnapshot(readLayoutSnapshotFromWindow(this.mainWindow, foldOverride));
      return;
    }
    this.applyLayoutSnapshot(readLayoutSnapshot(foldOverride));
  }

  private unbindWindowLayoutListeners(): void {
    const win = this.mainWindow;
    if (win === undefined) {
      return;
    }
    if (this.windowSizeListener !== undefined) {
      try {
        win.off('windowSizeChange', this.windowSizeListener);
      } catch (_e) {
        // ignore
      }
      this.windowSizeListener = undefined;
    }
    if (this.windowStatusListener !== undefined) {
      try {
        win.off('windowStatusChange', this.windowStatusListener);
      } catch (_e) {
        // ignore
      }
      this.windowStatusListener = undefined;
    }
  }

  private bindMainWindow(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      this.unbindWindowLayoutListeners();
      this.mainWindow = win;
      this.refreshLayout();
      void applyImmersiveSystemBarsIfIdle(win, this.colorMode);
      this.windowSizeListener = (_size: WindowSizePx) => {
        this.refreshLayout();
      };
      this.windowStatusListener = (_status: window.WindowStatusType) => {
        this.refreshLayout();
      };
      try {
        win.on('windowSizeChange', this.windowSizeListener);
      } catch (_e) {
        // Preview hosts may lack the event.
      }
      try {
        win.on('windowStatusChange', this.windowStatusListener);
      } catch (_e) {
        // API 11+; ignore if unavailable.
      }
      const ui = this.getUIContext();
      this.avoidListener = startSafeInsetsWatch(win, (px: number) => ui.px2vp(px),
        (insets: SafeInsetsVp) => {
          this.safeTopVp = insets.top;
          this.safeBottomVp = insets.bottom;
        });
    }).catch(() => {
      // Window unavailable in some preview hosts — keep display fallback layout.
      this.refreshLayout();
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
    .width('100%')
    .height('100%')
  }
}
