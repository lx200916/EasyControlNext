/**
 * In-memory remote system-info cache for Home detail pane.
 * Populated lazily via ADB getprop; never blocks first paint.
 */

import { Device } from './Device';

const CACHE_TTL_MS: number = 10 * 60 * 1000;

export class RemoteSystemSnapshot {
  model: string = '';
  release: string = '';
  sdk: string = '';
  reachable: boolean = false;
  /** True after at least one probe attempt finished (ok or fail). */
  probed: boolean = false;
  probedAt: number = 0;
  detail: string = '';
}

class CacheEntry {
  uuid: string = '';
  snap: RemoteSystemSnapshot = new RemoteSystemSnapshot();
}

export class DeviceInfoCache {
  private static entries: CacheEntry[] = [];

  static get(uuid: string): RemoteSystemSnapshot | undefined {
    if (uuid.length === 0) {
      return undefined;
    }
    for (let i = 0; i < DeviceInfoCache.entries.length; i++) {
      if (DeviceInfoCache.entries[i].uuid === uuid) {
        return DeviceInfoCache.entries[i].snap;
      }
    }
    return undefined;
  }

  static put(uuid: string, snap: RemoteSystemSnapshot): void {
    if (uuid.length === 0) {
      return;
    }
    for (let i = 0; i < DeviceInfoCache.entries.length; i++) {
      if (DeviceInfoCache.entries[i].uuid === uuid) {
        DeviceInfoCache.entries[i].snap = snap;
        return;
      }
    }
    const entry = new CacheEntry();
    entry.uuid = uuid;
    entry.snap = snap;
    DeviceInfoCache.entries.push(entry);
  }

  static remove(uuid: string): void {
    if (uuid.length === 0) {
      return;
    }
    const next: CacheEntry[] = [];
    for (let i = 0; i < DeviceInfoCache.entries.length; i++) {
      if (DeviceInfoCache.entries[i].uuid !== uuid) {
        next.push(DeviceInfoCache.entries[i]);
      }
    }
    DeviceInfoCache.entries = next;
  }

  /** Fresh enough to skip auto re-probe on select. */
  static isFresh(uuid: string): boolean {
    const snap = DeviceInfoCache.get(uuid);
    if (snap === undefined || !snap.probed) {
      return false;
    }
    return (Date.now() - snap.probedAt) < CACHE_TTL_MS;
  }
}

/** Stream options already on Device — no network. */
export function streamSummaryOf(device: Device): string {
  const codec = device.useH265 ? 'H.265' : 'H.264';
  return `${device.maxSize}p · ${device.maxFps} fps · ${codec}`;
}

export function formatAndroidVersion(release: string, sdk: string): string {
  const rel = release.trim();
  const api = sdk.trim();
  if (rel.length === 0 && api.length === 0) {
    return '未探测';
  }
  if (rel.length > 0 && api.length > 0) {
    return `Android ${rel}（API ${api}）`;
  }
  if (rel.length > 0) {
    return `Android ${rel}`;
  }
  return `API ${api}`;
}

export function formatModelLabel(model: string): string {
  const m = model.trim();
  return m.length > 0 ? m : '未知';
}

export function formatReachability(snap: RemoteSystemSnapshot | undefined): string {
  if (snap === undefined || !snap.probed) {
    return '未探测';
  }
  return snap.reachable ? '可达' : '不可达';
}

export function formatProbedAt(snap: RemoteSystemSnapshot | undefined): string {
  if (snap === undefined || !snap.probed || snap.probedAt <= 0) {
    return '';
  }
  const d = new Date(snap.probedAt);
  const hh = pad2(d.getHours());
  const mm = pad2(d.getMinutes());
  return `${hh}:${mm}`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}
