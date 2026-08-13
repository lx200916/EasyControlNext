/**
 * Wireless pairing + mDNS connect-port discovery (Android AdbTools / AdbServiceDiscovery parity).
 *
 * Important: HarmonyOS `serviceFound` usually does NOT include host/port — must call
 * `mdns.resolveLocalService` (same role as Android NsdManager.resolveService).
 *
 * QR flow (controller shows QR, Android scans):
 * 1) Generate WIFI:T:ADB;S:…;P:…;; and display QR
 * 2) Poll-discover `_adb-tls-pairing._tcp` matching S (Android advertises after scan)
 * 3) TCP SPAKE2 pair with P
 * 4) Optionally discover `_adb-tls-connect._tcp` for ADB port
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mdns } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import adbCore from 'libadb_core.so';
import { loadAdbKeyMaterial } from '../session/AdbKeyAssets';
import { AdbQrCredentials, AdbQrPairing } from './AdbQrPairing';

const DOMAIN: number = 0x0001;
const TAG: string = 'AdbPair';

/** OHOS mdns type strings must NOT end with a trailing '.' (unlike Android NsdManager). */
const SERVICE_CONNECT: string = '_adb-tls-connect._tcp';
const SERVICE_PAIRING: string = '_adb-tls-pairing._tcp';

/** Single mDNS window length — Android UI polls ~8s windows up to ~90s. */
const QR_POLL_WINDOW_MS: number = 8000;
/** Overall QR wait budget (scan → advertise → resolve). */
const QR_DEFAULT_BUDGET_MS: number = 90000;

interface NativePairResult {
  ok: boolean;
  host: string;
  pairPort: number;
  detail: string;
}

interface DiscoveryStartPayload {
  serviceInfo?: mdns.LocalServiceInfo;
  errorCode?: number;
}

export interface PairWirelessResult {
  ok: boolean;
  detail: string;
  /** Discovered connect port (>0) when fillAdbPort requested and mDNS found one. */
  connectPort: number;
  /** Host used for pairing / discovered via mDNS (QR flow). */
  host: string;
}

export interface MdnsEndpoint {
  host: string;
  port: number;
  serviceName: string;
}

/** Progress stages so the QR dialog can update instead of looking hung after Android pairs. */
export type QrPairStage =
  | 'waiting_scan'
  | 'found_pairing'
  | 'pairing'
  | 'discovering_connect'
  | 'done'
  | 'failed';

export type QrPairProgressFn = (stage: QrPairStage, detail: string) => void;

async function loadKeyMaterial(ctx: common.UIAbilityContext): Promise<Record<string, Object>> {
  const keys = await loadAdbKeyMaterial(ctx);
  const opts: Record<string, Object> = {
    'privateKeyPem': keys.privateKeyPem,
  };
  if (keys.publicKeyLine !== undefined) {
    opts['publicKeyLine'] = keys.publicKeyLine;
  }
  return opts;
}

/** Normalize pairing code (spaces stripped). */
export function normalizePairCode(code: string): string {
  try {
    return adbCore.adbNormalizePairCode(code) as string;
  } catch (_e) {
    return code.replace(/\s+/g, '').trim();
  }
}

function serviceNameMatches(name: string, filter: string | undefined): boolean {
  if (filter === undefined || filter.length === 0) {
    return true;
  }
  const lower = name.toLowerCase();
  const needle = filter.toLowerCase();
  return lower === needle || lower.indexOf(needle) >= 0;
}

/** Prefer IPv4; fall back to any non-empty address. */
function extractHostAddress(info: mdns.LocalServiceInfo): string {
  const host = info.host;
  if (host === undefined || host === null) {
    return '';
  }
  const addr = host.address;
  if (addr === undefined || addr === null) {
    return '';
  }
  const text = `${addr}`.trim();
  if (text.length === 0) {
    return '';
  }
  return text;
}

function endpointFromInfo(info: mdns.LocalServiceInfo): MdnsEndpoint | undefined {
  const name = info.serviceName ?? '';
  const host = extractHostAddress(info);
  const port = info.port ?? 0;
  if (host.length === 0 || port <= 0) {
    return undefined;
  }
  return { host: host, port: port, serviceName: name };
}

/**
 * Pair with Android wireless debugging (manual IP + pair port + code).
 * When fillAdbPort=true, also mDNS-discover `_adb-tls-connect._tcp` for the host.
 */
