package com.shiyunjin.easycontrolnext.app.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.window.core.layout.WindowSizeClass
import com.shiyunjin.easycontrolnext.app.MainActivity
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.client.Client
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.ConnectionPreset
import com.shiyunjin.easycontrolnext.app.entity.Device
import com.shiyunjin.easycontrolnext.app.helper.MyBroadcastReceiver
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import com.shiyunjin.easycontrolnext.app.ui.theme.EasyControlTheme

private const val ROUTE_HOME = "home"
private const val ROUTE_SETTINGS = "settings"
private const val ROUTE_PRESETS = "settings/presets"
private const val ROUTE_PRESET_EDIT = "settings/preset/{id}"
private const val ROUTE_ERROR_LOGS = "settings/error_logs"

@Composable
fun EasyControlApp(
  activity: Activity,
  settingsRequest: MainActivity.SettingsRequest? = null,
  onSettingsRequestConsumed: () -> Unit = {},
) {
  EasyControlTheme {
    val navController = rememberNavController()
    DisposableEffect(activity) {
      val receiver = MyBroadcastReceiver()
      receiver.register(activity)
      receiver.resetUSB()
      receiver.updateUSB()
      DeviceListStore.refresh()
      onDispose { receiver.unRegister(activity) }
    }

    // Deep links / legacy SetActivity → open Settings in-process (same window = no nav flicker).
    LaunchedEffect(settingsRequest?.nonce) {
      val req = settingsRequest ?: return@LaunchedEffect
      if (req.openErrorLog) {
        navController.navigate(ROUTE_SETTINGS) { launchSingleTop = true }
        navController.navigate(ROUTE_ERROR_LOGS) { launchSingleTop = true }
      } else {
        navController.navigate(ROUTE_SETTINGS) { launchSingleTop = true }
      }
      onSettingsRequestConsumed()
    }

    // Single NavHost + short fade/slide: nested Settings NavHost was double-animating and janky.
    NavHost(
      navController = navController,
      startDestination = ROUTE_HOME,
      enterTransition = NavTransitions.enterLambda,
      exitTransition = NavTransitions.exitLambda,
      popEnterTransition = NavTransitions.popEnterLambda,
      popExitTransition = NavTransitions.popExitLambda,
    ) {
      composable(ROUTE_HOME) {
        HomeScreen(
          onAdd = { navController.navigate("device/new") },
          onEdit = { id -> navController.navigate("device/$id") },
          onSettings = {
            navController.navigate(ROUTE_SETTINGS) {
              launchSingleTop = true
            }
          },
        )
      }
      composable(
        route = "device/{uuid}",
        arguments = listOf(navArgument("uuid") { type = NavType.StringType }),
      ) { entry ->
        val id = entry.arguments?.getString("uuid") ?: "new"
        DeviceEditorScreen(
          uuid = id,
          onBack = { navController.popBackStack() },
          onSaved = {
            DeviceListStore.refresh()
            navController.popBackStack()
          },
        )
      }
      composable(ROUTE_SETTINGS) {
        BackHandler { navController.popBackStack() }
        SettingsHomeScreen(
          onBack = { navController.popBackStack() },
          onOpenPresets = {
            navController.navigate(ROUTE_PRESETS) { launchSingleTop = true }
          },
          onOpenErrorLogs = {
            navController.navigate(ROUTE_ERROR_LOGS) { launchSingleTop = true }
          },
        )
      }
      composable(ROUTE_PRESETS) {
        BackHandler { navController.popBackStack() }
        PresetsListScreen(
          onBack = { navController.popBackStack() },
          onEdit = { id -> navController.navigate("settings/preset/$id") },
        )
      }
      composable(
        route = ROUTE_PRESET_EDIT,
        arguments = listOf(navArgument("id") { type = NavType.StringType }),
      ) { entry ->
        val id = entry.arguments?.getString("id") ?: "new"
        BackHandler { navController.popBackStack() }
        PresetEditorScreen(
          presetId = id,
          onBack = { navController.popBackStack() },
        )
      }
      composable(ROUTE_ERROR_LOGS) {
        BackHandler { navController.popBackStack() }
        ErrorLogScreen(onBack = { navController.popBackStack() })
      }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScreen(
  onAdd: () -> Unit,
  onEdit: (String) -> Unit,
  onSettings: () -> Unit,
) {
  val devices by DeviceListStore.devices.collectAsState()
  var menuDevice by remember { mutableStateOf<Device?>(null) }
  var appPickerDevice by remember { mutableStateOf<Device?>(null) }
  var cameraFacingDevice by remember { mutableStateOf<Device?>(null) }
  var presetPickerDevice by remember { mutableStateOf<Device?>(null) }
  var selectedUuid by remember { mutableStateOf<String?>(null) }
  val bg = MaterialTheme.colorScheme.background

  // Window-size driven: Medium/Expanded → list | detail; Compact → phone single column.
  val windowSizeClass = currentWindowAdaptiveInfo().windowSizeClass
  val useListDetail = windowSizeClass.isWidthAtLeastBreakpoint(
    WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND,
  )

  LaunchedEffect(devices, selectedUuid, useListDetail) {
    if (!useListDetail) return@LaunchedEffect
    if (selectedUuid != null && devices.none { it.uuid == selectedUuid }) {
      selectedUuid = devices.firstOrNull()?.uuid
    } else if (selectedUuid == null && devices.isNotEmpty()) {
      selectedUuid = devices.first().uuid
    }
  }

  val selectedDevice = devices.firstOrNull { it.uuid == selectedUuid }

  Scaffold(
    containerColor = bg,
    floatingActionButton = {
      // Scaffold already places the FAB above navigationBars; do not add navigationBarsPadding.
      FloatingActionButton(
        onClick = onAdd,
        containerColor = AccentBlue,
        contentColor = Color.White,
        elevation = FloatingActionButtonDefaults.elevation(6.dp),
        shape = CircleShape,
      ) {
        Icon(Icons.Default.Add, contentDescription = "添加设备")
      }
    },
  ) { padding ->
    // Scaffold contentWindowInsets already include status/nav bars — apply once via padding.
    Box(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .background(
          Brush.verticalGradient(
            listOf(
              MaterialTheme.colorScheme.background,
              MaterialTheme.colorScheme.background,
              MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
            ),
          ),
        ),
    ) {
      if (useListDetail) {
        Row(
          modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        ) {
          Column(
            modifier = Modifier
              .weight(0.42f)
              .fillMaxHeight()
              .widthIn(max = 420.dp),
          ) {
            HomeHeader(onSettings = onSettings)
            Spacer(modifier = Modifier.height(8.dp))
            HomeDeviceList(
              devices = devices,
              selectedUuid = selectedUuid,
              selectMode = true,
              onAdd = onAdd,
              onDeviceClick = { selectedUuid = it.uuid },
              onDeviceLongClick = { menuDevice = it },
            )
          }
          Spacer(modifier = Modifier.width(16.dp))
          HomeDetailPane(
            device = selectedDevice,
            modifier = Modifier
              .weight(0.58f)
              .fillMaxHeight()
              .widthIn(max = 560.dp),
            onConnect = { device -> Client.startDevice(device) },
            onEdit = { onEdit(it.uuid) },
            onDelete = {
              AppData.dbHelper.delete(it)
              DeviceListStore.refresh()
              if (selectedUuid == it.uuid) selectedUuid = null
            },
            onTempApp = { appPickerDevice = it },
            onTempCamera = { cameraFacingDevice = it },
            onApplyPreset = { presetPickerDevice = it },
            onAdd = onAdd,
          )
        }
      } else {
        Column(
          modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        ) {
          HomeHeader(onSettings = onSettings)
          Spacer(modifier = Modifier.height(8.dp))
          HomeDeviceList(
            devices = devices,
            selectedUuid = null,
            selectMode = false,
            onAdd = onAdd,
            onDeviceClick = { Client.startDevice(it) },
            onDeviceLongClick = { menuDevice = it },
          )
        }
      }
    }
  }

  menuDevice?.let { device ->
    ManageDeviceSheet(
      device = device,
      onDismiss = { menuDevice = null },
      onEdit = {
        menuDevice = null
        onEdit(device.uuid)
      },
      onDelete = {
        AppData.dbHelper.delete(device)
        DeviceListStore.refresh()
        if (selectedUuid == device.uuid) selectedUuid = null
        menuDevice = null
      },
      onTempApp = {
        menuDevice = null
        appPickerDevice = device
      },
      onTempCamera = {
        menuDevice = null
        cameraFacingDevice = device
      },
      onApplyPreset = {
        menuDevice = null
        presetPickerDevice = device
      },
    )
  }

  presetPickerDevice?.let { device ->
    ApplyPresetDialog(
      onDismiss = { presetPickerDevice = null },
      onPick = { preset ->
        presetPickerDevice = null
        startSessionWithPreset(device, preset)
      },
    )
  }

  appPickerDevice?.let { device ->
    AppPickerDialog(
      device = device,
      onDismiss = { appPickerDevice = null },
      onPicked = { pkg ->
        appPickerDevice = null
        startSessionOverride(device) { session ->
          session.videoSource = "display"
          session.startApp = pkg
        }
      },
    )
  }

  cameraFacingDevice?.let { device ->
    AlertDialog(
      onDismissRequest = { cameraFacingDevice = null },
      title = { Text(stringResource(R.string.manage_camera_facing_title), fontWeight = FontWeight.SemiBold) },
      text = {
        Text(
          stringResource(R.string.manage_temp_camera_detail),
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      },
      confirmButton = {
        TextButton(onClick = {
          val d = device
          cameraFacingDevice = null
          startSessionOverride(d) { session ->
            session.videoSource = "camera"
            session.cameraFacing = "back"
            session.startApp = ""
          }
        }) {
          Text(stringResource(R.string.device_camera_facing_back))
        }
      },
      dismissButton = {
        Row {
          TextButton(onClick = {
            val d = device
            cameraFacingDevice = null
            startSessionOverride(d) { session ->
              session.videoSource = "camera"
              session.cameraFacing = "front"
              session.startApp = ""
            }
          }) {
            Text(stringResource(R.string.device_camera_facing_front))
          }
          TextButton(onClick = { cameraFacingDevice = null }) {
            Text(stringResource(android.R.string.cancel))
          }
        }
      },
    )
  }
}

@Composable
private fun HomeHeader(onSettings: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      // Scaffold already insets for statusBars; modest extra top so title isn't cramped.
      .padding(top = 20.dp, bottom = 8.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Column(modifier = Modifier.weight(1f)) {
      Text(
        "EasyControl",
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold,
      )
      Spacer(modifier = Modifier.height(4.dp))
      Text(
        stringResource(R.string.home_subtitle),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    IconButton(
      onClick = onSettings,
      modifier = Modifier
        .size(44.dp)
        .clip(CircleShape)
        .background(MaterialTheme.colorScheme.surface)
        .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f), CircleShape),
    ) {
      Icon(
        Icons.Default.Settings,
        contentDescription = stringResource(R.string.main_menu_settings),
      )
    }
  }
}

@Composable
private fun HomeDeviceList(
  devices: List<Device>,
  selectedUuid: String?,
  selectMode: Boolean,
  onAdd: () -> Unit,
  onDeviceClick: (Device) -> Unit,
  onDeviceLongClick: (Device) -> Unit,
) {
  if (devices.isEmpty()) {
    EmptyDevicesState(
      modifier = Modifier
        .fillMaxSize()
        .padding(bottom = 88.dp),
      onAdd = onAdd,
    )
  } else {
    Text(
      stringResource(R.string.home_device_count, devices.size),
      style = MaterialTheme.typography.labelLarge,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
      modifier = Modifier.padding(bottom = 10.dp, top = 4.dp),
    )
    LazyColumn(
      modifier = Modifier.fillMaxSize(),
      contentPadding = PaddingValues(bottom = 108.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      items(devices, key = { it.uuid }) { device ->
        DeviceCard(
          device = device,
          selected = selectMode && device.uuid == selectedUuid,
          onClick = { onDeviceClick(device) },
          onLongClick = { onDeviceLongClick(device) },
        )
      }
    }
  }
}

@Composable
private fun HomeDetailPane(
  device: Device?,
  modifier: Modifier = Modifier,
  onConnect: (Device) -> Unit,
  onEdit: (Device) -> Unit,
  onDelete: (Device) -> Unit,
  onTempApp: (Device) -> Unit,
  onTempCamera: (Device) -> Unit,
  onApplyPreset: (Device) -> Unit,
  onAdd: () -> Unit,
) {
  Card(
    modifier = modifier.padding(top = 12.dp, bottom = 20.dp),
    shape = RoundedCornerShape(24.dp),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
  ) {
    if (device == null) {
      Column(
        modifier = Modifier
          .fillMaxSize()
          .padding(28.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        Icon(
          Icons.Default.Devices,
          contentDescription = null,
          tint = AccentBlue,
          modifier = Modifier.size(48.dp),
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
          stringResource(R.string.home_select_device_title),
          style = MaterialTheme.typography.titleLarge,
          fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
          stringResource(R.string.home_select_device_hint),
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(20.dp))
        TextButton(onClick = onAdd) {
          Text("添加设备", color = AccentBlue, fontWeight = FontWeight.SemiBold)
        }
      }
    } else {
      Column(
        modifier = Modifier
          .fillMaxSize()
          .verticalScroll(rememberScrollState())
          .padding(24.dp),
      ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Box(
            modifier = Modifier
              .size(56.dp)
              .clip(RoundedCornerShape(16.dp))
              .background(AccentBlue.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
          ) {
            Icon(
              imageVector = if (device.isNetworkDevice) Icons.Default.Wifi else Icons.Default.Usb,
              contentDescription = null,
              tint = AccentBlue,
            )
          }
          Spacer(modifier = Modifier.width(14.dp))
          Column(modifier = Modifier.weight(1f)) {
            Text(
              device.name,
              style = MaterialTheme.typography.headlineSmall,
              fontWeight = FontWeight.Bold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
              deviceAddressLabel(device),
              style = MaterialTheme.typography.bodyMedium,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }

        Spacer(modifier = Modifier.height(20.dp))
        Button(
          onClick = { onConnect(device) },
          modifier = Modifier.fillMaxWidth(),
          colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
          shape = RoundedCornerShape(14.dp),
        ) {
          Icon(Icons.Default.PlayArrow, contentDescription = null)
          Spacer(modifier = Modifier.width(8.dp))
          Text(stringResource(R.string.home_connect), fontWeight = FontWeight.SemiBold)
        }

        Spacer(modifier = Modifier.height(20.dp))
        Text(
          stringResource(R.string.manage_section_session),
          style = MaterialTheme.typography.labelLarge,
          color = AccentBlue,
          fontWeight = FontWeight.SemiBold,
        )
        Text(
          stringResource(R.string.manage_section_session_hint),
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          modifier = Modifier.padding(top = 2.dp, bottom = 8.dp),
        )
        ManageActionRow(
          icon = Icons.Default.Tune,
          title = stringResource(R.string.manage_apply_preset),
          detail = stringResource(R.string.manage_apply_preset_detail),
          onClick = { onApplyPreset(device) },
        )
        ManageActionRow(
          icon = Icons.Default.Apps,
          title = stringResource(R.string.manage_temp_app),
          detail = stringResource(R.string.manage_temp_app_detail),
          onClick = { onTempApp(device) },
        )
        ManageActionRow(
          icon = Icons.Default.CameraAlt,
          title = stringResource(R.string.manage_temp_camera),
          detail = stringResource(R.string.manage_temp_camera_detail),
          onClick = { onTempCamera(device) },
        )

        Spacer(modifier = Modifier.height(12.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
        Spacer(modifier = Modifier.height(12.dp))
        Text(
          stringResource(R.string.manage_section_device),
          style = MaterialTheme.typography.labelLarge,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          fontWeight = FontWeight.SemiBold,
          modifier = Modifier.padding(bottom = 8.dp),
        )
        ManageActionRow(
          icon = Icons.Default.Edit,
          title = stringResource(R.string.manage_edit),
          detail = null,
          onClick = { onEdit(device) },
        )
        ManageActionRow(
          icon = Icons.Default.Delete,
          title = stringResource(R.string.manage_delete),
          detail = null,
          onClick = { onDelete(device) },
          destructive = true,
        )
      }
    }
  }
}

private fun deviceAddressLabel(device: Device): String =
  if (device.isNetworkDevice) {
    val port = if (device.adbPort > 0) device.adbPort.toString() else "?"
    "${device.address}:$port"
  } else {
    "USB"
  }

/** Clone device for one connect session; does not persist overrides to DB. */
private fun startSessionOverride(device: Device, configure: (Device) -> Unit) {
  if (Client.getDevice(device.uuid) != null) {
    Client.sendAction(device.uuid, "close", null, 0)
  }
  val session = device.clone(device.uuid)
  session.sessionOnly = true
  // Avoid reconnecting forever with temporary overrides
  session.reconnectOnClose = false
  configure(session)
  Client.startDevice(session)
}

/** Session-only: apply preset stream options then connect (saved device & link unchanged). */
private fun startSessionWithPreset(device: Device, preset: ConnectionPreset) {
  startSessionOverride(device) { session ->
    preset.applyTo(session)
    // Session clone is not persisted; clear link marker so it cannot be mistaken for a save.
    session.presetId = ""
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ManageDeviceSheet(
  device: Device,
  onDismiss: () -> Unit,
  onEdit: () -> Unit,
  onDelete: () -> Unit,
  onTempApp: () -> Unit,
  onTempCamera: () -> Unit,
  onApplyPreset: () -> Unit,
) {
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  ModalBottomSheet(
    onDismissRequest = onDismiss,
    sheetState = sheetState,
    containerColor = MaterialTheme.colorScheme.surface,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      Text(device.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
      Spacer(modifier = Modifier.height(4.dp))
      Text(
        if (device.isNetworkDevice) {
          val port = if (device.adbPort > 0) device.adbPort.toString() else "?"
          "${device.address}:$port"
        } else {
          "USB 设备"
        },
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )

      Spacer(modifier = Modifier.height(20.dp))
      Text(
        stringResource(R.string.manage_section_session),
        style = MaterialTheme.typography.labelLarge,
        color = AccentBlue,
        fontWeight = FontWeight.SemiBold,
      )
      Text(
        stringResource(R.string.manage_section_session_hint),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 2.dp, bottom = 8.dp),
      )

      ManageActionRow(
        icon = Icons.Default.Tune,
        title = stringResource(R.string.manage_apply_preset),
        detail = stringResource(R.string.manage_apply_preset_detail),
        onClick = onApplyPreset,
      )
      ManageActionRow(
        icon = Icons.Default.Apps,
        title = stringResource(R.string.manage_temp_app),
        detail = stringResource(R.string.manage_temp_app_detail),
        onClick = onTempApp,
      )
      ManageActionRow(
        icon = Icons.Default.CameraAlt,
        title = stringResource(R.string.manage_temp_camera),
        detail = stringResource(R.string.manage_temp_camera_detail),
        onClick = onTempCamera,
      )

      Spacer(modifier = Modifier.height(12.dp))
      HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
      Spacer(modifier = Modifier.height(12.dp))

      Text(
        stringResource(R.string.manage_section_device),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(bottom = 8.dp),
      )
      ManageActionRow(
        icon = Icons.Default.Edit,
        title = stringResource(R.string.manage_edit),
        detail = null,
        onClick = onEdit,
      )
      ManageActionRow(
        icon = Icons.Default.Delete,
        title = stringResource(R.string.manage_delete),
        detail = null,
        onClick = onDelete,
        destructive = true,
      )
    }
  }
}

@Composable
private fun ManageActionRow(
  icon: ImageVector,
  title: String,
  detail: String?,
  onClick: () -> Unit,
  destructive: Boolean = false,
) {
  TextButton(
    onClick = onClick,
    modifier = Modifier.fillMaxWidth(),
    contentPadding = PaddingValues(horizontal = 4.dp, vertical = 10.dp),
  ) {
    Row(
      modifier = Modifier.fillMaxWidth(),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Icon(
        icon,
        contentDescription = null,
        tint = if (destructive) MaterialTheme.colorScheme.error else AccentBlue,
        modifier = Modifier.size(22.dp),
      )
      Spacer(modifier = Modifier.width(12.dp))
      Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
        Text(
          title,
          color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
          fontWeight = FontWeight.Medium,
        )
        if (detail != null) {
          Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }
    }
  }
}

@Composable
private fun EmptyDevicesState(modifier: Modifier = Modifier, onAdd: () -> Unit) {
  Column(
    modifier = modifier,
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Box(
      modifier = Modifier
        .size(88.dp)
        .clip(RoundedCornerShape(28.dp))
        .background(AccentBlue.copy(alpha = 0.12f)),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        Icons.Default.Devices,
        contentDescription = null,
        tint = AccentBlue,
        modifier = Modifier.size(40.dp),
      )
    }
    Spacer(modifier = Modifier.height(20.dp))
    Text("还没有设备", style = MaterialTheme.typography.titleLarge)
    Spacer(modifier = Modifier.height(8.dp))
    Text(
      "添加被控机后即可镜像监看。\nAndroid 11+ 可用二维码一键配对。",
      style = MaterialTheme.typography.bodyMedium,
      color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(20.dp))
    TextButton(onClick = onAdd) {
      Text("添加第一台设备", color = AccentBlue, fontWeight = FontWeight.SemiBold)
    }
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DeviceCard(
  device: Device,
  selected: Boolean = false,
  onClick: () -> Unit,
  onLongClick: () -> Unit,
) {
  val borderColor = if (selected) AccentBlue else MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
  Card(
    modifier = Modifier
      .fillMaxWidth()
      .border(1.dp, borderColor, RoundedCornerShape(20.dp)),
    shape = RoundedCornerShape(20.dp),
    colors = CardDefaults.cardColors(
      containerColor = if (selected) {
        AccentBlue.copy(alpha = 0.08f)
      } else {
        MaterialTheme.colorScheme.surface
      },
    ),
    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .combinedClickable(onClick = onClick, onLongClick = onLongClick)
        .padding(16.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Box(
        modifier = Modifier
          .size(52.dp)
          .clip(RoundedCornerShape(16.dp))
          .background(AccentBlue.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
      ) {
        Icon(
          imageVector = if (device.isNetworkDevice) Icons.Default.Wifi else Icons.Default.Usb,
          contentDescription = null,
          tint = AccentBlue,
        )
      }
      Spacer(modifier = Modifier.width(14.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
          device.name,
          style = MaterialTheme.typography.titleMedium,
          fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(3.dp))
        Text(
          if (device.isNetworkDevice) {
            val port = if (device.adbPort > 0) device.adbPort.toString() else "?"
            "${device.address} · $port"
          } else {
            "USB 连接"
          },
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (selected) {
          Spacer(modifier = Modifier.height(2.dp))
          Text(
            stringResource(R.string.home_selected),
            style = MaterialTheme.typography.labelSmall,
            color = AccentBlue,
            fontWeight = FontWeight.Medium,
          )
        }
      }
      TextButton(onClick = onLongClick) {
        Text(stringResource(R.string.manage_title), color = MaterialTheme.colorScheme.onSurfaceVariant)
      }
    }
  }
}
