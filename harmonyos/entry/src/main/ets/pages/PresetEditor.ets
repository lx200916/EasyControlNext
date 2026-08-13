/**
 * Create / edit a connection preset (Android PresetEditorScreen).
 */

import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { CameraFacing, HevcPref, VideoSource } from '../model/Device';
import { ConnectionPreset, normalizeHevcProfile } from '../model/ConnectionPreset';
import { PresetStore } from '../model/PresetStore';

@Component
export struct PresetEditor {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('safeBottomVp') safeBottomVp: number;
  @Prop presetId: string = 'new';
  @State private isNew: boolean = true;
  @State private nameText: string = '自定义预设';
  @State private builtInKey: string = '';
  @State private linkedCount: number = 0;
  @State private videoSource: VideoSource = 'display';
  @State private cameraFacing: CameraFacing = 'back';
  @State private startAppText: string = '';
  @State private virtualWidthText: string = '';
  @State private virtualHeightText: string = '';
  @State private virtualDpiText: string = '';
  @State private isAudio: boolean = false;
  @State private listenClip: boolean = true;
  @State private maxSizeText: string = '1600';
  @State private maxFpsText: string = '60';
  @State private maxVideoBitText: string = '4';
  @State private useH265: boolean = false;
  @State private keepWakeOnRunning: boolean = true;
  @State private changeToFullOnConnect: boolean = false;
  @State private wakeOnConnect: boolean = true;
  @State private lightOffOnConnect: boolean = false;
  @State private showNavBarOnConnect: boolean = true;
  @State private videoSourceIndex: number = 0;
  @State private cameraFacingIndex: number = 0;
  @State private maxSizeIndex: number = 2;
  @State private maxFpsIndex: number = 1;
  @State private maxVideoBitIndex: number = 2;
  private readonly maxSizeOptions: string[] = ['2560', '1920', '1600', '1280', '1024', '800'];
  private readonly maxFpsOptions: string[] = ['90', '60', '40', '30', '20', '10'];
  private readonly maxVideoBitOptions: string[] = ['12', '8', '4', '2', '1'];
  private readonly videoSourceLabels: string[] = ['屏幕', '摄像头'];
  private readonly cameraFacingLabels: string[] = ['后置', '前置'];
  private editId: string = '';
  private hevcProfile: HevcPref = 'main';
  private loaded: boolean = false;

  aboutToAppear(): void {
    this.isNew = this.presetId === 'new' || this.presetId.length === 0;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void PresetStore.init(ctx).then(() => {
      this.loadForm();
    });
  }

  private loadForm(): void {
    if (this.isNew) {
      this.editId = PresetStore.newId();
      this.applyPreset(PresetStore.getDefault(), true);
      this.nameText = '自定义预设';
      this.builtInKey = '';
      this.linkedCount = 0;
      this.loaded = true;
      return;
    }
    const existing = PresetStore.get(this.presetId);
    if (existing === undefined) {
      this.pathStack.pop();
      return;
    }
    this.editId = existing.id;
    this.applyPreset(existing, false);
    this.linkedCount = PresetStore.linkedCount(existing.id);
    this.loaded = true;
  }

