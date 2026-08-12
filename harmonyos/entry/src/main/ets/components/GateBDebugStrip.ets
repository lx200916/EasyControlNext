/**
 * Compact native capability check — Settings → Diagnostics only (not Home chrome).
 */

import { GateBProbeResult, runGateBProbe } from '../native/AdbCore';

@Component
export struct GateBDebugStrip {
  @Consume('safeBottomVp') safeBottomVp: number;
  /** When true, omit page-edge safe-bottom (embedded in Settings card). */
  @Prop embedded: boolean = false;
  @State private probeLabel: string = '点击检测原生能力';
  @State private probeOk: boolean = false;

  aboutToAppear(): void {
    this.probeLabel = '点击检测原生能力';
  }

  private refreshProbe(): void {
    const probe: GateBProbeResult = runGateBProbe();
    this.probeOk = probe.ok && probe.roundTripOk;
    this.probeLabel = probe.ok
      ? `原生库正常 · v${probe.version}`
      : `检测失败 · ${probe.detail}`;
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

        Button('检测')
          .type(ButtonType.Normal)
          .fontSize(13)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.ink'))
          .onClick(() => {
            this.refreshProbe();
          })
      }
      .width('100%')
      .constraintSize({ minHeight: $r('app.float.debug_strip_height') })
      .padding(this.embedded
        ? { left: 12, right: 12, top: 10, bottom: 10 }
        : { left: $r('app.float.space_page_h'), right: $r('app.float.space_page_h') })
    }
    .width('100%')
    .padding({ bottom: this.embedded ? 0 : this.safeBottomVp })
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.surface_muted'))
    .borderRadius(this.embedded ? $r('app.float.radius_sm') : 0)
  }
}
