/**
 * Worker thread: TCP reachability + short-lived ADB shell probe (getprop).
 * Imports libadb_core.so here so dlopen + adb_connect_authed run off the UI thread.
 * NetworkKit TCP also runs here — never on the UI thread.
 */

import { ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { socket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import adbCore from 'libadb_core.so';
import {
  ADB_PROBE_OP_SYSPROPS,
  ADB_PROBE_OP_TCP,
  AdbProbeReq,
  AdbProbeRsp,
} from '../session/AdbProbeProtocol';

const DOMAIN: number = 0x0001;
const TAG: string = 'AdbProbeWorker';
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;
const TCP_TIMEOUT_FALLBACK_MS: number = 500;

const SYSPROPS_CMD: string =
  'echo "$(getprop ro.product.model)|$(getprop ro.build.version.release)|$(getprop ro.build.version.sdk)"';

function failRsp(seq: number, op: string, detail: string): AdbProbeRsp {
  const rsp = new AdbProbeRsp();
  rsp.op = op;
  rsp.seq = seq;
  rsp.ok = false;
  rsp.detail = detail;
  return rsp;
}

function stripBrackets(host: string): string {
  if (host.startsWith('[') && host.endsWith(']')) {
    return host.substring(1, host.length - 1);
  }
  return host;
}

function addressFamily(host: string): number {
  return host.indexOf(':') >= 0 ? 2 : 1;
}

async function probeTcp(req: AdbProbeReq): Promise<AdbProbeRsp> {
  const h = stripBrackets(req.host.trim());
  if (h.length === 0 || req.adbPort <= 0 || req.adbPort > 65535) {
    return failRsp(req.seq, ADB_PROBE_OP_TCP, '地址或端口无效');
  }
  const budget = req.timeoutMs > 0 ? req.timeoutMs : TCP_TIMEOUT_FALLBACK_MS;
  const family = addressFamily(h);
  const tcp = socket.constructTCPSocketInstance();
  const t0 = Date.now();
  try {
    const local: socket.NetAddress = {
      address: family === 2 ? '::' : '0.0.0.0',
      port: 0,
      family: family,
    };
    await tcp.bind(local);
    const remote: socket.NetAddress = {
      address: h,
      port: req.adbPort,
      family: family,
    };
    await tcp.connect({ address: remote, timeout: budget });
    hilog.info(DOMAIN, TAG, 'tcp ok +%{public}dms %{public}s:%{public}d', Date.now() - t0, h, req.adbPort);
    const rsp = new AdbProbeRsp();
    rsp.op = ADB_PROBE_OP_TCP;
    rsp.seq = req.seq;
    rsp.ok = true;
    return rsp;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(
      DOMAIN,
      TAG,
      'tcp fail +%{public}dms %{public}s:%{public}d %{public}s',
      Date.now() - t0,
      h,
      req.adbPort,
      msg
    );
    return failRsp(req.seq, ADB_PROBE_OP_TCP, `设备不可达 · ${h}:${req.adbPort}`);
  } finally {
    try {
      await tcp.close();
    } catch (_e) {
      // already closed / never opened
    }
  }
}

function parseSysprops(out: string): AdbProbeRsp {
  const rsp = new AdbProbeRsp();
  rsp.op = ADB_PROBE_OP_SYSPROPS;
  const line = out.trim().split('\n')[0] ?? '';
  const parts = line.split('|');
  rsp.model = (parts[0] ?? '').trim();
  rsp.release = (parts[1] ?? '').trim();
  rsp.sdk = (parts[2] ?? '').trim();
  if (rsp.model.length === 0 && rsp.release.length === 0 && rsp.sdk.length === 0) {
    rsp.ok = false;
    rsp.detail = '属性为空';
    return rsp;
  }
  rsp.ok = true;
  rsp.detail = '';
  return rsp;
}

interface WorkerAuthOpts {
  host: string;
  adbPort: number;
  privateKeyPem: string;
  publicKeyLine?: ArrayBuffer;
}

function handleSysprops(req: AdbProbeReq): AdbProbeRsp {
  if (req.host.length === 0 || req.adbPort <= 0) {
    return failRsp(req.seq, ADB_PROBE_OP_SYSPROPS, '无设备地址');
  }
  if (req.privateKeyPem.length === 0) {
    return failRsp(req.seq, ADB_PROBE_OP_SYSPROPS, '缺少 ADB 私钥');
  }
  try {
    const caps: string = adbCore.nativeCapabilities() as string;
    if (!caps.includes('adb_shell')) {
      return failRsp(req.seq, ADB_PROBE_OP_SYSPROPS, 'adbShellExec missing — rebuild libadb_core.so');
    }
    const opts: WorkerAuthOpts = {
      host: req.host,
      adbPort: req.adbPort,
      privateKeyPem: req.privateKeyPem,
    };
    if (req.publicKeyLine !== undefined) {
      opts.publicKeyLine = req.publicKeyLine;
    }
    const t0 = Date.now();
    const out = adbCore.adbShellExec(opts, SYSPROPS_CMD) as string;
    hilog.info(
      DOMAIN,
      TAG,
      'sysprops done +%{public}dms host=%{public}s',
      Date.now() - t0,
      req.host
    );
    const rsp = parseSysprops(out);
    rsp.seq = req.seq;
    return rsp;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'sysprops failed %{public}s', msg);
    return failRsp(req.seq, ADB_PROBE_OP_SYSPROPS, msg);
  }
}

async function dispatch(req: AdbProbeReq): Promise<AdbProbeRsp> {
  if (req.op === ADB_PROBE_OP_TCP) {
    return await probeTcp(req);
  }
  if (req.op === ADB_PROBE_OP_SYSPROPS) {
    const tcp = await probeTcp(req);
    if (!tcp.ok) {
      tcp.op = ADB_PROBE_OP_SYSPROPS;
      return tcp;
    }
    return handleSysprops(req);
  }
  return failRsp(req.seq, req.op, `unknown op ${req.op}`);
}

workerPort.onmessage = (e: MessageEvents): void => {
  if (e.data === undefined || e.data === null) {
    workerPort.postMessage(failRsp(0, ADB_PROBE_OP_SYSPROPS, 'invalid probe request'));
    return;
  }
  const req = e.data as AdbProbeReq;
  void dispatch(req).then((rsp: AdbProbeRsp) => {
    workerPort.postMessage(rsp);
  });
};

workerPort.onerror = (e: ErrorEvent): void => {
  hilog.error(DOMAIN, TAG, 'worker error %{public}s', e.message);
};