  private applyPreset(preset: ConnectionPreset, asTemplate: boolean): void {
    if (!asTemplate) {
      this.nameText = preset.name;
      this.builtInKey = preset.builtInKey;
    }
    this.videoSource = preset.videoSource === 'camera' ? 'camera' : 'display';
    this.cameraFacing = preset.cameraFacing === 'front' ? 'front' : 'back';
    this.startAppText = this.videoSource === 'camera' ? '' : preset.startApp;
    this.virtualWidthText = preset.virtualWidth > 0 ? `${preset.virtualWidth}` : '';
    this.virtualHeightText = preset.virtualHeight > 0 ? `${preset.virtualHeight}` : '';
    this.virtualDpiText = preset.virtualDpi > 0 ? `${preset.virtualDpi}` : '';
    this.isAudio = preset.isAudio;
    this.listenClip = preset.listenClip;
    this.maxSizeText = `${preset.maxSize}`;
    this.maxFpsText = `${preset.maxFps}`;
    this.maxVideoBitText = `${preset.maxVideoBit}`;
    this.useH265 = preset.useH265;
    this.hevcProfile = normalizeHevcProfile(preset.hevcProfile);
    this.keepWakeOnRunning = preset.keepWakeOnRunning;
    this.changeToFullOnConnect = preset.changeToFullOnConnect;
    this.wakeOnConnect = preset.wakeOnConnect;
    this.lightOffOnConnect = preset.lightOffOnConnect;
    this.showNavBarOnConnect = preset.showNavBarOnConnect;
    this.videoSourceIndex = this.videoSource === 'camera' ? 1 : 0;
    this.cameraFacingIndex = this.cameraFacing === 'front' ? 1 : 0;
    this.maxSizeIndex = this.indexOfOption(this.maxSizeOptions, this.maxSizeText, 2);
    this.maxFpsIndex = this.indexOfOption(this.maxFpsOptions, this.maxFpsText, 1);
    this.maxVideoBitIndex = this.indexOfOption(this.maxVideoBitOptions, this.maxVideoBitText, 2);
  }

  private indexOfOption(options: string[], value: string, fallback: number): number {
    for (let i = 0; i < options.length; i++) {
      if (options[i] === value) {
        return i;
      }
    }
    return fallback;
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

  private parsePositive(raw: string, fallback: number): number {
    const n: number = parseInt(raw.trim(), 10);
    if (isNaN(n) || n <= 0) {
      return fallback;
    }
    return n;
  }

  private parseOptionalInt(raw: string): number {
    const t = raw.trim();
    if (t.length === 0) {
      return 0;
    }
    const n: number = parseInt(t, 10);
    if (isNaN(n) || n < 0) {
      return 0;
    }
    return n;
  }

  private buildPreset(): ConnectionPreset {
    const p = new ConnectionPreset();
    p.id = this.editId;
    p.name = this.nameText.trim();
    p.builtInKey = this.builtInKey;
    p.videoSource = this.videoSource === 'camera' ? 'camera' : 'display';
    p.cameraFacing = this.cameraFacing === 'front' ? 'front' : 'back';
    p.startApp = p.videoSource === 'camera' ? '' : this.startAppText.trim();
    p.virtualWidth = this.parseOptionalInt(this.virtualWidthText);
    p.virtualHeight = this.parseOptionalInt(this.virtualHeightText);
    p.virtualDpi = this.parseOptionalInt(this.virtualDpiText);
    p.isAudio = this.isAudio;
    p.listenClip = this.listenClip;
    p.maxSize = this.parsePositive(this.maxSizeText, 1600);
    p.maxFps = this.parsePositive(this.maxFpsText, 60);
    p.maxVideoBit = this.parsePositive(this.maxVideoBitText, 4);
    p.useH265 = this.useH265;
    p.hevcProfile = this.hevcProfile;
    p.keepWakeOnRunning = this.keepWakeOnRunning;
    p.changeToFullOnConnect = this.changeToFullOnConnect;
    p.wakeOnConnect = this.wakeOnConnect;
    p.lightOffOnConnect = this.lightOffOnConnect;
    p.showNavBarOnConnect = this.showNavBarOnConnect;
    return p;
  }

  private finishSave(saved: ConnectionPreset, askLinked: boolean): void {
    void PresetStore.save(saved).then(() => {
      this.toast('已保存');
      if (askLinked && PresetStore.linkedCount(saved.id) > 0) {
        this.askLinkedUpdate(saved);
      } else {
        this.pathStack.pop();
      }
    });
  }

  private askLinkedUpdate(saved: ConnectionPreset): void {
    const count = PresetStore.linkedCount(saved.id);
    AlertDialog.show({
      title: '更新已关联设备？',
      message: `是否用新选项更新仍关联「${saved.name}」的 ${count} 台设备？已解除关联的设备不会被改动。`,
      primaryButton: {
        value: '保持设备不变',
        action: () => {
          this.pathStack.pop();
        },
      },
      secondaryButton: {
        value: '更新设备',
        action: () => {
          void PresetStore.updateLinkedDevices(saved).then((n: number) => {
            this.toast(`已更新 ${n} 台设备`);
            this.pathStack.pop();
          });
        },
      },
    });
  }

  private onSave(): void {
    if (!this.loaded) {
      return;
    }
    if (this.nameText.trim().length === 0) {
      this.toast('名称不能为空');
      return;
    }
    this.finishSave(this.buildPreset(), !this.isNew);
  }

  private editorTitle(): Resource {
    return this.isNew ? $r('app.string.preset_create') : $r('app.string.preset_edit');
  }

  @Builder
  private fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .margin({ bottom: 6 })
  }

