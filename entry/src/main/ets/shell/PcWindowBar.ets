// 桌面端自绘窗口控制条（配合 setWindowDecorVisible(false) 使用）
import { window } from '@kit.ArkUI'
import { Logger } from '../utils/Logger'
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'

@ComponentV2
export struct PcWindowBar {
  @Param app: AppStores | null = null

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  private win(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  private startMove(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.startMoving()
    } catch (e) {
      Logger.warn('startMoving failed: ' + String(e))
    }
  }

  private minimize(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.minimize()
    } catch (e) {
      Logger.warn('minimize failed: ' + String(e))
    }
  }

  private toggleMaximize(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      const status: window.WindowStatusType = w.getWindowStatus()
      if (status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN) {
        w.restore()
      } else {
        w.maximize()
      }
    } catch (e) {
      Logger.warn('toggleMaximize failed: ' + String(e))
    }
  }

  private close(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.destroyWindow()
    } catch (e) {
      Logger.warn('destroyWindow failed: ' + String(e))
    }
  }

  build() {
    Row() {
      Text('Weaver')
        .fontSize(12).fontColor(this.colors().textSecondary)
        .margin({ left: 12 })

      Row() { }
        .layoutWeight(1)
        .height('100%')
        // 拖拽区分两条输入路径：触屏走 onTouch，鼠标走 onMouse（鼠标不派发 onTouch）
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.startMove()
          }
        })
        .onMouse((event: MouseEvent) => {
          if (event.action === MouseAction.Press) {
            this.startMove()
          }
        })
        // 双击标题栏空白区切换最大化 —— 与桌面端窗口操作习惯一致
        .gesture(TapGesture({ count: 2 }).onAction(() => {
          this.toggleMaximize()
        }))

      this.winButton('─', () => this.minimize())
      this.winButton('□', () => this.toggleMaximize())
      this.winButton('✕', () => this.close())
    }
    // 高度与 EntryAbility 里 setWindowDecorHeight(36) 保持一致
    .width('100%').height(36)
    .backgroundColor(this.colors().bgSurface)
    .border({ width: { bottom: 1 }, color: this.colors().divider })
  }

  // 窗口控制按钮统一为中性样式：图标用二级文本色，背景透明靠 hover 高亮反馈，
  // 不再使用 Windows 风格的红色关闭按钮（与 HarmonyOS 桌面形态不一致）
  @Builder
  winButton(glyph: string, action: () => void) {
    Row() {
      Text(glyph).fontSize(12).fontColor(this.colors().textSecondary)
    }
    .width(46).height('100%')
    .justifyContent(FlexAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }
}
