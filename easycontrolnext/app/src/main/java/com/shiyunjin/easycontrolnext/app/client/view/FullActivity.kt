package com.shiyunjin.easycontrolnext.app.client.view

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CropSquare
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.StayCurrentLandscape
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material.icons.filled.Window
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.window.core.layout.WindowSizeClass
import com.shiyunjin.easycontrolnext.app.client.Client
import com.shiyunjin.easycontrolnext.app.client.tools.ClientController
import com.shiyunjin.easycontrolnext.app.client.tools.ControlPacket
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.Device
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import com.shiyunjin.easycontrolnext.app.ui.theme.EasyControlTheme
import java.nio.ByteBuffer
import java.util.Objects
import androidx.compose.ui.graphics.Color as ComposeColor

/**
 * Full-screen mirror UI in Compose. Video stays on the shared TextureView
 * (via AndroidView) so the decode path is unchanged.
 */
class FullActivity : ComponentActivity(), SensorEventListener {

  @Volatile private var closed = false
  private var device: Device? = null
  private var controller: ClientController? = null
  private var autoRotate = true
  private var lastOrientation = -1

  private val showNavBarState = mutableStateOf(true)
  private val showPanelState = mutableStateOf(false)
  private val lightOnState = mutableStateOf(true)
  private val autoRotateState = mutableStateOf(true)

  /** Called by ClientController when leaving this mode. */
  fun hide() {
    val c = controller ?: return
    try {
      closed = true
      val tv = c.textureView
      (tv.parent as? ViewGroup)?.removeView(tv)
      finish()
    } catch (_: Exception) {
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge(
      statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
      navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
    )
    super.onCreate(savedInstanceState)
    WindowCompat.setDecorFitsSystemWindows(window, false)
    hideSystemBars()
    applyKeepScreenOn()

    val uuid = intent.getStringExtra("uuid")
    device = Client.getDevice(uuid)
    controller = Client.getClientController(uuid)
    val d = device
    val c = controller
    if (d == null || c == null) {
      finish()
      return
    }
    c.setFullView(this)

    showNavBarState.value = d.showNavBarOnConnect
    autoRotate = AppData.setting.autoRotate
    autoRotateState.value = autoRotate
    val singleApp = !Objects.equals(d.startApp, "")

    setContent {
      var showNavBar by showNavBarState
      var showPanel by showPanelState
      var lightOn by lightOnState
      var autoRotateUi by autoRotateState

      EasyControlTheme {
        FullMirrorScreen(
          device = d,
          controller = c,
          showNavBar = showNavBar,
          showPanel = showPanel,
          lightOn = lightOn,
          autoRotate = autoRotateUi,
          singleApp = singleApp,
          onShowNavBarChange = { showNavBar = it },
          onShowPanelChange = { showPanel = it },
          onLightChange = { lightOn = it },
          onAutoRotateChange = {
            autoRotate = it
            autoRotateUi = it
            AppData.setting.autoRotate = it
          },
          onClose = {
            closed = true
            Client.sendAction(d.uuid, "close", null, 0)
          },
        )
      }
    }

    registerOrientationSensor()
  }

  private fun hideSystemBars() {
    val insetsController = WindowInsetsControllerCompat(window, window.decorView)
    insetsController.hide(WindowInsetsCompat.Type.systemBars())
    insetsController.systemBarsBehavior =
      WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
  }

  override fun onResume() {
    super.onResume()
    hideSystemBars()
    applyKeepScreenOn()
    registerOrientationSensor()
  }

  private fun applyKeepScreenOn() {
    if (AppData.setting.keepScreenOnDuringControl) {
      window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    } else {
      window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
  }

  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    // Fold/unfold, split-screen, and rotate are handled via Compose recomposition +
    // TextureView onSizeChanged → updateMaxSize / adaptive resolution. Stay fullscreen.
    hideSystemBars()
  }

  override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
    super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
    hideSystemBars()
  }

