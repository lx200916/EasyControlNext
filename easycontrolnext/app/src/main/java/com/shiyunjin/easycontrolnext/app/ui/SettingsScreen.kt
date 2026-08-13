package com.shiyunjin.easycontrolnext.app.ui

import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.window.core.layout.WindowSizeClass
import com.shiyunjin.easycontrolnext.app.AdbKeyActivity
import com.shiyunjin.easycontrolnext.app.BuildConfig
import com.shiyunjin.easycontrolnext.app.IpActivity
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.Setting
import com.shiyunjin.easycontrolnext.app.helper.PublicTools
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue

private enum class SettingsPane {
  Connection,
  General,
  Diagnostics,
  About,
}

/**
 * Settings home content. Hosted by [EasyControlApp]'s single NavHost (no nested NavHost)
 * so home → settings only animates one layer.
 *
 * Compact: single-column stacked sections.
 * Medium+: left category nav + right section content (matches Home list–detail).
 */
@Composable
fun SettingsHomeScreen(
  onBack: () -> Unit,
  onOpenPresets: () -> Unit,
  onOpenErrorLogs: () -> Unit,
) {
  val context = LocalContext.current
  val windowSizeClass = currentWindowAdaptiveInfo().windowSizeClass
  val usePanes = windowSizeClass.isWidthAtLeastBreakpoint(
    WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND,
  )
  var selectedPane by remember { mutableStateOf(SettingsPane.Connection) }

  val panes = listOf(
    SettingsPaneItem(
      pane = SettingsPane.Connection,
      icon = Icons.Default.Tune,
      title = stringResource(R.string.set_section_connection),
      detail = stringResource(R.string.set_section_connection_detail),
    ),
    SettingsPaneItem(
      pane = SettingsPane.General,
      icon = Icons.Default.Language,
      title = stringResource(R.string.set_section_general),
      detail = stringResource(R.string.set_section_general_detail),
    ),
    SettingsPaneItem(
      pane = SettingsPane.Diagnostics,
      icon = Icons.Default.BugReport,
      title = stringResource(R.string.set_section_diagnostics),
      detail = stringResource(R.string.set_section_diagnostics_detail),
    ),
    SettingsPaneItem(
      pane = SettingsPane.About,
      icon = Icons.Default.Info,
      title = stringResource(R.string.set_section_about),
      detail = stringResource(R.string.set_section_about_detail),
    ),
  )

  Scaffold(
    containerColor = MaterialTheme.colorScheme.background,
  ) { padding ->
    // Scaffold contentWindowInsets already include status/nav bars — apply once via padding.
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding),
    ) {
      Row(
        modifier = Modifier
          .fillMaxWidth()
          // Scaffold already insets for statusBars; modest extra top so title isn't cramped.
          .padding(start = 8.dp, top = 12.dp, end = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        IconButton(onClick = onBack) {
          Icon(
            Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = stringResource(R.string.set_back),
          )
        }
        Column(modifier = Modifier.weight(1f)) {
          Text(
            stringResource(R.string.set_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
          )
          Text(
            stringResource(R.string.set_subtitle),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      if (usePanes) {
        Row(
          modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        ) {
          Column(
            modifier = Modifier
              .weight(0.38f)
              .fillMaxHeight()
              .widthIn(max = 360.dp)
              .verticalScroll(rememberScrollState())
              .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            panes.forEach { item ->
              SettingsPaneNavCard(
                icon = item.icon,
                title = item.title,
                detail = item.detail,
                selected = selectedPane == item.pane,
                onClick = { selectedPane = item.pane },
              )
            }
          }
          Spacer(modifier = Modifier.width(16.dp))
          Card(
            modifier = Modifier
              .weight(0.62f)
              .fillMaxHeight()
              .widthIn(max = 560.dp)
              .padding(bottom = 20.dp),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(0.dp),
          ) {
            Column(
              modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            ) {
              Text(
                panes.first { it.pane == selectedPane }.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
              )
              Spacer(modifier = Modifier.height(12.dp))
              when (selectedPane) {
                SettingsPane.Connection -> SettingsConnectionContent(
                  onOpenPresets = onOpenPresets,
                  onOpenIp = {
                    context.startActivity(Intent(context, IpActivity::class.java))
                  },
                  onOpenAdbKey = {
                    context.startActivity(Intent(context, AdbKeyActivity::class.java))
                  },
                  onResetKey = {
                    AppData.keyPair = PublicTools.reGenerateAdbKeyPair()
                    Toast.makeText(context, context.getString(R.string.toast_success), Toast.LENGTH_SHORT).show()
                  },
                )
                SettingsPane.General -> SettingsGeneralContent(
                  onToggleLocale = {
                    val next = if (AppData.setting.locale == "en") "zh" else "en"
                    AppData.setting.locale = next
                    Toast.makeText(
                      context,
                      context.getString(R.string.toast_change_locale),
                      Toast.LENGTH_SHORT,
                    ).show()
                  },
                )
                SettingsPane.Diagnostics -> SettingsDiagnosticsContent(
                  onOpenErrorLogs = onOpenErrorLogs,
                )
                SettingsPane.About -> SettingsAboutContent(
                  onOpenWebsite = {
                    PublicTools.startUrl(context, "https://github.com/shiyunjin/EasyControlNext")
                  },
                )
              }
            }
          }
        }
      } else {
        Column(
          modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp),
          verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          SettingsSection(title = stringResource(R.string.set_section_connection)) {
            SettingsConnectionContent(
              onOpenPresets = onOpenPresets,
              onOpenIp = {
                context.startActivity(Intent(context, IpActivity::class.java))
              },
              onOpenAdbKey = {
                context.startActivity(Intent(context, AdbKeyActivity::class.java))
              },
              onResetKey = {
                AppData.keyPair = PublicTools.reGenerateAdbKeyPair()
                Toast.makeText(context, context.getString(R.string.toast_success), Toast.LENGTH_SHORT).show()
              },
            )
          }

          SettingsSection(title = stringResource(R.string.set_section_general)) {
            SettingsGeneralContent(
              onToggleLocale = {
                val next = if (AppData.setting.locale == "en") "zh" else "en"
                AppData.setting.locale = next
                Toast.makeText(
                  context,
                  context.getString(R.string.toast_change_locale),
                  Toast.LENGTH_SHORT,
                ).show()
              },
            )
          }

          SettingsSection(title = stringResource(R.string.set_section_diagnostics)) {
            SettingsDiagnosticsContent(onOpenErrorLogs = onOpenErrorLogs)
          }

          SettingsSection(title = stringResource(R.string.set_section_about)) {
            SettingsAboutContent(
              onOpenWebsite = {
                PublicTools.startUrl(context, "https://github.com/shiyunjin/EasyControlNext")
              },
            )
          }
        }
      }
    }
  }
}

private data class SettingsPaneItem(
  val pane: SettingsPane,
  val icon: ImageVector,
  val title: String,
  val detail: String,
)

@Composable
private fun SettingsPaneNavCard(
  icon: ImageVector,
  title: String,
  detail: String,
  selected: Boolean,
  onClick: () -> Unit,
) {
  val borderColor = if (selected) AccentBlue else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
  Card(
    modifier = Modifier
      .fillMaxWidth()
      .border(1.dp, borderColor, RoundedCornerShape(20.dp))
      .clickable(onClick = onClick),
    shape = RoundedCornerShape(20.dp),
    colors = CardDefaults.cardColors(
      containerColor = if (selected) {
        AccentBlue.copy(alpha = 0.08f)
      } else {
        MaterialTheme.colorScheme.surface
      },
    ),
    elevation = CardDefaults.cardElevation(0.dp),
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(16.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = AccentBlue,
        modifier = Modifier.size(22.dp),
      )
      Spacer(modifier = Modifier.width(14.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
          title,
          style = MaterialTheme.typography.titleSmall,
          fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
          detail,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
  }
}

@Composable
private fun SettingsConnectionContent(
  onOpenPresets: () -> Unit,
  onOpenIp: () -> Unit,
  onOpenAdbKey: () -> Unit,
  onResetKey: () -> Unit,
) {
  SettingsNavRow(
    icon = Icons.Default.Tune,
    title = stringResource(R.string.set_presets),
    detail = stringResource(R.string.set_presets_detail),
    onClick = onOpenPresets,
  )
  SettingsDivider()
  SettingsReachabilityTimeoutRow()
  SettingsDivider()
  SettingsNavRow(
    icon = Icons.Default.Wifi,
    title = stringResource(R.string.set_other_ip),
    detail = stringResource(R.string.set_other_ip_detail),
    onClick = onOpenIp,
  )
  SettingsDivider()
  SettingsNavRow(
    icon = Icons.Default.Key,
    title = stringResource(R.string.set_other_custom_key),
    detail = stringResource(R.string.set_other_custom_key_detail),
    onClick = onOpenAdbKey,
  )
  SettingsDivider()
  SettingsNavRow(
    icon = Icons.Default.Refresh,
    title = stringResource(R.string.set_other_reset_key),
    detail = stringResource(R.string.set_other_reset_key_detail),
    onClick = onResetKey,
  )
}

@Composable
private fun SettingsReachabilityTimeoutRow() {
  var selectedMs by remember {
    mutableIntStateOf(AppData.setting.reachabilityTimeoutMs)
  }
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .padding(vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = Icons.Default.Timer,
      contentDescription = null,
      tint = AccentBlue,
      modifier = Modifier.size(22.dp),
    )
    Spacer(modifier = Modifier.width(14.dp))
    Column(modifier = Modifier.weight(1f)) {
      Text(
        stringResource(R.string.set_reachability_timeout),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(2.dp))
      Text(
        stringResource(R.string.set_reachability_timeout_detail),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Spacer(modifier = Modifier.height(8.dp))
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Setting.REACHABILITY_TIMEOUT_OPTIONS_MS.forEach { ms ->
          FilterChip(
            selected = selectedMs == ms,
            onClick = {
              selectedMs = ms
              AppData.setting.reachabilityTimeoutMs = ms
            },
            label = { Text(stringResource(R.string.set_reachability_timeout_option, ms)) },
          )
        }
      }
    }
  }
}

@Composable
private fun SettingsGeneralContent(onToggleLocale: () -> Unit) {
  SettingsNavRow(
    icon = Icons.Default.Language,
    title = stringResource(R.string.set_other_locale),
    detail = stringResource(R.string.set_other_locale_detail),
    onClick = onToggleLocale,
  )
}

@Composable
private fun SettingsDiagnosticsContent(onOpenErrorLogs: () -> Unit) {
  SettingsNavRow(
    icon = Icons.Default.BugReport,
    title = stringResource(R.string.set_other_error_log),
    detail = stringResource(R.string.set_other_error_log_detail),
    onClick = onOpenErrorLogs,
  )
}

@Composable
private fun SettingsAboutContent(onOpenWebsite: () -> Unit) {
  SettingsNavRow(
    icon = Icons.Default.Link,
    title = stringResource(R.string.set_about_website),
    detail = stringResource(R.string.set_about_website_detail),
    onClick = onOpenWebsite,
  )
  SettingsDivider()
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .padding(vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(modifier = Modifier.weight(1f)) {
      Text(
        stringResource(R.string.set_about_version),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(2.dp))
      Text(
        BuildConfig.VERSION_NAME,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
private fun SettingsSection(
  title: String,
  content: @Composable () -> Unit,
) {
  Card(
    modifier = Modifier.fillMaxWidth(),
    shape = RoundedCornerShape(20.dp),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    elevation = CardDefaults.cardElevation(0.dp),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(8.dp))
      content()
    }
  }
}

@Composable
private fun SettingsDivider() {
  HorizontalDivider(
    modifier = Modifier.padding(start = 44.dp),
    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f),
  )
}

@Composable
private fun SettingsNavRow(
  icon: ImageVector,
  title: String,
  detail: String,
  onClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onClick)
      .padding(vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = null,
      tint = AccentBlue,
      modifier = Modifier.size(22.dp),
    )
    Spacer(modifier = Modifier.width(14.dp))
    Column(modifier = Modifier.weight(1f)) {
      Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(2.dp))
      Text(
        detail,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    Icon(
      imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
      contentDescription = null,
      tint = MaterialTheme.colorScheme.onSurfaceVariant,
    )
  }
}
