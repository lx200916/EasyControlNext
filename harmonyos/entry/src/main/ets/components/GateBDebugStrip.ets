/**
 * Compact native capability check — Settings → Diagnostics only (not Home chrome).
 * libadb_core.so loads only when the user taps 检测.
 */

import { GateBProbeResult } from '../native/AdbCoreTypes';

interface AdbCoreNs {
  runGateBProbe: () => GateBProbeResult;
}

@Component
export struct GateBDebugStrip {
  @Consume('safeBottomVp') safeBottomVp: number;
  /** When true, omit page-edge safe-bottom (embedded in Settings card). */
  @Prop embedded: boolean = false;
  @State private probeLabel: string = '点击检测原生能力';
  @State private probeOk: boolean = false;
  @State private probeBusy: boolean = false;

  aboutToAppear(): void {
    this.probeLabel = '点击检测原生能力';
  }

  private refreshProbe(): void {
    if (this.probeBusy) {
      return;
    }
    this.probeBusy = true;
    this.probeLabel = '检测中…';
    void import('../native/AdbCore')
      .then((ns: AdbCoreNs) => {
        const probe: GateBProbeResult = ns.runGateBProbe();
        this.probeOk = probe.ok && probe.roundTripOk;
        this.probeLabel = probe.ok
          ? `原生库正常 · v${probe.version}`
          : `检测失败 · ${probe.detail}`;
        this.probeBusy = false;
      })
      .catch((e: Object) => {
        const msg = e instanceof Error ? e.message : String(e);
        this.probeOk = false;
        this.probeLabel = `检测失败 · ${msg}`;
        this.probeBusy = false;
      });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.probeLabel)
          .fontSize(13)
          .fontColor(this.probeOk ? $r('app.color.success') : $r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('检测')
          .fontSize(14)
          .fontColor(this.probeBusy ? $r('app.color.text_secondary') : $r('app.color.accent_blue'))
      }
      .width('100%')
      .constraintSize({ minHeight: $r('app.float.debug_strip_height') })
      .padding(this.embedded
        ? { left: 12, right: 12, top: 10, bottom: 10 }
        : { left: $r('app.float.space_page_h'), right: $r('app.float.space_page_h') })
      .onClick(() => {
        this.refreshProbe();
      })
    }
    .width('100%')
    .padding({ bottom: this.embedded ? 0 : this.safeBottomVp })
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.surface_muted'))
    .borderRadius(this.embedded ? $r('app.float.radius_sm') : 0)
  }
}
