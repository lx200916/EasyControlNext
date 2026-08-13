/**
 * Lazy facades for Home — keep libadb_core.so off the cold-start / expand UI path.
 * TCP + sysprops run on AdbProbeWorker; app listing still lazy-imports LiveMirror on demand.
 */

import { common } from '@kit.AbilityKit';
import { ColdStartTrace } from '../common/ColdStartTrace';
import { Device } from '../model/Device';
import { probeRemoteSystemPropsInWorker, probeTcpReachable } from './AdbProbeHost';
import { InstalledAppRow, RemoteSystemProps } from './RemoteDeviceTypes';
import { TcpReachResult } from './AdbProbeProtocol';

interface LiveMirrorNs {
  listRemoteThirdPartyApps: (ctx: common.UIAbilityContext, device: Device) => Promise<InstalledAppRow[]>;
}

let listAppsMod: LiveMirrorNs | null = null;

async function loadLiveMirrorForListApps(): Promise<LiveMirrorNs> {
  if (listAppsMod !== null) {
    return listAppsMod;
  }
  ColdStartTrace.mark('LiveMirror.lazyImport', 'listApps before');
  const mod = await import('./LiveMirror') as LiveMirrorNs;
  listAppsMod = mod;
  ColdStartTrace.mark('LiveMirror.lazyImport', 'listApps after');
  return mod;
}

/** TCP reachability on AdbProbeWorker (not UI thread). */
export async function probeTcpReachableLazy(
  host: string,
  port: number
): Promise<TcpReachResult> {
  return await probeTcpReachable(host, port);
}

/** Device detail getprop — Worker thread (TCP then adb_connect_authed off UI). */
export async function probeRemoteSystemPropsLazy(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<RemoteSystemProps> {
  ColdStartTrace.mark('Home.probeRemote.worker', device.uuid);
  return await probeRemoteSystemPropsInWorker(ctx, device);
}

/** Temp-app picker — still uses LiveMirror; only loads native when user opens the sheet. */
export async function listRemoteThirdPartyAppsLazy(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<InstalledAppRow[]> {
  const mod = await loadLiveMirrorForListApps();
  return await mod.listRemoteThirdPartyApps(ctx, device);
}
