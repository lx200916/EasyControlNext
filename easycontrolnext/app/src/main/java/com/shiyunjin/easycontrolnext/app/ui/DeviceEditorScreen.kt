package com.shiyunjin.easycontrolnext.app.ui

import android.graphics.Bitmap
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.window.core.layout.WindowSizeClass
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.adb.AdbQrPairing
import com.shiyunjin.easycontrolnext.app.client.Client
import com.shiyunjin.easycontrolnext.app.client.tools.AdbTools
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.ConnectionPreset
import com.shiyunjin.easycontrolnext.app.entity.Device
import com.shiyunjin.easycontrolnext.app.helper.AppErrorLog
import com.shiyunjin.easycontrolnext.app.helper.LanDeviceScanner
import com.shiyunjin.easycontrolnext.app.helper.PresetStore
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class DeviceEditorPane {
  Basic,
  Pairing,
  Preset,
  Video,
  OnConnect,
  OnRunning,
  OnClose,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceEditorScreen(
  uuid: String,
  onBack: () -> Unit,
  onSaved: () -> Unit,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  val isNew = uuid == "new"
  val windowSizeClass = currentWindowAdaptiveInfo().windowSizeClass
  val usePanes = windowSizeClass.isWidthAtLeastBreakpoint(
    WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND,
  )
  var selectedPane by remember { mutableStateOf(DeviceEditorPane.Basic) }

  val existing = remember(uuid) {
    if (isNew) null else AppData.dbHelper.getByUUID(uuid)
  }

  var form by remember { mutableStateOf(DeviceFormState.from(existing)) }
  var busy by remember { mutableStateOf(false) }
  var status by remember { mutableStateOf<String?>(null) }
  var showSearch by remember { mutableStateOf(false) }
  var showQr by remember { mutableStateOf(false) }
  var showPresetPicker by remember { mutableStateOf(false) }

  fun persist(device: Device) {
    if (isNew) AppData.dbHelper.insert(device) else AppData.dbHelper.update(device)
  }

  fun updateForm(next: DeviceFormState) {
    val merged = form.mergeStateDetachingPreset(next)
    if (form.isPresetLinked && !merged.isPresetLinked) {
      status = context.getString(R.string.preset_detached)
    }
    form = merged
  }

  fun pairManual() {
    if (busy) return
    val host = form.address.trim()
    val pPort = form.pairPort.trim().toIntOrNull() ?: 0
    val code = AdbTools.normalizePairCode(form.pairCode)
    if (host.isEmpty() || pPort <= 0 || code.isEmpty()) {
      Toast.makeText(context, "请填写 IP、配对端口和配对码，或改用二维码配对", Toast.LENGTH_SHORT).show()
      return
    }
    busy = true
    status = "正在配对…"
    scope.launch {
      try {
        withContext(Dispatchers.IO) { AdbTools.pairWireless(host, pPort, form.pairCode) }
        val discovered = withContext(Dispatchers.IO) {
          AdbTools.discoverTlsConnectPort(context, host, 4000)
        }
        if (discovered > 0) {
          form = form.copy(connectPort = discovered.toString(), pairPort = "", pairCode = "")
          status = "配对成功。已填入连接端口 $discovered"
        } else {
          form = form.copy(pairPort = "", pairCode = "")
          status = "配对成功。请确认连接端口后保存。"
        }
        Toast.makeText(context, "配对成功", Toast.LENGTH_SHORT).show()
      } catch (e: Exception) {
        status = e.message
        AppErrorLog.e("pair", e.message ?: "配对失败", e)
        Toast.makeText(context, e.message ?: "配对失败", Toast.LENGTH_LONG).show()
      } finally {
        busy = false
      }
    }
  }

  fun saveOnly() {
    if (busy) return
    if (form.address.trim().isEmpty()) {
      Toast.makeText(context, "请填写或搜索 IP", Toast.LENGTH_SHORT).show()
      return
    }
    if ((form.connectPort.trim().toIntOrNull() ?: 0) <= 0) {
      Toast.makeText(context, "请填写连接端口", Toast.LENGTH_SHORT).show()
      return
    }
    persist(form.toDevice(existing))
    DeviceListStore.refresh()
    onSaved()
  }

  fun saveAndConnect() {
    if (busy) return
    if (form.address.trim().isEmpty()) {
      Toast.makeText(context, "请填写或搜索 IP", Toast.LENGTH_SHORT).show()
      return
    }
    busy = true
    status = "连接中…"
    scope.launch {
      try {
        val device = form.toDevice(existing)
        if (device.adbPort <= 0) {
          val discovered = withContext(Dispatchers.IO) {
            if (device.pairPort > 0 && AdbTools.normalizePairCode(device.pairKey).isNotEmpty()) {
              AdbTools.pairWireless(device.address, device.pairPort, device.pairKey)
              device.pairPort = 0
              device.pairKey = ""
            }
            AdbTools.discoverTlsConnectPort(context, device.address, 4000)
          }
          if (discovered > 0) {
            device.adbPort = discovered
            form = form.copy(connectPort = discovered.toString())
          }
        }
        if (device.adbPort <= 0) throw Exception("缺少连接端口")
        persist(device)
        DeviceListStore.refresh()
        withContext(Dispatchers.Main) {
          Client.startDevice(device)
          onSaved()
        }
      } catch (e: Exception) {
        status = e.message
        AppErrorLog.e("connect", e.message ?: "连接失败", e)
        Toast.makeText(context, e.message ?: "连接失败", Toast.LENGTH_LONG).show()
      } finally {
        busy = false
      }
    }
  }

  val fieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    cursorColor = AccentBlue,
    focusedLabelColor = AccentBlue,
  )

  val panes = listOf(
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.Basic,
      icon = Icons.Default.Wifi,
      title = stringResource(R.string.device_editor_section_basic),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.Pairing,
      icon = Icons.Default.QrCode2,
      title = stringResource(R.string.device_editor_section_pairing),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.Preset,
      icon = Icons.Default.Tune,
      title = stringResource(R.string.device_editor_section_preset),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.Video,
      icon = Icons.Default.Videocam,
      title = stringResource(R.string.device_editor_section_video),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.OnConnect,
      icon = Icons.Default.Link,
      title = stringResource(R.string.device_editor_section_on_connect),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.OnRunning,
      icon = Icons.Default.Settings,
      title = stringResource(R.string.device_editor_section_on_running),
    ),
    DeviceEditorPaneItem(
      pane = DeviceEditorPane.OnClose,
      icon = Icons.Default.Close,
      title = stringResource(R.string.device_editor_section_on_close),
    ),
  )

  Scaffold(
    containerColor = MaterialTheme.colorScheme.background,
    // Global actions: bottom chrome of the whole editor (not under title, not inside a section).
    bottomBar = {
      Surface(color = MaterialTheme.colorScheme.surface) {
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        ) {
          HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f),
          )
          DeviceEditorActionBar(
            busy = busy,
            status = status,
            compact = !usePanes,
            onPairManual = ::pairManual,
            onSave = ::saveOnly,
            onSaveAndConnect = ::saveAndConnect,
            modifier = Modifier
              .fillMaxWidth()
              .padding(horizontal = 20.dp, vertical = 8.dp),
          )
        }
      }
    },
  ) { padding ->
    // Scaffold contentWindowInsets already include status/nav bars — apply once via padding.
    // bottomBar height is included in padding so panes/form sit above the action chrome.
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding),
    ) {
      Row(
        modifier = Modifier
          .fillMaxWidth()
          // Scaffold already insets for statusBars; modest extra top so title isn't cramped.
          .padding(start = 8.dp, top = 12.dp, end = 8.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        IconButton(onClick = onBack) {
          Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
        }
        Column(modifier = Modifier.weight(1f)) {
          Text(
            stringResource(if (isNew) R.string.device_editor_title_add else R.string.device_editor_title_edit),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
          )
          Text(
            stringResource(R.string.device_editor_subtitle),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      if (usePanes) {
        Row(
          modifier = Modifier
            .weight(1f)
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
        ) {
          Column(
            modifier = Modifier
              .weight(0.36f)
              .fillMaxHeight()
              .widthIn(max = 340.dp)
              .verticalScroll(rememberScrollState())
              .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            panes.forEach { item ->
              DeviceEditorPaneNavCard(
                icon = item.icon,
                title = item.title,
                selected = selectedPane == item.pane,
                onClick = { selectedPane = item.pane },
              )
            }
          }
          Spacer(modifier = Modifier.width(16.dp))
          Card(
            modifier = Modifier
              .weight(0.64f)
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
              DeviceEditorPaneBody(
                pane = selectedPane,
                form = form,
                fieldColors = fieldColors,
                onFormChange = { form = it },
                onAdvancedChange = ::updateForm,
                onShowSearch = { showSearch = true },
                onShowQr = { showQr = true },
                onShowPresetPicker = { showPresetPicker = true },
                onDetachPreset = {
                  form = form.copy(presetId = "")
                  status = context.getString(R.string.preset_detached)
                },
              )
            }
          }
        }
      } else {
        Column(
          modifier = Modifier
            .weight(1f)
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 16.dp),
          verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          SectionCard(title = "基本信息") {
            DeviceBasicFields(
              form = form,
              fieldColors = fieldColors,
              onFormChange = { form = it },
              onShowSearch = { showSearch = true },
            )
          }

          SectionCard(title = "无线配对") {
            DevicePairingFields(
              form = form,
              fieldColors = fieldColors,
              onFormChange = { form = it },
              onShowQr = { showQr = true },
            )
          }

          SectionCard(title = stringResource(R.string.preset_apply_section)) {
            DevicePresetFields(
              form = form,
              onShowPresetPicker = { showPresetPicker = true },
              onDetachPreset = {
                form = form.copy(presetId = "")
                status = context.getString(R.string.preset_detached)
              },
            )
          }

          SectionCard(title = "高级配置") {
            Text(
              stringResource(R.string.device_editor_advanced_hint),
              style = MaterialTheme.typography.bodySmall,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            DeviceAdvancedConfig(
              state = form,
              onStateChange = ::updateForm,
            )
          }
        }
      }
    }
  }

  if (showPresetPicker) {
    ApplyPresetDialog(
      onDismiss = { showPresetPicker = false },
      onPick = { preset ->
        form = form.applyPreset(preset)
        showPresetPicker = false
        status = context.getString(R.string.preset_applied, preset.name)
        Toast.makeText(context, context.getString(R.string.preset_applied, preset.name), Toast.LENGTH_SHORT).show()
      },
    )
  }

  if (showSearch) {
    IpSearchDialog(
      onDismiss = { showSearch = false },
      onPick = { result ->
        form = form.copy(
          address = result.host,
          connectPort = if (result.port != null && result.port > 0 && result.source != "mdns-pairing") {
            result.port.toString()
          } else form.connectPort,
          pairPort = if (result.source == "mdns-pairing" && result.port != null) {
            result.port.toString()
          } else form.pairPort,
        )
        showSearch = false
        status = "已选择 ${result.label}"
      },
    )
  }

  if (showQr) {
    QrPairDialog(
      onDismiss = { showQr = false },
      onPaired = { host, port ->
        form = form.copy(
          address = host,
          connectPort = if (port > 0) port.toString() else form.connectPort,
          pairPort = "",
          pairCode = "",
        )
        showQr = false
        status = if (port > 0) "二维码配对成功 · $host:$port" else "二维码配对成功 · $host（请确认连接端口）"
        Toast.makeText(context, "配对成功", Toast.LENGTH_SHORT).show()
      },
    )
  }
}

private data class DeviceEditorPaneItem(
  val pane: DeviceEditorPane,
  val icon: ImageVector,
  val title: String,
)

@Composable
private fun DeviceEditorPaneNavCard(
  icon: ImageVector,
  title: String,
  selected: Boolean,
  onClick: () -> Unit,
) {
  val borderColor = if (selected) AccentBlue else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
  Card(
    modifier = Modifier
      .fillMaxWidth()
      .border(1.dp, borderColor, RoundedCornerShape(16.dp))
      .clickable(onClick = onClick),
    shape = RoundedCornerShape(16.dp),
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
        .padding(horizontal = 14.dp, vertical = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        imageVector = icon,
        contentDescription = null,
        tint = AccentBlue,
        modifier = Modifier.size(20.dp),
      )
      Spacer(modifier = Modifier.width(12.dp))
      Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
      )
    }
  }
}

