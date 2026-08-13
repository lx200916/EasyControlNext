/*
 * 本项目大量借鉴学习了开源投屏软件：Scrcpy，在此对该项目表示感谢
 * Camera2 → MediaCodec path inspired by scrcpy CameraCapture (simplified: no OpenGL / torch / zoom).
 */
package com.shiyunjin.easycontrolnext.server.helper;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.content.Context;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.media.MediaCodec;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Pair;
import android.util.Range;
import android.util.Size;
import android.view.Surface;

import java.lang.reflect.Constructor;
import java.util.Collections;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import com.shiyunjin.easycontrolnext.server.entity.Device;
import com.shiyunjin.easycontrolnext.server.entity.Options;

@TargetApi(Build.VERSION_CODES.S)
public final class CameraCapture {
  private static final String TAG = "EasycontrolCamera";

  private static HandlerThread cameraThread;
  private static Handler cameraHandler;
  private static CameraManager cameraManager;
  private static String cameraId;
  private static Size captureSize;
  private static Range<Integer> fpsRange;
  private static CameraDevice cameraDevice;
  private static CameraCaptureSession captureSession;

  private CameraCapture() {
  }

  /**
   * Same pattern as {@link com.shiyunjin.easycontrolnext.server.wrappers.DisplayManager} /
   * scrcpy: construct CameraManager with {@link FakeContext}. Do not use
   * {@code ActivityThread.currentActivityThread().getSystemContext()} — under {@code app_process}
   * that thread is null and reflection throws NPE ("null receiver").
   */
  @SuppressLint("PrivateApi")
  private static CameraManager createCameraManager() throws Exception {
    FakeContext context = FakeContext.get();
    try {
      Constructor<CameraManager> ctor = CameraManager.class.getDeclaredConstructor(Context.class);
      ctor.setAccessible(true);
      return ctor.newInstance(context);
    } catch (Exception e) {
      Throwable cause = e.getCause() != null ? e.getCause() : e;
      String hint = context.getBaseContext() == null
        ? " (no system Context under app_process / ActivityThread)"
        : "";
      throw new Exception("CameraManager unavailable" + hint + ": " + cause.getMessage(), cause);
    }
  }

  public static void prepare() throws Exception {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      throw new Exception("Camera mirroring requires Android 12+");
    }
    cameraThread = new HandlerThread("easycontrol-camera");
    cameraThread.start();
    cameraHandler = new Handler(cameraThread.getLooper());

    cameraManager = createCameraManager();

    cameraId = selectCameraId(cameraManager, Options.cameraFacing);
    if (cameraId == null) throw new Exception("No matching camera for facing=" + Options.cameraFacing);

    CameraCharacteristics characteristics = cameraManager.getCameraCharacteristics(cameraId);
    captureSize = selectSize(characteristics, Options.maxSize);
    if (captureSize == null) throw new Exception("No suitable camera size");

