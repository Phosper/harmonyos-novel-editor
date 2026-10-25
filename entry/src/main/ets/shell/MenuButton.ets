// 「⋯」下拉菜单按钮（对标华为电子邮件）
//
// 用**系统菜单**实现：`bindMenu` + `Menu/MenuItem`，位置/材质/动画/点击关闭都归系统。
//
// 触发器不能复用 TopActionButton：自定义组件外层包了一层壳，bindMenu 挂在壳上时
// 点击被组件内部的 onClick 吃掉，菜单不会弹（实测）。所以这里直接把状态底 + 字形
// 画在一个普通 Stack 上，让 bindMenu 成为唯一的点击接收者。
//
// 形态与 TopActionButton 同源（LightTokens.topIconMetrics）：
//   电脑 40vp 方形（8vp 圆角）/ 平板 44vp 圆形；图标 20 / 24；热区 44-48 / 56。
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import { TOP_ICON_RADIUS, TopIconMetrics, topIconMetrics } from '../constants/LightTokens'

@ComponentV2
export struct MenuButton {
  @Param label: string = '更多'
  @Param themeId: string = DEFAULT_THEME_ID
  @Param pointerPrimary: boolean = true
  @Param tabletMode: boolean = false
  /** 电脑形态（PC / MatePad Edge 电脑模式）：方形状态底 */
  @Param desktopMode: boolean = false
  @Param isEnabled: boolean = true
  /** 覆盖左右外边距（<0 用设备默认；精简档传 0） */
  @Param gapOverride: number = -1
  /** 菜单项文案（同一种菜单，形态只影响字号） */
  @Param items: string[] = []
  @Event onSelect: (index: number) => void = () => {}

  @Local hovered: boolean = false
  @Local pressed: boolean = false

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId)
  }

  private metrics(): TopIconMetrics {
    return topIconMetrics(this.pointerPrimary, this.tabletMode, this.desktopMode)
  }

  private gap(): number {
    return this.gapOverride >= 0 ? this.gapOverride : this.metrics().gap
  }

  private stateRadius(): number {
    const metrics: TopIconMetrics = this.metrics()
    return metrics.circular ? metrics.visualSize / 2 : TOP_ICON_RADIUS
  }

  private overlayColor(): ResourceColor {
    if (this.pressed) {
      return this.colors().activeBg
    }
    return this.hovered ? this.colors().hoverBg : Color.Transparent
  }

  private itemFont(): number {
    return this.tabletMode ? 16 : 14
  }

  @Builder
  menuView() {
    Menu() {
      ForEach(this.items, (item: string, index: number) => {
        MenuItem({ content: item })
          .onClick(() => this.onSelect(index))
      }, (item: string, index: number) => item + '#' + index)
    }
    .fontSize(this.itemFont())
    .fontColor(this.colors().textPrimary)
    .radius(this.tabletMode ? 16 : 12)
  }

  build() {
    // 普通 Stack：只有 bindMenu 接收点击，没有自定义 onClick 抢事件
    Stack() {
      Column()
        .width(this.metrics().visualSize)
        .height(this.metrics().visualSize)
        .borderRadius(this.stateRadius())
        .backgroundColor(this.overlayColor())
        .animation({ duration: Motion.fast, curve: Motion.standardCurve })
        .hitTestBehavior(HitTestMode.None)

      // 鸿蒙标志性的「四点」更多图标（dot_grid_2x2），不再用西文省略号三点
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(this.metrics().iconSize + 2)
        .fontColor([this.isEnabled ? this.colors().textPrimary : this.colors().textTertiary])
        .hitTestBehavior(HitTestMode.None)
    }
    .width(this.metrics().hitSize)
    .height(this.metrics().hitSize)
    .alignContent(Alignment.Center)
    .margin({ left: this.gap(), right: this.gap() })
    .enabled(this.isEnabled)
    .focusable(true)
    .tabStop(true)
    .focusOnTouch(this.pointerPrimary)
    .opacity(this.isEnabled ? 1 : 0.38)
    .accessibilityText(this.label)
    .onHover((isHover: boolean) => {
      this.hovered = isHover
    })
    .onTouch((event: TouchEvent) => {
      if (!this.isEnabled) {
        return
      }
      if (event.type === TouchType.Down) {
        this.pressed = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false
      }
    })
    // 右对齐：菜单右边缘与 ⋯ 右边缘对齐、向左展开，不越过本栏边界
    .bindMenu(this.menuView, { placement: Placement.BottomRight })
  }
}
