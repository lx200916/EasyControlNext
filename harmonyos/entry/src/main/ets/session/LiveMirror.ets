/**
 * On-device Gate D live mirror: jar from rawfile, ADB RSA from HUKS-wrapped filesDir.
 * Assets are cached after first load so Connect does not re-read rawfiles / re-copy buffers.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import adbCore from 'libadb_core.so';
import { AppErrorLog } from '../common/AppErrorLog';
import { Device } from '../model/Device';
import { loadAdbKeyMaterial } from './AdbKeyAssets';
import { assertAdbTcpReachable } from './AdbProbeHost';
import {
  AdbOpResult,
  InstalledAppRow,
  RemoteSystemProps,
} from './RemoteDeviceTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'LiveMirror';
const APP_VERSION_CODE: number = 10014;

export interface LiveStatus {
  phase: string;
  detail: string;
  mode: string;
  width: number;
  height: number;
  useH265: boolean;
  ausFed: number;
  firstFrame: boolean;
  live: boolean;
  canAudio: boolean;
  useOpus: boolean;
  audioStarted: boolean;
  audioFrames: number;
  audioDetail: string;
}

interface LiveStartOpts {
  host: string;
  adbPort: number;
  serverPort: number;
  surfaceId: string;
  jarBytes: ArrayBuffer;
  privateKeyPem: string;
  publicKeyLine?: ArrayBuffer;
  appVersionCode: number;
  maxSize: number;
  maxFps: number;
  maxVideoBit: number;
  listenClip: boolean;
  isAudio: boolean;
  keepAwake: boolean;
  supportH265: boolean;
  virtualWidth: number;
  virtualHeight: number;
  virtualDpi: number;
}

interface CachedLiveAssets {
  jarBytes: ArrayBuffer;
  privateKeyPem: string;
  publicKeyLine?: ArrayBuffer;
}

let cachedAssets: CachedLiveAssets | null = null;
let lastLoggedPhase: string = '';
let connectT0Ms: number = 0;

async function loadRawCopy(ctx: common.UIAbilityContext, name: string): Promise<ArrayBuffer> {
  const raw = await ctx.resourceManager.getRawFileContent(name);
  const copy = new ArrayBuffer(raw.byteLength);
  new Uint8Array(copy).set(raw);
  return copy;
}

/** Prefetch jar + RSA while Session waits for XComponent surface (parallel with UI). */
export async function prefetchLiveMirrorAssets(ctx: common.UIAbilityContext): Promise<void> {
  if (cachedAssets !== null) {
    return;
  }
  await loadLiveAssets(ctx);
}

async function loadLiveAssets(ctx: common.UIAbilityContext): Promise<CachedLiveAssets> {
  if (cachedAssets !== null) {
    return cachedAssets;
  }
  const jar = await loadRawCopy(ctx, 'easycontrolnext_server.jar');
  const keys = await loadAdbKeyMaterial(ctx);
  const assets: CachedLiveAssets = {
    jarBytes: jar,
    privateKeyPem: keys.privateKeyPem,
  };
  if (keys.publicKeyLine !== undefined) {
    assets.publicKeyLine = keys.publicKeyLine;
  }
  cachedAssets = assets;
  hilog.info(DOMAIN, TAG, 'assets cached jar=%{public}d huks=1', jar.byteLength);
  return assets;
}

/**
 * @param forceAvc When true, ignore device.useH265 and request AVC (HarmonyOS often lacks HEVC).
 */
export async function startLiveMirror(
  ctx: common.UIAbilityContext,
  device: Device,
  surfaceId: string,
  forceAvc: boolean = false
): Promise<LiveStatus> {
  connectT0Ms = Date.now();
  lastLoggedPhase = '';
  const supportH265 = forceAvc ? false : device.useH265;
  const videoSource = device.videoSource === 'camera' ? 'camera' : 'display';
  const cameraFacing = device.cameraFacing === 'front' ? 'front' : 'back';
  // Camera ignores single-app VD; otherwise pass startApp for virtual display.
  const startApp = videoSource === 'camera' ? '' : (device.startApp ?? '').trim();
  hilog.info(
    DOMAIN,
    TAG,
    'connect_t0 %{public}s:%{public}d server=%{public}d surface=%{public}s h265=%{public}s forceAvc=%{public}s src=%{public}s facing=%{public}s startApp=%{public}s vd=%{public}dx%{public}d@%{public}d',
    device.address,
    device.adbPort,
    device.serverPort,
    surfaceId,
    supportH265 ? '1' : '0',
    forceAvc ? '1' : '0',
    videoSource,
    cameraFacing,
    startApp,
    device.virtualWidth,
    device.virtualHeight,
    device.virtualDpi
  );

  await assertAdbTcpReachable(device.address, device.adbPort);

  const assets = await loadLiveAssets(ctx);

  const opts: LiveStartOpts = {
    host: device.address,
    adbPort: device.adbPort,
    serverPort: device.serverPort,
    surfaceId: surfaceId,
    jarBytes: assets.jarBytes,
    privateKeyPem: assets.privateKeyPem,
    appVersionCode: APP_VERSION_CODE,
    maxSize: device.maxSize,
    maxFps: device.maxFps,
    maxVideoBit: device.maxVideoBit,
    listenClip: device.listenClip,
    isAudio: device.isAudio,
    keepAwake: device.keepWakeOnRunning,
    supportH265: supportH265,
    virtualWidth: device.virtualWidth,
    virtualHeight: device.virtualHeight,
    virtualDpi: device.virtualDpi,
  };
  if (assets.publicKeyLine !== undefined) {
    opts.publicKeyLine = assets.publicKeyLine;
  }

  hilog.info(
    DOMAIN,
    TAG,
    'live start jar=%{public}d +%{public}dms (native bg thread) startApp=%{public}s',
    assets.jarBytes.byteLength,
    Date.now() - connectT0Ms,
    startApp
  );

  // Source/startApp as discrete NAPI string args — object fields were dropped by binding.
  const st = adbCore.liveSessionStart(opts, videoSource, cameraFacing, startApp) as Record<string, Object>;
  return mapStatus(st);
}

