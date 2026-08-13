package com.shiyunjin.easycontrolnext.app.client.tools;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.os.Build;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.shiyunjin.easycontrolnext.app.BuildConfig;
import com.shiyunjin.easycontrolnext.app.R;
import com.shiyunjin.easycontrolnext.app.adb.Adb;
import com.shiyunjin.easycontrolnext.app.adb.AdbConnectionManager;
import com.shiyunjin.easycontrolnext.app.adb.AdbServiceDiscovery;
import com.shiyunjin.easycontrolnext.app.entity.AppData;
import com.shiyunjin.easycontrolnext.app.entity.Device;
import com.shiyunjin.easycontrolnext.app.entity.Setting;
import com.shiyunjin.easycontrolnext.app.entity.MyInterface;
import com.shiyunjin.easycontrolnext.app.helper.PublicTools;

import io.github.muntashirakon.adb.AbsAdbConnectionManager;
import io.github.muntashirakon.adb.AdbAuthenticationFailedException;
import io.github.muntashirakon.adb.AdbPairingRequiredException;

public class AdbTools {
  private static final HashMap<String, Adb> allAdbConnect = new HashMap<>();
  public static final ArrayList<Device> devicesList = new ArrayList<>();
  public static final HashMap<String, UsbDevice> usbDevicesList = new HashMap<>();

  /** Normalize Android wireless-debug pairing code (may contain spaces). */
  public static String normalizePairCode(String pairCode) {
    if (pairCode == null) return "";
    return pairCode.replaceAll("\\s+", "").trim();
  }

  /**
   * Pair with a device over wireless debugging (Android 11+).
   * Uses the temporary pairing port + 6-digit code from
   * Developer options → Wireless debugging → Pair with pairing code.
   */
  public static void pairWireless(String host, int pairPort, String pairCode) throws Exception {
    String code = normalizePairCode(pairCode);
    if (pairPort <= 0 || pairPort > 65535) {
      throw new Exception("配对端口无效（请填「使用配对码配对」弹窗里的端口，不是连接端口）");
    }
    if (code.isEmpty()) {
      throw new Exception("配对码/密码不能为空");
    }
    String ip = PublicTools.getIp(host);
    AbsAdbConnectionManager manager = AdbConnectionManager.keyPairClient(AppData.keyPair);
    manager.setTimeout(20, TimeUnit.SECONDS);
    try {
      manager.pair(ip, pairPort, code);
    } catch (Exception e) {
      throw new Exception("无线配对失败: " + rootMessage(e)
          + "。请确认配对码弹窗仍开着，且配对端口/IP 正确。", e);
    }
  }

  /**
   * After controller shows AOSP QR (WIFI:T:ADB;S:...;P:...;;), wait for the controlled
   * phone to scan it, advertise pairing over mDNS, then pair and discover connect port.
   *
   * @return String[2] = { host, connectPort } — connectPort may be empty if not found
   */
  public static String[] pairWithQrCredentials(Context context, String serviceName, String password, long timeoutMs)
      throws Exception {
    if (context == null) throw new Exception("Context 为空");
    if (serviceName == null || serviceName.isEmpty()) throw new Exception("二维码服务名无效");
    if (password == null || password.isEmpty()) throw new Exception("二维码密码无效");

    AdbServiceDiscovery.Endpoint pairing = AdbServiceDiscovery.INSTANCE.discoverFirstPairing(
        context.getApplicationContext(), serviceName, timeoutMs);
    if (pairing == null) {
      throw new Exception("未发现被控机。请在被控机：开发者选项 → 无线调试 →「使用二维码配对」，扫描本页二维码，并保持同一 Wi‑Fi。");
    }
    pairWireless(pairing.getHost(), pairing.getPort(), password);

    AdbServiceDiscovery.Endpoint connect = AdbServiceDiscovery.INSTANCE.discoverConnectForHost(
        context.getApplicationContext(), pairing.getHost(), Math.max(4000L, timeoutMs / 2));
    String port = connect != null ? String.valueOf(connect.getPort()) : "";
    return new String[]{pairing.getHost(), port};
  }

