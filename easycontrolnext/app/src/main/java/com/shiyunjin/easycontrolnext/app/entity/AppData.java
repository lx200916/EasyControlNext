package com.shiyunjin.easycontrolnext.app.entity;

import android.app.Activity;
import android.annotation.SuppressLint;
import android.content.ClipboardManager;
import android.content.Context;
import android.hardware.SensorManager;
import android.hardware.usb.UsbManager;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.view.WindowManager;

import com.shiyunjin.easycontrolnext.app.adb.AdbKeyPair;
import com.shiyunjin.easycontrolnext.app.helper.AppErrorLog;
import com.shiyunjin.easycontrolnext.app.helper.DbHelper;
import com.shiyunjin.easycontrolnext.app.helper.PublicTools;

public class AppData {
  @SuppressLint("StaticFieldLeak")
  public static Context applicationContext;
  @SuppressLint("StaticFieldLeak")
  public static Activity mainActivity;
  public static Handler uiHandler;

  // 数据库工具库
  public static DbHelper dbHelper;

  // 密钥文件
  public static AdbKeyPair keyPair;

  // 系统服务
  public static ClipboardManager clipBoard;
  public static WifiManager wifiManager;
  public static UsbManager usbManager;
  public static WindowManager windowManager;
  public static SensorManager sensorManager;

  // 设置值
  public static Setting setting;

  public static void init(Activity m) {
    mainActivity = m;
    applicationContext = m.getApplicationContext();
    uiHandler = new android.os.Handler(m.getMainLooper());
    dbHelper = new DbHelper(applicationContext);
    clipBoard = (ClipboardManager) applicationContext.getSystemService(Context.CLIPBOARD_SERVICE);
    wifiManager = (WifiManager) applicationContext.getSystemService(Context.WIFI_SERVICE);
    usbManager = (UsbManager) applicationContext.getSystemService(Context.USB_SERVICE);
    windowManager = (WindowManager) applicationContext.getSystemService(Context.WINDOW_SERVICE);
    sensorManager = (SensorManager) applicationContext.getSystemService(Context.SENSOR_SERVICE);
    setting = new Setting(applicationContext.getSharedPreferences("setting", Context.MODE_PRIVATE));
    AppErrorLog.init(applicationContext);
    AppErrorLog.installUncaughtHandler();
    // 读取密钥
    keyPair = PublicTools.readAdbKeyPair();
  }

}