    // Must match a Camera2-supported output size exactly. Padding to 16 (as display path does)
    // breaks session configure when e.g. 1920x1080 becomes 1920x1088.
    Device.videoSize = new Pair<>(captureSize.getWidth(), captureSize.getHeight());
    fpsRange = pickFpsRange(characteristics, Options.maxFps);
    Log.i(TAG, "Prepared cameraId=" + cameraId
      + " size=" + captureSize.getWidth() + "x" + captureSize.getHeight()
      + " fpsRange=" + fpsRange);
  }

  private static String selectCameraId(CameraManager manager, String facing) throws CameraAccessException {
    int want = "front".equalsIgnoreCase(facing)
      ? CameraCharacteristics.LENS_FACING_FRONT
      : CameraCharacteristics.LENS_FACING_BACK;
    String fallback = null;
    for (String id : manager.getCameraIdList()) {
      CameraCharacteristics ch = manager.getCameraCharacteristics(id);
      Integer lens = ch.get(CameraCharacteristics.LENS_FACING);
      if (fallback == null) fallback = id;
      if (lens != null && lens == want) return id;
    }
    return fallback;
  }

  private static Size selectSize(CameraCharacteristics ch, int maxSize) {
    android.hardware.camera2.params.StreamConfigurationMap map =
      ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
    if (map == null) return null;
    Size[] sizes = map.getOutputSizes(MediaCodec.class);
    if (sizes == null || sizes.length == 0) return null;

    Size bestAligned = null;
    long bestAlignedPixels = -1;
    Size bestAny = null;
    long bestAnyPixels = -1;

    for (Size s : sizes) {
      int w = s.getWidth();
      int h = s.getHeight();
      if (maxSize > 0 && Math.max(w, h) > maxSize) continue;
      long pixels = (long) w * h;
      if (pixels > bestAnyPixels) {
        bestAnyPixels = pixels;
        bestAny = s;
      }
      // Prefer sizes already encoder-friendly (both dims multiple of 16).
      if ((w & 15) == 0 && (h & 15) == 0 && pixels > bestAlignedPixels) {
        bestAlignedPixels = pixels;
        bestAligned = s;
      }
    }
    if (bestAligned != null) return bestAligned;
    if (bestAny != null) return bestAny;

    // Nothing under maxSize: pick the smallest declared MediaCodec size.
    Size smallest = sizes[0];
    for (Size s : sizes) {
      long pixels = (long) s.getWidth() * s.getHeight();
      long best = (long) smallest.getWidth() * smallest.getHeight();
      if (pixels < best) smallest = s;
    }
    return smallest;
  }

  /**
   * Pick a declared AE FPS range. Hard-coding [maxFps,maxFps] (often 60) fails on many devices.
   */
  private static Range<Integer> pickFpsRange(CameraCharacteristics ch, int targetFps) {
    Range<Integer>[] ranges = ch.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
    if (ranges == null || ranges.length == 0) return null;
    int want = Math.max(15, Math.min(targetFps > 0 ? targetFps : 30, 60));

    Range<Integer> exactFixed = null;
    Range<Integer> containsWant = null;
    Range<Integer> bestLeWant = null;
    Range<Integer> anyFixed = null;

    for (Range<Integer> r : ranges) {
      int lower = r.getLower();
      int upper = r.getUpper();
      if (lower == want && upper == want) exactFixed = r;
      if (lower <= want && want <= upper) {
        if (containsWant == null
          || upper < containsWant.getUpper()
          || (upper == containsWant.getUpper() && lower > containsWant.getLower())) {
          containsWant = r;
        }
      }
      if (upper <= want) {
        if (bestLeWant == null
          || upper > bestLeWant.getUpper()
          || (upper == bestLeWant.getUpper() && lower >= bestLeWant.getLower())) {
          bestLeWant = r;
        }
      }
      if (lower == upper) {
        if (anyFixed == null || Math.abs(upper - want) < Math.abs(anyFixed.getUpper() - want)) {
          anyFixed = r;
        }
      }
    }
    if (exactFixed != null) return exactFixed;
    if (containsWant != null) return containsWant;
    if (bestLeWant != null) return bestLeWant;
    if (anyFixed != null) return anyFixed;
    return ranges[0];
  }

  public static void start(Surface surface) throws Exception {
    if (cameraManager == null || cameraId == null) throw new Exception("CameraCapture not prepared");
    if (surface == null) throw new Exception("Camera encoder surface is null");
    openCamera();
    createSession(surface);
  }

  @SuppressLint("MissingPermission")
  private static void openCamera() throws Exception {
    CountDownLatch latch = new CountDownLatch(1);
    AtomicReference<CameraDevice> opened = new AtomicReference<>();
    AtomicReference<Exception> error = new AtomicReference<>();

    try {
      cameraManager.openCamera(cameraId, new CameraDevice.StateCallback() {
        @Override
        public void onOpened(CameraDevice camera) {
          opened.set(camera);
          latch.countDown();
        }

        @Override
        public void onDisconnected(CameraDevice camera) {
          camera.close();
          error.set(new Exception("Camera disconnected (in use elsewhere?)"));
          latch.countDown();
        }

        @Override
        public void onError(CameraDevice camera, int errorCode) {
          camera.close();
          error.set(new Exception(cameraErrorMessage(errorCode)));
          latch.countDown();
        }
      }, cameraHandler);
    } catch (SecurityException e) {
      throw new Exception("CAMERA permission denied for shell/camera service: " + e.getMessage(), e);
    } catch (CameraAccessException e) {
      throw new Exception("Cannot open camera: " + e.getMessage(), e);
    }

    if (!latch.await(8, TimeUnit.SECONDS)) {
      throw new Exception("Open camera timeout");
    }
    if (error.get() != null) throw error.get();
    cameraDevice = opened.get();
    if (cameraDevice == null) throw new Exception("Open camera failed");
  }

  private static String cameraErrorMessage(int errorCode) {
    switch (errorCode) {
      case CameraDevice.StateCallback.ERROR_CAMERA_IN_USE:
        return "Camera error: already in use";
      case CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE:
        return "Camera error: max cameras in use";
      case CameraDevice.StateCallback.ERROR_CAMERA_DISABLED:
        return "Camera error: disabled by policy";
      case CameraDevice.StateCallback.ERROR_CAMERA_DEVICE:
        return "Camera error: fatal device error";
      case CameraDevice.StateCallback.ERROR_CAMERA_SERVICE:
        return "Camera error: camera service";
      default:
        return "Camera error " + errorCode;
    }
  }

  private static void createSession(Surface surface) throws Exception {
    CountDownLatch latch = new CountDownLatch(1);
    AtomicReference<Exception> error = new AtomicReference<>();

    cameraDevice.createCaptureSession(Collections.singletonList(surface), new CameraCaptureSession.StateCallback() {
      @Override
      public void onConfigured(CameraCaptureSession session) {
        captureSession = session;
        try {
          startRepeating(session, surface, true);
        } catch (Exception e) {
          // Unsupported AE FPS range is common; retry without forcing FPS.
          try {
            startRepeating(session, surface, false);
            Log.w(TAG, "Retrying capture without FPS range after: " + e.getMessage());
          } catch (Exception e2) {
            error.set(e2);
          }
        }
        latch.countDown();
      }

      @Override
      public void onConfigureFailed(CameraCaptureSession session) {
        error.set(new Exception("Camera session configure failed (size "
          + (captureSize != null ? captureSize.getWidth() + "x" + captureSize.getHeight() : "?")
          + " may be unsupported for MediaCodec surface)"));
        latch.countDown();
      }
    }, cameraHandler);

    if (!latch.await(8, TimeUnit.SECONDS)) {
      throw new Exception("Camera session timeout");
    }
    if (error.get() != null) throw error.get();
  }

  private static void startRepeating(CameraCaptureSession session, Surface surface, boolean withFps)
    throws CameraAccessException {
    CaptureRequest.Builder builder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_RECORD);
    builder.addTarget(surface);
    if (withFps && fpsRange != null) {
      builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, fpsRange);
    }
    session.setRepeatingRequest(builder.build(), null, cameraHandler);
  }

  public static void stop() {
    try {
      if (captureSession != null) {
        captureSession.close();
        captureSession = null;
      }
    } catch (Exception ignored) {
    }
    try {
      if (cameraDevice != null) {
        cameraDevice.close();
        cameraDevice = null;
      }
    } catch (Exception ignored) {
    }
  }

  public static void release() {
    stop();
    if (cameraThread != null) {
      cameraThread.quitSafely();
      cameraThread = null;
      cameraHandler = null;
    }
    cameraManager = null;
    cameraId = null;
    captureSize = null;
    fpsRange = null;
  }
}
