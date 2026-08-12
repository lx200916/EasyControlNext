/**
 * Scaffold home. Do not import libadb_core.so here until Gate B device run.
 * See native/arkts/AdbCore.ets.example and ./scripts/build_native_ohos.sh.
 */
@Entry
@Component
struct Index {
  @State message: string = 'EasyControlNext';

  build() {
    Column({ space: 16 }) {
      Text(this.message)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand_primary'))

      Text('易控')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))

      Text('HarmonyOS controller · Android devices')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))

      Text('See IMPLEMENTATION_PLAN.md')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Button('开始')
        .onClick(() => {
          this.message = 'EasyControlNext · Controller';
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.page_background'))
    .padding(24)
  }
}
