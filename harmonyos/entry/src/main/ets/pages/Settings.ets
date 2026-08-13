/**
 * U4 Settings — about, general, connection presets, diagnostics.
 * sm: stacked cards; preferSplit: left category + right content.
 * Home 设置 tab embeds this with embedded=true (no NavDestination / back chrome).
 */

import { GateBDebugStrip } from '../components/GateBDebugStrip';
import { DecodeCapsStrip } from '../components/DecodeCapsStrip';
import { PresetListPanel } from '../components/PresetListPanel';
import { AppSettings, CONNECT_PROBE_TIMEOUT_DEFAULT_MS, CONNECT_PROBE_TIMEOUT_OPTIONS_MS } from '../common/AppSettings';

const CAT_ABOUT: string = 'about';
const CAT_GENERAL: string = 'general';
const CAT_CONNECTION: string = 'connection';
const CAT_DIAGNOSTICS: string = 'diagnostics';

const LANG_SYSTEM: string = '跟随系统';
const LANG_ZH: string = '简体中文';

@Component
export struct Settings {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('preferSplit') preferSplit: boolean;
  @Consume('safeBottomVp') safeBottomVp: number;
  /** When true, render as Home tab content without NavDestination / back chrome. */
  @Prop embedded: boolean = false;
  /**
   * Floating Home TabBar scroll clearance (vp). Content still paints under the pill;
   * use via Scroll/List contentEndOffset — do not blank the bottom as a safe-area.
   */
  @Prop tabBarInsetVp: number = 0;
  @State private category: string = CAT_ABOUT;
  @State private languageLabel: string = LANG_SYSTEM;
  @State private sessionBackToRemote: boolean = true;
  @State private showLanguageSheet: boolean = false;
  @State private probeTimeoutMs: number = CONNECT_PROBE_TIMEOUT_DEFAULT_MS;
  @State private probeTimeoutIndex: number = 1;
  private readonly probeTimeoutLabels: string[] = ['300 ms', '500 ms（默认）', '800 ms', '1.5 s', '3 s'];

  aboutToAppear(): void {
    this.sessionBackToRemote = AppSettings.isSessionBackToRemote();
    this.probeTimeoutMs = AppSettings.connectProbeTimeoutMs();
    this.probeTimeoutIndex = this.indexOfTimeout(this.probeTimeoutMs);
  }

  private indexOfTimeout(ms: number): number {
    for (let i = 0; i < CONNECT_PROBE_TIMEOUT_OPTIONS_MS.length; i++) {
      if (CONNECT_PROBE_TIMEOUT_OPTIONS_MS[i] === ms) {
        return i;
      }
    }
    return 1;
  }

