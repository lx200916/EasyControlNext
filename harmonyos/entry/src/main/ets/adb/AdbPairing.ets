/**
 * Wireless pairing + mDNS connect-port discovery (Android AdbTools / AdbServiceDiscovery parity).
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mdns } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import adbCore from 'libadb_core.so';
import { AdbQrCredentials, AdbQrPairing } from './AdbQrPairing';

const DOMAIN: number = 0x0001;
const TAG: string = 'AdbPair';

const SERVICE_CONNECT: string = '_adb-tls-connect._tcp';
const SERVICE_PAIRING: string = '_adb-tls-pairing._tcp';

interface NativePairResult {
  ok: boolean;
  host: string;
  pairPort: number;
  detail: string;
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

function utf8FromRaw(raw: Uint8Array): string {
  let s = '';
  for (let i = 0; i < raw.length; i++) {
    s += String.fromCharCode(raw[i]);
  }
  return s;
}

async function loadKeyMaterial(ctx: common.UIAbilityContext): Promise<Record<string, Object>> {
  const pemRaw = await ctx.resourceManager.getRawFileContent('adb_rsa_key.pem');
  const privateKeyPem = utf8FromRaw(pemRaw);
  const opts: Record<string, Object> = {
    'privateKeyPem': privateKeyPem,
  };
  try {
    const pub = await ctx.resourceManager.getRawFileContent('adb_rsa_key.pub');
    opts['publicKeyLine'] = pub.buffer.slice(pub.byteOffset, pub.byteOffset + pub.byteLength);
  } catch (_e) {
    // optional
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

/** Discover first `_adb-tls-pairing._tcp` matching serviceNameFilter (QR flow). */
export async function discoverFirstPairing(
  ctx: common.UIAbilityContext,
  serviceNameFilter: string,
  timeoutMs: number
): Promise<MdnsEndpoint | undefined> {
  const found = await discoverMdns(ctx, SERVICE_PAIRING, timeoutMs, serviceNameFilter);
  if (found.length > 0) {
    return found[0];
  }
  const retry = await discoverMdns(ctx, SERVICE_PAIRING, 1500, serviceNameFilter);
  return retry.length > 0 ? retry[0] : undefined;
}

/**
 * QR flow: wait for phone to scan our WIFI:T:ADB QR, advertise pairing mDNS, then pair + fill port.
 */
export async function pairWithQrCredentials(
  ctx: common.UIAbilityContext,
  credentials: AdbQrCredentials,
  timeoutMs: number
): Promise<PairWirelessResult> {
  const pairing = await discoverFirstPairing(ctx, credentials.serviceName, timeoutMs);
  if (pairing === undefined) {
    return {
      ok: false,
      detail: '未发现被控机。请在被控机：开发者选项 → 无线调试 →「使用二维码配对」，扫描本页二维码，并保持同一 Wi‑Fi。',
      connectPort: 0,
      host: '',
    };
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
    return {
      ok: false,
      detail: paired.detail,
      connectPort: 0,
      host: pairing.host,
    };
  }
  const connectPort = await discoverTlsConnectPort(ctx, pairing.host, Math.max(4000, Math.floor(timeoutMs / 2)));
  return {
    ok: true,
    detail: paired.detail,
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
  // Prefer createBarcode even when canIUse is unreliable on some emulators.
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

function discoverMdns(
  ctx: common.UIAbilityContext,
  serviceType: string,
  timeoutMs: number,
  serviceNameFilter: string | undefined
): Promise<MdnsEndpoint[]> {
  return new Promise<MdnsEndpoint[]>((resolve: (v: MdnsEndpoint[]) => void) => {
    const found: MdnsEndpoint[] = [];
    let done = false;
    let discovery: mdns.DiscoveryService | undefined = undefined;
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
      resolve(found);
    };
    const timer = setTimeout(() => {
      finish();
    }, timeoutMs);
    try {
      discovery = mdns.createDiscoveryService(ctx, serviceType);
      discovery.on('serviceFound', (info: mdns.LocalServiceInfo) => {
        if (done) {
          return;
        }
        const name = info.serviceName ?? '';
        if (serviceNameFilter !== undefined && serviceNameFilter.length > 0) {
          const filter = serviceNameFilter.toLowerCase();
          const lower = name.toLowerCase();
          if (lower !== filter && lower.indexOf(filter) < 0) {
            return;
          }
        }
        const host = info.host?.address ?? '';
        const port = info.port ?? 0;
        if (host.length === 0 || port <= 0) {
          return;
        }
        found.push({ host: host, port: port, serviceName: name });
        if (serviceNameFilter !== undefined && serviceNameFilter.length > 0) {
          clearTimeout(timer);
          finish();
        }
      });
      discovery.startSearchingMDNS();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'mdns start failed %{public}s', String(e));
      clearTimeout(timer);
      finish();
    }
  });
}
