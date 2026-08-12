package com.shiyunjin.easycontrolnext.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.entity.ConnectionPreset
import com.shiyunjin.easycontrolnext.app.entity.Device
import com.shiyunjin.easycontrolnext.app.helper.PresetStore
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import java.util.UUID

data class DeviceFormState(
  val name: String = "被控手机",
  val address: String = "",
  val connectPort: String = "",
  val pairPort: String = "",
  val pairCode: String = "",
  val startApp: String = "",
  /** Empty = custom / detached from any preset. */
  val presetId: String = "",
  val videoSource: String = "display",
  val cameraFacing: String = "back",
  val virtualWidth: String = "",
  val virtualHeight: String = "",
  val virtualDpi: String = "",
  val serverPort: String = "25166",
  val customResolutionOnConnect: Boolean = false,
  val customResolutionWidth: String = "1080",
  val customResolutionHeight: String = "2400",
  val wakeOnConnect: Boolean = true,
  val lightOffOnConnect: Boolean = false,
  val showNavBarOnConnect: Boolean = true,
  val changeToFullOnConnect: Boolean = false,
  val listenClip: Boolean = true,
  val keepWakeOnRunning: Boolean = true,
  val changeResolutionOnRunning: Boolean = false,
  val smallToMiniOnRunning: Boolean = false,
  val fullToMiniOnRunning: Boolean = true,
  val miniTimeoutOnRunning: Boolean = false,
  val lockOnClose: Boolean = true,
  val lightOnClose: Boolean = false,
  val reconnectOnClose: Boolean = false,
  val isAudio: Boolean = false,
  val maxSize: String = "1600",
  val maxFps: String = "60",
  val maxVideoBit: String = "4",
  val useH265: Boolean = true,
  /** auto | main | main10 — default main (8-bit). */
  val hevcProfile: String = "main",
  val connectOnStart: Boolean = false,
) {
  val isPresetLinked: Boolean get() = presetId.isNotBlank()

  /** Apply stream / session fields from a preset and link [presetId]. Identity fields unchanged. */
  fun applyPreset(preset: ConnectionPreset): DeviceFormState = copy(
    presetId = preset.id,
    videoSource = if (preset.videoSource == "camera") "camera" else "display",
    cameraFacing = if (preset.cameraFacing == "front") "front" else "back",
    startApp = if (preset.videoSource == "camera") "" else preset.startApp,
    virtualWidth = if (preset.virtualWidth > 0) preset.virtualWidth.toString() else "",
    virtualHeight = if (preset.virtualHeight > 0) preset.virtualHeight.toString() else "",
    virtualDpi = if (preset.virtualDpi > 0) preset.virtualDpi.toString() else "",
    isAudio = preset.isAudio,
    listenClip = preset.listenClip,
    maxSize = preset.maxSize.toString(),
    maxFps = preset.maxFps.toString(),
    maxVideoBit = preset.maxVideoBit.toString(),
    useH265 = preset.useH265,
    hevcProfile = ConnectionPreset.normalizeHevcProfile(preset.hevcProfile),
    keepWakeOnRunning = preset.keepWakeOnRunning,
    changeToFullOnConnect = preset.changeToFullOnConnect,
    wakeOnConnect = preset.wakeOnConnect,
    lightOffOnConnect = preset.lightOffOnConnect,
    showNavBarOnConnect = preset.showNavBarOnConnect,
  )

  /**
   * If [next] changes any preset-owned stream field while linked, clear [presetId] (detach).
   * Identity / unrelated fields do not detach.
   */
  fun mergeStateDetachingPreset(next: DeviceFormState): DeviceFormState {
    if (presetId.isBlank()) return next
    return if (presetOwnedFieldsEqual(next)) next.copy(presetId = presetId)
    else next.copy(presetId = "")
  }

  private fun presetOwnedFieldsEqual(other: DeviceFormState): Boolean =
    videoSource == other.videoSource &&
      cameraFacing == other.cameraFacing &&
      startApp == other.startApp &&
      virtualWidth == other.virtualWidth &&
      virtualHeight == other.virtualHeight &&
      virtualDpi == other.virtualDpi &&
      isAudio == other.isAudio &&
      listenClip == other.listenClip &&
      maxSize == other.maxSize &&
      maxFps == other.maxFps &&
      maxVideoBit == other.maxVideoBit &&
      useH265 == other.useH265 &&
      ConnectionPreset.normalizeHevcProfile(hevcProfile) ==
        ConnectionPreset.normalizeHevcProfile(other.hevcProfile) &&
      keepWakeOnRunning == other.keepWakeOnRunning &&
      changeToFullOnConnect == other.changeToFullOnConnect &&
      wakeOnConnect == other.wakeOnConnect &&
      lightOffOnConnect == other.lightOffOnConnect &&
      showNavBarOnConnect == other.showNavBarOnConnect

  fun toPreset(id: String, name: String, builtInKey: String?): ConnectionPreset = ConnectionPreset(
    id = id,
    name = name,
    builtInKey = builtInKey,
    videoSource = if (videoSource == "camera") "camera" else "display",
    cameraFacing = if (cameraFacing == "front") "front" else "back",
    startApp = if (videoSource == "camera") "" else startApp.trim(),
    virtualWidth = virtualWidth.trim().toIntOrNull() ?: 0,
    virtualHeight = virtualHeight.trim().toIntOrNull() ?: 0,
    virtualDpi = virtualDpi.trim().toIntOrNull() ?: 0,
    isAudio = isAudio,
    listenClip = listenClip,
    maxSize = maxSize.trim().toIntOrNull() ?: 1600,
    maxFps = maxFps.trim().toIntOrNull() ?: 60,
    maxVideoBit = maxVideoBit.trim().toIntOrNull() ?: 4,
    useH265 = useH265,
    hevcProfile = ConnectionPreset.normalizeHevcProfile(hevcProfile),
    keepWakeOnRunning = keepWakeOnRunning,
    changeToFullOnConnect = changeToFullOnConnect,
    wakeOnConnect = wakeOnConnect,
    lightOffOnConnect = lightOffOnConnect,
    showNavBarOnConnect = showNavBarOnConnect,
  )

  fun toDevice(existing: Device?): Device {
    val device = existing ?: Device(UUID.randomUUID().toString(), Device.TYPE_NETWORK)
    device.name = name.trim().ifEmpty { "被控手机" }
    device.address = address.trim()
    device.adbPort = connectPort.trim().toIntOrNull() ?: 0
    device.pairPort = pairPort.trim().toIntOrNull() ?: 0
    device.pairKey = pairCode
    device.startApp = if (videoSource == "camera") "" else startApp.trim()
    device.videoSource = if (videoSource == "camera") "camera" else "display"
    device.cameraFacing = if (cameraFacing == "front") "front" else "back"
    device.virtualWidth = virtualWidth.trim().toIntOrNull() ?: 0
    device.virtualHeight = virtualHeight.trim().toIntOrNull() ?: 0
    device.virtualDpi = virtualDpi.trim().toIntOrNull() ?: 0
    device.serverPort = serverPort.trim().toIntOrNull() ?: 25166
    device.customResolutionOnConnect = customResolutionOnConnect
    device.customResolutionWidth = customResolutionWidth.trim().toIntOrNull() ?: 1080
    device.customResolutionHeight = customResolutionHeight.trim().toIntOrNull() ?: 2400
    device.wakeOnConnect = wakeOnConnect
    device.lightOffOnConnect = lightOffOnConnect
    device.showNavBarOnConnect = showNavBarOnConnect
    device.changeToFullOnConnect = changeToFullOnConnect
    device.listenClip = listenClip
    device.keepWakeOnRunning = keepWakeOnRunning
    device.changeResolutionOnRunning = changeResolutionOnRunning
    device.smallToMiniOnRunning = smallToMiniOnRunning
    device.fullToMiniOnRunning = fullToMiniOnRunning
    device.miniTimeoutOnRunning = miniTimeoutOnRunning
    device.lockOnClose = lockOnClose
    device.lightOnClose = lightOnClose
    device.reconnectOnClose = reconnectOnClose
    device.isAudio = isAudio
    device.maxSize = maxSize.trim().toIntOrNull() ?: 1600
    device.maxFps = maxFps.trim().toIntOrNull() ?: 60
    device.maxVideoBit = maxVideoBit.trim().toIntOrNull() ?: 4
    device.useH265 = useH265
    device.hevcProfile = ConnectionPreset.normalizeHevcProfile(hevcProfile)
    device.connectOnStart = connectOnStart
    device.presetId = presetId
    return device
  }

  companion object {
    fun fromPreset(preset: ConnectionPreset): DeviceFormState =
      DeviceFormState().applyPreset(preset)

    fun from(device: Device?): DeviceFormState {
      if (device == null) {
        return fromPreset(PresetStore.getDefault())
      }
      val linkedId = device.presetId ?: ""
      // Stale link (preset deleted): keep fields, drop id
      val resolvedId = if (linkedId.isNotBlank() && PresetStore.get(linkedId) == null) "" else linkedId
      return DeviceFormState(
        name = device.name,
        address = device.address,
        connectPort = if (device.adbPort > 0) device.adbPort.toString() else "",
        pairPort = if (device.pairPort > 0) device.pairPort.toString() else "",
        pairCode = device.pairKey ?: "",
        startApp = device.startApp ?: "",
        presetId = resolvedId,
        videoSource = device.videoSource ?: "display",
        cameraFacing = device.cameraFacing ?: "back",
        virtualWidth = if (device.virtualWidth > 0) device.virtualWidth.toString() else "",
        virtualHeight = if (device.virtualHeight > 0) device.virtualHeight.toString() else "",
        virtualDpi = if (device.virtualDpi > 0) device.virtualDpi.toString() else "",
        serverPort = device.serverPort.toString(),
        customResolutionOnConnect = device.customResolutionOnConnect,
        customResolutionWidth = device.customResolutionWidth.toString(),
        customResolutionHeight = device.customResolutionHeight.toString(),
        wakeOnConnect = device.wakeOnConnect,
        lightOffOnConnect = device.lightOffOnConnect,
        showNavBarOnConnect = device.showNavBarOnConnect,
        changeToFullOnConnect = device.changeToFullOnConnect,
        listenClip = device.listenClip,
        keepWakeOnRunning = device.keepWakeOnRunning,
        changeResolutionOnRunning = device.changeResolutionOnRunning,
        smallToMiniOnRunning = device.smallToMiniOnRunning,
        fullToMiniOnRunning = device.fullToMiniOnRunning,
        miniTimeoutOnRunning = device.miniTimeoutOnRunning,
        lockOnClose = device.lockOnClose,
        lightOnClose = device.lightOnClose,
        reconnectOnClose = device.reconnectOnClose,
        isAudio = device.isAudio,
        maxSize = device.maxSize.toString(),
        maxFps = device.maxFps.toString(),
        maxVideoBit = device.maxVideoBit.toString(),
        useH265 = device.useH265,
        hevcProfile = ConnectionPreset.normalizeHevcProfile(device.hevcProfile),
        connectOnStart = device.connectOnStart,
      )
    }
  }
}