  /**
   * Do not demote to Small/Mini on foldable aspect changes, split-screen, or other
   * configuration transitions — only when the user truly leaves the activity.
   */
  override fun onPause() {
    AppData.sensorManager.unregisterListener(this)
    val d = device
    val c = controller
    if (d != null && c != null && !closed) {
      if (shouldKeepFullscreenRemote()) {
        if (isChangingConfigurations) {
          (c.textureView.parent as? ViewGroup)?.removeView(c.textureView)
        }
      } else {
        c.handleAction(
          if (d.fullToMiniOnRunning) "changeToMini" else "changeToSmall",
          ByteBuffer.wrap("changeToFull".toByteArray()),
          0,
        )
      }
    }
    super.onPause()
  }

  private fun shouldKeepFullscreenRemote(): Boolean {
    if (isChangingConfigurations) return true
    if (isInMultiWindowMode) return true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) return true
    return false
  }

  private fun registerOrientationSensor() {
    if (!autoRotate) return
    AppData.sensorManager.registerListener(
      this,
      AppData.sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER),
      SensorManager.SENSOR_DELAY_NORMAL,
    )
  }

  @Deprecated("Deprecated in Java")
  override fun onBackPressed() {
    // Swallow — use nav bar Back to control remote
  }

  override fun onSensorChanged(event: SensorEvent) {
    // In multi-window / split-screen, prefer system orientation over accelerometer lock.
    if (!autoRotate || isInMultiWindowMode) return
    if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
    val x = event.values[0]
    val y = event.values[1]
    var newOrientation = lastOrientation
    if (x > -3 && x < 3 && y >= 4.5) newOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    else if (y > -3 && y < 3 && x >= 4.5) newOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    else if (y > -3 && y < 3 && x <= -4.5) newOrientation = ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
    else if (x > -3 && x < 3 && y <= -4.5) newOrientation = ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
    if (lastOrientation != newOrientation) {
      lastOrientation = newOrientation
      requestedOrientation = newOrientation
    }
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}

