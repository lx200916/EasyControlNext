package com.shiyunjin.easycontrolnext.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.client.tools.AdbTools
import com.shiyunjin.easycontrolnext.app.entity.Device
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

@Composable
fun AppPickerDialog(
  device: Device,
  onDismiss: () -> Unit,
  onPicked: (packageName: String) -> Unit,
) {
  val scope = rememberCoroutineScope()
  var includeSystem by remember { mutableStateOf(false) }
  var query by remember { mutableStateOf("") }
  var loading by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  var apps by remember { mutableStateOf<List<AdbTools.InstalledApp>>(emptyList()) }

  val fieldColors = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = AccentBlue,
    focusedLabelColor = AccentBlue,
    cursorColor = AccentBlue,
  )

  fun load() {
    scope.launch {
      loading = true
      error = null
      try {
        val result = withContext(Dispatchers.IO) {
          withTimeout(25_000) {
            AdbTools.listInstalledApps(device, includeSystem)
          }
        }
        apps = result
        if (result.isEmpty()) {
          error = "未获取到应用列表（超时或为空）"
        }
      } catch (e: Exception) {
        apps = emptyList()
        error = e.message ?: e.toString()
      } finally {
        loading = false
      }
    }
  }

  LaunchedEffect(includeSystem) {
    load()
  }

  val filtered = remember(apps, query) {
    val q = query.trim().lowercase()
    if (q.isEmpty()) apps
    else apps.filter {
      it.label.lowercase().contains(q) || it.packageName.lowercase().contains(q)
    }
  }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false),
  ) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.94f)
        .fillMaxHeight(0.85f),
      shape = RoundedCornerShape(20.dp),
      color = MaterialTheme.colorScheme.surface,
      tonalElevation = 3.dp,
    ) {
      Column(modifier = Modifier.padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Text(
            stringResource(R.string.device_pick_app),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
          )
          IconButton(onClick = { if (!loading) load() }) {
            Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.device_pick_app_refresh))
          }
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = null)
          }
        }

        OutlinedTextField(
          value = query,
          onValueChange = { query = it },
          modifier = Modifier.fillMaxWidth(),
          singleLine = true,
          label = { Text(stringResource(R.string.device_pick_app_search)) },
          leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
          shape = RoundedCornerShape(14.dp),
          colors = fieldColors,
        )

        Row(
          modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(
            stringResource(R.string.device_pick_app_include_system),
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
          )
          Switch(
            checked = includeSystem,
            onCheckedChange = { includeSystem = it },
            colors = SwitchDefaults.colors(checkedTrackColor = AccentBlue),
          )
        }

        when {
          loading -> {
            Column(
              modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
              verticalArrangement = Arrangement.Center,
              horizontalAlignment = Alignment.CenterHorizontally,
            ) {
              AppLoadingIndicator()
              Spacer(modifier = Modifier.height(12.dp))
              Text(
                text = stringResource(R.string.device_pick_app_loading),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }

          error != null -> {
            Column(
              modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(8.dp),
              verticalArrangement = Arrangement.Center,
              horizontalAlignment = Alignment.CenterHorizontally,
            ) {
              Text(
                error ?: "",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
              )
              Spacer(modifier = Modifier.height(12.dp))
              TextButton(onClick = { load() }) {
                Text(stringResource(R.string.device_pick_app_refresh))
              }
            }
          }

          filtered.isEmpty() -> {
            Column(
              modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
              verticalArrangement = Arrangement.Center,
              horizontalAlignment = Alignment.CenterHorizontally,
            ) {
              Text(
                stringResource(R.string.device_pick_app_empty),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }

          else -> {
            LazyColumn(modifier = Modifier.weight(1f)) {
              items(filtered, key = { it.packageName }) { app ->
                Column(
                  modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                      onPicked(app.packageName)
                      onDismiss()
                    }
                    .padding(vertical = 10.dp, horizontal = 4.dp),
                ) {
                  Text(app.label, fontWeight = FontWeight.Medium)
                  Text(
                    app.packageName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
              }
            }
          }
        }
      }
    }
  }
}
