/**
 * ArkTS desktop card: 2*2 first device / empty; 2*4 up to three devices.
 * Tap → router EntryAbility (session uuid or home). No libadb_core.so.
 */

import {
  formNavHome,
  formNavSession,
} from '../../common/FormNav';

const STORAGE = new LocalStorage();

@Entry(STORAGE)
@Component
struct DeviceFormCard {
  @LocalStorageProp('title') title: string = '易控';
  @LocalStorageProp('subtitle') subtitle: string = '';
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('dimension') dimension: string = '2*2';
  @LocalStorageProp('name0') name0: string = '';
  @LocalStorageProp('uuid0') uuid0: string = '';
  @LocalStorageProp('ep0') ep0: string = '';
  @LocalStorageProp('has0') has0: boolean = false;
  @LocalStorageProp('name1') name1: string = '';
  @LocalStorageProp('uuid1') uuid1: string = '';
  @LocalStorageProp('ep1') ep1: string = '';
  @LocalStorageProp('has1') has1: boolean = false;
  @LocalStorageProp('name2') name2: string = '';
  @LocalStorageProp('uuid2') uuid2: string = '';
  @LocalStorageProp('ep2') ep2: string = '';
  @LocalStorageProp('has2') has2: boolean = false;

  private openHome(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        route: formNavHome()
      }
    });
  }

  private openSession(uuid: string): void {
    if (uuid.length === 0) {
      this.openHome();
      return;
    }
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        route: formNavSession(uuid)
      }
    });
  }

  @Builder
  private deviceRow(name: string, ep: string, uuid: string) {
    Column({ space: 2 }) {
      Text(name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(ep)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 6, bottom: 6 })
    .onClick(() => {
      this.openSession(uuid);
    })
  }

  @Builder
  private emptyBody() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
      Text($r('app.string.form_empty_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.openHome();
    })
  }

  @Builder
  private compactBody() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text(this.has0 ? this.name0 : this.subtitle)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.has0 ? this.ep0 : '')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.has0 ? $r('app.string.form_tap_connect') : '')
        .fontSize(11)
        .fontColor($r('app.color.accent_blue'))
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.has0) {
        this.openSession(this.uuid0);
      } else {
        this.openHome();
      }
    })
  }

  @Builder
  private wideBody() {
    Column({ space: 2 }) {
      Row() {
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Text(this.subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.has0) {
        this.deviceRow(this.name0, this.ep0, this.uuid0)
      }
      if (this.has1) {
        this.deviceRow(this.name1, this.ep1, this.uuid1)
      }
      if (this.has2) {
        this.deviceRow(this.name2, this.ep2, this.uuid2)
      }
      if (!this.has0) {
        Text($r('app.string.form_empty_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .onClick(() => {
            this.openHome();
          })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (!this.has0) {
        this.emptyBody()
      } else if (this.dimension === '2*4') {
        this.wideBody()
      } else {
        this.compactBody()
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius($r('app.float.radius_device_card'))
  }
}