@Composable
private fun DeviceEditorPaneBody(
  pane: DeviceEditorPane,
  form: DeviceFormState,
  fieldColors: androidx.compose.material3.TextFieldColors,
  onFormChange: (DeviceFormState) -> Unit,
  onAdvancedChange: (DeviceFormState) -> Unit,
  onShowSearch: () -> Unit,
  onShowQr: () -> Unit,
  onShowPresetPicker: () -> Unit,
  onDetachPreset: () -> Unit,
) {
  when (pane) {
    DeviceEditorPane.Basic -> DeviceBasicFields(
      form = form,
      fieldColors = fieldColors,
      onFormChange = onFormChange,
      onShowSearch = onShowSearch,
    )
    DeviceEditorPane.Pairing -> DevicePairingFields(
      form = form,
      fieldColors = fieldColors,
      onFormChange = onFormChange,
      onShowQr = onShowQr,
    )
    DeviceEditorPane.Preset -> DevicePresetFields(
      form = form,
      onShowPresetPicker = onShowPresetPicker,
      onDetachPreset = onDetachPreset,
    )
    DeviceEditorPane.Video -> DeviceVideoParamsConfig(
      state = form,
      onStateChange = onAdvancedChange,
    )
    DeviceEditorPane.OnConnect -> DeviceOnConnectConfig(
      state = form,
      onStateChange = onAdvancedChange,
    )
    DeviceEditorPane.OnRunning -> DeviceOnRunningConfig(
      state = form,
      onStateChange = onAdvancedChange,
    )
    DeviceEditorPane.OnClose -> DeviceOnCloseConfig(
      state = form,
      onStateChange = onAdvancedChange,
    )
  }
}

