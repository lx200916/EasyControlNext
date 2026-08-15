/**
 * Local OH_VideoDecoder HEVC probe — scheduled after first frame.
 * Does not import libadb_core.so at module load (lazy DecodeCaps).
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSettings } from '../common/AppSettings';
import { DecoderCapsResult } from '../native/AdbCoreTypes';

const DOMAIN: number = 0xEC03;
const TAG: string = 'DecoderCapsCache';
/** After Home first paint; CreateByMime must not block uiForeground. */
const PROBE_DELAY_MS: number = 1800;

interface DecodeCapsNs {
  probeDecoderCaps: () => DecoderCapsResult;
}

class DecoderCapsCacheImpl {
  private scheduled: boolean = false;

  /** Optimistic H.265 until a probe says this device has no HEVC decoder. */
  preferH265(): boolean {
    return AppSettings.preferH265();
  }

  scheduleBackgroundProbe(context: common.Context): void {
    if (this.scheduled) {
      return;
    }
    this.scheduled = true;
    setTimeout((): void => {
      void this.probeNow(context);
    }, PROBE_DELAY_MS);
  }

  private async probeNow(context: common.Context): Promise<void> {
    try {
      await AppSettings.init(context);
      const ns = await import('../native/DecodeCaps') as DecodeCapsNs;
      const caps = ns.probeDecoderCaps();
      await AppSettings.applyDecoderCaps(caps.hevc);
      hilog.info(
        DOMAIN,
        TAG,
        'probe hevc=%{public}s avc=%{public}s %{public}s',
        caps.hevc ? '1' : '0',
        caps.avc ? '1' : '0',
        caps.detail
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'probe failed %{public}s', msg);
    }
  }
}

export const DecoderCapsCache: DecoderCapsCacheImpl = new DecoderCapsCacheImpl();
