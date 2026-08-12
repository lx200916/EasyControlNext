/**
 * Stream / session preset (Android ConnectionPreset). Identity fields stay on Device.
 */

import { Device } from './Device';

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
    device.hevcProfile = this.hevcProfile === 'auto' || this.hevcProfile === 'main10'
      || this.hevcProfile === 'none' ? this.hevcProfile : 'main';
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

export function createBuiltInPresets(): ConnectionPreset[] {
  const normal = new ConnectionPreset();
  normal.id = PRESET_ID_NORMAL;
  normal.name = '普通远程';
  normal.builtInKey = 'normal_remote';
  normal.videoSource = 'display';
  normal.maxSize = 1600;
  normal.maxFps = 60;
  // Default AVC: many HarmonyOS devices/emulators lack OH_VideoDecoder HEVC.
  normal.useH265 = false;
  normal.listenClip = true;

  const camera = new ConnectionPreset();
  camera.id = PRESET_ID_CAMERA;
  camera.name = '摄像头监控';
  camera.builtInKey = 'camera_monitor';
  camera.videoSource = 'camera';
  camera.cameraFacing = 'back';
  camera.maxSize = 1280;
  camera.maxFps = 30;
  camera.useH265 = false;
  camera.listenClip = false;
  camera.changeToFullOnConnect = true;

  const app = new ConnectionPreset();
  app.id = PRESET_ID_APP;
  app.name = '单应用镜像';
  app.builtInKey = 'single_app';
  app.videoSource = 'display';
  app.maxSize = 1600;
  app.maxFps = 60;
  app.useH265 = false;
  app.listenClip = true;
  app.startApp = '';

  return [normal, camera, app];
}
