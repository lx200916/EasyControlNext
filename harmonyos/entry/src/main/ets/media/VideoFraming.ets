/**
 * Thin wrappers over native video framing (Gate E / Phase 5).
 * Wire shape: header + length-prefixed CSD + length-prefixed AUs (pts + NAL).
 */

import adbCore from 'libadb_core.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'VideoFraming';

export interface VideoHeaderParsed {
  useH265: boolean;
  width: number;
  height: number;
  csd0: ArrayBuffer;
  csd1: ArrayBuffer | null;
  csd0AnnexB: boolean;
  consumed: number;
}

export interface VideoAccessUnitParsed {
  ptsUs: number;
  payload: ArrayBuffer;
  annexB: boolean;
  consumed: number;
}

export function parseVideoStreamHeader(input: ArrayBuffer): VideoHeaderParsed {
  const hdr = adbCore.parseVideoStreamHeader(input) as Record<string, Object>;
  const csd1Raw = hdr['csd1'];
  return {
    useH265: hdr['useH265'] as boolean,
    width: hdr['width'] as number,
    height: hdr['height'] as number,
    csd0: hdr['csd0'] as ArrayBuffer,
    csd1: csd1Raw !== undefined && csd1Raw !== null ? csd1Raw as ArrayBuffer : null,
    csd0AnnexB: hdr['csd0AnnexB'] as boolean,
    consumed: hdr['consumed'] as number,
  };
}

export function parseVideoAccessUnit(input: ArrayBuffer): VideoAccessUnitParsed {
  const au = adbCore.parseVideoAccessUnit(input) as Record<string, Object>;
  return {
    ptsUs: au['ptsUs'] as number,
    payload: au['payload'] as ArrayBuffer,
    annexB: au['annexB'] as boolean,
    consumed: au['consumed'] as number,
  };
}

/**
 * Drain a concatenated buffer of length-prefixed AUs after the header.
 * Stops on truncate / error; returns how many complete AUs were parsed.
 */
export function parseAccessUnitStream(
  stream: ArrayBuffer,
  offset: number,
  maxAus: number
): VideoAccessUnitParsed[] {
  const out: VideoAccessUnitParsed[] = [];
  let off = offset;
  const bytes = new Uint8Array(stream);
  while (out.length < maxAus && off + 4 <= bytes.length) {
    const slice = stream.slice(off);
    try {
      const au = parseVideoAccessUnit(slice);
      out.push(au);
      off += au.consumed;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'AU parse stop at %{public}d: %{public}s', off, msg);
      break;
    }
  }
  return out;
}
