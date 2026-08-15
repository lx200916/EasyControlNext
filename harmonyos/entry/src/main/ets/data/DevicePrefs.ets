/**
 * Preferences-backed device list (JSON blob). Replaces relationalStore DevicesDb.
 * One-time best-effort import from legacy app.db when prefs are empty.
 * Legacy mock seed UUIDs (mock-pixel / mock-lab) are stripped on every load.
 */

import { common } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraFacing, Device, HevcPref, VideoSource } from '../model/Device';
import { stripLegacyMockDevices } from '../model/MockDevices';
import { ColdStartTrace } from '../common/ColdStartTrace';

const DOMAIN: number = 0xEC01;
const TAG: string = 'DevicePrefs';
const STORE_NAME: string = 'device_store';
const KEY_DEVICES: string = 'devices_json';
const LEGACY_DB_NAME: string = 'app.db';
const LEGACY_TABLE: string = 'DevicesDb';

/** Serializable shape for JSON prefs (all Device fields). */
interface DeviceDto {
  uuid: string;
  name: string;
  address: string;
  adbPort: number;
  serverPort: number;
  pairPort: number;
  pairKey: string;
  presetId: string;
  useH265: boolean;
  hevcProfile: string;
  isAudio: boolean;
  maxSize: number;
  maxFps: number;
  maxVideoBit: number;
  listenClip: boolean;
  keepWakeOnRunning: boolean;
  connectOnStart: boolean;
  changeToFullOnConnect: boolean;
  wakeOnConnect: boolean;
  lightOffOnConnect: boolean;
  showNavBarOnConnect: boolean;
  customResolutionOnConnect: boolean;
  customResolutionWidth: number;
  customResolutionHeight: number;
  lockOnClose: boolean;
  lightOnClose: boolean;
  videoSource: string;
  cameraFacing: string;
  virtualWidth: number;
  virtualHeight: number;
  virtualDpi: number;
  startApp: string;
}

function normalizeHevcProfile(raw: string): HevcPref {
  const v = raw.trim().toLowerCase();
  if (v === 'auto' || v === 'main10' || v === 'main' || v === 'none') {
    return v as HevcPref;
  }
  return 'main';
}

function normalizeVideoSource(raw: string): VideoSource {
  return raw === 'camera' ? 'camera' : 'display';
}

function normalizeCameraFacing(raw: string): CameraFacing {
  return raw === 'front' ? 'front' : 'back';
}

function asString(value: Object | undefined | null, fallback: string): string {
  if (typeof value === 'string') {
    return value;
  }
  return fallback;
}

function asNumber(value: Object | undefined | null, fallback: number): number {
  if (typeof value === 'number' && value === value) {
    return value;
  }
  return fallback;
}

function asBoolean(value: Object | undefined | null, fallback: boolean): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  return fallback;
}

function deviceToDto(device: Device): DeviceDto {
  return {
    uuid: device.uuid,
    name: device.name,
    address: device.address,
    adbPort: device.adbPort,
    serverPort: device.serverPort,
    pairPort: device.pairPort,
    pairKey: device.pairKey,
    presetId: device.presetId,
    useH265: device.useH265,
    hevcProfile: device.hevcProfile,
    isAudio: device.isAudio,
    maxSize: device.maxSize,
    maxFps: device.maxFps,
    maxVideoBit: device.maxVideoBit,
    listenClip: device.listenClip,
    keepWakeOnRunning: device.keepWakeOnRunning,
    connectOnStart: device.connectOnStart,
    changeToFullOnConnect: device.changeToFullOnConnect,
    wakeOnConnect: device.wakeOnConnect,
    lightOffOnConnect: device.lightOffOnConnect,
    showNavBarOnConnect: device.showNavBarOnConnect,
    customResolutionOnConnect: device.customResolutionOnConnect,
    customResolutionWidth: device.customResolutionWidth,
    customResolutionHeight: device.customResolutionHeight,
    lockOnClose: device.lockOnClose,
    lightOnClose: device.lightOnClose,
    videoSource: device.videoSource,
    cameraFacing: device.cameraFacing,
    virtualWidth: device.virtualWidth,
    virtualHeight: device.virtualHeight,
    virtualDpi: device.virtualDpi,
    startApp: device.startApp,
  };
}

