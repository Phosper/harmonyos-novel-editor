import { window } from '@kit.ArkUI'
import { Logger } from './Logger'

/**
 * 自绘桌面标题栏接管原生标题栏。
 * 仅供 2in1 主窗口在 loadContent 成功后、或窗口重新进入前台且内容已就绪时调用。
 * 常驻标题、原生三键与全屏热区悬浮标题分别配置；保留系统 Dock。
 */
export function configureDesktopChrome(w: window.Window): void {
  try {
    w.setWindowDecorVisible(false)
  } catch (e) {
    Logger.warn('Desktop window decor config failed: ' + String(e))
  }
  try {
    w.setWindowTitleButtonVisible(false, false, false)
  } catch (e) {
    Logger.warn('Desktop native title buttons config failed: ' + String(e))
  }
  try {
    w.setTitleAndDockHoverShown(false, true).catch((e: Error) => {
      Logger.warn('Desktop title hover config failed: ' + String(e))
    })
  } catch (e) {
    Logger.warn('Desktop title hover config threw: ' + String(e))
  }
}
