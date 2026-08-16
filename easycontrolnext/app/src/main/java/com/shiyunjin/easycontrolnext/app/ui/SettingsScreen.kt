package com.shiyunjin.easycontrolnext.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
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
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.StayCurrentPortrait
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VideoSettings
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.window.core.layout.WindowSizeClass
import com.shiyunjin.easycontrolnext.app.BuildConfig
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.adb.AdbKeyPair
import com.shiyunjin.easycontrolnext.app.client.decode.DecodecTools
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.Setting
import com.shiyunjin.easycontrolnext.app.helper.PublicTools
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.NetworkInterface

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
            SettingsConnectionContent(onOpenPresets = onOpenPresets)
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
) {
  var showIpSheet by remember { mutableStateOf(false) }
  var showAdbKeySheet by remember { mutableStateOf(false) }
  var showResetKeyDialog by remember { mutableStateOf(false) }

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
    onClick = { showIpSheet = true },
  )
  SettingsDivider()
  SettingsNavRow(
    icon = Icons.Default.Key,
    title = stringResource(R.string.set_other_custom_key),
    detail = stringResource(R.string.set_other_custom_key_detail),
    onClick = { showAdbKeySheet = true },
  )
  SettingsDivider()
  SettingsNavRow(
    icon = Icons.Default.Refresh,
    title = stringResource(R.string.set_other_reset_key),
    detail = stringResource(R.string.set_other_reset_key_detail),
    onClick = { showResetKeyDialog = true },
  )
  SettingsDivider()
  SettingsDecoderCapsRow()

  if (showIpSheet) {
    LocalIpAddressesSheet(onDismiss = { showIpSheet = false })
  }
  if (showAdbKeySheet) {
    CustomAdbKeySheet(onDismiss = { showAdbKeySheet = false })
  }
  if (showResetKeyDialog) {
    ResetAdbKeyDialog(onDismiss = { showResetKeyDialog = false })
  }
}

