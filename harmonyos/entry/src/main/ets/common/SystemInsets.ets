/**
 * Edge-to-edge / immersive system bars + safe-area insets (API 24).
 * Matches Android ComposeActivityBars: transparent status, opaque page-bg nav scrim,
 * dark icon content on light #F2F3F5 chrome.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'EasyControlNext';

/** SoftGray / page_background — keep in sync with resources/base/element/color.json */
export const IMMERSIVE_PAGE_BG: string = '#FFF2F3F5';
const STATUS_BAR_TRANSPARENT: string = '#00000000';
/** Dark glyphs for light chrome (status / nav). */
const BAR_CONTENT_DARK: string = '#FF000000';

export interface SafeInsetsVp {
  top: number;
  bottom: number;
}

export type SafeInsetsListener = (insets: SafeInsetsVp) => void;

/**
 * Full-screen layout + transparent status bar + opaque nav scrim.
 * Keeps status bar and navigation indicator visible (foldable-friendly).
 * Both window APIs are Promise-based — must be awaited.
 */
export async function applyImmersiveSystemBars(win: window.Window): Promise<void> {
  try {
    await win.setWindowLayoutFullScreen(true);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(e));
  }
  try {
    const props: window.SystemBarProperties = {
      statusBarColor: STATUS_BAR_TRANSPARENT,
      statusBarContentColor: BAR_CONTENT_DARK,
      isStatusBarLightIcon: false,
      navigationBarColor: IMMERSIVE_PAGE_BG,
      navigationBarContentColor: BAR_CONTENT_DARK,
      isNavigationBarLightIcon: false,
    };
    await win.setWindowSystemBarProperties(props);
    const applied = win.getWindowSystemBarProperties();
    hilog.info(DOMAIN, TAG,
      'System bars: status=%{public}s nav=%{public}s content=%{public}s',
      `${applied.statusBarColor}`,
      `${applied.navigationBarColor}`,
      `${applied.statusBarContentColor}`);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(e));
  }
}

export function readSafeInsetsVp(win: window.Window, px2vp: (px: number) => number): SafeInsetsVp {
  let topPx = 0;
  let bottomPx = 0;
  try {
    const systemAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    topPx = Math.max(topPx, systemAvoid.topRect.height);
    bottomPx = Math.max(bottomPx, systemAvoid.bottomRect.height);
  } catch (_e) {
    // ignore
  }
  try {
    const cutoutAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    topPx = Math.max(topPx, cutoutAvoid.topRect.height);
  } catch (_e) {
    // ignore
  }
  try {
    const navIndicator = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    bottomPx = Math.max(bottomPx, navIndicator.bottomRect.height);
  } catch (_e) {
    // ignore
  }

  return {
    top: px2vp(topPx),
    bottom: px2vp(bottomPx),
  };
}

/**
 * Subscribe to avoid-area changes (fold/unfold, rotation, split).
 * Pair with {@link stopSafeInsetsWatch} in aboutToDisappear.
 */
export function startSafeInsetsWatch(
  win: window.Window,
  px2vp: (px: number) => number,
  listener: SafeInsetsListener,
): (data: window.AvoidAreaOptions) => void {
  const emit = (): void => {
    listener(readSafeInsetsVp(win, px2vp));
  };
  emit();
  const onAvoid = (_data: window.AvoidAreaOptions): void => {
    emit();
  };
  win.on('avoidAreaChange', onAvoid);
  return onAvoid;
}

export function stopSafeInsetsWatch(
  win: window.Window | undefined,
  onAvoid: ((data: window.AvoidAreaOptions) => void) | undefined,
): void {
  if (win === undefined || onAvoid === undefined) {
    return;
  }
  try {
    win.off('avoidAreaChange', onAvoid);
  } catch (_e) {
    // ignore
  }
}
