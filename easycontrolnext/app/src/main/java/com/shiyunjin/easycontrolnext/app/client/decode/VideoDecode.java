package com.shiyunjin.easycontrolnext.app.client.decode;

import android.media.MediaCodec;
import android.media.MediaFormat;
import android.os.Build;
import android.os.Handler;
import android.os.SystemClock;
import android.util.Pair;
import android.view.Surface;

import androidx.annotation.NonNull;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Objects;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * Live decoder: keep reading the socket on the caller thread, hold few pending AUs,
 * drop stale work, and only render the newest output.
 */
public class VideoDecode {
  /** Match HarmonyOS {@code LIVE_MAX_PENDING_AUS}. */
  static final int LIVE_MAX_PENDING_AUS = 6;
  static final long STALE_OUTPUT_US = 40_000L;

  public interface Feedback {
    void onNeedIdr();

    void onArrivalDelayMs(int delayMs);
  }

  private static final class PendingAu {
    final long pts;
    final byte[] data;
    final boolean csd;
    final boolean idr;

    PendingAu(long pts, byte[] data, boolean csd, boolean idr) {
      this.pts = pts;
      this.data = data;
      this.csd = csd;
      this.idr = idr;
    }
  }

  private MediaCodec decodec;
  private final boolean useH265;
  private final Feedback feedback;
  private final Object lock = new Object();
  private final ArrayList<PendingAu> pending = new ArrayList<>();
  private final LinkedBlockingQueue<Integer> intputBufferQueue = new LinkedBlockingQueue<>();
  private volatile long latestIncomingPts;
  private boolean waitingForIdr;
  private long firstPts = Long.MIN_VALUE;
  private long firstLocalUs;

