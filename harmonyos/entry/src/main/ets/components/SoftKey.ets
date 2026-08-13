/**
 * On-screen QWERTY key with iOS-style press preview bubble.
 * Touch Down shows label above the key; Up/Cancel dismisses and fires onPress once.
 * Bubble is overlay-only (translate) so row height stays fixed.
 */

@Component
export struct SoftKey {
  @Prop label: string = '';
  @Prop flexW: number = 1;
  @Prop accent: boolean = false;
  @Prop keyHeight: number = 36;
  @Prop fontSize: number = 14;
  @Prop padTop: number = 8;
  /** Called once on TouchType.Up (not on Cancel). */
  onPress: () => void = () => {};
  @State private pressed: boolean = false;

  private bubbleLabel(): string {
    if (this.label === 'space') {
      return '␣';
    }
    if (this.label === 'shift') {
      return '⇧';
    }
    return this.label;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.label)
        .fontSize(this.fontSize)
        .fontColor('#F2F2F2')
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .height(this.keyHeight)
        .width('100%')
        .borderRadius(8)
        .backgroundColor(this.accent ? '#334A90E2' : (this.pressed ? '#55FFFFFF' : '#33FFFFFF'))
        .padding({ top: this.padTop })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressed = true;
          } else if (event.type === TouchType.Up) {
            if (this.pressed) {
              this.pressed = false;
              this.onPress();
            }
          } else if (event.type === TouchType.Cancel) {
            this.pressed = false;
          }
        })

      if (this.pressed) {
        Text(this.bubbleLabel())
          .fontSize(Math.max(this.fontSize + 6, 18))
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
          .textAlign(TextAlign.Center)
          .constraintSize({ minWidth: 40, minHeight: 44 })
          .padding({
            left: this.label.length > 1 ? 14 : 12,
            right: this.label.length > 1 ? 14 : 12,
            top: 10,
            bottom: 10,
          })
          .borderRadius(12)
          .backgroundColor('#F5F5F7')
          .shadow({
            radius: 10,
            color: '#66000000',
            offsetX: 0,
            offsetY: 3,
          })
          .translate({ y: -(this.keyHeight * 0.85 + 28) })
          .zIndex(30)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .height(this.keyHeight)
    .layoutWeight(this.flexW)
    .clip(false)
  }
}
