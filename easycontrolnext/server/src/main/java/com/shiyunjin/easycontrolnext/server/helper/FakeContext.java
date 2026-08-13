/*
 * 本项目大量借鉴学习了开源投屏软件：Scrcpy，在此对该项目表示感谢
 */
package com.shiyunjin.easycontrolnext.server.helper;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.content.AttributionSource;
import android.content.Context;
import android.content.MutableContextWrapper;
import android.os.Build;
import android.os.Looper;
import android.os.Process;
import android.util.Log;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Shell-uid Context for {@code app_process}. Base is the real system Context when available
 * (needed by CameraManager / some OEM paths); package / attribution stay {@code com.android.shell}.
 */
public final class FakeContext extends MutableContextWrapper {

  public static final String PACKAGE_NAME = "com.android.shell";
  public static final int ROOT_UID = 0; // Like android.os.Process.ROOT_UID, but before API 29

  private static final String TAG = "EasycontrolFakeCtx";
  private static final FakeContext INSTANCE = new FakeContext();

  public static FakeContext get() {
    INSTANCE.ensureSystemContext();
    return INSTANCE;
  }

  private FakeContext() {
    super(null);
  }

  /**
   * Under {@code app_process}, {@code ActivityThread.currentActivityThread()} is often null.
   * Create / bind a system ActivityThread (scrcpy Workarounds / ListApps.systemMain) so
   * {@code getSystemContext()} works, then use it as our base Context.
   */
  @SuppressLint({"PrivateApi", "DiscouragedPrivateApi"})
  private void ensureSystemContext() {
    if (getBaseContext() != null) return;
    synchronized (this) {
      if (getBaseContext() != null) return;
      try {
        try {
          Looper.prepareMainLooper();
        } catch (Throwable ignored) {
          // already prepared
        }
        Class<?> atClass = Class.forName("android.app.ActivityThread");
        Object activityThread = atClass.getMethod("currentActivityThread").invoke(null);
        if (activityThread == null) {
          try {
            Method systemMain = atClass.getDeclaredMethod("systemMain");
            activityThread = systemMain.invoke(null);
          } catch (Throwable ignored) {
            // Fallback: construct ActivityThread and publish as current (scrcpy-style).
            Constructor<?> ctor = atClass.getDeclaredConstructor();
            ctor.setAccessible(true);
            activityThread = ctor.newInstance();
            Field sCurrent = atClass.getDeclaredField("sCurrentActivityThread");
            sCurrent.setAccessible(true);
            sCurrent.set(null, activityThread);
            try {
              Field mSystemThread = atClass.getDeclaredField("mSystemThread");
              mSystemThread.setAccessible(true);
              mSystemThread.setBoolean(activityThread, true);
            } catch (NoSuchFieldException ignored2) {
            }
          }
        }
        if (activityThread == null) {
          Log.w(TAG, "ActivityThread unavailable; FakeContext has no system base");
          return;
        }
        Context sys = (Context) atClass.getMethod("getSystemContext").invoke(activityThread);
        if (sys != null) {
          setBaseContext(sys);
        } else {
          Log.w(TAG, "getSystemContext() returned null");
        }
      } catch (Throwable t) {
        Log.w(TAG, "Could not attach system context: " + t.getMessage());
      }
    }
  }

  @Override
  public String getPackageName() {
    return PACKAGE_NAME;
  }

  @Override
  public String getOpPackageName() {
    return PACKAGE_NAME;
  }

  @Override
  public Context getApplicationContext() {
    return this;
  }

  @TargetApi(Build.VERSION_CODES.S)
  @Override
  public AttributionSource getAttributionSource() {
    AttributionSource.Builder builder = new AttributionSource.Builder(Process.SHELL_UID);
    builder.setPackageName(PACKAGE_NAME);
    return builder.build();
  }

  // @Override to be added on SDK upgrade for Android 14
  @SuppressWarnings("unused")
  public int getDeviceId() {
    return 0;
  }
}
