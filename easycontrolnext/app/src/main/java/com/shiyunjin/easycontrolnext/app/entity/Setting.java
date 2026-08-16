package com.shiyunjin.easycontrolnext.app.entity;

import android.content.SharedPreferences;

import java.util.UUID;

public final class Setting {
  private final SharedPreferences sharedPreferences;

  private final SharedPreferences.Editor editor;

  public String getLocale() {
    return sharedPreferences.getString("locale", "");
  }

  public void setLocale(String value) {
    editor.putString("locale", value);
    editor.apply();
  }

  public boolean getAutoRotate() {
    return sharedPreferences.getBoolean("autoRotate", true);
  }

  public void setAutoRotate(boolean value) {
    editor.putBoolean("autoRotate", value);
    editor.apply();
  }

  /** Controller device: keep local screen on while a control/mirror UI is visible. Default on. */
  public boolean getKeepScreenOnDuringControl() {
    return sharedPreferences.getBoolean("keepScreenOnDuringControl", true);
  }

  public void setKeepScreenOnDuringControl(boolean value) {
    editor.putBoolean("keepScreenOnDuringControl", value);
    editor.apply();
  }

  public String getLocalUUID() {
    if (!sharedPreferences.contains("UUID")) {
      editor.putString("UUID", UUID.randomUUID().toString());
      editor.apply();
    }
    return sharedPreferences.getString("UUID", "");
  }

  /** Allowed TCP probe timeouts (ms). Default is the largest: 300. */
  public static final int REACHABILITY_TIMEOUT_DEFAULT_MS = 300;
  public static final int[] REACHABILITY_TIMEOUT_OPTIONS_MS = {100, 200, 300};

  public int getReachabilityTimeoutMs() {
    return clampReachabilityTimeoutMs(
        sharedPreferences.getInt("reachabilityTimeoutMs", REACHABILITY_TIMEOUT_DEFAULT_MS));
  }

  public void setReachabilityTimeoutMs(int value) {
    editor.putInt("reachabilityTimeoutMs", clampReachabilityTimeoutMs(value));
    editor.apply();
  }

  public static int clampReachabilityTimeoutMs(int timeoutMs) {
    int best = REACHABILITY_TIMEOUT_DEFAULT_MS;
    int bestDiff = Integer.MAX_VALUE;
    for (int option : REACHABILITY_TIMEOUT_OPTIONS_MS) {
      int diff = Math.abs(option - timeoutMs);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = option;
      }
    }
    return best;
  }

  public Setting(SharedPreferences sharedPreferences) {
    this.sharedPreferences = sharedPreferences;
    this.editor = sharedPreferences.edit();
  }
}