/** True when native failed because OHOS has no HEVC decoder for this stream. */
export function isHevcDecoderUnavailable(detail: string): boolean {
  return detail.indexOf('mime=video/hevc') >= 0 &&
    detail.indexOf('CreateByMime returned null') >= 0;
}

export function pollLiveStatus(): LiveStatus {
  const st = adbCore.liveSessionStatus() as Record<string, Object>;
  const mapped = mapStatus(st);
  logPhaseTiming(mapped);
  return mapped;
}

/**
 * OH_VideoDecoder_CreateByMime must run on the NAPI/JS thread.
 * Call when poll shows phase === 'configuring' (live worker has CSD ready).
 */
export function attachLiveDecoder(): LiveStatus {
  try {
    const st = adbCore.liveSessionAttachDecoder() as Record<string, Object>;
    const mapped = mapStatus(st);
    hilog.info(
      DOMAIN,
      TAG,
      'attachDecoder ok phase=%{public}s %{public}dx%{public}d h265=%{public}s',
      mapped.phase,
      mapped.width,
      mapped.height,
      mapped.useH265 ? '1' : '0'
    );
    logPhaseTiming(mapped);
    return mapped;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'attachDecoder failed %{public}s', msg);
    AppErrorLog.e('decoder', msg);
    return pollLiveStatus();
  }
}

function logPhaseTiming(st: LiveStatus): void {
  if (connectT0Ms <= 0) {
    return;
  }
  const elapsed = Date.now() - connectT0Ms;
  if (st.phase !== lastLoggedPhase) {
    lastLoggedPhase = st.phase;
    hilog.info(
      DOMAIN,
      TAG,
      'phase=%{public}s +%{public}dms detail=%{public}s',
      st.phase,
      elapsed,
      st.detail
    );
  }
  if (st.firstFrame && lastLoggedPhase !== 'first_frame_ok') {
    lastLoggedPhase = 'first_frame_ok';
    hilog.info(
      DOMAIN,
      TAG,
      'first_frame +%{public}dms %{public}dx%{public}d aus=%{public}d',
      elapsed,
      st.width,
      st.height,
      st.ausFed
    );
  }
}

export function writeLiveControl(packet: ArrayBuffer): boolean {
  try {
    return Boolean(adbCore.liveSessionWriteControl(packet));
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'writeControl failed %{public}s', msg);
    return false;
  }
}

export function stopLiveMirror(): void {
  try {
    adbCore.liveSessionStop();
  } catch (_e) {
    // ignore
  }
  connectT0Ms = 0;
  lastLoggedPhase = '';
}

export interface ScreencapResult {
  ok: boolean;
  png: ArrayBuffer | null;
  detail: string;
}

interface AdbAuthOpts {
  host: string;
  adbPort: number;
  privateKeyPem: string;
  publicKeyLine?: ArrayBuffer;
}

