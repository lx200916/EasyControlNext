/**
 * Typed device model for the HarmonyOS controller.
 * Field semantics align with Android `entity/Device.java` for protocol/session options.
 * Persisted via `data/DevicePrefs.ets` (preferences JSON blob).
 */
export type VideoSource = 'display' | 'camera';
export type CameraFacing = 'front' | 'back';
export type HevcPref = 'auto' | 'main' | 'main10' | 'none';

export class Device {
  uuid: string = '';
  name: string = '';
  address: string = '';
  /** ADB / connect port (wireless debugging). */
  adbPort: number = 5555;
  serverPort: number = 25166;
  /** Wireless pairing port (0 = unset). Written by pairing UI / Phase 3. */
  pairPort: number = 0;
  /** Pairing code/key stub. Written by pairing UI / Phase 3. */
  pairKey: string = '';
  /** Linked connection preset id, or empty when custom / detached (Android Device.presetId). */
  presetId: string = '';
  /** Default H.265 (Android parity). Session falls back to AVC if OHOS lacks HEVC. */
  useH265: boolean = true;
  hevcProfile: HevcPref = 'main';
  isAudio: boolean = false;
  maxSize: number = 1600;
  maxFps: number = 60;
  maxVideoBit: number = 4;
  listenClip: boolean = true;
  keepWakeOnRunning: boolean = true;
  /** Auto-connect this device when the controller app starts. */
  connectOnStart: boolean = false;
  /** Prefer fullscreen session chrome on connect (parity flag; Harmony session is fullscreen). */
  changeToFullOnConnect: boolean = false;
  /** After live main socket is up, send power mode 1 (server injects KEYCODE_WAKEUP). */
  wakeOnConnect: boolean = true;
  /** After connect, turn controlled display backlight off (delayed). */
  lightOffOnConnect: boolean = false;
  /** Initial session nav-bar visibility (controller chrome). */
  showNavBarOnConnect: boolean = true;
  /** Send fixed WxH resolution control event after connect. */
  customResolutionOnConnect: boolean = false;
  customResolutionWidth: number = 1080;
  customResolutionHeight: number = 2400;
  /** On session close: lock controlled device (power mode 0). */
  lockOnClose: boolean = false;
  /** On session close: restore backlight when not locking. */
  lightOnClose: boolean = false;
  videoSource: VideoSource = 'display';
  cameraFacing: CameraFacing = 'back';
  virtualWidth: number = 0;
  virtualHeight: number = 0;
  virtualDpi: number = 0;
  startApp: string = '';

  constructor(uuid?: string) {
    if (uuid !== undefined) {
      this.uuid = uuid;
    }
  }
}

/** Shown while `name` is empty, until the first successful getprop probe. */
export const DEVICE_NAME_PENDING: string = '等待探测…';

export function isLazyDeviceName(name: string): boolean {
  return name.trim().length === 0;
}

export function displayDeviceName(device: Device): string {
  const n = device.name.trim();
  return n.length > 0 ? n : DEVICE_NAME_PENDING;
}