  @Builder
  private toggleRow(title: Resource, hint: Resource, isOn: boolean, onChange: (on: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor($r('app.color.ink'))
        Text(hint).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.accent_blue'))
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
  }

  @Builder
  private streamForm() {
    Column({ space: 16 }) {
      Column({ space: 0 }) {
        this.fieldLabel('视频源')
        Text($r('app.string.preset_video_source_detail'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 6 })
        Select([
          { value: '屏幕' }, { value: '摄像头' },
        ])
          .selected(this.videoSourceIndex)
          .value(this.videoSourceLabels[this.videoSourceIndex])
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            if (index === 1) {
              this.videoSourceIndex = 1;
              this.videoSource = 'camera';
              this.startAppText = '';
            } else {
              this.videoSourceIndex = 0;
              this.videoSource = 'display';
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.videoSource === 'camera') {
        Column({ space: 0 }) {
          this.fieldLabel('摄像头朝向')
          Text($r('app.string.preset_camera_facing_detail'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 6 })
          Select([
            { value: '后置' }, { value: '前置' },
          ])
            .selected(this.cameraFacingIndex)
            .value(this.cameraFacingLabels[this.cameraFacingIndex])
            .width('100%')
            .height(44)
            .onSelect((index: number) => {
              if (index === 1) {
                this.cameraFacingIndex = 1;
                this.cameraFacing = 'front';
              } else {
                this.cameraFacingIndex = 0;
                this.cameraFacing = 'back';
              }
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Column({ space: 0 }) {
          this.fieldLabel('单应用包名（虚拟屏）')
          Text($r('app.string.preset_start_app_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 6 })
          TextInput({ text: this.startAppText, placeholder: '例如 com.example.app' })
            .height(44)
            .onChange((v: string) => {
              this.startAppText = v.trim();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          Column({ space: 0 }) {
            this.fieldLabel($r('app.string.preset_virtual_width'))
            TextInput({ text: this.virtualWidthText, placeholder: '0' })
              .type(InputType.Number)
              .height(44)
              .onChange((v: string) => {
                this.virtualWidthText = v;
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Column({ space: 0 }) {
            this.fieldLabel($r('app.string.preset_virtual_height'))
            TextInput({ text: this.virtualHeightText, placeholder: '0' })
              .type(InputType.Number)
              .height(44)
              .onChange((v: string) => {
                this.virtualHeightText = v;
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Column({ space: 0 }) {
          this.fieldLabel('DPI（0=默认）')
          TextInput({ text: this.virtualDpiText, placeholder: '0' })
            .type(InputType.Number)
            .height(44)
            .onChange((v: string) => {
              this.virtualDpiText = v;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_max_size'))
        Select([
          { value: '2560' }, { value: '1920' }, { value: '1600' },
          { value: '1280' }, { value: '1024' }, { value: '800' },
        ])
          .selected(this.maxSizeIndex)
          .value(this.maxSizeText)
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            if (index >= 0 && index < this.maxSizeOptions.length) {
              this.maxSizeIndex = index;
              this.maxSizeText = this.maxSizeOptions[index];
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_max_fps'))
        Select([
          { value: '90' }, { value: '60' }, { value: '40' },
          { value: '30' }, { value: '20' }, { value: '10' },
        ])
          .selected(this.maxFpsIndex)
          .value(this.maxFpsText)
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            if (index >= 0 && index < this.maxFpsOptions.length) {
              this.maxFpsIndex = index;
              this.maxFpsText = this.maxFpsOptions[index];
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_max_video_bit'))
        Select([
          { value: '12' }, { value: '8' }, { value: '4' }, { value: '2' }, { value: '1' },
        ])
          .selected(this.maxVideoBitIndex)
          .value(this.maxVideoBitText)
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            if (index >= 0 && index < this.maxVideoBitOptions.length) {
              this.maxVideoBitIndex = index;
              this.maxVideoBitText = this.maxVideoBitOptions[index];
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      this.toggleRow(
        $r('app.string.editor_field_use_h265'),
        $r('app.string.editor_field_use_h265_hint'),
        this.useH265,
        (on: boolean) => {
          this.useH265 = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_is_audio'),
        $r('app.string.editor_field_is_audio_hint'),
        this.isAudio,
        (on: boolean) => {
          this.isAudio = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_listen_clip'),
        $r('app.string.editor_field_listen_clip_hint'),
        this.listenClip,
        (on: boolean) => {
          this.listenClip = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_keep_wake'),
        $r('app.string.editor_field_keep_wake_hint'),
        this.keepWakeOnRunning,
        (on: boolean) => {
          this.keepWakeOnRunning = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_full_on_connect'),
        $r('app.string.editor_field_full_on_connect_hint'),
        this.changeToFullOnConnect,
        (on: boolean) => {
          this.changeToFullOnConnect = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_wake_on_connect'),
        $r('app.string.editor_field_wake_on_connect_hint'),
        this.wakeOnConnect,
        (on: boolean) => {
          this.wakeOnConnect = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_light_off_on_connect'),
        $r('app.string.editor_field_light_off_on_connect_hint'),
        this.lightOffOnConnect,
        (on: boolean) => {
          this.lightOffOnConnect = on;
        }
      )
      this.toggleRow(
        $r('app.string.editor_field_show_nav_bar'),
        $r('app.string.editor_field_show_nav_bar_hint'),
        this.showNavBarOnConnect,
        (on: boolean) => {
          this.showNavBarOnConnect = on;
        }
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 10 }) {
              this.fieldLabel($r('app.string.preset_name'))
              TextInput({ text: this.nameText, placeholder: $r('app.string.preset_name') })
                .height(44)
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius($r('app.float.radius_md'))
                .padding({ left: 12, right: 12 })
                .onChange((v: string) => {
                  this.nameText = v;
                })
              if (this.builtInKey.length > 0) {
                Text($r('app.string.preset_builtin_edit_hint'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (!this.isNew) {
                Text(`当前有 ${this.linkedCount} 台已保存设备关联此预设。保存时可选择是否同步更新。`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.surface_card'))
            .borderRadius($r('app.float.radius_detail_panel'))
            .alignItems(HorizontalAlign.Start)

            Column({ space: 10 }) {
              Text($r('app.string.preset_stream_section'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .width('100%')
              this.streamForm()
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.surface_card'))
            .borderRadius($r('app.float.radius_detail_panel'))
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({
            left: $r('app.float.space_page_h'),
            right: $r('app.float.space_page_h'),
            top: 8,
            bottom: 24 + this.safeBottomVp,
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .title(this.editorTitle())
    .hideTitleBar(false)
    .menus([
      {
        value: '保存',
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark')),
        action: () => {
          this.onSave();
        },
      },
    ])
    .backgroundColor($r('app.color.page_background'))
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
