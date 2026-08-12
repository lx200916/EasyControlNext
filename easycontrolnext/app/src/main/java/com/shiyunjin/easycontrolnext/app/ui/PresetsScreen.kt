package com.shiyunjin.easycontrolnext.app.ui

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.entity.ConnectionPreset
import com.shiyunjin.easycontrolnext.app.helper.PresetStore
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun PresetsListScreen(
  onBack: () -> Unit,
  onEdit: (String) -> Unit,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  // Defer Prefs/JSON read off first frame so open animation stays smooth.
  var presets by remember { mutableStateOf<List<ConnectionPreset>>(emptyList()) }
  var defaultId by remember { mutableStateOf("") }
  var loading by remember { mutableStateOf(true) }
  var confirmDelete by remember { mutableStateOf<ConnectionPreset?>(null) }
  var pendingLinkedUpdate by remember { mutableStateOf<ConnectionPreset?>(null) }

  fun reload() {
    scope.launch {
      val (list, def) = withContext(Dispatchers.IO) {
        PresetStore.all() to PresetStore.defaultId()
      }
      presets = list
      defaultId = def
      loading = false
    }
  }

  LaunchedEffect(Unit) { reload() }

  fun offerLinkedUpdate(preset: ConnectionPreset) {
    if (PresetStore.linkedCount(preset.id) > 0) {
      pendingLinkedUpdate = preset
    }
  }

  Scaffold(
    containerColor = MaterialTheme.colorScheme.background,
    floatingActionButton = {
      FloatingActionButton(
        onClick = { onEdit("new") },
        containerColor = AccentBlue,
        contentColor = MaterialTheme.colorScheme.onPrimary,
      ) {
        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.preset_create))
      }
    },
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
            stringResource(R.string.preset_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
          )
          Text(
            stringResource(R.string.preset_subtitle),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }

      Column(
        modifier = Modifier
          .fillMaxSize()
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp)
          .padding(bottom = 88.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        Text(
          stringResource(R.string.preset_default_hint),
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
          modifier = Modifier.padding(bottom = 4.dp),
        )
        if (loading && presets.isEmpty()) {
          AppInlineLoading(
            modifier = Modifier
              .fillMaxWidth()
              .padding(vertical = 32.dp),
          )
        } else {
          presets.forEach { preset ->
            PresetListRow(
              preset = preset,
              isDefault = preset.id == defaultId,
              onClick = { onEdit(preset.id) },
              onSetDefault = {
                PresetStore.setDefaultId(preset.id)
                reload()
                Toast.makeText(context, R.string.toast_success, Toast.LENGTH_SHORT).show()
              },
              onDuplicate = {
                PresetStore.duplicate(preset, context.getString(R.string.preset_copy_suffix))
                reload()
              },
              onDelete = { confirmDelete = preset },
              onReset = { confirmDelete = preset },
            )
          }
        }
      }
    }
  }

  confirmDelete?.let { target ->
    AlertDialog(
      onDismissRequest = { confirmDelete = null },
      title = {
        Text(
          if (target.isBuiltIn) stringResource(R.string.preset_reset_title)
          else stringResource(R.string.preset_delete_title),
        )
      },
      text = {
        Text(
          if (target.isBuiltIn) stringResource(R.string.preset_reset_message)
          else stringResource(R.string.preset_delete_message, target.name),
        )
      },
      confirmButton = {
        TextButton(onClick = {
          if (target.isBuiltIn) {
            val reset = PresetStore.resetBuiltIn(target.id)
            confirmDelete = null
            reload()
            Toast.makeText(context, R.string.preset_reset_done, Toast.LENGTH_SHORT).show()
            if (reset != null) offerLinkedUpdate(reset)
          } else {
            PresetStore.deleteOrReset(target.id)
            confirmDelete = null
            reload()
            Toast.makeText(context, R.string.toast_success, Toast.LENGTH_SHORT).show()
          }
        }) {
          Text(
            if (target.isBuiltIn) stringResource(R.string.preset_reset)
            else stringResource(R.string.preset_delete),
          )
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmDelete = null }) {
          Text(stringResource(android.R.string.cancel))
        }
      },
    )
  }

  pendingLinkedUpdate?.let { preset ->
    UpdateLinkedDevicesDialog(
      preset = preset,
      onUpdate = {
        val n = PresetStore.updateLinkedDevices(preset)
        pendingLinkedUpdate = null
        Toast.makeText(
          context,
          context.getString(R.string.preset_linked_updated, n),
          Toast.LENGTH_SHORT,
        ).show()
      },
      onKeep = { pendingLinkedUpdate = null },
    )
  }
}