async function buildAuthOpts(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<AdbAuthOpts> {
  const assets = await loadLiveAssets(ctx);
  const opts: AdbAuthOpts = {
    host: device.address,
    adbPort: device.adbPort,
    privateKeyPem: assets.privateKeyPem,
  };
  if (assets.publicKeyLine !== undefined) {
    opts.publicKeyLine = assets.publicKeyLine;
  }
  return opts;
}

/** Fail fast with a rebuild hint when the staged .so predates shell helpers. */
function shellExec(opts: AdbAuthOpts, command: string): string {
  const caps: string = adbCore.nativeCapabilities() as string;
  if (!caps.includes('adb_shell')) {
    throw new Error('adbShellExec missing — rebuild libadb_core.so (adb_shell)');
  }
  return adbCore.adbShellExec(opts, command) as string;
}

function isSafePackageName(pkg: string): boolean {
  if (pkg.length < 3 || pkg.length > 200 || !pkg.includes('.')) {
    return false;
  }
  for (let i = 0; i < pkg.length; i++) {
    const c = pkg.charCodeAt(i);
    const ok =
      (c >= 97 && c <= 122) ||
      (c >= 65 && c <= 90) ||
      (c >= 48 && c <= 57) ||
      c === 46 ||
      c === 95;
    if (!ok) {
      return false;
    }
  }
  return true;
}

/**
 * Expand the controlled device notification shade (status bar panel).
 * Uses `cmd statusbar` (API 29+) with legacy `service call statusbar 1` fallback.
 * Short-lived ADB shell — does not interrupt Gate D live mirror.
 */
export async function expandRemoteNotificationPanel(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<AdbOpResult> {
  if (device.address.length === 0) {
    return { ok: false, detail: '无设备地址' };
  }
  try {
    const opts = await buildAuthOpts(ctx, device);
    const out = shellExec(
      opts,
      'cmd statusbar expand-notifications 2>/dev/null || service call statusbar 1'
    );
    hilog.info(
      DOMAIN,
      TAG,
      'expand notifications out=%{public}s',
      out.trim().slice(0, 120)
    );
    return { ok: true, detail: '已展开通知栏' };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'expand notifications failed %{public}s', msg);
    return { ok: false, detail: msg };
  }
}

/**
 * MVP screenshot: separate short-lived ADB auth + `screencap -p | base64`.
 * Does not interrupt the live Gate D session.
 */
export async function captureRemoteScreenshot(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<ScreencapResult> {
  if (device.address.length === 0) {
    return { ok: false, png: null, detail: '无设备地址' };
  }
  try {
    const opts = await buildAuthOpts(ctx, device);
    const png = adbCore.adbScreencapPng(opts) as ArrayBuffer;
    if (png === undefined || png === null || png.byteLength < 8) {
      return { ok: false, png: null, detail: '截图为空' };
    }
    hilog.info(DOMAIN, TAG, 'screencap ok bytes=%{public}d', png.byteLength);
    return { ok: true, png: png, detail: `PNG ${png.byteLength} B` };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'screencap failed %{public}s', msg);
    AppErrorLog.e('screencap', msg);
    return { ok: false, png: null, detail: msg };
  }
}

export interface SyncPullFileResult {
  ok: boolean;
  data: ArrayBuffer | null;
  remotePath: string;
  sha256Hex: string;
  byteLen: number;
  detail: string;
}

function basenameOfRemote(path: string): string {
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    return 'pulled.bin';
  }
  const slash = trimmed.lastIndexOf('/');
  if (slash < 0 || slash >= trimmed.length - 1) {
    return 'pulled.bin';
  }
  const name = trimmed.substring(slash + 1);
  return name.length > 0 ? name : 'pulled.bin';
}

/** Undo shell/C-style escapes from `ls -b` / non-TTY ls (e.g. `My\\ File` → `My File`). */
function unescapeLsName(raw: string): string {
  let out = '';
  let i = 0;
  while (i < raw.length) {
    const ch = raw.charAt(i);
    if (ch !== '\\' || i + 1 >= raw.length) {
      out += ch;
      i++;
      continue;
    }
    const n = raw.charAt(i + 1);
    if (n >= '0' && n <= '7') {
      let oct = n;
      let j = i + 2;
      while (j < raw.length && oct.length < 3) {
        const d = raw.charAt(j);
        if (d < '0' || d > '7') {
          break;
        }
        oct += d;
        j++;
      }
      out += String.fromCharCode(parseInt(oct, 8));
      i = j;
      continue;
    }
    if (n === 'n') {
      out += '\n';
    } else if (n === 't') {
      out += '\t';
    } else if (n === 'r') {
      out += '\r';
    } else if (n === 'b') {
      out += '\b';
    } else if (n === 'f') {
      out += '\f';
    } else if (n === 'v') {
      out += String.fromCharCode(11);
    } else if (n === 'a') {
      out += String.fromCharCode(7);
    } else if (n === 'e') {
      out += String.fromCharCode(27);
    } else {
      // `\ ` `\\` `\'` etc. — keep the escaped character literally.
      out += n;
    }
    i += 2;
  }
  return out;
}

/**
 * Short-lived ADB sync RECV pull. Does not interrupt the live Gate D session.
 */
export async function pullRemoteFile(
  ctx: common.UIAbilityContext,
  device: Device,
  remotePath: string
): Promise<SyncPullFileResult> {
  // Undo leftover `ls -b` space escapes so RECV uses the real remote name.
  const path = unescapeLsName(remotePath.trim());
  if (device.address.length === 0) {
    return {
      ok: false,
      data: null,
      remotePath: path,
      sha256Hex: '',
      byteLen: 0,
      detail: '无设备地址',
    };
  }
  if (path.length === 0 || !path.startsWith('/')) {
    return {
      ok: false,
      data: null,
      remotePath: path,
      sha256Hex: '',
      byteLen: 0,
      detail: '请输入绝对路径，例如 /sdcard/Download/a.png',
    };
  }
  try {
    const caps: string = adbCore.nativeCapabilities() as string;
    if (!caps.includes('adb_sync_pull')) {
      throw new Error('adbSyncPull missing — rebuild libadb_core.so (adb_sync_pull)');
    }
    const opts = await buildAuthOpts(ctx, device);
    const result = adbCore.adbSyncPull(opts, path) as Record<string, Object>;
    const data = result['data'] as ArrayBuffer;
    const sha = String(result['sha256Hex'] ?? result['sha256_hex'] ?? '');
    const byteLen = Number(result['byteLen'] ?? result['byte_len'] ?? (data?.byteLength ?? 0));
    if (data === undefined || data === null || data.byteLength === 0) {
      return {
        ok: false,
        data: null,
        remotePath: path,
        sha256Hex: sha,
        byteLen: 0,
        detail: '拉取结果为空',
      };
    }
    hilog.info(DOMAIN, TAG, 'sync pull ok bytes=%{public}d path=%{public}s', data.byteLength, path);
    return {
      ok: true,
      data: data,
      remotePath: path,
      sha256Hex: sha,
      byteLen: byteLen,
      detail: `${basenameOfRemote(path)} · ${byteLen} B`,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'sync pull failed %{public}s', msg);
    AppErrorLog.e('sync-pull', msg);
    return {
      ok: false,
      data: null,
      remotePath: path,
      sha256Hex: '',
      byteLen: 0,
      detail: msg,
    };
  }
}

