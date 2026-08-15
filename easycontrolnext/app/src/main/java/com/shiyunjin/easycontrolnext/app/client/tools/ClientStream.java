package com.shiyunjin.easycontrolnext.app.client.tools;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;

import com.shiyunjin.easycontrolnext.app.BuildConfig;
import com.shiyunjin.easycontrolnext.app.R;
import com.shiyunjin.easycontrolnext.app.adb.Adb;
import com.shiyunjin.easycontrolnext.app.buffer.BufferStream;
import com.shiyunjin.easycontrolnext.app.client.decode.DecodecTools;
import com.shiyunjin.easycontrolnext.app.entity.AppData;
import com.shiyunjin.easycontrolnext.app.entity.Device;
import com.shiyunjin.easycontrolnext.app.entity.MyInterface;
import com.shiyunjin.easycontrolnext.app.helper.AppErrorLog;
import com.shiyunjin.easycontrolnext.app.helper.PublicTools;

public class ClientStream {
  private boolean isClose = false;
  private boolean connectDirect = false;
  private Adb adb;
  private Socket mainSocket;
  private Socket videoSocket;
  private OutputStream mainOutputStream;
  private DataInputStream mainDataInputStream;
  private DataInputStream videoDataInputStream;
  private BufferStream mainBufferStream;
  private BufferStream videoBufferStream;
  private BufferStream shell;
  private Thread connectThread = null;
  private final Object mainWriteLock = new Object();
  private static final String serverName = "/data/local/tmp/easycontrolnext_server_" + BuildConfig.VERSION_CODE + ".jar";
  private static final boolean supportH265 = DecodecTools.isSupportH265();
  private static final boolean supportOpus = DecodecTools.isSupportOpus();

  private static final int timeoutDelay = 1000 * 15;

  public ClientStream(Device device, MyInterface.MyFunctionBoolean handle) {
    final boolean cameraMode = device.videoSource != null && "camera".equalsIgnoreCase(device.videoSource);
    // 超时
    Thread timeOutThread = new Thread(() -> {
      try {
        Thread.sleep(timeoutDelay);
        String msg = AppData.applicationContext.getString(R.string.toast_timeout);
        if (cameraMode) {
          String cameraErr = peekCameraServerError();
          if (cameraErr != null) {
            msg = AppData.applicationContext.getString(R.string.toast_camera_failed, cameraErr);
          }
        }
        PublicTools.logToast("stream", msg, true);
        handle.run(false);
        if (connectThread != null) connectThread.interrupt();
      } catch (InterruptedException ignored) {
      }
    });
    // 连接
    connectThread = new Thread(() -> {
      try {
        adb = AdbTools.connectADB(device);
        startServer(device);
        connectServer(device);
        handle.run(true);
      } catch (Exception e) {
        String msg = e.getMessage() != null ? e.getMessage() : e.toString();
        if (cameraMode) {
          String cameraErr = peekCameraServerError();
          if (cameraErr != null) {
            msg = AppData.applicationContext.getString(R.string.toast_camera_failed, cameraErr);
          } else if (msg.toLowerCase().contains("camera") || msg.contains("相机")) {
            msg = AppData.applicationContext.getString(R.string.toast_camera_failed, msg);
          }
        }
        PublicTools.logToast("stream", msg, true);
        handle.run(false);
      } finally {
        timeOutThread.interrupt();
      }
    });
    connectThread.start();
    timeOutThread.start();
  }

  /** Best-effort parse of shell stderr when camera server dies before sockets accept. */
  private String peekCameraServerError() {
    if (shell == null) return null;
    try {
      Thread.sleep(300);
      String out = new String(shell.readByteArrayBeforeClose().array());
      if (out.isEmpty()) return null;
      PublicTools.logToast("server", out, false);
      String lower = out.toLowerCase();
      // Prefer the explicit camera / IOException lines from Server.main / VideoEncode.
      String[] markers = {
        "camera capture failed:",
        "camera mirroring requires",
        "camera error",
        "open camera",
        "camera session",
        "camera permission",
        "no matching camera",
        "no suitable camera",
        "cameramanager unavailable",
        "cameracapture not prepared"
      };
      for (String line : out.split("\n")) {
        String trimmed = line.trim();
        if (trimmed.isEmpty()) continue;
        String lineLower = trimmed.toLowerCase();
        for (String marker : markers) {
          if (lineLower.contains(marker)) {
            int idx = lineLower.indexOf(marker);
            String detail = trimmed.substring(idx).replaceFirst("(?i)^camera capture failed:\\s*", "");
            if (detail.length() > 180) detail = detail.substring(0, 180) + "…";
            return detail;
          }
        }
      }
      if (lower.contains("camera")) {
        // Fall back to last non-empty line mentioning camera
        String last = null;
        for (String line : out.split("\n")) {
          if (line.toLowerCase().contains("camera")) last = line.trim();
        }
        if (last != null) {
          if (last.length() > 180) last = last.substring(0, 180) + "…";
          return last;
        }
      }
    } catch (Exception ignored) {
    }
    return null;
  }

