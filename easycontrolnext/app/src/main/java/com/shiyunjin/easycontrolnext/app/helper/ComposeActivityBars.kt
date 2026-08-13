package com.shiyunjin.easycontrolnext.app.helper

import android.app.Activity
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.core.graphics.ColorUtils
import androidx.core.view.WindowCompat
import com.shiyunjin.easycontrolnext.app.R

/**
 * Stable system bars for Compose (and shared with View screens via [paintLegacy]).
 *
 * Critical: the **navigation bar scrim must be opaque SoftGrayBg**, never transparent.
 * Matching colors alone is NOT enough for home → Settings: swapping Activities still
 * flashes bars on MIUI/HyperOS during window animation. Prefer in-process Compose
 * navigation (Settings inside MainActivity) so the window / bars never leave.
 *
 * Call [enable] before `super.onCreate`, then [paint] after. Do **not** flip bar colors
 * from a Compose [androidx.compose.runtime.SideEffect].
 */
object ComposeActivityBars {
  /** SoftGrayBg — must match Theme.kt SoftGrayBg / themes.xml compose_window_background. */
  const val LIGHT_BG = 0xFFF2F3F5.toInt()
  /** DarkColors.background — must match Theme.kt / themes.xml. */
  const val DARK_BG = 0xFF0F1115.toInt()

  fun isNightMode(activity: Activity): Boolean {
    val mask = activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return mask == Configuration.UI_MODE_NIGHT_YES
  }

  fun backgroundColor(darkTheme: Boolean): Int = if (darkTheme) DARK_BG else LIGHT_BG

  /**
   * Full install for Compose hosts.
   * Call before `super.onCreate` (enableEdgeToEdge requirement), then call again after
   * `super.onCreate` via [paint] is unnecessary if [install] is used as:
   *   installBeforeSuper(); super.onCreate(); paintWindow();
   */
  fun enable(activity: ComponentActivity, darkTheme: Boolean = isNightMode(activity)) {
    applyEdgeToEdge(activity, darkTheme)
  }

  /** After `super.onCreate`, before `setContent`. Reinforces theme + opaque nav. */
  fun paint(activity: ComponentActivity, darkTheme: Boolean = isNightMode(activity)) {
    val bg = backgroundColor(darkTheme)
    // Re-assert edge-to-edge styles after Theme inflate (OEM themes can reset bars).
    applyEdgeToEdge(activity, darkTheme)
    activity.window.setBackgroundDrawableResource(
      if (darkTheme) R.color.compose_window_background_dark else R.color.compose_window_background,
    )
    WindowCompat.setDecorFitsSystemWindows(activity.window, false)

    @Suppress("DEPRECATION")
    run {
      activity.window.statusBarColor = Color.TRANSPARENT
      // Match SystemBarStyle nav scrim — must stay opaque SoftGrayBg / dark bg.
      activity.window.navigationBarColor = bg
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        activity.window.navigationBarDividerColor = Color.TRANSPARENT
      }
    }

    // API 29+: OEM contrast scrim (esp. MIUI 3-button / gesture quirks) causes visible flash.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      activity.window.isNavigationBarContrastEnforced = false
      activity.window.isStatusBarContrastEnforced = false
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      activity.window.attributes = activity.window.attributes.apply {
        layoutInDisplayCutoutMode =
          WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
      }
    }

    val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
    controller.isAppearanceLightStatusBars = !darkTheme
    controller.isAppearanceLightNavigationBars = !darkTheme &&
      ColorUtils.calculateLuminance(bg) > 0.5
  }

  private fun applyEdgeToEdge(activity: ComponentActivity, darkTheme: Boolean) {
    val bg = backgroundColor(darkTheme)
    // Status: transparent (windowBackground shows through).
    // Nav: OPAQUE bg — never transparent; enableEdgeToEdge re-applies this scrim.
    if (darkTheme) {
      activity.enableEdgeToEdge(
        statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        navigationBarStyle = SystemBarStyle.dark(bg),
      )
    } else {
      activity.enableEdgeToEdge(
        statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        navigationBarStyle = SystemBarStyle.light(bg, bg),
      )
    }
  }

  /** View-based activities (Ip / AdbKey): same opaque SoftGrayBg nav, no edge-to-edge. */
  @JvmStatic
  fun paintLegacy(activity: Activity) {
    val darkTheme = isNightMode(activity)
    val bg = backgroundColor(darkTheme)
    activity.window.setBackgroundDrawableResource(
      if (darkTheme) R.color.compose_window_background_dark else R.color.compose_window_background,
    )
    activity.window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION)
    @Suppress("DEPRECATION")
    run {
      activity.window.statusBarColor = bg
      activity.window.navigationBarColor = bg
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        activity.window.navigationBarDividerColor = Color.TRANSPARENT
      }
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      activity.window.isNavigationBarContrastEnforced = false
      activity.window.isStatusBarContrastEnforced = false
    }
    val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
    controller.isAppearanceLightStatusBars = !darkTheme
    controller.isAppearanceLightNavigationBars = !darkTheme
  }
}
