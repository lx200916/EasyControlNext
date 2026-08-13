/**
 * Device list helpers (lookup / endpoint formatting).
 * Historical mock seeds (`mock-pixel` / `mock-lab`) are never written on init;
 * strip them if still present from older builds or legacy RDB migrate.
 */

import { Device } from './Device';

/** UUIDs written by early `createMockDevices()` seed — remove on load, never re-create. */
export const LEGACY_MOCK_UUIDS: string[] = ['mock-pixel', 'mock-lab'];

export function isLegacyMockUuid(uuid: string): boolean {
  return uuid === 'mock-pixel' || uuid === 'mock-lab';
}

/** Drop known demo seed rows; preserves any real user devices. */
export function stripLegacyMockDevices(devices: Device[]): Device[] {
  const out: Device[] = [];
  for (let i = 0; i < devices.length; i++) {
    if (!isLegacyMockUuid(devices[i].uuid)) {
      out.push(devices[i]);
    }
  }
  return out;
}

export function findDeviceByUuid(devices: Device[], uuid: string): Device | undefined {
  for (let i = 0; i < devices.length; i++) {
    if (devices[i].uuid === uuid) {
      return devices[i];
    }
  }
  return undefined;
}

export function formatDeviceEndpoint(device: Device): string {
  return `${device.address}:${device.adbPort}`;
}