export function remotePullBasename(remotePath: string): string {
  return basenameOfRemote(remotePath);
}

export interface RemoteDirEntry {
  name: string;
  path: string;
  isDirectory: boolean;
}

export interface RemoteDirListResult {
  ok: boolean;
  path: string;
  entries: RemoteDirEntry[];
  detail: string;
}

function shellQuotePath(path: string): string {
  let out = "'";
  for (let i = 0; i < path.length; i++) {
    const ch = path.charAt(i);
    if (ch === "'") {
      out += "'\\''";
    } else {
      out += ch;
    }
  }
  out += "'";
  return out;
}

function basenameFromAbsolute(absPath: string): string {
  const p = absPath.trim();
  if (p.length === 0) {
    return '';
  }
  const slash = p.lastIndexOf('/');
  if (slash < 0 || slash >= p.length - 1) {
    return p;
  }
  return p.substring(slash + 1);
}

function normalizeRemoteDir(path: string): string {
  let p = path.trim();
  if (p.length === 0) {
    return '/sdcard';
  }
  if (!p.startsWith('/')) {
    p = `/${p}`;
  }
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p.length > 0 ? p : '/';
}

export function parentRemoteDir(path: string): string {
  const p = normalizeRemoteDir(path);
  if (p === '/') {
    return '/';
  }
  const slash = p.lastIndexOf('/');
  if (slash <= 0) {
    return '/';
  }
  return p.substring(0, slash);
}

export function joinRemotePath(dir: string, name: string): string {
  const base = normalizeRemoteDir(dir);
  if (base === '/') {
    return `/${name}`;
  }
  return `${base}/${name}`;
}

/**
 * Browse a remote directory. Prefer `find` (literal names, preserves spaces);
 * fall back to `ls -1Ap` with C/shell-escape unescaping (`My\\ File` → `My File`).
 */
export async function listRemoteDirectory(
  ctx: common.UIAbilityContext,
  device: Device,
  remoteDir: string
): Promise<RemoteDirListResult> {
  const path = normalizeRemoteDir(remoteDir);
  if (device.address.length === 0) {
    return { ok: false, path: path, entries: [], detail: '无设备地址' };
  }
  try {
    const opts = await buildAuthOpts(ctx, device);
    const quoted = shellQuotePath(path);
    // Probe find without swallowing stderr — empty+missing-find must not look like empty dir.
    const findProbe = shellExec(opts, `find ${quoted} -maxdepth 0 2>&1`);
    const probeTrim = findProbe.trim();
    const probeLower = probeTrim.toLowerCase();
    const findAvailable = probeTrim.length > 0 &&
      !probeLower.includes('not found') &&
      !probeLower.includes('no such file') &&
      !probeLower.startsWith('find:') &&
      !probeLower.includes('permission denied');

    if (findAvailable) {
      const findDirs = shellExec(
        opts,
        `find ${quoted} -maxdepth 1 -mindepth 1 -type d 2>/dev/null`
      );
      const findFiles = shellExec(
        opts,
        `find ${quoted} -maxdepth 1 -mindepth 1 ! -type d 2>/dev/null`
      );
      const dirs: RemoteDirEntry[] = [];
      const files: RemoteDirEntry[] = [];
      const dirLines = findDirs.split('\n');
      for (let i = 0; i < dirLines.length; i++) {
        const abs = dirLines[i].trim();
        if (abs.length === 0) {
          continue;
        }
        const name = basenameFromAbsolute(abs);
        if (name.length === 0 || name === '.' || name === '..') {
          continue;
        }
        dirs.push({
          name: name,
          path: joinRemotePath(path, name),
          isDirectory: true,
        });
      }
      const fileLines = findFiles.split('\n');
      for (let i = 0; i < fileLines.length; i++) {
        const abs = fileLines[i].trim();
        if (abs.length === 0) {
          continue;
        }
        const name = basenameFromAbsolute(abs);
        if (name.length === 0 || name === '.' || name === '..') {
          continue;
        }
        files.push({
          name: name,
          path: joinRemotePath(path, name),
          isDirectory: false,
        });
      }
      const entries = dirs.concat(files);
      return { ok: true, path: path, entries: entries, detail: `${entries.length}` };
    }

    if (probeLower.includes('no such file') || probeLower.includes('not a directory') ||
      probeLower.includes('permission denied')) {
      return { ok: false, path: path, entries: [], detail: probeTrim.split('\n')[0] };
    }

    // Fallback: ls — may C-escape spaces as `\ `; unescape before join/pull.
    const out = shellExec(opts, `ls -1Ap ${quoted} 2>&1`);
    const trimmed = out.trim();
    if (trimmed.length === 0) {
      return { ok: true, path: path, entries: [], detail: '' };
    }
    const lower = trimmed.toLowerCase();
    if (lower.includes('no such file') || lower.includes('not a directory') ||
      lower.includes('permission denied')) {
      return { ok: false, path: path, entries: [], detail: trimmed.split('\n')[0] };
    }
    const lines = trimmed.split('\n');
    const dirs: RemoteDirEntry[] = [];
    const files: RemoteDirEntry[] = [];
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('ls:')) {
        return { ok: false, path: path, entries: [], detail: line };
      }
      let isDirectory = false;
      if (line.endsWith('/')) {
        isDirectory = true;
        line = line.substring(0, line.length - 1);
      }
      line = unescapeLsName(line);
      if (line === '.' || line === '..' || line.length === 0) {
        continue;
      }
      const last = line.charAt(line.length - 1);
      if (last === '*' || last === '@' || last === '|' || last === '=') {
        line = line.substring(0, line.length - 1);
        line = unescapeLsName(line);
      }
      if (line.length === 0) {
        continue;
      }
      const entry: RemoteDirEntry = {
        name: line,
        path: joinRemotePath(path, line),
        isDirectory: isDirectory,
      };
      if (isDirectory) {
        dirs.push(entry);
      } else {
        files.push(entry);
      }
    }
    const entries = dirs.concat(files);
    return { ok: true, path: path, entries: entries, detail: `${entries.length}` };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'list dir failed %{public}s', msg);
    return { ok: false, path: path, entries: [], detail: msg };
  }
}