@Composable
private fun FullMirrorScreen(
  device: Device,
  controller: ClientController,
  showNavBar: Boolean,
  showPanel: Boolean,
  lightOn: Boolean,
  autoRotate: Boolean,
  singleApp: Boolean,
  onShowNavBarChange: (Boolean) -> Unit,
  onShowPanelChange: (Boolean) -> Unit,
  onLightChange: (Boolean) -> Unit,
  onAutoRotateChange: (Boolean) -> Unit,
  onClose: () -> Unit,
) {
  val windowSizeClass = currentWindowAdaptiveInfo().windowSizeClass
  val useSideControls = windowSizeClass.isWidthAtLeastBreakpoint(
    WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND,
  )

  fun reportSize(wPx: Int, hPx: Int) {
    if (wPx <= 0 || hPx <= 0) return
    val buf = ByteBuffer.allocate(8)
    buf.putInt(wPx)
    buf.putInt(hPx)
    buf.flip()
    controller.handleAction("updateMaxSize", buf, 0)
    if (!device.customResolutionOnConnect && device.changeResolutionOnRunning) {
      controller.handleAction(
        "writeByteBuffer",
        ControlPacket.createChangeResolutionEvent(wPx.toFloat() / hPx),
        0,
      )
    }
  }

  Box(
    modifier = Modifier
      .fillMaxSize()
      .background(ComposeColor.Black),
  ) {
    Row(modifier = Modifier.fillMaxSize()) {
      Box(
        modifier = Modifier
          .weight(1f)
          .fillMaxHeight()
          .padding(
            bottom = if (!useSideControls && showNavBar) 56.dp else 0.dp,
            end = if (useSideControls) 0.dp else 0.dp,
          )
          .onSizeChanged { size -> reportSize(size.width, size.height) },
        contentAlignment = Alignment.Center,
      ) {
        AndroidView(
          factory = { ctx ->
            FrameLayout(ctx).apply {
              layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
              )
              val tv = controller.textureView
              (tv.parent as? ViewGroup)?.removeView(tv)
              addView(
                tv,
                FrameLayout.LayoutParams(
                  ViewGroup.LayoutParams.WRAP_CONTENT,
                  ViewGroup.LayoutParams.WRAP_CONTENT,
                  Gravity.CENTER,
                ),
              )
            }
          },
          modifier = Modifier.fillMaxSize(),
          onRelease = { frame ->
            val tv = controller.textureView
            if (tv.parent === frame) frame.removeView(tv)
          },
        )
      }

      if (useSideControls) {
        FullSideControls(
          controller = controller,
          showNavBar = showNavBar,
          lightOn = lightOn,
          autoRotate = autoRotate,
          singleApp = singleApp,
          onShowNavBarChange = onShowNavBarChange,
          onLightChange = onLightChange,
          onAutoRotateChange = onAutoRotateChange,
          onClose = onClose,
        )
      }
    }

    AndroidView(
      factory = { ctx ->
        EditText(ctx).apply {
          layoutParams = FrameLayout.LayoutParams(1, 1)
          inputType = InputType.TYPE_NULL
          isFocusable = true
          isFocusableInTouchMode = true
          setOnKeyListener { _, keyCode, event ->
            if (event.action == KeyEvent.ACTION_DOWN &&
              keyCode != KeyEvent.KEYCODE_VOLUME_UP &&
              keyCode != KeyEvent.KEYCODE_VOLUME_DOWN
            ) {
              controller.handleAction(
                "writeByteBuffer",
                ControlPacket.createKeyEvent(event.keyCode, event.metaState),
                0,
              )
              true
            } else {
              false
            }
          }
          post { requestFocus() }
        }
      },
      modifier = Modifier.size(1.dp),
    )

    if (!useSideControls) {
      AnimatedVisibility(
        visible = showNavBar,
        modifier = Modifier.align(Alignment.BottomCenter),
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
      ) {
        Surface(
          color = ComposeColor(0xE6121214),
          modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        ) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .height(56.dp)
              .padding(start = 88.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            NavItem(Icons.AutoMirrored.Filled.ArrowBack, "返回") {
              controller.handleAction("buttonBack", null, 0)
            }
            if (!singleApp) {
              NavItem(Icons.Default.Home, "主页") {
                controller.handleAction("buttonHome", null, 0)
              }
              NavItem(Icons.Default.CropSquare, "多任务") {
                controller.handleAction("buttonSwitch", null, 0)
              }
            }
            NavItem(
              Icons.Default.Close,
              "断开",
              tint = ComposeColor(0xFFF2B8B5),
              onClick = onClose,
            )
          }
        }
      }

      if (showPanel) {
        Box(
          modifier = Modifier
            .fillMaxSize()
            .clickable(
              indication = null,
              interactionSource = remember { MutableInteractionSource() },
            ) { onShowPanelChange(false) },
        )
      }

      Box(
        modifier = Modifier
          .align(Alignment.BottomStart)
          .navigationBarsPadding()
          .padding(start = 12.dp, bottom = if (showNavBar) 10.dp else 14.dp)
          .height(40.dp)
          .width(72.dp)
          .clip(RoundedCornerShape(12.dp))
          .background(AccentBlue)
          .clickable { onShowPanelChange(!showPanel) },
        contentAlignment = Alignment.Center,
      ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Icon(
            Icons.Default.MoreHoriz,
            contentDescription = "更多",
            tint = ComposeColor.White,
            modifier = Modifier.size(22.dp),
          )
          Spacer(modifier = Modifier.width(2.dp))
          Text("更多", color = ComposeColor.White, fontSize = 12.sp, fontWeight = FontWeight.Medium)
        }
      }

      AnimatedVisibility(
        visible = showPanel,
        modifier = Modifier
          .align(Alignment.BottomStart)
          .navigationBarsPadding()
          .padding(start = 12.dp, bottom = if (showNavBar) 68.dp else 72.dp),
        enter = fadeIn() + slideInVertically { it / 2 },
        exit = fadeOut() + slideOutVertically { it / 2 },
      ) {
        ControlPanelCard(
          controller = controller,
          showNavBar = showNavBar,
          lightOn = lightOn,
          autoRotate = autoRotate,
          singleApp = singleApp,
          onShowNavBarChange = onShowNavBarChange,
          onShowPanelChange = onShowPanelChange,
          onLightChange = onLightChange,
          onAutoRotateChange = onAutoRotateChange,
        )
      }
    }
  }
}

