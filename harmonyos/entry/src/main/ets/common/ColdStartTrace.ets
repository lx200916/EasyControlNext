/**
 * Cold-start / first-frame timing marks → HiLog tag `ColdStart`.
 * Filter: hilog | grep ColdStart   (or DevEco HiLog tag = ColdStart)
 * Remove later by deleting call sites + this file.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ColdStart';

export class ColdStartTrace {
  private static t0Ms: number = 0;
  private static lastMs: number = 0;

  /**
   * Log absolute ms since first mark (+Nms) and delta since previous mark (ΔNms).
   * Format: COLD_START +XXXms ΔYYYms phase=... detail=...
   */
  static mark(phase: string, detail: string = ''): void {
    const now = Date.now();
    if (ColdStartTrace.t0Ms === 0) {
      ColdStartTrace.t0Ms = now;
      ColdStartTrace.lastMs = now;
    }
    const sinceStart = now - ColdStartTrace.t0Ms;
    const delta = now - ColdStartTrace.lastMs;
    ColdStartTrace.lastMs = now;
    if (detail.length > 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'COLD_START +%{public}dms Δ%{public}dms phase=%{public}s detail=%{public}s',
        sinceStart,
        delta,
        phase,
        detail
      );
    } else {
      hilog.info(
        DOMAIN,
        TAG,
        'COLD_START +%{public}dms Δ%{public}dms phase=%{public}s',
        sinceStart,
        delta,
        phase
      );
    }
  }
}
