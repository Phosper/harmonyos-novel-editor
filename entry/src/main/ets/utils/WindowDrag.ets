/**
 * 窗口拖动 / 最大化工具（融合标题栏后，拖动热区分散到各栏头部）。
 *
 * 约束：
 * - 只能在 TouchType.Down / 鼠标左键 Press 的回调内调用 startMoving（系统限制）；
 * - 没有 mainWindow（手机/平板普通窗口）时静默 no-op；
 * - 不持有 UI 状态，各 pane header 只负责把空白区事件转进来。
 */
import { window } from '@kit.ArkUI'
import { Logger } from './Logger'

function mainWindow(): window.Window | undefined {
  return AppStorage.get<window.Window>('mainWindow')
}

export function startWindowMove(): void {
  const w: window.Window | undefined = mainWindow()
  if (w === undefined) {
    return
  }
  try {
    w.startMoving().catch((e: Error) => {
      Logger.warn('startWindowMove failed: ' + String(e))
    })
  } catch (e) {
    Logger.warn('startWindowMove failed: ' + String(e))
  }
}

export function toggleWindowMaximize(): void {
  const w: window.Window | undefined = mainWindow()
  if (w === undefined) {
    return
  }
  try {
    const status: window.WindowStatusType = w.getWindowStatus()
    if (status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN) {
      w.recover().catch((e: Error) => {
        Logger.warn('recover failed: ' + String(e))
      })
    } else {
      w.maximize().catch((e: Error) => {
        Logger.warn('maximize failed: ' + String(e))
      })
    }
  } catch (e) {
    Logger.warn('toggleWindowMaximize failed: ' + String(e))
  }
}

/** 最小化窗口（自绘三键用） */
export function minimizeWindow(): void {
  const w: window.Window | undefined = mainWindow()
  if (w === undefined) {
    return
  }
  try {
    w.minimize().catch((e: Error) => {
      Logger.warn('minimizeWindow failed: ' + String(e))
    })
  } catch (e) {
    Logger.warn('minimizeWindow threw: ' + String(e))
  }
}

/** 当前窗口是否已最大化/全屏（决定三键画「最大化」还是「还原」） */
export function isWindowMaximized(): boolean {
  const w: window.Window | undefined = mainWindow()
  if (w === undefined) {
    return false
  }
  try {
    const status: window.WindowStatusType = w.getWindowStatus()
    return status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN
  } catch (e) {
    Logger.warn('isWindowMaximized failed: ' + String(e))
    return false
  }
}

/** 是否是桌面窗口形态（自由窗口/电脑模式）。仅用于决定是否提供拖动热区。 */
export function isDesktopWindow(): boolean {
  const free: boolean | undefined = AppStorage.get<boolean>('freeWindowMode')
  const pc: boolean | undefined = AppStorage.get<boolean>('isPcDevice')
  return (free !== undefined && free) || (pc !== undefined && pc)
}
