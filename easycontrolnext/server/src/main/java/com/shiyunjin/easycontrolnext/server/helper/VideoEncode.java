/*
 * 本项目大量借鉴学习了开源投屏软件：Scrcpy，在此对该项目表示感谢
 */
package com.shiyunjin.easycontrolnext.server.helper;

import android.graphics.Rect;
import android.hardware.display.VirtualDisplay;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.os.Build;
import android.os.IBinder;
import android.system.ErrnoException;
import android.view.Surface;

import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.nio.ByteBuffer;

import com.shiyunjin.easycontrolnext.server.Server;
import com.shiyunjin.easycontrolnext.server.entity.Device;
import com.shiyunjin.easycontrolnext.server.entity.Options;
import com.shiyunjin.easycontrolnext.server.wrappers.DisplayManager;
import com.shiyunjin.easycontrolnext.server.wrappers.SurfaceControl;

public final class VideoEncode {
  private static MediaCodec encedec;
  private static MediaFormat encodecFormat;
  public static boolean isHasChangeConfig = false;
  private static boolean useH265;
  /** Negotiated HEVC profile name: main10 | main | 0 (AVC). */
  private static String hevcProfile = EncodecTools.HEVC_PROFILE_NONE;
  private static int hevcProfileId = 0;
  private static boolean isConfigured = false;

  private static IBinder display;

  private static VirtualDisplay virtualDisplay;

  public static void init() throws InvocationTargetException, NoSuchMethodException, IllegalAccessException, IOException, ErrnoException {
    resolveCodecChoice();
    StreamAdapt.init(Options.maxVideoBit, Options.maxFps);
    // Configure (with Main10→Main→AVC fallback) before announcing codec to the client.
    prepareEncoderWithFallback();
    ByteBuffer byteBuffer = ByteBuffer.allocate(9);
    byteBuffer.put((byte) (useH265 ? 1 : 0));
    byteBuffer.putInt(Device.videoSize.first);
    byteBuffer.putInt(Device.videoSize.second);
    byteBuffer.flip();
    Server.writeVideo(byteBuffer);
    System.out.println("VideoEncode: stream header useH265=" + useH265
      + " hevcProfile=" + hevcProfile
      + " size=" + Device.videoSize.first + "x" + Device.videoSize.second);
    startEncode();
  }

  /**
   * Intersect client hevcProfile request with local HW encode caps.
   * Main is never upgraded to Main10; Main10 falls back to Main when encode cannot do Main10.
   */
  private static void resolveCodecChoice() {
    String requested = Options.hevcProfile;
    if (!Options.supportH265) {
      useH265 = false;
      hevcProfile = EncodecTools.HEVC_PROFILE_NONE;
      hevcProfileId = 0;
      System.out.println("VideoEncode: client disabled HEVC → AVC");
      return;
    }
    String selected = EncodecTools.intersectHevcProfile(requested);
    if (EncodecTools.HEVC_PROFILE_MAIN10.equals(selected)) {
      useH265 = true;
      hevcProfile = EncodecTools.HEVC_PROFILE_MAIN10;
      hevcProfileId = MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10;
    } else if (EncodecTools.HEVC_PROFILE_MAIN.equals(selected)) {
      useH265 = true;
      hevcProfile = EncodecTools.HEVC_PROFILE_MAIN;
      hevcProfileId = MediaCodecInfo.CodecProfileLevel.HEVCProfileMain;
    } else {
      useH265 = false;
      hevcProfile = EncodecTools.HEVC_PROFILE_NONE;
      hevcProfileId = 0;
    }
    System.out.println("VideoEncode: negotiate request=" + requested
      + " encodeMain=" + EncodecTools.isSupportHevcMain()
      + " encodeMain10=" + EncodecTools.isSupportHevcMain10()
      + " → selected=" + hevcProfile);
  }

