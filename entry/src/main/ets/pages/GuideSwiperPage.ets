// 首启引导页 —— 介绍功能后进入主界面
//
// 写作模式已统一为专业版：不再在首启或设置里让用户选「专业 / 普通」。
// 入口只有一条，避免用户为"要不要用素材/关系图"这类实现细节做一次无意义的抉择。
//
// 实现说明（避免重蹈覆辙）：
// 1. 本页**不使用 @Builder**。@Builder 的参数是"按值传递"的，在状态变化后
//    其函数体不保证重新执行；而 @Builder 嵌在 ForEach 里再放进 Swiper 更是
//    容易在重渲染时丢内容（表现为点击后整页变空）。
//    这里改为"显式子组件 + @Param"，@Param 变化必然驱动子组件刷新。
// 2. 轮播页数量是固定的 4 个，不需要 ForEach，直接列出即可 —— 少一层差量算法就少一处不确定。
// 3. 文案以固定数组驱动，无需状态，因此不存在"选中态同步"这类问题。
import { router } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { app } from '../store/AppStores'
import { prefs } from '../utils/PreferenceHelper'
import { Logger } from '../utils/Logger'
import { tokensFor, WeaverColorSet, WeaverRadii } from '../constants/DesignTokens'
import { PcWindowBar } from '../shell/PcWindowBar'

interface GuideSlide {
  title: string
  desc: string
}

const SLIDES: GuideSlide[] = [
  { title: '专注写作', desc: '极简的稿纸与编辑区，把注意力留给文字本身。' },
  { title: '分章管理', desc: '一章一篇，长篇小说也能清楚地组织与检索。' },
  { title: '素材与关系', desc: '人物、世界观、灵感集中沉淀，关系图自动生成。' },
  { title: '不丢一个字', desc: '编辑即自动保存，随时导出 TXT / Markdown / HTML。' }
]

@ComponentV2
struct GuideSlideView {
  @Param slide: GuideSlide = SLIDES[0]

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  build() {
    Column() {
      Text(this.slide.title)
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
        .margin({ bottom: 14 })
      Text(this.slide.desc)
        .fontSize(15).fontColor(this.colors().textSecondary)
        .textAlign(TextAlign.Center).width('72%').lineHeight(24)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
struct GuideContent {
  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private start(): void {
    // 写作模式已统一为专业版，不再由用户选择
    prefs.setGuided()
    router.replaceUrl({ url: 'pages/Index' }).catch((e: Error) => {
      Logger.error('GuideSwiperPage: replaceUrl failed: ' + String(e))
    })
  }

  build() {
    Column() {
      Swiper() {
        GuideSlideView({ slide: SLIDES[0] })
        GuideSlideView({ slide: SLIDES[1] })
        GuideSlideView({ slide: SLIDES[2] })
        GuideSlideView({ slide: SLIDES[3] })
      }
      .layoutWeight(1).width('100%').indicator(true).loop(false)

      Column() {
        Button('开始使用 Weaver')
          .width('80%').height(46).fontSize(16)
          .backgroundColor(this.colors().brand).fontColor(this.colors().onBrand)
          .borderRadius(WeaverRadii.MD)
          .onClick(() => this.start())
      }.padding({ bottom: 44 })
    }
    .width('100%').height('100%')
    .backgroundColor(this.colors().bgPrimary)
  }
}

@Entry
@ComponentV2
struct GuideSwiperPage {
  build() {
    Column() {
      if (deviceInfo.deviceType === '2in1') {
        PcWindowBar({ app: app })
      }
      GuideContent().layoutWeight(1)
    }.width('100%').height('100%')
  }
}
