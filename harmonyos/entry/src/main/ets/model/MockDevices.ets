/**
 * Seed devices when DevicesDb is empty on first launch (then persisted).
 */

import { Device } from './Device';

export function createMockDevices(): Device[] {
  const demo = new Device('mock-pixel');
  demo.name = 'Pixel Demo';
  demo.address = '192.168.31.60';
  demo.adbPort = 5555;
  demo.serverPort = 25166;
  demo.maxSize = 1600;
  demo.maxFps = 60;
  demo.useH265 = false;

  const lab = new Device('mock-lab');
  lab.name = 'Lab Tablet';
  lab.address = '10.0.0.42';
  lab.adbPort = 5555;
  lab.serverPort = 25166;
  lab.useH265 = false;
  lab.isAudio = false;

  return [demo, lab];
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
