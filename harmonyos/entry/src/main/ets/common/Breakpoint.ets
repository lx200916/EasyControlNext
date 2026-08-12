/**
 * Foldable-first layout breakpoints for EasyControlNext controller UI.
 *
 * Prefer container / window width in vp, and also react to fold posture.
 * Use if/else layout switches — do not hide branches with Visibility.None.
 *
 * Breakpoints (window width vp):
 * - sm:  < 600  — phone / folded outer
 * - md:  < 840  — unfolded narrow / small tablet
 * - lg:  >= 840 — unfolded wide / tablet / 2in1
 */

import { display } from '@kit.ArkUI';

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

export function readLayoutSnapshot(): LayoutSnapshot {
  try {
    const d = display.getDefaultDisplaySync();
    const density = d.densityPixels > 0 ? d.densityPixels : 1;
    const widthVp = d.width / density;
    const heightVp = d.height / density;
    const breakpoint = breakpointFromWidthVp(widthVp);
    let isFoldable = false;
    let foldPosture: FoldPosture = 'unknown';
    try {
      isFoldable = display.isFoldable();
      if (isFoldable) {
        foldPosture = foldPostureFromStatus(display.getFoldStatus());
      }
    } catch (_e) {
      // Fold APIs unavailable — keep width-only snapshot.
    }
    // Half-fold (悬停) must not prefer wide side-rail — Session uses hover dock instead.
    const preferSplit =
      foldPosture !== 'half' &&
      (breakpoint === BP_LG ||
        (isFoldable && foldPosture === 'expanded' && widthVp >= 600));
    return {
      breakpoint,
      widthVp,
      heightVp,
      foldPosture,
      isFoldable,
      preferSplit,
    };
  } catch (_e) {
    return {
      breakpoint: BP_SM,
      widthVp: 360,
      heightVp: 780,
      foldPosture: 'unknown',
      isFoldable: false,
      preferSplit: false,
    };
  }
}

/**
 * Subscribe to display size and fold posture changes.
 * Always pair with {@link stopLayoutWatch} in aboutToDisappear.
 */
export function startLayoutWatch(listener: LayoutChangeListener): void {
  listener(readLayoutSnapshot());
  display.on('change', (_id: number) => {
    listener(readLayoutSnapshot());
  });
  try {
    if (display.isFoldable()) {
      display.on('foldStatusChange', (_status: display.FoldStatus) => {
        listener(readLayoutSnapshot());
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
