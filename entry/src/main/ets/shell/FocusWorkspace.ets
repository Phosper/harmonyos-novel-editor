// 专注编辑面（沉浸模式）
//
// 关键：入场动画不依赖 AppShell 的 @Monitor 或全局状态，而由本组件每次挂载时
// 在 aboutToAppear 里触发。这样“进入 → 退出 → 再次进入”时，即使外部状态通知
// 有延迟，本组件也一定会重新开始自己的入场动画；且初始状态保持可见（scale 0.99），
// 不会出现 opacity 0 导致整页空白。
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import type { AppStores } from '../store/AppStores'
import { EditorPane } from './EditorPane'
import { exitFocusAnimated, FOCUS_EDITOR_ID } from './FocusTransition'

const KEY_ESCAPE_CODE: number = 2070;

@ComponentV2
export struct FocusWorkspace {
  @Param app: AppStores | null = null
  /** 入场动画进度：初始 0.99/8vp，下一拍回到 1/0 */
  @Local entered: boolean = false
  /** 退出胶囊的悬停态：改用极淡底色反馈，不再使用玻璃材质 */
  @Local exitHovered: boolean = false
  private enterTimer: number = -1
  private exitTimer: number = -1

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  aboutToAppear(): void {
    this.entered = false
    this.enterTimer = setTimeout(() => {
      this.enterTimer = -1
      this.entered = true
    }, 16)
  }

  aboutToDisappear(): void {
    if (this.enterTimer >= 0) {
      clearTimeout(this.enterTimer)
      this.enterTimer = -1
    }
    if (this.exitTimer >= 0) {
      clearTimeout(this.exitTimer)
      this.exitTimer = -1
    }
  }

  private focusTitle(): string {
    if (this.app === null) {
      return '未命名文稿'
    }
    const t: string = this.app.editor.title.trim()
    return t === '' ? '未命名文稿' : t
  }

  private focusStatus(): string {
    if (this.app === null) {
      return ''
    }
    const state: string = this.app.editor.dirtyCount > 0 ? '编辑中' : '已保存'
    return this.app.editor.wordCount.toString() + ' 字 · ' + state
  }

  /** 退出：先让专注面轻微收缩/下移，再恢复工作台，避免硬切 */
  private exitFocus(): void {
    if (this.app === null || !this.app.ui.immersiveEditing) {
      return
    }
    this.entered = false
    if (this.exitTimer >= 0) {
      clearTimeout(this.exitTimer)
    }
    this.exitTimer = setTimeout(() => {
      this.exitTimer = -1
      if (this.app !== null) {
        exitFocusAnimated(this.getUIContext())
      }
    }, 220)
  }

  private desktopRightInset(): number {
    if (this.app === null || !this.app.ui.usesDesktopChrome) {
      return 12
    }
    return this.app.ui.captionInset
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
    Column() {
      // 专注头：小标签 + 文稿标题 + 状态 + 明确退出入口
      Row() {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.fullscreen'))
              .fontSize(12)
              .fontColor([this.colors().textTertiary])
              .margin({ right: 5 })
            Text('专注写作')
              .fontSize(11).fontColor(this.colors().textTertiary)
          }
          Text(this.focusTitle())
            .fontSize(20).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.focusStatus())
          .fontSize(11).fontColor(this.colors().textTertiary)
          .margin({ right: 12 })

      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .padding({ left: 12, right: this.desktopRightInset(), top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Column() {
        EditorPane({ app: this.app, showTitle: false }).layoutWeight(1)
          .geometryTransition(FOCUS_EDITOR_ID)
      }
      .width('100%').layoutWeight(1)
      .constraintSize({ maxWidth: 720 })
      .padding({ top: 8, bottom: 8 })
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.colors().bgPrimary)
    // 始终可见：动画未触发/被打断时仍显示完整页面（0.94 也清晰可读），不再出现空白页
    .backgroundColor(this.colors().bgPrimary)

      // 右下角常驻退出胶囊：36vp（触摸 44），半透明，hover 不透明
      Row() {
        SymbolGlyph($r('sys.symbol.exit_full_screen'))
          .fontSize(14)
          .fontColor([this.colors().textSecondary])
          .margin({ right: 5 })
        Text('退出专注')
          .fontSize(12).fontColor(this.colors().textSecondary)
      }
      .height(this.app !== null && this.app.ui.pointerPrimary ? 36 : 44)
      .padding({ left: 12, right: 12 })
      .borderRadius(this.app !== null && this.app.ui.pointerPrimary ? 18 : 22)
      .backgroundColor(this.exitHovered ? this.colors().hoverBg : this.colors().bgSurface)
      .opacity(this.exitHovered ? 1 : 0.72)
      .animation({ duration: Motion.fast, curve: Motion.standardCurve })
      .margin({ right: 24, bottom: 24 })
      .accessibilityText('退出专注模式')
      .onHover((isHover: boolean) => { this.exitHovered = isHover })
      .onClick(() => this.exitFocus())
    }
    .width('100%').height('100%')
    .backgroundColor(this.colors().bgPrimary)
    // Esc 退出：冒泡到根节点时处理（编辑器未消费的情况下生效）
    .onKeyEvent((event: KeyEvent) => {
      // KeyCode.KEYCODE_ESCAPE = 2070（部分 SDK 未导出 KeyCode，用常量避免依赖）
      if (event.type === KeyType.Down && event.keyCode === KEY_ESCAPE_CODE) {
        this.exitFocus()
        return true
      }
      return false
    })
  }
}