function firstToken(raw: string): string {
  const s = raw.trim();
  if (s.length === 0) {
    return '';
  }
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 32 || c === 9 || c === 10 || c === 13) {
      return s.substring(0, i);
    }
  }
  return s;
}

function isWeakAppLabel(label: string, pkg: string): boolean {
  if (label.length === 0 || label === 'null') {
    return true;
  }
  if (label === pkg) {
    return true;
  }
  const dot = pkg.lastIndexOf('.');
  if (dot >= 0 && label === pkg.substring(dot + 1)) {
    return true;
  }
  return false;
}

/** Trim dumpsys / activity-dump label values (`Foo icon=0x…`). */
function cleanDumpLabel(raw: string): string {
  let label = raw.trim();
  if (label.length === 0 || label === 'null' || label.startsWith('null ')) {
    return '';
  }
  const iconIdx = label.indexOf(' icon=');
  if (iconIdx > 0) {
    label = label.substring(0, iconIdx).trim();
  }
  const lrIdx = label.indexOf(' labelRes=');
  if (lrIdx > 0) {
    label = label.substring(0, lrIdx).trim();
  }
  if (label === 'null' || label.length === 0) {
    return '';
  }
  return label;
}

function captureAfterKey(line: string, key: string): string {
  const idx = line.indexOf(key);
  if (idx < 0) {
    return '';
  }
  return cleanDumpLabel(line.substring(idx + key.length));
}

class LabelMap {
  private keys: string[] = [];
  private values: string[] = [];

  get(pkg: string): string {
    const i = this.keys.indexOf(pkg);
    return i >= 0 ? this.values[i] : '';
  }

  set(pkg: string, label: string): void {
    const i = this.keys.indexOf(pkg);
    if (i >= 0) {
      this.values[i] = label;
      return;
    }
    this.keys.push(pkg);
    this.values.push(label);
  }

  labeledCount(): number {
    return this.keys.length;
  }
}

/**
 * Match Android AdbTools shell fallback:
 * `cmd package query-activities` → nonLocalizedLabel / applicationLabel.
 */
function enrichLabelsFromActivityDump(dump: string, labels: LabelMap): void {
  let currentPkg: string = '';
  const lines = dump.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const pkgRaw = captureAfterKey(line, 'packageName=');
    const pkg = firstToken(pkgRaw);
    if (pkg.length > 0 && isSafePackageName(pkg)) {
      currentPkg = pkg;
    }
    if (currentPkg.length === 0) {
      continue;
    }
    const appLabel = captureAfterKey(line, 'applicationLabel=');
    if (appLabel.length > 0) {
      labels.set(currentPkg, appLabel);
      continue;
    }
    const nl = captureAfterKey(line, 'nonLocalizedLabel=');
    if (nl.length > 0 && isWeakAppLabel(labels.get(currentPkg), currentPkg)) {
      const token = firstToken(nl);
      if (token.length > 0 && token !== 'null') {
        labels.set(currentPkg, token);
      }
    }
  }
}

/** Match Android `Package [pkg]` + applicationLabel / nonLocalizedLabel dump lines. */
function enrichLabelsFromPackageDump(dump: string, labels: LabelMap): void {
  let currentPkg: string = '';
  const lines = dump.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const bracket = line.indexOf('Package [');
    if (bracket >= 0) {
      const start = bracket + 'Package ['.length;
      const end = line.indexOf(']', start);
      if (end > start) {
        const pkg = line.substring(start, end).trim();
        if (isSafePackageName(pkg)) {
          currentPkg = pkg;
        }
      }
      continue;
    }
    if (currentPkg.length === 0) {
      continue;
    }
    const fromApp = captureAfterKey(line, 'applicationLabel=');
    if (fromApp.length > 0) {
      labels.set(currentPkg, fromApp);
      continue;
    }
    const fromNl = captureAfterKey(line, 'nonLocalizedLabel=');
    if (fromNl.length > 0 && isWeakAppLabel(labels.get(currentPkg), currentPkg)) {
      const token = firstToken(fromNl);
      if (token.length > 0 && token !== 'null') {
        labels.set(currentPkg, token);
      }
    }
  }
}