function dtoFromObject(raw: Record<string, Object>): DeviceDto {
  return {
    uuid: asString(raw['uuid'], ''),
    name: asString(raw['name'], ''),
    address: asString(raw['address'], ''),
    adbPort: asNumber(raw['adbPort'], 5555),
    serverPort: asNumber(raw['serverPort'], 25166),
    pairPort: asNumber(raw['pairPort'], 0),
    pairKey: asString(raw['pairKey'], ''),
    presetId: asString(raw['presetId'], ''),
    useH265: asBoolean(raw['useH265'], true),
    hevcProfile: asString(raw['hevcProfile'], 'main'),
    isAudio: asBoolean(raw['isAudio'], false),
    maxSize: asNumber(raw['maxSize'], 1600),
    maxFps: asNumber(raw['maxFps'], 60),
    maxVideoBit: asNumber(raw['maxVideoBit'], 4),
    listenClip: asBoolean(raw['listenClip'], true),
    keepWakeOnRunning: asBoolean(raw['keepWakeOnRunning'], true),
    connectOnStart: asBoolean(raw['connectOnStart'], false),
    changeToFullOnConnect: asBoolean(raw['changeToFullOnConnect'], false),
    wakeOnConnect: asBoolean(raw['wakeOnConnect'], true),
    lightOffOnConnect: asBoolean(raw['lightOffOnConnect'], false),
    showNavBarOnConnect: asBoolean(raw['showNavBarOnConnect'], true),
    customResolutionOnConnect: asBoolean(raw['customResolutionOnConnect'], false),
    customResolutionWidth: asNumber(raw['customResolutionWidth'], 1080),
    customResolutionHeight: asNumber(raw['customResolutionHeight'], 2400),
    lockOnClose: asBoolean(raw['lockOnClose'], false),
    lightOnClose: asBoolean(raw['lightOnClose'], false),
    videoSource: asString(raw['videoSource'], 'display'),
    cameraFacing: asString(raw['cameraFacing'], 'back'),
    virtualWidth: asNumber(raw['virtualWidth'], 0),
    virtualHeight: asNumber(raw['virtualHeight'], 0),
    virtualDpi: asNumber(raw['virtualDpi'], 0),
    startApp: asString(raw['startApp'], ''),
  };
}

function deviceFromDto(dto: DeviceDto): Device {
  const d = new Device(dto.uuid);
  d.name = dto.name;
  d.address = dto.address;
  d.adbPort = dto.adbPort;
  d.serverPort = dto.serverPort;
  d.pairPort = dto.pairPort;
  d.pairKey = dto.pairKey;
  d.presetId = dto.presetId;
  d.useH265 = dto.useH265;
  d.hevcProfile = normalizeHevcProfile(dto.hevcProfile);
  d.isAudio = dto.isAudio;
  d.maxSize = dto.maxSize;
  d.maxFps = dto.maxFps;
  d.maxVideoBit = dto.maxVideoBit;
  d.listenClip = dto.listenClip;
  d.keepWakeOnRunning = dto.keepWakeOnRunning;
  d.connectOnStart = dto.connectOnStart;
  d.changeToFullOnConnect = dto.changeToFullOnConnect;
  d.wakeOnConnect = dto.wakeOnConnect;
  d.lightOffOnConnect = dto.lightOffOnConnect;
  d.showNavBarOnConnect = dto.showNavBarOnConnect;
  d.customResolutionOnConnect = dto.customResolutionOnConnect;
  d.customResolutionWidth = dto.customResolutionWidth;
  d.customResolutionHeight = dto.customResolutionHeight;
  d.lockOnClose = dto.lockOnClose;
  d.lightOnClose = dto.lightOnClose;
  d.videoSource = normalizeVideoSource(dto.videoSource);
  d.cameraFacing = normalizeCameraFacing(dto.cameraFacing);
  d.virtualWidth = dto.virtualWidth;
  d.virtualHeight = dto.virtualHeight;
  d.virtualDpi = dto.virtualDpi;
  d.startApp = dto.startApp;
  return d;
}

function parseDevicesJson(raw: string): Device[] {
  if (raw.length === 0) {
    return [];
  }
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const list: Object[] = parsed as Object[];
    const out: Device[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: Object = list[i];
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const dto = dtoFromObject(item as Record<string, Object>);
      if (dto.uuid.length === 0) {
        continue;
      }
      out.push(deviceFromDto(dto));
    }
    out.sort((a: Device, b: Device) => {
      if (a.name < b.name) {
        return -1;
      }
      if (a.name > b.name) {
        return 1;
      }
      return 0;
    });
    return out;
  } catch (_e) {
    hilog.warn(DOMAIN, TAG, '%{public}s', 'devices_json parse failed');
    return [];
  }
}