@Composable
private fun DeviceBasicFields(
  form: DeviceFormState,
  fieldColors: androidx.compose.material3.TextFieldColors,
  onFormChange: (DeviceFormState) -> Unit,
  onShowSearch: () -> Unit,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    OutlinedTextField(
      value = form.name,
      onValueChange = { onFormChange(form.copy(name = it)) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text("名称") },
      singleLine = true,
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
    Spacer(modifier = Modifier.height(10.dp))
    Row(
      modifier = Modifier.fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      OutlinedTextField(
        value = form.address,
        onValueChange = { onFormChange(form.copy(address = it)) },
        modifier = Modifier.weight(1f),
        label = { Text("被控机 IP") },
        placeholder = { Text("192.168.x.x") },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
        shape = RoundedCornerShape(14.dp),
        colors = fieldColors,
      )
      Spacer(modifier = Modifier.width(8.dp))
      IconButton(
        onClick = onShowSearch,
        modifier = Modifier
          .size(52.dp)
          .clip(RoundedCornerShape(14.dp))
          .background(AccentBlue.copy(alpha = 0.12f)),
      ) {
        Icon(Icons.Default.Search, contentDescription = "搜索 IP", tint = AccentBlue)
      }
    }
    Spacer(modifier = Modifier.height(10.dp))
    OutlinedTextField(
      value = form.connectPort,
      onValueChange = { onFormChange(form.copy(connectPort = it.filter(Char::isDigit).take(5))) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text("连接端口") },
      placeholder = { Text("无线调试主页顶部端口") },
      supportingText = { Text("不是配对弹窗端口；Android 11+ 通常也不是 5555") },
      singleLine = true,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
  }
}

@Composable
private fun DevicePairingFields(
  form: DeviceFormState,
  fieldColors: androidx.compose.material3.TextFieldColors,
  onFormChange: (DeviceFormState) -> Unit,
  onShowQr: () -> Unit,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    Text(
      "首次连接需要配对。推荐二维码；也可手动填配对码。",
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(12.dp))
    OutlinedButton(
      onClick = onShowQr,
      modifier = Modifier.fillMaxWidth(),
      shape = RoundedCornerShape(14.dp),
      colors = ButtonDefaults.outlinedButtonColors(contentColor = AccentBlue),
    ) {
      Icon(Icons.Default.QrCode2, contentDescription = null)
      Spacer(modifier = Modifier.width(8.dp))
      Text("二维码配对", fontWeight = FontWeight.SemiBold)
    }
    Spacer(modifier = Modifier.height(12.dp))
    OutlinedTextField(
      value = form.pairPort,
      onValueChange = { onFormChange(form.copy(pairPort = it.filter(Char::isDigit).take(5))) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text("配对端口（可选）") },
      singleLine = true,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
    Spacer(modifier = Modifier.height(10.dp))
    OutlinedTextField(
      value = form.pairCode,
      onValueChange = { onFormChange(form.copy(pairCode = it)) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text("配对码（可选）") },
      placeholder = { Text("6 位，可带空格") },
      singleLine = true,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
  }
}

@Composable
private fun DevicePresetFields(
  form: DeviceFormState,
  onShowPresetPicker: () -> Unit,
  onDetachPreset: () -> Unit,
) {
  val linkedPreset = form.presetId.takeIf { it.isNotBlank() }?.let { PresetStore.get(it) }
  Column(modifier = Modifier.fillMaxWidth()) {
    Text(
      if (linkedPreset != null) {
        stringResource(R.string.preset_link_status_linked, linkedPreset.name)
      } else {
        stringResource(R.string.preset_link_status_custom)
      },
      style = MaterialTheme.typography.bodyMedium,
      fontWeight = FontWeight.Medium,
      color = if (linkedPreset != null) AccentBlue else MaterialTheme.colorScheme.onSurface,
    )
    Spacer(modifier = Modifier.height(4.dp))
    Text(
      stringResource(R.string.preset_apply_device_hint),
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(10.dp))
    OutlinedButton(
      onClick = onShowPresetPicker,
      modifier = Modifier.fillMaxWidth(),
      shape = RoundedCornerShape(14.dp),
      colors = ButtonDefaults.outlinedButtonColors(contentColor = AccentBlue),
    ) {
      Text(stringResource(R.string.preset_apply), fontWeight = FontWeight.SemiBold)
    }
    if (linkedPreset != null) {
      Spacer(modifier = Modifier.height(4.dp))
      TextButton(
        onClick = onDetachPreset,
        modifier = Modifier.fillMaxWidth(),
      ) {
        Text(stringResource(R.string.preset_detach))
      }
    }
  }
}

@Composable
private fun DeviceEditorActionBar(
  busy: Boolean,
  status: String?,
  compact: Boolean,
  onPairManual: () -> Unit,
  onSave: () -> Unit,
  onSaveAndConnect: () -> Unit,
  modifier: Modifier = Modifier,
) {
  // Flat bottom-chrome content (parent Surface owns background / divider).
  Column(
    modifier = modifier.fillMaxWidth(),
    verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
      if (busy) {
        AppLoadingDialog(message = status)
      } else {
        status?.let {
          Text(
            it,
            color = AccentBlue,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(horizontal = 4.dp),
          )
        }
      }

      if (compact) {
        Column(
          modifier = Modifier.fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          OutlinedButton(
            onClick = onPairManual,
            enabled = !busy,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
          ) { Text(stringResource(R.string.device_editor_action_pair)) }

          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            Button(
              onClick = onSave,
              enabled = !busy,
              modifier = Modifier
                .weight(1f)
                .height(48.dp),
              shape = RoundedCornerShape(12.dp),
              colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
            ) {
              Text(stringResource(R.string.device_editor_action_save), fontWeight = FontWeight.SemiBold)
            }
            Button(
              onClick = onSaveAndConnect,
              enabled = !busy,
              modifier = Modifier
                .weight(1f)
                .height(48.dp),
              shape = RoundedCornerShape(12.dp),
              colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
              ),
            ) {
              Text(
                stringResource(R.string.device_editor_action_save_connect),
                fontWeight = FontWeight.SemiBold,
              )
            }
          }
        }
      } else {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          OutlinedButton(
            onClick = onPairManual,
            enabled = !busy,
            modifier = Modifier.height(44.dp),
            shape = RoundedCornerShape(12.dp),
          ) { Text(stringResource(R.string.device_editor_action_pair)) }
          Spacer(modifier = Modifier.weight(1f))
          Button(
            onClick = onSave,
            enabled = !busy,
            modifier = Modifier.height(44.dp),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
          ) {
            Text(stringResource(R.string.device_editor_action_save), fontWeight = FontWeight.SemiBold)
          }
          Button(
            onClick = onSaveAndConnect,
            enabled = !busy,
            modifier = Modifier.height(44.dp),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
              containerColor = MaterialTheme.colorScheme.primary,
            ),
          ) {
            Text(
              stringResource(R.string.device_editor_action_save_connect),
              fontWeight = FontWeight.SemiBold,
            )
          }
        }
      }
  }
}

