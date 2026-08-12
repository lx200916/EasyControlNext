/**
 * Error log browser — parity with Android ErrorLogScreen:
 * list / filter / search / expand / copy / clear.
 */

import { pasteboard } from '@kit.BasicServicesKit';
import {
  AppErrorLog,
  ErrorLogEntry,
  ErrorLogLevel,
  formatTimestampShort,
} from '../common/AppErrorLog';

type LevelFilter = 'all' | 'error' | 'warn';

@Component
export struct ErrorLog {
  @Consume('pathStack') pathStack: NavPathStack;
  @Consume('safeTopVp') safeTopVp: number;
  @Consume('safeBottomVp') safeBottomVp: number;
  @State private entries: ErrorLogEntry[] = [];
  @State private filtered: ErrorLogEntry[] = [];
  @State private query: string = '';
  @State private levelFilter: LevelFilter = 'all';
  @State private expandedIndex: number = -1;
  @State private showClearConfirm: boolean = false;

  aboutToAppear(): void {
    this.reload();
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

  private reload(): void {
    this.entries = AppErrorLog.readNewestFirst();
    this.expandedIndex = -1;
    this.applyFilter();
  }

  private applyFilter(): void {
    const q = this.query.trim().toLowerCase();
    const out: ErrorLogEntry[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      const e = this.entries[i];
      if (this.levelFilter === 'error' && e.level !== 'E') {
        continue;
      }
      if (this.levelFilter === 'warn' && e.level !== 'W') {
        continue;
      }
      if (q.length > 0) {
        const hay = `${e.tag} ${e.message} ${e.stackTrace}`.toLowerCase();
        if (!hay.includes(q)) {
          continue;
        }
      }
      out.push(e);
    }
    this.filtered = out;
  }

  private onQueryChange(value: string): void {
    this.query = value;
    this.expandedIndex = -1;
    this.applyFilter();
  }

  private setFilter(filter: LevelFilter): void {
    this.levelFilter = filter;
    this.expandedIndex = -1;
    this.applyFilter();
  }

  private levelColor(level: ErrorLogLevel): string {
    return level === 'E' ? '#E53935' : '#F9A825';
  }

  private async copyAll(): Promise<void> {
    const text = AppErrorLog.exportText();
    if (text.length === 0) {
      this.toast('暂无日志');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const board = pasteboard.getSystemPasteboard();
      await board.setData(data);
      this.toast('已复制到剪贴板');
    } catch (_e) {
      this.toast('复制失败');
    }
  }

  private doClear(): void {
    AppErrorLog.clear();
    this.showClearConfirm = false;
    this.reload();
    this.toast('已清空');
  }

  @Builder
  private filterChip(id: LevelFilter, label: Resource) {
    Text(label)
      .fontSize(13)
      .fontColor(this.levelFilter === id ? Color.White : $r('app.color.ink'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.levelFilter === id
        ? $r('app.color.brand_ink')
        : $r('app.color.surface_muted'))
      .onClick(() => {
        this.setFilter(id);
      })
  }

  @Builder
  private toolbarBtn(label: string, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.brand_primary'))
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .onClick(onTap)
  }

  @Builder
  private entryRow(entry: ErrorLogEntry, index: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(entry.level)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.levelColor(entry.level))
        Text(entry.tag)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatTimestampShort(entry.timestampMs))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Text(entry.message)
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .maxLines(this.expandedIndex === index ? 40 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.expandedIndex === index && entry.stackTrace.length > 0) {
        Text(entry.stackTrace)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_md'))
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.expandedIndex = this.expandedIndex === index ? -1 : index;
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 4 }) {
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

          Text($r('app.string.error_log_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)

          this.toolbarBtn('刷新', () => {
            this.reload();
          })
          this.toolbarBtn('复制', () => {
            void this.copyAll();
          })
          this.toolbarBtn('清空', () => {
            this.showClearConfirm = true;
          })
        }
        .width('100%')
        .padding({
          left: 8,
          right: 8,
          top: 8 + this.safeTopVp,
          bottom: 4,
        })

        TextInput({
          text: this.query,
          placeholder: '标签、消息、堆栈…',
        })
          .height(40)
          .margin({ left: 16, right: 16, top: 4, bottom: 8 })
          .backgroundColor($r('app.color.surface_muted'))
          .onChange((v: string) => {
            this.onQueryChange(v);
          })

        Row({ space: 8 }) {
          this.filterChip('all', $r('app.string.error_log_filter_all'))
          this.filterChip('error', $r('app.string.error_log_filter_error'))
          this.filterChip('warn', $r('app.string.error_log_filter_warn'))
          Blank()
          Text(`显示 ${this.filtered.length} / ${this.entries.length}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.filtered.length === 0) {
          Text($r('app.string.error_log_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 48 })
            .layoutWeight(1)
        } else {
          List({ space: 8 }) {
            ForEach(this.filtered, (entry: ErrorLogEntry, index: number) => {
              ListItem() {
                this.entryRow(entry, index)
              }
            }, (entry: ErrorLogEntry, index: number) =>
              `${entry.timestampMs}_${entry.level}_${entry.tag}_${index}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({
            left: 16,
            right: 16,
            bottom: 16 + this.safeBottomVp,
          })
          .scrollBar(BarState.Off)
        }
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
    .bindSheet($$this.showClearConfirm, this.clearConfirmBuilder(), {
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

  @Builder
  private clearConfirmBuilder() {
    Column({ space: 12 }) {
      Text($r('app.string.error_log_clear_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
      Text($r('app.string.error_log_clear_message'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 12 }) {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.surface_muted'))
          .fontColor($r('app.color.ink'))
          .onClick(() => {
            this.showClearConfirm = false;
          })
        Button($r('app.string.error_log_clear'))
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#E53935')
          .fontColor(Color.White)
          .onClick(() => {
            this.doClear();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 + this.safeBottomVp })
  }
}
