/**
 * U4 Settings lite — about/version, presets, error logs, language stub.
 * Gate B native probe lives under Diagnostics (not on Home primary chrome).
 * sm: grouped list; preferSplit: left category + right content.
 * Home 设置 tab embeds this with embedded=true (no NavDestination / back chrome).
 */

import { GateBDebugStrip } from '../components/GateBDebugStrip';
import { AppSettings } from '../common/AppSettings';

const CAT_ABOUT: string = 'about';
const CAT_GENERAL: string = 'general';
const CAT_CONNECTION: string = 'connection';
const CAT_DIAGNOSTICS: string = 'diagnostics';

@Component
export struct Settings {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('preferSplit') preferSplit: boolean;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  /** When true, render as Home tab content without NavDestination / back chrome. */
  @Prop embedded: boolean = false;
  /**
   * Floating Home TabBar scroll clearance (vp). Content still paints under the pill;
   * use via Scroll/List contentEndOffset — do not blank the bottom as a safe-area.
   */
  @Prop tabBarInsetVp: number = 0;
  @State private category: string = CAT_ABOUT;
  @State private languageLabel: string = '跟随系统';
  @State private sessionBackToRemote: boolean = true;

  aboutToAppear(): void {
    this.sessionBackToRemote = AppSettings.isSessionBackToRemote();
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

  @Builder
  private titleBar() {
    Row({ space: 8 }) {
      if (!this.embedded) {
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
      }

      Text($r('app.string.settings_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: this.embedded ? $r('app.float.space_page_h') : 8,
      right: $r('app.float.space_page_h'),
      top: this.embedded ? 4 : (8 + this.safeTopVp),
      bottom: 4,
    })
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

  @Builder
  private settingsRow(title: Resource, subtitle: string, enabled: boolean, onTap: () => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor(enabled ? $r('app.color.ink') : $r('app.color.text_secondary'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (enabled) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      } else {
        Text($r('app.string.settings_coming_soon'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .opacity(enabled ? 1 : 0.7)
    .onClick(() => {
      if (enabled) {
        onTap();
      } else {
        this.toast('即将推出');
      }
    })
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

      this.settingsRow($r('app.string.settings_version'), '1.0.0 (1000000)', false, () => {
      })

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      this.settingsRow($r('app.string.settings_bundle'), 'com.shiyunjin.easycontrolnext', false, () => {
      })

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
      this.settingsRow($r('app.string.settings_language'), this.languageLabel, true, () => {
        this.languageLabel = this.languageLabel === '跟随系统' ? '简体中文' : '跟随系统';
        this.toast(`语言 · ${this.languageLabel}`);
      })

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
    Column({ space: 0 }) {
      this.settingsRow($r('app.string.settings_presets'), '内置预设 · 应用到设备', true, () => {
        this.pathStack.pushPath({ name: 'presets' });
      })

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.settings_session_back_remote'))
            .fontSize(16)
            .fontColor($r('app.color.ink'))
          Text($r('app.string.settings_session_back_remote_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.sessionBackToRemote })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((on: boolean) => {
            this.sessionBackToRemote = on;
            void AppSettings.setSessionBackToRemote(on);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      Divider().color($r('app.color.divider')).margin({ left: 16 })

      Text($r('app.string.settings_connection_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding(16)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_detail_panel'))
  }

  @Builder
  private diagnosticsContent() {
    Column({ space: 0 }) {
      this.settingsRow($r('app.string.settings_error_logs'), '浏览、筛选、复制本机错误日志', true, () => {
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
  private settingsBody() {
    Column() {
      // Embedded under Home「设置」tab — skip redundant page title.
      if (!this.embedded) {
        this.titleBar()
      }

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
          // Layout extends under floating TabBar; scroll clearance is contentEndOffset.
          bottom: 8,
        })
      } else {
        this.stackedCompact()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedded ? Color.Transparent : $r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    if (this.embedded) {
      Column() {
        this.settingsBody()
      }
      .width('100%')
      .height('100%')
    } else {
      NavDestination() {
        this.settingsBody()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onBackPressed(() => {
        this.pathStack.pop();
        return true;
      })
    }
  }
}
