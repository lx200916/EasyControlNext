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
        // 要求硬件实现
        if (!codecName.startsWith("OMX.google") && !codecName.startsWith("c2.android")) {
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
      if (codecName.startsWith("OMX.google") || codecName.startsWith("c2.android")) continue;
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
      if (codecName.startsWith("OMX.google") || codecName.startsWith("c2.android")) continue;
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
   * @return main10 | main | 0
   */
  public static String intersectHevcProfile(String requested) {
    if (!isSupportH265()) return HEVC_PROFILE_NONE;
    if (requested == null) requested = HEVC_PROFILE_NONE;
    String req = requested.trim().toLowerCase();
    boolean wantMain10 = HEVC_PROFILE_MAIN10.equals(req) || "2".equals(req);
    boolean wantMain = HEVC_PROFILE_MAIN.equals(req) || "1".equals(req) || wantMain10;
    if (HEVC_PROFILE_NONE.equals(req) || "0".equals(req)) return HEVC_PROFILE_NONE;
    if (wantMain10 && isSupportHevcMain10()) return HEVC_PROFILE_MAIN10;
    if (wantMain && (isSupportHevcMain() || isSupportHevcMain10())) return HEVC_PROFILE_MAIN;
    return HEVC_PROFILE_NONE;
  }
}
