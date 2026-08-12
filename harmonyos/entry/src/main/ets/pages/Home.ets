/**
 * Foldable-first Home with HDS immersive TabBar: 设备 | 设置.
 * Official glass: HdsTabs.barFloatingStyle.systemMaterialEffect (UI Design Kit).
 * preferSplit: list|detail inside 设备; 设置 embeds Settings content.
 * 新增 is a header "+" action (push DeviceEditor create) — not a tab.
 * Manage sheet aligns with Android EasyControlApp ManageDeviceSheet.
 * Gate B stays in Settings → Diagnostics (not primary chrome).
 */

import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { DeviceCard } from '../components/DeviceCard';
import { ConnectionPreset } from '../model/ConnectionPreset';
import { Device } from '../model/Device';
import {
  DeviceInfoCache,
  RemoteSystemSnapshot,
  formatAndroidVersion,
  formatModelLabel,
  formatProbedAt,
  formatReachability,
  streamSummaryOf,
} from '../model/DeviceInfoCache';
import { DeviceStore } from '../model/DeviceStore';
import { PresetStore } from '../model/PresetStore';
import { Settings } from './Settings';
import {
  InstalledAppRow,
  listRemoteThirdPartyApps,
  probeRemoteSystemProps,
  RemoteSystemProps,
} from '../session/LiveMirror';
import { SessionLaunchOpts, stageSessionLaunch } from '../session/SessionLaunch';

const TAB_DEVICES: number = 0;
const TAB_SETTINGS: number = 1;
/** Tab bar content height (vp). Home-indicator inset is barFloatingStyle.barBottomMargin. */
const TAB_BAR_CONTENT_VP: number = 56;
/** Side inset for official floating HdsTabs bar (vp). */
const TAB_BAR_SIDE_MARGIN_VP: number = 16;
/** Extra gap above the floating pill when scrolling last rows into view. */
const TAB_BAR_SCROLL_GAP_VP: number = 8;

@Component
export struct Home {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('preferSplit') @Watch('onPreferSplitChanged') preferSplit: boolean;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  @StorageLink('deviceStoreRevision') @Watch('onDeviceStoreChanged')
  storeRevision: number = 0;
  @State private devices: Device[] = [];
  @State @Watch('onSelectedUuidChanged') private selectedUuid: string = '';
  /** Single bindSheet host — chaining two bindSheets + bottom Tabs race-dismisses the sheet. */
  @State private showActionSheet: boolean = false;
  /** 0 = manage device, 1 = preset picker, 2 = temp-app picker (virtual display). */
  @State private actionSheetKind: number = 0;
  @State private manageDevice: Device | undefined = undefined;
  @State private presetOptions: ConnectionPreset[] = [];
  @State private currentTab: number = TAB_DEVICES;
  @State private tempAppRows: InstalledAppRow[] = [];
  @State private tempAppLoading: boolean = false;
  @State private tempAppError: string = '';
  @State private tempAppQuery: string = '';
  /** Detail pane — remote props (lazy ADB); local stream line always from Device. */
  @State private detailModel: string = '未知';
  @State private detailAndroid: string = '未探测';
  @State private detailStatus: string = '未探测';
  @State private detailProbedHint: string = '';
  @State private detailProbeBusy: boolean = false;
  private autoConnectTried: boolean = false;
  private probeSeq: number = 0;
  private hdsTabsController: HdsTabsController = new HdsTabsController();

  aboutToAppear(): void {
    AppStorage.setOrCreate('deviceStoreRevision', this.storeRevision);
    this.presetOptions = PresetStore.all();
    this.reloadDevices();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void DeviceStore.init(ctx).then(() => {
      this.reloadDevices();
      this.maybeAutoConnect();
    });
  }

  private onDeviceStoreChanged(): void {
    this.reloadDevices();
  }

