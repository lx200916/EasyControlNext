package com.shiyunjin.easycontrolnext.server.helper;

import android.media.MediaCodec;
import android.os.Bundle;

/**
 * Session-hot bitrate / FPS adaptation from write-time and client arrival delay.
 * Never restarts the encoder; {@link MediaCodec#setParameters} failures are ignored.
 */
public final class StreamAdapt {
  private static final Object LOCK = new Object();

  static final long WRITE_SLOW_MS = 35;
  static final long WRITE_TIMEOUT_MS = 100;
  static final int DELAY_HIGH_MS = 80;
  static final int DELAY_CRITICAL_MS = 180;
  static final long DOWN_COOLDOWN_MS = 700;
  static final long UP_COOLDOWN_MS = 2200;
  static final int GOOD_STREAK_FOR_UP = 6;
  static final int BAD_STREAK_FOR_DOWN = 2;
  static final long FPS_DOWN_AFTER_MS = 1600;
  static final long FPS_UP_AFTER_MS = 3000;
  static final long SYNC_COOLDOWN_MS = 300;
  static final int WRITE_WINDOW = 8;

  private static int maxBitrate;
  private static int minBitrate;
  private static int maxFps;
  private static int minFps;
  private static int currentBitrate;
  private static int currentFps;

  private static boolean bitrateParamsOk = true;
  private static boolean fpsParamsOk = true;
  private static boolean syncParamsOk = true;

  private static final long[] writeMsWindow = new long[WRITE_WINDOW];
  private static int writeCount;
  private static int writeIdx;
  private static long lastWriteMs;

  private static long lastDownAt;
  private static long lastUpAt;
  private static int goodStreak;
  private static int badStreak;
  private static long congestedSince;
  private static boolean fpsReduced;
  private static long fpsReducedAt;

  private static volatile boolean dropUntilIdr;
  private static int lastClientDelayMs;
  private static long lastClientDelayAt;
  private static boolean pendingIdrRequest;
  private static boolean pendingApply;
  private static int appliedBitrate;
  private static int appliedFps;
  private static long lastSyncAt;

  private StreamAdapt() {
  }

  public static void init(int bitrateBps, int fps) {
    synchronized (LOCK) {
      maxBitrate = Math.max(250_000, bitrateBps);
      minBitrate = Math.max(250_000, maxBitrate / 8);
      maxFps = Math.max(1, fps);
      minFps = Math.max(15, maxFps / 2);
      if (minFps >= maxFps) minFps = maxFps;
      currentBitrate = maxBitrate;
      currentFps = maxFps;
      appliedBitrate = 0;
      appliedFps = 0;
      bitrateParamsOk = true;
      fpsParamsOk = true;
      syncParamsOk = true;
      writeCount = 0;
      writeIdx = 0;
      lastWriteMs = 0;
      lastDownAt = 0;
      lastUpAt = 0;
      goodStreak = 0;
      badStreak = 0;
      congestedSince = 0;
      fpsReduced = false;
      fpsReducedAt = 0;
      dropUntilIdr = false;
      lastClientDelayMs = 0;
      lastClientDelayAt = 0;
      pendingIdrRequest = false;
      pendingApply = false;
      lastSyncAt = 0;
    }
  }

  public static int bitrateForFormat(int fallbackBps) {
    synchronized (LOCK) {
      return currentBitrate > 0 ? currentBitrate : fallbackBps;
    }
  }

  public static float fpsForFormat(int fallbackFps) {
    synchronized (LOCK) {
      return currentFps > 0 ? currentFps : fallbackFps;
    }
  }

  public static boolean shouldDropNonKey() {
    return dropUntilIdr;
  }

  public static void onKeyFrameSent() {
    dropUntilIdr = false;
  }

  public static void onWriteMs(long writeMs) {
    synchronized (LOCK) {
      lastWriteMs = writeMs;
      writeMsWindow[writeIdx] = writeMs;
      writeIdx = (writeIdx + 1) % WRITE_WINDOW;
      if (writeCount < WRITE_WINDOW) writeCount++;
      if (writeMs >= WRITE_TIMEOUT_MS) {
        dropUntilIdr = true;
        pendingIdrRequest = true;
      }
      if (writeCount >= 3) {
        evaluateLocked(System.currentTimeMillis());
        pendingApply = true;
      }
    }
  }

  public static void onClientFeedback(boolean requestIdr, int delayMs) {
    synchronized (LOCK) {
      lastClientDelayMs = Math.max(0, delayMs);
      lastClientDelayAt = System.currentTimeMillis();
      if (requestIdr) {
        dropUntilIdr = true;
        pendingIdrRequest = true;
      }
      evaluateLocked(lastClientDelayAt);
      pendingApply = true;
    }
  }

