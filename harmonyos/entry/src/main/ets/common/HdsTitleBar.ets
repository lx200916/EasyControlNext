/**
 * Shared HdsNavigation / HdsNavDestination chrome.
 * Glass is system 沉浸光感 (systemMaterialEffect ADAPTIVE) — do not set blurRadius.
 * Official sample: enableScrollEffect false + GRADIENT_BLUR + ADAPTIVE material.
 * Overlay the bar (enableComponentSafeArea false) so content can show through.
 */

import {
  hdsMaterial,
  HdsNavigationTitleBarOptions,
  ScrollEffectType,
  SystemMaterialParams,
  TitleBarContentOptions,
  TitleBarStyleOptions,
} from '@kit.UIDesignKit';

/** Home device list scroller — AppShell HdsNavigation.bindToScrollable. */
export const HOME_LIST_SCROLLER: Scroller = new Scroller();

/** MINI title overlay height (vp), excluding status inset. Use as List/Scroll contentStartOffset. */
export const HDS_MINI_TITLE_INSET_VP: number = 56;

export function hdsAdaptiveMaterial(): SystemMaterialParams {
  const params: SystemMaterialParams = {
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
  };
  return params;
}

/** Official 系统自适应 title bar — system picks blur / material, not app blurRadius. */
export function hdsAdaptiveTitleBarStyle(): TitleBarStyleOptions {
  const style: TitleBarStyleOptions = {
    scrollEffectOpts: {
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
    },
    systemMaterialEffect: hdsAdaptiveMaterial(),
  };
  return style;
}

/** Overlay title bar — content paints underneath; do not enable component safe area. */
export function hdsOverlayTitleBar(content: TitleBarContentOptions): HdsNavigationTitleBarOptions {
  const opts: HdsNavigationTitleBarOptions = {
    enableComponentSafeArea: false,
    avoidLayoutSafeArea: false,
    content: content,
    style: hdsAdaptiveTitleBarStyle(),
  };
  return opts;
}