function remoteServerJarPath(): string {
  return `/data/local/tmp/easycontrolnext_server_${APP_VERSION_CODE}.jar`;
}

function sortInstalledAppRows(rows: InstalledAppRow[]): InstalledAppRow[] {
  rows.sort((a: InstalledAppRow, b: InstalledAppRow) => {
    const la = a.label.toLowerCase();
    const lb = b.label.toLowerCase();
    if (la < lb) {
      return -1;
    }
    if (la > lb) {
      return 1;
    }
    return a.packageName < b.packageName ? -1 : a.packageName > b.packageName ? 1 : 0;
  });
  return rows;
}

function countStrongLabels(rows: InstalledAppRow[]): number {
  let n = 0;
  for (let i = 0; i < rows.length; i++) {
    if (!isWeakAppLabel(rows[i].label, rows[i].packageName)) {
      n++;
    }
  }
  return n;
}

/** Android `AdbTools.parseListAppsOutput` — `package\\tlabel` lines. */
function parseListAppsOutput(out: string): InstalledAppRow[] {
  const apps: InstalledAppRow[] = [];
  if (out.length === 0) {
    return apps;
  }
  const lines = out.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (trimmed.length === 0 || trimmed.startsWith('Error') || trimmed.startsWith('Exception')) {
      continue;
    }
    const tab = trimmed.indexOf('\t');
    if (tab <= 0) {
      continue;
    }
    const pkg = trimmed.substring(0, tab).trim();
    let label = trimmed.substring(tab + 1).trim();
    if (!isSafePackageName(pkg)) {
      continue;
    }
    if (label.length === 0 || label === 'null') {
      label = pkg;
    }
    apps.push({ packageName: pkg, label: label });
  }
  return apps;
}

/**
 * Primary path (Android parity): on-device PackageManager via ListApps in server.jar.
 * Resolves locale-specific labels (zh-CN etc.) that dumpsys never prints as strings.
 */
function listAppsViaPackageManager(opts: AdbAuthOpts): InstalledAppRow[] {
  const jar = remoteServerJarPath();
  const ls = shellExec(opts, `ls ${jar} 2>/dev/null || true`);
  if (!ls.includes('easycontrolnext_server_')) {
    throw new Error('server jar missing on device');
  }
  const cmd =
    `app_process -Djava.class.path=${jar} / ` +
    'com.shiyunjin.easycontrolnext.server.helper.ListApps includeSystem=0';
  const out = shellExec(opts, cmd);
  const apps = parseListAppsOutput(out);
  if (apps.length === 0) {
    throw new Error('ListApps returned empty');
  }
  return sortInstalledAppRows(apps);
}

function collectThirdPartyPackages(opts: AdbAuthOpts): string[] {
  const out = shellExec(opts, 'pm list packages -3');
  const packages: string[] = [];
  const listLines = out.split('\n');
  for (let i = 0; i < listLines.length; i++) {
    const line = listLines[i].trim();
    if (!line.startsWith('package:')) {
      continue;
    }
    const pkg = line.substring('package:'.length).trim();
    if (isSafePackageName(pkg)) {
      packages.push(pkg);
    }
  }
  return packages;
}

function collectWeakPackages(packages: string[], labels: LabelMap): string[] {
  const weak: string[] = [];
  for (let i = 0; i < packages.length; i++) {
    const pkg = packages[i];
    if (isWeakAppLabel(labels.get(pkg), pkg)) {
      weak.push(pkg);
    }
  }
  return weak;
}

/**
 * Per-package dumpsys for remaining weak labels (applicationLabel / nonLocalizedLabel).
 * Caps work to keep picker responsive on large catalogs.
 */
function enrichLabelsFromPerPackageDump(
  opts: AdbAuthOpts,
  packages: string[],
  labels: LabelMap,
  maxPkgs: number
): number {
  let resolved = 0;
  let attempted = 0;
  for (let i = 0; i < packages.length && attempted < maxPkgs; i++) {
    const pkg = packages[i];
    if (!isWeakAppLabel(labels.get(pkg), pkg)) {
      continue;
    }
    attempted++;
    try {
      const dump = shellExec(opts, `dumpsys package ${pkg}`);
      const before = labels.get(pkg);
      enrichLabelsFromPackageDump(`Package [${pkg}]\n${dump}`, labels);
      const after = labels.get(pkg);
      if (!isWeakAppLabel(after, pkg) && after !== before) {
        resolved++;
      }
    } catch (_e) {
      // optional
    }
  }
  return resolved;
}

