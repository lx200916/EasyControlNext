/**
 * Persistent capped error/warning log under app filesDir — mirrors Android AppErrorLog.
 * Newest-first in memory; oldest-first on disk; separator `----`.
 * Hard caps: entry count, per-field length, and on-disk bytes (trim oldest first).
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const DOMAIN: number = 0x0001;
const TAG: string = 'AppErrorLog';
const FILE_NAME: string = 'error_log.txt';
/** Keep at most this many records in memory / on disk. */
const MAX_ENTRIES: number = 300;
/** Absolute on-disk size ceiling for error_log.txt (includes separators). */
const MAX_FILE_BYTES: number = 256 * 1024;
/** Refuse to load more than this from a runaway file (tail only). */
const MAX_LOAD_BYTES: number = MAX_FILE_BYTES;
const MAX_MESSAGE_CHARS: number = 2000;
const MAX_STACK_CHARS: number = 6000;
const MAX_TAG_CHARS: number = 64;
const RECORD_SEP: string = '----';
const HILOG_TAG: string = 'EasyControlNext';

export type ErrorLogLevel = 'E' | 'W';

export class ErrorLogEntry {
  /** Stable UI key — survives identical timestamps / tags after parse. */
  id: string = '';
  timestampMs: number = 0;
  level: ErrorLogLevel = 'E';
  tag: string = 'app';
  message: string = '';
  stackTrace: string = '';

  constructor(
    timestampMs: number,
    level: ErrorLogLevel,
    tag: string,
    message: string,
    stackTrace: string = '',
    id: string = ''
  ) {
    this.timestampMs = timestampMs;
    this.level = level;
    this.tag = tag;
    this.message = message;
    this.stackTrace = stackTrace;
    this.id = id.length > 0 ? id : `${timestampMs}_${level}_${Math.floor(Math.random() * 1e9)}`;
  }

  formatBlock(): string {
    const header = `${formatTimestamp(this.timestampMs)} ${this.level}/${this.tag}`;
    if (this.stackTrace.length === 0) {
      return `${header}\n${this.message}`;
    }
    return `${header}\n${this.message}\n${this.stackTrace}`;
  }
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function pad3(n: number): string {
  if (n < 10) {
    return `00${n}`;
  }
  if (n < 100) {
    return `0${n}`;
  }
  return `${n}`;
}

export function formatTimestamp(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ` +
    `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}.${pad3(d.getMilliseconds())}`;
}

export function formatTimestampShort(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ` +
    `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}.${pad3(d.getMilliseconds())}`;
}

class AppErrorLogStore {
  private entries: ErrorLogEntry[] = [];
  private loaded: boolean = false;
  private filesDir: string = '';
  private writeChain: Promise<void> = Promise.resolve();

  /**
   * Cold-start safe: bind filesDir + merge any entries appended before init.
   * Do not sync-read error_log.txt before first frame — that blocked UI on real devices.
   */
  init(context: common.Context): void {
    this.filesDir = context.filesDir;
    this.cleanupTmp();
    if (!this.loaded) {
      const pending = this.entries.slice();
      this.loadFromDisk();
      // Pre-init appends would otherwise be wiped by the first ensureLoaded().
      for (let i = pending.length - 1; i >= 0; i--) {
        this.entries.unshift(pending[i]);
      }
      this.trimToCaps();
      this.loaded = true;
      if (pending.length > 0) {
        this.enqueuePersist();
      }
    }
  }

  e(tag: string, message: string, stackTrace: string = ''): void {
    this.append('E', tag, message, stackTrace);
  }

  w(tag: string, message: string, stackTrace: string = ''): void {
    this.append('W', tag, message, stackTrace);
  }

  append(level: ErrorLogLevel, tag: string, message: string, stackTrace: string = ''): void {
    // Load existing log before appending so a first post-start error does not wipe history.
    this.ensureLoaded();
    const safeTag = truncateChars(tag.length > 0 ? tag : 'app', MAX_TAG_CHARS);
    const safeMsg = truncateChars(
      message.length > 0 ? message : (stackTrace.length > 0 ? '(exception)' : '(empty)'),
      MAX_MESSAGE_CHARS
    );
    const safeStack = truncateChars(stackTrace, MAX_STACK_CHARS);
    const entry = new ErrorLogEntry(Date.now(), level, safeTag, safeMsg, safeStack);
    if (level === 'E') {
      hilog.error(DOMAIN, HILOG_TAG, '%{public}s/%{public}s %{public}s', safeTag, level, safeMsg);
    } else {
      hilog.warn(DOMAIN, HILOG_TAG, '%{public}s/%{public}s %{public}s', safeTag, level, safeMsg);
    }
    this.entries.unshift(entry);
    this.trimToCaps();
    this.enqueuePersist();
  }

