package com.shiyunjin.easycontrolnext.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.helper.AppErrorLog
import com.shiyunjin.easycontrolnext.app.ui.theme.AccentBlue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class LevelFilter { ALL, ERROR, WARN }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ErrorLogScreen(onBack: () -> Unit) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  val entries = remember { mutableStateListOf<AppErrorLog.Entry>() }
  var query by remember { mutableStateOf("") }
  var levelFilter by remember { mutableStateOf(LevelFilter.ALL) }
  var selected by remember { mutableStateOf<Set<Int>>(emptySet()) }
  var expandedIndex by remember { mutableStateOf<Int?>(null) }
  var confirmClear by remember { mutableStateOf(false) }
  val dateFormat = remember { SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.getDefault()) }

  fun reload() {
    scope.launch {
      val list = withContext(Dispatchers.IO) { AppErrorLog.readNewestFirst() }
      entries.clear()
      entries.addAll(list)
      selected = emptySet()
      expandedIndex = null
    }
  }

  LaunchedEffect(Unit) { reload() }

  val filtered = remember(entries.toList(), query, levelFilter) {
    val q = query.trim().lowercase(Locale.getDefault())
    entries.mapIndexed { index, entry -> index to entry }
      .filter { (_, e) ->
        when (levelFilter) {
          LevelFilter.ALL -> true
          LevelFilter.ERROR -> e.level == AppErrorLog.Level.E
          LevelFilter.WARN -> e.level == AppErrorLog.Level.W
        }
      }
      .filter { (_, e) ->
        if (q.isEmpty()) true
        else {
          e.tag.lowercase(Locale.getDefault()).contains(q) ||
            e.message.lowercase(Locale.getDefault()).contains(q) ||
            (e.stackTrace?.lowercase(Locale.getDefault())?.contains(q) == true)
        }
      }
  }

  Scaffold(
    containerColor = MaterialTheme.colorScheme.background,
    topBar = {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .statusBarsPadding()
          // topBar owns statusBars; modest extra top so title isn't cramped under cutout.
          .padding(start = 8.dp, top = 12.dp, end = 8.dp, bottom = 8.dp),
      ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
          IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.error_log_back))
          }
          Text(
            stringResource(R.string.error_log_title),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
          )
          IconButton(onClick = { reload() }) {
            Icon(Icons.Default.Refresh, contentDescription = stringResource(R.string.error_log_refresh))
          }
          IconButton(
            onClick = {
              val text = if (selected.isEmpty()) {
                AppErrorLog.exportText()
              } else {
                selected.sorted().mapNotNull { i -> entries.getOrNull(i) }
                  .joinToString("\n----\n") { it.formatBlock() }
              }
              if (text.isBlank()) {
                Toast.makeText(context, context.getString(R.string.error_log_empty), Toast.LENGTH_SHORT).show()
              } else {
                copyText(context, text)
                Toast.makeText(context, context.getString(R.string.error_log_copied), Toast.LENGTH_SHORT).show()
              }
            },
          ) {
            Icon(Icons.Default.ContentCopy, contentDescription = stringResource(R.string.error_log_copy))
          }
          IconButton(
            onClick = {
              val text = if (selected.isEmpty()) AppErrorLog.exportText()
              else selected.sorted().mapNotNull { i -> entries.getOrNull(i) }
                .joinToString("\n----\n") { it.formatBlock() }
              if (text.isBlank()) {
                Toast.makeText(context, context.getString(R.string.error_log_empty), Toast.LENGTH_SHORT).show()
              } else {
                shareText(context, text)
              }
            },
          ) {
            Icon(Icons.Default.Share, contentDescription = stringResource(R.string.error_log_share))
          }
          IconButton(onClick = { confirmClear = true }) {
            Icon(
              Icons.Default.Delete,
              contentDescription = stringResource(R.string.error_log_clear),
              tint = MaterialTheme.colorScheme.error,
            )
          }
        }
      }
    },
  ) { padding ->
    // Scaffold content padding already includes navigationBars (topBar owns statusBars).
    Column(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding)
        .padding(horizontal = 16.dp),
    ) {
      OutlinedTextField(
        value = query,
        onValueChange = { query = it },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        shape = RoundedCornerShape(14.dp),
        placeholder = { Text(stringResource(R.string.error_log_search_hint)) },
        label = { Text(stringResource(R.string.error_log_search)) },
      )
      Spacer(modifier = Modifier.height(8.dp))
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(
          selected = levelFilter == LevelFilter.ALL,
          onClick = { levelFilter = LevelFilter.ALL },
          label = { Text(stringResource(R.string.error_log_filter_all)) },
        )
        FilterChip(
          selected = levelFilter == LevelFilter.ERROR,
          onClick = { levelFilter = LevelFilter.ERROR },
          label = { Text(stringResource(R.string.error_log_filter_error)) },
        )
        FilterChip(
          selected = levelFilter == LevelFilter.WARN,
          onClick = { levelFilter = LevelFilter.WARN },
          label = { Text(stringResource(R.string.error_log_filter_warn)) },
        )
      }
      Spacer(modifier = Modifier.height(4.dp))
      Text(
        stringResource(R.string.error_log_count, filtered.size, entries.size),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
      Spacer(modifier = Modifier.height(8.dp))

      if (filtered.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
          Text(
            stringResource(R.string.error_log_empty),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      } else {
        LazyColumn(
          modifier = Modifier.fillMaxSize(),
          contentPadding = PaddingValues(bottom = 24.dp),
          verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          itemsIndexed(filtered, key = { _, pair -> "${pair.first}-${pair.second.timestampMs}" }) { _, pair ->
            val (index, entry) = pair
            val isSelected = selected.contains(index)
            val expanded = expandedIndex == index
            ErrorLogRow(
              entry = entry,
              dateText = dateFormat.format(Date(entry.timestampMs)),
              selected = isSelected,
              expanded = expanded,
              onToggleSelect = {
                selected = if (isSelected) selected - index else selected + index
              },
              onToggleExpand = {
                expandedIndex = if (expanded) null else index
              },
            )
          }
        }
      }
    }
  }

  if (confirmClear) {
    AlertDialog(
      onDismissRequest = { confirmClear = false },
      title = { Text(stringResource(R.string.error_log_clear_title)) },
      text = { Text(stringResource(R.string.error_log_clear_message)) },
      confirmButton = {
        TextButton(
          onClick = {
            confirmClear = false
            AppErrorLog.clear()
            reload()
            Toast.makeText(context, context.getString(R.string.error_log_cleared), Toast.LENGTH_SHORT).show()
          },
        ) {
          Text(stringResource(R.string.error_log_clear), color = MaterialTheme.colorScheme.error)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmClear = false }) {
          Text(stringResource(android.R.string.cancel))
        }
      },
    )
  }
}