@Composable
fun ConfigSwitch(
  title: String,
  detail: String,
  checked: Boolean,
  onCheckedChange: (Boolean) -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .padding(vertical = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(modifier = Modifier.weight(1f)) {
      Text(title, fontWeight = FontWeight.Medium)
      Text(
        detail,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    Switch(
      checked = checked,
      onCheckedChange = onCheckedChange,
      colors = SwitchDefaults.colors(checkedTrackColor = AccentBlue),
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigSpinner(
  title: String,
  detail: String,
  value: String,
  options: List<String>,
  onValueChange: (String) -> Unit,
) {
  var expanded by remember { mutableStateOf(false) }
  val colors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    focusedLabelColor = AccentBlue,
    cursorColor = AccentBlue,
  )
  Column(modifier = Modifier.padding(vertical = 6.dp)) {
    Text(title, fontWeight = FontWeight.Medium)
    Text(
      detail,
      style = MaterialTheme.typography.bodySmall,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(6.dp))
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
      OutlinedTextField(
        value = value,
        onValueChange = {},
        readOnly = true,
        modifier = Modifier
          .menuAnchor()
          .fillMaxWidth(),
        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
        shape = RoundedCornerShape(14.dp),
        colors = colors,
      )
      ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        options.forEach { option ->
          DropdownMenuItem(
            text = { Text(option) },
            onClick = {
              onValueChange(option)
              expanded = false
            },
          )
        }
      }
    }
  }
}

@Composable
fun ExpandableSection(
  title: String,
  initiallyExpanded: Boolean = false,
  content: @Composable () -> Unit,
) {
  var expanded by remember { mutableStateOf(initiallyExpanded) }
  Column(modifier = Modifier.fillMaxWidth()) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .clickable { expanded = !expanded }
        .padding(vertical = 4.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.weight(1f),
      )
      Icon(
        if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    AnimatedVisibility(visible = expanded) {
      Column { content() }
    }
  }
}

@Composable
fun DeviceAdvancedConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  ExpandableSection(title = stringResource(R.string.device_editor_section_on_connect)) {
    DeviceOnConnectConfig(state = state, onStateChange = onStateChange)
  }

  Spacer(modifier = Modifier.height(8.dp))
  ExpandableSection(title = stringResource(R.string.device_editor_section_on_running)) {
    DeviceOnRunningConfig(state = state, onStateChange = onStateChange)
  }

  Spacer(modifier = Modifier.height(8.dp))
  ExpandableSection(title = stringResource(R.string.device_editor_section_on_close)) {
    DeviceOnCloseConfig(state = state, onStateChange = onStateChange)
  }

  Spacer(modifier = Modifier.height(8.dp))
  ExpandableSection(
    title = stringResource(R.string.device_editor_section_video),
    initiallyExpanded = true,
  ) {
    DeviceVideoParamsConfig(state = state, onStateChange = onStateChange)
  }
}

@Composable
fun DeviceOnConnectConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  val fieldColors = rememberDeviceFieldColors()
  Column(modifier = Modifier.fillMaxWidth()) {
    ConfigSwitch("连接时修改分辨率", "手动设置分辨率；开启后自适应分辨率失效", state.customResolutionOnConnect) {
      onStateChange(state.copy(customResolutionOnConnect = it))
    }
    if (state.customResolutionOnConnect) {
      Row(modifier = Modifier.fillMaxWidth()) {
        OutlinedTextField(
          value = state.customResolutionWidth,
          onValueChange = { onStateChange(state.copy(customResolutionWidth = it.filter(Char::isDigit).take(5))) },
          modifier = Modifier.weight(1f),
          label = { Text("宽") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
          shape = RoundedCornerShape(14.dp),
          colors = fieldColors,
        )
        Spacer(modifier = Modifier.width(8.dp))
        OutlinedTextField(
          value = state.customResolutionHeight,
          onValueChange = { onStateChange(state.copy(customResolutionHeight = it.filter(Char::isDigit).take(5))) },
          modifier = Modifier.weight(1f),
          label = { Text("高") },
          singleLine = true,
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
          shape = RoundedCornerShape(14.dp),
          colors = fieldColors,
        )
      }
    }
    ConfigSwitch("连接时自动唤醒", "连接成功后唤醒被控端", state.wakeOnConnect) {
      onStateChange(state.copy(wakeOnConnect = it))
    }
    ConfigSwitch("连接时关闭背光", "连接后关闭被控端屏幕", state.lightOffOnConnect) {
      onStateChange(state.copy(lightOffOnConnect = it))
    }
    ConfigSwitch("显示导航栏", "小窗/全屏默认显示导航栏", state.showNavBarOnConnect) {
      onStateChange(state.copy(showNavBarOnConnect = it))
    }
    ConfigSwitch("默认全屏启动", "连接成功后直接全屏", state.changeToFullOnConnect) {
      onStateChange(state.copy(changeToFullOnConnect = it))
    }
  }
}

@Composable
fun DeviceOnRunningConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    ConfigSwitch("监听剪切板", "运行时同步剪切板", state.listenClip) {
      onStateChange(state.copy(listenClip = it))
    }
    ConfigSwitch("被控端保持唤醒", "运行中不锁定（修改锁定时间）", state.keepWakeOnRunning) {
      onStateChange(state.copy(keepWakeOnRunning = it))
    }
    ConfigSwitch("自适应分辨率", "按窗口改分辨率，可能需手动恢复", state.changeResolutionOnRunning) {
      onStateChange(state.copy(changeResolutionOnRunning = it))
    }
    ConfigSwitch("小窗自动挂起", "点小窗外自动最小化", state.smallToMiniOnRunning) {
      onStateChange(state.copy(smallToMiniOnRunning = it))
    }
    ConfigSwitch("全屏挂起为 Mini", "退出全屏时挂起为 Mini 栏", state.fullToMiniOnRunning) {
      onStateChange(state.copy(fullToMiniOnRunning = it))
    }
    ConfigSwitch("挂起后自动恢复", "自动挂起 5 秒无操作后恢复", state.miniTimeoutOnRunning) {
      onStateChange(state.copy(miniTimeoutOnRunning = it))
    }
  }
}

