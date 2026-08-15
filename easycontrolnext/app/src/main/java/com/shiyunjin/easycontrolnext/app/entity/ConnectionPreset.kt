package com.shiyunjin.easycontrolnext.app.entity

/**
 * Connection / mirroring preset: stream and session options that map onto [Device]
 * (and server [com.shiyunjin.easycontrolnext.server.entity.Options]).
 * Does not include device identity (name, address, ports, pairing).
 */
data class ConnectionPreset(
  val id: String,
  val name: String,
  /** Non-null for shipped templates; used to re-seed / reset. */
  val builtInKey: String? = null,
  val videoSource: String = "display",
  val cameraFacing: String = "back",
  val startApp: String = "",
  val virtualWidth: Int = 0,
  val virtualHeight: Int = 0,
  val virtualDpi: Int = 0,
  val isAudio: Boolean = false,
  val listenClip: Boolean = true,
  val maxSize: Int = 1600,
  val maxFps: Int = 60,
  val maxVideoBit: Int = 4,
  val useH265: Boolean = true,
  /** auto | main | main10 — default main (8-bit). */
  val hevcProfile: String = "main",
  val keepWakeOnRunning: Boolean = true,
  val changeToFullOnConnect: Boolean = false,
  val wakeOnConnect: Boolean = true,
  val lightOffOnConnect: Boolean = false,
  val showNavBarOnConnect: Boolean = true,
) {
  val isBuiltIn: Boolean get() = builtInKey != null

  fun applyTo(device: Device) {
    device.videoSource = if (videoSource == "camera") "camera" else "display"
    device.cameraFacing = if (cameraFacing == "front") "front" else "back"
    device.startApp = if (device.videoSource == "camera") "" else (startApp ?: "")
    device.virtualWidth = virtualWidth
    device.virtualHeight = virtualHeight
    device.virtualDpi = virtualDpi
    device.isAudio = isAudio
    device.listenClip = listenClip
    device.maxSize = maxSize
    device.maxFps = maxFps
    device.maxVideoBit = maxVideoBit
    device.useH265 = useH265
    device.hevcProfile = normalizeHevcProfile(hevcProfile)
    device.keepWakeOnRunning = keepWakeOnRunning
    device.changeToFullOnConnect = changeToFullOnConnect
    device.wakeOnConnect = wakeOnConnect
    device.lightOffOnConnect = lightOffOnConnect
    device.showNavBarOnConnect = showNavBarOnConnect
    device.presetId = id
  }

  /** True when device stream fields still match this preset (linked & in sync). */
  fun matchesDevice(device: Device): Boolean {
    val vs = if (videoSource == "camera") "camera" else "display"
    val facing = if (cameraFacing == "front") "front" else "back"
    val app = if (vs == "camera") "" else (startApp ?: "")
    return (device.videoSource ?: "display") == vs &&
      (device.cameraFacing ?: "back") == facing &&
      (device.startApp ?: "") == app &&
      device.virtualWidth == virtualWidth &&
      device.virtualHeight == virtualHeight &&
      device.virtualDpi == virtualDpi &&
      device.isAudio == isAudio &&
      device.listenClip == listenClip &&
      device.maxSize == maxSize &&
      device.maxFps == maxFps &&
      device.maxVideoBit == maxVideoBit &&
      device.useH265 == useH265 &&
      normalizeHevcProfile(device.hevcProfile) == normalizeHevcProfile(hevcProfile) &&
      device.keepWakeOnRunning == keepWakeOnRunning &&
      device.changeToFullOnConnect == changeToFullOnConnect &&
      device.wakeOnConnect == wakeOnConnect &&
      device.lightOffOnConnect == lightOffOnConnect &&
      device.showNavBarOnConnect == showNavBarOnConnect
  }

  companion object {
    const val KEY_NORMAL_REMOTE = "normal_remote"
    const val KEY_CAMERA_MONITOR = "camera_monitor"
    const val KEY_SINGLE_APP = "single_app"
    const val KEY_WEAK_NETWORK = "weak_network"

    const val ID_NORMAL_REMOTE = "builtin_normal_remote"
    const val ID_CAMERA_MONITOR = "builtin_camera_monitor"
    const val ID_SINGLE_APP = "builtin_single_app"
    const val ID_WEAK_NETWORK = "builtin_weak_network"

    fun normalizeHevcProfile(value: String?): String {
      val v = value?.trim()?.lowercase().orEmpty()
      return when (v) {
        "auto", "main10", "main" -> v
        else -> "main"
      }
    }

    fun normalRemote(name: String) = ConnectionPreset(
      id = ID_NORMAL_REMOTE,
      name = name,
      builtInKey = KEY_NORMAL_REMOTE,
      videoSource = "display",
      cameraFacing = "back",
      startApp = "",
      virtualWidth = 0,
      virtualHeight = 0,
      virtualDpi = 0,
      isAudio = false,
      listenClip = true,
      maxSize = 1600,
      maxFps = 60,
      maxVideoBit = 4,
      useH265 = true,
      hevcProfile = "main",
      keepWakeOnRunning = true,
      changeToFullOnConnect = false,
      wakeOnConnect = true,
      lightOffOnConnect = false,
      showNavBarOnConnect = true,
    )

    fun cameraMonitor(name: String) = ConnectionPreset(
      id = ID_CAMERA_MONITOR,
      name = name,
      builtInKey = KEY_CAMERA_MONITOR,
      videoSource = "camera",
      cameraFacing = "back",
      startApp = "",
      virtualWidth = 0,
      virtualHeight = 0,
      virtualDpi = 0,
      isAudio = false,
      listenClip = false,
      maxSize = 1280,
      maxFps = 30,
      maxVideoBit = 4,
      useH265 = true,
      hevcProfile = "main",
      keepWakeOnRunning = true,
      changeToFullOnConnect = true,
      wakeOnConnect = true,
      lightOffOnConnect = false,
      showNavBarOnConnect = true,
    )

    fun singleApp(name: String) = ConnectionPreset(
      id = ID_SINGLE_APP,
      name = name,
      builtInKey = KEY_SINGLE_APP,
      videoSource = "display",
      cameraFacing = "back",
      startApp = "", // placeholder: pick package when applying / editing device
      virtualWidth = 0,
      virtualHeight = 0,
      virtualDpi = 0,
      isAudio = false,
      listenClip = true,
      maxSize = 1600,
      maxFps = 60,
      maxVideoBit = 4,
      useH265 = true,
      hevcProfile = "main",
      keepWakeOnRunning = true,
      changeToFullOnConnect = false,
      wakeOnConnect = true,
      lightOffOnConnect = false,
      showNavBarOnConnect = true,
    )

    /** Poor-network preset: chase live edge (1280 / 30fps / 2Mbps / HEVC Main / no audio). */
    fun weakNetwork(name: String) = ConnectionPreset(
      id = ID_WEAK_NETWORK,
      name = name,
      builtInKey = KEY_WEAK_NETWORK,
      videoSource = "display",
      cameraFacing = "back",
      startApp = "",
      virtualWidth = 0,
      virtualHeight = 0,
      virtualDpi = 0,
      isAudio = false,
      listenClip = true,
      maxSize = 1280,
      maxFps = 30,
      maxVideoBit = 2,
      useH265 = true,
      hevcProfile = "main",
      keepWakeOnRunning = true,
      changeToFullOnConnect = false,
      wakeOnConnect = true,
      lightOffOnConnect = false,
      showNavBarOnConnect = true,
    )
  }
}