  private onProbeTimeoutSelect(index: number): void {
    if (index < 0 || index >= CONNECT_PROBE_TIMEOUT_OPTIONS_MS.length) {
      return;
    }
    this.probeTimeoutIndex = index;
    this.probeTimeoutMs = CONNECT_PROBE_TIMEOUT_OPTIONS_MS[index];
    void AppSettings.setConnectProbeTimeoutMs(this.probeTimeoutMs);
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

  /** End-of-scroll clearance: floating tab when embedded, else home-indicator only. */
  private scrollEndClearance(): number {
    if (this.tabBarInsetVp > 0) {
      return this.tabBarInsetVp;
    }
    return 24 + this.safeBottomVp;
  }

  private selectLanguage(label: string): void {
    this.languageLabel = label;
    this.showLanguageSheet = false;
    this.toast(`语言 · ${label}`);
  }

  @Builder
  private categoryHeading() {
    if (this.category === CAT_GENERAL) {
      Text($r('app.string.settings_cat_general'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
    } else if (this.category === CAT_CONNECTION) {
      Text($r('app.string.settings_cat_connection'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
    } else if (this.category === CAT_DIAGNOSTICS) {
      Text($r('app.string.settings_cat_diagnostics'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
    } else {
      Text($r('app.string.settings_cat_about'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
    }
  }

  @Builder
  private categoryRow(id: string, title: Resource) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(this.category === id ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.category === id ? $r('app.color.accent_blue') : $r('app.color.ink'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.category === id
      ? $r('app.color.accent_container')
      : Color.Transparent)
    .borderRadius($r('app.float.radius_md'))
    .onClick(() => {
      this.category = id;
    })
  }

  @Builder
  private categoryNav() {
    Column({ space: 4 }) {
      this.categoryRow(CAT_ABOUT, $r('app.string.settings_cat_about'))
      this.categoryRow(CAT_GENERAL, $r('app.string.settings_cat_general'))
      this.categoryRow(CAT_CONNECTION, $r('app.string.settings_cat_connection'))
      this.categoryRow(CAT_DIAGNOSTICS, $r('app.string.settings_cat_diagnostics'))
    }
    .width('100%')
    .padding(8)
  }

  /** Navigation-style row (chevron). */
  @Builder
  private navRow(title: Resource, subtitle: string, onTap: () => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.ink'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => {
      onTap();
    })
  }

  /** Read-only value row (no chevron / no tap). */
  @Builder
  private valueRow(title: Resource, value: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  /** Toggle row — HarmonyOS settings pattern. */
  @Builder
  private toggleRow(title: Resource, hint: Resource, isOn: boolean, onChange: (on: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.ink'))
        Text(hint)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.brand_primary'))
        .onChange((on: boolean) => {
          onChange(on);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private aboutContent() {
    Column({ space: 0 }) {
      Column({ space: 4 }) {
        Text($r('app.string.app_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text($r('app.string.settings_about_tagline'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Divider().color($r('app.color.divider'))

      this.valueRow($r('app.string.settings_version'), '1.0.0 (1000000)')

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      this.valueRow($r('app.string.settings_bundle'), 'com.shiyunjin.easycontrolnext')

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      Text($r('app.string.settings_about_note'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }

  @Builder
  private generalContent() {
    Column({ space: 0 }) {
      this.navRow($r('app.string.settings_language'), this.languageLabel, () => {
        this.showLanguageSheet = true;
      })

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      this.toggleRow(
        $r('app.string.settings_session_back_remote'),
        $r('app.string.settings_session_back_remote_hint'),
        this.sessionBackToRemote,
        (on: boolean) => {
          this.sessionBackToRemote = on;
          void AppSettings.setSessionBackToRemote(on);
        }
      )

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      DecodeCapsStrip()

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      Text($r('app.string.settings_language_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }

  @Builder
  private connectionContent() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text($r('app.string.settings_probe_timeout'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .width('100%')
        Text($r('app.string.settings_probe_timeout_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Select([
          { value: '300 ms' },
          { value: '500 ms（默认）' },
          { value: '800 ms' },
          { value: '1.5 s' },
          { value: '3 s' },
        ])
          .selected(this.probeTimeoutIndex)
          .value(this.probeTimeoutLabels[this.probeTimeoutIndex])
          .width('100%')
          .height(44)
          .onSelect((index: number) => {
            this.onProbeTimeoutSelect(index);
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .backgroundColor($r('app.color.surface_card'))
      .borderRadius($r('app.float.radius_detail_panel'))

      PresetListPanel()
    }
    .width('100%')
  }

  @Builder
  private diagnosticsContent() {
    Column({ space: 0 }) {
      this.navRow($r('app.string.settings_error_logs'), '浏览、筛选、复制本机错误日志', () => {
        this.pathStack.pushPath({ name: 'error_logs' });
      })

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      Column({ space: 8 }) {
        Text($r('app.string.settings_gate_b_probe'))
          .fontSize(16)
          .fontColor($r('app.color.ink'))
          .width('100%')
        Text($r('app.string.settings_diagnostics_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        GateBDebugStrip({ embedded: true })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }

  @Builder
  private contentForCategory() {
    if (this.category === CAT_GENERAL) {
      this.generalContent()
    } else if (this.category === CAT_CONNECTION) {
      this.connectionContent()
    } else if (this.category === CAT_DIAGNOSTICS) {
      this.diagnosticsContent()
    } else {
      this.aboutContent()
    }
  }

  @Builder
  private stackedCompact() {
    Scroll() {
      Column({ space: 16 }) {
        Text($r('app.string.settings_cat_about'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        this.aboutContent()

        Text($r('app.string.settings_cat_general'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        this.generalContent()

        Text($r('app.string.settings_cat_connection'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        this.connectionContent()

        Text($r('app.string.settings_cat_diagnostics'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        this.diagnosticsContent()
      }
      .width('100%')
      .padding({
        left: $r('app.float.space_page_h'),
        right: $r('app.float.space_page_h'),
        top: this.embedded ? 8 : 12,
        bottom: 16,
      })
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .contentEndOffset(this.scrollEndClearance())
  }

  @Builder
  private languageSheetBuilder() {
    Column({ space: 0 }) {
      Text($r('app.string.settings_language'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ bottom: 12 })

      this.languageOption(LANG_SYSTEM)
      Divider().color($r('app.color.divider'))
      this.languageOption(LANG_ZH)

      Button('取消')
        .type(ButtonType.Capsule)
        .width('100%')
        .height(40)
        .margin({ top: 16 })
        .backgroundColor($r('app.color.surface_muted'))
        .fontColor($r('app.color.ink'))
        .onClick(() => {
          this.showLanguageSheet = false;
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 28 + this.safeBottomVp })
  }

  @Builder
  private languageOption(label: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      if (this.languageLabel === label) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([$r('app.color.accent_blue')])
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .onClick(() => {
      this.selectLanguage(label);
    })
  }

  @Builder
  private settingsBody() {
    Column() {
      if (this.preferSplit) {
        Row({ space: 12 }) {
          Column() {
            this.categoryNav()
          }
          .width('30%')
          .height('100%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius($r('app.float.radius_detail_panel'))
          .padding(8)

          Scroll() {
            Column({ space: 8 }) {
              this.categoryHeading()
              this.contentForCategory()
            }
            .width('100%')
            .padding(16)
          }
          .layoutWeight(1)
          .height('100%')
          .align(Alignment.TopStart)
          .contentEndOffset(this.scrollEndClearance())
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
        this.stackedCompact()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.page_background'))
  }

  build() {
    if (this.embedded) {
      Column() {
        this.settingsBody()
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showLanguageSheet, this.languageSheetBuilder(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: true,
        backgroundColor: $r('app.color.surface_card'),
      })
    } else {
      NavDestination() {
        this.settingsBody()
      }
      .title($r('app.string.settings_title'))
      .hideTitleBar(false)
      .backgroundColor($r('app.color.page_background'))
      .bindSheet($$this.showLanguageSheet, this.languageSheetBuilder(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: true,
        backgroundColor: $r('app.color.surface_card'),
      })
      .bindSheet($$this.showLanguageSheet, this.languageSheetBuilder(), {
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
}
