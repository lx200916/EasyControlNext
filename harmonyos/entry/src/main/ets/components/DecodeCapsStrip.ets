/**
 * Settings → 通用: local OH_VideoDecoder / OH_AudioCodec capability test.
 * libadb_core.so loads only when the user taps 测试.
 */

import { DecoderCapsResult } from '../native/AdbCoreTypes';

interface DecodeCapsNs {
  probeDecoderCaps: () => DecoderCapsResult;
}

function mark(ok: boolean): string {
  return ok ? '可用' : '不可用';
}

@Component
export struct DecodeCapsStrip {
  @State private statusLine: string = '';
  @State private avcLine: string = '';
  @State private hevcLine: string = '';
  @State private opusLine: string = '';
  @State private aacLine: string = '';
  @State private hasResult: boolean = false;
  @State private allOk: boolean = false;
  @State private busy: boolean = false;

  aboutToAppear(): void {
    this.statusLine = '';
    this.hasResult = false;
  }

  private runProbe(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusLine = '测试中…';
    void import('../native/DecodeCaps')
      .then((ns: DecodeCapsNs) => {
        const caps: DecoderCapsResult = ns.probeDecoderCaps();
        this.avcLine = `H.264（AVC）  ${mark(caps.avc)}`;
        this.hevcLine = `H.265（HEVC）  ${mark(caps.hevc)}`;
        this.opusLine = `Opus  ${mark(caps.opus)}`;
        this.aacLine = `AAC  ${mark(caps.aac)}`;
        this.allOk = caps.avc && caps.hevc && caps.opus && caps.aac;
        this.hasResult = true;
        if (!caps.avc) {
          this.statusLine = 'H.264 不可用，会话无法出画';
        } else if (!caps.hevc) {
          this.statusLine = 'H.265 不可用，会话会回退 H.264';
        } else {
          this.statusLine = '视频硬件解码可用';
        }
        this.busy = false;
      })
      .catch((e: Object) => {
        const msg = e instanceof Error ? e.message : String(e);
        this.hasResult = false;
        this.allOk = false;
        this.statusLine = `测试失败 · ${msg}`;
        this.busy = false;
      });
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text($r('app.string.settings_decode_caps'))
            .fontSize(16)
            .fontColor($r('app.color.ink'))
          Text($r('app.string.settings_decode_caps_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text($r('app.string.settings_decode_caps_run'))
          .fontSize(14)
          .fontColor(this.busy ? $r('app.color.text_secondary') : $r('app.color.accent_blue'))
      }
      .width('100%')
      .onClick(() => {
        this.runProbe();
      })

      if (this.statusLine.length > 0) {
        Text(this.statusLine)
          .fontSize(12)
          .fontColor(this.hasResult && this.allOk
            ? $r('app.color.success')
            : $r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.hasResult) {
        Column({ space: 4 }) {
          Text(this.avcLine)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(this.hevcLine)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(this.opusLine)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(this.aacLine)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }
}
