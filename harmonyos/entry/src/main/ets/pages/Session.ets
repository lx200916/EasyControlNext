/**
 * U5 Session fullscreen shell — live Gate D mirror when reachable, fixture fallback.
 * Chrome matches Android FullActivity + SmallView: Back / Home / Recents / Disconnect
 * + extras (power, rotate, light, nav, clipboard, notification panel, audio relay,
 *   volume, screenshot, ADB sync pull, quick-launch app, expanded/hover keyboard).
 *
 * Hover (foldPosture === 'half'): upper = letterboxed video; lower = control dock (+ optional
 * QWERTY). Do not use phone bottom bar or wide side rail in half-fold.
 * Wide/side rail (preferSplit): narrow single-column chrome by default; opens wider 3-column
 * tool pad + in-rail QWERTY when the on-screen keyboard is shown (≤50% height, width-capped).
 * Portrait expanded extras: Column — tool row on top, optional QWERTY below.
 * Fold/layout: XComponent surface rebind without tearing down ADB.
 */

import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppErrorLog } from '../common/AppErrorLog';
import { AppSettings } from '../common/AppSettings';
import { FoldPosture } from '../common/Breakpoint';
import { Device } from '../model/Device';
import { DeviceStore } from '../model/DeviceStore';
import { loadDecodeFixture } from '../media/FixtureBitstream';
import { DecodePipelineStatus, H264DecodeSession } from '../media/H264DecodeSession';
import {
  DISPLAY_STATE_OFF,
  DISPLAY_STATE_ON,
  DISPLAY_STATE_UNKNOWN,
  EncodedControl,
  encodeChangeResolutionWh,
  encodeClipboardPacket,
  encodeKeyPacket,
  encodeLightPacket,
  encodePowerPacket,
  encodeRotatePacket,
  encodeTouchPacket,
  KEYCODE_APP_SWITCH,
  KEYCODE_BACK,
  KEYCODE_DEL,
  KEYCODE_ENTER,
  KEYCODE_HOME,
  KEYCODE_SPACE,
  KEYCODE_VOLUME_DOWN,
  KEYCODE_VOLUME_UP,
  keyCodeForDigit,
  keyCodeForLetter,
  META_SHIFT_ON,
  MOTION_DOWN,
  MOTION_MOVE,
  MOTION_UP,
} from '../session/ControlStub';
import {
  captureRemoteScreenshot,
  expandRemoteNotificationPanel,
  InstalledAppRow,
  attachLiveDecoder,
  isHevcDecoderUnavailable,
  joinRemotePath,
  launchRemoteAppForeground,
  listRemoteDirectory,
  listRemoteThirdPartyApps,
  LiveStatus,
  parentRemoteDir,
  pollLiveStatus,
  prefetchLiveMirrorAssets,
  pullRemoteFile,
  rebindLiveSurface,
  RemoteDirEntry,
  remotePullBasename,
  startLiveMirror,
  stopLiveMirror,
  writeLiveControl,
} from '../session/LiveMirror';
import { consumeSessionLaunch } from '../session/SessionLaunch';

const SESSION_LOG_DOMAIN: number = 0x0001;
const SESSION_LOG_TAG: string = 'SessionDecode';
const ICON_SIZE: number = 22;
const HIT: number = 44;
/** Hover / laptop dock: shorter landscape toolbar chips, wider hit targets. */
const HOVER_TOOL_H: number = 52;
const HOVER_KB_KEY_H: number = 44;
const CHROME_BG: string = '#E6121214';
const ICON_TINT: string = '#F2F2F2';
const ICON_DANGER: string = '#F2B8B5';
const ICON_BTN_BG: string = '#22FFFFFF';
const ICON_BTN_PRESSED: string = '#33FFFFFF';
const ICON_BTN_ACCENT: string = '#334A90E2';
/** Coalesce rapid fold/layout surface recreate events. */
const REBIND_COALESCE_MS: number = 64;
/** Narrow single-column side rail (keyboard collapsed). */
const SIDE_RAIL_NARROW_W: number = 84;
/** Floor / ceiling for wide side-rail width (vp) when keyboard is open. */
const SIDE_RAIL_MIN_W: number = 260;
const SIDE_RAIL_MAX_W: number = 380;
/** Soft max width for portrait / hover QWERTY so it is not full-bleed on large screens. */
const KB_PANEL_MAX_W: number = 480;
/** Compact QWERTY block height estimate (vp) when under half-screen clamp. */
const EXPANDED_KB_COMPACT_VP: number = 200;

const KB_ROW1: string[] = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
const KB_ROW2: string[] = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
const KB_ROW3: string[] = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

@Component
export struct Session {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('preferSplit') preferSplit: boolean;
  @Consume('foldPosture') @Watch('onFoldPostureChange') foldPosture: FoldPosture;
  @Consume('widthVp') widthVp: number;
  @Consume('heightVp') heightVp: number;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  @Prop uuid: string = '';
  @State private deviceName: string = '';
  @State private statusLine: string = '';
  @State private firstFrameOk: boolean = false;
  @State private surfaceReady: boolean = false;
  @State private videoW: number = 0;
  @State private videoH: number = 0;
  @State private usingLive: boolean = false;
  @State private usingFixture: boolean = false;
  @State private lightOn: boolean = true;
  @State private showNavBar: boolean = true;
  @State private showExtras: boolean = false;
  @State private showAppPicker: boolean = false;
  @State private showFilePull: boolean = false;
  @State private browsePath: string = '/sdcard/Download';
  @State private browseEntries: RemoteDirEntry[] = [];
  @State private browseLoading: boolean = false;
  @State private browseError: string = '';
  @State private pulling: boolean = false;
  /** Hover defaults to QWERTY dock; phone/expanded keep off until toggled. */
  @State private showKeyboard: boolean = false;
  @State private shiftOn: boolean = false;
  /**
   * Session audio-relay intent (Device.isAudio → server isAudio).
   * While live, toggling reconnects so the server encode handshake matches.
   */
  @State private audioRelayOn: boolean = false;
  /** Last known native audio playback status (from live poll). */
  @State private audioPlaying: boolean = false;
  @State private audioCodecLabel: string = '';
  /** One-shot toast when HW audio decode fails for this session. */
  private audioFailToasted: boolean = false;
  @State private capturing: boolean = false;
  @State private appLoading: boolean = false;
  @State private appError: string = '';
  @State private appQuery: string = '';
  @State private appRows: InstalledAppRow[] = [];
  /** Session-scoped app list cache (avoids re-resolving labels on reopen). */
  private appCacheKey: string = '';
  private appCacheRows: InstalledAppRow[] = [];
  /** Video host area (vp) for Contain letterbox. */
  @State private hostW: number = 0;
  @State private hostH: number = 0;
  @State private fittedW: number = 0;
  @State private fittedH: number = 0;
  /** True only while fold/layout surface rebind is in progress — light overlay, no Gate D. */
  @State private surfaceRebinding: boolean = false;
  private xController: XComponentController = new XComponentController();
  private decodeSession: H264DecodeSession = new H264DecodeSession();
  private touchStartMs: number = 0;
  private pollTimer: number = -1;
  private device: Device | undefined = undefined;
  private sessionStarted: boolean = false;
  /** Sticky: once live connected this Session, never cold-start Gate D on fold. */
  private everLive: boolean = false;
  private lastSurfaceId: string = '';
  private fixtureBuffer: ArrayBuffer | null = null;
  /** Coalesce fold/layout onLoad rebinds. */
  private rebindTimer: number = -1;
  private pendingRebindSid: string = '';
  private rebindInFlight: boolean = false;
  private rebindT0Ms: number = 0;
  /** From manage-sheet: open app picker once live is up. */
  private pendingOpenAppPicker: boolean = false;
  private appPickerAutoOpened: boolean = false;
  /** One-shot: retry live with AVC if HEVC CreateByMime fails on this device. */
  private hevcAvcFallbackTried: boolean = false;
  /** Android Client on-connect actions (wake / lightOff / custom res) — once per session. */
  private connectActionsApplied: boolean = false;
  private closeActionsApplied: boolean = false;