@Composable
fun ApplyPresetDialog(
  onDismiss: () -> Unit,
  onPick: (ConnectionPreset) -> Unit,
) {
  val presets = remember { PresetStore.all() }
  AlertDialog(
    onDismissRequest = onDismiss,
    title = {
      Text(stringResource(R.string.preset_apply), fontWeight = FontWeight.SemiBold)
    },
    text = {
      Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
          stringResource(R.string.preset_picker_hint),
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(4.dp))
        presets.forEach { preset ->
          TextButton(
            onClick = { onPick(preset) },
            modifier = Modifier.fillMaxWidth(),
          ) {
            Column(
              modifier = Modifier.fillMaxWidth(),
              horizontalAlignment = Alignment.Start,
            ) {
              Text(preset.name, fontWeight = FontWeight.Medium)
              Text(
                buildString {
                  append(if (preset.videoSource == "camera") "camera" else "display")
                  append(" · ")
                  append(preset.maxSize)
                  append("px · ")
                  append(preset.maxFps)
                  append("fps")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
        }
      }
    },
    confirmButton = {
      TextButton(onClick = onDismiss) {
        Text(stringResource(android.R.string.cancel))
      }
    },
  )
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
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
      Spacer(modifier = Modifier.height(12.dp))
      content()
    }
  }
}

