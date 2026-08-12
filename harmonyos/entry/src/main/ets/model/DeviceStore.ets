/**
 * Device list: in-memory cache backed by relationalStore (`DeviceDb`).
 * Home watches AppStorage `deviceStoreRevision` for list refresh.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { DeviceDb } from '../data/DeviceDb';
import { Device } from './Device';
import { createMockDevices, findDeviceByUuid, formatDeviceEndpoint } from './MockDevices';

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
  private static rdb: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<void> | null = null;
  private static ready: boolean = false;

  static isReady(): boolean {
    return DeviceStore.ready;
  }

  static bumpRevision(): void {
    const prev = AppStorage.get<number>(STORE_REV_KEY);
    const next = (prev !== undefined ? prev : 0) + 1;
    AppStorage.setOrCreate(STORE_REV_KEY, next);
  }

  /** Idempotent: open RDB, load rows, seed mocks once if empty. */
  static init(context: common.Context): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      return DeviceStore.initPromise;
    }
    DeviceStore.initPromise = DeviceStore.doInit(context);
    return DeviceStore.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    try {
      const store = await DeviceDb.open(context);
      DeviceStore.rdb = store;
      let rows = await DeviceDb.getAll(store);
      if (rows.length === 0) {
        const seeds = createMockDevices();
        for (let i = 0; i < seeds.length; i++) {
          await DeviceDb.upsert(store, seeds[i]);
        }
        rows = await DeviceDb.getAll(store);
        hilog.info(DOMAIN, TAG, 'seeded %{public}d mock devices', seeds.length);
      }
      DeviceStore.devices = rows;
      DeviceStore.ready = true;
      DeviceStore.bumpRevision();
      hilog.info(DOMAIN, TAG, 'loaded %{public}d devices', DeviceStore.devices.length);
    } catch (_e) {
      DeviceStore.ready = false;
      DeviceStore.initPromise = null;
      hilog.error(DOMAIN, TAG, '%{public}s', 'init failed');
      throw new Error('DeviceStore init failed');
    }
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
    return d;
  }

  /** Insert or replace by uuid in RDB + cache. Returns the persisted clone. */
  static async upsert(device: Device): Promise<Device> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    const store = DeviceStore.rdb;
    if (store === null) {
      throw new Error('DeviceStore not initialized');
    }
    const saved = cloneDevice(device);
    await DeviceDb.upsert(store, saved);
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
    DeviceStore.bumpRevision();
    hilog.info(DOMAIN, TAG, 'upsert ok uuid=%{public}s name=%{public}s', saved.uuid, saved.name);
    return cloneDevice(saved);
  }

  static async deleteByUuid(uuid: string): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    const store = DeviceStore.rdb;
    if (store === null) {
      throw new Error('DeviceStore not initialized');
    }
    await DeviceDb.deleteByUuid(store, uuid);
    const next: Device[] = [];
    for (let i = 0; i < DeviceStore.devices.length; i++) {
      if (DeviceStore.devices[i].uuid !== uuid) {
        next.push(DeviceStore.devices[i]);
      }
    }
    DeviceStore.devices = next;
    DeviceStore.bumpRevision();
  }

  /** Reload cache from RDB (e.g. after external write). */
  static async reload(): Promise<void> {
    if (DeviceStore.initPromise !== null) {
      await DeviceStore.initPromise;
    }
    const store = DeviceStore.rdb;
    if (store === null) {
      return;
    }
    DeviceStore.devices = await DeviceDb.getAll(store);
    DeviceStore.bumpRevision();
  }

  static endpointOf(device: Device): string {
    return formatDeviceEndpoint(device);
  }
}
