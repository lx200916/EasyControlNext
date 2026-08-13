/**
 * App-wide preferences (not per-device). Mirrors Android Setting SharedPreferences lite.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ColdStartTrace } from './ColdStartTrace';

const DOMAIN: number = 0x0001;
const TAG: string = 'AppSettings';
const STORE_NAME: string = 'app_settings';
/** When true, Session system Back injects KEYCODE_BACK to remote (current default). */
const KEY_SESSION_BACK_TO_REMOTE: string = 'session_system_back_to_remote';
/** TCP preflight before ADB AUTH / TLS. LAN/hotspot default is short. */
const KEY_CONNECT_PROBE_TIMEOUT_MS: string = 'connect_probe_timeout_ms';

/** LAN / hotspot: fail closed ports in well under a second. */
export const CONNECT_PROBE_TIMEOUT_DEFAULT_MS: number = 500;
export const CONNECT_PROBE_TIMEOUT_MIN_MS: number = 200;
export const CONNECT_PROBE_TIMEOUT_MAX_MS: number = 5000;
/** Settings picker. */
export const CONNECT_PROBE_TIMEOUT_OPTIONS_MS: number[] = [300, 500, 800, 1500, 3000];

export function clampConnectProbeTimeoutMs(ms: number): number {
  if (Number.isNaN(ms)) {
    return CONNECT_PROBE_TIMEOUT_DEFAULT_MS;
  }
  if (ms < CONNECT_PROBE_TIMEOUT_MIN_MS) {
    return CONNECT_PROBE_TIMEOUT_MIN_MS;
  }
  if (ms > CONNECT_PROBE_TIMEOUT_MAX_MS) {
    return CONNECT_PROBE_TIMEOUT_MAX_MS;
  }
  return Math.floor(ms);
}

class AppSettingsStore {
  private prefs: preferences.Preferences | null = null;
  private sessionBackToRemote: boolean = true;
  private connectProbeTimeoutMsValue: number = CONNECT_PROBE_TIMEOUT_DEFAULT_MS;
  private ready: boolean = false;
  private initPromise: Promise<void> | null = null;

  async init(context: common.Context): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise;
    }
    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.Context): Promise<void> {
    ColdStartTrace.mark('AppSettings.init.start');
    try {
      this.prefs = await preferences.getPreferences(context, STORE_NAME);
      this.sessionBackToRemote =
        (await this.prefs.get(KEY_SESSION_BACK_TO_REMOTE, true)) as boolean;
      const rawTimeout: preferences.ValueType =
        await this.prefs.get(KEY_CONNECT_PROBE_TIMEOUT_MS, CONNECT_PROBE_TIMEOUT_DEFAULT_MS);
      this.connectProbeTimeoutMsValue = this.readTimeoutMs(rawTimeout);
      this.ready = true;
      ColdStartTrace.mark('AppSettings.init.end');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'init failed %{public}s', msg);
      this.ready = true;
      ColdStartTrace.mark('AppSettings.init.end', 'failed');
    }
  }

  private readTimeoutMs(raw: preferences.ValueType): number {
    if (typeof raw === 'number') {
      return clampConnectProbeTimeoutMs(raw);
    }
    if (typeof raw === 'string') {
      return clampConnectProbeTimeoutMs(parseInt(raw, 10));
    }
    return CONNECT_PROBE_TIMEOUT_DEFAULT_MS;
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

  /** TCP probe timeout before ADB connect (ms). */
  connectProbeTimeoutMs(): number {
    return this.connectProbeTimeoutMsValue;
  }

  async setConnectProbeTimeoutMs(value: number): Promise<void> {
    this.connectProbeTimeoutMsValue = clampConnectProbeTimeoutMs(value);
    const store = this.prefs;
    if (store === null) {
      return;
    }
    try {
      await store.put(KEY_CONNECT_PROBE_TIMEOUT_MS, this.connectProbeTimeoutMsValue);
      await store.flush();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'save probe timeout failed %{public}s', msg);
    }
  }

  isReady(): boolean {
    return this.ready;
  }
}

export const AppSettings: AppSettingsStore = new AppSettingsStore();
