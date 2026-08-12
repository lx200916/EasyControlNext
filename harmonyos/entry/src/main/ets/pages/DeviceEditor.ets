/**
 * U3 Device Editor — basic host/port/name + wireless pairing + save.
 * sm: scroll form + bottom bar; preferSplit: left section nav + right form.
 */

import { common } from '@kit.AbilityKit';
import { ComponentContent } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  AdbQrCredentials,
  AdbQrPairing,
  encodeQrPixelMap,
  pairWirelessManual,
  pairWithQrCredentials,
} from '../adb/AdbPairing';
import { AppErrorLog } from '../common/AppErrorLog';
import { CameraFacing, Device, VideoSource } from '../model/Device';
import { DeviceStore } from '../model/DeviceStore';

const SECTION_BASIC: string = 'basic';
const SECTION_PAIRING: string = 'pairing';
const SECTION_VIDEO: string = 'video';

/** Params for QR pairing custom dialog (module-level builder + ComponentContent). */
class QrPairDialogParams {
  payload: string = '';
  pixelMap: image.PixelMap | undefined = undefined;
  encodeFailed: boolean = false;
  closeAction: () => void = () => {
  };
}

@Builder
function qrPairDialogBuilder(params: QrPairDialogParams) {
  Column({ space: 12 }) {
    Text($r('app.string.editor_qr_sheet_title'))
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.ink'))
      .width('100%')
    Text($r('app.string.editor_qr_sheet_hint'))
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')

    Column() {
      if (params.pixelMap !== undefined) {
        Image(params.pixelMap)
          .width(220)
          .height(220)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.White)
      } else if (params.payload.length > 0) {
        QRCode(params.payload)
          .width(220)
          .height(220)
          .backgroundColor(Color.White)
          .color(Color.Black)
      } else {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.accent_blue'))
      }
    }
    .width(236)
    .height(236)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .padding(8)

    if (params.encodeFailed) {
      Text($r('app.string.editor_qr_payload_fallback'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    Text($r('app.string.editor_qr_waiting'))
      .fontSize(13)
      .fontColor($r('app.color.accent_blue'))
      .width('100%')

    Button('关闭')
      .type(ButtonType.Normal)
      .width('100%')
      .height(40)
      .backgroundColor($r('app.color.surface_muted'))
      .fontColor($r('app.color.ink'))
      .onClick(() => {
        params.closeAction();
      })
  }
  .width('86%')
  .constraintSize({ maxWidth: 360 })
  .padding(20)
  .backgroundColor($r('app.color.surface_card'))
  .borderRadius(16)
}

@Component
export struct DeviceEditor {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('preferSplit') preferSplit: boolean;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  @Prop uuid: string = 'new';
  /** When true, render inline (sheet / embedded host) without NavDestination / back chrome. */
  @Prop embedded: boolean = false;
  /** Bump to reset draft fields after a successful save (embedded create flow). */
  @Prop @Watch('onFormRevisionChanged') formRevision: number = 0;
  onSaved: () => void = () => {
  };
  @State private isNew: boolean = true;
  @State private section: string = SECTION_BASIC;
  @State private nameText: string = '';
  @State private hostText: string = '';
  @State private adbPortText: string = '5555';
  @State private serverPortText: string = '25166';
  @State private pairPortText: string = '';
  @State private pairCodeText: string = '';
  @State private pairBusy: boolean = false;
  @State private pairStatus: string = '';
  @State private qrWaiting: boolean = false;
  private qrPayload: string = '';
  private qrPixelMap: image.PixelMap | undefined = undefined;
  private qrDialogNode: ComponentContent<QrPairDialogParams> | undefined = undefined;
  @State private connectOnStart: boolean = false;
  @State private changeToFullOnConnect: boolean = false;
  @State private wakeOnConnect: boolean = true;
  @State private lightOffOnConnect: boolean = false;
  @State private showNavBarOnConnect: boolean = true;
  @State private listenClip: boolean = true;
  @State private keepWakeOnRunning: boolean = true;
  @State private isAudio: boolean = false;
  @State private customResolutionOnConnect: boolean = false;
  @State private customResWidthText: string = '1080';
  @State private customResHeightText: string = '2400';
  @State private lockOnClose: boolean = true;
  @State private lightOnClose: boolean = false;
  @State private maxSizeText: string = '1600';
  @State private maxFpsText: string = '60';
  @State private maxVideoBitText: string = '4';
  @State private useH265: boolean = false;
  @State private presetId: string = '';
  @State private maxSizeIndex: number = 2;
  @State private maxFpsIndex: number = 1;
  @State private maxVideoBitIndex: number = 1;
  @State private videoSource: VideoSource = 'display';
  @State private cameraFacing: CameraFacing = 'back';
  @State private startAppText: string = '';
  @State private virtualWidthText: string = '';
  @State private virtualHeightText: string = '';
  @State private virtualDpiText: string = '';
  @State private videoSourceIndex: number = 0;
  @State private cameraFacingIndex: number = 0;
  private readonly maxSizeOptions: string[] = ['2560', '1920', '1600', '1280', '1024', '800'];
  private readonly maxFpsOptions: string[] = ['90', '60', '40', '30', '20', '10'];
  private readonly maxVideoBitOptions: string[] = ['8', '4', '2', '1'];
  private readonly videoSourceLabels: string[] = ['屏幕', '摄像头'];
  private readonly cameraFacingLabels: string[] = ['后置', '前置'];
  private editUuid: string = '';
  private qrCreds: AdbQrCredentials | undefined = undefined;
  /** Bumped on dismiss/cancel so in-flight QR pairing ignores late results. */
  private qrSessionId: number = 0;

  aboutToAppear(): void {
    this.isNew = this.uuid === 'new' || this.uuid.length === 0;
    if (this.isNew) {
      this.resetToDraft();
      return;
    }
    // Wait for RDB init so edit loads persisted row (not a stale empty cache).
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void DeviceStore.init(ctx).then(() => {
      this.loadExistingOrDraft();
    }).catch(() => {
      this.loadExistingOrDraft();
    });
  }

  private onFormRevisionChanged(): void {
    if (!this.embedded) {
      return;
    }
    this.resetToDraft();
  }

  private resetToDraft(): void {
    this.dismissQrDialog();
    const draft = DeviceStore.createDraft();
    this.editUuid = draft.uuid;
    this.isNew = true;
    this.section = SECTION_BASIC;
    this.pairBusy = false;
    this.pairStatus = '';
    this.qrWaiting = false;
    this.qrPayload = '';
    this.qrCreds = undefined;
    this.applyDevice(draft);
  }

  private loadExistingOrDraft(): void {
    const existing = DeviceStore.findByUuid(this.uuid);
    if (existing !== undefined) {
      this.editUuid = existing.uuid;
      this.applyDevice(existing);
      this.isNew = false;
      return;
    }
    const draft = DeviceStore.createDraft();
    this.editUuid = draft.uuid;
    this.isNew = true;
    this.applyDevice(draft);
  }

  private applyDevice(device: Device): void {
    this.nameText = device.name;
    this.hostText = device.address;
    this.adbPortText = `${device.adbPort}`;
    this.serverPortText = `${device.serverPort}`;
    this.pairPortText = device.pairPort > 0 ? `${device.pairPort}` : '';
    this.pairCodeText = device.pairKey;
    this.connectOnStart = device.connectOnStart;
    this.changeToFullOnConnect = device.changeToFullOnConnect;
    this.wakeOnConnect = device.wakeOnConnect;
    this.lightOffOnConnect = device.lightOffOnConnect;
    this.showNavBarOnConnect = device.showNavBarOnConnect;
    this.listenClip = device.listenClip;
    this.keepWakeOnRunning = device.keepWakeOnRunning;
    this.isAudio = device.isAudio;
    this.customResolutionOnConnect = device.customResolutionOnConnect;
    this.customResWidthText = `${device.customResolutionWidth}`;
    this.customResHeightText = `${device.customResolutionHeight}`;
    this.lockOnClose = device.lockOnClose;
    this.lightOnClose = device.lightOnClose;
    this.maxSizeText = `${device.maxSize}`;
    this.maxFpsText = `${device.maxFps}`;
    this.maxVideoBitText = `${device.maxVideoBit}`;
    this.useH265 = device.useH265;
    this.presetId = device.presetId;
    this.videoSource = device.videoSource === 'camera' ? 'camera' : 'display';
    this.cameraFacing = device.cameraFacing === 'front' ? 'front' : 'back';
    this.startAppText = device.startApp;
    this.virtualWidthText = device.virtualWidth > 0 ? `${device.virtualWidth}` : '';
    this.virtualHeightText = device.virtualHeight > 0 ? `${device.virtualHeight}` : '';
    this.virtualDpiText = device.virtualDpi > 0 ? `${device.virtualDpi}` : '';
    this.videoSourceIndex = this.videoSource === 'camera' ? 1 : 0;
    this.cameraFacingIndex = this.cameraFacing === 'front' ? 1 : 0;
    this.maxSizeIndex = this.indexOfOption(this.maxSizeOptions, this.maxSizeText, 2);
    this.maxFpsIndex = this.indexOfOption(this.maxFpsOptions, this.maxFpsText, 1);
    this.maxVideoBitIndex = this.indexOfOption(this.maxVideoBitOptions, this.maxVideoBitText, 1);
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
      // PromptAction may be unavailable in some preview hosts.
    }
  }

  private parsePort(raw: string, fallback: number): number {
    const n: number = parseInt(raw.trim(), 10);
    if (isNaN(n) || n <= 0 || n > 65535) {
      return fallback;
    }
    return n;
  }

  private validate(): boolean {
    if (this.nameText.trim().length === 0) {
      this.toast('请填写设备名称');
      return false;
    }
    if (this.hostText.trim().length === 0) {
      this.toast('请填写主机地址');
      return false;
    }
    const adb = this.parsePort(this.adbPortText, 0);
    if (adb <= 0) {
      this.toast('ADB 端口无效');
      return false;
    }
    const server = this.parsePort(this.serverPortText, 0);
    if (server <= 0) {
      this.toast('Server 端口无效');
      return false;
    }
    return true;
  }

  private buildDevice(): Device {
    const base = DeviceStore.findByUuid(this.editUuid);
    const device = base !== undefined ? base : DeviceStore.createDraft();
    device.uuid = this.editUuid;
    device.name = this.nameText.trim();
    device.address = this.hostText.trim();
    device.adbPort = this.parsePort(this.adbPortText, 5555);
    device.serverPort = this.parsePort(this.serverPortText, 25166);
    device.pairPort = this.parsePort(this.pairPortText, 0);
    device.pairKey = this.pairCodeText.trim();
    device.connectOnStart = this.connectOnStart;
    device.changeToFullOnConnect = this.changeToFullOnConnect;
    device.wakeOnConnect = this.wakeOnConnect;
    device.lightOffOnConnect = this.lightOffOnConnect;
    device.showNavBarOnConnect = this.showNavBarOnConnect;
    device.listenClip = this.listenClip;
    device.keepWakeOnRunning = this.keepWakeOnRunning;
    device.isAudio = this.isAudio;
    device.customResolutionOnConnect = this.customResolutionOnConnect;
    device.customResolutionWidth = this.parsePositive(this.customResWidthText, 1080);
    device.customResolutionHeight = this.parsePositive(this.customResHeightText, 2400);
    device.lockOnClose = this.lockOnClose;
    device.lightOnClose = this.lightOnClose;
    device.maxSize = this.parsePort(this.maxSizeText, 1600);
    device.maxFps = this.parsePort(this.maxFpsText, 60);
    device.maxVideoBit = this.parsePositive(this.maxVideoBitText, 4);
    device.useH265 = this.useH265;
    device.presetId = this.presetId;
    device.videoSource = this.videoSource === 'camera' ? 'camera' : 'display';
    device.cameraFacing = this.cameraFacing === 'front' ? 'front' : 'back';
    if (device.videoSource === 'camera') {
      device.startApp = '';
      device.virtualWidth = 0;
      device.virtualHeight = 0;
      device.virtualDpi = 0;
    } else {
      device.startApp = this.startAppText.trim();
      device.virtualWidth = this.parseOptionalInt(this.virtualWidthText);
      device.virtualHeight = this.parseOptionalInt(this.virtualHeightText);
      device.virtualDpi = this.parseOptionalInt(this.virtualDpiText);
    }
    return device;
  }

  private parsePositive(raw: string, fallback: number): number {
    const n: number = parseInt(raw.trim(), 10);
    if (isNaN(n) || n <= 0) {
      return fallback;
    }
    return n;
  }

  /** Empty / invalid → 0 (server falls back to real display metrics). */
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

  private detachPreset(): void {
    this.presetId = '';
  }

  private async runPair(fillAdbPort: boolean): Promise<void> {
    if (this.pairBusy) {
      return;
    }
    const host = this.hostText.trim();
    const pPort = this.parsePort(this.pairPortText, 0);
    const code = this.pairCodeText.trim();
    if (host.length === 0 || pPort <= 0 || code.length === 0) {
      this.toast('请填写 IP、配对端口和配对码，或改用二维码配对');
      return;
    }
    this.pairBusy = true;
    this.pairStatus = '正在配对…';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await pairWirelessManual(
      ctx,
      host,
      pPort,
      code,
      this.nameText.trim(),
      fillAdbPort
    );
    this.pairBusy = false;
    if (!result.ok) {
      this.pairStatus = result.detail;
      this.toast(result.detail.length > 0 ? result.detail : '配对失败');
      AppErrorLog.e('pair', result.detail.length > 0 ? result.detail : '配对失败');
      return;
    }
    this.pairPortText = '';
    this.pairCodeText = '';
    if (fillAdbPort && result.connectPort > 0) {
      this.adbPortText = `${result.connectPort}`;
      this.pairStatus = `配对成功。已填入连接端口 ${result.connectPort}`;
    } else if (fillAdbPort) {
      this.pairStatus = '配对成功。未发现连接端口，请手动填写 ADB 端口后保存。';
    } else {
      this.pairStatus = '配对成功。请确认连接端口后保存。';
    }
    this.toast('配对成功');
  }

  private releaseQrPixelMap(): void {
    if (this.qrPixelMap !== undefined) {
      try {
        this.qrPixelMap.release();
      } catch (_e) {
        // PixelMap may already be released by the framework.
      }
      this.qrPixelMap = undefined;
    }
  }

  private resetQrSessionState(): void {
    this.qrSessionId += 1;
    this.qrWaiting = false;
    if (this.pairStatus === '等待被控机扫描…') {
      this.pairStatus = '';
    }
    this.releaseQrPixelMap();
    this.qrPayload = '';
    this.qrCreds = undefined;
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_e) {
      // Focus controller unavailable in some hosts.
    }
  }

  /** Close QR dialog + cancel in-flight wait; restore editor interaction. */
  private dismissQrDialog(): void {
    const node = this.qrDialogNode;
    this.qrDialogNode = undefined;
    this.resetQrSessionState();
    if (node !== undefined) {
      void this.getUIContext().getPromptAction().closeCustomDialog(node).catch(() => {
        // Dialog may already be dismissed by autoCancel / back.
      });
    }
  }

  private async openQrDialog(encodeFailed: boolean): Promise<void> {
    if (this.qrDialogNode !== undefined) {
      const prev = this.qrDialogNode;
      this.qrDialogNode = undefined;
      try {
        await this.getUIContext().getPromptAction().closeCustomDialog(prev);
      } catch (_e) {
        // ignore
      }
    }
    const ui = this.getUIContext();
    const params = new QrPairDialogParams();
    params.payload = this.qrPayload;
    params.pixelMap = this.qrPixelMap;
    params.encodeFailed = encodeFailed;
    params.closeAction = () => {
      this.dismissQrDialog();
    };
    const node = new ComponentContent<QrPairDialogParams>(ui, wrapBuilder(qrPairDialogBuilder), params);
    this.qrDialogNode = node;
    await ui.getPromptAction().openCustomDialog(node, {
      alignment: DialogAlignment.Center,
      autoCancel: true,
      isModal: true,
      onWillDismiss: (action: DismissDialogAction) => {
        // Outside tap / system dismiss — do not call closeCustomDialog again.
        this.qrDialogNode = undefined;
        this.resetQrSessionState();
        action.dismiss();
      },
    });
  }

  private async openQrPair(): Promise<void> {
    if (this.qrWaiting) {
      return;
    }
    this.releaseQrPixelMap();
    this.qrCreds = AdbQrPairing.generate();
    this.qrPayload = this.qrCreds.payload;
    const session = this.qrSessionId + 1;
    this.qrSessionId = session;
    this.qrWaiting = true;
    this.pairStatus = '等待被控机扫描…';

    const pixelMap = await encodeQrPixelMap(this.qrPayload);
    if (session !== this.qrSessionId) {
      if (pixelMap !== undefined) {
        try {
          pixelMap.release();
        } catch (_e) {
          // ignore
        }
      }
      return;
    }
    const encodeFailed = pixelMap === undefined;
    if (encodeFailed) {
      this.toast('二维码图片生成失败，已改用内置二维码组件');
    } else {
      this.qrPixelMap = pixelMap;
    }

    try {
      await this.openQrDialog(encodeFailed);
    } catch (e) {
      this.qrDialogNode = undefined;
      this.qrWaiting = false;
      this.pairStatus = '';
      const err = e as Error;
      const msg = err !== undefined && err.message !== undefined ? err.message : String(e);
      this.toast(`无法打开二维码对话框：${msg}`);
      return;
    }
    if (session !== this.qrSessionId) {
      return;
    }

    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const creds = this.qrCreds;
    const result = await pairWithQrCredentials(ctx, creds, 60000);
    if (session !== this.qrSessionId) {
      return;
    }
    this.qrWaiting = false;
    if (!result.ok) {
      this.pairStatus = result.detail;
      this.toast(result.detail);
      return;
    }
    this.dismissQrDialog();
    this.pairPortText = '';
    this.pairCodeText = '';
    if (result.host.length > 0) {
      this.hostText = result.host;
    }
    if (result.connectPort > 0) {
      this.adbPortText = `${result.connectPort}`;
      this.pairStatus = `二维码配对成功。已填入连接端口 ${result.connectPort}`;
    } else {
      this.pairStatus = '二维码配对成功。请确认连接端口后保存。';
    }
    this.toast('配对成功');
  }

  aboutToDisappear(): void {
    this.qrSessionId += 1;
    const node = this.qrDialogNode;
    this.qrDialogNode = undefined;
    if (node !== undefined) {
      try {
        this.getUIContext().getPromptAction().closeCustomDialog(node);
      } catch (_e) {
        // ignore
      }
    }
    if (this.qrPixelMap !== undefined) {
      try {
        this.qrPixelMap.release();
      } catch (_e) {
        // ignore
      }
    }
  }

  private onSave(andConnect: boolean): void {
    if (!this.validate()) {
      return;
    }
    void DeviceStore.upsert(this.buildDevice()).then((saved: Device) => {
      this.isNew = false;
      if (andConnect) {
        this.toast(`已保存，正在连接 ${saved.name}`);
        if (this.embedded) {
          this.onSaved();
          this.pathStack.pushPath({ name: 'session', param: saved.uuid });
        } else {
          this.pathStack.replacePath({ name: 'session', param: saved.uuid });
        }
        return;
      }
      this.toast(`已保存 · ${saved.name}`);
      if (this.embedded) {
        this.onSaved();
        return;
      }
      this.pathStack.pop();
    }).catch(() => {
      this.toast('保存失败');
    });
  }

  @Builder
  private titleBar() {
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

      Text(this.isNew ? $r('app.string.editor_title_new') : $r('app.string.editor_title_edit'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: 8,
      right: $r('app.float.space_page_h'),
      top: 8 + this.safeTopVp,
      bottom: 4,
    })
  }

  @Builder
  private sectionRow(id: string, title: string, enabled: boolean) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(this.section === id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(enabled
          ? (this.section === id ? $r('app.color.accent_blue') : $r('app.color.ink'))
          : $r('app.color.text_secondary'))
      Blank()
      if (!enabled) {
        Text($r('app.string.editor_section_later'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.section === id && enabled
      ? $r('app.color.accent_container')
      : Color.Transparent)
    .borderRadius($r('app.float.radius_md'))
    .opacity(enabled ? 1 : 0.55)
    .onClick(() => {
      if (enabled) {
        this.section = id;
      } else {
        this.toast('即将推出');
      }
    })
  }

  @Builder
  private sectionNav() {
    Column({ space: 4 }) {
      Text($r('app.string.editor_sections'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 8, bottom: 4 })

      this.sectionRow(SECTION_BASIC, '基本信息', true)
      this.sectionRow(SECTION_PAIRING, '配对', true)
      this.sectionRow(SECTION_VIDEO, '视频与启动', true)
    }
    .width('100%')
    .padding(8)
  }

  @Builder
  private compactSectionChip(id: string, title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(this.section === id ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.section === id ? $r('app.color.accent_blue') : $r('app.color.ink'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.section === id
        ? $r('app.color.accent_container')
        : $r('app.color.surface_card'))
      .borderRadius(16)
      .onClick(() => {
        this.section = id;
      })
  }

  @Builder
  private fieldLabel(label: ResourceStr) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .margin({ bottom: 6 })
  }

  @Builder
  private basicForm() {
    Column({ space: 16 }) {
      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_name'))
        TextInput({ text: this.nameText, placeholder: '例如 Pixel Demo' })
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.nameText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_host'))
        TextInput({ text: this.hostText, placeholder: '192.168.1.10' })
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.hostText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_adb_port'))
        TextInput({ text: this.adbPortText, placeholder: '5555' })
          .type(InputType.Number)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.adbPortText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_server_port'))
        TextInput({ text: this.serverPortText, placeholder: '25166' })
          .type(InputType.Number)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.serverPortText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_connect_on_start'))
            .fontSize(15)
            .fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_connect_on_start_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.connectOnStart })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.connectOnStart = on;
          })
      }
      .width('100%')
      .margin({ top: 8 })

      Text($r('app.string.editor_basic_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private videoForm() {
    Column({ space: 16 }) {
      Column({ space: 0 }) {
        this.fieldLabel('视频源')
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
            this.detachPreset();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.videoSource === 'camera') {
        Column({ space: 0 }) {
          this.fieldLabel('摄像头朝向')
          Text('需要被控端 Android 12+')
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
              this.detachPreset();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Column({ space: 0 }) {
          this.fieldLabel('单应用包名（虚拟屏）')
          Text('非空时使用虚拟显示启动该 App（Android 11+）；留空为整屏镜像')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 6 })
          TextInput({ text: this.startAppText, placeholder: '例如 com.example.app' })
            .height(44)
            .onChange((v: string) => {
              this.startAppText = v.trim();
              this.detachPreset();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.startAppText.trim().length > 0) {
          Text('虚拟屏尺寸（可选，0/空=使用被控端分辨率）')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Row({ space: 12 }) {
            Column({ space: 0 }) {
              this.fieldLabel('宽')
              TextInput({ text: this.virtualWidthText, placeholder: '0' })
                .type(InputType.Number)
                .height(44)
                .onChange((v: string) => {
                  this.virtualWidthText = v;
                  this.detachPreset();
                })
            }.layoutWeight(1)
            Column({ space: 0 }) {
              this.fieldLabel('高')
              TextInput({ text: this.virtualHeightText, placeholder: '0' })
                .type(InputType.Number)
                .height(44)
                .onChange((v: string) => {
                  this.virtualHeightText = v;
                  this.detachPreset();
                })
            }.layoutWeight(1)
            Column({ space: 0 }) {
              this.fieldLabel('DPI')
              TextInput({ text: this.virtualDpiText, placeholder: '0' })
                .type(InputType.Number)
                .height(44)
                .onChange((v: string) => {
                  this.virtualDpiText = v;
                  this.detachPreset();
                })
            }.layoutWeight(1)
          }.width('100%')
        }
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
              this.detachPreset();
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
              this.detachPreset();
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_max_video_bit'))
        Select([
          { value: '8' }, { value: '4' }, { value: '2' }, { value: '1' },
        ])
          .selected(this.maxVideoBitIndex)
          .value(this.maxVideoBitText)
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            if (index >= 0 && index < this.maxVideoBitOptions.length) {
              this.maxVideoBitIndex = index;
              this.maxVideoBitText = this.maxVideoBitOptions[index];
              this.detachPreset();
            }
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_use_h265')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_use_h265_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.useH265 })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.useH265 = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_is_audio')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_is_audio_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isAudio })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.isAudio = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_listen_clip')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_listen_clip_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.listenClip })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.listenClip = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_keep_wake')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_keep_wake_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.keepWakeOnRunning })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.keepWakeOnRunning = on;
            this.detachPreset();
          })
      }.width('100%')

      Text($r('app.string.editor_section_on_connect'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_blue'))
        .width('100%')
        .margin({ top: 4 })

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_full_on_connect')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_full_on_connect_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.changeToFullOnConnect })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.changeToFullOnConnect = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_wake_on_connect')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_wake_on_connect_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.wakeOnConnect })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.wakeOnConnect = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_light_off_on_connect')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_light_off_on_connect_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.lightOffOnConnect })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.lightOffOnConnect = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_show_nav_bar')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_show_nav_bar_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.showNavBarOnConnect })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.showNavBarOnConnect = on;
            this.detachPreset();
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_custom_res')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_custom_res_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.customResolutionOnConnect })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.customResolutionOnConnect = on;
            this.detachPreset();
          })
      }.width('100%')

      if (this.customResolutionOnConnect) {
        Row({ space: 12 }) {
          Column({ space: 0 }) {
            this.fieldLabel($r('app.string.editor_field_custom_res_w'))
            TextInput({ text: this.customResWidthText, placeholder: '1080' })
              .type(InputType.Number)
              .height(44)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.radius_md'))
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.customResWidthText = v;
                this.detachPreset();
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Column({ space: 0 }) {
            this.fieldLabel($r('app.string.editor_field_custom_res_h'))
            TextInput({ text: this.customResHeightText, placeholder: '2400' })
              .type(InputType.Number)
              .height(44)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius($r('app.float.radius_md'))
              .padding({ left: 12, right: 12 })
              .onChange((v: string) => {
                this.customResHeightText = v;
                this.detachPreset();
              })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }

      Text($r('app.string.editor_section_on_close'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent_blue'))
        .width('100%')
        .margin({ top: 4 })

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_lock_on_close')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_lock_on_close_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.lockOnClose })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.lockOnClose = on;
          })
      }.width('100%')

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.editor_field_light_on_close')).fontSize(15).fontColor($r('app.color.ink'))
          Text($r('app.string.editor_field_light_on_close_hint')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.lightOnClose })
          .selectedColor($r('app.color.accent_blue'))
          .onChange((on: boolean) => {
            this.lightOnClose = on;
          })
      }.width('100%')

      if (this.presetId.length > 0) {
        Text(`已链接预设：${this.presetId}`)
          .fontSize(12)
          .fontColor($r('app.color.accent_blue'))
          .width('100%')
      } else {
        Text($r('app.string.editor_video_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private pairingForm() {
    Column({ space: 14 }) {
      Text($r('app.string.editor_pairing_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Button($r('app.string.editor_action_qr_pair'))
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.accent_container'))
        .fontColor($r('app.color.accent_blue'))
        .borderRadius($r('app.float.radius_md'))
        .enabled(!this.pairBusy && !this.qrWaiting)
        .onClick(() => {
          void this.openQrPair();
        })

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_pair_port'))
        TextInput({ text: this.pairPortText, placeholder: '例如 37123' })
          .type(InputType.Number)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.pairPortText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 0 }) {
        this.fieldLabel($r('app.string.editor_field_pair_code'))
        TextInput({ text: this.pairCodeText, placeholder: '6 位，可带空格' })
          .type(InputType.Number)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.radius_md'))
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.pairCodeText = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.pairStatus.length > 0) {
        Text(this.pairStatus)
          .fontSize(12)
          .fontColor($r('app.color.accent_blue'))
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private formBody() {
    if (this.section === SECTION_BASIC) {
      this.basicForm()
    } else if (this.section === SECTION_PAIRING) {
      this.pairingForm()
    } else if (this.section === SECTION_VIDEO) {
      this.videoForm()
    } else {
      Text($r('app.string.editor_section_later'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
  }

  @Builder
  private bottomBar() {
    Column({ space: 8 }) {
      if (this.pairBusy || this.qrWaiting) {
        Text(this.pairStatus.length > 0 ? this.pairStatus : '处理中…')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else if (this.pairStatus.length > 0) {
        Text(this.pairStatus)
          .fontSize(12)
          .fontColor($r('app.color.accent_blue'))
          .width('100%')
      }

      Row({ space: 8 }) {
        Button($r('app.string.editor_action_pair_only'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.ink'))
          .borderRadius($r('app.float.radius_md'))
          .enabled(!this.pairBusy)
          .onClick(() => {
            void this.runPair(false);
          })
        Button($r('app.string.editor_action_pair_fill'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.accent_blue'))
          .borderRadius($r('app.float.radius_md'))
          .enabled(!this.pairBusy)
          .onClick(() => {
            void this.runPair(true);
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button($r('app.string.action_save'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.accent_blue'))
          .borderRadius($r('app.float.radius_md'))
          .enabled(!this.pairBusy)
          .onClick(() => {
            this.onSave(false);
          })

        Button($r('app.string.action_save_connect'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.brand_ink'))
          .fontColor(Color.White)
          .borderRadius($r('app.float.radius_md'))
          .enabled(!this.pairBusy)
          .onClick(() => {
            this.onSave(true);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: $r('app.float.space_page_h'),
      right: $r('app.float.space_page_h'),
      top: 10,
      bottom: 12 + (this.embedded ? 8 : this.safeBottomVp),
    })
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.page_background'))
  }

  @Builder
  private editorBody() {
    Column() {
      if (!this.embedded) {
        this.titleBar()
      }

      if (this.preferSplit && !this.embedded) {
        Row({ space: 12 }) {
          Column() {
            this.sectionNav()
          }
          .width('30%')
          .height('100%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius($r('app.float.radius_detail_panel'))
          .padding(8)

          Column() {
            Scroll() {
              Column() {
                this.formBody()
              }
              .width('100%')
              .padding(20)
            }
            .layoutWeight(1)
            .align(Alignment.TopStart)

            this.bottomBar()
          }
          .layoutWeight(1)
          .height('100%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius($r('app.float.radius_detail_panel'))
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: $r('app.float.space_page_h'),
          right: $r('app.float.space_page_h'),
          top: 8,
          bottom: 8,
        })
      } else {
        Row({ space: 8 }) {
          this.compactSectionChip(SECTION_BASIC, '基本')
          this.compactSectionChip(SECTION_PAIRING, '配对')
          this.compactSectionChip(SECTION_VIDEO, '视频')
        }
        .width('100%')
        .padding({
          left: $r('app.float.space_page_h'),
          right: $r('app.float.space_page_h'),
          top: 4,
          bottom: 4,
        })

        Scroll() {
          Column() {
            this.formBody()
          }
          .width('100%')
          .padding({
            left: $r('app.float.space_page_h'),
            right: $r('app.float.space_page_h'),
            top: 12,
            bottom: 24,
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)

        this.bottomBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.page_background'))
  }

  build() {
    if (this.embedded) {
      Column() {
        this.editorBody()
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.editorBody()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onBackPressed(() => {
        if (this.qrDialogNode !== undefined || this.qrWaiting) {
          this.dismissQrDialog();
          return true;
        }
        this.pathStack.pop();
        return true;
      })
    }
  }
}
