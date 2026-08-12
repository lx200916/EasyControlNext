package com.shiyunjin.easycontrolnext.app

import android.os.Bundle
import androidx.activity.ComponentActivity

/**
 * Deep-link / legacy entry that opens the settings-integrated error log screen
 * inside [MainActivity] (no separate Settings Activity).
 */
class ErrorLogActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    startActivity(MainActivity.createSettingsIntent(this, openErrorLog = true))
    @Suppress("DEPRECATION")
    overridePendingTransition(0, 0)
    finish()
    @Suppress("DEPRECATION")
    overridePendingTransition(0, 0)
  }
}
