/**
 * Device list row.
 * - compact (preferSplit sidebar): name + address + subtle type icon
 * - full (sm): denser card with 连接 / 管理
 */

import { Device, displayDeviceName, isLazyDeviceName } from '../model/Device';
import { formatDeviceEndpoint } from '../model/MockDevices';

@Component
export struct DeviceCard {
  @Prop device: Device = new Device();
  @Prop selected: boolean = false;
  /** Sidebar row — no action chrome; selection only. */
  @Prop compact: boolean = false;
  onConnect: (device: Device) => void = (_device: Device) => {};
  onManage: (device: Device) => void = (_device: Device) => {};
  onSelect: (device: Device) => void = (_device: Device) => {};

  private displayName(): string {
    return displayDeviceName(this.device);
  }

  private nameColor(): ResourceColor {
    return isLazyDeviceName(this.device.name)
      ? $r('app.color.text_secondary')
      : $r('app.color.ink');
  }

  build() {
    if (this.compact) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.wifi'))
          .fontSize(18)
          .fontColor([this.selected ? $r('app.color.accent_blue') : $r('app.color.text_secondary')])
          .opacity(this.selected ? 1 : 0.55)

        Column({ space: 2 }) {
          Text(this.displayName())
            .fontSize(16)
            .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.nameColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(formatDeviceEndpoint(this.device))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(this.selected
        ? $r('app.color.accent_container')
        : $r('app.color.surface_card'))
      .borderRadius($r('app.float.radius_md'))
      .border({
        width: this.selected ? 1.5 : 0,
        color: $r('app.color.accent_blue'),
      })
      .onClick(() => {
        this.onSelect(this.device);
      })
    } else {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.wifi'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
            .opacity(0.6)

          Column({ space: 3 }) {
            Text(this.displayName())
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.nameColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(formatDeviceEndpoint(this.device))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .onClick(() => {
          this.onSelect(this.device);
        })

        Row({ space: 8 }) {
          Button($r('app.string.action_manage'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.accent_container'))
            .fontColor($r('app.color.accent_blue'))
            .hitTestBehavior(HitTestMode.Default)
            .onClick(() => {
              this.onManage(this.device);
            })

          Button($r('app.string.action_connect'))
            .type(ButtonType.Capsule)
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.brand_ink'))
            .fontColor($r('app.color.on_brand_ink'))
            .hitTestBehavior(HitTestMode.Default)
            .onClick(() => {
              this.onConnect(this.device);
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius($r('app.float.radius_device_card'))
    }
  }
}