@Composable
fun DeviceOnCloseConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  Column(modifier = Modifier.fillMaxWidth()) {
    ConfigSwitch("断开时锁定", "断开时锁定被控端（会覆盖恢复背光）", state.lockOnClose) {
      onStateChange(state.copy(lockOnClose = it))
    }
    ConfigSwitch("断开时恢复背光", "断开时恢复被控端背光", state.lightOnClose) {
      onStateChange(state.copy(lightOnClose = it))
    }
    ConfigSwitch("自动重连", "意外断开时自动重连", state.reconnectOnClose) {
      onStateChange(state.copy(reconnectOnClose = it))
    }
  }
}

@Composable
fun DeviceVideoParamsConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  val fieldColors = rememberDeviceFieldColors()
  Column(modifier = Modifier.fillMaxWidth()) {
    VideoAndVirtualDisplaySection(state = state, onStateChange = onStateChange, fieldColors = fieldColors)
    Spacer(modifier = Modifier.height(8.dp))
    OutlinedTextField(
      value = state.serverPort,
      onValueChange = { onStateChange(state.copy(serverPort = it.filter(Char::isDigit).take(5))) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text("服务端口") },
      singleLine = true,
      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
    ConfigSwitch("音频", "需要被控端 Android 12+", state.isAudio) {
      onStateChange(state.copy(isAudio = it))
    }
    ConfigSpinner("最大大小", "画面最大边长", state.maxSize, listOf("2560", "1920", "1600", "1280", "1024", "800")) {
      onStateChange(state.copy(maxSize = it))
    }
    ConfigSpinner("最大帧率", "越低越省带宽", state.maxFps, listOf("90", "60", "40", "30", "20", "10")) {
      onStateChange(state.copy(maxFps = it))
    }
    ConfigSpinner("最大码率 (Mbps)", "建议 4；过高会增延迟", state.maxVideoBit, listOf("12", "8", "4", "2", "1")) {
      onStateChange(state.copy(maxVideoBit = it))
    }
    ConfigSwitch(
      title = stringResource(R.string.device_use_h265),
      detail = stringResource(R.string.device_use_h265_detail),
      checked = state.useH265,
    ) {
      onStateChange(state.copy(useH265 = it))
    }
    AnimatedVisibility(visible = state.useH265) {
      HevcProfileSpinner(state = state, onStateChange = onStateChange)
    }
    ConfigSwitch("软件启动时打开", "启动 App 时自动连接", state.connectOnStart) {
      onStateChange(state.copy(connectOnStart = it))
    }
  }
}

