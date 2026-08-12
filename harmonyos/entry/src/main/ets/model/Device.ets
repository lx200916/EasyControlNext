/**
 * Typed device model for the HarmonyOS controller.
 * Field semantics align with Android `entity/Device.java` for protocol/session options.
 * Persistence via relationalStore is Phase 6.
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
  useH265: boolean = false;
  hevcProfile: HevcPref = 'main';
  isAudio: boolean = false;
  maxSize: number = 1600;
  maxFps: number = 60;
  maxVideoBit: number = 4;
  listenClip: boolean = true;
  keepWakeOnRunning: boolean = true;
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
