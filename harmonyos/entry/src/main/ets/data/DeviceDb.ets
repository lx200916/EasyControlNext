/**
 * relationalStore access for DevicesDb (Android DbHelper field subset + pairing + preset link).
 * Migration-safe: CREATE TABLE IF NOT EXISTS + additive ALTER for new columns.
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CameraFacing, Device, HevcPref, VideoSource } from '../model/Device';

const DOMAIN: number = 0xEC01;
const TAG: string = 'DeviceDb';
const DB_NAME: string = 'app.db';
export const DEVICES_TABLE: string = 'DevicesDb';

const CREATE_SQL: string =
  'CREATE TABLE IF NOT EXISTS DevicesDb (' +
  'uuid TEXT PRIMARY KEY,' +
  'name TEXT,' +
  'address TEXT,' +
  'adbPort INTEGER,' +
  'serverPort INTEGER,' +
  'pairPort INTEGER,' +
  'pairKey TEXT,' +
  'presetId TEXT,' +
  'useH265 INTEGER,' +
  'hevcProfile TEXT,' +
  'isAudio INTEGER,' +
  'maxSize INTEGER,' +
  'maxFps INTEGER,' +
  'maxVideoBit INTEGER,' +
  'listenClip INTEGER,' +
  'keepWakeOnRunning INTEGER,' +
  'connectOnStart INTEGER,' +
  'changeToFullOnConnect INTEGER,' +
  'wakeOnConnect INTEGER,' +
  'lightOffOnConnect INTEGER,' +
  'showNavBarOnConnect INTEGER,' +
  'customResolutionOnConnect INTEGER,' +
  'customResolutionWidth INTEGER,' +
  'customResolutionHeight INTEGER,' +
  'lockOnClose INTEGER,' +
  'lightOnClose INTEGER,' +
  'videoSource TEXT,' +
  'cameraFacing TEXT,' +
  'virtualWidth INTEGER,' +
  'virtualHeight INTEGER,' +
  'virtualDpi INTEGER,' +
  'startApp TEXT)';

const ALTER_COLUMNS: string[] = [
  'ALTER TABLE DevicesDb ADD COLUMN presetId TEXT',
  'ALTER TABLE DevicesDb ADD COLUMN connectOnStart INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN changeToFullOnConnect INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN wakeOnConnect INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN lightOffOnConnect INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN showNavBarOnConnect INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN customResolutionOnConnect INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN customResolutionWidth INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN customResolutionHeight INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN lockOnClose INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN lightOnClose INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN videoSource TEXT',
  'ALTER TABLE DevicesDb ADD COLUMN cameraFacing TEXT',
  'ALTER TABLE DevicesDb ADD COLUMN virtualWidth INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN virtualHeight INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN virtualDpi INTEGER',
  'ALTER TABLE DevicesDb ADD COLUMN startApp TEXT',
];

function boolToInt(v: boolean): number {
  return v ? 1 : 0;
}

function intToBool(v: number): boolean {
  return v === 1;
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

function deviceFromRow(rs: relationalStore.ResultSet): Device {
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
  d.lockOnClose = intToBool(readLong(rs, 'lockOnClose', 1));
  d.lightOnClose = intToBool(readLong(rs, 'lightOnClose', 0));
  d.videoSource = normalizeVideoSource(readString(rs, 'videoSource', 'display'));
  d.cameraFacing = normalizeCameraFacing(readString(rs, 'cameraFacing', 'back'));
  d.virtualWidth = readLong(rs, 'virtualWidth', 0);
  d.virtualHeight = readLong(rs, 'virtualHeight', 0);
  d.virtualDpi = readLong(rs, 'virtualDpi', 0);
  d.startApp = readString(rs, 'startApp', '');
  return d;
}

function toValues(device: Device): relationalStore.ValuesBucket {
  const values: relationalStore.ValuesBucket = {
    'uuid': device.uuid,
    'name': device.name,
    'address': device.address,
    'adbPort': device.adbPort,
    'serverPort': device.serverPort,
    'pairPort': device.pairPort,
    'pairKey': device.pairKey,
    'presetId': device.presetId,
    'useH265': boolToInt(device.useH265),
    'hevcProfile': device.hevcProfile,
    'isAudio': boolToInt(device.isAudio),
    'maxSize': device.maxSize,
    'maxFps': device.maxFps,
    'maxVideoBit': device.maxVideoBit,
    'listenClip': boolToInt(device.listenClip),
    'keepWakeOnRunning': boolToInt(device.keepWakeOnRunning),
    'connectOnStart': boolToInt(device.connectOnStart),
    'changeToFullOnConnect': boolToInt(device.changeToFullOnConnect),
    'wakeOnConnect': boolToInt(device.wakeOnConnect),
    'lightOffOnConnect': boolToInt(device.lightOffOnConnect),
    'showNavBarOnConnect': boolToInt(device.showNavBarOnConnect),
    'customResolutionOnConnect': boolToInt(device.customResolutionOnConnect),
    'customResolutionWidth': device.customResolutionWidth,
    'customResolutionHeight': device.customResolutionHeight,
    'lockOnClose': boolToInt(device.lockOnClose),
    'lightOnClose': boolToInt(device.lightOnClose),
    'videoSource': device.videoSource,
    'cameraFacing': device.cameraFacing,
    'virtualWidth': device.virtualWidth,
    'virtualHeight': device.virtualHeight,
    'virtualDpi': device.virtualDpi,
    'startApp': device.startApp,
  };
  return values;
}

async function ensureColumns(store: relationalStore.RdbStore): Promise<void> {
  for (let i = 0; i < ALTER_COLUMNS.length; i++) {
    try {
      await store.executeSql(ALTER_COLUMNS[i]);
    } catch (_e) {
      // Column already present on upgraded DBs.
    }
  }
}

export class DeviceDb {
  static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    });
    await store.executeSql(CREATE_SQL);
    await ensureColumns(store);
    hilog.info(DOMAIN, TAG, 'RDB ready %{public}s table=%{public}s', DB_NAME, DEVICES_TABLE);
    return store;
  }

  static async getAll(store: relationalStore.RdbStore): Promise<Device[]> {
    const predicates = new relationalStore.RdbPredicates(DEVICES_TABLE);
    predicates.orderByAsc('name');
    const rs = await store.query(predicates);
    const out: Device[] = [];
    try {
      while (rs.goToNextRow()) {
        out.push(deviceFromRow(rs));
      }
    } finally {
      rs.close();
    }
    return out;
  }

  static async getByUuid(store: relationalStore.RdbStore, uuid: string): Promise<Device | undefined> {
    const predicates = new relationalStore.RdbPredicates(DEVICES_TABLE);
    predicates.equalTo('uuid', uuid);
    const rs = await store.query(predicates);
    try {
      if (rs.goToNextRow()) {
        return deviceFromRow(rs);
      }
      return undefined;
    } finally {
      rs.close();
    }
  }

  static async upsert(store: relationalStore.RdbStore, device: Device): Promise<void> {
    const existing = await DeviceDb.getByUuid(store, device.uuid);
    const values = toValues(device);
    if (existing !== undefined) {
      const predicates = new relationalStore.RdbPredicates(DEVICES_TABLE);
      predicates.equalTo('uuid', device.uuid);
      await store.update(values, predicates);
      hilog.info(DOMAIN, TAG, 'update uuid=%{public}s', device.uuid);
    } else {
      await store.insert(DEVICES_TABLE, values);
      hilog.info(DOMAIN, TAG, 'insert uuid=%{public}s', device.uuid);
    }
  }

  static async deleteByUuid(store: relationalStore.RdbStore, uuid: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(DEVICES_TABLE);
    predicates.equalTo('uuid', uuid);
    await store.delete(predicates);
    hilog.info(DOMAIN, TAG, 'delete uuid=%{public}s', uuid);
  }
}
