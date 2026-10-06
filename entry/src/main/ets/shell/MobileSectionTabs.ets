// md（中等宽度）内容区顶部分段页签 —— 文稿 / 素材 / 关系图
//
// 与底部页签共用 app.ui.mobileTab 作为选中来源；本组件只是顶部形态的呈现。
import { tokensFor, WeaverColorSet, WeaverMobile, MobileTab, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { MobileTabItem } from './MobileTabBar'

@ComponentV2
export struct MobileSectionTabs {
  @Param items: MobileTabItem[] = []
  @Param selected: MobileTab = MobileTab.DOCS
  @Param themeId: string = DEFAULT_THEME_ID
  @Event onSelect: (tab: MobileTab) => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId)
  }

  private isActive(tab: MobileTab): boolean {
    return this.selected === tab
  }

  build() {
    Row() {
      ForEach(this.items, (item: MobileTabItem) => {
        Column() {
          Text(item.label)
            .fontSize(14)
            .fontWeight(this.isActive(item.id) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isActive(item.id) ? this.colors().brand : this.colors().textSecondary)
          Divider()
            .width(WeaverMobile.INDICATOR_W)
            .height(2)
            .color(this.isActive(item.id) ? this.colors().brand : Color.Transparent)
            .margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .padding({ left: 14, right: 14 })
        .height('100%')
        .accessibilityText(item.label)
        .onClick(() => this.onSelect(item.id))
      }, (item: MobileTabItem) => item.label)
      Blank()
    }
    .width('100%')
    .height(44)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.colors().bgCard)
    .border({ width: { bottom: 1 }, color: this.colors().divider })
  }
}
