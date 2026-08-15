/*
 * 本项目大量借鉴学习了开源投屏软件：Scrcpy，在此对该项目表示感谢
 */
package com.shiyunjin.easycontrolnext.server.entity;

public final class Options {
  public static int serverPort = 25166;
  public static boolean listenerClip = true;
  public static boolean isAudio = true;
  public static int maxSize = 1600;
  public static int maxVideoBit = 4000000;
  public static int maxFps = 60;
  public static boolean keepAwake = true;
  public static boolean supportH265 = true;
  /**
   * Client-requested HEVC profile after decode-side probe: {@code main10}, {@code main}, or {@code 0}.
   * Omitted by old clients → treated as {@code main} when {@link #supportH265} is true (safe default).
   */
  public static String hevcProfile = "main";
  public static boolean supportOpus = true;
  public static String startApp = "";
  /** display | camera */
  public static String videoSource = "display";
  /** back | front (used when videoSource=camera) */
  public static String cameraFacing = "back";
  /** 0 = use physical display size / density */
  public static int virtualWidth = 0;
  public static int virtualHeight = 0;
  public static int virtualDpi = 0;

  public static void parse(String... args) {
    for (String arg : args) {
      int equalIndex = arg.indexOf('=');
      if (equalIndex == -1) throw new IllegalArgumentException("参数格式错误");
      String key = arg.substring(0, equalIndex);
      String value = arg.substring(equalIndex + 1);
      switch (key) {
        case "serverPort":
          serverPort = Integer.parseInt(value);
          break;
        case "listenerClip":
          listenerClip = Integer.parseInt(value) == 1;
          break;
        case "isAudio":
          isAudio = Integer.parseInt(value) == 1;
          break;
        case "maxSize":
          maxSize = Integer.parseInt(value);
          break;
        case "maxFps":
          maxFps = Integer.parseInt(value);
          break;
        case "maxVideoBit":
          maxVideoBit = Integer.parseInt(value) * 1000000;
          break;
        case "keepAwake":
          keepAwake = Integer.parseInt(value) == 1;
          break;
        case "supportH265":
          supportH265 = Integer.parseInt(value) == 1;
          break;
        case "hevcProfile":
          hevcProfile = normalizeHevcProfile(value);
          break;
        case "supportOpus":
          supportOpus = Integer.parseInt(value) == 1;
          break;
        case "startApp":
          startApp = value;
          break;
        case "videoSource":
          videoSource = value == null || value.isEmpty() ? "display" : value;
          break;
        case "cameraFacing":
          cameraFacing = value == null || value.isEmpty() ? "back" : value;
          break;
        case "virtualWidth":
          virtualWidth = Integer.parseInt(value);
          break;
        case "virtualHeight":
          virtualHeight = Integer.parseInt(value);
          break;
        case "virtualDpi":
          virtualDpi = Integer.parseInt(value);
          break;
      }
    }
  }

  public static boolean isCameraSource() {
    return "camera".equalsIgnoreCase(videoSource);
  }

  /** Wire value: {@code main10} | {@code main} | {@code 0} | {@code auto}. Unknown → main (never Main10). */
  static String normalizeHevcProfile(String value) {
    if (value == null || value.isEmpty()) return "main";
    String v = value.trim().toLowerCase();
    if ("2".equals(v)) return "main10";
    if ("1".equals(v)) return "main";
    if ("main10".equals(v) || "main".equals(v) || "0".equals(v) || "auto".equals(v)) return v;
    return "main";
  }
}
