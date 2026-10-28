// 顶栏操作图标（对齐华为电子邮件顶部操作区）
//
// 形态由**设备 + 输入**决定，组件不自己拍数字（见 LightTokens.topIconMetrics）：
//   · 桌面（PC / MatePad Edge 电脑模式）：40vp 方形（8vp 圆角）状态底、20vp 图标、44/48 热区；
//   · 平板（触摸平板、非电脑模式）：44vp 圆形状态底、24vp 图标、56 热区。
// 圆形是平板 App 的语言、方形是电脑 App 的语言，二者按形态分流，不混用。
//
// 静态外观始终透明：无材质、无描边、无阴影、零实时模糊；
// 只有指针悬停 / 键盘焦点时才浮出状态底，按下再深一档。
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import { TOP_ICON_RADIUS, TopIconMetrics, topIconMetrics } from '../constants/LightTokens'

@ComponentV2
export struct TopActionButton {
  /** 图标符号；与 glyphText 二选一（glyphText 优先） */
  @Param symbol: Resource | null = null
  /**
   * 用文本字形代替符号（如 '⋯'）。
   * HarmonyOS 符号集里 `more` 是「应用格」图形、没有可用的省略号符号，
   * 所以溢出菜单用文本字形，跨版本/跨设备都稳定。
   */
  @Param glyphText: string = ''
  @Param label: string = ''
  @Param themeId: string = DEFAULT_THEME_ID
  @Param active: boolean = false
  /** 是否可用；命名避开 CustomComponent 内置 enabled 属性 */
  @Param isEnabled: boolean = true
  /** 键鼠优先（决定热区 44 与触摸焦点策略） */
  @Param pointerPrimary: boolean = true
  /** 平板形态（决定是否用圆形状态底与大尺寸） */
  @Param tabletMode: boolean = false
  /** 电脑形态（PC / MatePad Edge 电脑模式）：方形状态底，与输入方式无关 */
  @Param desktopMode: boolean = false
  /** 覆盖左右外边距（<0 表示用设备默认；精简档传 0 把热区贴紧） */
  @Param gapOverride: number = -1
  @Event onTap: () => void = () => {}

  @Local hovered: boolean = false
  @Local pressed: boolean = false
  @Local focused: boolean = false
  /** 悬停提示（键鼠优先时显示，文案即 label） */
  @Local showTip: boolean = false

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId)
  }

  private metrics(): TopIconMetrics {
    return topIconMetrics(this.pointerPrimary, this.tabletMode, this.desktopMode)
  }

  private gap(): number {
    return this.gapOverride >= 0 ? this.gapOverride : this.metrics().gap
  }

  /** 状态底：透明 → hoverBg → activeBg；无材质、无描边、无阴影 */
  private overlayColor(): ResourceColor {
    if (this.pressed) {
      return this.colors().activeBg
    }
    if (this.hovered || this.focused) {
      return this.colors().hoverBg
    }
    return Color.Transparent
  }

  private glyphColor(): ResourceColor {
    if (!this.isEnabled) {
      return this.colors().textTertiary
    }
    return this.active ? this.colors().brand : this.colors().textPrimary
  }

  private stateRadius(): number {
    const metrics: TopIconMetrics = this.metrics()
    return metrics.circular ? metrics.visualSize / 2 : TOP_ICON_RADIUS
  }

  @Builder
  tip() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.colors().textPrimary)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .backgroundColor(this.colors().bgCard)
      .borderRadius(6)
  }

  build() {
    // 根节点就是热区：视觉层不参与命中测试，事件统一落在根上
    Stack() {
      // ① 状态底：电脑 = 圆角方形，平板 = 圆形
      Column()
        .width(this.metrics().visualSize)
        .height(this.metrics().visualSize)
        .borderRadius(this.stateRadius())
        .backgroundColor(this.overlayColor())
        .animation({ duration: Motion.fast, curve: Motion.standardCurve })
        .hitTestBehavior(HitTestMode.None)

      // ② 图标：文本字形优先，其次 SymbolGlyph
      if (this.glyphText !== '') {
        Text(this.glyphText)
          .fontSize(this.metrics().iconSize + 4)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.glyphColor())
          .hitTestBehavior(HitTestMode.None)
      } else if (this.symbol !== null) {
        SymbolGlyph(this.symbol)
          .fontSize(this.metrics().iconSize)
          .fontColor([this.glyphColor()])
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.metrics().hitSize)
    .height(this.metrics().hitSize)
    .alignContent(Alignment.Center)
    .margin({ left: this.gap(), right: this.gap() })
    .enabled(this.isEnabled)
    .focusable(this.isEnabled)
    .tabStop(this.isEnabled)
    // 触摸设备点击不抢焦点，避免状态底在手指抬起后残留
    .focusOnTouch(this.pointerPrimary)
    .opacity(this.isEnabled ? 1 : 0.38)
    .accessibilityText(this.isEnabled ? this.label : this.label + '（不可用）')
    // 悬停气泡：图标语义兜底（对齐备忘录的“调整字体大小”提示）
    .bindPopup(this.showTip, {
      builder: this.tip,
      placement: Placement.Bottom,
      enableArrow: true,
      mask: false
    })
    .onHover((isHover: boolean) => {
      this.hovered = isHover
      this.showTip = isHover && this.isEnabled && this.pointerPrimary
    })
    .onFocus(() => {
      this.focused = true
    })
    .onBlur(() => {
      this.focused = false
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
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap()
      }
    })
  }
}
