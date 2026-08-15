package com.shiyunjin.easycontrolnext.app.client.decode;

import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;

import java.util.ArrayList;
import java.util.Objects;

public class DecodecTools {
  private static ArrayList<String> hevcDecodecList = null;
  private static ArrayList<String> avcDecodecList = null;
  private static ArrayList<String> opusDecodecList = null;
  private static Boolean isSupportOpus = null;
  private static Boolean isSupportH265 = null;
  private static Boolean isSupportHevcMain = null;
  private static Boolean isSupportHevcMain10 = null;

  /** No HEVC. */
  public static final String HEVC_PROFILE_NONE = "0";
  /** HEVC Main (8-bit). */
  public static final String HEVC_PROFILE_MAIN = "main";
  /** HEVC Main10 (10-bit). */
  public static final String HEVC_PROFILE_MAIN10 = "main10";

  /** User preference: pick Main10 when decode supports it. */
  public static final String HEVC_PREF_AUTO = "auto";
  /** User preference: force Main (8-bit). Default. */
  public static final String HEVC_PREF_MAIN = "main";
  /** User preference: request Main10 (falls back if unsupported). */
  public static final String HEVC_PREF_MAIN10 = "main10";

  // 获取解码器列表
  private static void getDecodecList() {
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    hevcDecodecList = new ArrayList<>();
    avcDecodecList = new ArrayList<>();
    opusDecodecList = new ArrayList<>();
    for (MediaCodecInfo mediaCodecInfo : mediaCodecList.getCodecInfos()) {
      if (!mediaCodecInfo.isEncoder()) {
        String codecName = mediaCodecInfo.getName();
        for (String supportType : mediaCodecInfo.getSupportedTypes()) {
          if (Objects.equals(supportType, MediaFormat.MIMETYPE_AUDIO_OPUS)) opusDecodecList.add(codecName);
          else {
            // 视频解码器要求硬件实现
            if (!codecName.startsWith("OMX.google") && !codecName.startsWith("c2.android")) {
              if (Objects.equals(supportType, MediaFormat.MIMETYPE_VIDEO_HEVC)) hevcDecodecList.add(codecName);
              else if (Objects.equals(supportType, MediaFormat.MIMETYPE_VIDEO_AVC)) avcDecodecList.add(codecName);
            }
          }
        }
      }
    }
  }