export async function pairWirelessManual(
  ctx: common.UIAbilityContext,
  host: string,
  pairPort: number,
  pairCode: string,
  deviceName: string,
  fillAdbPort: boolean
): Promise<PairWirelessResult> {
  const code = normalizePairCode(pairCode);
  if (host.trim().length === 0 || pairPort <= 0 || code.length === 0) {
    return {
      ok: false,
      detail: '请填写 IP、配对端口和配对码',
      connectPort: 0,
      host: '',
    };
  }
  try {
    const keys = await loadKeyMaterial(ctx);
    const opts: Record<string, Object> = {
      'host': host.trim(),
      'pairPort': pairPort,
      'pairCode': code,
      'privateKeyPem': keys['privateKeyPem'] as string,
      'deviceName': deviceName.trim().length > 0 ? deviceName.trim() : 'EasyControlNext',
      'timeoutSec': 20,
    };
    if (keys['publicKeyLine'] !== undefined) {
      opts['publicKeyLine'] = keys['publicKeyLine'];
    }
    const native = adbCore.adbPairWireless(opts) as NativePairResult;
    hilog.info(DOMAIN, TAG, 'pair ok %{public}s', native.detail);
    let connectPort = 0;
    if (fillAdbPort) {
      connectPort = await discoverTlsConnectPort(ctx, host.trim(), 4000);
    }
    return {
      ok: true,
      detail: native.detail,
      connectPort: connectPort,
      host: host.trim(),
    };
  } catch (e) {
    const err = e as Error;
    const msg = err !== undefined && err.message !== undefined ? err.message : String(e);
    hilog.error(DOMAIN, TAG, 'pair failed %{public}s', msg);
    return {
      ok: false,
      detail: msg,
      connectPort: 0,
      host: host.trim(),
    };
  }
}

/** Discover `_adb-tls-connect._tcp` for expectedHost; returns port or 0. */
export async function discoverTlsConnectPort(
  ctx: common.UIAbilityContext,
  expectedHost: string,
  timeoutMs: number
): Promise<number> {
  const endpoints = await discoverMdns(ctx, SERVICE_CONNECT, timeoutMs, undefined);
  if (endpoints.length === 0) {
    return 0;
  }
  if (expectedHost.length === 0) {
    return endpoints[0].port;
  }
  for (let i = 0; i < endpoints.length; i++) {
    if (endpoints[i].host === expectedHost) {
      return endpoints[i].port;
    }
  }
  return endpoints[0].port;
}

/**
 * Discover first `_adb-tls-pairing._tcp` matching serviceNameFilter (QR flow).
 * Uses short windows so a missed resolve / brief advertise still gets retries
 * (parity with Android DeviceEditorScreen 8s poll loop).
 */
export async function discoverFirstPairing(
  ctx: common.UIAbilityContext,
  serviceNameFilter: string,
  timeoutMs: number,
  onProgress?: QrPairProgressFn
): Promise<MdnsEndpoint | undefined> {
  const budget = timeoutMs > 0 ? timeoutMs : QR_DEFAULT_BUDGET_MS;
  const deadline = Date.now() + budget;
  let round = 0;
  hilog.info(DOMAIN, TAG, 'QR wait pairing name=%{public}s budget=%{public}d',
    serviceNameFilter, budget);
  while (Date.now() < deadline) {
    round += 1;
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      break;
    }
    const windowMs = Math.min(QR_POLL_WINDOW_MS, remaining);
    if (onProgress !== undefined) {
      onProgress('waiting_scan', `等待被控机扫描…（第 ${round} 轮）`);
    }
    const found = await discoverMdns(ctx, SERVICE_PAIRING, windowMs, serviceNameFilter);
    if (found.length > 0) {
      return found[0];
    }
    // Brief yield so UI can paint status between windows.
    await sleepMs(120);
  }
  return undefined;
}

/**
 * QR flow: wait for Android to scan our WIFI:T:ADB QR, advertise pairing mDNS, then pair + fill port.
 * Invokes onProgress so the UI can leave "waiting" as soon as TCP pair succeeds (Android already shows paired).
 */