  /**
   * Discover the TLS ADB connect port advertised via mDNS after pairing.
   * @return port or -1 if not found
   */
  public static int discoverTlsConnectPort(Context context, String expectedHost, long timeoutMs) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN) return -1;
    if (context == null) return -1;
    AdbServiceDiscovery.Endpoint ep = AdbServiceDiscovery.INSTANCE.discoverConnectForHost(
        context.getApplicationContext(), expectedHost, timeoutMs);
    return ep == null ? -1 : ep.getPort();
  }

  // 连接ADB
  public static Adb connectADB(Device device) throws Exception {
    String addressId = device.isLinkDevice() ? device.address : device.address + ":" + device.adbPort;
    Adb adb = allAdbConnect.get(addressId);
    if (adb == null || adb.isClosed()) {
      if (device.isLinkDevice()) {
        adb = new Adb(usbDevicesList.get(addressId), AppData.keyPair);
      } else {
        adb = connectNetworkAdb(device);
      }
      allAdbConnect.put(device.isLinkDevice() ? addressId : device.address + ":" + device.adbPort, adb);
    }
    return adb;
  }

  private static Adb connectNetworkAdb(Device device) throws Exception {
    AbsAdbConnectionManager manager = AdbConnectionManager.keyPairClient(AppData.keyPair);
    manager.setTimeout(15, TimeUnit.SECONDS);
    manager.setThrowOnUnauthorised(true);

    String ip = PublicTools.getIp(device.address);
    int probeTimeoutMs = AppData.setting != null
        ? AppData.setting.getReachabilityTimeoutMs()
        : Setting.REACHABILITY_TIMEOUT_DEFAULT_MS;
    String pairKey = normalizePairCode(device.pairKey);
    if (device.pairPort > 0 && !pairKey.isEmpty()) {
      requireReachable(ip, device.pairPort, probeTimeoutMs);
      try {
        manager.pair(ip, device.pairPort, pairKey);
        device.pairPort = 0;
        device.pairKey = "";
        if (!device.isTempDevice()) {
          AppData.dbHelper.update(device);
        }
      } catch (Exception e) {
        throw new Exception("无线配对失败: " + rootMessage(e)
            + "。配对端口必须来自「配对码」弹窗；连接端口来自无线调试主页顶部。", e);
      }
    }

    int connectPort = device.adbPort;
    if (connectPort <= 0) {
      throw new Exception("连接端口无效。请填写无线调试页面顶部的 IP:端口 中的端口（通常不是 5555）。");
    }

    requireReachable(ip, connectPort, probeTimeoutMs);

    try {
      manager.connect(ip, connectPort);
    } catch (AdbPairingRequiredException e) {
      throw new Exception("尚未配对。请先填写配对端口+配对码并配对，或点「仅配对」。", e);
    } catch (AdbAuthenticationFailedException e) {
      throw new Exception("ADB 未授权。请在被控机弹窗点「允许」，或重新配对。", e);
    } catch (Exception e) {
      // Common mistake: using pairing port / default 5555 as connect port on Android 11+
      int discovered = -1;
      try {
        discovered = discoverTlsConnectPort(AppData.applicationContext, ip, 2500);
      } catch (Exception ignored) {
      }
      if (discovered > 0 && discovered != connectPort) {
        try {
          AbsAdbConnectionManager retry = AdbConnectionManager.keyPairClient(AppData.keyPair);
          retry.setTimeout(15, TimeUnit.SECONDS);
          retry.setThrowOnUnauthorised(true);
          retry.connect(ip, discovered);
          device.adbPort = discovered;
          if (!device.isTempDevice()) {
            AppData.dbHelper.update(device);
          }
          return new Adb(retry);
        } catch (Exception retryError) {
          throw new Exception("连接失败（端口 " + connectPort + "）。已尝试自动发现端口 "
              + discovered + " 仍失败: " + rootMessage(retryError)
              + "。请核对无线调试主页顶部的连接端口。", retryError);
        }
      }
      throw new Exception("连接失败（" + ip + ":" + connectPort + "）: " + rootMessage(e)
          + "。Android 11+ 请用无线调试主页顶部的端口，不要用配对弹窗端口，也不要默认填 5555。", e);
    }
    return new Adb(manager);
  }

  private static void requireReachable(String ip, int port, int timeoutMs) throws Exception {
    try {
      PublicTools.probeTcpReachable(ip, port, timeoutMs);
    } catch (Exception e) {
      if (Thread.currentThread().isInterrupted()) {
        throw e;
      }
      throw new Exception(AppData.applicationContext.getString(
          R.string.toast_host_unreachable, ip, port, timeoutMs), e);
    }
  }

  private static String rootMessage(Throwable e) {
    Throwable cur = e;
    String msg = e.getMessage();
    while (cur.getCause() != null) {
      cur = cur.getCause();
      if (cur.getMessage() != null && !cur.getMessage().isEmpty()) msg = cur.getMessage();
    }
    return msg == null ? e.getClass().getSimpleName() : msg;
  }

  public static void runOnceCmd(Device device, String cmd, MyInterface.MyFunctionBoolean handle) {
    new Thread(() -> {
      try {
        Adb adb = connectADB(device);
        adb.runAdbCmd(cmd);
        handle.run(true);
      } catch (Exception ignored) {
        handle.run(false);
      }
    }).start();
  }

  public static void restartOnTcpip(Device device, MyInterface.MyFunctionBoolean handle) {
    new Thread(() -> {
      try {
        Adb adb = connectADB(device);
        String output = adb.restartOnTcpip(5555);
        handle.run(output.contains("restarting"));
      } catch (Exception ignored) {
        handle.run(false);
      }
    }).start();
  }

  /** Installed app entry for Compose picker (label + package). */
  public static final class InstalledApp {
    public final String label;
    public final String packageName;

    public InstalledApp(String label, String packageName) {
      this.label = label == null || label.isEmpty() ? packageName : label;
      this.packageName = packageName;
    }
  }

  private static final String SERVER_JAR =
    "/data/local/tmp/easycontrolnext_server_" + BuildConfig.VERSION_CODE + ".jar";

  /**
   * List installed packages via ADB for the device being edited / managed.
   * Primary: on-device {@code ListApps} via PackageManager (resolved labels).
   * Fallback: {@code pm list packages} + dumpsys / launcher query enrichment.
   */
  public static List<InstalledApp> listInstalledApps(Device device, boolean includeSystem) throws Exception {
    if (device == null) throw new Exception("设备为空");
    if (!device.isLinkDevice()) {
      if (device.address == null || device.address.trim().isEmpty()) {
        throw new Exception("先填写 IP 与连接端口并确保已配对");
      }
      if (device.adbPort <= 0) {
        throw new Exception("先填写 IP 与连接端口并确保已配对");
      }
    }
    Adb adb = connectADB(device);

    try {
      List<InstalledApp> viaPm = listAppsViaPackageManager(adb, includeSystem);
      if (!viaPm.isEmpty()) return viaPm;
    } catch (Exception ignored) {
      // fall through to shell fallback
    }

    return listAppsViaShellFallback(adb, includeSystem);
  }

  /** Push server jar if needed, then run ListApps with real PackageManager labels. */
  private static List<InstalledApp> listAppsViaPackageManager(Adb adb, boolean includeSystem) throws Exception {
    ensureServerJar(adb);
    String cmd = "app_process -Djava.class.path=" + SERVER_JAR
      + " / com.shiyunjin.easycontrolnext.server.helper.ListApps includeSystem="
      + (includeSystem ? "1" : "0");
    String out = adb.runAdbCmd(cmd);
    List<InstalledApp> apps = parseListAppsOutput(out);
    if (apps.isEmpty()) {
      throw new Exception("ListApps returned empty");
    }
    Collections.sort(apps, INSTALLED_APP_COMPARATOR);
    return apps;
  }

  private static void ensureServerJar(Adb adb) throws Exception {
    if (BuildConfig.ENABLE_DEBUG_FEATURE || !adb.runAdbCmd("ls /data/local/tmp/easycontrolnext_*").contains(SERVER_JAR)) {
      adb.runAdbCmd("rm /data/local/tmp/easycontrolnext_* ");
      adb.pushFile(
        AppData.applicationContext.getResources().openRawResource(R.raw.easycontrolnext_server),
        SERVER_JAR,
        null
      );
    }
  }

  private static List<InstalledApp> parseListAppsOutput(String out) {
    List<InstalledApp> apps = new ArrayList<>();
    if (out == null || out.isEmpty()) return apps;
    for (String line : out.split("\n")) {
      String trimmed = line.trim();
      if (trimmed.isEmpty() || trimmed.startsWith("Error") || trimmed.startsWith("Exception")) continue;
      int tab = trimmed.indexOf('\t');
      if (tab <= 0) continue;
      String pkg = trimmed.substring(0, tab).trim();
      String label = trimmed.substring(tab + 1).trim();
      if (pkg.isEmpty() || !pkg.contains(".")) continue;
      apps.add(new InstalledApp(label, pkg));
    }
    return apps;
  }

  private static final Comparator<InstalledApp> INSTALLED_APP_COMPARATOR = new Comparator<InstalledApp>() {
    @Override
    public int compare(InstalledApp a, InstalledApp b) {
      int c = a.label.toLowerCase(Locale.ROOT).compareTo(b.label.toLowerCase(Locale.ROOT));
      if (c != 0) return c;
      return a.packageName.compareTo(b.packageName);
    }
  };

  /** Shell fallback when ListApps / server jar cannot run. */
  private static List<InstalledApp> listAppsViaShellFallback(Adb adb, boolean includeSystem) throws Exception {
    String listCmd = includeSystem ? "pm list packages" : "pm list packages -3";
    String listOut = adb.runAdbCmd(listCmd);
    List<String> packages = new ArrayList<>();
    Matcher pkgMatcher = Pattern.compile("package:(\\S+)").matcher(listOut);
    while (pkgMatcher.find()) {
      packages.add(pkgMatcher.group(1));
    }
    if (packages.isEmpty()) {
      throw new Exception("未获取到应用列表（超时或为空）");
    }

    Map<String, String> labels = new LinkedHashMap<>();

    // Full (non-brief) launcher query — may include nonLocalizedLabel
    try {
      String launcherOut = adb.runAdbCmd(
        "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER");
      enrichLabelsFromActivityDump(launcherOut, labels);
    } catch (Exception ignored) {
    }

    try {
      String dump = adb.runAdbCmd("dumpsys package");
      enrichLabelsFromPackageDump(dump, labels);
    } catch (Exception ignored) {
      try {
        String dump = adb.runAdbCmd(
          "dumpsys package packages | grep -E 'Package \\[|applicationLabel=|nonLocalizedLabel='");
        enrichLabelsFromPackageDump(dump, labels);
      } catch (Exception ignored2) {
      }
    }

    // aapt badging when available on device
    try {
      enrichLabelsFromAapt(adb, packages, labels);
    } catch (Exception ignored) {
    }

    List<InstalledApp> apps = new ArrayList<>(packages.size());
    for (String p : packages) {
      String label = labels.get(p);
      if (label == null || label.isEmpty() || label.equals("null")) {
        label = p;
      }
      apps.add(new InstalledApp(label, p));
    }
    Collections.sort(apps, INSTALLED_APP_COMPARATOR);
    return apps;
  }

  private static void enrichLabelsFromActivityDump(String dump, Map<String, String> labels) {
    if (dump == null) return;
    String currentPkg = null;
    for (String line : dump.split("\n")) {
      Matcher pkgLine = Pattern.compile("packageName=(\\S+)").matcher(line);
      if (pkgLine.find()) {
        currentPkg = pkgLine.group(1);
      }
      Matcher nl = Pattern.compile("nonLocalizedLabel=([^\\s]+)").matcher(line);
      if (nl.find() && currentPkg != null) {
        String label = nl.group(1).trim();
        if (!label.isEmpty() && !"null".equals(label) && isWeakLabel(labels.get(currentPkg), currentPkg)) {
          labels.put(currentPkg, label);
        }
      }
      Matcher al = Pattern.compile("applicationLabel=(.+)").matcher(line);
      if (al.find() && currentPkg != null) {
        String label = al.group(1).trim();
        if (!label.isEmpty() && !"null".equals(label)) {
          labels.put(currentPkg, label);
        }
      }
    }
  }

  private static void enrichLabelsFromPackageDump(String dump, Map<String, String> labels) {
    if (dump == null) return;
    String currentPkg = null;
    for (String line : dump.split("\n")) {
      Matcher pm = Pattern.compile("Package \\[([^]]+)]").matcher(line);
      if (pm.find()) {
        currentPkg = pm.group(1);
        continue;
      }
      if (currentPkg == null) continue;
      Matcher lm = Pattern.compile("(?:applicationLabel|nonLocalizedLabel)=(.+)").matcher(line);
      if (lm.find()) {
        String label = lm.group(1).trim();
        // nonLocalizedLabel=null icon=0x... — take first token
        int space = label.indexOf(' ');
        if (space > 0 && label.startsWith("null")) {
          continue;
        }
        if (space > 0 && !label.contains(" ")) {
          // keep full if no space; else if looks like "Foo icon=..." trim
        }
        if (label.contains(" icon=") || label.contains(" labelRes=")) {
          Matcher token = Pattern.compile("^(\\S+)").matcher(label);
          if (token.find()) label = token.group(1);
        }
        if (!label.isEmpty() && !"null".equals(label)
          && (isWeakLabel(labels.get(currentPkg), currentPkg) || line.contains("applicationLabel="))) {
          labels.put(currentPkg, label);
        }
      }
    }
  }

  private static boolean isWeakLabel(String label, String pkg) {
    return label == null || label.isEmpty() || label.equals(pkg)
      || (pkg != null && label.equals(pkg.substring(pkg.lastIndexOf('.') + 1)));
  }

  private static void enrichLabelsFromAapt(Adb adb, List<String> packages, Map<String, String> labels) throws Exception {
    String aaptCheck = adb.runAdbCmd(
      "command -v aapt || command -v aapt2 || ls /data/local/tmp/aapt 2>/dev/null || true");
    String aapt = null;
    for (String line : aaptCheck.split("\n")) {
      String t = line.trim();
      if (t.startsWith("/") || t.equals("aapt") || t.equals("aapt2")) {
        aapt = t;
        break;
      }
    }
    if (aapt == null || aapt.isEmpty()) return;

    String pathOut = adb.runAdbCmd("pm list packages -f");
    Map<String, String> apkPaths = new HashMap<>();
    Matcher m = Pattern.compile("package:(.+)=([\\w.]+)").matcher(pathOut);
    while (m.find()) {
      apkPaths.put(m.group(2), m.group(1));
    }

    int resolved = 0;
    for (String p : packages) {
      if (!isWeakLabel(labels.get(p), p)) continue;
      String apk = apkPaths.get(p);
      if (apk == null) continue;
      try {
        String badge = adb.runAdbCmd(aapt + " dump badging " + shellQuote(apk) + " 2>/dev/null | head -n 40");
        Matcher lm = Pattern.compile("application-label(?:-\\w+)?:['\"]([^'\"]+)['\"]").matcher(badge);
        if (lm.find()) {
          labels.put(p, lm.group(1).trim());
          resolved++;
        }
      } catch (Exception ignored) {
      }
      // Cap aapt calls — slow on large catalogs
      if (resolved >= 80) break;
    }
  }

  private static String shellQuote(String path) {
    return "'" + path.replace("'", "'\\''") + "'";
  }

  public static void pushFile(Device device, InputStream file, String fileName, MyInterface.MyFunctionInt handleProcess) {
    new Thread(() -> {
      try {
        String tempFileName = fileName;
        Adb adb = connectADB(device);
        // 因为糟糕的ADB，如果使用中文名的话，会崩溃，所以此处使用随机名词
        if (!Pattern.compile("^[a-zA-Z0-9\\(\\)\\-\\_\\[\\]\\.]+$").matcher(tempFileName).matches()) {
          int dotIndex = tempFileName.lastIndexOf(".");
          tempFileName = UUID.randomUUID() + (dotIndex == -1 ? "" : tempFileName.substring(dotIndex));
        }
        adb.pushFile(file, "/sdcard/Download/Easycontrol/" + tempFileName, handleProcess);
      } catch (Exception ignored) {
        handleProcess.run(-1);
      }
    }).start();
  }
}
