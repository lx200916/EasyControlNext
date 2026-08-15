package com.shiyunjin.easycontrolnext.app.adb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address
import java.net.InetAddress
import java.util.ArrayDeque
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
    val finished = AtomicBoolean(false)
    val latch = CountDownLatch(1)
    val mainHandler = Handler(Looper.getMainLooper())
    val pending = ArrayDeque<NsdServiceInfo>()
    val resolving = AtomicBoolean(false)

    fun accept(info: NsdServiceInfo) {
      if (finished.get()) return
      val name = info.serviceName ?: return
      if (!serviceNameMatches(name, serviceNameFilter)) return
      val ip = preferredHost(hostsOf(info)) ?: return
      val port = info.port
      if (port <= 0) return
      synchronized(lock) {
        found["$ip:$port:$name"] = Endpoint(ip, port, name, type)
      }
      if (!serviceNameFilter.isNullOrBlank()) {
        latch.countDown()
      }
    }

    fun pumpResolve() {
      if (finished.get()) return
      val next: NsdServiceInfo
      synchronized(lock) {
        if (resolving.get()) return
        val queued = pending.pollFirst() ?: return
        resolving.set(true)
        next = queued
      }
      // NsdManager.resolveService cannot reuse one listener; serialize in-flight resolves.
      val listener = object : NsdManager.ResolveListener {
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
          resolving.set(false)
          pumpResolve()
        }

        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
          accept(serviceInfo)
          resolving.set(false)
          pumpResolve()
        }
      }
      val start = Runnable {
        try {
          @Suppress("DEPRECATION")
          nsd.resolveService(next, listener)
        } catch (_: Exception) {
          resolving.set(false)
          pumpResolve()
        }
      }
      if (Looper.myLooper() == Looper.getMainLooper()) start.run()
      else mainHandler.post(start)
    }

    val discoveryListener = object : NsdManager.DiscoveryListener {
      override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
        latch.countDown()
      }

      override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
      override fun onDiscoveryStarted(serviceType: String) {}
      override fun onDiscoveryStopped(serviceType: String) {}

      override fun onServiceFound(serviceInfo: NsdServiceInfo) {
        if (finished.get()) return
        val name = serviceInfo.serviceName ?: return
        if (!serviceNameMatches(name, serviceNameFilter)) return
        synchronized(lock) { pending.addLast(serviceInfo) }
        pumpResolve()
      }

      override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
    }

    try {
      nsd.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
      latch.await(timeoutMs.coerceAtLeast(500L), TimeUnit.MILLISECONDS)
      // Resolves often finish after the discover window; keep collecting briefly.
      try {
        Thread.sleep(700)
      } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
      }
    } catch (_: Exception) {
    } finally {
      finished.set(true)
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
    if (all.isEmpty()) return null
    if (host.isNullOrBlank()) return all.firstOrNull()
    all.firstOrNull { hostsMatch(it.host, host) }?.let { return it }
    val want = normalizeHost(host)
    if (want.count { it == '.' } == 3) {
      val prefix = want.substringBeforeLast('.')
      all.firstOrNull { normalizeHost(it.host).startsWith("$prefix.") }?.let { return it }
    }
    return all.firstOrNull()
  }

  fun hostsMatch(a: String?, b: String?): Boolean {
    if (a.isNullOrBlank() || b.isNullOrBlank()) return false
    if (a.equals(b, ignoreCase = true)) return true
    val na = normalizeHost(a)
    val nb = normalizeHost(b)
    if (na.equals(nb, ignoreCase = true)) return true
    return try {
      InetAddress.getByName(na) == InetAddress.getByName(nb)
    } catch (_: Exception) {
      false
    }
  }

  fun normalizeHost(host: String): String {
    var h = host.trim()
    if (h.startsWith("[") && h.endsWith("]")) {
      h = h.substring(1, h.length - 1)
    }
    val zone = h.indexOf('%')
    if (zone > 0) h = h.substring(0, zone)
    if (h.startsWith("::ffff:") || h.startsWith("::FFFF:")) {
      h = h.substring(7)
    }
    return h
  }

  private fun serviceNameMatches(name: String, filter: String?): Boolean {
    if (filter.isNullOrBlank()) return true
    return name.equals(filter, ignoreCase = true) || name.contains(filter, ignoreCase = true)
  }

  private fun hostsOf(info: NsdServiceInfo): List<InetAddress> {
    val out = ArrayList<InetAddress>()
    if (Build.VERSION.SDK_INT >= 34) {
      try {
        out.addAll(info.hostAddresses)
      } catch (_: Exception) {
      }
    }
    @Suppress("DEPRECATION")
    info.host?.let { addr ->
      if (out.none { it == addr }) out.add(addr)
    }
    return out
  }

  private fun preferredHost(addrs: List<InetAddress>): String? {
    addrs.firstOrNull { it is Inet4Address }?.hostAddress?.let { return it }
    return addrs.firstOrNull()?.hostAddress
  }
}
