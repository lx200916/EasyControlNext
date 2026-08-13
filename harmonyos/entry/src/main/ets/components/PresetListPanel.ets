/**
 * Shared preset manager list (Android PresetsListScreen).
 * Tap row to edit; duplicate / set-default / reset-or-delete on the card.
 */

import { common } from '@kit.AbilityKit';
import { ConnectionPreset } from '../model/ConnectionPreset';
import { PresetStore } from '../model/PresetStore';

@Component
export struct PresetListPanel {
  @Consume('pathStack') pathStack: NavPathStack;
  @StorageLink('presetStoreRevision') @Watch('onRevision') storeRevision: number = 0;
  @State private presets: ConnectionPreset[] = [];
  @State private defaultId: string = '';
  @State private pendingLinked: ConnectionPreset | undefined = undefined;

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void PresetStore.init(ctx).then(() => {
      this.reload();
    });
    this.reload();
  }

  private onRevision(): void {
    this.reload();
  }

  private reload(): void {
    this.presets = PresetStore.all();
    this.defaultId = PresetStore.defaultId();
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

  private openEditor(id: string): void {
    this.pathStack.pushPath({ name: 'preset', param: id });
  }

  private offerLinkedUpdate(preset: ConnectionPreset): void {
    if (PresetStore.linkedCount(preset.id) > 0) {
      this.pendingLinked = preset;
      this.askLinkedUpdate();
    }
  }

  private askLinkedUpdate(): void {
    const preset = this.pendingLinked;
    if (preset === undefined) {
      return;
    }
    const count = PresetStore.linkedCount(preset.id);
    AlertDialog.show({
      title: '更新已关联设备？',
      message: `是否用新选项更新仍关联「${preset.name}」的 ${count} 台设备？已解除关联的设备不会被改动。`,
      primaryButton: {
        value: '保持设备不变',
        action: () => {
          this.pendingLinked = undefined;
        },
      },
      secondaryButton: {
        value: '更新设备',
        action: () => {
          const target = this.pendingLinked;
          this.pendingLinked = undefined;
          if (target === undefined) {
            return;
          }
          void PresetStore.updateLinkedDevices(target).then((n: number) => {
            this.toast(`已更新 ${n} 台设备`);
          });
        },
      },
    });
  }

  private onSetDefault(preset: ConnectionPreset): void {
    void PresetStore.setDefaultId(preset.id).then(() => {
      this.reload();
      this.toast('已设为默认');
    });
  }

  private onDuplicate(preset: ConnectionPreset): void {
    void PresetStore.duplicate(preset, '（副本）').then(() => {
      this.reload();
      this.toast('已复制');
    });
  }

  private confirmDeleteOrReset(preset: ConnectionPreset): void {
    const isBuiltIn = preset.isBuiltIn;
    AlertDialog.show({
      title: isBuiltIn ? '恢复内置预设？' : '删除预设？',
      message: isBuiltIn
        ? '将此内置预设恢复为出厂选项。内置预设无法永久删除。'
        : `确定删除「${preset.name}」？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: isBuiltIn ? '恢复默认' : '删除',
        fontColor: isBuiltIn ? Color.Black : Color.Red,
        action: () => {
          if (isBuiltIn) {
            void PresetStore.resetBuiltIn(preset.id).then((reset: ConnectionPreset | undefined) => {
              this.reload();
              this.toast('已恢复内置预设');
              if (reset !== undefined) {
                this.offerLinkedUpdate(reset);
              }
            });
          } else {
            void PresetStore.deleteOrReset(preset.id).then(() => {
              this.reload();
              this.toast('已删除');
            });
          }
        },
      },
    });
  }

  @Builder
  private presetRow(preset: ConnectionPreset) {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 4 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text(preset.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .margin({ right: 8 })
            if (preset.id === this.defaultId) {
              Text('默认')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent_blue'))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.accent_container'))
                .borderRadius(8)
                .margin({ right: 6 })
            }
            if (preset.isBuiltIn) {
              Text('内置')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius(8)
            }
          }
          .width('100%')

          Text(PresetStore.summaryLine(preset))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .onClick(() => {
        this.openEditor(preset.id);
      })

      Flex({ wrap: FlexWrap.Wrap }) {
        if (preset.id !== this.defaultId) {
          Text($r('app.string.preset_set_default'))
            .fontSize(13)
            .fontColor($r('app.color.accent_blue'))
            .padding({ right: 14, top: 6, bottom: 2 })
            .onClick(() => {
              this.onSetDefault(preset);
            })
        }
        Text($r('app.string.preset_duplicate'))
          .fontSize(13)
          .fontColor($r('app.color.accent_blue'))
          .padding({ right: 14, top: 6, bottom: 2 })
          .onClick(() => {
            this.onDuplicate(preset);
          })
        if (preset.isBuiltIn) {
          Text($r('app.string.preset_reset'))
            .fontSize(13)
            .fontColor($r('app.color.accent_blue'))
            .padding({ right: 14, top: 6, bottom: 2 })
            .onClick(() => {
              this.confirmDeleteOrReset(preset);
            })
        } else {
          Text($r('app.string.preset_delete'))
            .fontSize(13)
            .fontColor(Color.Red)
            .padding({ right: 14, top: 6, bottom: 2 })
            .onClick(() => {
              this.confirmDeleteOrReset(preset);
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 0 }) {
      Text($r('app.string.preset_default_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Column() {
        Button($r('app.string.preset_create'))
          .type(ButtonType.Capsule)
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.brand_ink'))
          .fontColor($r('app.color.on_brand_ink'))
          .onClick(() => {
            this.openEditor('new');
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      ForEach(this.presets, (preset: ConnectionPreset, index: number) => {
        Column() {
          if (index > 0) {
            Divider().color($r('app.color.divider')).margin({ left: 16 })
          }
          this.presetRow(preset)
        }
        .width('100%')
      }, (preset: ConnectionPreset) => preset.id)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }
}
