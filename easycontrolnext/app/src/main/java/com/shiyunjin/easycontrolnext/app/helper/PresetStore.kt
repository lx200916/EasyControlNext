package com.shiyunjin.easycontrolnext.app.helper

import android.content.Context
import android.content.SharedPreferences
import com.shiyunjin.easycontrolnext.app.R
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.ConnectionPreset
import com.shiyunjin.easycontrolnext.app.entity.Device
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Persists connection presets in SharedPreferences (JSON).
 * Built-ins are re-seeded if missing; deleting a built-in resets it to factory.
 */
object PresetStore {
  private const val PREFS = "connection_presets"
  private const val KEY_LIST = "presets_json"
  private const val KEY_DEFAULT = "default_preset_id"

  private fun prefs(): SharedPreferences {
    val ctx = AppData.applicationContext
    return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
  }

  fun all(): List<ConnectionPreset> {
    ensureSeeded()
    return readList()
  }

  fun get(id: String): ConnectionPreset? = all().find { it.id == id }

  fun getDefault(): ConnectionPreset {
    ensureSeeded()
    val id = prefs().getString(KEY_DEFAULT, ConnectionPreset.ID_NORMAL_REMOTE)
      ?: ConnectionPreset.ID_NORMAL_REMOTE
    return get(id) ?: get(ConnectionPreset.ID_NORMAL_REMOTE) ?: factoryBuiltIns().first()
  }

  fun setDefaultId(id: String) {
    prefs().edit().putString(KEY_DEFAULT, id).apply()
  }

  fun defaultId(): String {
    ensureSeeded()
    return prefs().getString(KEY_DEFAULT, ConnectionPreset.ID_NORMAL_REMOTE)
      ?: ConnectionPreset.ID_NORMAL_REMOTE
  }

  fun save(preset: ConnectionPreset) {
    val list = all().toMutableList()
    val idx = list.indexOfFirst { it.id == preset.id }
    if (idx >= 0) list[idx] = preset else list.add(preset)
    writeList(list)
  }

  fun duplicate(preset: ConnectionPreset, copySuffix: String): ConnectionPreset {
    val copy = preset.copy(
      id = UUID.randomUUID().toString(),
      name = preset.name + copySuffix,
      builtInKey = null,
    )
    save(copy)
    return copy
  }

  /**
   * Custom: remove. Built-in: reset to factory (not permanently deletable).
   * @return true if removed, false if reset
   */
  fun deleteOrReset(id: String): Boolean {
    val list = all().toMutableList()
    val existing = list.find { it.id == id } ?: return true
    if (existing.isBuiltIn) {
      val factory = factoryByKey(existing.builtInKey!!)
      val idx = list.indexOfFirst { it.id == id }
      if (idx >= 0 && factory != null) {
        // Keep user-chosen name if they renamed; restore options from factory
        list[idx] = factory.copy(name = existing.name)
        writeList(list)
      }
      return false
    }
    list.removeAll { it.id == id }
    writeList(list)
    // Keep device field values; only clear the link
    clearDeviceLinks(id)
    if (defaultId() == id) {
      setDefaultId(ConnectionPreset.ID_NORMAL_REMOTE)
    }
    return true
  }

  fun resetBuiltIn(id: String): ConnectionPreset? {
    val list = all().toMutableList()
    val existing = list.find { it.id == id } ?: return null
    val key = existing.builtInKey ?: return null
    val factory = factoryByKey(key) ?: return null
    val idx = list.indexOfFirst { it.id == id }
    if (idx >= 0) {
      list[idx] = factory
      writeList(list)
    }
    return factory
  }

  /** Devices that still link this preset (presetId set). Detached devices are excluded. */
  fun linkedDevices(presetId: String): List<Device> {
    if (presetId.isEmpty()) return emptyList()
    return AppData.dbHelper.all.filter { device ->
      !device.sessionOnly && (device.presetId ?: "") == presetId
    }
  }

  /** Devices with this presetId (manual stream edits clear the link). */
  fun linkedCount(presetId: String): Int = linkedDevices(presetId).size

  /** Copy preset fields onto all devices still linked to [preset.id]. Returns updated count. */
  fun updateLinkedDevices(preset: ConnectionPreset): Int {
    val linked = linkedDevices(preset.id)
    for (device in linked) {
      preset.applyTo(device)
      AppData.dbHelper.update(device)
    }
    return linked.size
  }

  fun clearDeviceLinks(presetId: String) {
    for (device in linkedDevices(presetId)) {
      device.presetId = ""
      AppData.dbHelper.update(device)
    }
  }

