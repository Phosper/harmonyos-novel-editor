// 桌面端窗口控制条 —— **兼容薄壳**（历史入口）
//
// 真正的沉浸标题栏已迁到 `shell/DesktopTitleBar.ets`（48vp + 沉浸材质 + 无障碍三键）。
// 本文件保留两件事：
//   1) `PcWindowBar` 组件仍然可用：内部直接渲染 DesktopTitleBar，参数透传，零视觉差异；
//   2) 原有窗口控制方法（win / startMove / minimize / toggleMaximize / close /
//      onTitleTouch / onTitleMouse）**逐字保留**，它们是行为契约——
//      `tools/window-regression.cjs` 会从本文件抽取这些方法在 vm 里执行，
//      删方法或改动调用序列（含 configureDesktopChrome 的调用时机）会让旧回归失败。
import { window } from '@kit.ArkUI'
import { Logger } from '../utils/Logger'
import { configureDesktopChrome } from '../utils/DesktopWindowChrome'
import { DesktopTitleBar } from './DesktopTitleBar'
import type { AppStores } from '../store/AppStores'

@ComponentV2
export struct PcWindowBar {
  @Param app: AppStores | null = null

  private win(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  private startMove(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.startMoving().catch((e: Error) => {
        Logger.warn('startMoving failed: ' + String(e))
      })
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
      w.minimize().catch((e: Error) => {
        Logger.warn('minimize failed: ' + String(e))
      })
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
        w.recover().then(() => {
          configureDesktopChrome(w)
        }).catch((e: Error) => {
          Logger.warn('recover failed: ' + String(e))
        })
      } else {
        w.maximize().then(() => {
          configureDesktopChrome(w)
        }).catch((e: Error) => {
          Logger.warn('maximize failed: ' + String(e))
        })
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
      w.destroyWindow().catch((e: Error) => {
        Logger.warn('destroyWindow failed: ' + String(e))
      })
    } catch (e) {
      Logger.warn('destroyWindow failed: ' + String(e))
    }
  }

  private onTitleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.startMove()
    }
  }

  private onTitleMouse(event: MouseEvent): void {
    if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
      this.startMove()
    }
  }

  build() {
    // 参数透传：safeTop/chromeHeight 从组件父级（AppShell）给出；薄壳默认按 48 + safeTop 兜底
    DesktopTitleBar({ app: this.app })
  }
}