@Composable
private fun IpSearchDialog(
  onDismiss: () -> Unit,
  onPick: (LanDeviceScanner.Result) -> Unit,
) {
  val context = LocalContext.current
  var scanning by remember { mutableStateOf(true) }
  var results by remember { mutableStateOf<List<LanDeviceScanner.Result>>(emptyList()) }
  var error by remember { mutableStateOf<String?>(null) }

  LaunchedEffect(Unit) {
    scanning = true
    error = null
    try {
      results = withContext(Dispatchers.IO) { LanDeviceScanner.scan(context, 5000) }
      if (results.isEmpty()) error = "未找到设备。请确认被控机已开无线调试，且同一 Wi‑Fi（勿开 AP 隔离）。"
    } catch (e: Exception) {
      error = e.message ?: "扫描失败"
    } finally {
      scanning = false
    }
  }

  Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.92f)
        .clip(RoundedCornerShape(24.dp)),
      color = MaterialTheme.colorScheme.surface,
    ) {
      Column(modifier = Modifier.padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Text("搜索局域网设备", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "关闭")
          }
        }
        Text(
          "优先发现无线调试 mDNS，并探测 5555 端口",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(16.dp))
        when {
          scanning -> {
            AppInlineLoading(message = "正在扫描…")
          }
          error != null && results.isEmpty() -> {
            Text(error!!, color = MaterialTheme.colorScheme.error)
          }
          else -> {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
              results.forEach { item ->
                Row(
                  modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
                    .clickable { onPick(item) }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                  verticalAlignment = Alignment.CenterVertically,
                ) {
                  Column(modifier = Modifier.weight(1f)) {
                    Text(item.host, fontWeight = FontWeight.SemiBold)
                    Text(
                      item.label,
                      style = MaterialTheme.typography.bodySmall,
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                  }
                  Text("选用", color = AccentBlue, fontWeight = FontWeight.SemiBold)
                }
              }
            }
          }
        }
        Spacer(modifier = Modifier.height(8.dp))
        TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
          Text("关闭")
        }
      }
    }
  }
}

