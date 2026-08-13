/**
 * EasyControl video fixtures for Session inject / Gate E decode proof.
 *
 * Prefer rawfile `fixture_avc_easycontrol.bin` (real libx264 baseline 320x180).
 * Fallback synthetic NALs only prove framing — hardware decoders usually reject them.
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'FixtureBitstream';

function writeU32Be(view: DataView, offset: number, value: number): void {
  view.setUint32(offset, value >>> 0, false);
}

function writeI64Be(view: DataView, offset: number, value: number): void {
  const hi = Math.floor(value / 0x100000000);
  const lo = value >>> 0;
  view.setUint32(offset, hi >>> 0, false);
  view.setUint32(offset + 4, lo, false);
}

function appendPtsFrame(chunks: number[][], ptsUs: number, nal: number[]): void {
  const body = new ArrayBuffer(8 + nal.length);
  const view = new DataView(body);
  writeI64Be(view, 0, ptsUs);
  const u8 = new Uint8Array(body);
  for (let i = 0; i < nal.length; i++) {
    u8[8 + i] = nal[i];
  }
  const lenBuf = new ArrayBuffer(4);
  writeU32Be(new DataView(lenBuf), 0, body.byteLength);
  chunks.push(Array.from(new Uint8Array(lenBuf)));
  chunks.push(Array.from(u8));
}

/** Framing-only synthetic (not decoder-valid). */
export function buildSyntheticAvcFixture(): ArrayBuffer {
  const sps: number[] = [0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x0a, 0xf8];
  const pps: number[] = [0x00, 0x00, 0x00, 0x01, 0x68, 0xce, 0x38, 0x80];
  const idr: number[] = [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00, 0x10];

  const header = new ArrayBuffer(9);
  const hv = new DataView(header);
  hv.setUint8(0, 0);
  writeU32Be(hv, 1, 720);
  writeU32Be(hv, 5, 1280);

  const chunks: number[][] = [Array.from(new Uint8Array(header))];
  appendPtsFrame(chunks, 0, sps);
  appendPtsFrame(chunks, 0, pps);
  appendPtsFrame(chunks, 33333, idr);

  let total = 0;
  for (let i = 0; i < chunks.length; i++) {
    total += chunks[i].length;
  }
  const out = new Uint8Array(total);
  let off = 0;
  for (let i = 0; i < chunks.length; i++) {
    out.set(chunks[i], off);
    off += chunks[i].length;
  }
  return out.buffer;
}

/**
 * Load real Annex-B EasyControl fixture from rawfile (libx264 baseline).
 * Falls back to synthetic framing-only buffer if rawfile missing.
 */
export async function loadDecodeFixture(ctx: common.UIAbilityContext): Promise<ArrayBuffer> {
  try {
    const raw = await ctx.resourceManager.getRawFileContent('fixture_avc_easycontrol.bin');
    // getRawFileContent returns Uint8Array
    const copy = new ArrayBuffer(raw.byteLength);
    new Uint8Array(copy).set(raw);
    hilog.info(DOMAIN, TAG, 'loaded fixture_avc_easycontrol.bin %{public}d bytes', raw.byteLength);
    return copy;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'rawfile fixture missing, synthetic fallback: %{public}s', msg);
    return buildSyntheticAvcFixture();
  }
}
