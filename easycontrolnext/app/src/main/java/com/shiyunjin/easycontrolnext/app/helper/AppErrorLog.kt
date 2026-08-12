package com.shiyunjin.easycontrolnext.app.helper

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.io.PrintWriter
import java.io.StringWriter
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Persistent, capped error/warning log under app private storage.
 * Writes are async; reads return newest-first snapshots.
 */
object AppErrorLog {
  enum class Level {
    E,
    W,
  }

  data class Entry(
    val timestampMs: Long,
    val level: Level,
    val tag: String,
    val message: String,
    val stackTrace: String? = null,
  ) {
    fun formatBlock(dateFormat: SimpleDateFormat = defaultDateFormat()): String {
      val header = "${dateFormat.format(Date(timestampMs))} ${level.name}/$tag"
      return if (stackTrace.isNullOrBlank()) {
        "$header\n$message"
      } else {
        "$header\n$message\n$stackTrace"
      }
    }
  }

  private const val TAG = "AppErrorLog"
  private const val FILE_NAME = "error_log.txt"
  private const val MAX_ENTRIES = 400
  private const val MAX_FILE_BYTES = 512 * 1024
  private const val RECORD_SEP = "----"

  private val lock = Any()
  private val entries = ArrayDeque<Entry>(MAX_ENTRIES)
  private val loaded = AtomicBoolean(false)
  private val handlerInstalled = AtomicBoolean(false)

  @Volatile
  private var logFile: File? = null

  private val writer: ExecutorService = Executors.newSingleThreadExecutor { r ->
    Thread(r, "AppErrorLog").apply { isDaemon = true }
  }

  @JvmStatic
  fun init(context: Context) {
    val file = File(context.applicationContext.filesDir, FILE_NAME)
    synchronized(lock) {
      logFile = file
      if (!loaded.get()) {
        loadLocked(file)
        loaded.set(true)
      }
    }
  }

