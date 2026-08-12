/**
 * Thin ArkTS wrapper over libadb_core.so (Gate B probe + Phase 5 video/control).
 * Full surface: native/arkts/AdbCore.ets.example
 */

import adbCore from 'libadb_core.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { buildSyntheticAvcFixture } from '../media/FixtureBitstream';
import { parseAccessUnitStream, parseVideoStreamHeader } from '../media/VideoFraming';

const DOMAIN: number = 0x0001;
const TAG: string = 'GateB';

export interface GateBProbeResult {
  ok: boolean;
  version: string;
  capabilities: string;
  roundTripOk: boolean;
  detail: string;
}

export function runGateBProbe(): GateBProbeResult {
  try {
    const version: string = adbCore.nativeVersion() as string;
    const capabilities: string = adbCore.nativeCapabilities() as string;
    const input = new Uint8Array([1, 2, 3, 4]).buffer;
    const echoed = adbCore.roundTripBytes(input) as ArrayBuffer;
    const out = new Uint8Array(echoed);
    const roundTripOk: boolean =
      out.length === 4 && out[0] === 1 && out[1] === 2 && out[2] === 3 && out[3] === 4;

    // Phase 5 framing smoke (does not require Session UI).
    let framingOk = false;
    let framingDetail = '';
    try {
      const fixture = buildSyntheticAvcFixture();
      const hdr = parseVideoStreamHeader(fixture);
      const aus = parseAccessUnitStream(fixture, hdr.consumed, 8);
      framingOk = hdr.width > 0 && hdr.csd0AnnexB && aus.length >= 1;
      framingDetail = `videoFrame=${framingOk} ${hdr.width}x${hdr.height} au=${aus.length}`;
    } catch (fe) {
      framingDetail = `videoFrame=err ${fe instanceof Error ? fe.message : String(fe)}`;
    }

    const detail =
      `nativeVersion=${version}; capabilities=${capabilities}; roundTrip=${roundTripOk}; ${framingDetail}`;
    hilog.info(DOMAIN, TAG, 'probe ok %{public}s', detail);
    return {
      ok: true,
      version,
      capabilities,
      roundTripOk,
      detail,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    hilog.error(DOMAIN, TAG, 'probe failed %{public}s', msg);
    return {
      ok: false,
      version: '',
      capabilities: '',
      roundTripOk: false,
      detail: msg,
    };
  }
}
