/**
 * Stream / session preset (Android ConnectionPreset). Identity fields stay on Device.
 */

import { Device, HevcPref } from './Device';

export class ConnectionPreset {
  id: string = '';
  name: string = '';
  /** Non-empty for shipped templates. */
  builtInKey: string = '';
  videoSource: string = 'display';
  cameraFacing: string = 'back';
  startApp: string = '';
  virtualWidth: number = 0;
  virtualHeight: number = 0;
  virtualDpi: number = 0;
  isAudio: boolean = false;
  listenClip: boolean = true;
  maxSize: number = 1600;
  maxFps: number = 60;
  maxVideoBit: number = 4;
  useH265: boolean = false;
  hevcProfile: string = 'main';
  keepWakeOnRunning: boolean = true;
  changeToFullOnConnect: boolean = false;
  wakeOnConnect: boolean = true;
  lightOffOnConnect: boolean = false;
  showNavBarOnConnect: boolean = true;

  get isBuiltIn(): boolean {
    return this.builtInKey.length > 0;
  }

  clone(): ConnectionPreset {
    const p = new ConnectionPreset();
    p.id = this.id;
    p.name = this.name;
    p.builtInKey = this.builtInKey;
    p.videoSource = this.videoSource;
    p.cameraFacing = this.cameraFacing;
    p.startApp = this.startApp;
    p.virtualWidth = this.virtualWidth;
    p.virtualHeight = this.virtualHeight;
    p.virtualDpi = this.virtualDpi;
    p.isAudio = this.isAudio;
    p.listenClip = this.listenClip;
    p.maxSize = this.maxSize;
    p.maxFps = this.maxFps;
    p.maxVideoBit = this.maxVideoBit;
    p.useH265 = this.useH265;
    p.hevcProfile = this.hevcProfile;
    p.keepWakeOnRunning = this.keepWakeOnRunning;
    p.changeToFullOnConnect = this.changeToFullOnConnect;
    p.wakeOnConnect = this.wakeOnConnect;
    p.lightOffOnConnect = this.lightOffOnConnect;
    p.showNavBarOnConnect = this.showNavBarOnConnect;
    return p;
  }

  /** Copy stream fields onto device and set presetId link. */
  applyTo(device: Device): void {
    device.videoSource = this.videoSource === 'camera' ? 'camera' : 'display';
    device.cameraFacing = this.cameraFacing === 'front' ? 'front' : 'back';
    device.startApp = device.videoSource === 'camera' ? '' : this.startApp;
    device.virtualWidth = this.virtualWidth;
    device.virtualHeight = this.virtualHeight;
    device.virtualDpi = this.virtualDpi;
    device.isAudio = this.isAudio;
    device.listenClip = this.listenClip;
    device.maxSize = this.maxSize;
    device.maxFps = this.maxFps;
    device.maxVideoBit = this.maxVideoBit;
    device.useH265 = this.useH265;
    device.hevcProfile = normalizeHevcProfile(this.hevcProfile);
    device.keepWakeOnRunning = this.keepWakeOnRunning;
    device.changeToFullOnConnect = this.changeToFullOnConnect;
    device.wakeOnConnect = this.wakeOnConnect;
    device.lightOffOnConnect = this.lightOffOnConnect;
    device.showNavBarOnConnect = this.showNavBarOnConnect;
    device.presetId = this.id;
  }

  /** Session-only: apply stream fields without linking presetId. */
  applySessionOnly(device: Device): void {
    this.applyTo(device);
    device.presetId = '';
  }
}

export const PRESET_ID_NORMAL: string = 'builtin_normal_remote';
export const PRESET_ID_CAMERA: string = 'builtin_camera_monitor';
export const PRESET_ID_APP: string = 'builtin_single_app';

export const PRESET_KEY_NORMAL: string = 'normal_remote';
export const PRESET_KEY_CAMERA: string = 'camera_monitor';
export const PRESET_KEY_APP: string = 'single_app';

export function normalizeHevcProfile(raw: string): HevcPref {
  const v = raw.trim().toLowerCase();
  if (v === 'auto' || v === 'main10' || v === 'main' || v === 'none') {
    return v as HevcPref;
  }
  return 'main';
}

function applyFactoryDefaults(p: ConnectionPreset): void {
  // Default AVC: many HarmonyOS devices/emulators lack OH_VideoDecoder HEVC.
  p.useH265 = false;
  p.hevcProfile = 'main';
  p.isAudio = false;
  p.keepWakeOnRunning = true;
  p.wakeOnConnect = true;
  p.lightOffOnConnect = false;
  p.showNavBarOnConnect = true;
}

export function createNormalRemotePreset(name: string): ConnectionPreset {
  const normal = new ConnectionPreset();
  normal.id = PRESET_ID_NORMAL;
  normal.name = name;
  normal.builtInKey = PRESET_KEY_NORMAL;
  normal.videoSource = 'display';
  normal.maxSize = 1600;
  normal.maxFps = 60;
  normal.maxVideoBit = 4;
  normal.listenClip = true;
  applyFactoryDefaults(normal);
  return normal;
}

export function createCameraMonitorPreset(name: string): ConnectionPreset {
  const camera = new ConnectionPreset();
  camera.id = PRESET_ID_CAMERA;
  camera.name = name;
  camera.builtInKey = PRESET_KEY_CAMERA;
  camera.videoSource = 'camera';
  camera.cameraFacing = 'back';
  camera.maxSize = 1280;
  camera.maxFps = 30;
  camera.maxVideoBit = 4;
  camera.listenClip = false;
  camera.changeToFullOnConnect = true;
  applyFactoryDefaults(camera);
  return camera;
}

export function createSingleAppPreset(name: string): ConnectionPreset {
  const app = new ConnectionPreset();
  app.id = PRESET_ID_APP;
  app.name = name;
  app.builtInKey = PRESET_KEY_APP;
  app.videoSource = 'display';
  app.maxSize = 1600;
  app.maxFps = 60;
  app.maxVideoBit = 4;
  app.listenClip = true;
  app.startApp = '';
  applyFactoryDefaults(app);
  return app;
}

export function createBuiltInPresets(): ConnectionPreset[] {
  return [
    createNormalRemotePreset('普通远程'),
    createCameraMonitorPreset('摄像头监控'),
    createSingleAppPreset('单应用镜像'),
  ];
}

export function factoryPresetByKey(key: string): ConnectionPreset | undefined {
  if (key === PRESET_KEY_NORMAL) {
    return createNormalRemotePreset('普通远程');
  }
  if (key === PRESET_KEY_CAMERA) {
    return createCameraMonitorPreset('摄像头监控');
  }
  if (key === PRESET_KEY_APP) {
    return createSingleAppPreset('单应用镜像');
  }
  return undefined;
}