/** Optional aapt/aapt2 badging for locale labels (`application-label-zh:` etc.). */
function enrichLabelsFromAapt(
  opts: AdbAuthOpts,
  packages: string[],
  labels: LabelMap,
  maxResolve: number
): number {
  let aaptBin = '';
  try {
    const check = shellExec(
      opts,
      'command -v aapt || command -v aapt2 || ls /data/local/tmp/aapt 2>/dev/null || true'
    );
    const lines = check.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t === 'aapt' || t === 'aapt2' || t.startsWith('/')) {
        aaptBin = t;
        break;
      }
    }
  } catch (_e) {
    return 0;
  }
  if (aaptBin.length === 0) {
    return 0;
  }

  const apkPaths: LabelMap = new LabelMap();
  try {
    const pathOut = shellExec(opts, 'pm list packages -f -3');
    const lines = pathOut.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      // package:/path/base.apk=com.example.app
      if (!line.startsWith('package:')) {
        continue;
      }
      const body = line.substring('package:'.length);
      const eq = body.lastIndexOf('=');
      if (eq <= 0) {
        continue;
      }
      const apk = body.substring(0, eq).trim();
      const pkg = body.substring(eq + 1).trim();
      if (apk.length > 0 && isSafePackageName(pkg)) {
        apkPaths.set(pkg, apk);
      }
    }
  } catch (_e2) {
    return 0;
  }

  let resolved = 0;
  for (let i = 0; i < packages.length && resolved < maxResolve; i++) {
    const pkg = packages[i];
    if (!isWeakAppLabel(labels.get(pkg), pkg)) {
      continue;
    }
    const apk = apkPaths.get(pkg);
    if (apk.length === 0) {
      continue;
    }
    // Quote path for shell; APK paths from pm rarely contain quotes.
    const quoted = `'${apk}'`;
    try {
      const badge = shellExec(
        opts,
        `${aaptBin} dump badging ${quoted} 2>/dev/null | head -n 40`
      );
      // Prefer locale-specific then default: application-label-zh: '微信'
      let found = '';
      const badgeLines = badge.split('\n');
      for (let j = 0; j < badgeLines.length; j++) {
        const bl = badgeLines[j];
        const zhIdx = bl.indexOf("application-label-zh:'");
        const zhCnIdx = bl.indexOf("application-label-zh-CN:'");
        const defIdx = bl.indexOf("application-label:'");
        let start = -1;
        if (zhCnIdx >= 0) {
          start = zhCnIdx + "application-label-zh-CN:'".length;
        } else if (zhIdx >= 0) {
          start = zhIdx + "application-label-zh:'".length;
        } else if (defIdx >= 0 && found.length === 0) {
          start = defIdx + "application-label:'".length;
        }
        if (start < 0) {
          continue;
        }
        const end = bl.indexOf("'", start);
        if (end > start) {
          const label = bl.substring(start, end).trim();
          if (label.length > 0) {
            found = label;
            if (zhCnIdx >= 0 || zhIdx >= 0) {
              break;
            }
          }
        }
      }
      if (found.length > 0) {
        labels.set(pkg, found);
        resolved++;
      }
    } catch (_e3) {
      // optional
    }
  }
  return resolved;
}

/**
 * Shell fallback when ListApps / server.jar cannot run (Android AdbTools parity+).
 * Strategies: query-activities → full dumpsys → grepped dumpsys → per-pkg dumpsys → aapt.
 */
function listAppsViaShellFallback(opts: AdbAuthOpts): InstalledAppRow[] {
  const packages = collectThirdPartyPackages(opts);
  if (packages.length === 0) {
    return [];
  }

  const labels: LabelMap = new LabelMap();

  try {
    const launcherOut = shellExec(
      opts,
      'cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER'
    );
    enrichLabelsFromActivityDump(launcherOut, labels);
  } catch (_e) {
    // optional
  }

  // Full dumpsys (not grepped) — some OEMs only emit labels outside `packages` snippets.
  let dumpOk = false;
  try {
    const dump = shellExec(opts, 'dumpsys package');
    enrichLabelsFromPackageDump(dump, labels);
    dumpOk = true;
  } catch (_e2) {
    dumpOk = false;
  }
  if (!dumpOk) {
    try {
      const dump = shellExec(
        opts,
        "dumpsys package packages | grep -E 'Package \\[|applicationLabel=|nonLocalizedLabel='"
      );
      enrichLabelsFromPackageDump(dump, labels);
    } catch (_e3) {
      // optional
    }
  }

  const weakAfterDump = collectWeakPackages(packages, labels);
  if (weakAfterDump.length > 0) {
    enrichLabelsFromPerPackageDump(opts, weakAfterDump, labels, 40);
  }

  const weakAfterPerPkg = collectWeakPackages(packages, labels);
  if (weakAfterPerPkg.length > 0) {
    enrichLabelsFromAapt(opts, weakAfterPerPkg, labels, 80);
  }

  const rows: InstalledAppRow[] = [];
  for (let i = 0; i < packages.length; i++) {
    const pkg = packages[i];
    let label = labels.get(pkg);
    // Prefer resolved label; only fall back to package when missing/null.
    if (label.length === 0 || label === 'null') {
      label = pkg;
    }
    rows.push({ packageName: pkg, label: label });
  }
  return sortInstalledAppRows(rows);
}

/**
 * List third-party packages with display labels (Android AppPickerDialog / AdbTools parity).
 * Primary: ListApps via PackageManager (resolved + locale labels).
 * Fallback: multi-strategy shell dumpsys / query-activities / aapt.
 */
export async function listRemoteThirdPartyApps(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<InstalledAppRow[]> {
  if (device.address.length === 0) {
    return [];
  }
  await assertAdbTcpReachable(device.address, device.adbPort);
  const opts = await buildAuthOpts(ctx, device);

  try {
    const viaPm = listAppsViaPackageManager(opts);
    const strong = countStrongLabels(viaPm);
    hilog.info(
      DOMAIN,
      TAG,
      'listApps via=ListApps packages=%{public}d labeled=%{public}d',
      viaPm.length,
      strong
    );
    return viaPm;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'ListApps failed, shell fallback: %{public}s', msg);
  }

  const rows = listAppsViaShellFallback(opts);
  const strong = countStrongLabels(rows);
  hilog.info(
    DOMAIN,
    TAG,
    'listApps via=shell packages=%{public}d labeled=%{public}d',
    rows.length,
    strong
  );
  return rows;
}