@Composable
fun UpdateLinkedDevicesDialog(
  preset: ConnectionPreset,
  onUpdate: () -> Unit,
  onKeep: () -> Unit,
) {
  val count = PresetStore.linkedCount(preset.id)
  AlertDialog(
    onDismissRequest = onKeep,
    title = { Text(stringResource(R.string.preset_update_linked_title)) },
    text = {
      Text(stringResource(R.string.preset_update_linked_message, count, preset.name))
    },
    confirmButton = {
      TextButton(onClick = onUpdate) {
        Text(stringResource(R.string.preset_update_linked_confirm))
      }
    },
    dismissButton = {
      TextButton(onClick = onKeep) {
        Text(stringResource(R.string.preset_update_linked_keep))
      }
    },
  )
}

@Composable
private fun PresetListRow(
  preset: ConnectionPreset,
  isDefault: Boolean,
  onClick: () -> Unit,
  onSetDefault: () -> Unit,
  onDuplicate: () -> Unit,
  onDelete: () -> Unit,
  onReset: () -> Unit,
) {
  Card(
    modifier = Modifier
      .fillMaxWidth()
      .clickable(onClick = onClick),
    shape = RoundedCornerShape(18.dp),
    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    elevation = CardDefaults.cardElevation(0.dp),
  ) {
    Column(modifier = Modifier.padding(14.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
              preset.name,
              style = MaterialTheme.typography.titleSmall,
              fontWeight = FontWeight.SemiBold,
            )
            if (isDefault) {
              Spacer(modifier = Modifier.width(6.dp))
              Text(
                stringResource(R.string.preset_badge_default),
                style = MaterialTheme.typography.labelSmall,
                color = AccentBlue,
                fontWeight = FontWeight.SemiBold,
              )
            }
            if (preset.isBuiltIn) {
              Spacer(modifier = Modifier.width(6.dp))
              Text(
                stringResource(R.string.preset_badge_builtin),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
          Spacer(modifier = Modifier.height(2.dp))
          Text(
            presetSummary(preset),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
        Icon(
          Icons.AutoMirrored.Filled.KeyboardArrowRight,
          contentDescription = null,
          tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      Spacer(modifier = Modifier.height(6.dp))
      Row(verticalAlignment = Alignment.CenterVertically) {
        if (!isDefault) {
          TextButton(onClick = onSetDefault) {
            Icon(Icons.Default.Star, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(4.dp))
            Text(stringResource(R.string.preset_set_default))
          }
        }
        TextButton(onClick = onDuplicate) {
          Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
          Spacer(modifier = Modifier.width(4.dp))
          Text(stringResource(R.string.preset_duplicate))
        }
        if (preset.isBuiltIn) {
          TextButton(onClick = onReset) {
            Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(4.dp))
            Text(stringResource(R.string.preset_reset))
          }
        } else {
          TextButton(onClick = onDelete) {
            Icon(
              Icons.Default.Delete,
              contentDescription = null,
              modifier = Modifier.size(16.dp),
              tint = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
              stringResource(R.string.preset_delete),
              color = MaterialTheme.colorScheme.error,
            )
          }
        }
      }
    }
  }
}

@Composable
private fun presetSummary(preset: ConnectionPreset): String {
  val source = if (preset.videoSource == "camera") {
    stringResource(R.string.device_video_source_camera)
  } else {
    stringResource(R.string.device_video_source_display)
  }
  return "$source · ${preset.maxSize}px · ${preset.maxFps}fps · ${preset.maxVideoBit}Mbps"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PresetEditorScreen(
  presetId: String,
  onBack: () -> Unit,
) {
  val context = LocalContext.current
  val isNew = presetId == "new"
  val existing = remember(presetId) {
    if (isNew) null else PresetStore.get(presetId)
  }
  if (!isNew && existing == null) {
    LaunchedEffectMissing(onBack)
    return
  }

  var name by remember {
    mutableStateOf(existing?.name ?: context.getString(R.string.preset_new_name))
  }
  var form by remember {
    mutableStateOf(
      if (existing != null) DeviceFormState.fromPreset(existing)
      else DeviceFormState.fromPreset(PresetStore.getDefault()).copy(presetId = ""),
    )
  }
  var pendingLinkedUpdate by remember { mutableStateOf<ConnectionPreset?>(null) }
  val fieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    focusedLabelColor = AccentBlue,
    cursorColor = AccentBlue,
  )

  fun finishSave(saved: ConnectionPreset, askLinked: Boolean) {
    PresetStore.save(saved)
    Toast.makeText(context, R.string.toast_success, Toast.LENGTH_SHORT).show()
    if (askLinked && PresetStore.linkedCount(saved.id) > 0) {
      pendingLinkedUpdate = saved
    } else {
      onBack()
    }
  }

  Scaffold(containerColor = MaterialTheme.colorScheme.background) { padding ->
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
        Text(
          if (isNew) stringResource(R.string.preset_create)
          else stringResource(R.string.preset_edit),
          style = MaterialTheme.typography.titleLarge,
          fontWeight = FontWeight.Bold,
          modifier = Modifier.weight(1f),
        )
        TextButton(onClick = {
          val trimmed = name.trim()
          if (trimmed.isEmpty()) {
            Toast.makeText(context, R.string.preset_name_required, Toast.LENGTH_SHORT).show()
            return@TextButton
          }
          val saved = form.toPreset(
            id = existing?.id ?: UUID.randomUUID().toString(),
            name = trimmed,
            builtInKey = existing?.builtInKey,
          )
          finishSave(saved, askLinked = !isNew)
        }) {
          Text(stringResource(R.string.preset_save), color = AccentBlue, fontWeight = FontWeight.SemiBold)
        }
      }

      Column(
        modifier = Modifier
          .fillMaxSize()
          .verticalScroll(rememberScrollState())
          .padding(horizontal = 20.dp)
          .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Card(
          modifier = Modifier.fillMaxWidth(),
          shape = RoundedCornerShape(20.dp),
          colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
          elevation = CardDefaults.cardElevation(0.dp),
        ) {
          Column(modifier = Modifier.padding(16.dp)) {
            OutlinedTextField(
              value = name,
              onValueChange = { name = it },
              modifier = Modifier.fillMaxWidth(),
              label = { Text(stringResource(R.string.preset_name)) },
              singleLine = true,
              shape = RoundedCornerShape(14.dp),
              colors = fieldColors,
            )
            if (existing?.isBuiltIn == true) {
              Spacer(modifier = Modifier.height(8.dp))
              Text(
                stringResource(R.string.preset_builtin_edit_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
            if (!isNew && existing != null) {
              Spacer(modifier = Modifier.height(8.dp))
              Text(
                stringResource(
                  R.string.preset_linked_count_hint,
                  PresetStore.linkedCount(existing.id),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
        }

        Card(
          modifier = Modifier.fillMaxWidth(),
          shape = RoundedCornerShape(20.dp),
          colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
          elevation = CardDefaults.cardElevation(0.dp),
        ) {
          Column(modifier = Modifier.padding(16.dp)) {
            Text(
              stringResource(R.string.preset_stream_section),
              style = MaterialTheme.typography.titleMedium,
              fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(8.dp))
            PresetStreamConfig(state = form, onStateChange = { form = it }, fieldColors = fieldColors)
          }
        }
      }
    }
  }

  pendingLinkedUpdate?.let { preset ->
    UpdateLinkedDevicesDialog(
      preset = preset,
      onUpdate = {
        val n = PresetStore.updateLinkedDevices(preset)
        pendingLinkedUpdate = null
        Toast.makeText(
          context,
          context.getString(R.string.preset_linked_updated, n),
          Toast.LENGTH_SHORT,
        ).show()
        onBack()
      },
      onKeep = {
        pendingLinkedUpdate = null
        onBack()
      },
    )
  }
}

@Composable
private fun LaunchedEffectMissing(onBack: () -> Unit) {
  androidx.compose.runtime.LaunchedEffect(Unit) { onBack() }
}

@Composable
fun PresetStreamConfig(
  state: DeviceFormState,
  onStateChange: (DeviceFormState) -> Unit,
  fieldColors: androidx.compose.material3.TextFieldColors,
) {
  val videoSourceDisplay = stringResource(R.string.device_video_source_display)
  val videoSourceCamera = stringResource(R.string.device_video_source_camera)
  val facingBack = stringResource(R.string.device_camera_facing_back)
  val facingFront = stringResource(R.string.device_camera_facing_front)

  ConfigSpinner(
    title = stringResource(R.string.device_video_source),
    detail = stringResource(R.string.preset_video_source_detail),
    value = if (state.videoSource == "camera") videoSourceCamera else videoSourceDisplay,
    options = listOf(videoSourceDisplay, videoSourceCamera),
  ) { selected ->
    onStateChange(state.copy(videoSource = if (selected == videoSourceCamera) "camera" else "display"))
  }

  if (state.videoSource == "camera") {
    ConfigSpinner(
      title = stringResource(R.string.device_camera_facing),
      detail = stringResource(R.string.preset_camera_facing_detail),
      value = if (state.cameraFacing == "front") facingFront else facingBack,
      options = listOf(facingBack, facingFront),
    ) { selected ->
      onStateChange(state.copy(cameraFacing = if (selected == facingFront) "front" else "back"))
    }
  } else {
    OutlinedTextField(
      value = state.startApp,
      onValueChange = { onStateChange(state.copy(startApp = it.trim())) },
      modifier = Modifier.fillMaxWidth(),
      label = { Text(stringResource(R.string.device_start_app)) },
      supportingText = { Text(stringResource(R.string.preset_start_app_hint)) },
      singleLine = true,
      shape = RoundedCornerShape(14.dp),
      colors = fieldColors,
    )
    Row(modifier = Modifier.fillMaxWidth()) {
      OutlinedTextField(
        value = state.virtualWidth,
        onValueChange = { onStateChange(state.copy(virtualWidth = it.filter(Char::isDigit).take(5))) },
        modifier = Modifier.weight(1f),
        label = { Text(stringResource(R.string.preset_virtual_width)) },
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
        label = { Text(stringResource(R.string.preset_virtual_height)) },
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

  ConfigSwitch(
    title = stringResource(R.string.device_is_audio),
    detail = stringResource(R.string.device_is_audio_detail),
    checked = state.isAudio,
    onCheckedChange = { onStateChange(state.copy(isAudio = it)) },
  )
  ConfigSwitch(
    title = stringResource(R.string.device_listen_clip_on_running),
    detail = stringResource(R.string.device_listen_clip_on_running_detail),
    checked = state.listenClip,
    onCheckedChange = { onStateChange(state.copy(listenClip = it)) },
  )
  ConfigSpinner(
    title = stringResource(R.string.device_max_size),
    detail = stringResource(R.string.device_max_size_detail),
    value = state.maxSize,
    options = listOf("2560", "1920", "1600", "1280", "1024", "800"),
  ) { onStateChange(state.copy(maxSize = it)) }
  ConfigSpinner(
    title = stringResource(R.string.device_max_fps),
    detail = stringResource(R.string.device_max_fps_detail),
    value = state.maxFps,
    options = listOf("90", "60", "40", "30", "20", "10"),
  ) { onStateChange(state.copy(maxFps = it)) }
  ConfigSpinner(
    title = stringResource(R.string.device_max_video_bit),
    detail = stringResource(R.string.device_max_video_bit_detail),
    value = state.maxVideoBit,
    options = listOf("12", "8", "4", "2", "1"),
  ) { onStateChange(state.copy(maxVideoBit = it)) }
  ConfigSwitch(
    title = stringResource(R.string.device_use_h265),
    detail = stringResource(R.string.device_use_h265_detail),
    checked = state.useH265,
    onCheckedChange = { onStateChange(state.copy(useH265 = it)) },
  )
  AnimatedVisibility(visible = state.useH265) {
    HevcProfileSpinner(state = state, onStateChange = onStateChange)
  }
  ConfigSwitch(
    title = stringResource(R.string.device_change_to_full_on_connect),
    detail = stringResource(R.string.device_change_to_full_on_connect_detail),
    checked = state.changeToFullOnConnect,
    onCheckedChange = { onStateChange(state.copy(changeToFullOnConnect = it)) },
  )
  ConfigSwitch(
    title = stringResource(R.string.device_keep_wake_on_running),
    detail = stringResource(R.string.device_keep_wake_on_running_detail),
    checked = state.keepWakeOnRunning,
    onCheckedChange = { onStateChange(state.copy(keepWakeOnRunning = it)) },
  )
  ConfigSwitch(
    title = stringResource(R.string.device_wake_on_connect),
    detail = stringResource(R.string.device_wake_on_connect_detail),
    checked = state.wakeOnConnect,
    onCheckedChange = { onStateChange(state.copy(wakeOnConnect = it)) },
  )
  ConfigSwitch(
    title = stringResource(R.string.device_light_off_on_connect),
    detail = stringResource(R.string.device_light_off_on_connect_detail),
    checked = state.lightOffOnConnect,
    onCheckedChange = { onStateChange(state.copy(lightOffOnConnect = it)) },
  )
  ConfigSwitch(
    title = stringResource(R.string.device_show_nav_bar_on_connect),
    detail = stringResource(R.string.device_show_nav_bar_on_connect_detail),
    checked = state.showNavBarOnConnect,
    onCheckedChange = { onStateChange(state.copy(showNavBarOnConnect = it)) },
  )
}
