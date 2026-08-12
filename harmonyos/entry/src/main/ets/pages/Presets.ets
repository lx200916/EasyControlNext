/**
 * Presets lite — list built-in ConnectionPreset and apply (link) to a saved device.
 */

import { ConnectionPreset } from '../model/ConnectionPreset';
import { Device } from '../model/Device';
import { DeviceStore } from '../model/DeviceStore';
import { PresetStore } from '../model/PresetStore';

@Component
export struct Presets {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  @StorageLink('deviceStoreRevision') storeRevision: number = 0;
  @State private presets: ConnectionPreset[] = [];
  @State private devices: Device[] = [];
  @State private showDevicePicker: boolean = false;
  @State private pendingPreset: ConnectionPreset | undefined = undefined;

  aboutToAppear(): void {
    this.presets = PresetStore.all();
    this.devices = DeviceStore.getAll();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2000,
      });
    } catch (_e) {
      // preview hosts
    }
  }

  private beginApply(preset: ConnectionPreset): void {
    this.devices = DeviceStore.getAll();
    if (this.devices.length === 0) {
      this.toast('请先添加设备');
      return;
    }
    this.pendingPreset = preset;
    this.showDevicePicker = true;
  }

  private applyToDevice(device: Device): void {
    const preset = this.pendingPreset;
    if (preset === undefined) {
      return;
    }
    const target = DeviceStore.findByUuid(device.uuid);
    if (target === undefined) {
      this.toast('设备不存在');
      return;
    }
    preset.applyTo(target);
    void DeviceStore.upsert(target).then(() => {
      this.showDevicePicker = false;
      this.pendingPreset = undefined;
      this.toast(`已应用到「${target.name}」`);
    }).catch(() => {
      this.toast('保存失败');
    });
  }

  @Builder
  private devicePickerBuilder() {
    Column({ space: 8 }) {
      Text(this.pendingPreset !== undefined
        ? `将「${this.pendingPreset.name}」应用到设备`
        : '选择设备')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
      Text('会写入该设备的流媒体字段并链接 presetId')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      ForEach(this.devices, (device: Device) => {
        Column({ space: 2 }) {
          Text(device.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(DeviceStore.endpointOf(device))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 12, bottom: 12 })
        .onClick(() => {
          this.applyToDevice(device);
        })
      }, (device: Device) => device.uuid)

      Button('取消')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .margin({ top: 8 })
        .backgroundColor($r('app.color.surface_muted'))
        .fontColor($r('app.color.ink'))
        .borderRadius($r('app.float.radius_md'))
        .onClick(() => {
          this.showDevicePicker = false;
          this.pendingPreset = undefined;
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 })
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([$r('app.color.ink')])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.pathStack.pop();
          })

          Column({ space: 2 }) {
            Text($r('app.string.presets_title'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text($r('app.string.presets_subtitle'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({
          left: 8,
          right: $r('app.float.space_page_h'),
          top: 8 + this.safeTopVp,
          bottom: 8,
        })

        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.presets, (preset: ConnectionPreset) => {
              Column({ space: 6 }) {
                Row() {
                  Text(preset.name)
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                    .layoutWeight(1)
                  Text('内置')
                    .fontSize(11)
                    .fontColor($r('app.color.accent_blue'))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor($r('app.color.accent_container'))
                    .borderRadius(8)
                }
                .width('100%')

                Text(PresetStore.summaryLine(preset))
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                Button($r('app.string.presets_apply_to_device'))
                  .type(ButtonType.Normal)
                  .width('100%')
                  .height(40)
                  .margin({ top: 4 })
                  .backgroundColor($r('app.color.brand_ink'))
                  .fontColor(Color.White)
                  .borderRadius($r('app.float.radius_md'))
                  .onClick(() => {
                    this.beginApply(preset);
                  })
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.surface_card'))
              .borderRadius($r('app.float.radius_detail_panel'))
            }, (preset: ConnectionPreset) => preset.id)

            Text($r('app.string.presets_lite_note'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 16 })
          }
          .width('100%')
          .padding({
            left: $r('app.float.space_page_h'),
            right: $r('app.float.space_page_h'),
            bottom: 24 + this.safeBottomVp,
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
    .bindSheet($$this.showDevicePicker, this.devicePickerBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      backgroundColor: $r('app.color.surface_card'),
    })
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
