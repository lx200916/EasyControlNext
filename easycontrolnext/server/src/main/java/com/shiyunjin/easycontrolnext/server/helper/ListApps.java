package com.shiyunjin.easycontrolnext.server.helper;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Looper;

import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * One-shot helper run via {@code app_process} to list installed apps with resolved labels
 * (PackageManager.loadLabel), which works across OEMs where dumpsys label fields are missing.
 *
 * Output lines: {@code packageName\tlabel}
 */
public final class ListApps {
  private ListApps() {
  }

  public static void main(String... args) {
    boolean includeSystem = false;
    if (args != null) {
      for (String arg : args) {
        if (arg != null && arg.startsWith("includeSystem=")) {
          String v = arg.substring("includeSystem=".length());
          includeSystem = "1".equals(v) || "true".equalsIgnoreCase(v);
        }
      }
    }
    try {
      Context context = createContext();
      PackageManager pm = context.getPackageManager();
      Map<String, String> apps = new LinkedHashMap<>();

      // Prefer launchable apps first (typical for virtual-display startApp)
      Intent launcher = new Intent(Intent.ACTION_MAIN);
      launcher.addCategory(Intent.CATEGORY_LAUNCHER);
      List<ResolveInfo> activities = pm.queryIntentActivities(launcher, 0);
      if (activities != null) {
        for (ResolveInfo ri : activities) {
          if (ri == null || ri.activityInfo == null) continue;
          ApplicationInfo ai = ri.activityInfo.applicationInfo;
          if (ai == null) continue;
          if (!includeSystem && (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
          String pkg = ri.activityInfo.packageName;
          if (pkg == null || pkg.isEmpty() || apps.containsKey(pkg)) continue;
          apps.put(pkg, safeLabel(ri.loadLabel(pm), pkg));
        }
      }

      // Fill remaining installed packages (non-launcher / missing from query)
      List<ApplicationInfo> installed = pm.getInstalledApplications(0);
      if (installed != null) {
        for (ApplicationInfo ai : installed) {
          if (ai == null || ai.packageName == null) continue;
          if (!includeSystem && (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;
          if (apps.containsKey(ai.packageName)) continue;
          apps.put(ai.packageName, safeLabel(pm.getApplicationLabel(ai), ai.packageName));
        }
      }

      StringBuilder sb = new StringBuilder();
      for (Map.Entry<String, String> e : apps.entrySet()) {
        sb.append(e.getKey()).append('\t').append(e.getValue()).append('\n');
      }
      System.out.print(sb);
      System.out.flush();
      System.exit(0);
    } catch (Throwable t) {
      t.printStackTrace(System.err);
      System.exit(1);
    }
  }

  private static String safeLabel(CharSequence label, String pkg) {
    if (label == null) return pkg;
    String s = label.toString().replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').trim();
    return s.isEmpty() ? pkg : s;
  }

  private static Context createContext() throws Exception {
    try {
      Looper.prepareMainLooper();
    } catch (Throwable ignored) {
      // already prepared
    }
    Class<?> atClass = Class.forName("android.app.ActivityThread");
    Method systemMain = atClass.getDeclaredMethod("systemMain");
    Object activityThread = systemMain.invoke(null);
    Method getSystemContext = atClass.getDeclaredMethod("getSystemContext");
    Context context = (Context) getSystemContext.invoke(activityThread);
    if (context == null) throw new IllegalStateException("null system context");
    return context;
  }
}
