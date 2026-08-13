/**
 * Connection presets persisted in preferences (Android PresetStore).
 * Built-ins are re-seeded if missing; deleting a built-in resets it to factory.
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Device } from './Device';
import { DeviceStore } from './DeviceStore';
import {
  ConnectionPreset,
  createBuiltInPresets,
  factoryPresetByKey,
  normalizeHevcProfile,
  PRESET_ID_NORMAL,
} from './ConnectionPreset';

const DOMAIN: number = 0xEC02;
const TAG: string = 'PresetStore';
const STORE_NAME: string = 'connection_presets';
const KEY_LIST: string = 'presets_json';
const KEY_DEFAULT: string = 'default_preset_id';
const REV_KEY: string = 'presetStoreRevision';

interface PresetDto {
  id: string;
  name: string;
  builtInKey: string;
  videoSource: string;
  cameraFacing: string;
  startApp: string;
  virtualWidth: number;
  virtualHeight: number;
  virtualDpi: number;
  isAudio: boolean;
  listenClip: boolean;
  maxSize: number;
  maxFps: number;
  maxVideoBit: number;
  useH265: boolean;
  hevcProfile: string;
  keepWakeOnRunning: boolean;
  changeToFullOnConnect: boolean;
  wakeOnConnect: boolean;
  lightOffOnConnect: boolean;
  showNavBarOnConnect: boolean;
}

function asString(value: Object | undefined | null, fallback: string): string {
  if (typeof value === 'string') {
    return value;
  }
  return fallback;
}

function asNumber(value: Object | undefined | null, fallback: number): number {
  if (typeof value === 'number' && !isNaN(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const n: number = parseInt(value, 10);
    if (!isNaN(n)) {
      return n;
    }
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

function presetToDto(preset: ConnectionPreset): PresetDto {
  const dto: PresetDto = {
    id: preset.id,
    name: preset.name,
    builtInKey: preset.builtInKey,
    videoSource: preset.videoSource,
    cameraFacing: preset.cameraFacing,
    startApp: preset.startApp,
    virtualWidth: preset.virtualWidth,
    virtualHeight: preset.virtualHeight,
    virtualDpi: preset.virtualDpi,
    isAudio: preset.isAudio,
    listenClip: preset.listenClip,
    maxSize: preset.maxSize,
    maxFps: preset.maxFps,
    maxVideoBit: preset.maxVideoBit,
    useH265: preset.useH265,
    hevcProfile: normalizeHevcProfile(preset.hevcProfile),
    keepWakeOnRunning: preset.keepWakeOnRunning,
    changeToFullOnConnect: preset.changeToFullOnConnect,
    wakeOnConnect: preset.wakeOnConnect,
    lightOffOnConnect: preset.lightOffOnConnect,
    showNavBarOnConnect: preset.showNavBarOnConnect,
  };
  return dto;
}

function dtoFromObject(raw: Record<string, Object>): PresetDto {
  const dto: PresetDto = {
    id: asString(raw['id'], ''),
    name: asString(raw['name'], ''),
    builtInKey: asString(raw['builtInKey'], ''),
    videoSource: asString(raw['videoSource'], 'display'),
    cameraFacing: asString(raw['cameraFacing'], 'back'),
    startApp: asString(raw['startApp'], ''),
    virtualWidth: asNumber(raw['virtualWidth'], 0),
    virtualHeight: asNumber(raw['virtualHeight'], 0),
    virtualDpi: asNumber(raw['virtualDpi'], 0),
    isAudio: asBoolean(raw['isAudio'], false),
    listenClip: asBoolean(raw['listenClip'], true),
    maxSize: asNumber(raw['maxSize'], 1600),
    maxFps: asNumber(raw['maxFps'], 60),
    maxVideoBit: asNumber(raw['maxVideoBit'], 4),
    useH265: asBoolean(raw['useH265'], false),
    hevcProfile: asString(raw['hevcProfile'], 'main'),
    keepWakeOnRunning: asBoolean(raw['keepWakeOnRunning'], true),
    changeToFullOnConnect: asBoolean(raw['changeToFullOnConnect'], false),
    wakeOnConnect: asBoolean(raw['wakeOnConnect'], true),
    lightOffOnConnect: asBoolean(raw['lightOffOnConnect'], false),
    showNavBarOnConnect: asBoolean(raw['showNavBarOnConnect'], true),
  };
  return dto;
}

function presetFromDto(dto: PresetDto): ConnectionPreset {
  const p = new ConnectionPreset();
  p.id = dto.id;
  p.name = dto.name.length > 0 ? dto.name : dto.id;
  p.builtInKey = dto.builtInKey;
  p.videoSource = dto.videoSource === 'camera' ? 'camera' : 'display';
  p.cameraFacing = dto.cameraFacing === 'front' ? 'front' : 'back';
  p.startApp = dto.startApp;
  p.virtualWidth = dto.virtualWidth;
  p.virtualHeight = dto.virtualHeight;
  p.virtualDpi = dto.virtualDpi;
  p.isAudio = dto.isAudio;
  p.listenClip = dto.listenClip;
  p.maxSize = dto.maxSize;
  p.maxFps = dto.maxFps;
  p.maxVideoBit = dto.maxVideoBit;
  p.useH265 = dto.useH265;
  p.hevcProfile = normalizeHevcProfile(dto.hevcProfile);
  p.keepWakeOnRunning = dto.keepWakeOnRunning;
  p.changeToFullOnConnect = dto.changeToFullOnConnect;
  p.wakeOnConnect = dto.wakeOnConnect;
  p.lightOffOnConnect = dto.lightOffOnConnect;
  p.showNavBarOnConnect = dto.showNavBarOnConnect;
  return p;
}

function parsePresetsJson(raw: string): ConnectionPreset[] {
  if (raw.length === 0) {
    return [];
  }
  try {
    const parsed: Object = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const list: Object[] = parsed as Object[];
    const out: ConnectionPreset[] = [];
    for (let i = 0; i < list.length; i++) {
      const item: Object = list[i];
      if (item === null || typeof item !== 'object') {
        continue;
      }
      const dto = dtoFromObject(item as Record<string, Object>);
      if (dto.id.length === 0) {
        continue;
      }
      out.push(presetFromDto(dto));
    }
    return out;
  } catch (_e) {
    hilog.warn(DOMAIN, TAG, '%{public}s', 'presets_json parse failed');
    return [];
  }
}

function serializePresets(list: ConnectionPreset[]): string {
  const dtos: PresetDto[] = [];
  for (let i = 0; i < list.length; i++) {
    dtos.push(presetToDto(list[i]));
  }
  return JSON.stringify(dtos);
}

function cloneList(list: ConnectionPreset[]): ConnectionPreset[] {
  const out: ConnectionPreset[] = [];
  for (let i = 0; i < list.length; i++) {
    out.push(list[i].clone());
  }
  return out;
}

export class PresetStore {
  private static prefs: preferences.Preferences | null = null;
  private static cache: ConnectionPreset[] = createBuiltInPresets();
  private static defaultPresetId: string = PRESET_ID_NORMAL;
  private static initPromise: Promise<void> | null = null;
  private static ready: boolean = false;

  static bumpRevision(): void {
    const prev = AppStorage.get<number>(REV_KEY);
    const next = (prev !== undefined ? prev : 0) + 1;
    AppStorage.setOrCreate(REV_KEY, next);
  }

  static isReady(): boolean {
    return PresetStore.ready;
  }

  static async init(context: common.Context): Promise<void> {
    if (PresetStore.initPromise !== null) {
      return PresetStore.initPromise;
    }
    PresetStore.initPromise = PresetStore.doInit(context);
    return PresetStore.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    try {
      PresetStore.prefs = await preferences.getPreferences(context, STORE_NAME);
      const raw = (await PresetStore.prefs.get(KEY_LIST, '')) as string;
      const loaded = parsePresetsJson(raw);
      PresetStore.cache = loaded.length > 0 ? loaded : [];
      const defRaw = (await PresetStore.prefs.get(KEY_DEFAULT, PRESET_ID_NORMAL)) as string;
      PresetStore.defaultPresetId = defRaw.length > 0 ? defRaw : PRESET_ID_NORMAL;
      const seeded = PresetStore.ensureSeededInMemory();
      if (seeded || loaded.length === 0) {
        await PresetStore.persist();
      }
      PresetStore.ready = true;
      PresetStore.bumpRevision();
      hilog.info(DOMAIN, TAG, 'loaded %{public}d presets', PresetStore.cache.length);
    } catch (e) {
      PresetStore.ready = true;
      PresetStore.initPromise = null;
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'init failed %{public}s', msg);
      PresetStore.cache = createBuiltInPresets();
      PresetStore.defaultPresetId = PRESET_ID_NORMAL;
      PresetStore.bumpRevision();
    }
  }

  /** Re-seed missing built-ins. Returns true when the in-memory list changed. */
  private static ensureSeededInMemory(): boolean {
    let changed = false;
    const factories = createBuiltInPresets();
    for (let i = 0; i < factories.length; i++) {
      const factory = factories[i];
      let found = false;
      for (let j = 0; j < PresetStore.cache.length; j++) {
        if (PresetStore.cache[j].id === factory.id ||
          PresetStore.cache[j].builtInKey === factory.builtInKey) {
          found = true;
          break;
        }
      }
      if (!found) {
        PresetStore.cache.push(factory);
        changed = true;
      }
    }
    if (PresetStore.get(PresetStore.defaultPresetId) === undefined) {
      PresetStore.defaultPresetId = PRESET_ID_NORMAL;
      changed = true;
    }
    return changed;
  }

  private static async persist(): Promise<void> {
    const store = PresetStore.prefs;
    if (store === null) {
      return;
    }
    try {
      await store.put(KEY_LIST, serializePresets(PresetStore.cache));
      await store.put(KEY_DEFAULT, PresetStore.defaultPresetId);
      await store.flush();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'persist failed %{public}s', msg);
    }
  }

  static all(): ConnectionPreset[] {
    return cloneList(PresetStore.cache);
  }

  static get(id: string): ConnectionPreset | undefined {
    for (let i = 0; i < PresetStore.cache.length; i++) {
      if (PresetStore.cache[i].id === id) {
        return PresetStore.cache[i].clone();
      }
    }
    return undefined;
  }

  static defaultId(): string {
    return PresetStore.defaultPresetId;
  }

  static getDefault(): ConnectionPreset {
    const found = PresetStore.get(PresetStore.defaultPresetId);
    if (found !== undefined) {
      return found;
    }
    const normal = PresetStore.get(PRESET_ID_NORMAL);
    if (normal !== undefined) {
      return normal;
    }
    return createBuiltInPresets()[0];
  }

  static async setDefaultId(id: string): Promise<void> {
    if (PresetStore.get(id) === undefined) {
      return;
    }
    PresetStore.defaultPresetId = id;
    await PresetStore.persist();
    PresetStore.bumpRevision();
  }

  static async save(preset: ConnectionPreset): Promise<void> {
    const next = preset.clone();
    let idx = -1;
    for (let i = 0; i < PresetStore.cache.length; i++) {
      if (PresetStore.cache[i].id === next.id) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      PresetStore.cache[idx] = next;
    } else {
      PresetStore.cache.push(next);
    }
    await PresetStore.persist();
    PresetStore.bumpRevision();
  }

  static newId(): string {
    return util.generateRandomUUID();
  }

  static async duplicate(preset: ConnectionPreset, copySuffix: string): Promise<ConnectionPreset> {
    const copy = preset.clone();
    copy.id = PresetStore.newId();
    copy.name = `${preset.name}${copySuffix}`;
    copy.builtInKey = '';
    await PresetStore.save(copy);
    return copy;
  }

  /**
   * Custom: remove. Built-in: restore factory options (keep user-chosen name).
   * Returns true if removed.
   */
  static async deleteOrReset(id: string): Promise<boolean> {
    const existing = PresetStore.get(id);
    if (existing === undefined) {
      return true;
    }
    if (existing.isBuiltIn) {
      const factory = factoryPresetByKey(existing.builtInKey);
      if (factory !== undefined) {
        factory.name = existing.name;
        await PresetStore.save(factory);
      }
      return false;
    }
    const next: ConnectionPreset[] = [];
    for (let i = 0; i < PresetStore.cache.length; i++) {
      if (PresetStore.cache[i].id !== id) {
        next.push(PresetStore.cache[i]);
      }
    }
    PresetStore.cache = next;
    await PresetStore.clearDeviceLinks(id);
    if (PresetStore.defaultPresetId === id) {
      PresetStore.defaultPresetId = PRESET_ID_NORMAL;
    }
    await PresetStore.persist();
    PresetStore.bumpRevision();
    return true;
  }

  static async resetBuiltIn(id: string): Promise<ConnectionPreset | undefined> {
    const existing = PresetStore.get(id);
    if (existing === undefined || !existing.isBuiltIn) {
      return undefined;
    }
    const factory = factoryPresetByKey(existing.builtInKey);
    if (factory === undefined) {
      return undefined;
    }
    await PresetStore.save(factory);
    return factory;
  }

  static linkedDevices(presetId: string): Device[] {
    if (presetId.length === 0) {
      return [];
    }
    const all = DeviceStore.getAll();
    const out: Device[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].presetId === presetId) {
        out.push(all[i]);
      }
    }
    return out;
  }

  static linkedCount(presetId: string): number {
    return PresetStore.linkedDevices(presetId).length;
  }

  static async updateLinkedDevices(preset: ConnectionPreset): Promise<number> {
    const linked = PresetStore.linkedDevices(preset.id);
    for (let i = 0; i < linked.length; i++) {
      const device = linked[i];
      preset.applyTo(device);
      await DeviceStore.upsert(device);
    }
    return linked.length;
  }

  static async clearDeviceLinks(presetId: string): Promise<void> {
    const linked = PresetStore.linkedDevices(presetId);
    for (let i = 0; i < linked.length; i++) {
      const device = linked[i];
      device.presetId = '';
      await DeviceStore.upsert(device);
    }
  }

  static summaryLine(preset: ConnectionPreset): string {
    const src = preset.videoSource === 'camera' ? '摄像头' : '屏幕';
    return `${src} · ${preset.maxSize}px · ${preset.maxFps}fps · ${preset.maxVideoBit}Mbps`;
  }
}