@Composable
private fun ErrorLogRow(
  entry: AppErrorLog.Entry,
  dateText: String,
  selected: Boolean,
  expanded: Boolean,
  onToggleSelect: () -> Unit,
  onToggleExpand: () -> Unit,
) {
  val levelColor = when (entry.level) {
    AppErrorLog.Level.E -> MaterialTheme.colorScheme.error
    AppErrorLog.Level.W -> MaterialTheme.colorScheme.tertiary
  }
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(MaterialTheme.colorScheme.surface)
      .border(
        width = if (selected) 2.dp else 1.dp,
        color = if (selected) AccentBlue else MaterialTheme.colorScheme.outline.copy(alpha = 0.45f),
        shape = RoundedCornerShape(16.dp),
      )
      .clickable(onClick = onToggleExpand)
      .padding(14.dp),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Box(
        modifier = Modifier
          .size(28.dp)
          .clip(CircleShape)
          .background(levelColor.copy(alpha = 0.15f))
          .clickable(onClick = onToggleSelect),
        contentAlignment = Alignment.Center,
      ) {
        Text(
          entry.level.name,
          color = levelColor,
          style = MaterialTheme.typography.labelMedium,
          fontWeight = FontWeight.Bold,
        )
      }
      Spacer(modifier = Modifier.width(10.dp))
      Column(modifier = Modifier.weight(1f)) {
        Text(
          entry.tag,
          style = MaterialTheme.typography.titleSmall,
          fontWeight = FontWeight.SemiBold,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          dateText,
          style = MaterialTheme.typography.labelSmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
      }
      Text(
        if (selected) stringResource(R.string.error_log_selected)
        else stringResource(R.string.error_log_tap_select),
        style = MaterialTheme.typography.labelSmall,
        color = if (selected) AccentBlue else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
          .clip(RoundedCornerShape(8.dp))
          .clickable(onClick = onToggleSelect)
          .padding(horizontal = 8.dp, vertical = 4.dp),
      )
    }
    Spacer(modifier = Modifier.height(8.dp))
    Text(
      entry.message,
      style = MaterialTheme.typography.bodyMedium,
      maxLines = if (expanded) Int.MAX_VALUE else 3,
      overflow = TextOverflow.Ellipsis,
      fontFamily = FontFamily.Monospace,
    )
    if (expanded && !entry.stackTrace.isNullOrBlank()) {
      Spacer(modifier = Modifier.height(8.dp))
      HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
      Spacer(modifier = Modifier.height(8.dp))
      Text(
        entry.stackTrace,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontFamily = FontFamily.Monospace,
      )
    }
  }
}

private fun copyText(context: Context, text: String) {
  val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
  cm.setPrimaryClip(ClipData.newPlainText("error_log", text))
}

private fun shareText(context: Context, text: String) {
  val intent = Intent(Intent.ACTION_SEND).apply {
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, text)
  }
  context.startActivity(Intent.createChooser(intent, context.getString(R.string.error_log_share)))
}