  readNewestFirst(): ErrorLogEntry[] {
    this.ensureLoaded();
    return this.entries.slice();
  }

  clear(): void {
    this.ensureLoaded();
    this.entries = [];
    this.enqueuePersist();
  }

  exportText(): string {
    const list = this.readNewestFirst();
    if (list.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (let i = 0; i < list.length; i++) {
      parts.push(list[i].formatBlock());
    }
    return parts.join(`\n${RECORD_SEP}\n`);
  }

  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    if (this.filesDir.length === 0) {
      return;
    }
    this.loadFromDisk();
    this.loaded = true;
  }

  private logPath(): string {
    return `${this.filesDir}/${FILE_NAME}`;
  }

  private tmpPath(): string {
    return `${this.logPath()}.tmp`;
  }

  private cleanupTmp(): void {
    if (this.filesDir.length === 0) {
      return;
    }
    try {
      const tmp = this.tmpPath();
      if (fs.accessSync(tmp)) {
        fs.unlinkSync(tmp);
      }
    } catch (_e) {
      // ignore
    }
  }

  /** Drop oldest until entry count and estimated UTF-8 size are under caps. */
  private trimToCaps(): void {
    while (this.entries.length > MAX_ENTRIES) {
      this.entries.pop();
    }
    while (this.entries.length > 1 && estimateBodyBytes(this.entries) > MAX_FILE_BYTES) {
      this.entries.pop();
    }
  }

  private enqueuePersist(): void {
    this.writeChain = this.writeChain.then(() => {
      this.persistSync();
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'persist failed %{public}s', e.message);
    });
  }

  private loadFromDisk(): void {
    this.entries = [];
    if (this.filesDir.length === 0) {
      return;
    }
    const path = this.logPath();
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const stat = fs.statSync(path);
      const size = Number(stat.size);
      if (size <= 0) {
        return;
      }
      // Runaway / legacy oversized file: only ingest the newest tail.
      const readLen = size > MAX_LOAD_BYTES ? MAX_LOAD_BYTES : size;
      const fileOffset = size > MAX_LOAD_BYTES ? size - MAX_LOAD_BYTES : 0;
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      if (fileOffset > 0) {
        fs.lseek(file.fd, fileOffset, fs.WhenceType.SEEK_SET);
      }
      const buf = new ArrayBuffer(readLen);
      const got = fs.readSync(file.fd, buf);
      fs.closeSync(file);
      let text = bufferToString(got < readLen ? buf.slice(0, got) : buf);
      if (fileOffset > 0) {
        // Align to first full record after the partial head.
        const sepIdx = text.indexOf(`\n${RECORD_SEP}\n`);
        if (sepIdx >= 0) {
          text = text.substring(sepIdx + RECORD_SEP.length + 2);
        }
      }
      const blocks = splitBlocks(text);
      const parsed: ErrorLogEntry[] = [];
      for (let i = 0; i < blocks.length; i++) {
        const entry = parseBlock(blocks[i]);
        if (entry !== undefined) {
          parsed.push(entry);
        }
      }
      let keep = parsed;
      if (keep.length > MAX_ENTRIES) {
        keep = keep.slice(keep.length - MAX_ENTRIES);
      }
      // File is oldest-first → memory newest-first
      for (let i = keep.length - 1; i >= 0; i--) {
        this.entries.push(keep[i]);
      }
      this.trimToCaps();
      // If disk was oversized, rewrite trimmed content so storage stays bounded.
      if (size > MAX_FILE_BYTES) {
        this.persistSync();
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'load failed %{public}s', msg);
      this.entries = [];
    }
  }

  private persistSync(): void {
    if (this.filesDir.length === 0) {
      return;
    }
    this.trimToCaps();
    const path = this.logPath();
    const tmp = this.tmpPath();
    try {
      let body = buildBodyOldestFirst(this.entries);
      let bytes = stringToBuffer(body);
      while (bytes.byteLength > MAX_FILE_BYTES && this.entries.length > 1) {
        this.entries.pop();
        body = buildBodyOldestFirst(this.entries);
        bytes = stringToBuffer(body);
      }
      const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, bytes);
      fs.closeSync(file);
      try {
        if (fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
      } catch (_e) {
        // ignore
      }
      fs.renameSync(tmp, path);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'write failed %{public}s', msg);
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (_e3) {
        // ignore
      }
    }
  }
}

function truncateChars(text: string, maxChars: number): string {
  if (text.length <= maxChars) {
    return text;
  }
  return `${text.substring(0, maxChars)}…`;
}

