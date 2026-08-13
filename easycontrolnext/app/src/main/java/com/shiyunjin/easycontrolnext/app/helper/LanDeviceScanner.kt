package com.shiyunjin.easycontrolnext.app.helper

import android.content.Context
import com.shiyunjin.easycontrolnext.app.adb.AdbServiceDiscovery
import com.shiyunjin.easycontrolnext.app.entity.AppData
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Find candidate controlled devices on the LAN.
 * Prefers mDNS wireless-debug services; also probes common ADB ports on the subnet.
 */
object LanDeviceScanner {

  data class Result(
    val host: String,
    val port: Int?,
    val label: String,
    val source: String,
  )

  fun scan(context: Context, timeoutMs: Long = 4500): List<Result> {
    val byKey = ConcurrentHashMap<String, Result>()

    // 1) mDNS TLS connect (Android 11+ wireless debugging)
    try {
      val connects = AdbServiceDiscovery.discover(
        context,
        AdbServiceDiscovery.Type.CONNECT,
        timeoutMs,
        null,
      )
      for (ep in connects) {
        val key = "${ep.host}:${ep.port}"
        byKey[key] = Result(
          host = ep.host,
          port = ep.port,
          label = "${ep.host}:${ep.port}  (无线调试)",
          source = "mdns-connect",
        )
      }
    } catch (_: Exception) {
    }

    // 2) mDNS TLS pairing (device currently showing pair UI)
    try {
      val pairings = AdbServiceDiscovery.discover(
        context,
        AdbServiceDiscovery.Type.PAIRING,
        timeoutMs / 2,
        null,
      )
      for (ep in pairings) {
        val key = "pair-${ep.host}:${ep.port}"
        byKey.putIfAbsent(
          key,
          Result(
            host = ep.host,
            port = ep.port,
            label = "${ep.host}:${ep.port}  (配对中)",
            source = "mdns-pairing",
          ),
        )
      }
    } catch (_: Exception) {
    }

    // 3) Subnet probe on classic 5555 + a quick check that host is up via TCP
    val localIps = localIpv4Addresses()
    val executor = Executors.newFixedThreadPool(64)
    for (local in localIps) {
      val subnet = local.substringBeforeLast('.', missingDelimiterValue = "")
      if (subnet.isEmpty()) continue
      for (i in 1..254) {
        val host = "$subnet.$i"
        executor.execute {
          // Prefer already-found mDNS hosts; still probe 5555 for older adb tcpip
          if (probePort(host, 5555, 350)) {
            val suffix = if (host == local) " (本机)" else " (5555)"
            byKey.putIfAbsent(
              "$host:5555",
              Result(host, 5555, "$host$suffix", "tcp-5555"),
            )
          }
        }
      }
    }
    executor.shutdown()
    try {
      executor.awaitTermination(timeoutMs, TimeUnit.MILLISECONDS)
    } catch (_: InterruptedException) {
      Thread.currentThread().interrupt()
    }

    return byKey.values
      .sortedWith(compareBy<Result> { if (it.source.startsWith("mdns")) 0 else 1 }.thenBy { it.host })
  }

  private fun probePort(host: String, port: Int, timeoutMs: Int): Boolean {
    return try {
      Socket().use { socket ->
        socket.connect(InetSocketAddress(host, port), timeoutMs)
      }
      true
    } catch (_: Exception) {
      false
    }
  }

  private fun localIpv4Addresses(): List<String> {
    val list = ArrayList<String>()
    try {
      for (nif in Collections.list(NetworkInterface.getNetworkInterfaces())) {
        if (!nif.isUp || nif.isLoopback) continue
        for (addr in Collections.list(nif.inetAddresses)) {
          if (addr is Inet4Address && !addr.isLoopbackAddress) {
            addr.hostAddress?.let { list.add(it) }
          }
        }
      }
    } catch (_: Exception) {
    }
    if (list.isEmpty()) {
      try {
        val pair = PublicTools.getLocalIp()
        list.addAll(pair.first)
      } catch (_: Exception) {
      }
    }
    return list
  }
}