  public static void applyPending(MediaCodec codec) {
    if (codec == null) return;
    boolean wantIdr;
    int br;
    int fps;
    boolean apply;
    synchronized (LOCK) {
      apply = pendingApply;
      pendingApply = false;
      wantIdr = pendingIdrRequest;
      pendingIdrRequest = false;
      br = currentBitrate;
      fps = currentFps;
    }
    if (apply) {
      if (br != appliedBitrate) {
        if (setBitrate(codec, br)) appliedBitrate = br;
      }
      if (fps != appliedFps) {
        if (setFps(codec, fps)) appliedFps = fps;
      }
    }
    if (wantIdr) requestSyncFrame(codec);
  }

  private static void evaluateLocked(long now) {
    long avg = writeAvgLocked();
    boolean writeSlow = writeCount >= 3 && avg >= WRITE_SLOW_MS;
    boolean writeTimeout = lastWriteMs >= WRITE_TIMEOUT_MS;
    boolean delayFresh = lastClientDelayAt > 0 && (now - lastClientDelayAt) < 2000;
    boolean delayHigh = delayFresh && lastClientDelayMs >= DELAY_HIGH_MS;
    boolean delayCrit = delayFresh && lastClientDelayMs >= DELAY_CRITICAL_MS;
    boolean congested = writeSlow || writeTimeout || delayHigh || delayCrit;

    if (congested) {
      goodStreak = 0;
      badStreak++;
      if (congestedSince == 0) congestedSince = now;
      boolean strong = writeTimeout || delayCrit;
      if (badStreak >= BAD_STREAK_FOR_DOWN && now - lastDownAt >= DOWN_COOLDOWN_MS) {
        int next = strong ? (int) (currentBitrate * 0.60) : (int) (currentBitrate * 0.75);
        next = Math.max(minBitrate, next);
        if (next < currentBitrate) {
          currentBitrate = next;
          lastDownAt = now;
          System.out.println("StreamAdapt: bitrate down → " + currentBitrate
            + " writeAvg=" + avg + " writeMs=" + lastWriteMs + " delayMs=" + lastClientDelayMs);
        }
      }
      if (currentBitrate <= minBitrate && currentFps > minFps
        && congestedSince > 0 && now - congestedSince >= FPS_DOWN_AFTER_MS
        && now - lastDownAt >= DOWN_COOLDOWN_MS) {
        currentFps = minFps;
        fpsReduced = true;
        fpsReducedAt = now;
        lastDownAt = now;
        System.out.println("StreamAdapt: fps down → " + currentFps);
      }
    } else {
      badStreak = 0;
      congestedSince = 0;
      goodStreak++;
      if (goodStreak >= GOOD_STREAK_FOR_UP && now - lastUpAt >= UP_COOLDOWN_MS
        && now - lastDownAt >= UP_COOLDOWN_MS) {
        if (currentBitrate < maxBitrate) {
          int next = Math.min(maxBitrate, (int) (currentBitrate * 1.12));
          if (next == currentBitrate) next = Math.min(maxBitrate, currentBitrate + 80_000);
          currentBitrate = next;
          lastUpAt = now;
          System.out.println("StreamAdapt: bitrate up → " + currentBitrate);
        } else if (fpsReduced && currentFps < maxFps && now - fpsReducedAt >= FPS_UP_AFTER_MS) {
          currentFps = maxFps;
          fpsReduced = false;
          lastUpAt = now;
          System.out.println("StreamAdapt: fps up → " + currentFps);
        }
      }
    }
  }

  private static long writeAvgLocked() {
    if (writeCount <= 0) return 0;
    long sum = 0;
    int n = Math.min(writeCount, WRITE_WINDOW);
    for (int i = 0; i < n; i++) sum += writeMsWindow[i];
    return sum / n;
  }

  private static boolean setBitrate(MediaCodec codec, int bps) {
    if (!bitrateParamsOk) return false;
    try {
      Bundle b = new Bundle();
      b.putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bps);
      codec.setParameters(b);
      return true;
    } catch (Throwable t) {
      bitrateParamsOk = false;
      System.out.println("StreamAdapt: setParameters bitrate unsupported: " + t);
      return false;
    }
  }

  private static boolean setFps(MediaCodec codec, int fps) {
    if (!fpsParamsOk) return false;
    try {
      Bundle b = new Bundle();
      b.putFloat("max-fps-to-encoder", fps);
      codec.setParameters(b);
      return true;
    } catch (Throwable t) {
      fpsParamsOk = false;
      System.out.println("StreamAdapt: setParameters fps unsupported: " + t);
      return false;
    }
  }

  private static void requestSyncFrame(MediaCodec codec) {
    if (!syncParamsOk) return;
    long now = System.currentTimeMillis();
    synchronized (LOCK) {
      if (now - lastSyncAt < SYNC_COOLDOWN_MS) return;
      lastSyncAt = now;
    }
    try {
      Bundle b = new Bundle();
      b.putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0);
      codec.setParameters(b);
    } catch (Throwable t) {
      syncParamsOk = false;
      System.out.println("StreamAdapt: REQUEST_SYNC_FRAME unsupported: " + t);
    }
  }
}