function buildBodyOldestFirst(entries: ErrorLogEntry[]): string {
  if (entries.length === 0) {
    return '';
  }
  const ordered = entries.slice().reverse();
  const chunks: string[] = [];
  for (let i = 0; i < ordered.length; i++) {
    if (i > 0) {
      chunks.push(RECORD_SEP);
    }
    chunks.push(ordered[i].formatBlock());
  }
  return `${chunks.join('\n')}\n`;
}

/** Cheap upper-bound estimate (UTF-16 length ≈ bytes for ASCII-heavy logs). */
function estimateBodyBytes(entries: ErrorLogEntry[]): number {
  if (entries.length === 0) {
    return 0;
  }
  let n = 0;
  for (let i = 0; i < entries.length; i++) {
    n += entries[i].formatBlock().length + 1;
    if (i > 0) {
      n += RECORD_SEP.length + 1;
    }
  }
  // UTF-8 may be larger for CJK; pad ~50% then clamp against hard write check.
  return Math.floor(n * 1.5);
}

function bufferToString(buf: ArrayBuffer): string {
  try {
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeWithStream(new Uint8Array(buf), { stream: false });
  } catch (_e) {
    const bytes = new Uint8Array(buf);
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }
}

function stringToBuffer(text: string): ArrayBuffer {
  const encoder = new util.TextEncoder();
  const u8 = encoder.encodeInto(text);
  return u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
}

function splitBlocks(text: string): string[] {
  const lines = text.split('\n');
  const blocks: string[] = [];
  let current: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line === RECORD_SEP) {
      if (current.length > 0) {
        blocks.push(current.join('\n'));
      }
      current = [];
    } else {
      current.push(line);
    }
  }
  if (current.length > 0) {
    blocks.push(current.join('\n'));
  }
  return blocks;
}

function parseBlock(block: string): ErrorLogEntry | undefined {
  const trimmed = block.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const lines = trimmed.split('\n');
  const header = lines[0];
  const slash = header.lastIndexOf('/');
  const space = header.lastIndexOf(' ');
  if (slash <= 0 || space <= 0 || space >= slash) {
    return new ErrorLogEntry(Date.now(), 'E', 'log', trimmed, '');
  }
  const levelChar = header.substring(space + 1, slash);
  const tag = header.substring(slash + 1);
  const level: ErrorLogLevel = levelChar.toUpperCase() === 'W' ? 'W' : 'E';
  const tsText = header.substring(0, space);
  let ts = parseTimestampMs(tsText);
  if (ts <= 0) {
    ts = Date.now();
  }
  const message = lines.length > 1 ? lines[1] : '';
  let stack = '';
  if (lines.length > 2) {
    stack = lines.slice(2).join('\n');
  }
  const safeTag = truncateChars(tag.length > 0 ? tag : 'log', MAX_TAG_CHARS);
  const safeMsg = truncateChars(message, MAX_MESSAGE_CHARS);
  const safeStack = truncateChars(stack, MAX_STACK_CHARS);
  // Stable-ish id so ForEach does not collapse rows that share the same ms/tag.
  const id = `${ts}_${level}_${safeTag}_${safeMsg.length}_${safeStack.length}_${header.length}`;
  return new ErrorLogEntry(ts, level, safeTag, safeMsg, safeStack, id);
}

/** Parse `YYYY-MM-DD HH:mm:ss.SSS` without relying on Date.parse locale quirks. */
function parseTimestampMs(text: string): number {
  // Expected: 2026-08-12 23:00:00.123
  if (text.length < 19) {
    const fallback = Date.parse(text.replace(' ', 'T'));
    return isNaN(fallback) ? 0 : fallback;
  }
  const year = Number(text.substring(0, 4));
  const month = Number(text.substring(5, 7));
  const day = Number(text.substring(8, 10));
  const hour = Number(text.substring(11, 13));
  const minute = Number(text.substring(14, 16));
  const second = Number(text.substring(17, 19));
  let ms = 0;
  if (text.length > 20 && text.charAt(19) === '.') {
    const frac = text.substring(20);
    if (frac.length === 1) {
      ms = Number(frac) * 100;
    } else if (frac.length === 2) {
      ms = Number(frac) * 10;
    } else {
      ms = Number(frac.substring(0, 3));
    }
  }
  if (isNaN(year) || isNaN(month) || isNaN(day) || isNaN(hour) || isNaN(minute) || isNaN(second) ||
    isNaN(ms)) {
    const fallback = Date.parse(text.replace(' ', 'T'));
    return isNaN(fallback) ? 0 : fallback;
  }
  const d = new Date(year, month - 1, day, hour, minute, second, ms);
  const t = d.getTime();
  return isNaN(t) ? 0 : t;
}

/** Singleton used by UI + session paths. */
export const AppErrorLog: AppErrorLogStore = new AppErrorLogStore();
