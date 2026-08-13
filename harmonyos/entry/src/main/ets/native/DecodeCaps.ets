/**
 * Lazy-loaded native probe — imports libadb_core.so.
 * Settings tap and first-launch background `DecoderCapsCache` (after first frame).
 * Do not import this from Home / AppShell / Form Kit.
 */

import adbCore from 'libadb_core.so';
import { DecoderCapsResult } from './AdbCoreTypes';

export function probeDecoderCaps(): DecoderCapsResult {
  const raw = adbCore.probeDecoderCaps() as Record<string, Object>;
  return {
    avc: Boolean(raw['avc']),
    hevc: Boolean(raw['hevc']),
    opus: Boolean(raw['opus']),
    aac: Boolean(raw['aac']),
    detail: typeof raw['detail'] === 'string' ? raw['detail'] as string : '',
  };
}
