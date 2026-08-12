package com.shiyunjin.easycontrolnext.app.ui

import com.shiyunjin.easycontrolnext.app.client.tools.AdbTools
import com.shiyunjin.easycontrolnext.app.entity.AppData
import com.shiyunjin.easycontrolnext.app.entity.Device
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Shared device list for Compose UI + legacy broadcast updates.
 */
object DeviceListStore {
  private val _devices = MutableStateFlow<List<Device>>(emptyList())
  val devices: StateFlow<List<Device>> = _devices.asStateFlow()

  @JvmStatic
  fun refresh() {
    if (AppData.dbHelper == null) {
      _devices.value = emptyList()
      return
    }
    val raw = AppData.dbHelper.getAll()
    val link = ArrayList<Device>()
    val network = ArrayList<Device>()
    for (device in raw) {
      if (device.isLinkDevice && AdbTools.usbDevicesList.containsKey(device.address)) {
        link.add(device)
      } else if (device.isNetworkDevice) {
        network.add(device)
      }
    }
    AdbTools.devicesList.clear()
    AdbTools.devicesList.addAll(link)
    AdbTools.devicesList.addAll(network)
    _devices.value = ArrayList(AdbTools.devicesList)
  }
}