@Composable
private fun QrPairDialog(
  onDismiss: () -> Unit,
  onPaired: (host: String, connectPort: Int) -> Unit,
) {
  val context = LocalContext.current
  val credentials = remember { AdbQrPairing.generate() }
  val qrBitmap: Bitmap = remember(credentials.payload) {
    AdbQrPairing.encodeBitmap(credentials.payload, 840)
  }
  var status by remember { mutableStateOf("等待被控机扫码…") }
  var pairing by remember { mutableStateOf(true) }
  var job by remember { mutableStateOf<Job?>(null) }
  val scope = rememberCoroutineScope()

  DisposableEffect(credentials.serviceName) {
    job = scope.launch {
      pairing = true
      status = "等待被控机扫码…"
      try {
        val result = withContext(Dispatchers.IO) {
          // Poll until timeout — phone may need time after scan
          var lastError: Exception? = null
          val deadline = System.currentTimeMillis() + 90_000
          while (isActive && System.currentTimeMillis() < deadline) {
            try {
              return@withContext AdbTools.pairWithQrCredentials(
                context,
                credentials.serviceName,
                credentials.password,
                8_000,
              )
            } catch (e: Exception) {
              lastError = e
              status = "等待扫码中…（保持二维码页开启）"
            }
          }
          throw lastError ?: Exception("配对超时")
        }
        val host = result[0]
        val port = result[1].toIntOrNull() ?: 0
        status = "配对成功"
        pairing = false
        onPaired(host, port)
      } catch (e: Exception) {
        if (isActive) {
          status = e.message ?: "配对失败"
          pairing = false
          AppErrorLog.e("qr-pair", e.message ?: "二维码配对失败", e)
        }
      }
    }
    onDispose { job?.cancel() }
  }

  Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.92f)
        .clip(RoundedCornerShape(24.dp)),
      color = MaterialTheme.colorScheme.surface,
    ) {
      Column(
        modifier = Modifier.padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
          Text(
            "二维码配对",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.weight(1f),
          )
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "关闭")
          }
        }
        Text(
          "被控机：开发者选项 → 无线调试 →「使用二维码配对」扫描下方二维码",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Box(
          modifier = Modifier
            .clip(RoundedCornerShape(18.dp))
            .background(androidx.compose.ui.graphics.Color.White)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f), RoundedCornerShape(18.dp))
            .padding(14.dp),
        ) {
          Image(
            bitmap = qrBitmap.asImageBitmap(),
            contentDescription = "配对二维码",
            modifier = Modifier.size(240.dp),
          )
        }
        Spacer(modifier = Modifier.height(14.dp))
        if (pairing) {
          AppLoadingIndicator(size = 24.dp)
          Spacer(modifier = Modifier.height(8.dp))
        }
        Text(status, style = MaterialTheme.typography.bodyMedium, color = AccentBlue)
        Spacer(modifier = Modifier.height(8.dp))
        TextButton(onClick = onDismiss) { Text("取消") }
      }
    }
  }
}
