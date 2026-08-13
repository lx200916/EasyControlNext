import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  errorManager,
  UIAbility,
  Want,
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppErrorLog } from '../common/AppErrorLog';
import { AppSettings } from '../common/AppSettings';
import { ColdStartTrace } from '../common/ColdStartTrace';
import {
  applyImmersiveSystemBars,
  applyImmersiveSystemBarsIfIdle,
  CURRENT_COLOR_MODE_KEY,
} from '../common/SystemInsets';
import { DecoderCapsCache } from '../media/DecoderCapsCache';
import { DeviceStore } from '../model/DeviceStore';
import {
  PENDING_FORM_NAV_KEY,
} from '../common/FormNav';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private errorObserverId: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    ColdStartTrace.mark('EntryAbility.onCreate.enter');
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onCreate');
    // Bind log path only — do not sync-read error_log.txt before first frame.
    ColdStartTrace.mark('AppErrorLog.init.enter');
    AppErrorLog.init(this.context);
    ColdStartTrace.mark('AppErrorLog.init.exit');
    AppStorage.setOrCreate(CURRENT_COLOR_MODE_KEY, this.context.config.colorMode);
    this.applyFormWant(want);
    const observer: errorManager.ErrorObserver = {
      onUnhandledException(errMsg: string): void {
        AppErrorLog.e('Uncaught', errMsg);
      },
      onException(errObject: Error): void {
        const stack = errObject.stack !== undefined ? errObject.stack : '';
        AppErrorLog.e('Uncaught', `${errObject.name}: ${errObject.message}`, stack);
      }
    };
    this.errorObserverId = errorManager.on('error', observer);
    // Prefer first frame: AppSettings is async prefs; DeviceStore waits for loadContent.
    ColdStartTrace.mark('EntryAbility.onCreate.exit');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onDestroy');
    if (this.errorObserverId >= 0) {
      errorManager.off('error', this.errorObserverId);
      this.errorObserverId = -1;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    ColdStartTrace.mark('EntryAbility.onWindowStageCreate.enter');
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onWindowStageCreate');

    ColdStartTrace.mark('loadContent.before', 'pages/Index');
    windowStage.loadContent('pages/Index', (err) => {
      ColdStartTrace.mark('loadContent.callback', err.code ? `err=${err.code}` : 'ok');
      if (err.code) {
        hilog.error(DOMAIN, 'EasyControlNext', 'Failed to load the content. Cause: %{public}s',
          JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'EasyControlNext', 'Succeeded in loading the content.');
      // After content bind: warm settings + device cache without delaying loadContent.
      void AppSettings.init(this.context);
      DecoderCapsCache.scheduleBackgroundProbe(this.context);
      void DeviceStore.init(this.context).catch((e: Error) => {
        const msg = e.message;
        hilog.error(DOMAIN, 'EasyControlNext', 'DeviceStore.init: %{public}s', msg);
        AppErrorLog.e('DeviceStore', `init failed: ${msg}`, e.stack !== undefined ? e.stack : '');
      });
      // Apply after content bind so bar props stick on first frame hosts.
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        applyImmersiveSystemBars(mainWindow, this.context.config.colorMode).then(() => {
          hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Immersive system bars enabled');
        });
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'EasyControlNext', 'getMainWindow failed: %{public}s', JSON.stringify(e));
      });
    });
    ColdStartTrace.mark('EntryAbility.onWindowStageCreate.exit', 'loadContent scheduled');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate(CURRENT_COLOR_MODE_KEY, newConfig.colorMode);
    window.getLastWindow(this.context).then((win: window.Window) => {
      void applyImmersiveSystemBarsIfIdle(win, newConfig.colorMode);
    }).catch((_e: Error) => {
      // Window may be unavailable during early config churn.
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onForeground');
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.applyFormWant(want);
  }

  private applyFormWant(want: Want): void {
    if (want.parameters === undefined) {
      return;
    }
    const raw = want.parameters['params'];
    let route: string = '';
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const parsed: Object = JSON.parse(raw) as Object;
        if (parsed !== null && typeof parsed === 'object') {
          const rec = parsed as Record<string, Object>;
          if (typeof rec['route'] === 'string') {
            route = rec['route'] as string;
          }
        }
      } catch (_e) {
        hilog.warn(DOMAIN, 'EasyControlNext', '%{public}s', 'form want params parse failed');
      }
    } else if (raw !== undefined && typeof raw === 'object') {
      const rec = raw as Record<string, Object>;
      if (typeof rec['route'] === 'string') {
        route = rec['route'] as string;
      }
    }
    if (route.length > 0) {
      AppStorage.setOrCreate(PENDING_FORM_NAV_KEY, route);
      hilog.info(DOMAIN, 'EasyControlNext', 'form nav %{public}s', route);
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onBackground');
  }
}
