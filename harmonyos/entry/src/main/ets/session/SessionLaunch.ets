/**
 * One-shot session launch options (manage-sheet overrides / open app picker).
 * Consumed by Session.aboutToAppear; not persisted.
 *
 * Shared contract with Home manage sheet / connect-override path:
 * - Prefer staging a full Device clone via `overrideDevice` (stream + connect flags).
 * - Manage「临时启动应用」→ set overrideDevice.startApp + videoSource=display (virtual display).
 * - Manage「使用摄像头」→ set overrideDevice.videoSource=camera + cameraFacing.
 * - Session toolbar app picker stays foreground-only (`launchRemoteAppForeground`);
 *   do not reuse that path for manage temp-app.
 * - Do not invent parallel option bags; extend Device fields instead.
 */

import { Device } from '../model/Device';

export class SessionLaunchOpts {
  /** When set, Session uses this clone instead of DeviceStore lookup. */
  overrideDevice: Device | undefined = undefined;
  /**
   * Open Session toolbar app picker after live connect (foreground launch only).
   * Not used by manage「临时启动应用」(that path uses overrideDevice.startApp).
   */
  openAppPicker: boolean = false;
}

let pending: SessionLaunchOpts | undefined = undefined;

export function stageSessionLaunch(opts: SessionLaunchOpts): void {
  pending = opts;
}

export function consumeSessionLaunch(): SessionLaunchOpts {
  const opts = pending !== undefined ? pending : new SessionLaunchOpts();
  pending = undefined;
  return opts;
}
