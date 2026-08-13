/**
 * Foldable-first layout breakpoints for EasyControlNext controller UI.
 *
 * Prefer **app window** width in vp (not full display) so split-screen / floating
 * panes do not inherit the unfolded expanded chrome. Fold posture still drives
 * half-fold hover behavior and must flip layout immediately on fold/unfold —
 * windowRect often lags the fold animation by hundreds of ms to seconds.
 *
 * Breakpoints (window width vp):
 * - sm:  < 600  — phone / folded outer / narrow split pane
 * - md:  < 840  — unfolded narrow / small tablet
 * - lg:  >= 840 — unfolded wide / tablet / 2in1
 */

import { display, window } from '@kit.ArkUI';

export const BP_SM: string = 'sm';
export const BP_MD: string = 'md';
export const BP_LG: string = 'lg';

export type FoldPosture = 'folded' | 'half' | 'expanded' | 'unknown';

export interface LayoutSnapshot {
  breakpoint: string;
  widthVp: number;
  heightVp: number;
  foldPosture: FoldPosture;
  isFoldable: boolean;
  /** True when a two-pane master/detail shell is preferred. */
  preferSplit: boolean;
}

export type LayoutChangeListener = (snapshot: LayoutSnapshot) => void;

export interface FoldMeta {
  isFoldable: boolean;
  foldPosture: FoldPosture;
}

function foldPostureFromStatus(status: display.FoldStatus): FoldPosture {
  switch (status) {
    case display.FoldStatus.FOLD_STATUS_FOLDED:
      return 'folded';
    case display.FoldStatus.FOLD_STATUS_HALF_FOLDED:
      return 'half';
    case display.FoldStatus.FOLD_STATUS_EXPANDED:
      return 'expanded';
    default:
      return 'unknown';
  }
}

export function breakpointFromWidthVp(widthVp: number): string {
  if (widthVp < 600) {
    return BP_SM;
  }
  if (widthVp < 840) {
    return BP_MD;
  }
  return BP_LG;
}

export function readFoldMeta(): FoldMeta {
  try {
    const isFoldable = display.isFoldable();
    if (!isFoldable) {
      return { isFoldable: false, foldPosture: 'unknown' };
    }
    return {
      isFoldable: true,
      foldPosture: foldPostureFromStatus(display.getFoldStatus()),
    };
  } catch (_e) {
    return { isFoldable: false, foldPosture: 'unknown' };
  }
}

/**
 * Compact chrome for multi-window modes even if the pane is still fairly wide
 * (expanded foldable + 50/50 split can stay >= 600vp).
 */
export function isCompactWindowStatus(status: window.WindowStatusType): boolean {
  return status === window.WindowStatusType.SPLIT_SCREEN ||
    status === window.WindowStatusType.FLOATING;
}

export function computePreferSplit(
  widthVp: number,
  foldPosture: FoldPosture,
  isFoldable: boolean,
  windowStatus?: window.WindowStatusType
): boolean {
  // Posture wins over lagging windowRect during fold/unfold animation.
  // folded outer / half-fold hover must never keep master-detail chrome.
  if (foldPosture === 'half' || foldPosture === 'folded') {
    return false;
  }
  if (windowStatus !== undefined && isCompactWindowStatus(windowStatus)) {
    return false;
  }
  const breakpoint = breakpointFromWidthVp(widthVp);
  // Full-width lg, or expanded foldable with a truly wide window (not a split pane).
  return breakpoint === BP_LG ||
    (isFoldable && foldPosture === 'expanded' && widthVp >= 600);
}

export function buildLayoutSnapshot(
  widthVp: number,
  heightVp: number,
  fold: FoldMeta,
  windowStatus?: window.WindowStatusType
): LayoutSnapshot {
  const w = widthVp > 0 ? widthVp : 360;
  const h = heightVp > 0 ? heightVp : 780;
  return {
    breakpoint: breakpointFromWidthVp(w),
    widthVp: w,
    heightVp: h,
    foldPosture: fold.foldPosture,
    isFoldable: fold.isFoldable,
    preferSplit: computePreferSplit(w, fold.foldPosture, fold.isFoldable, windowStatus),
  };
}

/** Display-sized fallback before the main window is bound (Previewer / early init). */
export function readLayoutSnapshot(foldOverride?: FoldMeta): LayoutSnapshot {
  const fold = foldOverride !== undefined ? foldOverride : readFoldMeta();
  try {
    const d = display.getDefaultDisplaySync();
    const density = d.densityPixels > 0 ? d.densityPixels : 1;
    return buildLayoutSnapshot(d.width / density, d.height / density, fold);
  } catch (_e) {
    return buildLayoutSnapshot(360, 780, fold);
  }
}

/**
 * Snapshot from the live app window — preferred for preferSplit / Session chrome.
 *
 * @param foldOverride Use foldStatusChange event status; getFoldStatus() can lag briefly.
 */
export function readLayoutSnapshotFromWindow(
  win: window.Window,
  foldOverride?: FoldMeta
): LayoutSnapshot {
  const fold = foldOverride !== undefined ? foldOverride : readFoldMeta();
  try {
    const d = display.getDefaultDisplaySync();
    const density = d.densityPixels > 0 ? d.densityPixels : 1;
    const rect = win.getWindowProperties().windowRect;
    let widthVp = rect.width / density;
    let heightVp = rect.height / density;
    let status: window.WindowStatusType | undefined = undefined;
    try {
      status = win.getWindowStatus();
    } catch (_e) {
      status = undefined;
    }
    // Fold/unfold animation: windowRect often lags the active display by a long
    // time. Prefer display size when posture says the active panel changed and
    // we are not in an intentional compact multi-window pane.
    if (fold.isFoldable &&
      (status === undefined || !isCompactWindowStatus(status))) {
      const displayW = d.width / density;
      const displayH = d.height / density;
      if (fold.foldPosture === 'expanded' && displayW > widthVp + 1) {
        // Unfold: outer → inner; window still reports small outer rect.
        widthVp = displayW;
        heightVp = displayH;
      } else if ((fold.foldPosture === 'folded' || fold.foldPosture === 'half') &&
        displayW < widthVp - 1) {
        // Fold / hover: inner → outer (or crease); window still reports huge rect.
        widthVp = displayW;
        heightVp = displayH;
      }
    }
    return buildLayoutSnapshot(widthVp, heightVp, fold, status);
  } catch (_e) {
    return buildLayoutSnapshot(360, 780, fold);
  }
}

/**
 * Subscribe to display size and fold posture changes.
 * Prefer pairing with window size/status listeners in AppShell for split-screen.
 * Always pair with {@link stopLayoutWatch} in aboutToDisappear.
 *
 * foldStatusChange passes an authoritative FoldMeta via the snapshot so callers
 * do not re-query getFoldStatus() (which can briefly lag the event).
 */
export function startLayoutWatch(listener: LayoutChangeListener): void {
  listener(readLayoutSnapshot());
  display.on('change', (_id: number) => {
    listener(readLayoutSnapshot());
  });
  try {
    if (display.isFoldable()) {
      display.on('foldStatusChange', (status: display.FoldStatus) => {
        const fold: FoldMeta = {
          isFoldable: true,
          foldPosture: foldPostureFromStatus(status),
        };
        listener(readLayoutSnapshot(fold));
      });
    }
  } catch (_e) {
    // Ignore — width change path still covers most emulator resizes.
  }
}

export function stopLayoutWatch(): void {
  try {
    display.off('change');
  } catch (_e) {
    // ignore
  }
  try {
    display.off('foldStatusChange');
  } catch (_e) {
    // ignore
  }
}
