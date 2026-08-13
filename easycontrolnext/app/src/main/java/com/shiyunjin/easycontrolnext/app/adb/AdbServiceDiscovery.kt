package com.shiyunjin.easycontrolnext.app.adb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import java.net.Inet4Address
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Discover remote ADB wireless-debug services without the broken "same local IP" filter
 * used by the vendored AdbMdns helper.
 */
object AdbServiceDiscovery {

  data class Endpoint(
    val host: String,
    val port: Int,
    val serviceName: String,
    val type: Type,
  )

  enum class Type { PAIRING, CONNECT }

  fun discover(
    context: Context,
    type: Type,
    timeoutMs: Long,
    serviceNameFilter: String? = null,
  ): List<Endpoint> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN) return emptyList()
    val serviceType = when (type) {
      Type.PAIRING -> "_adb-tls-pairing._tcp."
      Type.CONNECT -> "_adb-tls-connect._tcp."
    }
    val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    val found = LinkedHashMap<String, Endpoint>()
    val lock = Any()
    val done = AtomicBoolean(false)
    val latch = CountDownLatch(1)

    val resolveListener = object : NsdManager.ResolveListener {
      override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}

      override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
        if (done.get()) return
        val name = serviceInfo.serviceName ?: return
        if (!serviceNameFilter.isNullOrBlank() &&
          !name.equals(serviceNameFilter, ignoreCase = true) &&
          !name.contains(serviceNameFilter, ignoreCase = true)
        ) {
          return
        }
        val host = serviceInfo.host ?: return
        // Prefer IPv4
        val ip = if (host is Inet4Address) {
          host.hostAddress
        } else {
          host.hostAddress
        } ?: return
        val port = serviceInfo.port
        if (port <= 0) return
        synchronized(lock) {
          found["$ip:$port:$name"] = Endpoint(ip, port, name, type)
        }
        if (!serviceNameFilter.isNullOrBlank()) {
          done.set(true)
          latch.countDown()
        }
      }
    }

    val discoveryListener = object : NsdManager.DiscoveryListener {
      override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
        latch.countDown()
      }

      override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
      override fun onDiscoveryStarted(serviceType: String) {}
      override fun onDiscoveryStopped(serviceType: String) {}

      override fun onServiceFound(serviceInfo: NsdServiceInfo) {
        if (done.get()) return
        val name = serviceInfo.serviceName ?: return
        if (!serviceNameFilter.isNullOrBlank() &&
          !name.equals(serviceNameFilter, ignoreCase = true) &&
          !name.contains(serviceNameFilter, ignoreCase = true)
        ) {
          return
        }
        try {
          nsd.resolveService(serviceInfo, resolveListener)
        } catch (_: Exception) {
        }
      }

      override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
    }

    try {
      nsd.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
      latch.await(timeoutMs, TimeUnit.MILLISECONDS)
    } catch (_: Exception) {
    } finally {
      done.set(true)
      try {
        nsd.stopServiceDiscovery(discoveryListener)
      } catch (_: Exception) {
      }
    }
    synchronized(lock) {
      return found.values.toList()
    }
  }

  fun discoverFirstPairing(
    context: Context,
    serviceName: String,
    timeoutMs: Long,
  ): Endpoint? {
    return discover(context, Type.PAIRING, timeoutMs, serviceName).firstOrNull()
      ?: discover(context, Type.PAIRING, 1500, serviceName).firstOrNull()
  }

  fun discoverConnectForHost(
    context: Context,
    host: String?,
    timeoutMs: Long,
  ): Endpoint? {
    val all = discover(context, Type.CONNECT, timeoutMs, null)
    if (host.isNullOrBlank()) return all.firstOrNull()
    return all.firstOrNull { it.host == host } ?: all.firstOrNull()
  }
}