  aboutToAppear(): void {
    const launch = consumeSessionLaunch();
    this.pendingOpenAppPicker = launch.openAppPicker;
    if (launch.overrideDevice !== undefined) {
      this.device = launch.overrideDevice;
    } else {
      this.device = DeviceStore.findByUuid(this.uuid);
    }
    this.deviceName = this.device !== undefined ? this.device.name : 'Session';
    this.showNavBar = this.device !== undefined ? this.device.showNavBarOnConnect : true;
    this.audioRelayOn = this.device !== undefined ? this.device.isAudio : false;
    this.audioFailToasted = false;
    this.statusLine = '正在连接…';
    this.firstFrameOk = false;
    this.connectActionsApplied = false;
    this.closeActionsApplied = false;
    this.applyHoverChromeDefaults();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      void prefetchLiveMirrorAssets(ctx);
    } catch (_e) {
      // preview hosts
    }
  }

  private onFoldPostureChange(): void {
    this.applyHoverChromeDefaults();
    this.updateFittedSize();
  }

  /** Half-fold → laptop chrome: show landscape QWERTY dock by default. */
  private applyHoverChromeDefaults(): void {
    if (this.foldPosture === 'half') {
      this.showKeyboard = true;
      this.showExtras = false;
      hilog.info(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'HOVER_LAYOUT dockSpan=%{public}d widthVp=%{public}d heightVp=%{public}d',
        Math.floor(this.hoverDockSpanVp()),
        Math.floor(this.widthVp),
        Math.floor(this.heightVp)
      );
    }
  }

  aboutToDisappear(): void {
    if (this.rebindTimer >= 0) {
      clearTimeout(this.rebindTimer);
      this.rebindTimer = -1;
    }
    this.pendingRebindSid = '';
    this.clearPollTimer();
    this.appCacheKey = '';
    this.appCacheRows = [];
    this.applyCloseActions();
    stopLiveMirror();
    this.decodeSession.release();
  }

  private isHover(): boolean {
    return this.foldPosture === 'half';
  }

  /**
   * Half-fold windows often still report portrait widthVp. Treat dock as a wide
   * landscape band using the longer window edge as the effective dock span.
   */
  private hoverDockSpanVp(): number {
    const w = this.widthVp > 0 ? this.widthVp : 360;
    const h = this.heightVp > 0 ? this.heightVp : 780;
    if (this.isHover()) {
      return Math.max(w, h * 0.5);
    }
    return w;
  }

  private clearPollTimer(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800,
      });
    } catch (_e) {
      // preview hosts
    }
  }

  private updateFittedSize(): void {
    if (this.hostW <= 0 || this.hostH <= 0) {
      return;
    }
    if (this.videoW <= 0 || this.videoH <= 0) {
      this.fittedW = this.hostW;
      this.fittedH = this.hostH;
      return;
    }
    // Hover upper pane: prefer width-driven Contain (landscape-friendly letterbox).
    let scale = this.hostW / this.videoW;
    if (this.videoH * scale > this.hostH) {
      scale = this.hostH / this.videoH;
    }
    if (!this.isHover()) {
      scale = Math.min(this.hostW / this.videoW, this.hostH / this.videoH);
    }
    this.fittedW = Math.max(1, Math.floor(this.videoW * scale));
    this.fittedH = Math.max(1, Math.floor(this.videoH * scale));
  }

  private minimalStatus(width: number, height: number): string {
    if (width > 0 && height > 0) {
      return `${width}×${height}`;
    }
    return '';
  }

  private applyStatus(st: DecodePipelineStatus): void {
    this.firstFrameOk = st.firstFrameRendered;
    this.videoW = st.width;
    this.videoH = st.height;
    this.updateFittedSize();
    if (st.firstFrameRendered) {
      this.statusLine = this.minimalStatus(st.width, st.height);
    } else {
      this.statusLine = '';
    }
  }

  private applyLive(st: LiveStatus, fromRebind: boolean = false): void {
    // Sticky: once live is up, do not clear usingLive on transient poll gaps during fold rebind.
    const liveActive = st.live || st.phase === 'streaming' || st.phase === 'connecting' ||
      st.phase === 'pushing' || st.phase === 'launching' || st.phase === 'configuring';
    if (liveActive) {
      this.usingLive = true;
      this.usingFixture = false;
      this.everLive = true;
    } else if (!fromRebind && !this.surfaceRebinding &&
      (st.phase === 'error' || st.phase === 'stopped')) {
      // Never drop sticky live during fold surface rebind.
      this.usingLive = false;
    }
    if (st.width > 0 && st.height > 0) {
      this.videoW = st.width;
      this.videoH = st.height;
      this.updateFittedSize();
    }
    this.firstFrameOk = st.firstFrame;
    if (st.firstFrame) {
      this.statusLine = this.minimalStatus(st.width, st.height);
      if (this.surfaceRebinding) {
        this.finishSurfaceRebind(true);
      }
    } else if (fromRebind || this.surfaceRebinding) {
      // Fold path: never show full Gate D "正在连接…" chrome.
      this.statusLine = '';
    } else if (st.phase === 'error') {
      this.statusLine = '连接失败';
    } else {
      this.statusLine = this.connectingLabel(st);
    }
    this.applyAudioLiveStatus(st);
    // Match Android Client: run wake / custom-res once main stream is up.
    if (!fromRebind && (st.phase === 'streaming' || st.firstFrame || st.live)) {
      this.applyConnectActions();
    }
  }

  private applyAudioLiveStatus(st: LiveStatus): void {
    const wasPlaying = this.audioPlaying;
    this.audioPlaying = st.audioStarted && st.canAudio;
    if (st.canAudio) {
      this.audioCodecLabel = st.useOpus ? 'Opus HW' : 'AAC HW';
    } else {
      this.audioCodecLabel = '';
    }
    if (st.audioDetail.indexOf('unavailable') >= 0 && this.audioRelayOn && !this.audioFailToasted) {
      this.audioFailToasted = true;
      this.toast('音频硬件解码不可用，暂无声音');
      AppErrorLog.w('audio', '硬件解码不可用');
      hilog.warn(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'audio HW unavailable %{public}s',
        st.audioDetail
      );
    } else if (st.audioStarted && !wasPlaying && st.canAudio) {
      hilog.info(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'audio playing codec=%{public}s frames=%{public}d',
        this.audioCodecLabel,
        st.audioFrames
      );
    }
  }

  /**
   * Android Client.java on-connect: custom res → wake → restore panel → delayed lightOff.
   * Retries until main TCP accepts control (HEVC→AVC reconnect / early poll races).
   * Without a successful wake, MIUI often mirrors lock-wallpaper with dead touch.
   */
  private applyConnectActions(): void {
    if (this.connectActionsApplied || this.device === undefined) {
      return;
    }
    if (!this.usingLive || this.usingFixture) {
      return;
    }
    const d = this.device;
    if (d.customResolutionOnConnect) {
      if (!this.trySendControl(encodeChangeResolutionWh(d.customResolutionWidth, d.customResolutionHeight))) {
        return;
      }
    }
    if (d.wakeOnConnect) {
      if (!this.trySendControl(encodePowerPacket(1))) {
        return;
      }
      // Clear prior light-off / POWER_MODE_OFF so the panel is interactive again.
      // lightOffOnConnect (if set) turns it back off after 2s, matching Android Client.
      if (!this.trySendControl(encodeLightPacket(DISPLAY_STATE_ON))) {
        return;
      }
      this.lightOn = true;
    }
    this.connectActionsApplied = true;
    hilog.info(
      SESSION_LOG_DOMAIN,
      SESSION_LOG_TAG,
      'connect actions applied wake=%{public}s lightOffLater=%{public}s',
      d.wakeOnConnect ? '1' : '0',
      d.lightOffOnConnect ? '1' : '0'
    );
    if (d.lightOffOnConnect) {
      setTimeout(() => {
        if (this.usingLive && !this.usingFixture) {
          this.sendControl(encodeLightPacket(DISPLAY_STATE_UNKNOWN));
          this.lightOn = false;
        }
      }, 2000);
    }
  }

  /** Silent control write for connect/close sequencing (no toast spam on retry). */
  private trySendControl(packet: EncodedControl): boolean {
    if (!packet.ok || packet.bytes === null) {
      return false;
    }
    if (!this.usingLive || this.usingFixture) {
      return false;
    }
    return writeLiveControl(packet.bytes);
  }

  /** Android Client.close: lock preferred over light restore. */
  private applyCloseActions(): void {
    if (this.closeActionsApplied || this.device === undefined) {
      return;
    }
    if (!this.usingLive || this.usingFixture) {
      return;
    }
    this.closeActionsApplied = true;
    const d = this.device;
    if (d.lockOnClose) {
      this.sendControl(encodePowerPacket(0));
    } else if (d.lightOnClose) {
      this.sendControl(encodeLightPacket(DISPLAY_STATE_ON));
      this.sendControl(encodeLightPacket(DISPLAY_STATE_OFF));
    }
  }

  private finishSurfaceRebind(gotFrame: boolean): void {
    if (!this.surfaceRebinding) {
      return;
    }
    const dt = this.rebindT0Ms > 0 ? Date.now() - this.rebindT0Ms : -1;
    hilog.info(
      SESSION_LOG_DOMAIN,
      SESSION_LOG_TAG,
      'SURFACE_REBIND_DONE frame=%{public}s +%{public}dms',
      gotFrame ? '1' : '0',
      dt
    );
    this.surfaceRebinding = false;
    this.rebindT0Ms = 0;
  }

  /** preferSplit rail expands to multi-column only while the on-screen keyboard is open. */
  private isWideRail(): boolean {
    return !this.isHover() && this.preferSplit && this.showKeyboard;
  }

  /** Side rail width: narrow single-column by default; wide when keyboard is shown. */
  private sideRailWidthVp(): number {
    if (!this.isWideRail()) {
      return SIDE_RAIL_NARROW_W;
    }
    const w = this.widthVp > 0 ? this.widthVp : 840;
    return Math.min(SIDE_RAIL_MAX_W, Math.max(SIDE_RAIL_MIN_W, Math.floor(w * 0.38)));
  }

  /** Virtual keyboard may occupy at most half the window height. */
  private keyboardMaxHeightVp(): number {
    const h = this.heightVp > 0 ? this.heightVp : 780;
    return Math.max(160, Math.floor(h * 0.5));
  }

  /** QWERTY panel width — rail content width, or capped centered band on portrait/hover. */
  private keyboardPanelWidthVp(): number {
    if (this.isWideRail()) {
      return Math.max(160, this.sideRailWidthVp() - 16);
    }
    const w = this.widthVp > 0 ? this.widthVp : 360;
    return Math.min(KB_PANEL_MAX_W, Math.max(200, Math.floor(w - 24)));
  }

  private kbKeyHeightVp(): number {
    if (this.isHover()) {
      return HOVER_KB_KEY_H;
    }
    // Side-rail QWERTY stays compact so the panel fits under the half-height clamp.
    if (this.isWideRail()) {
      return 32;
    }
    return 36;
  }

  /** Portrait chrome bottom inset for the capped QWERTY block. */
  private expandedKbInsetVp(): number {
    return Math.min(EXPANDED_KB_COMPACT_VP, this.keyboardMaxHeightVp());
  }

  /** Chrome insets so stable XComponent host sizes correctly without remounting. */
  private chromeRightInsetVp(): number {
    if (!this.isHover() && this.preferSplit) {
      return this.sideRailWidthVp();
    }
    return 0;
  }

  private chromeBottomInsetVp(): number {
    if (this.isHover()) {
      const h = this.heightVp > 0 ? this.heightVp : 780;
      return Math.max(160, Math.floor(h * 0.5));
    }
    if (this.preferSplit) {
      // Keyboard (when open) lives inside the side rail — no bottom strip.
      return 0;
    }
    let bar = 16 + HIT + this.safeBottomVp;
    if (this.showExtras) {
      bar += HIT + 10;
      if (this.showKeyboard) {
        bar += this.expandedKbInsetVp();
      }
    }
    return bar;
  }

  private toggleExpandedKeyboard(): void {
    const next = !this.showKeyboard;
    this.showKeyboard = next;
    if (next && !this.isHover() && !this.preferSplit) {
      // Portrait: keyboard lives in the expanded extras Column.
      this.showExtras = true;
    }
    // preferSplit rail width changes with keyboard — refresh letterbox metrics.
    this.updateFittedSize();
  }

  private async toggleAudioRelay(): Promise<void> {
    const next = !this.audioRelayOn;
    this.audioRelayOn = next;
    const device = this.device;
    if (device !== undefined) {
      device.isAudio = next;
      try {
        await DeviceStore.upsert(device);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        hilog.warn(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'audio relay persist failed %{public}s', msg);
      }
    }
    if (this.usingLive && !this.usingFixture) {
      // Server encodes only when launched with isAudio=1 — reconnect to apply honestly.
      this.toast(next ? '已开启音频转接，正在重连…' : '已关闭音频转接，正在重连…');
      await this.reconnectLiveForAudio();
      return;
    }
    this.toast(next ? '已开启音频转接（下次连接生效）' : '已关闭音频转接');
  }

  /** Tear down + restart Gate D so server isAudio handshake matches the toggle. */
  private async reconnectLiveForAudio(): Promise<void> {
    this.clearPollTimer();
    this.firstFrameOk = false;
    this.connectActionsApplied = false;
    this.audioPlaying = false;
    this.audioCodecLabel = '';
    this.audioFailToasted = false;
    this.statusLine = this.audioRelayOn ? '正在重连（开启音频）…' : '正在重连（关闭音频）…';
    try {
      stopLiveMirror();
    } catch (_e) {
      // ignore
    }
    this.usingLive = false;
    this.sessionStarted = false;
    await this.runLiveOrFixture();
  }

  private connectingLabel(st: LiveStatus): string {
    if (st.phase === 'pushing') {
      return '正在准备…';
    }
    if (st.phase === 'launching') {
      return '正在启动…';
    }
    if (st.phase === 'configuring') {
      return '正在初始化…';
    }
    if (st.phase === 'streaming') {
      return '等待画面…';
    }
    if (st.phase === 'connecting') {
      return '正在连接…';
    }
    if (st.phase === 'error') {
      return '连接失败';
    }
    return '正在连接…';
  }

  private overlayStatusText(): string | Resource {
    if (this.surfaceRebinding) {
      return $r('app.string.session_restoring_surface');
    }
    if (!this.surfaceReady) {
      return $r('app.string.session_waiting_surface');
    }
    if (this.statusLine.length > 0 && !this.firstFrameOk) {
      return this.statusLine;
    }
    return $r('app.string.session_waiting_frame');
  }

  private showWaitingOverlay(): boolean {
    if (this.firstFrameOk) {
      return false;
    }
    // Fold rebind: brief light hint only; skip heavy "正在连接" gate.
    return true;
  }

  private startFirstFramePoll(): void {
    this.clearPollTimer();
    let ticks = 0;
    this.pollTimer = setInterval(() => {
      ticks++;
      if (this.usingLive && !this.usingFixture) {
        let live = pollLiveStatus();
        if (live.phase === 'configuring') {
          live = attachLiveDecoder();
        }
        this.applyLive(live);
        if (live.phase === 'error') {
          if (!this.hevcAvcFallbackTried && isHevcDecoderUnavailable(live.detail)) {
            this.hevcAvcFallbackTried = true;
            hilog.warn(
              SESSION_LOG_DOMAIN,
              SESSION_LOG_TAG,
              'HEVC unavailable on device — retry live with AVC'
            );
            this.toast('本机不支持 H.265，正在改用 H.264…');
            this.clearPollTimer();
            stopLiveMirror();
            void this.retryLiveWithAvc();
            return;
          }
          hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'LIVE_FAIL %{public}s', live.detail);
          AppErrorLog.e('live', live.detail);
          this.clearPollTimer();
          this.toast(this.liveFailToast(live.detail));
          void this.runFixtureInject();
          return;
        }
        if (live.firstFrame) {
          hilog.info(
            SESSION_LOG_DOMAIN,
            SESSION_LOG_TAG,
            'LIVE_FIRST_FRAME_OK aus=%{public}d %{public}dx%{public}d',
            live.ausFed,
            live.width,
            live.height
          );
          this.clearPollTimer();
          this.startLiveStatusPoll();
        } else if (ticks >= 600) {
          const progressing = live.ausFed > 0 || live.phase === 'streaming' ||
            live.phase === 'connecting' || live.phase === 'pushing' ||
            live.phase === 'launching' || live.phase === 'configuring';
          if (progressing && live.ausFed > 0 && ticks < 1200) {
            return;
          }
          hilog.error(
            SESSION_LOG_DOMAIN,
            SESSION_LOG_TAG,
            'LIVE_TIMEOUT aus=%{public}d %{public}s',
            live.ausFed,
            live.detail
          );
          this.clearPollTimer();
          this.toast('连接超时，请稍后重试');
          stopLiveMirror();
          void this.runFixtureInject();
        }
        return;
      }

      const st = this.decodeSession.refreshDecoderStatus();
      this.applyStatus(st);
      if (st.firstFrameRendered) {
        hilog.info(
          SESSION_LOG_DOMAIN,
          SESSION_LOG_TAG,
          'FIRST_FRAME_OK out=%{public}d detail=%{public}s',
          st.outputFrames,
          st.detail
        );
        this.clearPollTimer();
      } else if (st.lastError !== 0 || ticks >= 40) {
        hilog.error(
          SESSION_LOG_DOMAIN,
          SESSION_LOG_TAG,
          'FIRST_FRAME_PENDING err=%{public}d ticks=%{public}d detail=%{public}s',
          st.lastError,
          ticks,
          st.detail
        );
        this.clearPollTimer();
      }
    }, 100) as number;
  }

  private startLiveStatusPoll(): void {
    this.clearPollTimer();
    this.pollTimer = setInterval(() => {
      const live = pollLiveStatus();
      this.applyLive(live);
      if (live.phase === 'error' || live.phase === 'stopped' || live.phase === 'idle') {
        this.clearPollTimer();
      }
    }, 500) as number;
  }

  private async runFixtureInject(): Promise<void> {
    this.usingFixture = true;
    this.usingLive = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const fixture = await loadDecodeFixture(ctx);
      this.fixtureBuffer = fixture;
      const st = this.decodeSession.injectBitstream(fixture);
      this.applyStatus(st);
      hilog.info(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'inject framingOk=%{public}s started=%{public}s detail=%{public}s',
        st.framingOk ? '1' : '0',
        st.decoderStarted ? '1' : '0',
        st.detail
      );
      if (st.decoderStarted && !st.firstFrameRendered) {
        this.startFirstFramePoll();
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.statusLine = msg;
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'inject exception %{public}s', msg);
      AppErrorLog.e('fixture', msg);
    }
  }

  private async runLiveOrFixture(): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      await this.runFixtureInject();
      return;
    }
    this.hevcAvcFallbackTried = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const sid = this.xController.getXComponentSurfaceId();
      const st = await startLiveMirror(ctx, device, sid, false);
      this.applyLive(st);
      this.usingLive = true;
      this.usingFixture = false;
      this.everLive = true;
      this.startFirstFramePoll();
      this.maybeOpenPendingAppPicker();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'live start failed %{public}s', msg);
      AppErrorLog.e('live', msg);
      this.toast(this.liveFailToast(msg));
      stopLiveMirror();
      await this.runFixtureInject();
      this.maybeOpenPendingAppPicker();
    }
  }

  /** Prefer honest camera / virtual-display SDK errors over a generic connect toast. */
  private liveFailToast(detail: string): string {
    const d = detail.trim();
    if (d.length === 0) {
      return '连接失败，请稍后重试';
    }
    if (d.indexOf('Android') >= 0 || d.indexOf('相机') >= 0 || d.indexOf('虚拟') >= 0) {
      return d;
    }
    return `连接失败 · ${d}`;
  }

  /** Restart Gate D requesting AVC after HEVC CreateByMime failed on this OHOS device. */
  private async retryLiveWithAvc(): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      await this.runFixtureInject();
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const sid = this.xController.getXComponentSurfaceId();
      // Session-only: do not persist; next connect still honors saved useH265.
      device.useH265 = false;
      const st = await startLiveMirror(ctx, device, sid, true);
      this.applyLive(st);
      this.usingLive = true;
      this.usingFixture = false;
      this.everLive = true;
      this.startFirstFramePoll();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'AVC retry failed %{public}s', msg);
      this.clearPollTimer();
      this.toast('连接失败，请稍后重试');
      stopLiveMirror();
      await this.runFixtureInject();
    }
  }

  private maybeOpenPendingAppPicker(): void {
    if (!this.pendingOpenAppPicker || this.appPickerAutoOpened) {
      return;
    }
    this.appPickerAutoOpened = true;
    this.pendingOpenAppPicker = false;
    void this.openAppPicker();
  }

  /** Fold / layout: rebind decoder to new surface; never restart ADB / push jar. */
  private rebindDecoderSurface(sid: string): void {
    const surfaceId = sid.trim();
    if (surfaceId.length === 0 || surfaceId === '0') {
      hilog.warn(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_REBIND skipped empty sid');
      return;
    }
    if (this.rebindInFlight) {
      this.pendingRebindSid = surfaceId;
      hilog.info(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_REBIND coalesce sid=%{public}s', surfaceId);
      return;
    }
    this.rebindInFlight = true;
    this.surfaceRebinding = true;
    this.rebindT0Ms = Date.now();
    this.firstFrameOk = false;
    this.surfaceReady = true;
    this.statusLine = '';
    this.decodeSession.bindSurface(surfaceId);
    hilog.info(
      SESSION_LOG_DOMAIN,
      SESSION_LOG_TAG,
      'SURFACE_LOST→REBIND begin sid=%{public}s live=%{public}s ever=%{public}s',
      surfaceId,
      this.usingLive || this.everLive ? '1' : '0',
      this.everLive ? '1' : '0'
    );
    try {
      if (this.usingLive || this.everLive) {
        this.usingLive = true;
        this.usingFixture = false;
        const live = rebindLiveSurface(surfaceId);
        this.applyLive(live, true);
        const dt = Date.now() - this.rebindT0Ms;
        hilog.info(
          SESSION_LOG_DOMAIN,
          SESSION_LOG_TAG,
          'SURFACE_REBOUND +%{public}dms first=%{public}s phase=%{public}s',
          dt,
          live.firstFrame ? '1' : '0',
          live.phase
        );
        if (live.firstFrame) {
          this.finishSurfaceRebind(true);
        } else {
          this.startRebindFramePoll();
        }
        return;
      }
      if (this.usingFixture && this.fixtureBuffer !== null) {
        const rebound = this.decodeSession.rebindSurface(surfaceId);
        if (rebound.state !== 'error' && rebound.decoderStarted) {
          this.applyStatus(rebound);
          if (!rebound.firstFrameRendered) {
            this.startRebindFramePoll();
          } else {
            this.finishSurfaceRebind(true);
          }
          return;
        }
        const again = this.decodeSession.injectBitstream(this.fixtureBuffer);
        this.applyStatus(again);
        if (again.decoderStarted && !again.firstFrameRendered) {
          this.startRebindFramePoll();
        } else if (again.firstFrameRendered) {
          this.finishSurfaceRebind(true);
        }
        return;
      }
      // Session not yet live/fixture — only then allow cold start (should be rare on fold).
      hilog.warn(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_REBIND no live/fixture — cold start');
      this.surfaceRebinding = false;
      void this.runLiveOrFixture();
    } finally {
      this.rebindInFlight = false;
      if (this.pendingRebindSid.length > 0 && this.pendingRebindSid !== surfaceId) {
        const next = this.pendingRebindSid;
        this.pendingRebindSid = '';
        this.scheduleSurfaceRebind(next);
      } else {
        this.pendingRebindSid = '';
      }
    }
  }

  /** Short poll after fold rebind — never falls back to fixture / Gate D. */
  private startRebindFramePoll(): void {
    this.clearPollTimer();
    let ticks = 0;
    this.pollTimer = setInterval(() => {
      ticks++;
      if (this.usingLive || this.everLive) {
        const live = pollLiveStatus();
        this.applyLive(live, true);
        if (live.firstFrame) {
          hilog.info(
            SESSION_LOG_DOMAIN,
            SESSION_LOG_TAG,
            'LIVE_FIRST_FRAME_OK (rebind) aus=%{public}d +%{public}dms',
            live.ausFed,
            this.rebindT0Ms > 0 ? Date.now() - this.rebindT0Ms : -1
          );
          this.clearPollTimer();
          this.startLiveStatusPoll();
        } else if (ticks >= 50) {
          // ~5s: keep live sticky, drop overlay, keep status poll — do NOT fixture.
          hilog.warn(
            SESSION_LOG_DOMAIN,
            SESSION_LOG_TAG,
            'SURFACE_REBIND frame slow ticks=%{public}d — keep live',
            ticks
          );
          this.finishSurfaceRebind(false);
          this.clearPollTimer();
          this.startLiveStatusPoll();
        }
        return;
      }
      const st = this.decodeSession.refreshDecoderStatus();
      this.applyStatus(st);
      if (st.firstFrameRendered) {
        this.finishSurfaceRebind(true);
        this.clearPollTimer();
      } else if (ticks >= 40) {
        this.finishSurfaceRebind(false);
        this.clearPollTimer();
      }
    }, 100) as number;
  }

  private scheduleSurfaceRebind(sid: string): void {
    this.pendingRebindSid = sid;
    if (this.rebindTimer >= 0) {
      clearTimeout(this.rebindTimer);
      this.rebindTimer = -1;
    }
    this.rebindTimer = setTimeout(() => {
      this.rebindTimer = -1;
      const next = this.pendingRebindSid;
      this.pendingRebindSid = '';
      if (next.length > 0) {
        this.rebindDecoderSurface(next);
      }
    }, REBIND_COALESCE_MS) as number;
  }

  private onSurfaceLoad(): void {
    const sid = this.xController.getXComponentSurfaceId();
    if (sid.length === 0 || sid === '0') {
      hilog.warn(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_LOAD empty surfaceId — ignore');
      return;
    }
    this.surfaceReady = true;
    if (!this.sessionStarted) {
      this.sessionStarted = true;
      this.lastSurfaceId = sid;
      this.decodeSession.bindSurface(sid);
      hilog.info(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_READY sid=%{public}s', sid);
      void this.runLiveOrFixture();
      return;
    }
    if (sid !== this.lastSurfaceId) {
      hilog.info(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'SURFACE_RECREATE old=%{public}s new=%{public}s',
        this.lastSurfaceId,
        sid
      );
    } else {
      hilog.info(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'SURFACE_RELOAD same sid=%{public}s', sid);
    }
    this.lastSurfaceId = sid;
    this.scheduleSurfaceRebind(sid);
  }

  private onSurfaceDestroy(): void {
    hilog.warn(
      SESSION_LOG_DOMAIN,
      SESSION_LOG_TAG,
      'SURFACE_LOST sid=%{public}s (fold/layout) — awaiting onLoad rebind',
      this.lastSurfaceId
    );
    this.rebindT0Ms = Date.now();
    this.surfaceRebinding = true;
    this.firstFrameOk = false;
    // Keep surfaceReady true so UI does not flash full "等待画面/正在连接".
  }

  private closeSession(): void {
    if (this.rebindTimer >= 0) {
      clearTimeout(this.rebindTimer);
      this.rebindTimer = -1;
    }
    this.pendingRebindSid = '';
    this.clearPollTimer();
    this.applyCloseActions();
    stopLiveMirror();
    this.decodeSession.release();
    this.pathStack.pop();
  }

  private sendControl(packet: EncodedControl): void {
    if (!packet.ok || packet.bytes === null) {
      return;
    }
    if (this.usingLive && !this.usingFixture) {
      const wrote = writeLiveControl(packet.bytes);
      if (!wrote) {
        this.toast('控制发送失败');
      }
    }
  }

  private sendKey(keyCode: number, meta: number = 0): void {
    this.sendControl(encodeKeyPacket(keyCode, meta));
  }

  private sendPower(): void {
    this.sendControl(encodePowerPacket(-1));
  }

  private sendRotate(): void {
    this.sendControl(encodeRotatePacket());
  }

  private toggleLight(): void {
    const next = !this.lightOn;
    this.lightOn = next;
    if (next) {
      this.sendControl(encodeLightPacket(DISPLAY_STATE_ON));
      this.sendControl(encodeLightPacket(DISPLAY_STATE_OFF));
    } else {
      this.sendControl(encodeLightPacket(DISPLAY_STATE_UNKNOWN));
    }
  }

  private async expandNotificationPanel(): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0 || !this.usingLive || this.usingFixture) {
      this.toast('通知栏需要已连接的设备');
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await expandRemoteNotificationPanel(ctx, device);
      if (!result.ok) {
        this.toast(`通知栏失败 · ${result.detail}`);
        return;
      }
      this.toast('已展开通知栏');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'notification panel failed %{public}s', msg);
      this.toast('通知栏失败');
    }
  }

  private async sendClipboardHint(): Promise<void> {
    try {
      const board = pasteboard.getSystemPasteboard();
      const data = await board.getData();
      if (!data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        this.toast('剪贴板无文本');
        return;
      }
      const text = data.getPrimaryText();
      if (text === undefined || text.length === 0) {
        this.toast('剪贴板为空');
        return;
      }
      const packet = encodeClipboardPacket(text);
      if (!packet.ok) {
        this.toast(`剪贴板发送失败 · ${packet.detail}`);
        return;
      }
      this.sendControl(packet);
      this.toast('已发送剪贴板到远端');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.toast(`剪贴板失败 · ${msg}`);
    }
  }

  private async takeScreenshot(): Promise<void> {
    if (this.capturing) {
      return;
    }
    const device = this.device;
    if (device === undefined || device.address.length === 0 || !this.usingLive || this.usingFixture) {
      this.toast('截图需要已连接的设备');
      return;
    }
    this.capturing = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await captureRemoteScreenshot(ctx, device);
      if (!result.ok || result.png === null) {
        this.toast('截图失败');
        return;
      }
      const path = `${ctx.filesDir}/screenshot_${Date.now()}.png`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, result.png);
      fs.closeSync(file);
      this.toast('截图已保存');
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'screenshot failed %{public}s', msg);
      this.toast('截图失败');
    } finally {
      this.capturing = false;
    }
  }

  private openFilePullSheet(): void {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      this.toast('请先配置设备地址');
      return;
    }
    this.browsePath = '/sdcard/Download';
    this.browseEntries = [];
    this.browseError = '';
    this.browseLoading = true;
    this.showFilePull = true;
  }

  private async loadBrowseDir(path?: string): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      this.browseError = '请先配置设备地址';
      this.browseLoading = false;
      return;
    }
    const target = path !== undefined ? path : this.browsePath;
    this.browseLoading = true;
    this.browseError = '';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await listRemoteDirectory(ctx, device, target);
      this.browsePath = result.path;
      if (!result.ok) {
        this.browseEntries = [];
        this.browseError = result.detail.length > 0 ? result.detail : '无法打开目录';
        return;
      }
      this.browseEntries = result.entries;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'list dir failed %{public}s', msg);
      this.browseEntries = [];
      this.browseError = '无法打开目录';
    } finally {
      this.browseLoading = false;
    }
  }

  private browseGoUp(): void {
    if (this.pulling || this.browseLoading) {
      return;
    }
    const parent = parentRemoteDir(this.browsePath);
    if (parent === this.browsePath) {
      return;
    }
    void this.loadBrowseDir(parent);
  }

  private onBrowseEntryTap(entry: RemoteDirEntry): void {
    if (this.pulling || this.browseLoading) {
      return;
    }
    if (entry.isDirectory) {
      void this.loadBrowseDir(entry.path);
      return;
    }
    void this.pullSelectedFile(entry.path);
  }

  private async pullSelectedFile(remote: string): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      this.toast('请先配置设备地址');
      return;
    }
    if (this.pulling) {
      return;
    }
    this.pulling = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await pullRemoteFile(ctx, device, remote);
      if (!result.ok || result.data === null) {
        this.toast(result.detail.length > 0 ? `拉取失败 · ${result.detail}` : '拉取失败');
        return;
      }
      const name = remotePullBasename(remote);
      const path = `${ctx.filesDir}/pull_${Date.now()}_${name}`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, result.data);
      fs.closeSync(file);
      this.showFilePull = false;
      this.toast(`已保存 ${name}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(SESSION_LOG_DOMAIN, SESSION_LOG_TAG, 'pull failed %{public}s', msg);
      AppErrorLog.e('file-pull', msg);
      this.toast('拉取失败');
    } finally {
      this.pulling = false;
    }
  }

  private pathCrumbSegments(): string[] {
    const p = this.browsePath;
    if (p === '/' || p.length === 0) {
      return ['/'];
    }
    const parts = p.split('/');
    const segs: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        segs.push(parts[i]);
      }
    }
    return segs.length > 0 ? segs : ['/'];
  }

  private pathForCrumbIndex(index: number): string {
    const segs = this.pathCrumbSegments();
    if (segs.length === 1 && segs[0] === '/') {
      return '/';
    }
    let out = '';
    for (let i = 0; i <= index && i < segs.length; i++) {
      out = joinRemotePath(out.length > 0 ? out : '/', segs[i]);
    }
    return out.length > 0 ? out : '/';
  }

  private async openAppPicker(): Promise<void> {
    const device = this.device;
    if (device === undefined || device.address.length === 0) {
      this.toast('请先配置设备地址');
      return;
    }
    const cacheKey = `${device.address}:${device.adbPort}`;
    this.showAppPicker = true;
    this.appError = '';
    this.appQuery = '';
    if (this.appCacheKey === cacheKey && this.appCacheRows.length > 0) {
      this.appRows = this.appCacheRows;
      this.appLoading = false;
      return;
    }
    this.appLoading = true;
    this.appRows = [];
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const rows = await listRemoteThirdPartyApps(ctx, device);
      this.appRows = rows;
      this.appCacheKey = cacheKey;
      this.appCacheRows = rows;
      if (rows.length === 0) {
        this.appError = '未获取到第三方应用';
      }
    } catch (e) {
      this.appError = e instanceof Error ? e.message : String(e);
    } finally {
      this.appLoading = false;
    }
  }

  /**
   * Session toolbar quick-launch: foreground only (monkey/am start).
   * Manage「临时启动应用」uses virtual display via SessionLaunch overrideDevice.startApp.
   */
  private async launchPickedApp(pkg: string): Promise<void> {
    const device = this.device;
    if (device === undefined) {
      return;
    }
    this.showAppPicker = false;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await launchRemoteAppForeground(ctx, device, pkg);
      this.toast(result.ok ? `前台启动 · ${result.detail}` : `启动失败 · ${result.detail}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.toast(`启动失败 · ${msg}`);
    }
  }

  private filteredApps(): InstalledAppRow[] {
    const q = this.appQuery.trim().toLowerCase();
    if (q.length === 0) {
      return this.appRows;
    }
    return this.appRows.filter((row: InstalledAppRow) => {
      return row.packageName.toLowerCase().includes(q) || row.label.toLowerCase().includes(q);
    });
  }

  private injectLetter(ch: string): void {
    const code = keyCodeForLetter(ch);
    if (code < 0) {
      return;
    }
    this.sendKey(code, this.shiftOn ? META_SHIFT_ON : 0);
  }

  private injectDigit(ch: string): void {
    const code = keyCodeForDigit(ch);
    if (code < 0) {
      return;
    }
    this.sendKey(code, 0);
  }

  private lengthToNumber(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? 1 : parsed;
    }
    return 1;
  }

  /**
   * Map local touch → normalized remote coords (Android ClientController style).
   * Formula (Contain / letterbox):
   *   scale = min(hostW/videoW, hostH/videoH)  → fittedW/H
   *   If touch is on the fitted frame (preferred): nx = clamp(x / fittedW), ny = clamp(y / fittedH)
   *   If touch is on the host Stack: subtract pillar/letterbox inset first:
   *     nx = clamp((x - (hostW-fittedW)/2) / fittedW)
   *     ny = clamp((y - (hostH-fittedH)/2) / fittedH)
   * Clamp before encode — protocol coerces out-of-range to ACTION_UP.
   */
  private mapTouchNorm(localX: number, localY: number, targetW: number, targetH: number): number[] {
    const frameW = this.fittedW > 0 ? this.fittedW : Math.max(1, targetW);
    const frameH = this.fittedH > 0 ? this.fittedH : Math.max(1, targetH);
    let x = localX;
    let y = localY;
    // Host-space events (fold chrome / Stack): remove Contain insets.
    const hostLooksLikeTarget =
      this.hostW > 0 &&
      this.hostH > 0 &&
      targetW >= this.hostW - 1 &&
      targetH >= this.hostH - 1 &&
      (frameW + 1 < this.hostW || frameH + 1 < this.hostH);
    if (hostLooksLikeTarget) {
      x = localX - (this.hostW - frameW) / 2;
      y = localY - (this.hostH - frameH) / 2;
    }
    const nx = Math.min(1, Math.max(0, x / frameW));
    const ny = Math.min(1, Math.max(0, y / frameH));
    return [nx, ny];
  }

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return;
    }
    const t = event.touches[0];
    let targetW = this.fittedW > 0 ? this.fittedW : 1;
    let targetH = this.fittedH > 0 ? this.fittedH : 1;
    try {
      const aw = this.lengthToNumber(event.target.area.width);
      const ah = this.lengthToNumber(event.target.area.height);
      if (aw > 0 && ah > 0) {
        targetW = aw;
        targetH = ah;
      }
    } catch (_e) {
      // keep fitted metrics
    }
    const norm = this.mapTouchNorm(t.x, t.y, targetW, targetH);
    const x = norm[0];
    const y = norm[1];
    let action = MOTION_MOVE;
    if (event.type === TouchType.Down) {
      this.touchStartMs = Date.now();
      action = MOTION_DOWN;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      action = MOTION_UP;
    }
    const offset = Math.max(0, Date.now() - this.touchStartMs);
    if (action === MOTION_DOWN) {
      hilog.info(
        SESSION_LOG_DOMAIN,
        SESSION_LOG_TAG,
        'TOUCH_DOWN norm=%{public}s,%{public}s fitted=%{public}dx%{public}d host=%{public}dx%{public}d video=%{public}dx%{public}d target=%{public}dx%{public}d',
        x.toFixed(3),
        y.toFixed(3),
        this.fittedW,
        this.fittedH,
        this.hostW,
        this.hostH,
        this.videoW,
        this.videoH,
        targetW,
        targetH
      );
    }
    const encoded = encodeTouchPacket(action, 0, x, y, offset);
    if (encoded.ok && encoded.bytes !== null && this.usingLive && !this.usingFixture) {
      writeLiveControl(encoded.bytes);
    }
  }

  @Builder
  private symbolIconBtn(symbol: Resource, onTap: () => void, danger: boolean = false, accent: boolean = false) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(ICON_SIZE)
        .fontColor([danger ? ICON_DANGER : ICON_TINT])
    }
    .width(this.isWideRail() ? '100%' : HIT)
    .height(HIT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(accent ? ICON_BTN_ACCENT : ICON_BTN_BG)
    .stateStyles({
      pressed: {
        .backgroundColor(ICON_BTN_PRESSED)
      }
    })
    .onClick(onTap)
  }

  @Builder
  private mediaIconBtn(icon: Resource, onTap: () => void, accent: boolean = false) {
    Column() {
      Image(icon)
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .objectFit(ImageFit.Contain)
    }
    .width(this.isWideRail() ? '100%' : HIT)
    .height(HIT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(accent ? ICON_BTN_ACCENT : ICON_BTN_BG)
    .stateStyles({
      pressed: {
        .backgroundColor(ICON_BTN_PRESSED)
      }
    })
    .onClick(onTap)
  }

  @Builder
  private labeledIcon(icon: Resource, label: Resource | string, onTap: () => void, accent: boolean = false) {
    Column({ space: 4 }) {
      Image(icon)
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize(10)
        .fontColor('#CCE8EAED')
        .maxLines(1)
    }
    .width(64)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .borderRadius(14)
    .backgroundColor(accent ? ICON_BTN_ACCENT : ICON_BTN_BG)
    .onClick(onTap)
  }

  @Builder
  private navPrimaryKeys() {
    // Back / Home / Recents only — disconnect is laid out separately on portrait bar.
    if (this.showNavBar) {
      this.symbolIconBtn($r('sys.symbol.chevron_left'), () => {
        this.sendKey(KEYCODE_BACK);
      })
      this.mediaIconBtn($r('app.media.ic_nav_home'), () => {
        this.sendKey(KEYCODE_HOME);
      })
      this.mediaIconBtn($r('app.media.ic_nav_recents'), () => {
        this.sendKey(KEYCODE_APP_SWITCH);
      })
    }
  }

  @Builder
  private disconnectIconBtn() {
    this.symbolIconBtn($r('sys.symbol.xmark'), () => {
      this.closeSession();
    }, true)
  }

  @Builder
  private extrasControls() {
    this.mediaIconBtn($r('app.media.ic_nav_power'), () => {
      this.sendPower();
    })
    this.mediaIconBtn($r('app.media.ic_nav_rotate'), () => {
      this.sendRotate();
    })
    this.mediaIconBtn($r('app.media.ic_nav_light'), () => {
      this.toggleLight();
    }, this.lightOn)
    this.mediaIconBtn($r('app.media.ic_nav_bar'), () => {
      this.showNavBar = !this.showNavBar;
    }, this.showNavBar)
    this.mediaIconBtn($r('app.media.ic_nav_clipboard'), () => {
      void this.sendClipboardHint();
    })
    this.mediaIconBtn($r('app.media.ic_nav_notification'), () => {
      void this.expandNotificationPanel();
    })
    this.mediaIconBtn($r('app.media.ic_nav_audio'), () => {
      void this.toggleAudioRelay();
    }, this.audioRelayOn)
    this.mediaIconBtn($r('app.media.ic_nav_keyboard'), () => {
      this.toggleExpandedKeyboard();
    }, this.showKeyboard)
    this.mediaIconBtn($r('app.media.ic_nav_vol_up'), () => {
      this.sendKey(KEYCODE_VOLUME_UP);
    })
    this.mediaIconBtn($r('app.media.ic_nav_vol_down'), () => {
      this.sendKey(KEYCODE_VOLUME_DOWN);
    })
    this.mediaIconBtn($r('app.media.ic_nav_shot'), () => {
      void this.takeScreenshot();
    }, this.capturing)
    this.mediaIconBtn($r('app.media.ic_nav_file'), () => {
      this.openFilePullSheet();
    }, this.pulling)
    this.mediaIconBtn($r('app.media.ic_nav_app'), () => {
      void this.openAppPicker();
    })
  }

  @Builder
  private primaryIconRow() {
    // Portrait: [断开] … [返回 主页 多任务] … [展开]
    Row() {
      this.disconnectIconBtn()
      Blank().layoutWeight(1)
      Row({ space: 6 }) {
        this.navPrimaryKeys()
      }
      Blank().layoutWeight(1)
      this.symbolIconBtn($r('sys.symbol.plus'), () => {
        const next = !this.showExtras;
        this.showExtras = next;
        // Portrait keyboard is part of expanded chrome — hide with the extras row.
        if (!next && !this.isHover()) {
          this.showKeyboard = false;
        }
      }, false, this.showExtras)
    }
    .width('100%')
    .height(HIT + 4)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private extrasIconRow() {
    Scroll() {
      Row({ space: 6 }) {
        this.extrasControls()
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(HIT + 4)
  }

  @Builder
  private bottomBar() {
    Column({ space: 6 }) {
      if (this.statusLine.length > 0) {
        Text(this.statusLine)
          .fontSize(11)
          .fontColor('#80E8EAED')
          .width('100%')
          .textAlign(TextAlign.Center)
          .gesture(
            LongPressGesture({ duration: 900 })
              .onAction(() => {
                stopLiveMirror();
                void this.runFixtureInject();
              })
          )
      }
      this.primaryIconRow()
      if (this.showExtras) {
        // Expanded portrait chrome: tools on top, optional QWERTY in the lower half.
        this.extrasIconRow()
        if (this.showKeyboard) {
          Column() {
            this.hoverKeyboard()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .constraintSize({ maxHeight: this.keyboardMaxHeightVp() })
        }
      }
    }
    .width('100%')
    .padding({
      left: 12,
      right: 12,
      top: 8,
      bottom: 8 + this.safeBottomVp,
    })
    .backgroundColor(CHROME_BG)
  }

  @Builder
  private sideRail() {
    Column() {
      Scroll() {
        Column({ space: 8 }) {
          Text(this.deviceName)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E8EAED')
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: this.safeTopVp })
            .gesture(
              LongPressGesture({ duration: 900 })
                .onAction(() => {
                  stopLiveMirror();
                  void this.runFixtureInject();
                })
            )

          if (this.statusLine.length > 0) {
            Text(this.statusLine)
              .fontSize(11)
              .fontColor('#80E8EAED')
              .width('100%')
              .textAlign(TextAlign.Center)
          }

          if (this.isWideRail()) {
            // Keyboard open: 3-column tool pad; disconnect spans a full row below nav.
            if (this.showNavBar) {
              Grid() {
                GridItem() {
                  this.symbolIconBtn($r('sys.symbol.chevron_left'), () => {
                    this.sendKey(KEYCODE_BACK);
                  })
                }
                GridItem() {
                  this.mediaIconBtn($r('app.media.ic_nav_home'), () => {
                    this.sendKey(KEYCODE_HOME);
                  })
                }
                GridItem() {
                  this.mediaIconBtn($r('app.media.ic_nav_recents'), () => {
                    this.sendKey(KEYCODE_APP_SWITCH);
                  })
                }
              }
              .columnsTemplate('1fr 1fr 1fr')
              .columnsGap(6)
              .rowsGap(8)
              .width('100%')
            }

            this.disconnectIconBtn()

            Divider()
              .color('#33FFFFFF')
              .strokeWidth(1)
              .width('100%')
              .margin({ top: 2, bottom: 2 })

            Grid() {
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_power'), () => {
                  this.sendPower();
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_rotate'), () => {
                  this.sendRotate();
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_light'), () => {
                  this.toggleLight();
                }, this.lightOn)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_bar'), () => {
                  this.showNavBar = !this.showNavBar;
                }, this.showNavBar)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_clipboard'), () => {
                  void this.sendClipboardHint();
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_notification'), () => {
                  void this.expandNotificationPanel();
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_audio'), () => {
                  void this.toggleAudioRelay();
                }, this.audioRelayOn)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_keyboard'), () => {
                  this.toggleExpandedKeyboard();
                }, this.showKeyboard)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_vol_up'), () => {
                  this.sendKey(KEYCODE_VOLUME_UP);
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_vol_down'), () => {
                  this.sendKey(KEYCODE_VOLUME_DOWN);
                })
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_shot'), () => {
                  void this.takeScreenshot();
                }, this.capturing)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_file'), () => {
                  this.openFilePullSheet();
                }, this.pulling)
              }
              GridItem() {
                this.mediaIconBtn($r('app.media.ic_nav_app'), () => {
                  void this.openAppPicker();
                })
              }
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(6)
            .rowsGap(8)
            .width('100%')
            .padding({ bottom: 4 })
          } else {
            // Keyboard collapsed: skinny single-column icon stack.
            Column({ space: 8 }) {
              this.navPrimaryKeys()
              this.disconnectIconBtn()
              Divider()
                .color('#33FFFFFF')
                .strokeWidth(1)
                .width(HIT)
              this.extrasControls()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 4 })
          }
        }
        .width('100%')
        .padding({
          left: this.isWideRail() ? 8 : 10,
          right: this.isWideRail() ? 8 : 10,
          top: 10,
          bottom: 8,
        })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      if (this.showKeyboard) {
        Column() {
          this.hoverKeyboard()
        }
        .width('100%')
        .padding({
          left: 6,
          right: 6,
          top: 4,
          bottom: 8 + this.safeBottomVp,
        })
        .constraintSize({ maxHeight: this.keyboardMaxHeightVp() })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.sideRailWidthVp())
    .height('100%')
    .backgroundColor(CHROME_BG)
  }

  /** Landscape toolbar chip — spreads LTR across full dock width (not a portrait tile). */
  @Builder
  private hoverToolbarBtn(icon: Resource, label: Resource | string, onTap: () => void, accent: boolean = false) {
    Column({ space: 2 }) {
      Image(icon)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
      Text(label)
        .fontSize(9)
        .fontColor('#CCE8EAED')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(HOVER_TOOL_H)
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minWidth: HIT })
    .borderRadius(10)
    .backgroundColor(accent ? ICON_BTN_ACCENT : ICON_BTN_BG)
    .onClick(onTap)
  }

  @Builder
  private hoverSymbolToolBtn(
    symbol: Resource,
    label: Resource | string,
    onTap: () => void,
    danger: boolean = false,
    accent: boolean = false
  ) {
    Column({ space: 2 }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([danger ? ICON_DANGER : ICON_TINT])
      Text(label)
        .fontSize(9)
        .fontColor(danger ? ICON_DANGER : '#CCE8EAED')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(HOVER_TOOL_H)
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minWidth: HIT })
    .borderRadius(10)
    .backgroundColor(accent ? ICON_BTN_ACCENT : ICON_BTN_BG)
    .onClick(onTap)
  }

  /**
   * Hover / half-fold dock: wide landscape toolbar rows + optional QWERTY.
   * Never use phone bottom-bar or wrapped portrait icon pad here.
   */
  @Builder
  private hoverDock() {
    Column({ space: 6 }) {
      Text($r('app.string.session_hover_dock_hint'))
        .fontSize(11)
        .fontColor('#80E8EAED')
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.statusLine.length > 0) {
        Text(this.statusLine)
          .fontSize(10)
          .fontColor('#66E8EAED')
          .width('100%')
          .textAlign(TextAlign.Start)
          .gesture(
            LongPressGesture({ duration: 900 })
              .onAction(() => {
                stopLiveMirror();
                void this.runFixtureInject();
              })
          )
      }

      // Primary nav — single horizontal toolbar band
      Row({ space: 4 }) {
        this.hoverSymbolToolBtn($r('sys.symbol.chevron_left'), $r('app.string.session_action_back'), () => {
          this.sendKey(KEYCODE_BACK);
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_home'), $r('app.string.session_action_home'), () => {
          this.sendKey(KEYCODE_HOME);
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_recents'), $r('app.string.session_action_recents'), () => {
          this.sendKey(KEYCODE_APP_SWITCH);
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_keyboard'), $r('app.string.session_action_keyboard'), () => {
          this.showKeyboard = !this.showKeyboard;
        }, this.showKeyboard)
        this.hoverSymbolToolBtn($r('sys.symbol.xmark'), $r('app.string.session_action_close'), () => {
          this.closeSession();
        }, true)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // Session extras — second LTR toolbar (not a vertical phone rail)
      Row({ space: 4 }) {
        this.hoverToolbarBtn($r('app.media.ic_nav_power'), $r('app.string.session_action_power'), () => {
          this.sendPower();
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_rotate'), $r('app.string.session_action_rotate'), () => {
          this.sendRotate();
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_light'), $r('app.string.session_action_light'), () => {
          this.toggleLight();
        }, this.lightOn)
        this.hoverToolbarBtn($r('app.media.ic_nav_bar'), $r('app.string.session_action_nav'), () => {
          this.showNavBar = !this.showNavBar;
        }, this.showNavBar)
        this.hoverToolbarBtn($r('app.media.ic_nav_clipboard'), $r('app.string.session_action_clipboard'), () => {
          void this.sendClipboardHint();
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_notification'), $r('app.string.session_action_notification'), () => {
          void this.expandNotificationPanel();
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_audio'), $r('app.string.session_action_audio'), () => {
          void this.toggleAudioRelay();
        }, this.audioRelayOn)
        this.hoverToolbarBtn($r('app.media.ic_nav_vol_up'), $r('app.string.session_action_vol_up'), () => {
          this.sendKey(KEYCODE_VOLUME_UP);
        })
        this.hoverToolbarBtn($r('app.media.ic_nav_vol_down'), $r('app.string.session_action_vol_down'), () => {
          this.sendKey(KEYCODE_VOLUME_DOWN);
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // Keep QWERTY above tertiary tools so the landscape band stays visible without scrolling.
      if (this.showKeyboard) {
        Column() {
          this.hoverKeyboard()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .constraintSize({ maxHeight: this.keyboardMaxHeightVp() })
      }

      Row({ space: 4 }) {
        this.hoverToolbarBtn($r('app.media.ic_nav_shot'), $r('app.string.session_action_screenshot'), () => {
          void this.takeScreenshot();
        }, this.capturing)
        this.hoverToolbarBtn($r('app.media.ic_nav_file'), $r('app.string.session_action_file_pull'), () => {
          this.openFilePullSheet();
        }, this.pulling)
        this.hoverToolbarBtn($r('app.media.ic_nav_app'), $r('app.string.session_action_launch_app'), () => {
          void this.openAppPicker();
        })
        Blank().layoutWeight(4)
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: 12,
      right: 12,
      top: 8,
      bottom: 8 + this.safeBottomVp,
    })
    .backgroundColor(CHROME_BG)
  }

  @Builder
  private kbKey(label: string, onTap: () => void, flexW: number = 1, accent: boolean = false) {
    Text(label)
      .fontSize(this.isHover() ? 16 : (this.isWideRail() ? 12 : 14))
      .fontColor(ICON_TINT)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .height(this.kbKeyHeightVp())
      .layoutWeight(flexW)
      .borderRadius(this.isHover() ? 10 : 8)
      .backgroundColor(accent ? ICON_BTN_ACCENT : '#33FFFFFF')
      .padding({ top: this.isHover() ? 10 : (this.isWideRail() ? 6 : 8) })
      .onClick(onTap)
  }

  /** QWERTY panel — height ≤50% screen; width capped (rail / centered band, not full-bleed). */
  @Builder
  private hoverKeyboard() {
    Column({ space: this.isWideRail() ? 4 : 5 }) {
      Text($r('app.string.session_keyboard_cjk_note'))
        .fontSize(10)
        .fontColor('#66E8EAED')
        .width('100%')
        .textAlign(TextAlign.Start)
      Row({ space: 3 }) {
        ForEach(KB_ROW1, (ch: string) => {
          this.kbKey(this.shiftOn ? ch.toUpperCase() : ch, () => {
            this.injectLetter(ch);
          })
        }, (ch: string) => `r1-${ch}`)
      }
      .width('100%')
      Row({ space: 3 }) {
        Blank().width(this.isWideRail() ? 8 : 14)
        ForEach(KB_ROW2, (ch: string) => {
          this.kbKey(this.shiftOn ? ch.toUpperCase() : ch, () => {
            this.injectLetter(ch);
          })
        }, (ch: string) => `r2-${ch}`)
        Blank().width(this.isWideRail() ? 8 : 14)
      }
      .width('100%')
      Row({ space: 3 }) {
        this.kbKey(this.shiftOn ? '⇧' : 'shift', () => {
          this.shiftOn = !this.shiftOn;
        }, 2, this.shiftOn)
        ForEach(KB_ROW3, (ch: string) => {
          this.kbKey(this.shiftOn ? ch.toUpperCase() : ch, () => {
            this.injectLetter(ch);
          })
        }, (ch: string) => `r3-${ch}`)
        this.kbKey('⌫', () => {
          this.sendKey(KEYCODE_DEL);
        }, 2)
      }
      .width('100%')
      Row({ space: 3 }) {
        ForEach(['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], (d: string) => {
          this.kbKey(d, () => {
            this.injectDigit(d);
          })
        }, (d: string) => `d-${d}`)
      }
      .width('100%')
      Row({ space: 3 }) {
        this.kbKey('space', () => {
          this.sendKey(KEYCODE_SPACE);
        }, 5)
        this.kbKey('↵', () => {
          this.sendKey(KEYCODE_ENTER);
        }, 2)
      }
      .width('100%')
    }
    .width(this.keyboardPanelWidthVp())
    .constraintSize({ maxHeight: this.keyboardMaxHeightVp() })
    .padding({ top: 4 })
  }

  @Builder
  private videoSurface() {
    Stack({ alignContent: Alignment.Center }) {
      // Touch target matches letterboxed frame (not full host Stack).
      Stack() {
        XComponent({
          id: 'session_video',
          type: XComponentType.SURFACE,
          controller: this.xController,
        })
          .onLoad(() => {
            this.onSurfaceLoad();
          })
          .onDestroy(() => {
            this.onSurfaceDestroy();
          })
          .width('100%')
          .height('100%')

        if (this.showWaitingOverlay()) {
          Column({ space: this.surfaceRebinding ? 6 : 10 }) {
            if (!this.surfaceRebinding) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color('#B3FFFFFF')
            }
            Text(this.overlayStatusText())
              .fontSize(this.surfaceRebinding ? 13 : 14)
              .fontColor('#B3FFFFFF')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.surfaceRebinding ? '#66121214' : '#CC121214')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width(this.fittedW > 0 ? this.fittedW : '100%')
      .height(this.fittedH > 0 ? this.fittedH : '100%')
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event);
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(Color.Black)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w = this.lengthToNumber(newArea.width);
      const h = this.lengthToNumber(newArea.height);
      if (w > 0 && h > 0 && (w !== this.hostW || h !== this.hostH)) {
        this.hostW = w;
        this.hostH = h;
        this.updateFittedSize();
      }
    })
  }

  @Builder
  private appPickerOverlay() {
    Column() {
      Column({ space: 10 }) {
        Row() {
          Text($r('app.string.session_app_picker_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#E8EAED')
            .layoutWeight(1)
          Text($r('app.string.session_action_close'))
            .fontSize(14)
            .fontColor('#4A90E2')
            .onClick(() => {
              this.showAppPicker = false;
            })
        }
        .width('100%')

        Text($r('app.string.session_app_picker_hint'))
          .fontSize(12)
          .fontColor('#80E8EAED')

        TextInput({ placeholder: '搜索应用名或包名', text: this.appQuery })
          .height(40)
          .backgroundColor('#22FFFFFF')
          .fontColor('#E8EAED')
          .placeholderColor('#66E8EAED')
          .onChange((v: string) => {
            this.appQuery = v;
          })

        if (this.appLoading) {
          LoadingProgress().width(32).height(32).color('#B3FFFFFF').margin({ top: 24 })
        } else if (this.appError.length > 0) {
          Text(this.appError)
            .fontSize(13)
            .fontColor('#F2B8B5')
            .margin({ top: 16 })
        } else {
          List({ space: 4 }) {
            ForEach(this.filteredApps(), (row: InstalledAppRow) => {
              ListItem() {
                Column({ space: 2 }) {
                  Text(row.label)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#E8EAED')
                    .width('100%')
                  Text(row.packageName)
                    .fontSize(12)
                    .fontColor('#80E8EAED')
                    .width('100%')
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .backgroundColor('#22FFFFFF')
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  void this.launchPickedApp(row.packageName);
                })
              }
            }, (row: InstalledAppRow) => row.packageName)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('92%')
      .height('70%')
      .padding(16)
      .borderRadius(18)
      .backgroundColor('#F21C1C1E')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showAppPicker = false;
    })
  }

  @Builder
  private filePullSheetBuilder() {
    Column({ space: 0 }) {
      Text($r('app.string.session_file_pull_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .enabled(!this.pulling && !this.browseLoading && this.browsePath !== '/')
        .opacity(this.browsePath === '/' ? 0.35 : 1)
        .onClick(() => {
          this.browseGoUp();
        })

        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.pathCrumbSegments(), (seg: string, index: number) => {
              Row({ space: 4 }) {
                if (index > 0) {
                  Text('/')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                }
                Text(seg === '/' ? '根目录' : seg)
                  .fontSize(13)
                  .fontColor(index === this.pathCrumbSegments().length - 1
                    ? $r('app.color.ink') : $r('app.color.brand_primary'))
                  .fontWeight(index === this.pathCrumbSegments().length - 1
                    ? FontWeight.Medium : FontWeight.Regular)
                  .maxLines(1)
                  .onClick(() => {
                    if (!this.pulling && !this.browseLoading) {
                      void this.loadBrowseDir(this.pathForCrumbIndex(index));
                    }
                  })
              }
            }, (seg: string, index: number) => `${index}_${seg}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 8, right: 16, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Button($r('app.string.session_file_pull_shortcut_download'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(12)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.ink'))
          .enabled(!this.pulling && !this.browseLoading)
          .onClick(() => {
            void this.loadBrowseDir('/sdcard/Download');
          })
        Button($r('app.string.session_file_pull_shortcut_sdcard'))
          .type(ButtonType.Capsule)
          .height(32)
          .fontSize(12)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.ink'))
          .enabled(!this.pulling && !this.browseLoading)
          .onClick(() => {
            void this.loadBrowseDir('/sdcard');
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.pulling) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color($r('app.color.brand_primary'))
          Text($r('app.string.session_file_pull_saving'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.browseLoading) {
        Column() {
          LoadingProgress().width(36).height(36).color($r('app.color.brand_primary'))
          Text($r('app.string.session_file_pull_loading'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.browseError.length > 0) {
        Column({ space: 12 }) {
          Text(this.browseError)
            .fontSize(14)
            .fontColor($r('app.color.danger'))
            .textAlign(TextAlign.Center)
          Button($r('app.string.session_file_pull_retry'))
            .type(ButtonType.Capsule)
            .height(36)
            .fontSize(14)
            .onClick(() => {
              void this.loadBrowseDir();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else if (this.browseEntries.length === 0) {
        Text($r('app.string.session_file_pull_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        List() {
          ForEach(this.browseEntries, (entry: RemoteDirEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                Image(entry.isDirectory
                  ? $r('app.media.ic_browse_folder')
                  : $r('app.media.ic_browse_file'))
                  .width(24)
                  .height(24)
                  .objectFit(ImageFit.Contain)
                Column({ space: 2 }) {
                  Text(entry.name)
                    .fontSize(16)
                    .fontColor($r('app.color.ink'))
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(entry.isDirectory
                    ? $r('app.string.session_file_pull_folder')
                    : $r('app.string.session_file_pull_file'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                if (entry.isDirectory) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
            }
            .onClick(() => {
              this.onBrowseEntryTap(entry);
            })
          }, (entry: RemoteDirEntry) => `${entry.isDirectory ? 'd' : 'f'}:${entry.path}`)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: $r('app.color.divider'),
          startMargin: 50,
          endMargin: 16,
        })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST,
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        // Stable video host — never inside fold if/else (avoids XComponent destroy → Gate D).
        Column() {
          this.videoSurface()
        }
        .width('100%')
        .height('100%')
        .padding({
          right: this.chromeRightInsetVp(),
          bottom: this.chromeBottomInsetVp(),
        })

        // Chrome overlays remount freely. Transparent so video under Blank receives taps;
        // Default parent would swallow all touches after the fold layout change.
        if (this.isHover()) {
          Column() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
            Scroll() {
              this.hoverDock()
            }
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.None)
            .layoutWeight(1)
            .width('100%')
            .backgroundColor(CHROME_BG)
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        } else if (this.preferSplit) {
          Row() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
            this.sideRail()
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Column() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
            this.bottomBar()
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }

        if (this.showAppPicker) {
          this.appPickerOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showFilePull, this.filePullSheetBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      preferType: SheetType.BOTTOM,
      title: { title: $r('app.string.session_file_pull_title') },
      backgroundColor: Color.White,
      onAppear: () => {
        void this.loadBrowseDir(this.browsePath);
      },
      onWillDismiss: (action: DismissSheetAction) => {
        if (this.pulling) {
          return;
        }
        action.dismiss();
      },
    })
    .onBackPressed(() => {
      if (this.showFilePull) {
        if (!this.pulling) {
          this.showFilePull = false;
        }
        return true;
      }
      if (this.showAppPicker) {
        this.showAppPicker = false;
        return true;
      }
      // Setting: system Back → remote KEYCODE_BACK, or exit Session locally.
      if (AppSettings.isSessionBackToRemote()) {
        this.sendKey(KEYCODE_BACK);
        return true;
      }
      this.closeSession();
      return true;
    })
  }
}