function serializeDevices(devices: Device[]): string {
  const dtos: DeviceDto[] = [];
  for (let i = 0; i < devices.length; i++) {
    dtos.push(deviceToDto(devices[i]));
  }
  return JSON.stringify(dtos);
}

function intToBool(v: number): boolean {
  return v === 1;
}

function readString(rs: relationalStore.ResultSet, col: string, fallback: string): string {
  const idx = rs.getColumnIndex(col);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return fallback;
  }
  const v = rs.getString(idx);
  return v !== undefined && v !== null ? v : fallback;
}

function readLong(rs: relationalStore.ResultSet, col: string, fallback: number): number {
  const idx = rs.getColumnIndex(col);
  if (idx < 0 || rs.isColumnNull(idx)) {
    return fallback;
  }
  return rs.getLong(idx);
}

function deviceFromLegacyRow(rs: relationalStore.ResultSet): Device {
  const uuid = readString(rs, 'uuid', '');
  const d = new Device(uuid);
  d.name = readString(rs, 'name', '');
  d.address = readString(rs, 'address', '');
  d.adbPort = readLong(rs, 'adbPort', 5555);
  d.serverPort = readLong(rs, 'serverPort', 25166);
  d.pairPort = readLong(rs, 'pairPort', 0);
  d.pairKey = readString(rs, 'pairKey', '');
  d.presetId = readString(rs, 'presetId', '');
  d.useH265 = intToBool(readLong(rs, 'useH265', 0));
  d.hevcProfile = normalizeHevcProfile(readString(rs, 'hevcProfile', 'main'));
  d.isAudio = intToBool(readLong(rs, 'isAudio', 0));
  d.maxSize = readLong(rs, 'maxSize', 1600);
  d.maxFps = readLong(rs, 'maxFps', 60);
  d.maxVideoBit = readLong(rs, 'maxVideoBit', 4);
  d.listenClip = intToBool(readLong(rs, 'listenClip', 1));
  d.keepWakeOnRunning = intToBool(readLong(rs, 'keepWakeOnRunning', 1));
  d.connectOnStart = intToBool(readLong(rs, 'connectOnStart', 0));
  d.changeToFullOnConnect = intToBool(readLong(rs, 'changeToFullOnConnect', 0));
  d.wakeOnConnect = intToBool(readLong(rs, 'wakeOnConnect', 1));
  d.lightOffOnConnect = intToBool(readLong(rs, 'lightOffOnConnect', 0));
  d.showNavBarOnConnect = intToBool(readLong(rs, 'showNavBarOnConnect', 1));
  d.customResolutionOnConnect = intToBool(readLong(rs, 'customResolutionOnConnect', 0));
  d.customResolutionWidth = readLong(rs, 'customResolutionWidth', 1080);
  d.customResolutionHeight = readLong(rs, 'customResolutionHeight', 2400);
  d.lockOnClose = intToBool(readLong(rs, 'lockOnClose', 0));
  d.lightOnClose = intToBool(readLong(rs, 'lightOnClose', 0));
  d.videoSource = normalizeVideoSource(readString(rs, 'videoSource', 'display'));
  d.cameraFacing = normalizeCameraFacing(readString(rs, 'cameraFacing', 'back'));
  d.virtualWidth = readLong(rs, 'virtualWidth', 0);
  d.virtualHeight = readLong(rs, 'virtualHeight', 0);
  d.virtualDpi = readLong(rs, 'virtualDpi', 0);
  d.startApp = readString(rs, 'startApp', '');
  return d;
}

/** True if a legacy app.db already exists — avoid getRdbStore creating an empty DB. */
function legacyRdbFileExists(context: common.Context): boolean {
  const candidates: string[] = [
    `${context.databaseDir}/${LEGACY_DB_NAME}`,
    `${context.databaseDir}/rdb/${LEGACY_DB_NAME}`,
  ];
  for (let i = 0; i < candidates.length; i++) {
    try {
      if (fs.accessSync(candidates[i])) {
        return true;
      }
    } catch (_e) {
      // try next path
    }
  }
  return false;
}

