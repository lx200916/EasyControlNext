/**
 * System bars + safe-area insets.
 * Home / NavDestination pages must NOT ignore layout safe areas — doing so on real
 * devices pushed HdsTabs off-screen and put system back under the status bar.
 * Home HdsTabs uses safeBottomVp in barFloatingStyle.barBottomMargin (see Home.ets).
 * Session may still go edge-to-edge via its own expand/ignore attributes.
 *
 * Standard bars follow Configuration colorMode so dark theme gets light icons and
 * dark bar backgrounds matching resources/dark page_background.
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ColdStartTrace } from './ColdStartTrace';

const DOMAIN = 0x0000;
const TAG = 'EasyControlNext';

/** SoftGray / page_background — keep in sync with resources/base/element/color.json */
export const IMMERSIVE_PAGE_BG_LIGHT: string = '#FFF2F3F5';
/** Dark page_background — keep in sync with resources/dark/element/color.json */
export const IMMERSIVE_PAGE_BG_DARK: string = '#FF121212';
/** @deprecated Use IMMERSIVE_PAGE_BG_LIGHT — kept for call sites that expect the old name. */
export const IMMERSIVE_PAGE_BG: string = IMMERSIVE_PAGE_BG_LIGHT;
const STATUS_BAR_TRANSPARENT: string = '#00000000';
/** Dark glyphs on light bars. */
const BAR_CONTENT_ON_LIGHT: string = '#FF000000';
/** Light glyphs on dark bars. */
const BAR_CONTENT_ON_DARK: string = '#FFFFFFFF';
const MAX_SAFE_TOP_VP: number = 64;
const MAX_SAFE_BOTTOM_VP: number = 48;

/** Log first applyImmersiveSystemBars only (startup); later theme flips stay quiet. */
let firstBarsApplyLogged: boolean = false;

/** AppStorage key — Session sets true while fullscreen chrome is active. */
export const SESSION_FULLSCREEN_ACTIVE_KEY: string = 'sessionFullscreenActive';
/** AppStorage key — ConfigurationConstant.ColorMode for Home / EntryAbility. */
export const CURRENT_COLOR_MODE_KEY: string = 'currentColorMode';

export interface SafeInsetsVp {
  top: number;
  bottom: number;
}

export type SafeInsetsListener = (insets: SafeInsetsVp) => void;

export function isDarkColorMode(colorMode: number | undefined): boolean {
  return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
}

export function resolveColorMode(explicit?: number): number {
  if (explicit !== undefined && explicit !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
    return explicit;
  }
  const stored = AppStorage.get<number>(CURRENT_COLOR_MODE_KEY);
  if (stored !== undefined && stored !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
    return stored;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
}

/** Standard (non-fullscreen) bars for Home and title-bar pages — theme-aware. */
export async function applyImmersiveSystemBars(
  win: window.Window,
  colorMode?: number,
): Promise<void> {
  const logCold = !firstBarsApplyLogged;
  if (logCold) {
    firstBarsApplyLogged = true;
    ColdStartTrace.mark('applyImmersiveSystemBars.enter');
  }
  try {
    await win.setWindowLayoutFullScreen(false);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(e));
  }
  try {
    const dark = isDarkColorMode(resolveColorMode(colorMode));
    const bg = dark ? IMMERSIVE_PAGE_BG_DARK : IMMERSIVE_PAGE_BG_LIGHT;
    const content = dark ? BAR_CONTENT_ON_DARK : BAR_CONTENT_ON_LIGHT;
    const props: window.SystemBarProperties = {
      statusBarColor: bg,
      statusBarContentColor: content,
      isStatusBarLightIcon: dark,
      navigationBarColor: bg,
      navigationBarContentColor: content,
      isNavigationBarLightIcon: dark,
    };
    await win.setWindowSystemBarProperties(props);
    hilog.info(DOMAIN, TAG, 'Standard system bars applied dark=%{public}s', dark ? '1' : '0');
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(e));
  }
  if (logCold) {
    ColdStartTrace.mark('applyImmersiveSystemBars.exit');
  }
}

/** Session video chrome: draw under status / home indicator. */
export async function enableSessionFullscreen(win: window.Window): Promise<void> {
  try {
    await win.setWindowLayoutFullScreen(true);
    await win.setWindowSystemBarProperties({
      statusBarColor: STATUS_BAR_TRANSPARENT,
      statusBarContentColor: BAR_CONTENT_ON_DARK,
      isStatusBarLightIcon: true,
      navigationBarColor: STATUS_BAR_TRANSPARENT,
      navigationBarContentColor: BAR_CONTENT_ON_DARK,
      isNavigationBarLightIcon: true,
    });
    AppStorage.setOrCreate(SESSION_FULLSCREEN_ACTIVE_KEY, true);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'enableSessionFullscreen failed: %{public}s', JSON.stringify(e));
  }
}

export async function restoreStandardSystemBars(
  win: window.Window,
  colorMode?: number,
): Promise<void> {
  AppStorage.setOrCreate(SESSION_FULLSCREEN_ACTIVE_KEY, false);
  await applyImmersiveSystemBars(win, colorMode);
}

/** Re-apply theme bars unless Session owns the window chrome. */
export async function applyImmersiveSystemBarsIfIdle(
  win: window.Window,
  colorMode?: number,
): Promise<void> {
  const sessionActive = AppStorage.get<boolean>(SESSION_FULLSCREEN_ACTIVE_KEY);
  if (sessionActive === true) {
    return;
  }
  await applyImmersiveSystemBars(win, colorMode);
}

export function readSafeInsetsVp(win: window.Window, px2vp: (px: number) => number): SafeInsetsVp {
  let topPx = 0;
  let bottomPx = 0;
  let windowH = 0;
  try {
    windowH = win.getWindowProperties().windowRect.height;
  } catch (_e) {
    windowH = 0;
  }
  try {
    const systemAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    topPx = Math.max(topPx, systemAvoid.topRect.height);
    const sysBottom = systemAvoid.bottomRect.height;
    // Reject inflated SYSTEM bottoms (seen on some fullscreen hosts).
    if (sysBottom > 0 && (windowH <= 0 || sysBottom < windowH / 4)) {
      bottomPx = Math.max(bottomPx, sysBottom);
    }
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

  const top = Math.min(MAX_SAFE_TOP_VP, Math.max(0, px2vp(topPx)));
  const bottom = Math.min(MAX_SAFE_BOTTOM_VP, Math.max(0, px2vp(bottomPx)));
  hilog.info(DOMAIN, TAG, 'safeInsets top=%{public}d bottom=%{public}d vp', top, bottom);
  return { top: top, bottom: bottom };
}

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
