/**
 * Device list: in-memory cache backed by preferences (`DevicePrefs`).
 * Home watches AppStorage `deviceStoreRevision` for list refresh.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ColdStartTrace } from '../common/ColdStartTrace';
import { DevicePrefs } from '../data/DevicePrefs';
import { AppSettings } from '../common/AppSettings';
import { Device } from './Device';
import { findDeviceByUuid, formatDeviceEndpoint } from './MockDevices';
import { pushDeviceForms } from '../formability/DeviceFormSync';

const DOMAIN: number = 0xEC01;
const TAG: string = 'DeviceStore';
const STORE_REV_KEY: string = 'deviceStoreRevision';

function cloneDevice(src: Device): Device {
  const d = new Device(src.uuid);
  d.name = src.name;
  d.address = src.address;
  d.adbPort = src.adbPort;
  d.serverPort = src.serverPort;
  d.pairPort = src.pairPort;
  d.pairKey = src.pairKey;
  d.presetId = src.presetId;
  d.useH265 = src.useH265;
  d.hevcProfile = src.hevcProfile;
  d.isAudio = src.isAudio;
  d.maxSize = src.maxSize;
  d.maxFps = src.maxFps;
  d.maxVideoBit = src.maxVideoBit;
  d.listenClip = src.listenClip;
  d.keepWakeOnRunning = src.keepWakeOnRunning;
  d.connectOnStart = src.connectOnStart;
  d.changeToFullOnConnect = src.changeToFullOnConnect;
  d.wakeOnConnect = src.wakeOnConnect;
  d.lightOffOnConnect = src.lightOffOnConnect;
  d.showNavBarOnConnect = src.showNavBarOnConnect;
  d.customResolutionOnConnect = src.customResolutionOnConnect;
  d.customResolutionWidth = src.customResolutionWidth;
  d.customResolutionHeight = src.customResolutionHeight;
  d.lockOnClose = src.lockOnClose;
  d.lightOnClose = src.lightOnClose;
  d.videoSource = src.videoSource;
  d.cameraFacing = src.cameraFacing;
  d.virtualWidth = src.virtualWidth;
  d.virtualHeight = src.virtualHeight;
  d.virtualDpi = src.virtualDpi;
  d.startApp = src.startApp;
  return d;
}

export class DeviceStore {
  private static devices: Device[] = [];
  private static initPromise: Promise<void> | null = null;
  private static ready: boolean = false;
  private static hostContext: common.Context | null = null;

  static isReady(): boolean {
    return DeviceStore.ready;
  }

  static bumpRevision(): void {
    const prev = AppStorage.get<number>(STORE_REV_KEY);
    const next = (prev !== undefined ? prev : 0) + 1;
    AppStorage.setOrCreate(STORE_REV_KEY, next);
  }

  /** Idempotent: open preferences, load devices (no mock seed on empty). */
  static init(context: common.Context): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      return DeviceStore.initPromise;
    }
    DeviceStore.initPromise = DeviceStore.doInit(context);
    return DeviceStore.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    ColdStartTrace.mark('DeviceStore.init.start');
    try {
      DeviceStore.hostContext = context;
      await DevicePrefs.open(context);
      DeviceStore.devices = await DevicePrefs.loadAll(context);
      DeviceStore.ready = true;
      DeviceStore.bumpRevision();
      hilog.info(DOMAIN, TAG, 'loaded %{public}d devices', DeviceStore.devices.length);
      ColdStartTrace.mark('DeviceStore.init.end', `count=${DeviceStore.devices.length}`);
      DeviceStore.scheduleFormPush();
    } catch (_e) {
      DeviceStore.ready = false;
      DeviceStore.initPromise = null;
      hilog.error(DOMAIN, TAG, '%{public}s', 'init failed');
      ColdStartTrace.mark('DeviceStore.init.end', 'failed');
      throw new Error('DeviceStore init failed');
    }
  }

  private static scheduleFormPush(): void {
    const ctx = DeviceStore.hostContext;
    if (ctx === null) {
      return;
    }
    void pushDeviceForms(ctx, DeviceStore.devices).catch((_e: Error) => {
      // Form updates are best-effort (no cards installed is fine).
    });
  }

  static getAll(): Device[] {
    const out: Device[] = [];
    for (let i = 0; i < DeviceStore.devices.length; i++) {
      out.push(cloneDevice(DeviceStore.devices[i]));
    }
    return out;
  }

  static findByUuid(uuid: string): Device | undefined {
    const found = findDeviceByUuid(DeviceStore.devices, uuid);
    return found !== undefined ? cloneDevice(found) : undefined;
  }

  static createDraft(): Device {
    const d = new Device(`device-${Date.now()}`);
    d.name = '';
    d.address = '';
    d.adbPort = 5555;
    d.serverPort = 25166;
    d.pairPort = 0;
    d.pairKey = '';
    d.maxSize = 1600;
    d.maxFps = 60;
    d.useH265 = AppSettings.preferH265();
    return d;
  }

  /** Insert or replace by uuid in preferences + cache. Returns the persisted clone. */
  static async upsert(device: Device): Promise<Device> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    if (!DeviceStore.ready) {
      throw new Error('DeviceStore not initialized');
    }
    const saved = cloneDevice(device);
    let idx = -1;
    for (let i = 0; i < DeviceStore.devices.length; i++) {
      if (DeviceStore.devices[i].uuid === saved.uuid) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      DeviceStore.devices[idx] = saved;
    } else {
      DeviceStore.devices.push(saved);
    }
    await DevicePrefs.saveAll(DeviceStore.devices);
    DeviceStore.bumpRevision();
    DeviceStore.scheduleFormPush();
    hilog.info(DOMAIN, TAG, 'upsert ok uuid=%{public}s name=%{public}s', saved.uuid, saved.name);
    return cloneDevice(saved);
  }

  static async deleteByUuid(uuid: string): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    if (!DeviceStore.ready) {
      throw new Error('DeviceStore not initialized');
    }
    const next: Device[] = [];
    for (let i = 0; i < DeviceStore.devices.length; i++) {
      if (DeviceStore.devices[i].uuid !== uuid) {
        next.push(DeviceStore.devices[i]);
      }
    }
    DeviceStore.devices = next;
    await DevicePrefs.saveAll(DeviceStore.devices);
    DeviceStore.bumpRevision();
    DeviceStore.scheduleFormPush();
  }

  /** Reload cache from preferences (e.g. after external write). */
  static async reload(): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    if (!DeviceStore.ready) {
      return;
    }
    DeviceStore.devices = await DevicePrefs.readAll();
    DeviceStore.bumpRevision();
    DeviceStore.scheduleFormPush();
  }

  static endpointOf(device: Device): string {
    return formatDeviceEndpoint(device);
  }

  /**
   * First successful probe may fill an empty name (model). Never overwrites a
   * user-set name. Returns true when the persisted name changed.
   */
  static async applyProbedNameIfEmpty(uuid: string, model: string): Promise<boolean> {
    const name = model.trim();
    if (uuid.length === 0 || name.length === 0) {
      return false;
    }
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    if (!DeviceStore.ready) {
      return false;
    }
    const found = findDeviceByUuid(DeviceStore.devices, uuid);
    if (found === undefined || found.name.trim().length > 0) {
      return false;
    }
    found.name = name;
    await DevicePrefs.saveAll(DeviceStore.devices);
    DeviceStore.bumpRevision();
    DeviceStore.scheduleFormPush();
    hilog.info(DOMAIN, TAG, 'probed name uuid=%{public}s name=%{public}s', uuid, name);
    return true;
  }
}