  @JvmStatic
  fun installUncaughtHandler() {
    if (!handlerInstalled.compareAndSet(false, true)) return
    val previous = Thread.getDefaultUncaughtExceptionHandler()
    Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
      try {
        appendSync(
          Level.E,
          "Uncaught",
          "Uncaught exception in thread ${thread.name}",
          throwable,
        )
      } catch (_: Exception) {
      }
      previous?.uncaughtException(thread, throwable)
    }
  }

  @JvmStatic
  @JvmOverloads
  fun e(tag: String, message: String, throwable: Throwable? = null) {
    append(Level.E, tag, message, throwable)
  }

  @JvmStatic
  @JvmOverloads
  fun w(tag: String, message: String, throwable: Throwable? = null) {
    append(Level.W, tag, message, throwable)
  }

  @JvmStatic
  fun append(level: Level, tag: String, message: String, throwable: Throwable? = null) {
    val safeTag = tag.ifBlank { "app" }
    val safeMsg = message.ifBlank { throwable?.message ?: "(empty)" }
    val entry = Entry(
      timestampMs = System.currentTimeMillis(),
      level = level,
      tag = safeTag,
      message = safeMsg,
      stackTrace = throwable?.let { stackString(it) },
    )
    // Keep Logcat visibility for developers
    val logTag = "Easycontrol_$safeTag"
    when (level) {
      Level.E -> if (throwable != null) Log.e(logTag, safeMsg, throwable) else Log.e(logTag, safeMsg)
      Level.W -> if (throwable != null) Log.w(logTag, safeMsg, throwable) else Log.w(logTag, safeMsg)
    }
    writer.execute {
      try {
        appendSync(entry)
      } catch (t: Throwable) {
        Log.w(TAG, "Failed to persist log entry", t)
      }
    }
  }

  /** Newest-first snapshot for UI. */
  @JvmStatic
  fun readNewestFirst(): List<Entry> {
    ensureLoaded()
    synchronized(lock) {
      return entries.toList()
    }
  }

  @JvmStatic
  fun clear() {
    ensureLoaded()
    synchronized(lock) {
      entries.clear()
    }
    writer.execute {
      synchronized(lock) {
        // Keep empty unless newer entries arrived while queued
        if (entries.isEmpty()) {
          persistLocked()
        }
      }
    }
  }

  @JvmStatic
  fun exportText(): String {
    val df = defaultDateFormat()
    val list = readNewestFirst()
    if (list.isEmpty()) return ""
    return list.joinToString("\n$RECORD_SEP\n") { it.formatBlock(df) }
  }

  private fun appendSync(level: Level, tag: String, message: String, throwable: Throwable?) {
    appendSync(
      Entry(
        timestampMs = System.currentTimeMillis(),
        level = level,
        tag = tag.ifBlank { "app" },
        message = message.ifBlank { throwable?.message ?: "(empty)" },
        stackTrace = throwable?.let { stackString(it) },
      ),
    )
  }

  private fun appendSync(entry: Entry) {
    ensureLoaded()
    synchronized(lock) {
      entries.addFirst(entry)
      while (entries.size > MAX_ENTRIES) {
        entries.removeLast()
      }
      persistLocked()
    }
  }

  private fun ensureLoaded() {
    if (loaded.get()) return
    val file = logFile ?: return
    synchronized(lock) {
      if (!loaded.get()) {
        loadLocked(file)
        loaded.set(true)
      }
    }
  }

  private fun loadLocked(file: File) {
    entries.clear()
    if (!file.isFile || file.length() == 0L) return
    try {
      BufferedReader(InputStreamReader(FileInputStream(file), StandardCharsets.UTF_8)).use { reader ->
        val blocks = ArrayList<StringBuilder>()
        var current: StringBuilder? = null
        var line: String?
        while (reader.readLine().also { line = it } != null) {
          val text = line ?: continue
          if (text == RECORD_SEP) {
            current = StringBuilder()
            blocks.add(current)
          } else {
            if (current == null) {
              current = StringBuilder()
              blocks.add(current)
            }
            if (current.isNotEmpty()) current.append('\n')
            current.append(text)
          }
        }
        // File is oldest-first on disk → keep newest-first in memory
        val parsed = ArrayList<Entry>(blocks.size)
        for (block in blocks) {
          parseBlock(block.toString())?.let { parsed.add(it) }
        }
        val keep = if (parsed.size > MAX_ENTRIES) {
          parsed.subList(parsed.size - MAX_ENTRIES, parsed.size)
        } else {
          parsed
        }
        for (i in keep.size - 1 downTo 0) {
          entries.addLast(keep[i])
        }
      }
    } catch (t: Throwable) {
      Log.w(TAG, "Failed to load error log", t)
      entries.clear()
    }
  }

  private fun persistLocked() {
    val file = logFile ?: return
    try {
      // Write oldest-first for append-friendly reading
      val ordered = entries.toList().asReversed()
      val tmp = File(file.parentFile, "$FILE_NAME.tmp")
      FileOutputStream(tmp, false).use { fos ->
        val df = defaultDateFormat()
        val out = fos.bufferedWriter(StandardCharsets.UTF_8)
        for ((index, entry) in ordered.withIndex()) {
          if (index > 0) out.append(RECORD_SEP).append('\n')
          out.append(entry.formatBlock(df)).append('\n')
        }
        out.flush()
      }
      if (!tmp.renameTo(file)) {
        tmp.copyTo(file, overwrite = true)
        tmp.delete()
      }
      // Soft size cap: drop oldest if file still huge
      if (file.length() > MAX_FILE_BYTES && entries.isNotEmpty()) {
        while (file.length() > MAX_FILE_BYTES * 3 / 4 && entries.size > 20) {
          entries.removeLast()
        }
        persistLocked()
      }
    } catch (t: Throwable) {
      Log.w(TAG, "Failed to write error log", t)
    }
  }

  private fun parseBlock(block: String): Entry? {
    val trimmed = block.trim()
    if (trimmed.isEmpty()) return null
    val lines = trimmed.split('\n', limit = 3)
    if (lines.isEmpty()) return null
    val header = lines[0]
    // "yyyy-MM-dd HH:mm:ss.SSS E/tag"
    val slash = header.lastIndexOf('/')
    val space = header.lastIndexOf(' ')
    if (slash <= 0 || space <= 0 || space >= slash) {
      return Entry(System.currentTimeMillis(), Level.E, "log", trimmed, null)
    }
    val levelChar = header.substring(space + 1, slash)
    val tag = header.substring(slash + 1).ifBlank { "log" }
    val level = if (levelChar.equals("W", true)) Level.W else Level.E
    val ts = try {
      defaultDateFormat().parse(header.substring(0, space))?.time ?: System.currentTimeMillis()
    } catch (_: Exception) {
      System.currentTimeMillis()
    }
    val message = if (lines.size > 1) lines[1] else ""
    val stack = if (lines.size > 2) lines[2] else null
    return Entry(ts, level, tag, message, stack)
  }

  private fun stackString(t: Throwable): String {
    val sw = StringWriter()
    t.printStackTrace(PrintWriter(sw))
    val full = sw.toString()
    return if (full.length > 8000) full.substring(0, 8000) + "\n…" else full
  }

  private fun defaultDateFormat(): SimpleDateFormat =
    SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
}