  private fun ensureSeeded() {
    val list = readList().toMutableList()
    var changed = false
    for (factory in factoryBuiltIns()) {
      if (list.none { it.id == factory.id || it.builtInKey == factory.builtInKey }) {
        list.add(factory)
        changed = true
      }
    }
    if (changed) writeList(list)
    if (!prefs().contains(KEY_DEFAULT)) {
      setDefaultId(ConnectionPreset.ID_NORMAL_REMOTE)
    }
  }

  private fun factoryBuiltIns(): List<ConnectionPreset> {
    val ctx = AppData.applicationContext
    return listOf(
      ConnectionPreset.normalRemote(ctx.getString(R.string.preset_builtin_normal)),
      ConnectionPreset.cameraMonitor(ctx.getString(R.string.preset_builtin_camera)),
      ConnectionPreset.singleApp(ctx.getString(R.string.preset_builtin_single_app)),
    )
  }

  private fun factoryByKey(key: String): ConnectionPreset? {
    val ctx = AppData.applicationContext
    return when (key) {
      ConnectionPreset.KEY_NORMAL_REMOTE ->
        ConnectionPreset.normalRemote(ctx.getString(R.string.preset_builtin_normal))
      ConnectionPreset.KEY_CAMERA_MONITOR ->
        ConnectionPreset.cameraMonitor(ctx.getString(R.string.preset_builtin_camera))
      ConnectionPreset.KEY_SINGLE_APP ->
        ConnectionPreset.singleApp(ctx.getString(R.string.preset_builtin_single_app))
      else -> null
    }
  }

  private fun readList(): List<ConnectionPreset> {
    val raw = prefs().getString(KEY_LIST, null) ?: return emptyList()
    return try {
      val arr = JSONArray(raw)
      buildList {
        for (i in 0 until arr.length()) {
          parse(arr.getJSONObject(i))?.let { add(it) }
        }
      }
    } catch (_: Exception) {
      emptyList()
    }
  }

  private fun writeList(list: List<ConnectionPreset>) {
    val arr = JSONArray()
    list.forEach { arr.put(toJson(it)) }
    prefs().edit().putString(KEY_LIST, arr.toString()).apply()
  }

  private fun toJson(p: ConnectionPreset): JSONObject = JSONObject().apply {
    put("id", p.id)
    put("name", p.name)
    put("builtInKey", p.builtInKey ?: JSONObject.NULL)
    put("videoSource", p.videoSource)
    put("cameraFacing", p.cameraFacing)
    put("startApp", p.startApp)
    put("virtualWidth", p.virtualWidth)
    put("virtualHeight", p.virtualHeight)
    put("virtualDpi", p.virtualDpi)
    put("isAudio", p.isAudio)
    put("listenClip", p.listenClip)
    put("maxSize", p.maxSize)
    put("maxFps", p.maxFps)
    put("maxVideoBit", p.maxVideoBit)
    put("useH265", p.useH265)
    put("hevcProfile", ConnectionPreset.normalizeHevcProfile(p.hevcProfile))
    put("keepWakeOnRunning", p.keepWakeOnRunning)
    put("changeToFullOnConnect", p.changeToFullOnConnect)
    put("wakeOnConnect", p.wakeOnConnect)
    put("lightOffOnConnect", p.lightOffOnConnect)
    put("showNavBarOnConnect", p.showNavBarOnConnect)
  }

  private fun parse(o: JSONObject): ConnectionPreset? {
    val id = o.optString("id", "")
    if (id.isEmpty()) return null
    return ConnectionPreset(
      id = id,
      name = o.optString("name", id),
      builtInKey = when {
        !o.has("builtInKey") || o.isNull("builtInKey") -> null
        else -> o.optString("builtInKey").takeIf { it.isNotEmpty() }
      },
      videoSource = o.optString("videoSource", "display"),
      cameraFacing = o.optString("cameraFacing", "back"),
      startApp = o.optString("startApp", ""),
      virtualWidth = o.optInt("virtualWidth", 0),
      virtualHeight = o.optInt("virtualHeight", 0),
      virtualDpi = o.optInt("virtualDpi", 0),
      isAudio = o.optBoolean("isAudio", false),
      listenClip = o.optBoolean("listenClip", true),
      maxSize = o.optInt("maxSize", 1600),
      maxFps = o.optInt("maxFps", 60),
      maxVideoBit = o.optInt("maxVideoBit", 4),
      useH265 = o.optBoolean("useH265", true),
      hevcProfile = ConnectionPreset.normalizeHevcProfile(o.optString("hevcProfile", "main")),
      keepWakeOnRunning = o.optBoolean("keepWakeOnRunning", true),
      changeToFullOnConnect = o.optBoolean("changeToFullOnConnect", false),
      wakeOnConnect = o.optBoolean("wakeOnConnect", true),
      lightOffOnConnect = o.optBoolean("lightOffOnConnect", false),
      showNavBarOnConnect = o.optBoolean("showNavBarOnConnect", true),
    )
  }
}