@Composable
private fun SettingsDecoderCapsRow() {
  var caps by remember { mutableStateOf<DecodecTools.LocalDecoderCaps?>(null) }
  var probing by remember { mutableStateOf(true) }
  val scope = rememberCoroutineScope()

  fun refresh() {
    probing = true
    scope.launch {
      val result = withContext(Dispatchers.Default) {
        DecodecTools.probeLocalDecoderCaps()
      }
      caps = result
      probing = false
    }
  }

  LaunchedEffect(Unit) { refresh() }

  val supported = stringResource(R.string.set_decode_caps_supported)
  val unsupported = stringResource(R.string.set_decode_caps_unsupported)
  val hw = stringResource(R.string.set_decode_caps_hw)
  val sw = stringResource(R.string.set_decode_caps_sw)
  val main8 = stringResource(R.string.set_decode_caps_hevc_main)
  val main10 = stringResource(R.string.set_decode_caps_hevc_main10)

  fun implLabel(hasHw: Boolean, hasSw: Boolean): String = when {
    hasHw -> "$supported · $hw"
    hasSw -> "$supported · $sw"
    else -> unsupported
  }

  SettingsStackedRow(
    icon = Icons.Default.VideoSettings,
    title = stringResource(R.string.set_decode_caps),
    detail = stringResource(R.string.set_decode_caps_detail),
  ) {
    Text(
      text = stringResource(R.string.set_decode_caps_refresh),
      style = MaterialTheme.typography.labelLarge,
      color = if (probing) {
        MaterialTheme.colorScheme.onSurfaceVariant
      } else {
        AccentBlue
      },
      modifier = Modifier
        .clickable(enabled = !probing, onClick = { refresh() })
        .padding(vertical = 4.dp),
    )
    Spacer(modifier = Modifier.height(4.dp))
    if (probing && caps == null) {
      Text(
        stringResource(R.string.set_decode_caps_probing),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    } else {
      val c = caps
      if (c != null) {
        val hevcProfiles = buildList {
          if (c.hevcMain) add(main8)
          if (c.hevcMain10) add(main10)
        }.joinToString(" / ")
        val hevcExtra = if ((c.hevcHw || c.hevcSw) && hevcProfiles.isNotEmpty()) {
          stringResource(R.string.set_decode_caps_hevc_profiles, hevcProfiles)
        } else {
          null
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          DecoderCapLine(stringResource(R.string.set_decode_caps_avc), implLabel(c.avcHw, c.avcSw))
          DecoderCapLine(
            title = stringResource(R.string.set_decode_caps_hevc),
            status = implLabel(c.hevcHw, c.hevcSw),
            spec = hevcExtra,
          )
          DecoderCapLine(stringResource(R.string.set_decode_caps_av1), implLabel(c.av1Hw, c.av1Sw))
          DecoderCapLine(stringResource(R.string.set_decode_caps_opus), implLabel(c.opusHw, c.opusSw))
          DecoderCapLine(stringResource(R.string.set_decode_caps_aac), implLabel(c.aacHw, c.aacSw))
        }
      }
    }
  }
}

@Composable
private fun DecoderCapLine(
  title: String,
  status: String,
  spec: String? = null,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        title,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurface,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      Spacer(modifier = Modifier.width(12.dp))
      Text(
        status,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.End,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    if (spec != null) {
      Text(
        spec,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 2.dp),
      )
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsReachabilityTimeoutRow() {
  var selectedMs by remember {
    mutableIntStateOf(AppData.setting.reachabilityTimeoutMs)
  }
  var expanded by remember { mutableStateOf(false) }
  val fieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    focusedLabelColor = AccentBlue,
    cursorColor = AccentBlue,
  )
  SettingsStackedRow(
    icon = Icons.Default.Timer,
    title = stringResource(R.string.set_reachability_timeout),
    detail = stringResource(R.string.set_reachability_timeout_detail),
  ) {
    ExposedDropdownMenuBox(
      expanded = expanded,
      onExpandedChange = { expanded = it },
      modifier = Modifier.widthIn(max = 220.dp),
    ) {
      OutlinedTextField(
        value = stringResource(R.string.set_reachability_timeout_option, selectedMs),
        onValueChange = {},
        readOnly = true,
        singleLine = true,
        modifier = Modifier
          .menuAnchor(type = ExposedDropdownMenuAnchorType.PrimaryNotEditable)
          .fillMaxWidth(),
        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
        textStyle = MaterialTheme.typography.bodyMedium,
        shape = RoundedCornerShape(14.dp),
        colors = fieldColors,
      )
      ExposedDropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
      ) {
        Setting.REACHABILITY_TIMEOUT_OPTIONS_MS.forEach { ms ->
          DropdownMenuItem(
            text = { Text(stringResource(R.string.set_reachability_timeout_option, ms)) },
            onClick = {
              selectedMs = ms
              AppData.setting.reachabilityTimeoutMs = ms
              expanded = false
            },
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
  SettingsDivider()
  SettingsKeepScreenOnRow()
}

@Composable
private fun SettingsKeepScreenOnRow() {
  var enabled by remember {
    mutableStateOf(AppData.setting.keepScreenOnDuringControl)
  }
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .padding(vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Icon(
      imageVector = Icons.Default.StayCurrentPortrait,
      contentDescription = null,
      tint = AccentBlue,
      modifier = Modifier.size(22.dp),
    )
    Spacer(modifier = Modifier.width(14.dp))
    Column(modifier = Modifier.weight(1f)) {
      Text(
        stringResource(R.string.set_keep_screen_on),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(2.dp))
      Text(
        stringResource(R.string.set_keep_screen_on_detail),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    Switch(
      checked = enabled,
      onCheckedChange = {
        enabled = it
        AppData.setting.keepScreenOnDuringControl = it
      },
      colors = SwitchDefaults.colors(checkedTrackColor = AccentBlue),
    )
  }
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

/** Icon + title/detail like [SettingsNavRow]; extra controls sit under the text column. */
@Composable
private fun SettingsStackedRow(
  icon: ImageVector,
  title: String,
  detail: String,
  content: @Composable ColumnScope.() -> Unit,
) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .padding(vertical = 10.dp),
  ) {
    Row(
      modifier = Modifier.fillMaxWidth(),
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
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(start = 36.dp, top = 8.dp),
      content = content,
    )
  }
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

private data class LocalIpEntry(
  val iface: String,
  val address: String,
  val ipv4: Boolean,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LocalIpAddressesSheet(onDismiss: () -> Unit) {
  val context = LocalContext.current
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val entries = remember { collectLocalIpEntries() }
  val ipv4 = entries.filter { it.ipv4 }
  val ipv6 = entries.filter { !it.ipv4 }

  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = sheetState,
    containerColor = MaterialTheme.colorScheme.surface,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      Text(
        stringResource(R.string.set_other_ip),
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(6.dp))
      Text(
        stringResource(R.string.set_ip_sheet_detail),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Spacer(modifier = Modifier.height(16.dp))
      LocalIpAddressSection(
        title = stringResource(R.string.set_ip_section_ipv4),
        entries = ipv4,
        onCopy = { copySettingText(context, it) },
      )
      Spacer(modifier = Modifier.height(16.dp))
      LocalIpAddressSection(
        title = stringResource(R.string.set_ip_section_ipv6),
        entries = ipv6,
        onCopy = { copySettingText(context, it) },
      )
    }
  }
}

@Composable
private fun LocalIpAddressSection(
  title: String,
  entries: List<LocalIpEntry>,
  onCopy: (String) -> Unit,
) {
  Text(
    title,
    style = MaterialTheme.typography.labelLarge,
    color = AccentBlue,
    fontWeight = FontWeight.SemiBold,
  )
  Spacer(modifier = Modifier.height(6.dp))
  if (entries.isEmpty()) {
    Text(
      stringResource(R.string.set_ip_empty),
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
      modifier = Modifier.padding(vertical = 8.dp),
    )
  } else {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
      entries.forEach { entry ->
        LocalIpAddressRow(entry = entry, onCopy = { onCopy(entry.address) })
      }
    }
  }
}

@Composable
private fun LocalIpAddressRow(
  entry: LocalIpEntry,
  onCopy: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onCopy)
      .padding(vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(modifier = Modifier.weight(1f)) {
      Text(
        entry.address,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace,
      )
      if (entry.iface.isNotBlank()) {
        Spacer(modifier = Modifier.height(2.dp))
        Text(
          entry.iface,
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
    }
    Icon(
      imageVector = Icons.Default.ContentCopy,
      contentDescription = stringResource(R.string.set_ip_copy),
      tint = MaterialTheme.colorScheme.onSurfaceVariant,
      modifier = Modifier.size(20.dp),
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomAdbKeySheet(onDismiss: () -> Unit) {
  val context = LocalContext.current
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val fieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    focusedLabelColor = AccentBlue,
    cursorColor = AccentBlue,
  )
  var pubText by remember { mutableStateOf("") }
  var priText by remember { mutableStateOf("") }

  LaunchedEffect(Unit) {
    val files = PublicTools.getAdbKeyFile(context)
    pubText = readKeyFile(files.first)
    priText = readKeyFile(files.second)
  }

  val pickPub = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
    if (uri == null) return@rememberLauncherForActivityResult
    val text = readUriText(context, uri)
    if (text.isEmpty()) {
      Toast.makeText(context, context.getString(R.string.toast_fail), Toast.LENGTH_SHORT).show()
    } else {
      pubText = text
    }
  }
  val pickPri = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
    if (uri == null) return@rememberLauncherForActivityResult
    val text = readUriText(context, uri)
    if (text.isEmpty()) {
      Toast.makeText(context, context.getString(R.string.toast_fail), Toast.LENGTH_SHORT).show()
    } else {
      priText = text
    }
  }

  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = sheetState,
    containerColor = MaterialTheme.colorScheme.surface,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .imePadding()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      Text(
        stringResource(R.string.set_other_custom_key),
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.SemiBold,
      )
      Spacer(modifier = Modifier.height(6.dp))
      Text(
        stringResource(R.string.set_adb_key_sheet_detail),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Spacer(modifier = Modifier.height(16.dp))
      OutlinedTextField(
        value = pubText,
        onValueChange = { pubText = it },
        modifier = Modifier
          .fillMaxWidth()
          .heightIn(min = 88.dp),
        label = { Text(stringResource(R.string.adb_key_pub)) },
        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        minLines = 3,
        maxLines = 6,
        shape = RoundedCornerShape(14.dp),
        colors = fieldColors,
      )
      Spacer(modifier = Modifier.height(12.dp))
      OutlinedTextField(
        value = priText,
        onValueChange = { priText = it },
        modifier = Modifier
          .fillMaxWidth()
          .heightIn(min = 88.dp),
        label = { Text(stringResource(R.string.adb_key_pri)) },
        textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        minLines = 3,
        maxLines = 8,
        shape = RoundedCornerShape(14.dp),
        colors = fieldColors,
      )
      Spacer(modifier = Modifier.height(12.dp))
      OutlinedButton(
        onClick = { pickPub.launch("*/*") },
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
      ) {
        Text(stringResource(R.string.set_adb_key_import_pub))
      }
      Spacer(modifier = Modifier.height(8.dp))
      OutlinedButton(
        onClick = { pickPri.launch("*/*") },
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
      ) {
        Text(stringResource(R.string.set_adb_key_import_pri))
      }
      Spacer(modifier = Modifier.height(8.dp))
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
      ) {
        TextButton(onClick = onDismiss) {
          Text(stringResource(android.R.string.cancel))
        }
        TextButton(
          onClick = {
            if (saveCustomAdbKey(context, pubText, priText)) {
              Toast.makeText(context, context.getString(R.string.toast_success), Toast.LENGTH_SHORT).show()
              onDismiss()
            } else {
              Toast.makeText(context, context.getString(R.string.toast_fail), Toast.LENGTH_SHORT).show()
            }
          },
        ) {
          Text(stringResource(R.string.adb_key_button), color = AccentBlue)
        }
      }
    }
  }
}

@Composable
private fun ResetAdbKeyDialog(onDismiss: () -> Unit) {
  val context = LocalContext.current
  AlertDialog(
    onDismissRequest = onDismiss,
    title = {
      Text(
        stringResource(R.string.set_reset_key_title),
        fontWeight = FontWeight.SemiBold,
      )
    },
    text = {
      Text(
        stringResource(R.string.set_reset_key_message),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    },
    confirmButton = {
      TextButton(
        onClick = {
          AppData.keyPair = PublicTools.reGenerateAdbKeyPair()
          onDismiss()
          Toast.makeText(context, context.getString(R.string.toast_success), Toast.LENGTH_SHORT).show()
        },
      ) {
        Text(
          stringResource(R.string.set_reset_key_confirm),
          color = MaterialTheme.colorScheme.error,
        )
      }
    },
    dismissButton = {
      TextButton(onClick = onDismiss) {
        Text(stringResource(android.R.string.cancel))
      }
    },
  )
}

private fun collectLocalIpEntries(): List<LocalIpEntry> {
  val entries = mutableListOf<LocalIpEntry>()
  try {
    val interfaces = NetworkInterface.getNetworkInterfaces() ?: return fallbackLocalIpEntries()
    while (interfaces.hasMoreElements()) {
      val nif = interfaces.nextElement()
      val addrs = nif.inetAddresses
      while (addrs.hasMoreElements()) {
        val inet = addrs.nextElement()
        if (inet.isLoopbackAddress) continue
        val name = nif.displayName.orEmpty().ifBlank { nif.name.orEmpty() }
        when (inet) {
          is Inet4Address -> {
            val host = inet.hostAddress ?: continue
            entries += LocalIpEntry(name, host, ipv4 = true)
          }
          is Inet6Address -> {
            if (inet.isLinkLocalAddress) continue
            val host = inet.hostAddress ?: continue
            entries += LocalIpEntry(name, "[$host]", ipv4 = false)
          }
        }
      }
    }
  } catch (_: Exception) {
    return fallbackLocalIpEntries()
  }
  return entries.ifEmpty { fallbackLocalIpEntries() }
}

private fun fallbackLocalIpEntries(): List<LocalIpEntry> {
  val pair = PublicTools.getLocalIp()
  return pair.first.map { LocalIpEntry("", it, ipv4 = true) } +
    pair.second.map { LocalIpEntry("", it, ipv4 = false) }
}

private fun copySettingText(context: Context, text: String) {
  val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
  clipboard.setPrimaryClip(ClipData.newPlainText("easycontrol", text))
  Toast.makeText(context, context.getString(R.string.toast_copy), Toast.LENGTH_SHORT).show()
}

private fun readKeyFile(file: File): String {
  return try {
    if (file.isFile) file.readText() else ""
  } catch (_: Exception) {
    ""
  }
}

private fun readUriText(context: Context, uri: Uri?): String {
  if (uri == null) return ""
  return try {
    context.contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
  } catch (_: Exception) {
    ""
  }
}

private fun saveCustomAdbKey(context: Context, publicKey: String, privateKey: String): Boolean {
  return try {
    val files = PublicTools.getAdbKeyFile(context)
    files.first.writeText(publicKey)
    files.second.writeText(privateKey)
    AppData.keyPair = AdbKeyPair.read(files.first, files.second)
    true
  } catch (_: Exception) {
    false
  }
}
