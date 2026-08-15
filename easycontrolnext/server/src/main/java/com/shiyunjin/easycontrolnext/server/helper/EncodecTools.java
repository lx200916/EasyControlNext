package com.shiyunjin.easycontrolnext.server.helper;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;

import java.util.ArrayList;
import java.util.Objects;

public class EncodecTools {
  private static ArrayList<String> hevcEncodecList = null;
  private static ArrayList<String> opusEncodecList = null;
  private static Boolean isSupportHevcMain = null;
  private static Boolean isSupportHevcMain10 = null;

  public static final String HEVC_PROFILE_NONE = "0";
  public static final String HEVC_PROFILE_MAIN = "main";
  public static final String HEVC_PROFILE_MAIN10 = "main10";

  // 获取编码器列表
  private static void getEncodecList() {
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    hevcEncodecList = new ArrayList<>();
    opusEncodecList = new ArrayList<>();
    for (MediaCodecInfo mediaCodecInfo : mediaCodecList.getCodecInfos()) {
      if (mediaCodecInfo.isEncoder()) {
        String codecName = mediaCodecInfo.getName();
        if (codecName.toLowerCase().contains("opus")) opusEncodecList.add(codecName);
        if (!isSoftwareCodec(codecName)) {
          for (String supportType : mediaCodecInfo.getSupportedTypes()) {
            if (Objects.equals(supportType, MediaFormat.MIMETYPE_VIDEO_HEVC)) hevcEncodecList.add(codecName);
          }
        }
      }
    }
  }

  private static void probeHevcProfiles() {
    if (hevcEncodecList == null) getEncodecList();
    boolean main = false;
    boolean main10 = false;
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    for (MediaCodecInfo info : mediaCodecList.getCodecInfos()) {
      if (!info.isEncoder()) continue;
      String codecName = info.getName();
      if (isSoftwareCodec(codecName)) continue;
      try {
        for (String type : info.getSupportedTypes()) {
          if (!Objects.equals(type, MediaFormat.MIMETYPE_VIDEO_HEVC)) continue;
          MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
          if (caps == null || caps.profileLevels == null) continue;
          for (MediaCodecInfo.CodecProfileLevel pl : caps.profileLevels) {
            if (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain) {
              main = true;
            } else if (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10) {
              main10 = true;
            }
          }
        }
      } catch (Exception ignored) {
      }
    }
    // Firmware may omit profileLevels; HW HEVC encoder still implies at least Main.
    if (!main && !main10 && hevcEncodecList.size() > 0) main = true;
    isSupportHevcMain = main;
    isSupportHevcMain10 = main10;
  }

  // 获取编码器是否支持
  public static boolean isSupportOpus() {
    if (opusEncodecList == null) getEncodecList();
    return opusEncodecList.size() > 0;
  }

  public static boolean isSupportH265() {
    if (hevcEncodecList == null) getEncodecList();
    return hevcEncodecList.size() > 0;
  }

  public static boolean isSupportHevcMain() {
    if (isSupportHevcMain != null) return isSupportHevcMain;
    probeHevcProfiles();
    return isSupportHevcMain;
  }

  public static boolean isSupportHevcMain10() {
    if (isSupportHevcMain10 != null) return isSupportHevcMain10;
    probeHevcProfiles();
    return isSupportHevcMain10;
  }

  /**
   * Highest advertised level for a HEVC profile among HW encoders, or a safe default.
   */
  public static int getHevcMaxLevel(int profile) {
    int maxLevel = 0;
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    for (MediaCodecInfo info : mediaCodecList.getCodecInfos()) {
      if (!info.isEncoder()) continue;
      String codecName = info.getName();
      if (isSoftwareCodec(codecName)) continue;
      try {
        for (String type : info.getSupportedTypes()) {
          if (!Objects.equals(type, MediaFormat.MIMETYPE_VIDEO_HEVC)) continue;
          MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
          if (caps == null || caps.profileLevels == null) continue;
          for (MediaCodecInfo.CodecProfileLevel pl : caps.profileLevels) {
            if (pl.profile == profile && pl.level > maxLevel) maxLevel = pl.level;
          }
        }
      } catch (Exception ignored) {
      }
    }
    if (maxLevel > 0) return maxLevel;
    // HEVCMainTierLevel51 — widely supported fallback when profileLevels are empty
    return MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel51;
  }

  /**
   * Intersect client-requested profile with local encode capability.
   * Main is never upgraded to Main10. Main10 falls back to Main only when Main10 is unsupported.
   * @return main10 | main | 0
   */
  public static String intersectHevcProfile(String requested) {
    if (!isSupportH265()) return HEVC_PROFILE_NONE;
    if (requested == null) requested = HEVC_PROFILE_NONE;
    String req = requested.trim().toLowerCase();
    if (HEVC_PROFILE_NONE.equals(req) || "0".equals(req)) return HEVC_PROFILE_NONE;
    boolean wantMain10 = HEVC_PROFILE_MAIN10.equals(req) || "2".equals(req) || "auto".equals(req);
    if (wantMain10) {
      if (isSupportHevcMain10()) return HEVC_PROFILE_MAIN10;
      if (isSupportHevcMain()) return HEVC_PROFILE_MAIN;
      // HW HEVC with omitted profileLevels still counts as Main via probe fallback.
      return isSupportH265() ? HEVC_PROFILE_MAIN : HEVC_PROFILE_NONE;
    }
    // Explicit Main (8-bit) or any other value: never upgrade to Main10.
    return HEVC_PROFILE_MAIN;
  }

  /**
   * Hardware HEVC encoder that advertises {@code profileId}, preferring c2.
   * For Main, may return any HW HEVC encoder so KEY_PROFILE can still be tried;
   * caller must reject a Main10 output.
   */
  public static String findHevcEncoderForProfile(int profileId) {
    ArrayList<String> exact = new ArrayList<>();
    ArrayList<String> any = new ArrayList<>();
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    for (MediaCodecInfo info : mediaCodecList.getCodecInfos()) {
      if (!info.isEncoder()) continue;
      String codecName = info.getName();
      if (isSoftwareCodec(codecName)) continue;
      try {
        for (String type : info.getSupportedTypes()) {
          if (!Objects.equals(type, MediaFormat.MIMETYPE_VIDEO_HEVC)) continue;
          if (!any.contains(codecName)) any.add(codecName);
          MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
          if (caps == null || caps.profileLevels == null) continue;
          for (MediaCodecInfo.CodecProfileLevel pl : caps.profileLevels) {
            if (pl.profile == profileId && !exact.contains(codecName)) {
              exact.add(codecName);
              break;
            }
          }
        }
      } catch (Exception ignored) {
      }
    }
    if (!exact.isEmpty()) return preferC2(exact);
    if (profileId == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain && !any.isEmpty()) {
      return preferC2(any);
    }
    return "";
  }

  private static String preferC2(ArrayList<String> names) {
    for (String name : names) {
      if (name.contains("c2")) return name;
    }
    return names.get(0);
  }

  static boolean isSoftwareCodec(String codecName) {
    if (codecName == null) return true;
    String n = codecName.toLowerCase();
    return n.startsWith("omx.google") || n.startsWith("c2.android") || n.contains(".sw.");
  }
}