@Composable
private fun rememberDeviceFieldColors() = OutlinedTextFieldDefaults.colors(
  focusedBorderColor = AccentBlue,
  focusedLabelColor = AccentBlue,
  cursorColor = AccentBlue,
)

@Composable
fun HevcProfileSpinner(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
) {
  val labelAuto = stringResource(R.string.device_hevc_profile_auto)
  val labelMain = stringResource(R.string.device_hevc_profile_main)
  val labelMain10 = stringResource(R.string.device_hevc_profile_main10)
  val display = when (ConnectionPreset.normalizeHevcProfile(state.hevcProfile)) {
    "auto" -> labelAuto
    "main10" -> labelMain10
    else -> labelMain
  }
  ConfigSpinner(
    title = stringResource(R.string.device_hevc_profile),
    detail = stringResource(R.string.device_hevc_profile_detail),
    value = display,
    options = listOf(labelAuto, labelMain, labelMain10),
  ) { selected ->
    val value = when (selected) {
      labelAuto -> "auto"
      labelMain10 -> "main10"
      else -> "main"
    }
    onStateChange(state.copy(hevcProfile = value))
  }
}

@Composable
private fun VideoAndVirtualDisplaySection(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
  fieldColors: androidx.compose.material3.TextFieldColors,
) {
  var showAppPicker by remember { mutableStateOf(false) }
  var showManualPackage by remember { mutableStateOf(state.startApp.isNotBlank()) }
  var pickerError by remember { mutableStateOf<String?>(null) }

  val videoSourceDisplay = stringResource(R.string.device_video_source_display)
  val videoSourceCamera = stringResource(R.string.device_video_source_camera)
  val facingBack = stringResource(R.string.device_camera_facing_back)
  val facingFront = stringResource(R.string.device_camera_facing_front)

  ConfigSpinner(
    title = stringResource(R.string.device_video_source),
    detail = "屏幕镜像，或相机画面（Android 12+）",
    value = if (state.videoSource == "camera") videoSourceCamera else videoSourceDisplay,
    options = listOf(videoSourceDisplay, videoSourceCamera),
  ) { selected ->
    onStateChange(state.copy(videoSource = if (selected == videoSourceCamera) "camera" else "display"))
  }

  AnimatedVisibility(visible = state.videoSource == "camera") {
    ConfigSpinner(
      title = stringResource(R.string.device_camera_facing),
      detail = "固定前后置，无手电筒",
      value = if (state.cameraFacing == "front") facingFront else facingBack,
      options = listOf(facingBack, facingFront),
    ) { selected ->
      onStateChange(state.copy(cameraFacing = if (selected == facingFront) "front" else "back"))
    }
  }

  AnimatedVisibility(visible = state.videoSource != "camera") {
    Column {
      Text(
        stringResource(R.string.device_start_app),
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(top = 8.dp),
      )
      Text(
        stringResource(R.string.device_start_app_hint),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Spacer(modifier = Modifier.height(8.dp))
      if (state.startApp.isNotBlank()) {
        Text(
          "已选：${state.startApp}",
          style = MaterialTheme.typography.bodyMedium,
          fontWeight = FontWeight.Medium,
        )
        Spacer(modifier = Modifier.height(6.dp))
      }
      Row(modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(
          onClick = {
            val port = state.connectPort.trim().toIntOrNull() ?: 0
            if (state.address.isBlank() || port <= 0) {
              pickerError = "先填写 IP 与连接端口并确保已配对"
            } else {
              pickerError = null
              showAppPicker = true
            }
          },
          modifier = Modifier.weight(1f),
          shape = RoundedCornerShape(14.dp),
        ) {
          Text(stringResource(R.string.device_pick_app))
        }
        Spacer(modifier = Modifier.width(8.dp))
        OutlinedButton(
          onClick = { onStateChange(state.copy(startApp = "")) },
          shape = RoundedCornerShape(14.dp),
        ) {
          Text("整屏")
        }
      }
      pickerError?.let {
        Text(
          it,
          color = MaterialTheme.colorScheme.error,
          style = MaterialTheme.typography.bodySmall,
          modifier = Modifier.padding(top = 4.dp),
        )
      }
      Text(
        stringResource(R.string.device_pick_app_manual),
        color = AccentBlue,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier
          .padding(top = 8.dp)
          .clickable { showManualPackage = !showManualPackage },
      )
      AnimatedVisibility(visible = showManualPackage) {
        OutlinedTextField(
          value = state.startApp,
          onValueChange = { onStateChange(state.copy(startApp = it.trim())) },
          modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp),
          label = { Text("包名（如 com.example.app）") },
          singleLine = true,
          shape = RoundedCornerShape(14.dp),
          colors = fieldColors,
        )
      }

      AnimatedVisibility(visible = state.startApp.isNotBlank()) {
        Column {
          Spacer(modifier = Modifier.height(8.dp))
          Text(
            stringResource(R.string.device_virtual_size),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
          Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
              value = state.virtualWidth,
              onValueChange = { onStateChange(state.copy(virtualWidth = it.filter(Char::isDigit).take(5))) },
              modifier = Modifier.weight(1f),
              label = { Text("宽(0默认)") },
              singleLine = true,
              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
              shape = RoundedCornerShape(14.dp),
              colors = fieldColors,
            )
            Spacer(modifier = Modifier.width(8.dp))
            OutlinedTextField(
              value = state.virtualHeight,
              onValueChange = { onStateChange(state.copy(virtualHeight = it.filter(Char::isDigit).take(5))) },
              modifier = Modifier.weight(1f),
              label = { Text("高(0默认)") },
              singleLine = true,
              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
              shape = RoundedCornerShape(14.dp),
              colors = fieldColors,
            )
          }
          OutlinedTextField(
            value = state.virtualDpi,
            onValueChange = { onStateChange(state.copy(virtualDpi = it.filter(Char::isDigit).take(4))) },
            modifier = Modifier
              .fillMaxWidth()
              .padding(top = 6.dp),
            label = { Text(stringResource(R.string.device_virtual_dpi)) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            shape = RoundedCornerShape(14.dp),
            colors = fieldColors,
          )
        }
      }
    }
  }

  if (showAppPicker) {
    val probe = Device("probe", Device.TYPE_NETWORK).apply {
      address = state.address.trim()
      adbPort = state.connectPort.trim().toIntOrNull() ?: 0
      pairPort = state.pairPort.trim().toIntOrNull() ?: 0
      pairKey = state.pairCode
    }
    AppPickerDialog(
      device = probe,
      onDismiss = { showAppPicker = false },
      onPicked = { pkg ->
        onStateChange(state.copy(startApp = pkg))
        showManualPackage = false
        pickerError = null
      },
    )
  }
}