  private reloadDevices(): void {
    this.devices = DeviceStore.getAll();
    if (this.devices.length === 0) {
      this.selectedUuid = '';
      this.resetDetailInfoPlaceholders();
      return;
    }
    let stillThere = false;
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].uuid === this.selectedUuid) {
        stillThere = true;
        break;
      }
    }
    if (!stillThere) {
      this.selectedUuid = this.devices[0].uuid;
    } else {
      this.syncDetailInfoFromCache(false);
    }
  }

  private onSelectedUuidChanged(): void {
    this.syncDetailInfoFromCache(this.preferSplit);
  }

  private onPreferSplitChanged(): void {
    if (this.preferSplit) {
      this.syncDetailInfoFromCache(true);
    }
  }

  private resetDetailInfoPlaceholders(): void {
    this.detailModel = '未知';
    this.detailAndroid = '未探测';
    this.detailStatus = '未探测';
    this.detailProbedHint = '';
    this.detailProbeBusy = false;
  }

  private applySnapshotToDetail(snap: RemoteSystemSnapshot | undefined): void {
    if (snap === undefined || !snap.probed) {
      this.detailModel = '未知';
      this.detailAndroid = '未探测';
      this.detailStatus = '未探测';
      this.detailProbedHint = '';
      return;
    }
    this.detailModel = formatModelLabel(snap.model);
    this.detailAndroid = formatAndroidVersion(snap.release, snap.sdk);
    this.detailStatus = formatReachability(snap);
    const at = formatProbedAt(snap);
    this.detailProbedHint = at.length > 0 ? `上次探测 ${at}` : '';
  }

  /**
   * Paint from cache immediately; optionally kick a background probe when stale.
   * Never awaits — Home render must stay non-blocking.
   */
  private syncDetailInfoFromCache(autoProbe: boolean): void {
    const uuid = this.selectedUuid;
    if (uuid.length === 0) {
      this.resetDetailInfoPlaceholders();
      return;
    }
    const snap = DeviceInfoCache.get(uuid);
    this.applySnapshotToDetail(snap);
    if (autoProbe && this.preferSplit && !DeviceInfoCache.isFresh(uuid)) {
      this.probeSelectedDeviceInfo(false);
    }
  }

  private probeSelectedDeviceInfo(force: boolean): void {
    const device = this.selectedDevice();
    if (device === undefined) {
      return;
    }
    if (!force && DeviceInfoCache.isFresh(device.uuid)) {
      this.applySnapshotToDetail(DeviceInfoCache.get(device.uuid));
      return;
    }
    const uuid = device.uuid;
    const seq = ++this.probeSeq;
    this.detailProbeBusy = true;
    if (!DeviceInfoCache.isFresh(uuid)) {
      this.detailStatus = '探测中…';
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void probeRemoteSystemProps(ctx, device).then((props: RemoteSystemProps) => {
      if (seq !== this.probeSeq || this.selectedUuid !== uuid) {
        return;
      }
      const snap = new RemoteSystemSnapshot();
      snap.probed = true;
      snap.probedAt = Date.now();
      snap.reachable = props.ok;
      snap.detail = props.detail;
      if (props.ok) {
        snap.model = props.model;
        snap.release = props.release;
        snap.sdk = props.sdk;
      }
      DeviceInfoCache.put(uuid, snap);
      this.applySnapshotToDetail(snap);
      this.detailProbeBusy = false;
    }).catch(() => {
      if (seq !== this.probeSeq || this.selectedUuid !== uuid) {
        return;
      }
      const snap = new RemoteSystemSnapshot();
      snap.probed = true;
      snap.probedAt = Date.now();
      snap.reachable = false;
      DeviceInfoCache.put(uuid, snap);
      this.applySnapshotToDetail(snap);
      this.detailProbeBusy = false;
    });
  }

  private maybeAutoConnect(): void {
    if (this.autoConnectTried) {
      return;
    }
    this.autoConnectTried = true;
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].connectOnStart) {
        this.onConnect(this.devices[i]);
        return;
      }
    }
  }

  private selectedDevice(): Device | undefined {
    for (let i = 0; i < this.devices.length; i++) {
      if (this.devices[i].uuid === this.selectedUuid) {
        return this.devices[i];
      }
    }
    return undefined;
  }

  /** Floating bar clearance above home indicator (official HdsTabs.barBottomMargin). */
  private floatingBarBottomMargin(): number {
    return this.safeBottomVp > 0 ? this.safeBottomVp : 12;
  }

  /**
   * Scroll end offset only — NOT a layout safe-area blank.
   * With barOverlap + floating HdsTabs, content paints under the translucent pill;
   * regions not covered by the pill stay visible and hit-testable. This value only
   * lets the last rows scroll clear of the pill.
   */
  private floatingTabScrollClearance(): number {
    return TAB_BAR_CONTENT_VP + this.floatingBarBottomMargin() + TAB_BAR_SCROLL_GAP_VP;
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

  private openAddDevice(): void {
    this.pathStack.pushPath({ name: 'device', param: 'new' });
  }

  private openEditor(uuid: string): void {
    this.pathStack.pushPath({ name: 'device', param: uuid });
  }

  private closeActionSheet(): void {
    this.showActionSheet = false;
    this.actionSheetKind = 0;
  }

  private onConnect(device: Device): void {
    this.closeActionSheet();
    this.pathStack.pushPath({ name: 'session', param: device.uuid });
    this.toast(`正在连接 ${device.name}`);
  }

  private onManage(device: Device): void {
    this.manageDevice = device;
    if (this.selectedUuid !== device.uuid) {
      this.selectedUuid = device.uuid;
    }
    this.actionSheetKind = 0;
    this.showActionSheet = true;
  }

  private onSelect(device: Device): void {
    this.selectedUuid = device.uuid;
  }

  private confirmDelete(device: Device): void {
    AlertDialog.show({
      title: '删除设备',
      message: `确定删除「${device.name}」？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          void DeviceStore.deleteByUuid(device.uuid).then(() => {
            DeviceInfoCache.remove(device.uuid);
            this.closeActionSheet();
            this.manageDevice = undefined;
            this.toast('已删除');
          }).catch(() => {
            this.toast('删除失败');
          });
        },
      },
    });
  }

  private applyPresetSessionOnly(device: Device, preset: ConnectionPreset): void {
    const sessionDev = DeviceStore.findByUuid(device.uuid);
    if (sessionDev === undefined) {
      this.toast('设备不存在');
      return;
    }
    preset.applySessionOnly(sessionDev);
    const opts = new SessionLaunchOpts();
    opts.overrideDevice = sessionDev;
    stageSessionLaunch(opts);
    this.closeActionSheet();
    this.pathStack.pushPath({ name: 'session', param: device.uuid });
    this.toast(`已应用预设 · ${preset.name}`);
  }

  /** Detail「应用预设」: session-only picker sheet (does not persist device). */
  private openPresetPicker(device: Device): void {
    this.manageDevice = device;
    this.actionSheetKind = 1;
    this.showActionSheet = true;
  }

  /**
   * Detail「临时启动应用」: pick package → connect with startApp + virtual display
   * (Android AppPickerDialog → ClientStream startApp). Not foreground monkey.
   */
  private tempStartApp(device: Device): void {
    this.manageDevice = device;
    this.actionSheetKind = 2;
    this.tempAppQuery = '';
    this.tempAppError = '';
    this.tempAppRows = [];
    this.tempAppLoading = true;
    this.showActionSheet = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void listRemoteThirdPartyApps(ctx, device).then((rows: InstalledAppRow[]) => {
      this.tempAppRows = rows;
      this.tempAppLoading = false;
      if (rows.length === 0) {
        this.tempAppError = '未获取到第三方应用';
      }
    }).catch((e: Error | string) => {
      this.tempAppLoading = false;
      this.tempAppError = e instanceof Error ? e.message : String(e);
    });
  }

  private connectVirtualAppSession(device: Device, packageName: string): void {
    const pkg = packageName.trim();
    if (pkg.length === 0) {
      return;
    }
    // findByUuid already clones — session-only overrides (not persisted).
    const sessionDev = DeviceStore.findByUuid(device.uuid);
    if (sessionDev === undefined) {
      this.toast('设备不存在');
      return;
    }
    sessionDev.videoSource = 'display';
    sessionDev.cameraFacing = 'back';
    sessionDev.startApp = pkg;
    // virtualWidth/Height/Dpi 0 → server uses physical display size (Android DisplayManager).
    const opts = new SessionLaunchOpts();
    opts.overrideDevice = sessionDev;
    stageSessionLaunch(opts);
    this.closeActionSheet();
    this.pathStack.pushPath({ name: 'session', param: device.uuid });
    this.toast(`虚拟屏启动 · ${pkg}`);
  }

  private filteredTempApps(): InstalledAppRow[] {
    const q = this.tempAppQuery.trim().toLowerCase();
    if (q.length === 0) {
      return this.tempAppRows;
    }
    return this.tempAppRows.filter((row: InstalledAppRow) => {
      return row.packageName.toLowerCase().includes(q) || row.label.toLowerCase().includes(q);
    });
  }

  /** Detail「使用摄像头」: facing picker → videoSource=camera session (Android 12+). */
  private tempCamera(device: Device): void {
    AlertDialog.show({
      title: '摄像头朝向',
      message: '将被控端摄像头画面镜像到本机（需要被控端 Android 12+）',
      primaryButton: {
        value: '后置',
        action: () => {
          this.connectCameraSession(device, 'back');
        },
      },
      secondaryButton: {
        value: '前置',
        action: () => {
          this.connectCameraSession(device, 'front');
        },
      },
    });
  }

  private connectCameraSession(device: Device, facing: string): void {
    const sessionDev = DeviceStore.findByUuid(device.uuid);
    if (sessionDev === undefined) {
      this.toast('设备不存在');
      return;
    }
    sessionDev.videoSource = 'camera';
    sessionDev.cameraFacing = facing === 'front' ? 'front' : 'back';
    sessionDev.startApp = '';
    const opts = new SessionLaunchOpts();
    opts.overrideDevice = sessionDev;
    stageSessionLaunch(opts);
    this.pathStack.pushPath({ name: 'session', param: device.uuid });
    this.toast(facing === 'front' ? '正在连接前置摄像头…' : '正在连接后置摄像头…');
  }

  @Builder
  private manageActionRow(title: string, detail: string, destructive: boolean, onTap: () => void) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(destructive ? Color.Red : $r('app.color.ink'))
        .width('100%')
      if (detail.length > 0) {
        Text(detail)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private manageSheetBuilder() {
    // Folded (!preferSplit) full manage sheet — session + device actions.
    // Expanded detail pane owns session one-shots; it uses Edit|Delete inline.
    Column({ space: 4 }) {
      if (this.manageDevice !== undefined) {
        Text(this.manageDevice.name)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .width('100%')
        Text(DeviceStore.endpointOf(this.manageDevice))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 8 })

        Text($r('app.string.manage_section_session'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent_blue'))
          .width('100%')
          .margin({ top: 8 })
        Text($r('app.string.manage_section_session_hint'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 4 })

        this.manageActionRow('连接', '打开投屏会话', false, () => {
          if (this.manageDevice !== undefined) {
            this.onConnect(this.manageDevice);
          }
        })
        Divider().color($r('app.color.divider'))
        this.manageActionRow('应用预设', '仅本次会话，不改已保存设备', false, () => {
          this.presetOptions = PresetStore.all();
          this.actionSheetKind = 1;
        })
        Divider().color($r('app.color.divider'))
        this.manageActionRow('临时启动应用', '虚拟屏单应用镜像（Android 11+）', false, () => {
          if (this.manageDevice !== undefined) {
            this.tempStartApp(this.manageDevice);
          }
        })
        Divider().color($r('app.color.divider'))
        this.manageActionRow('使用摄像头', '相机镜像（Android 12+）', false, () => {
          if (this.manageDevice !== undefined) {
            this.tempCamera(this.manageDevice);
          }
        })

        Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 8 })

        Text($r('app.string.manage_section_device'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text($r('app.string.manage_section_device_hint'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 4 })

        this.manageActionRow('编辑', '修改地址、画面与连接选项', false, () => {
          if (this.manageDevice !== undefined) {
            const uuid = this.manageDevice.uuid;
            this.closeActionSheet();
            this.openEditor(uuid);
          }
        })
        Divider().color($r('app.color.divider'))
        this.manageActionRow('删除', '从列表移除，不可撤销', true, () => {
          if (this.manageDevice !== undefined) {
            this.confirmDelete(this.manageDevice);
          }
        })
      }
    }
    .width('100%')
    // Sheet content owns safe-area inset; do not also pad the bindSheet host
    // (host bottom pad + Tabs previously caused AceSheet "Bottom offset invalid").
    .padding({
      left: 20,
      right: 20,
      top: 16,
      bottom: Math.max(16, this.safeBottomVp),
    })
  }

  @Builder
  private presetPickerBuilder() {
    Column({ space: 8 }) {
      Text($r('app.string.manage_apply_preset'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
      Text($r('app.string.manage_apply_preset_detail'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      ForEach(this.presetOptions, (preset: ConnectionPreset) => {
        Column({ space: 2 }) {
          Text(preset.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .width('100%')
          Text(PresetStore.summaryLine(preset))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 12, bottom: 12 })
        .onClick(() => {
          if (this.manageDevice !== undefined) {
            this.applyPresetSessionOnly(this.manageDevice, preset);
          }
        })
      }, (preset: ConnectionPreset) => preset.id)

      Button('取消')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .margin({ top: 8 })
        .backgroundColor($r('app.color.surface_muted'))
        .fontColor($r('app.color.ink'))
        .borderRadius($r('app.float.radius_md'))
        .onClick(() => {
          this.closeActionSheet();
        })
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 16,
      bottom: Math.max(16, this.safeBottomVp),
    })
  }

  @Builder
  private tempAppPickerBuilder() {
    Column({ space: 8 }) {
      Text('选择应用（虚拟屏）')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
      Text('将以单应用虚拟显示连接，与会话内前台启动不同')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.tempAppQuery, placeholder: '搜索应用名或包名' })
        .height(40)
        .onChange((v: string) => {
          this.tempAppQuery = v;
        })

      if (this.tempAppLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(24).height(24).color($r('app.color.accent_blue'))
          Text('正在读取应用列表…')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .justifyContent(FlexAlign.Center)
      } else if (this.tempAppError.length > 0) {
        Text(this.tempAppError)
          .fontSize(13)
          .fontColor(Color.Red)
          .width('100%')
          .padding({ top: 16, bottom: 16 })
      } else {
        List({ space: 0 }) {
          ForEach(this.filteredTempApps(), (row: InstalledAppRow) => {
            ListItem() {
              Column({ space: 2 }) {
                Text(row.label.length > 0 ? row.label : row.packageName)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                  .width('100%')
                Text(row.packageName)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ top: 12, bottom: 12 })
              .onClick(() => {
                if (this.manageDevice !== undefined) {
                  this.connectVirtualAppSession(this.manageDevice, row.packageName);
                }
              })
            }
          }, (row: InstalledAppRow) => row.packageName)
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ maxHeight: 360 })
      }

      Button('取消')
        .type(ButtonType.Normal)
        .width('100%')
        .height(44)
        .margin({ top: 8 })
        .backgroundColor($r('app.color.surface_muted'))
        .fontColor($r('app.color.ink'))
        .borderRadius($r('app.float.radius_md'))
        .onClick(() => {
          this.closeActionSheet();
        })
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 16,
      bottom: Math.max(16, this.safeBottomVp),
    })
  }

  @Builder
  private actionSheetBuilder() {
    if (this.actionSheetKind === 1) {
      this.presetPickerBuilder()
    } else if (this.actionSheetKind === 2) {
      this.tempAppPickerBuilder()
    } else {
      this.manageSheetBuilder()
    }
  }

  @Builder
  private headerBar() {
    Row() {
      Text($r('app.string.app_title'))
        .fontSize(this.preferSplit ? 22 : 24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)

      if (this.currentTab === TAB_DEVICES) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_card'))
        .borderRadius($r('app.float.radius_md'))
        .accessibilityText($r('app.string.action_add_device'))
        .onClick(() => {
          this.openAddDevice();
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: $r('app.float.space_page_h'),
      right: $r('app.float.space_page_h'),
      top: 10 + this.safeTopVp,
      bottom: 4,
    })
  }

  @Builder
  private tabBarItem(index: number, title: Resource, icon: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentTab === index ? '#3A70FC' : '#99000000'])
      Text(title)
        .fontSize(10)
        .fontColor(this.currentTab === index ? '#3A70FC' : '#99000000')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private emptyList() {
    Column({ space: 8 }) {
      Text($r('app.string.home_empty_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
      Text($r('app.string.home_empty_hint'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.action_add_device'))
        .type(ButtonType.Normal)
        .height(40)
        .margin({ top: 8 })
        .padding({ left: 20, right: 20 })
        .backgroundColor($r('app.color.accent_blue'))
        .fontColor(Color.White)
        .borderRadius($r('app.float.radius_md'))
        .onClick(() => {
          this.openAddDevice();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding($r('app.float.space_page_h'))
  }

  @Builder
  private deviceList() {
    if (this.devices.length === 0) {
      this.emptyList();
    } else {
      List({ space: this.preferSplit ? 8 : 12 }) {
        ForEach(this.devices, (device: Device) => {
          ListItem() {
            DeviceCard({
              device: device,
              compact: this.preferSplit,
              selected: this.preferSplit && device.uuid === this.selectedUuid,
              onConnect: (item: Device) => {
                this.onConnect(item);
              },
              onManage: (item: Device) => {
                this.onManage(item);
              },
              onSelect: (item: Device) => {
                this.onSelect(item);
              },
            })
          }
        }, (device: Device) => device.uuid)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: this.preferSplit ? 12 : $r('app.float.space_page_h'),
        right: this.preferSplit ? 4 : $r('app.float.space_page_h'),
      })
      // Paint under floating glass bar; clearance is scroll-only (design: non-pill area clickable).
      .contentEndOffset(this.floatingTabScrollClearance())
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  private detailTitle(): string {
    const device = this.selectedDevice();
    if (device === undefined) {
      return '';
    }
    return device.name.length > 0 ? device.name : '未命名设备';
  }

  private detailEndpoint(): string {
    const device = this.selectedDevice();
    if (device === undefined) {
      return '';
    }
    return DeviceStore.endpointOf(device);
  }

  private detailStreamLine(): string {
    const device = this.selectedDevice();
    if (device === undefined) {
      return '';
    }
    return streamSummaryOf(device);
  }

  @Builder
  private detailInfoRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '64%' })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
  }

  @Builder
  private detailSessionRow(title: Resource, detail: Resource, onTap: () => void) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
      Text(detail)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 11, bottom: 11 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private detailPane() {
    Column() {
      if (this.selectedDevice() === undefined) {
        Column({ space: 6 }) {
          Text($r('app.string.detail_empty_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text($r('app.string.detail_empty_hint'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 0 }) {
            Column({ space: 4 }) {
              Text(this.detailTitle())
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.ink'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(this.detailEndpoint())
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.detailInfoRow($r('app.string.detail_label_model'), this.detailModel)
              Divider().color($r('app.color.divider'))
              this.detailInfoRow($r('app.string.detail_label_android'), this.detailAndroid)
              Divider().color($r('app.color.divider'))
              this.detailInfoRow($r('app.string.detail_label_stream'), this.detailStreamLine())
              Divider().color($r('app.color.divider'))
              this.detailInfoRow($r('app.string.detail_label_status'), this.detailStatus)
            }
            .width('100%')
            .margin({ top: 16 })
            .padding({ left: 4, right: 4 })

            Row({ space: 8 }) {
              if (this.detailProbeBusy) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color($r('app.color.accent_blue'))
              }
              Text(this.detailProbeBusy
                ? '探测中…'
                : (this.detailProbedHint.length > 0 ? this.detailProbedHint : '点击刷新获取系统信息'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              Text($r('app.string.detail_refresh_info'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.detailProbeBusy
                  ? $r('app.color.text_secondary')
                  : $r('app.color.accent_blue'))
                .onClick(() => {
                  if (!this.detailProbeBusy) {
                    this.probeSelectedDeviceInfo(true);
                  }
                })
            }
            .width('100%')
            .margin({ top: 6, bottom: 16 })
            .alignItems(VerticalAlign.Center)

            Button($r('app.string.action_connect'))
              .type(ButtonType.Normal)
              .width('100%')
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand_ink'))
              .fontColor(Color.White)
              .borderRadius($r('app.float.radius_md'))
              .onClick(() => {
                const device = this.selectedDevice();
                if (device !== undefined) {
                  this.onConnect(device);
                }
              })

            Text($r('app.string.detail_section_session'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent_blue'))
              .width('100%')
              .margin({ top: 18 })
            Text($r('app.string.detail_section_session_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 2, bottom: 4 })

            this.detailSessionRow(
              $r('app.string.detail_action_temp_app'),
              $r('app.string.detail_action_temp_app_hint'),
              () => {
                const device = this.selectedDevice();
                if (device !== undefined) {
                  this.tempStartApp(device);
                }
              }
            )
            Divider().color($r('app.color.divider'))
            this.detailSessionRow(
              $r('app.string.detail_action_camera'),
              $r('app.string.detail_action_camera_hint'),
              () => {
                const device = this.selectedDevice();
                if (device !== undefined) {
                  this.tempCamera(device);
                }
              }
            )
            Divider().color($r('app.color.divider'))
            this.detailSessionRow(
              $r('app.string.manage_apply_preset'),
              $r('app.string.manage_apply_preset_detail'),
              () => {
                const device = this.selectedDevice();
                if (device !== undefined) {
                  this.openPresetPicker(device);
                }
              }
            )

            Row({ space: 8 }) {
              Button($r('app.string.action_edit'))
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.ink'))
                .borderRadius($r('app.float.radius_md'))
                .onClick(() => {
                  const device = this.selectedDevice();
                  if (device !== undefined) {
                    this.openEditor(device.uuid);
                  }
                })

              Button($r('app.string.action_delete'))
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.surface_muted'))
                .fontColor($r('app.color.danger'))
                .borderRadius($r('app.float.radius_md'))
                .onClick(() => {
                  const device = this.selectedDevice();
                  if (device !== undefined) {
                    this.confirmDelete(device);
                  }
                })
            }
            .width('100%')
            .margin({ top: 16 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        .contentEndOffset(this.floatingTabScrollClearance())
      }
    }
    .width('100%')
    .height('100%')
    // Extend under floating TabBar (not a blank safe-area). Scroll clearance is contentEndOffset.
    .padding({ left: 24, right: 24, top: 24, bottom: 16 })
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }

  @Builder
  private devicesTabContent() {
    // Transparent scaffold so overlapping TabBar can sample list/detail pixels (no opaque fill).
    if (this.preferSplit) {
      Row({ space: 16 }) {
        Column() {
          Text($r('app.string.home_devices_heading'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 14, bottom: 6 })
          this.deviceList()
        }
        .width('34%')
        .height('100%')
        .backgroundColor(Color.Transparent)

        Column() {
          this.detailPane()
        }
        .layoutWeight(1)
        .height('100%')
        .padding({
          right: $r('app.float.space_page_h'),
          // Keep detail painted under the glass bar (scroll clearance is inside detailPane).
          bottom: 8,
          top: 0,
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, top: 4 })
      .backgroundColor(Color.Transparent)
    } else {
      Column() {
        this.deviceList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
  }

  @Builder
  private settingsTabContent() {
    Settings({
      embedded: true,
      // Scroll clearance only — Settings must not treat TabBar as opaque safe-area blank.
      tabBarInsetVp: this.floatingTabScrollClearance(),
    })
  }

  build() {
    Column() {
      this.headerBar()

      // Official liquid glass / 沉浸光感: HdsTabs + barFloatingStyle.systemMaterialEffect
      // (UI Design Kit). Do not hand-roll barBackgroundBlurStyle / barBackgroundEffect.
      HdsTabs({
        barPosition: BarPosition.End,
        index: this.currentTab,
        controller: this.hdsTabsController,
      }) {
        TabContent() {
          this.devicesTabContent()
        }
        .tabBar(this.tabBarItem(TAB_DEVICES, $r('app.string.home_tab_devices'), $r('sys.symbol.wifi')))

        TabContent() {
          this.settingsTabContent()
        }
        .tabBar(this.tabBarItem(TAB_SETTINGS, $r('app.string.home_tab_settings'), $r('sys.symbol.gearshape')))
      }
      .vertical(false)
      .barOverlap(true)
      .barHeight(TAB_BAR_CONTENT_VP)
      .barFloatingStyle({
        barSideMargin: TAB_BAR_SIDE_MARGIN_VP,
        barBottomMargin: this.floatingBarBottomMargin(),
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
        },
      })
      .scrollable(false)
      .animationDuration(0)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .bindSheet($$this.showActionSheet, this.actionSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      backgroundColor: Color.White,
      preferType: SheetType.BOTTOM,
      onDisappear: () => {
        this.actionSheetKind = 0;
        this.manageDevice = undefined;
      },
    })
  }
}
