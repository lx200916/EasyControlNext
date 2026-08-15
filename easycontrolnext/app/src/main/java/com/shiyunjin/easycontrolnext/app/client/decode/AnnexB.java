package com.shiyunjin.easycontrolnext.app.client.decode;

/**
 * Lightweight Annex-B NAL scan for live-queue decisions (CSD vs IDR vs P).
 */
public final class AnnexB {
  private AnnexB() {
  }

  public static final class Kind {
    public final boolean csd;
    public final boolean idr;

    Kind(boolean csd, boolean idr) {
      this.csd = csd;
      this.idr = idr;
    }
  }

  public static Kind classify(byte[] data, boolean hevc) {
    if (data == null || data.length == 0) return new Kind(false, false);
    boolean hasParam = false;
    boolean hasIdr = false;
    boolean hasVcl = false;
    int i = 0;
    int n = data.length;
    while (i < n - 2) {
      int sc = startCodeLen(data, i, n);
      if (sc == 0) {
        i++;
        continue;
      }
      int nal = i + sc;
      if (nal >= n) break;
      if (hevc) {
        int type = (data[nal] >> 1) & 0x3f;
        if (type == 32 || type == 33 || type == 34) {
          hasParam = true;
        } else if (type == 19 || type == 20 || type == 21) {
          hasIdr = true;
          hasVcl = true;
        } else if (type <= 31) {
          hasVcl = true;
        }
      } else {
        int type = data[nal] & 0x1f;
        if (type == 7 || type == 8) {
          hasParam = true;
        } else if (type == 5) {
          hasIdr = true;
          hasVcl = true;
        } else if (type >= 1 && type <= 4) {
          hasVcl = true;
        }
      }
      i = findNextStart(data, nal, n);
    }
    return new Kind(hasParam && !hasVcl, hasIdr);
  }

  private static int startCodeLen(byte[] d, int i, int n) {
    if (d[i] != 0 || d[i + 1] != 0) return 0;
    if (d[i + 2] == 1) return 3;
    if (i + 3 < n && d[i + 2] == 0 && d[i + 3] == 1) return 4;
    return 0;
  }

  private static int findNextStart(byte[] d, int from, int n) {
    for (int i = from; i < n - 2; i++) {
      if (startCodeLen(d, i, n) > 0) return i;
    }
    return n;
  }
}