  private static void createEncodecFormat(boolean setLevel) throws IOException {
    String codecMime = useH265 ? MediaFormat.MIMETYPE_VIDEO_HEVC : MediaFormat.MIMETYPE_VIDEO_AVC;
    if (encedec != null) {
      try {
        encedec.release();
      } catch (Exception ignored) {
      }
      encedec = null;
    }
    if (useH265 && hevcProfileId != 0) {
      String encoderName = EncodecTools.findHevcEncoderForProfile(hevcProfileId);
      if (encoderName != null && !encoderName.isEmpty()) {
        encedec = MediaCodec.createByCodecName(encoderName);
        System.out.println("VideoEncode: encoder=" + encoderName + " for profile=" + hevcProfile);
      } else {
        encedec = MediaCodec.createEncoderByType(codecMime);
      }
    } else {
      encedec = MediaCodec.createEncoderByType(codecMime);
    }
    encodecFormat = new MediaFormat();
    encodecFormat.setString(MediaFormat.KEY_MIME, codecMime);
    encodecFormat.setInteger(MediaFormat.KEY_BIT_RATE, StreamAdapt.bitrateForFormat(Options.maxVideoBit));
    encodecFormat.setInteger(MediaFormat.KEY_FRAME_RATE, Options.maxFps);
    encodecFormat.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 10);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) encodecFormat.setInteger(MediaFormat.KEY_INTRA_REFRESH_PERIOD, Options.maxFps * 3);
    encodecFormat.setFloat("max-fps-to-encoder", StreamAdapt.fpsForFormat(Options.maxFps));
    encodecFormat.setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 50_000);
    encodecFormat.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface);
    if (useH265 && hevcProfileId != 0) {
      encodecFormat.setInteger(MediaFormat.KEY_PROFILE, hevcProfileId);
      if (setLevel && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        encodecFormat.setInteger(MediaFormat.KEY_LEVEL, EncodecTools.getHevcMaxLevel(hevcProfileId));
      }
      // Force SDR / 8-bit signaling so Main is not silently promoted to Main10.
      if (hevcProfileId == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain
        && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        encodecFormat.setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709);
        encodecFormat.setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO);
        encodecFormat.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED);
      }
    }
    isConfigured = false;
  }

  private static void createEncodecFormat() throws IOException {
    createEncodecFormat(true);
  }

  /** Try configure; on failure degrade Main10 → Main → AVC. Leaves codec configured (not started). */
  private static void prepareEncoderWithFallback() throws IOException {
    Exception last = null;
    while (true) {
      // Prefer profile+level; some devices reject max level — retry profile-only before downgrade.
      if (tryConfigureOnce(true)) return;
      if (useH265 && tryConfigureOnce(false)) return;
      last = new IOException("configure failed for hevcProfile=" + hevcProfile);
      if (!downgradeCodecChoice()) {
        throw new IOException("Video encoder configure failed after fallbacks", last);
      }
    }
  }

  private static boolean tryConfigureOnce(boolean setLevel) {
    try {
      createEncodecFormat(setLevel);
      encodecFormat.setInteger(MediaFormat.KEY_WIDTH, Device.videoSize.first);
      encodecFormat.setInteger(MediaFormat.KEY_HEIGHT, Device.videoSize.second);
      encedec.configure(encodecFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
      if (useH265 && EncodecTools.HEVC_PROFILE_MAIN.equals(hevcProfile) && outputIsHevcMain10(encedec)) {
        System.out.println("VideoEncode: encoder ignored KEY_PROFILE=Main and selected Main10 — reject");
        throw new IOException("encoder produced Main10 for Main request");
      }
      isConfigured = true;
      System.out.println("VideoEncode: configured ok useH265=" + useH265 + " hevcProfile=" + hevcProfile
        + (useH265 ? (" profileId=" + hevcProfileId + " setLevel=" + setLevel) : ""));
      return true;
    } catch (Exception e) {
      System.out.println("VideoEncode: configure failed for hevcProfile=" + hevcProfile
        + " setLevel=" + setLevel + ": " + e);
      try {
        if (encedec != null) encedec.reset();
      } catch (Exception ignored) {
      }
      try {
        if (encedec != null) encedec.release();
      } catch (Exception ignored) {
      }
      encedec = null;
      isConfigured = false;
      return false;
    }
  }

  /** True when the configured encoder reports Main10 despite a Main request. */
  private static boolean outputIsHevcMain10(MediaCodec codec) {
    try {
      return isHevcMain10Profile(codec.getOutputFormat());
    } catch (Exception ignored) {
      return false;
    }
  }

  private static boolean isHevcMain10Profile(MediaFormat format) {
    if (format == null || !format.containsKey(MediaFormat.KEY_PROFILE)) return false;
    int profile = format.getInteger(MediaFormat.KEY_PROFILE);
    if (profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10) return true;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
      && profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10) {
      return true;
    }
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
      && profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus;
  }

  /** @return true if a lower choice remains to try */
  private static boolean downgradeCodecChoice() {
    if (useH265 && EncodecTools.HEVC_PROFILE_MAIN10.equals(hevcProfile)) {
      hevcProfile = EncodecTools.HEVC_PROFILE_MAIN;
      hevcProfileId = MediaCodecInfo.CodecProfileLevel.HEVCProfileMain;
      useH265 = true;
      System.out.println("VideoEncode: fallback Main10 → Main");
      return true;
    }
    if (useH265) {
      useH265 = false;
      hevcProfile = EncodecTools.HEVC_PROFILE_NONE;
      hevcProfileId = 0;
      System.out.println("VideoEncode: fallback HEVC → AVC");
      return true;
    }
    return false;
  }

  private static void ensureConfigured() throws IOException {
    encodecFormat.setInteger(MediaFormat.KEY_WIDTH, Device.videoSize.first);
    encodecFormat.setInteger(MediaFormat.KEY_HEIGHT, Device.videoSize.second);
    if (isConfigured) return;
    try {
      encedec.configure(encodecFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
      isConfigured = true;
    } catch (Exception e) {
      // Size-change path: header already sent — only allow Main10 → Main (same mime).
      System.out.println("VideoEncode: reconfigure failed: " + e);
      if (useH265 && EncodecTools.HEVC_PROFILE_MAIN10.equals(hevcProfile)) {
        hevcProfile = EncodecTools.HEVC_PROFILE_MAIN;
        hevcProfileId = MediaCodecInfo.CodecProfileLevel.HEVCProfileMain;
        createEncodecFormat();
        encodecFormat.setInteger(MediaFormat.KEY_WIDTH, Device.videoSize.first);
        encodecFormat.setInteger(MediaFormat.KEY_HEIGHT, Device.videoSize.second);
        encedec.configure(encodecFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        isConfigured = true;
        System.out.println("VideoEncode: reconfigure fallback Main10 → Main");
      } else {
        throw e instanceof IOException ? (IOException) e : new IOException(e);
      }
    }
  }

  // 初始化编码器
  private static Surface surface;

  public static void startEncode() throws InvocationTargetException, NoSuchMethodException, IllegalAccessException, IOException, ErrnoException {
    ControlPacket.sendVideoSizeEvent();
    ensureConfigured();
    surface = encedec.createInputSurface();
    if (surface == null) throw new IOException("Encoder input surface is null");

    if (Options.isCameraSource()) {
      try {
        CameraCapture.start(surface);
      } catch (Exception e) {
        // Surface/session failures leave the encoder half-configured; stop cleanly for client reconnect.
        try {
          encedec.reset();
        } catch (Exception ignored) {
        }
        isConfigured = false;
        try {
          surface.release();
        } catch (Exception ignored) {
        }
        surface = null;
        throw new IOException("Camera capture failed: " + e.getMessage(), e);
      }
    } else {
      // Mirror the target displayId (virtual display when startApp is set) onto the encoder surface
      try {
        virtualDisplay = DisplayManager.createVirtualDisplay(
          "easycontrolnext",
          Device.displayInfo.width,
          Device.displayInfo.height,
          Device.displayInfo.displayId,
          surface);
      } catch (Exception displayManagerException) {
        display = SurfaceControl.createDisplay("easycontrolnext", Build.VERSION.SDK_INT < Build.VERSION_CODES.R || (Build.VERSION.SDK_INT == Build.VERSION_CODES.R && !"S".equals(Build.VERSION.CODENAME)));
        setDisplaySurface(display, surface);
      }
    }

    encedec.start();
  }

  public static void stopEncode() {
    try {
      if (Options.isCameraSource()) CameraCapture.stop();
    } catch (Exception ignored) {
    }
    try {
      if (encedec != null) {
        try {
          encedec.stop();
        } catch (Exception ignored) {
        }
        try {
          encedec.reset();
        } catch (Exception ignored) {
        }
      }
    } catch (Exception ignored) {
    }
    isConfigured = false;
    try {
      if (surface != null) {
        surface.release();
        surface = null;
      }
    } catch (Exception ignored) {
    }

    try {
      if (display != null) {
        SurfaceControl.destroyDisplay(display);
        display = null;
      }
      if (virtualDisplay != null) {
        virtualDisplay.release();
        virtualDisplay = null;
      }
    } catch (Exception ignored) {
    }
  }

  private static void setDisplaySurface(IBinder display, Surface surface) throws InvocationTargetException, NoSuchMethodException, IllegalAccessException {
    SurfaceControl.openTransaction();
    try {
      SurfaceControl.setDisplaySurface(display, surface);
      SurfaceControl.setDisplayProjection(display, 0, new Rect(0, 0, Device.displayInfo.width, Device.displayInfo.height), new Rect(0, 0, Device.videoSize.first, Device.videoSize.second));
      SurfaceControl.setDisplayLayerStack(display, Device.displayInfo.layerStack);
    } finally {
      SurfaceControl.closeTransaction();
    }
  }

  private static final MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();

  public static void encodeOut() throws IOException {
    try {
      StreamAdapt.applyPending(encedec);
      // 找到已完成的输出缓冲区
      int outIndex;
      do outIndex = encedec.dequeueOutputBuffer(bufferInfo, -1); while (outIndex < 0);
      ByteBuffer buffer = encedec.getOutputBuffer(outIndex);
      if (buffer == null) return;
      boolean isConfig = (bufferInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
      boolean isKey = (bufferInfo.flags & MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0;
      if (StreamAdapt.shouldDropNonKey() && !isConfig && !isKey) {
        encedec.releaseOutputBuffer(outIndex, false);
        StreamAdapt.applyPending(encedec);
        return;
      }
      if (isKey) StreamAdapt.onKeyFrameSent();
      StreamAdapt.onWriteMs(ControlPacket.sendVideoEvent(bufferInfo.presentationTimeUs, buffer));
      StreamAdapt.applyPending(encedec);
      encedec.releaseOutputBuffer(outIndex, false);
    } catch (IllegalStateException ignored) {
    }
  }

  public static void onClientFeedback(boolean requestIdr, int arrivalDelayMs) {
    StreamAdapt.onClientFeedback(requestIdr, arrivalDelayMs);
  }

  public static void release() {
    try {
      stopEncode();
      if (encedec != null) {
        encedec.release();
        encedec = null;
      }

      if (display != null) {
        SurfaceControl.destroyDisplay(display);
        display = null;
      }

      if (virtualDisplay != null) {
        virtualDisplay.release();
        virtualDisplay = null;
      }
    } catch (Exception ignored) {
    }
    try {
      if (Options.isCameraSource()) CameraCapture.release();
    } catch (Exception ignored) {
    }
  }

}
