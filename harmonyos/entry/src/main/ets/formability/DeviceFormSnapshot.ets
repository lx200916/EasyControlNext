/**
 * Flattened device-list payload for Form Kit LocalStorageProp (primitives only).
 */

import { Device, displayDeviceName } from '../model/Device';
import { formatDeviceEndpoint } from '../model/MockDevices';

export class DeviceFormSnapshot {
  title: string = '易控';
  subtitle: string = '';
  count: number = 0;
  dimension: string = '2*2';
  name0: string = '';
  uuid0: string = '';
  ep0: string = '';
  has0: boolean = false;
  name1: string = '';
  uuid1: string = '';
  ep1: string = '';
  has1: boolean = false;
  name2: string = '';
  uuid2: string = '';
  ep2: string = '';
  has2: boolean = false;
}

function fillSlot(snap: DeviceFormSnapshot, index: number, device: Device): void {
  const name = displayDeviceName(device);
  const uuid = device.uuid;
  const ep = formatDeviceEndpoint(device);
  if (index === 0) {
    snap.name0 = name;
    snap.uuid0 = uuid;
    snap.ep0 = ep;
    snap.has0 = true;
  } else if (index === 1) {
    snap.name1 = name;
    snap.uuid1 = uuid;
    snap.ep1 = ep;
    snap.has1 = true;
  } else if (index === 2) {
    snap.name2 = name;
    snap.uuid2 = uuid;
    snap.ep2 = ep;
    snap.has2 = true;
  }
}

export function buildDeviceFormSnapshot(devices: Device[], dimension: string): DeviceFormSnapshot {
  const snap = new DeviceFormSnapshot();
  snap.dimension = dimension.length > 0 ? dimension : '2*2';
  snap.count = devices.length;
  if (devices.length === 0) {
    snap.subtitle = '点此添加设备';
    return snap;
  }
  snap.subtitle = devices.length === 1 ? '1 台设备' : `${devices.length} 台设备`;
  const max = devices.length < 3 ? devices.length : 3;
  for (let i = 0; i < max; i++) {
    fillSlot(snap, i, devices[i]);
  }
  return snap;
}

export function snapshotToBinding(snap: DeviceFormSnapshot): Record<string, Object> {
  const rec: Record<string, Object> = {};
  rec['title'] = snap.title;
  rec['subtitle'] = snap.subtitle;
  rec['count'] = snap.count;
  rec['dimension'] = snap.dimension;
  rec['name0'] = snap.name0;
  rec['uuid0'] = snap.uuid0;
  rec['ep0'] = snap.ep0;
  rec['has0'] = snap.has0;
  rec['name1'] = snap.name1;
  rec['uuid1'] = snap.uuid1;
  rec['ep1'] = snap.ep1;
  rec['has1'] = snap.has1;
  rec['name2'] = snap.name2;
  rec['uuid2'] = snap.uuid2;
  rec['ep2'] = snap.ep2;
  rec['has2'] = snap.has2;
  return rec;
}