export async function pairWithQrCredentials(
  ctx: common.UIAbilityContext,
  credentials: AdbQrCredentials,
  timeoutMs: number,
  onProgress?: QrPairProgressFn
): Promise<PairWirelessResult> {
  const budget = timeoutMs > 0 ? timeoutMs : QR_DEFAULT_BUDGET_MS;
  if (onProgress !== undefined) {
    onProgress('waiting_scan', '等待被控机扫描…');
  }
  const pairing = await discoverFirstPairing(ctx, credentials.serviceName, budget, onProgress);
  if (pairing === undefined) {
    const detail =
      '未发现被控机。请在被控机：开发者选项 → 无线调试 →「使用二维码配对」，扫描本页二维码，并保持同一 Wi‑Fi。';
    if (onProgress !== undefined) {
      onProgress('failed', detail);
    }
    return {
      ok: false,
      detail: detail,
      connectPort: 0,
      host: '',
    };
  }
  hilog.info(DOMAIN, TAG, 'QR found pairing %{public}s:%{public}d name=%{public}s',
    pairing.host, pairing.port, pairing.serviceName);
  if (onProgress !== undefined) {
    onProgress('found_pairing', `已发现被控机 ${pairing.host}:${pairing.port}，正在配对…`);
    onProgress('pairing', '正在完成加密配对…');
  }
  const paired = await pairWirelessManual(
    ctx,
    pairing.host,
    pairing.port,
    credentials.password,
    'EasyControlNext',
    false
  );
  if (!paired.ok) {
    if (onProgress !== undefined) {
      onProgress('failed', paired.detail);
    }
    return {
      ok: false,
      detail: paired.detail,
      connectPort: 0,
      host: pairing.host,
    };
  }
  // Pairing already succeeded on Android here — surface that before connect-port wait.
  if (onProgress !== undefined) {
    onProgress('discovering_connect', '配对成功，正在查找 ADB 连接端口…');
  }
  // Poll `_adb-tls-connect._tcp` — Android may take a moment to advertise after pair.
  let connectPort = 0;
  const connectDeadline = Date.now() + Math.min(12000, Math.max(6000, Math.floor(budget / 3)));
  while (connectPort <= 0 && Date.now() < connectDeadline) {
    const remaining = connectDeadline - Date.now();
    connectPort = await discoverTlsConnectPort(
      ctx,
      pairing.host,
      Math.min(4000, Math.max(1500, remaining))
    );
    if (connectPort <= 0) {
      await sleepMs(300);
    }
  }
  const detail = connectPort > 0
    ? `配对成功，连接端口 ${connectPort}（无线 TLS，请勿填配对端口）`
    : '配对成功。未自动发现连接端口：请在被控机无线调试页查看「IP 地址与端口」中的连接端口（不是配对端口）后手动填写。';
  if (onProgress !== undefined) {
    onProgress('done', detail);
  }
  return {
    ok: true,
    detail: detail,
    connectPort: connectPort,
    host: pairing.host,
  };
}

export async function encodeQrPixelMap(payload: string): Promise<image.PixelMap | undefined> {
  const text = payload.trim();
  if (text.length === 0) {
    hilog.warn(DOMAIN, TAG, 'QR encode skipped: empty payload');
    return undefined;
  }
  try {
    const options: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: 480,
      width: 480,
      margin: 2,
    };
    const pixelMap: image.PixelMap = await generateBarcode.createBarcode(text, options);
    return pixelMap;
  } catch (e) {
    const err = e as Error;
    const msg = err !== undefined && err.message !== undefined ? err.message : String(e);
    hilog.warn(DOMAIN, TAG, 'QR encode failed %{public}s', msg);
    return undefined;
  }
}

export { AdbQrPairing, AdbQrCredentials };

function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

function resolveMdnsService(
  ctx: common.UIAbilityContext,
  info: mdns.LocalServiceInfo
): Promise<mdns.LocalServiceInfo | undefined> {
  return new Promise<mdns.LocalServiceInfo | undefined>(
    (resolve: (v: mdns.LocalServiceInfo | undefined) => void) => {
      let settled = false;
      const settle = (v: mdns.LocalServiceInfo | undefined): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(v);
      };
      // Guard against resolveLocalService never calling back.
      const guard = setTimeout(() => {
        hilog.warn(DOMAIN, TAG, 'mdns resolve timeout name=%{public}s', info.serviceName ?? '');
        settle(undefined);
      }, 5000);
      try {
        mdns.resolveLocalService(ctx, info, (error: BusinessError, data: mdns.LocalServiceInfo) => {
          clearTimeout(guard);
          if (data !== undefined && data !== null) {
            settle(data);
            return;
          }
          const code = error !== undefined ? error.code : -1;
          const msg = error !== undefined ? error.message : '';
          hilog.warn(DOMAIN, TAG, 'mdns resolve err code=%{public}d %{public}s name=%{public}s',
            code, msg, info.serviceName ?? '');
          settle(undefined);
        });
      } catch (e) {
        clearTimeout(guard);
        hilog.warn(DOMAIN, TAG, 'mdns resolve threw %{public}s', String(e));
        settle(undefined);
      }
    });
}

