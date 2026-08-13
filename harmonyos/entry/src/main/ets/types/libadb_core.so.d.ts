/**
 * Type declarations for Gate B/E/D native module staged at entry/libs/arm64-v8a/libadb_core.so
 * (produced by scripts/build_native_ohos.sh; Assemble runs that via entry/hvigorfile.ts → buildNativeOhos).
 */
declare module 'libadb_core.so' {
  export interface VideoDecoderStatusNative {
    started: boolean;
    firstFrameRendered: boolean;
    inputQueued: number;
    outputFrames: number;
    streamChanged: number;
    lastError: number;
    width: number;
    height: number;
    useH265: boolean;
    surfaceId: string;
    detail: string;
  }

  export interface DecoderCapsNative {
    avc: boolean;
    hevc: boolean;
    opus: boolean;
    aac: boolean;
    detail: string;
  }

  export interface LiveSessionStartNative {
    host: string;
    adbPort: number;
    serverPort: number;
    surfaceId: string;
    jarBytes: ArrayBuffer;
    privateKeyPem: string;
    publicKeyLine?: ArrayBuffer;
    appVersionCode: number;
    maxSize: number;
    maxFps: number;
    maxVideoBit: number;
    listenClip: boolean;
    isAudio: boolean;
    keepAwake: boolean;
    supportH265: boolean;
    virtualWidth: number;
    virtualHeight: number;
    virtualDpi: number;
  }

  export interface LiveSessionStatusNative {
    phase: string;
    detail: string;
    mode: string;
    width: number;
    height: number;
    useH265: boolean;
    ausFed: number;
    firstFrame: boolean;
    live: boolean;
    canAudio: boolean;
    useOpus: boolean;
    audioStarted: boolean;
    audioFrames: number;
    audioDetail: string;
  }

  export interface AdbAuthOptsNative {
    host: string;
    adbPort: number;
    privateKeyPem: string;
    publicKeyLine?: ArrayBuffer;
  }

  export interface SyncPullResultNative {
    data: ArrayBuffer;
    sha256Hex: string;
    remotePath: string;
    mtime: number;
    byteLen: number;
  }

  export interface AdbPairOptsNative {
    host: string;
    pairPort: number;
    pairCode: string;
    privateKeyPem: string;
    publicKeyLine?: ArrayBuffer;
    deviceName?: string;
    timeoutSec?: number;
  }

  export interface AdbPairResultNative {
    ok: boolean;
    host: string;
    pairPort: number;
    detail: string;
  }

  const adbCore: {
    nativeVersion: () => string;
    nativeCapabilities: () => string;
    roundTripBytes: (input: ArrayBuffer) => ArrayBuffer;
    encodeAdbConnect: () => ArrayBuffer;
    encodeAdbOkay: (localId: number, remoteId: number) => ArrayBuffer;
    encodeAdbOpen: (localId: number, dest: string) => ArrayBuffer;
    parseVideoStreamHeader: (input: ArrayBuffer) => Object;
    parseVideoAccessUnit: (input: ArrayBuffer) => Object;
    encodeControlKeepAlive: () => ArrayBuffer;
    encodeControlTouch: (
      action: number,
      pointerId: number,
      x: number,
      y: number,
      offsetTime: number
    ) => ArrayBuffer;
    encodeControlClipboard: (text: string) => ArrayBuffer;
    videoDecoderPlayBitstream: (surfaceId: string, bitstream: ArrayBuffer) => VideoDecoderStatusNative;
    videoDecoderWaitFirstFrame: (timeoutMs: number) => VideoDecoderStatusNative;
    videoDecoderStatus: () => VideoDecoderStatusNative;
    videoDecoderRelease: () => void;
    /** Fold/layout: rebind NativeWindow; does not stop live ADB session. */
    videoDecoderRebindSurface: (surfaceId: string) => VideoDecoderStatusNative;
    /** CreateByMime + Destroy for AVC/HEVC/Opus/AAC (JS thread; no surface). */
    probeDecoderCaps: () => DecoderCapsNative;
    /** videoSource / cameraFacing / startApp are discrete args (object fields were dropped by NAPI). */
    liveSessionStart: (
      opts: LiveSessionStartNative | Record<string, Object>,
      videoSource: string,
      cameraFacing: string,
      startApp: string
    ) => LiveSessionStatusNative;
    liveSessionStatus: () => LiveSessionStatusNative;
    /** Create OH_VideoDecoder on JS thread when phase === configuring. */
    liveSessionAttachDecoder: () => LiveSessionStatusNative;
    liveSessionWriteControl: (packet: ArrayBuffer) => boolean;
    liveSessionStop: () => void;
    /** Short-lived ADB shell screencap → PNG. */
    adbScreencapPng: (opts: AdbAuthOptsNative | Record<string, Object>) => ArrayBuffer;
    /** Short-lived ADB shell:<cmd> (separate from Gate D live mux). */
    adbShellExec: (opts: AdbAuthOptsNative | Record<string, Object>, command: string) => string;
    /** Short-lived ADB sync: RECV pull (absolute remote path; max 32 MiB). */
    adbSyncPull: (
      opts: AdbAuthOptsNative | Record<string, Object>,
      remotePath: string
    ) => SyncPullResultNative;
    /** Android 11+ wireless pairing (TLS1.3 + SPAKE2 + peer-info). */
    adbPairWireless: (opts: AdbPairOptsNative | Record<string, Object>) => AdbPairResultNative;
    adbNormalizePairCode: (pairCode: string) => string;
  };
  export default adbCore;
}
