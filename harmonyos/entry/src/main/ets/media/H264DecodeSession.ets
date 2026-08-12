/**
 * Phase 5 decode pipeline.
 *
 * HarmonyOS API 24: OH_VideoDecoder is C NDK only. Framing stays in ArkTS/NAPI;
 * surface bind + decode runs in libadb_core.so (ohos_vdec).
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import adbCore from 'libadb_core.so';
import {
  parseAccessUnitStream,
  parseVideoStreamHeader,
  VideoAccessUnitParsed,
  VideoHeaderParsed,
} from './VideoFraming';

const DOMAIN: number = 0x0001;
const TAG: string = 'H264Decode';

export type DecodePipelineState =
  | 'idle'
  | 'surface_ready'
  | 'header_ok'
  | 'framed'
  | 'decoding'
  | 'first_frame'
  | 'error';

export interface DecodePipelineStatus {
  state: DecodePipelineState;
  surfaceId: string;
  width: number;
  height: number;
  useH265: boolean;
  auCount: number;
  annexBCount: number;
  firstPtsUs: number;
  detail: string;
  framingOk: boolean;
  firstFrameRendered: boolean;
  decoderStarted: boolean;
  inputQueued: number;
  outputFrames: number;
  lastError: number;
}

export class H264DecodeSession {
  private surfaceId: string = '';
  private state: DecodePipelineState = 'idle';
  private header: VideoHeaderParsed | null = null;
  private aus: VideoAccessUnitParsed[] = [];
  private detail: string = 'idle';
  private lastError: string = '';
  private firstFrameRendered: boolean = false;
  private decoderStarted: boolean = false;
  private inputQueued: number = 0;
  private outputFrames: number = 0;
  private decoderLastError: number = 0;

  bindSurface(surfaceId: string): void {
    this.surfaceId = surfaceId;
    this.state = 'surface_ready';
    this.detail = `surfaceId=${surfaceId}`;
    hilog.info(DOMAIN, TAG, 'surface bound %{public}s', surfaceId);
  }

  /**
   * Fold/layout: rebind running decoder to a new XComponent surfaceId.
   * No bitstream re-inject; native Stop → SetSurface → Start + CSD replay.
   */
  rebindSurface(surfaceId: string): DecodePipelineStatus {
    const sid = surfaceId.trim();
    if (sid.length === 0 || sid === '0') {
      this.detail = 'rebind skipped: empty surfaceId';
      hilog.warn(DOMAIN, TAG, 'SURFACE_REBIND skipped empty surfaceId');
      return this.status();
    }
    this.surfaceId = sid;
    hilog.info(DOMAIN, TAG, 'SURFACE_LOST→REBIND %{public}s', sid);
    try {
      const dec = adbCore.videoDecoderRebindSurface(sid) as Record<string, Object>;
      this.applyDecoderRecord(dec);
      if (this.firstFrameRendered) {
        this.state = 'first_frame';
      } else if (this.decoderStarted) {
        this.state = 'decoding';
      }
      hilog.info(
        DOMAIN,
        TAG,
        'SURFACE_REBOUND sid=%{public}s first=%{public}s detail=%{public}s',
        sid,
        this.firstFrameRendered ? '1' : '0',
        this.detail
      );
    } catch (e) {
      this.state = 'error';
      this.detail = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'SURFACE_REBIND failed %{public}s', this.detail);
    }
    return this.status();
  }

  /**
   * Inject EasyControl video buffer: frame via Rust, then start OH_VideoDecoder → surface.
   */
  injectBitstream(buffer: ArrayBuffer): DecodePipelineStatus {
    try {
      const hdr = parseVideoStreamHeader(buffer);
      this.header = hdr;
      this.state = 'header_ok';
      this.aus = parseAccessUnitStream(buffer, hdr.consumed, 32);
      let annexB = 0;
      for (let i = 0; i < this.aus.length; i++) {
        if (this.aus[i].annexB) {
          annexB++;
        }
      }
      if (hdr.csd0AnnexB) {
        annexB++;
      }
      this.state = 'framed';
      this.detail =
        `framed h265=${hdr.useH265} ${hdr.width}x${hdr.height} aus=${this.aus.length} annexB=${annexB}`;
      hilog.info(DOMAIN, TAG, 'framing ok %{public}s', this.detail);

      if (this.surfaceId.length === 0) {
        this.detail += '; surface not bound — decoder deferred';
        return this.status();
      }

      const dec = adbCore.videoDecoderPlayBitstream(this.surfaceId, buffer) as Record<string, Object>;
      this.applyDecoderRecord(dec);
      if (this.decoderLastError !== 0) {
        this.state = 'error';
        this.detail = `decoder error=${this.decoderLastError} ${String(dec['detail'] ?? '')}`;
        hilog.error(DOMAIN, TAG, '%{public}s', this.detail);
        return this.status();
      }
      this.state = this.firstFrameRendered ? 'first_frame' : 'decoding';
      hilog.info(
        DOMAIN,
        TAG,
        'decoder started inQ=%{public}d out=%{public}d first=%{public}s detail=%{public}s',
        this.inputQueued,
        this.outputFrames,
        this.firstFrameRendered ? 'yes' : 'no',
        this.detail
      );
      return this.status();
    } catch (e) {
      this.state = 'error';
      this.lastError = e instanceof Error ? e.message : String(e);
      this.detail = this.lastError;
      hilog.error(DOMAIN, TAG, 'inject failed %{public}s', this.lastError);
      return this.status();
    }
  }

  /** Poll native decoder counters (async output callbacks). */
  refreshDecoderStatus(): DecodePipelineStatus {
    try {
      const dec = adbCore.videoDecoderStatus() as Record<string, Object>;
      this.applyDecoderRecord(dec);
      if (this.firstFrameRendered) {
        this.state = 'first_frame';
      } else if (this.decoderStarted && this.state !== 'error') {
        this.state = 'decoding';
      }
      if (this.decoderLastError !== 0 && !this.firstFrameRendered) {
        this.state = 'error';
      }
    } catch (e) {
      this.detail = e instanceof Error ? e.message : String(e);
    }
    return this.status();
  }

  /**
   * Block in native briefly waiting for first rendered buffer.
   * Prefer refreshDecoderStatus + timer on UI thread for production; this is for fixture proof.
   */
  waitFirstFrame(timeoutMs: number): DecodePipelineStatus {
    try {
      const dec = adbCore.videoDecoderWaitFirstFrame(timeoutMs) as Record<string, Object>;
      this.applyDecoderRecord(dec);
      if (this.firstFrameRendered) {
        this.state = 'first_frame';
      } else if (this.decoderLastError !== 0) {
        this.state = 'error';
      }
    } catch (e) {
      this.state = 'error';
      this.detail = e instanceof Error ? e.message : String(e);
    }
    return this.status();
  }

  private applyDecoderRecord(dec: Record<string, Object>): void {
    this.decoderStarted = Boolean(dec['started']);
    this.firstFrameRendered = Boolean(dec['firstFrameRendered']);
    this.inputQueued = Number(dec['inputQueued'] ?? 0);
    this.outputFrames = Number(dec['outputFrames'] ?? 0);
    this.decoderLastError = Number(dec['lastError'] ?? 0);
    const d = dec['detail'];
    if (typeof d === 'string' && d.length > 0) {
      this.detail = d;
    }
    const w = Number(dec['width'] ?? 0);
    const h = Number(dec['height'] ?? 0);
    if (w > 0 && h > 0 && this.header !== null) {
      // keep framed header sizes; decoder may echo same
    }
  }

  status(): DecodePipelineStatus {
    const hdr = this.header;
    const firstPts = this.aus.length > 0 ? this.aus[0].ptsUs : -1;
    let annexBCount = 0;
    for (let i = 0; i < this.aus.length; i++) {
      if (this.aus[i].annexB) {
        annexBCount++;
      }
    }
    if (hdr !== null && hdr.csd0AnnexB) {
      annexBCount++;
    }
    return {
      state: this.state,
      surfaceId: this.surfaceId,
      width: hdr !== null ? hdr.width : 0,
      height: hdr !== null ? hdr.height : 0,
      useH265: hdr !== null ? hdr.useH265 : false,
      auCount: this.aus.length,
      annexBCount: annexBCount,
      firstPtsUs: firstPts,
      detail: this.detail,
      framingOk: this.state === 'framed' || this.state === 'decoding' || this.state === 'first_frame',
      firstFrameRendered: this.firstFrameRendered,
      decoderStarted: this.decoderStarted,
      inputQueued: this.inputQueued,
      outputFrames: this.outputFrames,
      lastError: this.decoderLastError,
    };
  }

  release(): void {
    try {
      adbCore.videoDecoderRelease();
    } catch (_e) {
      // native may already be down
    }
    this.surfaceId = '';
    this.header = null;
    this.aus = [];
    this.state = 'idle';
    this.detail = 'released';
    this.firstFrameRendered = false;
    this.decoderStarted = false;
    this.inputQueued = 0;
    this.outputFrames = 0;
    this.decoderLastError = 0;
  }
}