function discoverMdns(
  ctx: common.UIAbilityContext,
  serviceType: string,
  timeoutMs: number,
  serviceNameFilter: string | undefined
): Promise<MdnsEndpoint[]> {
  return new Promise<MdnsEndpoint[]>((resolve: (v: MdnsEndpoint[]) => void) => {
    const found: MdnsEndpoint[] = [];
    const seenKeys: Record<string, boolean> = {};
    let done = false;
    let discovery: mdns.DiscoveryService | undefined = undefined;
    /** In-flight resolves must still be accepted after stop if they win the race. */
    let pendingResolves = 0;
    let timedOut = false;

    const finish = (): void => {
      if (done) {
        return;
      }
      done = true;
      try {
        if (discovery !== undefined) {
          discovery.stopSearchingMDNS();
          discovery.off('serviceFound');
          discovery.off('discoveryStart');
        }
      } catch (_e) {
        // ignore cleanup errors
      }
      hilog.info(DOMAIN, TAG, 'mdns done type=%{public}s count=%{public}d filter=%{public}s',
        serviceType, found.length, serviceNameFilter ?? '');
      resolve(found);
    };

    const timer = setTimeout(() => {
      timedOut = true;
      // If a resolve is in flight, give it a short grace instead of dropping a valid hit.
      if (pendingResolves > 0) {
        setTimeout(() => {
          finish();
        }, 1500);
      } else {
        finish();
      }
    }, timeoutMs);

    const acceptEndpoint = (ep: MdnsEndpoint): void => {
      if (done) {
        return;
      }
      if (!serviceNameMatches(ep.serviceName, serviceNameFilter)) {
        return;
      }
      const key = `${ep.host}:${ep.port}:${ep.serviceName}`;
      if (seenKeys[key]) {
        return;
      }
      seenKeys[key] = true;
      found.push(ep);
      hilog.info(DOMAIN, TAG, 'mdns hit %{public}s:%{public}d name=%{public}s',
        ep.host, ep.port, ep.serviceName);
      if (serviceNameFilter !== undefined && serviceNameFilter.length > 0) {
        clearTimeout(timer);
        finish();
      }
    };

    const handleFound = (info: mdns.LocalServiceInfo): void => {
      if (done) {
        return;
      }
      const name = info.serviceName ?? '';
      hilog.info(DOMAIN, TAG, 'mdns serviceFound name=%{public}s type=%{public}s',
        name, info.serviceType ?? serviceType);
      if (!serviceNameMatches(name, serviceNameFilter)) {
        return;
      }
      const direct = endpointFromInfo(info);
      if (direct !== undefined) {
        acceptEndpoint(direct);
        return;
      }
      // Typical path on real devices: name only until resolveLocalService fills host/port.
      pendingResolves += 1;
      void resolveMdnsService(ctx, info).then((resolved: mdns.LocalServiceInfo | undefined) => {
        pendingResolves = Math.max(0, pendingResolves - 1);
        if (done) {
          return;
        }
        if (resolved === undefined) {
          if (timedOut && pendingResolves === 0) {
            finish();
          }
          return;
        }
        const ep = endpointFromInfo(resolved);
        if (ep !== undefined) {
          acceptEndpoint(ep);
        } else {
          hilog.warn(DOMAIN, TAG, 'mdns resolved without host/port name=%{public}s',
            resolved.serviceName ?? name);
          if (timedOut && pendingResolves === 0) {
            finish();
          }
        }
      });
    };

    try {
      discovery = mdns.createDiscoveryService(ctx, serviceType);
      discovery.on('discoveryStart', (payload: DiscoveryStartPayload) => {
        if (payload.errorCode !== undefined && payload.errorCode !== 0) {
          hilog.error(DOMAIN, TAG, 'mdns discoveryStart failed type=%{public}s code=%{public}d',
            serviceType, payload.errorCode);
          clearTimeout(timer);
          finish();
        } else {
          hilog.info(DOMAIN, TAG, 'mdns discoveryStart ok type=%{public}s', serviceType);
        }
      });
      discovery.on('serviceFound', handleFound);
      discovery.startSearchingMDNS();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'mdns start failed %{public}s', String(e));
      clearTimeout(timer);
      finish();
    }
  });
}
