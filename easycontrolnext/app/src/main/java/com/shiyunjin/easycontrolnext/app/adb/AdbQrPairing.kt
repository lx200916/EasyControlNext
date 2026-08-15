package com.shiyunjin.easycontrolnext.app.adb

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import java.security.SecureRandom
import kotlin.math.max

/**
 * Android Studio / AOSP wireless-debug QR pairing payload:
 * `WIFI:T:ADB;S:<service-name>;P:<password>;;`
 *
 * Official AOSP QR has **no IP, pairing port, or connect port**. After the phone
 * scans it, the controller learns the pair endpoint from `_adb-tls-pairing._tcp`
 * and the ADB connect port from `_adb-tls-connect._tcp`.
 *
 * [parse] also accepts a few unofficial extras (`H`/`HOST`, `C`/`PORT`/`ADBPORT`,
 * `PAIRPORT`) and `PAIRING:host:pairPort:code` / `ipv4:pairPort:6digits` text.
 * Those still do not appear on stock Android wireless-debug QR codes.
 */
object AdbQrPairing {

  data class Credentials(
    val serviceName: String,
    val password: String,
  ) {
    val payload: String
      get() = "WIFI:T:ADB;S:$serviceName;P:$password;;"
  }

  data class Parsed(
    val serviceName: String,
    val password: String,
    val host: String? = null,
    val pairPort: Int? = null,
    val connectPort: Int? = null,
  )

  fun generate(): Credentials {
    val random = SecureRandom()
    val serviceName = "easycontrol-" + random.nextInt(1_000_000).toString().padStart(6, '0')
    val password = buildString {
      repeat(6) { append(random.nextInt(10)) }
    }
    return Credentials(serviceName, password)
  }

  fun parse(raw: String): Parsed? {
    val text = raw.trim()
    if (text.isEmpty()) return null
    return parseWifiAdb(text) ?: parsePairingText(text)
  }

  private fun parseWifiAdb(text: String): Parsed? {
    if (!text.regionMatches(0, "WIFI:", 0, 5, ignoreCase = true)) return null
    val body = text.substring(5)
    val parts = body.split(';').map { it.trim() }.filter { it.isNotEmpty() }
    var type: String? = null
    var service: String? = null
    var password: String? = null
    var host: String? = null
    var pairPort: Int? = null
    var connectPort: Int? = null
    for (part in parts) {
      val idx = part.indexOf(':')
      if (idx <= 0) continue
      val key = part.substring(0, idx)
      val value = part.substring(idx + 1)
      when (key.uppercase()) {
        "T" -> type = value
        "S" -> service = value
        "P" -> password = value
        "H", "HOST" -> host = value.trim().ifBlank { null }
        "PAIRPORT" -> pairPort = value.toIntOrNull()?.takeIf { it in 1..65535 }
        "C", "PORT", "ADBPORT" -> connectPort = value.toIntOrNull()?.takeIf { it in 1..65535 }
      }
    }
    if (!type.equals("ADB", ignoreCase = true)) return null
    if (service.isNullOrBlank() || password.isNullOrBlank()) return null
    return Parsed(service, password, host, pairPort, connectPort)
  }

  /** Unofficial `PAIRING:host:pairPort:code` or `ipv4:pairPort:6digits`. */
  private fun parsePairingText(text: String): Parsed? {
    val body = if (text.uppercase().startsWith("PAIRING:")) text.substring(8) else text
    val match = IPV4_PAIR_TEXT.matchEntire(body) ?: return null
    val host = match.groupValues[1]
    val pairPort = match.groupValues[2].toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
    val password = match.groupValues[3]
    return Parsed(
      serviceName = "",
      password = password,
      host = host,
      pairPort = pairPort,
      connectPort = null,
    )
  }

  private val IPV4_PAIR_TEXT = Regex("""^(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5}):(\d{6})$""")

  fun encodeBitmap(content: String, sizePx: Int = 768): Bitmap {
    val size = max(256, sizePx)
    val hints = mapOf(
      EncodeHintType.CHARACTER_SET to "UTF-8",
      EncodeHintType.MARGIN to 1,
    )
    val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) {
      for (y in 0 until size) {
        bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
      }
    }
    return bitmap
  }
}