  private static void probeHevcProfiles() {
    if (hevcDecodecList == null) getDecodecList();
    boolean main = false;
    boolean main10 = false;
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    for (MediaCodecInfo info : mediaCodecList.getCodecInfos()) {
      if (info.isEncoder()) continue;
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
              main = true; // Main10 decoders can decode Main
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
              && pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) {
              main10 = true;
              main = true;
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
              && pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus) {
              main10 = true;
              main = true;
            }
          }
        }
      } catch (Exception ignored) {
      }
    }
    // Some firmwares omit profileLevels; HW HEVC decoder still implies at least Main.
    if (!main && !main10 && hevcDecodecList.size() > 0) main = true;
    isSupportHevcMain = main;
    isSupportHevcMain10 = main10;
  }

  // 获取解码器是否支持
  public static boolean isSupportOpus() {
    if (isSupportOpus != null) return isSupportOpus;
    if (opusDecodecList == null) getDecodecList();
    isSupportOpus = opusDecodecList.size() > 0;
    return isSupportOpus;
  }

  public static boolean isSupportH265() {
    if (isSupportH265 != null) return isSupportH265;
    if (hevcDecodecList == null) getDecodecList();
    isSupportH265 = hevcDecodecList.size() > 0;
    return isSupportH265;
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
   * Best HEVC profile this device can decode: {@code main10}, {@code main}, or {@code 0}.
   * Used only for capability display / Auto — never to override an explicit Main (8-bit) choice.
   */
  public static String getPreferredHevcProfile() {
    if (!isSupportH265()) return HEVC_PROFILE_NONE;
    if (isSupportHevcMain10()) return HEVC_PROFILE_MAIN10;
    if (isSupportHevcMain()) return HEVC_PROFILE_MAIN;
    return HEVC_PROFILE_NONE;
  }

  /**
   * Resolve wire {@code hevcProfile} from user preference ∩ HW decode caps.
   * Preference: {@code auto} | {@code main} | {@code main10}. Result: {@code main10} | {@code main} | {@code 0}.
   * <p>
   * Main (8-bit) is never upgraded to Main10, even if this device can decode Main10.
   * Main10 is used only when the user chose {@code auto} or {@code main10}, and only if decode supports it;
   * otherwise fall back to Main.
   */
  public static String resolveRequestedHevcProfile(String preference) {
    if (!isSupportH265()) return HEVC_PROFILE_NONE;
    String pref = preference == null ? HEVC_PREF_MAIN : preference.trim().toLowerCase();
    if (HEVC_PREF_MAIN10.equals(pref) || HEVC_PREF_AUTO.equals(pref)) {
      return isSupportHevcMain10() ? HEVC_PROFILE_MAIN10 : HEVC_PROFILE_MAIN;
    }
    // main and any unknown pref: never upgrade to Main10
    return HEVC_PROFILE_MAIN;
  }

  /** Fresh MediaCodecList scan for Settings; does not reuse connection-time caches. */
  public static LocalDecoderCaps probeLocalDecoderCaps() {
    LocalDecoderCaps caps = new LocalDecoderCaps();
    MediaCodecList mediaCodecList = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
    for (MediaCodecInfo info : mediaCodecList.getCodecInfos()) {
      if (info.isEncoder()) continue;
      boolean hw = isHardwareDecoder(info);
      try {
        for (String type : info.getSupportedTypes()) {
          if (Objects.equals(type, MediaFormat.MIMETYPE_VIDEO_AVC)) {
            if (hw) caps.avcHw = true;
            else caps.avcSw = true;
          } else if (Objects.equals(type, MediaFormat.MIMETYPE_VIDEO_HEVC)) {
            if (hw) caps.hevcHw = true;
            else caps.hevcSw = true;
            collectHevcDecodeProfiles(info, type, caps);
          } else if (Objects.equals(type, "video/av01")) {
            if (hw) caps.av1Hw = true;
            else caps.av1Sw = true;
          } else if (Objects.equals(type, MediaFormat.MIMETYPE_AUDIO_OPUS)) {
            if (hw) caps.opusHw = true;
            else caps.opusSw = true;
          } else if (Objects.equals(type, MediaFormat.MIMETYPE_AUDIO_AAC)) {
            if (hw) caps.aacHw = true;
            else caps.aacSw = true;
          }
        }
      } catch (Exception ignored) {
      }
    }
    if (caps.hevcHw && !caps.hevcMain && !caps.hevcMain10) {
      caps.hevcMain = true;
    }
    return caps;
  }

  private static void collectHevcDecodeProfiles(MediaCodecInfo info, String type, LocalDecoderCaps caps) {
    try {
      MediaCodecInfo.CodecCapabilities codecCaps = info.getCapabilitiesForType(type);
      if (codecCaps == null || codecCaps.profileLevels == null) return;
      for (MediaCodecInfo.CodecProfileLevel pl : codecCaps.profileLevels) {
        if (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain) {
          caps.hevcMain = true;
        } else if (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10) {
          caps.hevcMain10 = true;
          caps.hevcMain = true;
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
          && pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) {
          caps.hevcMain10 = true;
          caps.hevcMain = true;
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
          && pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus) {
          caps.hevcMain10 = true;
          caps.hevcMain = true;
        }
      }
    } catch (Exception ignored) {
    }
  }

  private static boolean isHardwareDecoder(MediaCodecInfo info) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      return info.isHardwareAccelerated();
    }
    String name = info.getName();
    return !name.startsWith("OMX.google") && !name.startsWith("c2.android");
  }

  public static final class LocalDecoderCaps {
    public boolean avcHw;
    public boolean avcSw;
    public boolean hevcHw;
    public boolean hevcSw;
    public boolean hevcMain;
    public boolean hevcMain10;
    public boolean av1Hw;
    public boolean av1Sw;
    public boolean opusHw;
    public boolean opusSw;
    public boolean aacHw;
    public boolean aacSw;
  }

  // 获取视频最优解码器
  public static String getVideoDecoder(boolean h265) {
    if (hevcDecodecList == null || avcDecodecList == null) getDecodecList();
    ArrayList<String> allHardNormalDecodec = h265 ? hevcDecodecList : avcDecodecList;
    ArrayList<String> allHardLowLatencyDecodec = new ArrayList<>();
    for (String codecName : allHardNormalDecodec) if (codecName.contains("low_latency")) allHardLowLatencyDecodec.add(codecName);
    // 存在低延迟解码器
    if (allHardLowLatencyDecodec.size() > 0) return getC2Decodec(allHardLowLatencyDecodec);
    // 选择正常解码器
    if (allHardNormalDecodec.size() > 0) return getC2Decodec(allHardNormalDecodec);
    return "";
  }

  // 优选C2解码器
  private static String getC2Decodec(ArrayList<String> allHardDecodec) {
    for (String codecName : allHardDecodec) if (codecName.contains("c2")) return codecName;
    return allHardDecodec.get(0);
  }
}
