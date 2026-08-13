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
 * WIFI:T:ADB;S:<service-name>;P:<password>;;
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
    if (!text.uppercase().startsWith("WIFI:")) return null
    // WIFI:T:ADB;S:name;P:pass;;
    val body = text.removePrefix("WIFI:").removePrefix("wifi:")
    val parts = body.split(';').map { it.trim() }.filter { it.isNotEmpty() }
    var type: String? = null
    var service: String? = null
    var password: String? = null
    for (part in parts) {
      val idx = part.indexOf(':')
      if (idx <= 0) continue
      val key = part.substring(0, idx)
      val value = part.substring(idx + 1)
      when (key.uppercase()) {
        "T" -> type = value
        "S" -> service = value
        "P" -> password = value
      }
    }
    if (!type.equals("ADB", ignoreCase = true)) return null
    if (service.isNullOrBlank() || password.isNullOrBlank()) return null
    return Parsed(service, password)
  }

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
