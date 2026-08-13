/**
 * Serializable probe request/response for AdbProbeWorker ↔ UI host.
 * No libadb_core.so dependency — safe for Home static import graph.
 */

export const ADB_PROBE_OP_TCP: string = 'tcp';
export const ADB_PROBE_OP_SYSPROPS: string = 'sysprops';

export class AdbProbeReq {
  op: string = ADB_PROBE_OP_SYSPROPS;
  seq: number = 0;
  host: string = '';
  adbPort: number = 0;
  /** TCP preflight timeout (ms). Host copies AppSettings; Worker must not read prefs. */
  timeoutMs: number = 500;
  privateKeyPem: string = '';
  /** Optional ADB public key line bytes. */
  publicKeyLine: ArrayBuffer | undefined = undefined;
}

export class AdbProbeRsp {
  op: string = ADB_PROBE_OP_SYSPROPS;
  seq: number = 0;
  ok: boolean = false;
  model: string = '';
  release: string = '';
  sdk: string = '';
  detail: string = '';
}

export class TcpReachResult {
  ok: boolean = false;
  detail: string = '';
}

export function isUnreachableDetail(detail: string): boolean {
  return detail.indexOf('设备不可达') >= 0;
}