@Composable
private fun FullSideControls(
  controller: ClientController,
  showNavBar: Boolean,
  lightOn: Boolean,
  autoRotate: Boolean,
  singleApp: Boolean,
  onShowNavBarChange: (Boolean) -> Unit,
  onLightChange: (Boolean) -> Unit,
  onAutoRotateChange: (Boolean) -> Unit,
  onClose: () -> Unit,
) {
  Surface(
    color = ComposeColor(0xF2121214),
    modifier = Modifier
      .width(248.dp)
      .fillMaxHeight(),
  ) {
    Column(
      modifier = Modifier
        .fillMaxSize()
        .statusBarsPadding()
        .navigationBarsPadding()
        .padding(horizontal = 14.dp, vertical = 16.dp)
        .verticalScroll(rememberScrollState()),
      verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
      Text(
        "投屏控制",
        color = ComposeColor(0xFFE8EAED),
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
      )
      Text(
        deviceSubtitleHint(singleApp),
        color = ComposeColor(0x99FFFFFF),
        fontSize = 12.sp,
      )
      Spacer(modifier = Modifier.height(4.dp))
      SideNavRow(
        Icons.AutoMirrored.Filled.ArrowBack,
        "返回",
      ) { controller.handleAction("buttonBack", null, 0) }
      if (!singleApp) {
        SideNavRow(Icons.Default.Home, "主页") {
          controller.handleAction("buttonHome", null, 0)
        }
        SideNavRow(Icons.Default.CropSquare, "多任务") {
          controller.handleAction("buttonSwitch", null, 0)
        }
      }
      SideNavRow(Icons.Default.Close, "断开", tint = ComposeColor(0xFFF2B8B5), onClick = onClose)
      HorizontalDivider(color = ComposeColor(0x33FFFFFF))
      ControlPanelCard(
        controller = controller,
        showNavBar = showNavBar,
        lightOn = lightOn,
        autoRotate = autoRotate,
        singleApp = singleApp,
        onShowNavBarChange = onShowNavBarChange,
        onShowPanelChange = {},
        onLightChange = onLightChange,
        onAutoRotateChange = onAutoRotateChange,
        fillWidth = true,
      )
    }
  }
}

private fun deviceSubtitleHint(singleApp: Boolean): String =
  if (singleApp) "单应用镜像" else "全屏镜像 · 宽屏侧栏"