  private final MediaCodec.Callback callback = new MediaCodec.Callback() {
    @Override
    public void onInputBufferAvailable(@NonNull MediaCodec mediaCodec, int inIndex) {
      intputBufferQueue.offer(inIndex);
      tryFeed();
    }

    @Override
    public void onOutputBufferAvailable(@NonNull MediaCodec mediaCodec, int outIndex, @NonNull MediaCodec.BufferInfo bufferInfo) {
      try {
        boolean codecConfig = (bufferInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
        if (codecConfig || bufferInfo.size == 0) {
          mediaCodec.releaseOutputBuffer(outIndex, false);
          return;
        }
        long latest = latestIncomingPts;
        boolean stale = latest > 0 && bufferInfo.presentationTimeUs > 0
          && bufferInfo.presentationTimeUs + STALE_OUTPUT_US < latest;
        mediaCodec.releaseOutputBuffer(outIndex, !stale);
      } catch (IllegalStateException ignored) {
      }
    }

    @Override
    public void onError(@NonNull MediaCodec mediaCodec, @NonNull MediaCodec.CodecException e) {
    }

    @Override
    public void onOutputFormatChanged(@NonNull MediaCodec mediaCodec, @NonNull MediaFormat format) {
    }
  };

  public VideoDecode(Pair<Integer, Integer> videoSize, Surface surface, ByteBuffer csd0, ByteBuffer csd1, Handler playHandler, Feedback feedback) throws IOException {
    this.useH265 = csd1 == null;
    this.feedback = feedback;
    setVideoDecodec(videoSize, surface, csd0, csd1, playHandler);
  }

  public void release() {
    try {
      decodec.stop();
      decodec.release();
    } catch (Exception ignored) {
    }
    synchronized (lock) {
      pending.clear();
    }
    intputBufferQueue.clear();
  }

  /**
   * Caller must keep reading the socket. This method never blocks on the decoder.
   */
  public void decodeIn(ByteBuffer data) {
    if (data == null || data.remaining() < 8) return;
    long pts = data.getLong();
    byte[] payload = new byte[data.remaining()];
    data.get(payload);
    AnnexB.Kind kind = AnnexB.classify(payload, useH265);
    if (!kind.csd && pts > 0) {
      latestIncomingPts = Math.max(latestIncomingPts, pts);
      noteArrival(pts);
    }
    boolean needIdr;
    synchronized (lock) {
      if (waitingForIdr && !kind.csd && !kind.idr) {
        needIdr = true;
      } else {
        pending.add(new PendingAu(pts, payload, kind.csd, kind.idr));
        if (kind.idr) waitingForIdr = false;
        needIdr = dropOldLiveAusLocked();
      }
    }
    if (needIdr) notifyNeedIdr();
    tryFeed();
  }

  private void noteArrival(long pts) {
    if (feedback == null) return;
    long nowUs = SystemClock.elapsedRealtimeNanos() / 1000L;
    if (firstPts == Long.MIN_VALUE || pts + 1_000_000L < firstPts) {
      firstPts = pts;
      firstLocalUs = nowUs;
      return;
    }
    long expected = firstLocalUs + (pts - firstPts);
    long delayUs = nowUs - expected;
    int delayMs = (int) Math.max(0L, Math.min(delayUs / 1000L, 30_000L));
    feedback.onArrivalDelayMs(delayMs);
  }

  /** @return true if a P-frame was dropped and the server should send an IDR */
  private boolean dropOldLiveAusLocked() {
    boolean needIdr = false;
    while (pending.size() > LIVE_MAX_PENDING_AUS) {
      int dropAt = indexOfOldestDroppable(false);
      if (dropAt < 0) dropAt = indexOfOldestDroppable(true);
      if (dropAt < 0) break;
      PendingAu dropped = pending.remove(dropAt);
      if (!dropped.idr && !dropped.csd) {
        waitingForIdr = true;
        needIdr = true;
      }
    }
    if (waitingForIdr) {
      for (int i = pending.size() - 1; i >= 0; i--) {
        PendingAu au = pending.get(i);
        if (!au.csd && !au.idr) pending.remove(i);
      }
    }
    return needIdr;
  }

  /** Prefer oldest non-CSD non-IDR; {@code allowIdr} also allows dropping an old IDR. */
  private int indexOfOldestDroppable(boolean allowIdr) {
    for (int i = 0; i < pending.size(); i++) {
      PendingAu au = pending.get(i);
      if (au.csd) continue;
      if (!allowIdr && au.idr) continue;
      return i;
    }
    return -1;
  }

  private void notifyNeedIdr() {
    if (feedback != null) feedback.onNeedIdr();
  }

  private void tryFeed() {
    boolean needIdr = false;
    while (true) {
      Integer inIndex;
      PendingAu au;
      synchronized (lock) {
        au = takeFeedableLocked();
        if (au == null) break;
        inIndex = intputBufferQueue.poll();
        if (inIndex == null) {
          pending.add(0, au);
          break;
        }
      }
      try {
        ByteBuffer in = decodec.getInputBuffer(inIndex);
        if (in == null) {
          intputBufferQueue.offer(inIndex);
          synchronized (lock) {
            pending.add(0, au);
          }
          break;
        }
        if (au.data.length > in.remaining()) {
          intputBufferQueue.offer(inIndex);
          if (!au.csd) {
            synchronized (lock) {
              waitingForIdr = true;
            }
            needIdr = true;
          }
          continue;
        }
        in.clear();
        in.put(au.data);
        decodec.queueInputBuffer(inIndex, 0, au.data.length, au.pts, 0);
      } catch (IllegalStateException ignored) {
        break;
      }
    }
    if (needIdr) notifyNeedIdr();
  }

  private PendingAu takeFeedableLocked() {
    if (pending.isEmpty()) return null;
    if (waitingForIdr) {
      for (int i = 0; i < pending.size(); i++) {
        PendingAu au = pending.get(i);
        if (au.csd || au.idr) return pending.remove(i);
      }
      return null;
    }
    return pending.remove(0);
  }

  private void setVideoDecodec(Pair<Integer, Integer> videoSize, Surface surface, ByteBuffer csd0, ByteBuffer csd1, Handler playHandler) throws IOException {
    String codecMime = useH265 ? MediaFormat.MIMETYPE_VIDEO_HEVC : MediaFormat.MIMETYPE_VIDEO_AVC;
    try {
      String codecName = DecodecTools.getVideoDecoder(useH265);
      if (Objects.equals(codecName, "")) decodec = MediaCodec.createDecoderByType(codecMime);
      else decodec = MediaCodec.createByCodecName(codecName);
    } catch (Exception ignord) {
      decodec = MediaCodec.createDecoderByType(codecMime);
    }
    MediaFormat decodecFormat = MediaFormat.createVideoFormat(codecMime, videoSize.first, videoSize.second);
    csd0.position(8);
    decodecFormat.setByteBuffer("csd-0", csd0);
    if (!useH265) {
      csd1.position(8);
      decodecFormat.setByteBuffer("csd-1", csd1);
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && playHandler != null) {
      decodec.setCallback(callback, playHandler);
    } else decodec.setCallback(callback);
    decodec.configure(decodecFormat, surface, null, 0);
    decodec.start();
    csd0.position(0);
    decodeIn(csd0);
    if (!useH265) {
      csd1.position(0);
      decodeIn(csd1);
    }
  }
}
