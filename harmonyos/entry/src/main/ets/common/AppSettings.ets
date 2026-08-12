/**
 * App-wide preferences (not per-device). Mirrors Android Setting SharedPreferences lite.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'AppSettings';
const STORE_NAME: string = 'app_settings';
/** When true, Session system Back injects KEYCODE_BACK to remote (current default). */
const KEY_SESSION_BACK_TO_REMOTE: string = 'session_system_back_to_remote';

class AppSettingsStore {
  private prefs: preferences.Preferences | null = null;
  private sessionBackToRemote: boolean = true;
  private ready: boolean = false;

  async init(context: common.Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      this.sessionBackToRemote =
        (await this.prefs.get(KEY_SESSION_BACK_TO_REMOTE, true)) as boolean;
      this.ready = true;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'init failed %{public}s', msg);
      this.ready = true;
    }
  }

  /** System Back in Session → remote KEYCODE_BACK when true; else close session. */
  isSessionBackToRemote(): boolean {
    return this.sessionBackToRemote;
  }

  async setSessionBackToRemote(value: boolean): Promise<void> {
    this.sessionBackToRemote = value;
    const store = this.prefs;
    if (store === null) {
      return;
    }
    try {
      await store.put(KEY_SESSION_BACK_TO_REMOTE, value);
      await store.flush();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'save back preference failed %{public}s', msg);
    }
  }

  isReady(): boolean {
    return this.ready;
  }
}

export const AppSettings: AppSettingsStore = new AppSettingsStore();
