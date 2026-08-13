/**
 * Gate B probe result DTO — no libadb_core.so dependency.
 */

export interface GateBProbeResult {
  ok: boolean;
  version: string;
  capabilities: string;
  roundTripOk: boolean;
  detail: string;
}

/** Local OH_VideoDecoder / OH_AudioCodec CreateByMime probe. */
export interface DecoderCapsResult {
  avc: boolean;
  hevc: boolean;
  opus: boolean;
  aac: boolean;
  detail: string;
}