/**
 * Foreground-launch an app on the controlled device (no virtual display).
 * Prefer monkey LAUNCHER; fallback to am start MAIN/LAUNCHER intent.
 */
export async function launchRemoteAppForeground(
  ctx: common.UIAbilityContext,
  device: Device,
  packageName: string
): Promise<AdbOpResult> {
  const pkg = packageName.trim();
  if (!isSafePackageName(pkg)) {
    return { ok: false, detail: '非法包名' };
  }
  if (device.address.length === 0) {
    return { ok: false, detail: '无设备地址' };
  }
  try {
    const opts = await buildAuthOpts(ctx, device);
    const monkey =
      `monkey -p ${pkg} -c android.intent.category.LAUNCHER 1`;
    let out = shellExec(opts, monkey);
    const lower = out.toLowerCase();
    if (lower.includes('error') || lower.includes('exception') || lower.includes('aborted')) {
      const am =
        `am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER ${pkg}`;
      out = shellExec(opts, am);
    }
    hilog.info(DOMAIN, TAG, 'launch %{public}s out=%{public}s', pkg, out.trim().slice(0, 120));
    return { ok: true, detail: `已启动 ${pkg}` };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'launch failed %{public}s', msg);
    return { ok: false, detail: msg };
  }
}

/**
 * Lightweight Home detail probe: model + Android release/SDK via getprop.
 * Short-lived ADB auth; safe to call from Home without touching live session.
 */
export async function probeRemoteSystemProps(
  ctx: common.UIAbilityContext,
  device: Device
): Promise<RemoteSystemProps> {
  if (device.address.length === 0) {
    return { ok: false, model: '', release: '', sdk: '', detail: '无设备地址' };
  }
  try {
    const opts = await buildAuthOpts(ctx, device);
    const out = shellExec(
      opts,
      'echo "$(getprop ro.product.model)|$(getprop ro.build.version.release)|$(getprop ro.build.version.sdk)"'
    );
    const line = out.trim().split('\n')[0] ?? '';
    const parts = line.split('|');
    const model = (parts[0] ?? '').trim();
    const release = (parts[1] ?? '').trim();
    const sdk = (parts[2] ?? '').trim();
    if (model.length === 0 && release.length === 0 && sdk.length === 0) {
      return { ok: false, model: '', release: '', sdk: '', detail: '属性为空' };
    }
    hilog.info(
      DOMAIN,
      TAG,
      'sysprops model=%{public}s release=%{public}s sdk=%{public}s',
      model,
      release,
      sdk
    );
    return { ok: true, model: model, release: release, sdk: sdk, detail: '' };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'sysprops failed %{public}s', msg);
    return { ok: false, model: '', release: '', sdk: '', detail: msg };
  }
}

/**
 * Fold / XComponent recreate: rebind OH_VideoDecoder → new surfaceId.
 * Keeps ADB + AU feed alive (drop AUs only while native REBINDING). No AUTH/push/connect_t0.
 */
export function rebindLiveSurface(surfaceId: string): LiveStatus {
  const sid = surfaceId.trim();
  if (sid.length === 0 || sid === '0') {
    hilog.warn(DOMAIN, TAG, 'SURFACE_REBIND skipped empty surfaceId');
    return pollLiveStatus();
  }
  const t0 = Date.now();
  hilog.info(DOMAIN, TAG, 'SURFACE_REBIND request sid=%{public}s', sid);
  try {
    const dec = adbCore.videoDecoderRebindSurface(sid) as Record<string, Object>;
    hilog.info(
      DOMAIN,
      TAG,
      'SURFACE_REBOUND ok +%{public}dms sid=%{public}s detail=%{public}s first=%{public}s',
      Date.now() - t0,
      String(dec['surfaceId'] ?? sid),
      String(dec['detail'] ?? ''),
      Boolean(dec['firstFrameRendered']) ? '1' : '0'
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(
      DOMAIN,
      TAG,
      'SURFACE_REBIND failed +%{public}dms %{public}s',
      Date.now() - t0,
      msg
    );
  }
  // Do not reset connectT0Ms — fold must not look like a new Gate D connect.
  return pollLiveStatus();
}

function mapStatus(st: Record<string, Object>): LiveStatus {
  return {
    phase: String(st['phase'] ?? 'idle'),
    detail: String(st['detail'] ?? ''),
    mode: String(st['mode'] ?? ''),
    width: Number(st['width'] ?? 0),
    height: Number(st['height'] ?? 0),
    useH265: Boolean(st['useH265']),
    ausFed: Number(st['ausFed'] ?? 0),
    firstFrame: Boolean(st['firstFrame']),
    live: Boolean(st['live']),
    canAudio: Boolean(st['canAudio']),
    useOpus: Boolean(st['useOpus']),
    audioStarted: Boolean(st['audioStarted']),
    audioFrames: Number(st['audioFrames'] ?? 0),
    audioDetail: String(st['audioDetail'] ?? ''),
  };
}