  // 启动Server
  private void startServer(Device device) throws Exception {
    if (BuildConfig.ENABLE_DEBUG_FEATURE || !adb.runAdbCmd("ls /data/local/tmp/easycontrolnext_*").contains(serverName)) {
      adb.runAdbCmd("rm /data/local/tmp/easycontrolnext_* ");
      adb.pushFile(AppData.applicationContext.getResources().openRawResource(R.raw.easycontrolnext_server), serverName, null);
    }

    String videoSource = device.videoSource == null || device.videoSource.isEmpty() ? "display" : device.videoSource;
    String startApp = device.startApp == null ? "" : device.startApp.trim();
    if ("camera".equalsIgnoreCase(videoSource)) {
      int sdk = readDeviceSdk(adb);
      if (sdk > 0 && sdk < 31) {
        throw new Exception(AppData.applicationContext.getString(R.string.toast_camera_android12));
      }
      startApp = ""; // camera source ignores single-app VD
    } else if (!startApp.isEmpty()) {
      int sdk = readDeviceSdk(adb);
      if (sdk > 0 && sdk < 30) {
        throw new Exception(AppData.applicationContext.getString(R.string.toast_virtual_display_android11));
      }
    }

    String cameraFacing = device.cameraFacing == null || device.cameraFacing.isEmpty() ? "back" : device.cameraFacing;
    // User preference ∩ decode caps; server intersects with encode caps.
    String hevcPref = device.hevcProfile == null ? DecodecTools.HEVC_PREF_MAIN : device.hevcProfile.trim().toLowerCase();
    if (!DecodecTools.HEVC_PREF_AUTO.equals(hevcPref)
      && !DecodecTools.HEVC_PREF_MAIN10.equals(hevcPref)
      && !DecodecTools.HEVC_PREF_MAIN.equals(hevcPref)) {
      hevcPref = DecodecTools.HEVC_PREF_MAIN;
    }
    String hevcProfile = DecodecTools.HEVC_PROFILE_NONE;
    if (device.useH265 && supportH265) {
      hevcProfile = DecodecTools.resolveRequestedHevcProfile(hevcPref);
    }
    // Explicit Main (8-bit) must never be upgraded, even if this device decodes Main10.
    if (DecodecTools.HEVC_PREF_MAIN.equals(hevcPref)
      && DecodecTools.HEVC_PROFILE_MAIN10.equals(hevcProfile)) {
      hevcProfile = DecodecTools.HEVC_PROFILE_MAIN;
    }
    boolean enableH265 = !DecodecTools.HEVC_PROFILE_NONE.equals(hevcProfile);
    if (DecodecTools.HEVC_PREF_MAIN10.equals(hevcPref)
      && enableH265
      && !DecodecTools.HEVC_PROFILE_MAIN10.equals(hevcProfile)) {
      PublicTools.logToast("hevc", AppData.applicationContext.getString(R.string.toast_hevc_main10_fallback), true);
    }
    AppErrorLog.w("hevc", "pref=" + hevcPref
      + " decode caps: h265=" + supportH265
      + " main=" + DecodecTools.isSupportHevcMain()
      + " main10=" + DecodecTools.isSupportHevcMain10()
      + " → request hevcProfile=" + hevcProfile
      + " (device.useH265=" + device.useH265 + ")");
    shell = adb.getShell();
    shell.write(ByteBuffer.wrap(("app_process -Djava.class.path=" + serverName + " / com.shiyunjin.easycontrolnext.server.Server"
      + " serverPort=" + device.serverPort
      + " listenClip=" + (device.listenClip ? 1 : 0)
      + " isAudio=" + (device.isAudio ? 1 : 0)
      + " maxSize=" + device.maxSize
      + " maxFps=" + device.maxFps
      + " maxVideoBit=" + device.maxVideoBit
      + " keepAwake=" + (device.keepWakeOnRunning ? 1 : 0)
      + " supportH265=" + (enableH265 ? 1 : 0)
      + " hevcProfile=" + hevcProfile
      + " supportOpus=" + (supportOpus ? 1 : 0)
      + " videoSource=" + videoSource
      + " cameraFacing=" + cameraFacing
      + " virtualWidth=" + device.virtualWidth
      + " virtualHeight=" + device.virtualHeight
      + " virtualDpi=" + device.virtualDpi
      + " startApp=" + startApp + " \n").getBytes()));
  }

  private static int readDeviceSdk(Adb adb) {
    try {
      String sdk = adb.runAdbCmd("getprop ro.build.version.sdk").trim();
      // take first integer token
      StringBuilder digits = new StringBuilder();
      for (int i = 0; i < sdk.length(); i++) {
        char c = sdk.charAt(i);
        if (c >= '0' && c <= '9') digits.append(c);
        else if (digits.length() > 0) break;
      }
      if (digits.length() == 0) return -1;
      return Integer.parseInt(digits.toString());
    } catch (Exception e) {
      return -1;
    }
  }

