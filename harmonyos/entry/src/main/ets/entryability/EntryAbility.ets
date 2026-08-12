import { AbilityConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppErrorLog } from '../common/AppErrorLog';
import { AppSettings } from '../common/AppSettings';
import { applyImmersiveSystemBars } from '../common/SystemInsets';
import { DeviceStore } from '../model/DeviceStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private errorObserverId: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onCreate');
    AppErrorLog.init(this.context);
    void AppSettings.init(this.context);
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
    // Kick off RDB load before first frame; AppShell/Home also await init.
    void DeviceStore.init(this.context).catch((e: Error) => {
      const msg = e.message;
      hilog.error(DOMAIN, 'EasyControlNext', 'DeviceStore.init: %{public}s', msg);
      AppErrorLog.e('DeviceStore', `init failed: ${msg}`, e.stack !== undefined ? e.stack : '');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onDestroy');
    if (this.errorObserverId >= 0) {
      errorManager.off('error', this.errorObserverId);
      this.errorObserverId = -1;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EasyControlNext', 'Failed to load the content. Cause: %{public}s',
          JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'EasyControlNext', 'Succeeded in loading the content.');
      // Apply after content bind so bar props stick on first frame hosts.
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        applyImmersiveSystemBars(mainWindow).then(() => {
          hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Immersive system bars enabled');
        });
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'EasyControlNext', 'getMainWindow failed: %{public}s', JSON.stringify(e));
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'EasyControlNext', '%{public}s', 'Ability onBackground');
  }
}
