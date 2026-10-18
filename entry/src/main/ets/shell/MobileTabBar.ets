// 手机端底部页签栏（官方"基础底部导航"的自定义实现）
//
// 官方《常见导航样式案例》以 Tabs(barPosition.End) 为底栏范式；此处采用"自定义
// Row 底栏 + 状态驱动内容"的等价实现，原因：
//   1) 四个板块并不都是独立 TabContent —— 文稿/素材/关系图要与工作区状态(view)联动、
//      素材/关系图在进入时需异步加载数据，用 onChange 驱动比 TabContent 更直接；
//   2) 选中态由 app.ui.mobileTab 单一来源派生，避免 Tabs 内部 index 与 store 两份真相。
// 视觉仍遵循官方：底栏 56vp、图标位（本版以文字 + 选中指示条承载）、选中用品牌色。
import { tokensFor, WeaverColorSet, WeaverMobile, MobileTab, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { glassTabBarStyle } from './MaterialSurface'

/** 底部页签项（静态描述，选中态由外部 selected 传入） */
export interface MobileTabItem {
  id: MobileTab
  label: string
}

@ComponentV2
export struct MobileTabBar {
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
            .fontSize(12)
            .fontWeight(this.isActive(item.id) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isActive(item.id) ? this.colors().brand : this.colors().textSecondary)
          Divider()
            .width(WeaverMobile.INDICATOR_W)
            .height(2)
            .color(this.isActive(item.id) ? this.colors().brand : Color.Transparent)
            .margin({ top: 5 })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(item.label)
        .onClick(() => this.onSelect(item.id))
      }, (item: MobileTabItem) => item.label)
    }
    .width('100%')
    .height(WeaverMobile.TABBAR_H)
    // 底部页签玻璃条：与顶栏同一材质（上沿 1px 高光），是每屏第 2 层（也是最后一层）实时模糊
    .attributeModifier(glassTabBarStyle(this.themeId))
  }
}
