/**
 * On-device ADB RSA material: generate once, HUKS-wrap into filesDir.
 * Does not import libadb_core.so (keep probe/Home first frame free of dlopen).
 * Never logs PEM / wrapping plaintext.
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AdbHuksWrap } from '../adb/AdbHuksWrap';
import { generateAdbRsaPkcs8Pem } from '../adb/AdbRsaGenerate';

const DOMAIN: number = 0xEC02;
const TAG: string = 'AdbKey';
const WRAP_FILE: string = 'adb_rsa_huks.bin';
const MAGIC: number[] = [0x45, 0x43, 0x57, 0x31]; // ECW1
const MAGIC_LEN: number = 4;

export interface AdbKeyMaterial {
  privateKeyPem: string;
  publicKeyLine?: ArrayBuffer;
}

let cached: AdbKeyMaterial | null = null;
let loadPromise: Promise<AdbKeyMaterial> | null = null;

function utf8ToBytes(text: string): Uint8Array {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    out[i] = text.charCodeAt(i) & 0xff;
  }
  return out;
}

function bytesToUtf8(raw: Uint8Array): string {
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    out += String.fromCharCode(raw[i]);
  }
  return out;
}

function wrapPath(ctx: common.Context): string {
  return `${ctx.filesDir}/${WRAP_FILE}`;
}

function fileExists(path: string): boolean {
  try {
    return fs.accessSync(path);
  } catch (_e) {
    return false;
  }
}

function readAllBytes(path: string): Uint8Array {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const stat = fs.statSync(path);
    const size = stat.size;
    if (size <= 0 || size > 64 * 1024) {
      throw new Error('wrapped key size invalid');
    }
    const buf = new ArrayBuffer(size);
    const n = fs.readSync(file.fd, buf);
    return new Uint8Array(buf, 0, n);
  } finally {
    fs.closeSync(file);
  }
}

function writeAllBytes(path: string, data: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
  try {
    const copy = new ArrayBuffer(data.byteLength);
    new Uint8Array(copy).set(data);
    fs.writeSync(file.fd, copy);
  } finally {
    fs.closeSync(file);
  }
}

function packBlob(packed: Uint8Array): Uint8Array {
  const out = new Uint8Array(MAGIC_LEN + packed.length);
  for (let i = 0; i < MAGIC_LEN; i++) {
    out[i] = MAGIC[i];
  }
  out.set(packed, MAGIC_LEN);
  return out;
}

function unpackBlob(fileBytes: Uint8Array): Uint8Array {
  if (fileBytes.length < MAGIC_LEN + 16) {
    throw new Error('wrapped key truncated');
  }
  for (let i = 0; i < MAGIC_LEN; i++) {
    if (fileBytes[i] !== MAGIC[i]) {
      throw new Error('wrapped key magic mismatch');
    }
  }
  return fileBytes.slice(MAGIC_LEN);
}

function looksLikePkcs8Pem(pem: string): boolean {
  return pem.indexOf('BEGIN PRIVATE KEY') >= 0 && pem.indexOf('END PRIVATE KEY') >= 0;
}

async function createAndStore(ctx: common.Context): Promise<string> {
  const pem = await generateAdbRsaPkcs8Pem();
  const wrapped = await AdbHuksWrap.wrap(utf8ToBytes(pem));
  writeAllBytes(wrapPath(ctx), packBlob(wrapped));
  hilog.info(DOMAIN, TAG, '%{public}s', 'generated device RSA, HUKS-wrapped');
  return pem;
}

async function loadOrCreate(ctx: common.Context): Promise<AdbKeyMaterial> {
  const path = wrapPath(ctx);
  if (fileExists(path)) {
    try {
      const packed = unpackBlob(readAllBytes(path));
      const plain = await AdbHuksWrap.unwrap(packed);
      const pem = bytesToUtf8(plain);
      if (!looksLikePkcs8Pem(pem)) {
        throw new Error('unwrapped payload is not PKCS#8 PEM');
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loaded HUKS-wrapped RSA');
      return { privateKeyPem: pem };
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'unwrap failed';
      hilog.warn(DOMAIN, TAG, 'unwrap failed, regenerating %{public}s', msg);
    }
  }
  const pem = await createAndStore(ctx);
  return { privateKeyPem: pem };
}

/**
 * Load (or generate) the controller ADB RSA private key.
 * Public ADB wire format is rebuilt in Rust from the PEM.
 */
export async function loadAdbKeyMaterial(ctx: common.Context): Promise<AdbKeyMaterial> {
  if (cached !== null) {
    return cached;
  }
  if (loadPromise !== null) {
    return loadPromise;
  }
  loadPromise = loadOrCreate(ctx).then((keys: AdbKeyMaterial) => {
    cached = keys;
    return keys;
  }).catch((e: Object) => {
    loadPromise = null;
    if (e instanceof Error) {
      throw e;
    }
    throw new Error('load adb key failed');
  });
  return loadPromise;
}
