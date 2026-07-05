// GuideSwiperPage.ets — 3-page onboarding Swiper
import { router } from '@kit.ArkUI'
import { PreferenceHelper, PrefKeys, SemanticColors, GreenColors, GrayColors } from '@ohos/common'

@Component
struct ModeCard {
  @Prop image: ResourceStr
  @Prop icon: string
  @Prop title: string
  @Prop desc: string
  @Prop mode: string = 'normal'
  @State pressed: boolean = false

  build() {
    Column() {
      Image(this.image)
        .width('100%')
        .layoutWeight(1)
        .objectFit(ImageFit.Contain)
        .borderRadius({ topLeft: 16, topRight: 16 })

      Column() {
        Row({ space: 6 }) {
          Text(this.icon).fontSize(20)
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(GrayColors.G900)
        }
        .margin({ bottom: 4 })

        Text(this.desc)
          .fontSize(13)
          .fontColor(GrayColors.G300)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(GrayColors.G50)
      .borderRadius({ bottomLeft: 16, bottomRight: 16 })
    }
    .width('40%')
    .height('50%')
    .borderRadius(16)
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.08)', offsetY: 4 })
    .scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .border({ width: this.pressed ? 2 : 0, color: GreenColors.G500 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
  }
}

@Entry
@Component
struct GuideSwiperPage {
  @State currentIndex: number = 0
  private totalPages: number = 3
  private swiperController: SwiperController = new SwiperController()

  enterApp(mode: string): void {
    PreferenceHelper.getInstance().init(getContext(this)).then(() => {
      PreferenceHelper.getInstance().setMode(mode)
      PreferenceHelper.getInstance().setGuided()
      router.replaceUrl({ url: 'pages/Index' })
    })
  }

  skipGuide(): void {
    this.swiperController.changeIndex(2)
  }

  // ===== Page 1: Brand =====
  @Builder
  PageBrand() {
    Column() {
      Image($r('app.media.app_icon'))
        .width(120)
        .height(120)
        .borderRadius(28)
        .shadow({ radius: 24, color: 'rgba(122,183,95,0.25)' })

      Text('欢迎使用 Weaver')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor(GrayColors.G900)
        .margin({ top: 32 })

      Text('为长篇小说创作者而生')
        .fontSize(18)
        .fontColor(GrayColors.G700)
        .margin({ top: 16 })

      Text('人物 · 世界观 · 关系图，一站管理')
        .fontSize(16)
        .fontColor(GrayColors.G300)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColors.BG_CARD)
  }

  // ===== Page 2: Feature Preview =====
  @Builder
  PagePreview() {
    Column() {
      Text('你的创作工具箱')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(GrayColors.G900)
        .margin({ bottom: 32 })

      Row({ space: 16 }) {
        Column() {
          Image($r('app.media.guide_editor'))
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
          Text('Markdown 写作')
            .fontSize(14)
            .fontColor(GrayColors.G700)
            .padding(12)
        }
        .width('44%')
        .borderRadius(16)
        .backgroundColor(GrayColors.G50)

        Column() {
          Image($r('app.media.guide_material'))
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
          Text('素材 · 关系图')
            .fontSize(14)
            .fontColor(GrayColors.G700)
            .padding(12)
        }
        .width('44%')
        .borderRadius(16)
        .backgroundColor(GrayColors.G50)
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 24 })

      Text('所见即所得 — 这就是你的写作界面')
        .fontSize(14)
        .fontColor(GrayColors.G300)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColors.BG_CARD)
  }

  // ===== Page 3: Mode Selection =====
  @Builder
  PageModeSelect() {
    Column() {
      Text('选择你的写作方式')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(GrayColors.G900)
        .margin({ bottom: 32 })

      Row({ space: 24 }) {
        ModeCard({
          image: $r('app.media.guide_normal'),
          icon: '✏️',
          title: '日常写作',
          desc: '简洁编辑器，随时记录',
          mode: 'normal'
        })
          .onClick(() => { this.enterApp('normal') })

        ModeCard({
          image: $r('app.media.guide_professional'),
          icon: '📦',
          title: '小说创作',
          desc: '人物、世界观、关系图',
          mode: 'professional'
        })
          .onClick(() => { this.enterApp('professional') })
      }
      .justifyContent(FlexAlign.Center)

      Text('可在设置中随时切换')
        .fontSize(14)
        .fontColor(GrayColors.G300)
        .margin({ top: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(SemanticColors.BG_CARD)
  }

  build() {
    Stack() {
      Swiper(this.swiperController) {
        this.PageBrand()
        this.PagePreview()
        this.PageModeSelect()
      }
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentIndex = index
      })

      // Skip button (pages 1-2 only)
      if (this.currentIndex < 2) {
        Text('跳过引导')
          .fontSize(14)
          .fontColor(GrayColors.G300)
          .position({ x: '80%', y: '8%' })
          .onClick(() => {
            this.skipGuide()
          })
      }

      // Left arrow
      if (this.currentIndex > 0) {
        Button() {
          Text('←').fontSize(20).fontColor(GrayColors.G900)
        }
        .width(44)
        .height(44)
        .backgroundColor(GrayColors.G50)
        .borderRadius(22)
        .position({ x: 24, y: '88%' })
        .onClick(() => {
          this.swiperController.showPrevious()
        })
      }

      // Right arrow (not on last page)
      if (this.currentIndex < 2) {
        Button() {
          Text('→').fontSize(20).fontColor(GrayColors.G900)
        }
        .width(44)
        .height(44)
        .backgroundColor(GrayColors.G50)
        .borderRadius(22)
        .position({ x: '92%', y: '88%' })
        .onClick(() => {
          this.swiperController.showNext()
        })
      }

      // Page indicator dots
      Row({ space: 8 }) {
        ForEach([0, 1, 2], (index: number) => {
          Circle({ width: 8, height: 8 })
            .fill(index === this.currentIndex ? GreenColors.G500 : GrayColors.G100)
        }, (item: number) => item.toString())
      }
      .position({ x: '50%', y: '89%' })
      .translate({ x: '-50%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