/**
 * Best-effort one-shot read from legacy RDB. No CREATE/ALTER — misses or errors → [].
 * Skips getRdbStore when no app.db file exists (opening would create an empty DB and
 * slow first cold start for fresh installs).
 * Leaves app.db untouched when present.
 */
async function tryMigrateFromLegacyRdb(context: common.Context): Promise<Device[]> {
  if (!legacyRdbFileExists(context)) {
    hilog.info(DOMAIN, TAG, '%{public}s', 'no legacy app.db — skip RDB migrate');
    ColdStartTrace.mark('DevicePrefs.migrate', 'skipped no app.db');
    return [];
  }
  ColdStartTrace.mark('DevicePrefs.migrate.start', 'legacy app.db found');
  try {
    const store = await relationalStore.getRdbStore(context, {
      name: LEGACY_DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    });
    const predicates = new relationalStore.RdbPredicates(LEGACY_TABLE);
    predicates.orderByAsc('name');
    const rs = await store.query(predicates);
    const out: Device[] = [];
    try {
      while (rs.goToNextRow()) {
        const d = deviceFromLegacyRow(rs);
        if (d.uuid.length > 0) {
          out.push(d);
        }
      }
    } finally {
      rs.close();
    }
    ColdStartTrace.mark('DevicePrefs.migrate.end', `count=${out.length}`);
    return out;
  } catch (_e) {
    ColdStartTrace.mark('DevicePrefs.migrate.end', 'error');
    return [];
  }
}

export class DevicePrefs {
  private static prefs: preferences.Preferences | null = null;

  static async open(context: common.Context): Promise<void> {
    ColdStartTrace.mark('DevicePrefs.open.start');
    DevicePrefs.prefs = await preferences.getPreferences(context, STORE_NAME);
    hilog.info(DOMAIN, TAG, 'preferences ready %{public}s', STORE_NAME);
    ColdStartTrace.mark('DevicePrefs.open.end');
  }

  /** Read prefs only (no RDB migration). */
  static async readAll(): Promise<Device[]> {
    const store = DevicePrefs.prefs;
    if (store === null) {
      throw new Error('DevicePrefs not opened');
    }
    const raw = (await store.get(KEY_DEVICES, '')) as string;
    return parseDevicesJson(raw);
  }

  /**
   * Init load: preferences first; if key never written, try one-shot legacy RDB import.
   * Empty prefs after a prior save ("[]") stays empty — no re-migrate, no mock seed.
   * Always strips historical seed UUIDs (`mock-pixel` / `mock-lab`) so upgrades and
   * HAP reinstalls that keep sandbox data no longer surface Lab Tablet / Pixel Demo.
   */
  static async loadAll(context: common.Context): Promise<Device[]> {
    ColdStartTrace.mark('DevicePrefs.load.start');
    const store = DevicePrefs.prefs;
    if (store === null) {
      throw new Error('DevicePrefs not opened');
    }
    const raw = (await store.get(KEY_DEVICES, '')) as string;
    let devices = parseDevicesJson(raw);
    let dirty: boolean = false;
    if (devices.length === 0 && raw.length === 0) {
      const legacy = stripLegacyMockDevices(await tryMigrateFromLegacyRdb(context));
      if (legacy.length > 0) {
        devices = legacy;
        dirty = true;
        hilog.info(DOMAIN, TAG, 'migrated %{public}d devices from legacy RDB', legacy.length);
      } else {
        // Persist empty list so subsequent launches skip legacy RDB open
        // (and so mock-only legacy DBs do not keep reappearing).
        dirty = true;
      }
    } else {
      ColdStartTrace.mark('DevicePrefs.migrate', 'not needed prefs present');
    }
    const cleaned = stripLegacyMockDevices(devices);
    if (cleaned.length !== devices.length) {
      hilog.info(DOMAIN, TAG, 'removed %{public}d legacy mock seed device(s)',
        devices.length - cleaned.length);
      devices = cleaned;
      dirty = true;
    }
    if (dirty) {
      await DevicePrefs.saveAll(devices);
    }
    ColdStartTrace.mark('DevicePrefs.load.end', `count=${devices.length}`);
    return devices;
  }

  static async saveAll(devices: Device[]): Promise<void> {
    const store = DevicePrefs.prefs;
    if (store === null) {
      throw new Error('DevicePrefs not opened');
    }
    await store.put(KEY_DEVICES, serializeDevices(devices));
    await store.flush();
  }
}
