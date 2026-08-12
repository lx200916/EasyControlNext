package com.shiyunjin.easycontrolnext.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.shiyunjin.easycontrolnext.app.client.Client
import com.shiyunjin.easycontrolnext.app.client.tools.AdbTools
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.helper.ComposeActivityBars
import com.shiyunjin.easycontrolnext.app.helper.ViewTools
import com.shiyunjin.easycontrolnext.app.ui.DeviceListStore
import com.shiyunjin.easycontrolnext.app.ui.EasyControlApp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class MainActivity : ComponentActivity() {

  /** Non-null once when Settings (optionally Error Log) should open in-process. */
  data class SettingsRequest(val openErrorLog: Boolean, val nonce: Long = System.nanoTime())

  private val settingsRequestFlow = MutableStateFlow<SettingsRequest?>(null)
  val settingsRequests: StateFlow<SettingsRequest?> = settingsRequestFlow.asStateFlow()

  override fun onCreate(savedInstanceState: Bundle?) {
    ComposeActivityBars.enable(this)
    super.onCreate(savedInstanceState)
    ComposeActivityBars.paint(this)
    AppData.init(this)
    ViewTools.setLocale(this)
    DeviceListStore.refresh()
    consumeSettingsExtras(intent)
    AppData.uiHandler.postDelayed({
      for (device in AdbTools.devicesList) {
        if (device.connectOnStart) Client.startDevice(device)
      }
    }, 2000)
    setContent {
      val settingsRequest by settingsRequests.collectAsState()
      EasyControlApp(
        activity = this,
        settingsRequest = settingsRequest,
        onSettingsRequestConsumed = { settingsRequestFlow.value = null },
      )
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    consumeSettingsExtras(intent)
  }

  override fun onResume() {
    super.onResume()
    ComposeActivityBars.paint(this)
    DeviceListStore.refresh()
  }

  private fun consumeSettingsExtras(intent: Intent?) {
    if (intent == null) return
    val openErrorLog = intent.getBooleanExtra(EXTRA_OPEN_ERROR_LOG, false)
    val openSettings = intent.getBooleanExtra(EXTRA_OPEN_SETTINGS, false) || openErrorLog
    if (!openSettings) return
    settingsRequestFlow.value = SettingsRequest(openErrorLog = openErrorLog)
    intent.removeExtra(EXTRA_OPEN_SETTINGS)
    intent.removeExtra(EXTRA_OPEN_ERROR_LOG)
  }

  companion object {
    const val EXTRA_OPEN_SETTINGS = "open_settings"
    const val EXTRA_OPEN_ERROR_LOG = "open_error_log"

    /**
     * Deep-link / legacy entry into Settings inside [MainActivity] (no second Activity →
     * no OEM system-bar flash on home ↔ settings).
     */
    @JvmStatic
    @JvmOverloads
    fun createSettingsIntent(context: Context, openErrorLog: Boolean = false): Intent {
      return Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(EXTRA_OPEN_SETTINGS, true)
        putExtra(EXTRA_OPEN_ERROR_LOG, openErrorLog)
      }
    }
  }
}