  // 连接Server
  private void connectServer(Device device) throws Exception {
    Thread.sleep(50);
    int reTry = 40;
    int reTryTime = timeoutDelay / reTry;
    if (!device.isLinkDevice()) {
      long startTime = System.currentTimeMillis();
      boolean mainConn = false;
      InetSocketAddress inetSocketAddress = new InetSocketAddress(PublicTools.getIp(device.address), device.serverPort);
      for (int i = 0; i < reTry; i++) {
        try {
          if (!mainConn) {
            mainSocket = new Socket();
            mainSocket.connect(inetSocketAddress, timeoutDelay / 2);
            trySetTcpNoDelay(mainSocket);
            mainConn = true;
          }
          videoSocket = new Socket();
          videoSocket.connect(inetSocketAddress, timeoutDelay / 2);
          trySetTcpNoDelay(videoSocket);
          mainOutputStream = mainSocket.getOutputStream();
          mainDataInputStream = new DataInputStream(mainSocket.getInputStream());
          videoDataInputStream = new DataInputStream(videoSocket.getInputStream());
          connectDirect = true;
          return;
        } catch (Exception ignored) {
          if (mainSocket != null) mainSocket.close();
          if (videoSocket != null) videoSocket.close();
          // 如果超时，直接跳出循环
          if (System.currentTimeMillis() - startTime >= timeoutDelay / 2 - 1000) i = reTry;
          else Thread.sleep(reTryTime);
        }
      }
    }
    // 直连失败尝试ADB中转
    for (int i = 0; i < reTry; i++) {
      try {
        if (mainBufferStream == null) mainBufferStream = adb.tcpForward(device.serverPort);
        // 为了减少adb同步阻塞的问题，此处分开音视频流
        if (videoBufferStream == null) videoBufferStream = adb.tcpForward(device.serverPort);
        return;
      } catch (Exception ignored) {
        Thread.sleep(reTryTime);
      }
    }
    throw new Exception(AppData.applicationContext.getString(R.string.toast_connect_server));
  }

  public String runShell(String cmd) throws Exception {
    return adb.runAdbCmd(cmd);
  }

  public byte readByteFromMain() throws IOException, InterruptedException {
    if (connectDirect) return mainDataInputStream.readByte();
    else return mainBufferStream.readByte();
  }

  public byte readByteFromVideo() throws IOException, InterruptedException {
    if (connectDirect) return videoDataInputStream.readByte();
    else return videoBufferStream.readByte();
  }

  public int readIntFromMain() throws IOException, InterruptedException {
    if (connectDirect) return mainDataInputStream.readInt();
    else return mainBufferStream.readInt();
  }

  public int readIntFromVideo() throws IOException, InterruptedException {
    if (connectDirect) return videoDataInputStream.readInt();
    else return videoBufferStream.readInt();
  }

  public ByteBuffer readByteArrayFromMain(int size) throws IOException, InterruptedException {
    if (connectDirect) {
      byte[] buffer = new byte[size];
      mainDataInputStream.readFully(buffer);
      return ByteBuffer.wrap(buffer);
    } else return mainBufferStream.readByteArray(size);
  }

  public ByteBuffer readByteArrayFromVideo(int size) throws IOException, InterruptedException {
    if (connectDirect) {
      byte[] buffer = new byte[size];
      videoDataInputStream.readFully(buffer);
      return ByteBuffer.wrap(buffer);
    }
    return videoBufferStream.readByteArray(size);
  }

  public ByteBuffer readFrameFromMain() throws Exception {
    if (!connectDirect) mainBufferStream.flush();
    return readByteArrayFromMain(readIntFromMain());
  }

  public ByteBuffer readFrameFromVideo() throws Exception {
    if (!connectDirect) videoBufferStream.flush();
    int size = readIntFromVideo();
    return readByteArrayFromVideo(size);
  }

  public void writeToMain(ByteBuffer byteBuffer) throws Exception {
    if (byteBuffer == null) return;
    synchronized (mainWriteLock) {
      if (connectDirect) mainOutputStream.write(byteBuffer.array());
      else mainBufferStream.write(byteBuffer);
    }
  }

  static void trySetTcpNoDelay(Socket socket) {
    if (socket == null) return;
    try {
      socket.setTcpNoDelay(true);
    } catch (Exception ignored) {
    }
  }

  public void close() {
    if (isClose) return;
    isClose = true;
    if (shell != null) PublicTools.logToast("server", new String(shell.readByteArrayBeforeClose().array()), false);
    if (connectDirect) {
      try {
        mainOutputStream.close();
        videoDataInputStream.close();
        mainDataInputStream.close();
        mainSocket.close();
        videoSocket.close();
      } catch (Exception ignored) {
      }
    } else {
      mainBufferStream.close();
      videoBufferStream.close();
    }
  }
}
