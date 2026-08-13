/**
 * UI-thread host for AdbProbeWorker.
 * - Loads HUKS-wrapped PEM on UI (no libadb_core.so)
 * - Posts TCP reachability / adb_connect_authed / shell getprop to Worker
 * - Resolves Promise; Home applies @State only after probeSeq check
 */

import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { AppSettings } from '../common/AppSettings';
import { ColdStartTrace } from '../common/ColdStartTrace';
import { Device } from '../model/Device';
import { loadAdbKeyMaterial } from './AdbKeyAssets';
import {
  ADB_PROBE_OP_SYSPROPS,
  ADB_PROBE_OP_TCP,
  AdbProbeReq,
  AdbProbeRsp,
  TcpReachResult,
} from './AdbProbeProtocol';
import { RemoteSystemProps } from './RemoteDeviceTypes';

const WORKER_PATH: string = 'entry/ets/workers/AdbProbeWorker.ets';

interface PendingProbe {
  seq: number;
  resolve: (value: AdbProbeRsp) => void;
  reject: (reason: Error) => void;
}

let workerInst: worker.ThreadWorker | null = null;
let nextSeq: number = 1;
let pending: PendingProbe[] = [];

function takePending(seq: number): PendingProbe | undefined {
  for (let i = 0; i < pending.length; i++) {
    if (pending[i].seq === seq) {
      const hit = pending[i];
      const next: PendingProbe[] = [];
      for (let j = 0; j < pending.length; j++) {
        if (j !== i) {
          next.push(pending[j]);
        }
      }
      pending = next;
      return hit;
    }
  }
  return undefined;
}

function rejectAll(err: Error): void {
  const copy = pending;
  pending = [];
  for (let i = 0; i < copy.length; i++) {
    copy[i].reject(err);
  }
}

function onWorkerMessage(e: MessageEvents): void {
  if (e.data === undefined || e.data === null) {
    return;
  }
  const rsp = e.data as AdbProbeRsp;
  const hit = takePending(rsp.seq);
  if (hit === undefined) {
    return;
  }
  ColdStartTrace.mark('AdbProbeHost.workerReply', rsp.ok ? 'ok' : rsp.detail);
  hit.resolve(rsp);
}

function onWorkerError(e: ErrorEvent): void {
  ColdStartTrace.mark('AdbProbeHost.workerError', e.message);
  rejectAll(new Error(e.message));
}

function ensureWorker(): worker.ThreadWorker {
  if (workerInst !== null) {
    return workerInst;
  }
  ColdStartTrace.mark('AdbProbeHost.workerCreate', 'before');
  const w = new worker.ThreadWorker(WORKER_PATH);
  w.onmessage = onWorkerMessage;
  w.onerror = onWorkerError;
  workerInst = w;
  ColdStartTrace.mark('AdbProbeHost.workerCreate', 'after');
  return w;
}

function postToWorker(req: AdbProbeReq): Promise<AdbProbeRsp> {
  const seq = req.seq;
  return new Promise<AdbProbeRsp>((resolve: (v: AdbProbeRsp) => void,
    reject: (e: Error) => void) => {
    pending.push({ seq: seq, resolve: resolve, reject: reject });
    try {
      const w = ensureWorker();
      ColdStartTrace.mark('AdbProbeHost.post', `seq=${seq} op=${req.op}`);
      w.postMessage(req);
    } catch (e) {
      takePending(seq);
      const msg = e instanceof Error ? e.message : String(e);
      reject(new Error(msg));
    }
  });
}

/** TCP connect on AdbProbeWorker. Timeout from Settings (default 500ms). */
export async function probeTcpReachable(
  host: string,
  port: number,
  timeoutMs?: number
): Promise<TcpReachResult> {
  const out = new TcpReachResult();
  const h = host.trim();
  if (h.length === 0 || port <= 0 || port > 65535) {
    out.detail = '地址或端口无效';
    return out;
  }
  const req = new AdbProbeReq();
  req.op = ADB_PROBE_OP_TCP;
  req.seq = nextSeq++;
  req.host = h;
  req.adbPort = port;
  req.timeoutMs = timeoutMs !== undefined && timeoutMs > 0
    ? timeoutMs
    : AppSettings.connectProbeTimeoutMs();
  const rsp = await postToWorker(req);
  out.ok = rsp.ok;
  out.detail = rsp.detail;
  return out;
}

export async function assertAdbTcpReachable(host: string, port: number): Promise<void> {
  const r = await probeTcpReachable(host, port);
  if (!r.ok) {
    throw new Error(r.detail);
  }
}

/**
 * Probe remote model/release/sdk via Worker-thread adbShellExec.
 * Worker TCP-preflights first. Does not import LiveMirror / libadb_core on the UI thread.
 */
export async function probeRemoteSystemPropsInWorker(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<RemoteSystemProps> {
  if (device.address.length === 0) {
    return { ok: false, model: '', release: '', sdk: '', detail: '无设备地址' };
  }
  const keys = await loadAdbKeyMaterial(ctx);
  const req = new AdbProbeReq();
  req.op = ADB_PROBE_OP_SYSPROPS;
  req.seq = nextSeq++;
  req.host = device.address;
  req.adbPort = device.adbPort;
  req.timeoutMs = AppSettings.connectProbeTimeoutMs();
  req.privateKeyPem = keys.privateKeyPem;
  if (keys.publicKeyLine !== undefined) {
    req.publicKeyLine = keys.publicKeyLine;
  }
  const rsp = await postToWorker(req);
  const props: RemoteSystemProps = {
    ok: rsp.ok,
    model: rsp.model,
    release: rsp.release,
    sdk: rsp.sdk,
    detail: rsp.detail,
  };
  return props;
}
