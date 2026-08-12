package com.shiyunjin.easycontrolnext.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * Legacy entry point. Settings now lives in [MainActivity] (Compose destination) so
 * home → settings does not swap Activities / system bars (MIUI/HyperOS flash).
 *
 * Kept so any old `SetActivity` intents still resolve.
 */
class SetActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val openErrorLog = intent.getBooleanExtra(EXTRA_OPEN_ERROR_LOG, false)
    startActivity(MainActivity.createSettingsIntent(this, openErrorLog = openErrorLog))
    @Suppress("DEPRECATION")
    overridePendingTransition(0, 0)
    finish()
    @Suppress("DEPRECATION")
    overridePendingTransition(0, 0)
  }

  companion object {
    const val EXTRA_OPEN_ERROR_LOG = MainActivity.EXTRA_OPEN_ERROR_LOG

    @JvmStatic
    @JvmOverloads
    fun createIntent(context: Context, openErrorLog: Boolean = false): Intent {
      return MainActivity.createSettingsIntent(context, openErrorLog = openErrorLog)
    }
  }
}