@Composable
private fun ControlPanelCard(
  controller: ClientController,
  showNavBar: Boolean,
  lightOn: Boolean,
  autoRotate: Boolean,
  singleApp: Boolean,
  onShowNavBarChange: (Boolean) -> Unit,
  onShowPanelChange: (Boolean) -> Unit,
  onLightChange: (Boolean) -> Unit,
  onAutoRotateChange: (Boolean) -> Unit,
  fillWidth: Boolean = false,
) {
  Surface(
    shape = RoundedCornerShape(18.dp),
    color = ComposeColor(0xF21C1C1E),
    shadowElevation = if (fillWidth) 0.dp else 8.dp,
    modifier = if (fillWidth) Modifier.fillMaxWidth() else Modifier.width(228.dp),
  ) {
    Column(modifier = Modifier.padding(12.dp)) {
      if (!fillWidth) {
        Text(
          "投屏控制",
          color = ComposeColor(0xFFE8EAED),
          fontWeight = FontWeight.SemiBold,
          fontSize = 13.sp,
          modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
        )
      }
      Row(modifier = Modifier.fillMaxWidth()) {
        if (!singleApp) {
          PanelItem(Icons.Default.Apps, "应用") {
            controller.handleAction("changeToApp", null, 0)
            onShowPanelChange(false)
          }
        }
        PanelItem(Icons.Default.Remove, "挂起") {
          controller.handleAction("changeToMini", null, 0)
        }
        PanelItem(Icons.Default.Window, "小窗") {
          controller.handleAction("changeToSmall", null, 0)
        }
        PanelItem(
          if (autoRotate) Icons.Default.ScreenRotation else Icons.Default.ScreenLockRotation,
          if (autoRotate) "自动" else "锁定",
          accent = autoRotate,
        ) {
          onAutoRotateChange(!autoRotate)
        }
      }
      HorizontalDivider(
        modifier = Modifier.padding(vertical = 8.dp),
        color = ComposeColor(0x33FFFFFF),
      )
      Row(modifier = Modifier.fillMaxWidth()) {
        PanelItem(Icons.Default.StayCurrentLandscape, "横竖屏") {
          controller.handleAction("buttonRotate", null, 0)
          onShowPanelChange(false)
        }
        PanelItem(Icons.Default.ViewAgenda, if (showNavBar) "藏导航" else "显导航") {
          onShowNavBarChange(!showNavBar)
          onShowPanelChange(false)
        }
        PanelItem(Icons.Default.PowerSettingsNew, "电源") {
          controller.handleAction("buttonPower", null, 0)
          onShowPanelChange(false)
        }
        PanelItem(
          Icons.Default.Lightbulb,
          if (lightOn) "关背光" else "开背光",
        ) {
          val next = !lightOn
          onLightChange(next)
          controller.handleAction(if (next) "buttonLight" else "buttonLightOff", null, 0)
          onShowPanelChange(false)
        }
      }
    }
  }
}

@Composable
private fun SideNavRow(
  icon: ImageVector,
  label: String,
  tint: ComposeColor = ComposeColor(0xFFE8EAED),
  onClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(ComposeColor(0x22FFFFFF))
      .clickable(onClick = onClick)
      .padding(horizontal = 12.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(22.dp))
    Spacer(modifier = Modifier.width(10.dp))
    Text(label, color = tint, fontSize = 14.sp, fontWeight = FontWeight.Medium)
  }
}

@Composable
private fun RowScope.NavItem(
  icon: ImageVector,
  label: String,
  tint: ComposeColor = ComposeColor(0xFFF2F2F2),
  onClick: () -> Unit,
) {
  Column(
    modifier = Modifier
      .weight(1f)
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(vertical = 6.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(26.dp))
    Text(label, color = ComposeColor(0xB3FFFFFF), fontSize = 10.sp)
  }
}

@Composable
private fun RowScope.PanelItem(
  icon: ImageVector,
  label: String,
  danger: Boolean = false,
  accent: Boolean = false,
  onClick: () -> Unit,
) {
  val tint = when {
    danger -> ComposeColor(0xFFF2B8B5)
    accent -> AccentBlue
    else -> ComposeColor(0xFFE8EAED)
  }
  Column(
    modifier = Modifier
      .weight(1f)
      .clickable(onClick = onClick)
      .padding(vertical = 4.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Icon(
      icon,
      contentDescription = label,
      tint = tint,
      modifier = Modifier.size(22.dp),
    )
    Spacer(modifier = Modifier.height(2.dp))
    Text(label, color = ComposeColor(0x99FFFFFF), fontSize = 10.sp)
  }
}
