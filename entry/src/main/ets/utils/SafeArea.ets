// 安全区工具 —— 全屏布局（setWindowLayoutFullScreen(true)）下读取系统避让区，
// 供页面根容器做上下 padding 避让，避免标题栏/底部被状态栏与导航条遮挡。
//
// 设计要点：
// 1. 避让高度必须在**开启全屏布局之后**读取，否则 getWindowAvoidArea 返回值可能与实际不符
//    （官方沉浸式文档明确要求）；
// 2. px → vp 按定义换算（vp = px / densityPixels），不用已废弃的全局 px2vp；
// 3. 提供 watch 能力：窗口形态变化（最大化/分屏/旋转）会改变避让区，需要重新读取；
//    返回的函数用于 aboutToDisappear 里解绑，避免监听残留。
import { display, window } from '@kit.ArkUI'
import { Logger } from './Logger'

/** 顶部（状态栏 / 系统标题区）避让高度，vp */
let cachedTopVp: number = 0
/** 底部（导航条 / Home 指示条）避让高度，vp */
let cachedBottomVp: number = 0
/** 软键盘遮挡高度，vp（0 = 未弹出） */
let cachedKeyboardVp: number = 0

let bound: boolean = false
let listener: ((data: window.AvoidAreaOptions) => void) | null = null
let onAreaChange: (() => void) | null = null
let cachedWin: window.Window | null = null
let boundWin: window.Window | null = null

/**
 * px → vp。
 * 不用全局 `px2vp`：该接口已废弃（编译警告 deprecated），官方建议用 UIContext 的
 * `px2vp()`；本模块是无 UIContext 的工具函数，因此按定义换算 `vp = px / densityPixels`。
 * 密度读取失败时按 1:1 退化，至少不会因为异常中断页面。
 */
function toVp(px: number): number {
  if (cachedWin !== null) {
    try {
      return cachedWin.getUIContext().px2vp(px)
    } catch (e) {
    }
  }
  try {
    const density: number = display.getDefaultDisplaySync().densityPixels
    return px / (density > 0 ? density : 1)
  } catch (e) {
    return px
  }
}

/**
 * 读取一次避让区（结果缓存到模块级变量）。
 * @param win 显式指定的窗口；不传时回退 AppStorage('mainWindow')。
 *            显式传入可避免"AppStorage 还没写入就读"的时序问题（DeviceProfile.attach 用）。
 */
export function readSafeArea(win?: window.Window): void {
  const w: window.Window | undefined = win !== undefined ? win : AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    return
  }
  if (cachedWin !== w) {
    cachedTopVp = 0
    cachedBottomVp = 0
    cachedKeyboardVp = 0
    cachedWin = w
  }
  try {
    const sys: window.AvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
    cachedTopVp = toVp(sys.topRect.height)
  } catch (e) {
    Logger.warn('SafeArea: read TYPE_SYSTEM failed ' + String(e))
  }
  try {
    const nav: window.AvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
    cachedBottomVp = toVp(nav.bottomRect.height)
  } catch (e) {
    Logger.warn('SafeArea: read TYPE_NAVIGATION_INDICATOR failed ' + String(e))
  }
  try {
    // 软键盘：输入时必须让内容/光标让位，否则编辑器末行被键盘盖住
    const kb: window.AvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD)
    cachedKeyboardVp = toVp(kb.bottomRect.height)
  } catch (e) {
    Logger.warn('SafeArea: read TYPE_KEYBOARD failed ' + String(e))
  }
}

export function safeTopVp(): number {
  return cachedTopVp
}

export function safeBottomVp(): number {
  return cachedBottomVp
}

/** 软键盘遮挡高度（vp）：0 表示未弹出；收起时回到 0 */
export function keyboardHeightVp(): number {
  return cachedKeyboardVp
}

/**
 * 监听避让区变化。返回的 disposer 必须在页面 aboutToDisappear 中调用。
 *
 * 注意：只保留**一个**监听（AppShell 单例），多次注册会互相覆盖，
 * 故此处用模块级 bound 标志做幂等。
 */
export function watchSafeArea(onChange: () => void, win?: window.Window): () => void {
  readSafeArea(win)
  const w: window.Window | null = cachedWin
  if (w === null) {
    return () => {}
  }
  if (boundWin !== null && listener !== null && bound) {
    try {
      boundWin.off('avoidAreaChange', listener)
    } catch (e) {
      Logger.warn('SafeArea: replace watch failed ' + String(e))
    }
  }
  bound = false
  boundWin = w
  onAreaChange = onChange
  const nextListener: (data: window.AvoidAreaOptions) => void = (data: window.AvoidAreaOptions): void => {
    if (boundWin !== w || listener !== nextListener) {
      return
    }
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      cachedTopVp = toVp(data.area.topRect.height)
    } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      cachedBottomVp = toVp(data.area.bottomRect.height)
    } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      // 弹出/收起/切换输入法都会回调：高度 0 即收起
      cachedKeyboardVp = toVp(data.area.bottomRect.height)
    }
    if (onAreaChange !== null) {
      onAreaChange()
    }
  }
  listener = nextListener
  try {
    w.on('avoidAreaChange', nextListener)
    bound = true
  } catch (e) {
    Logger.warn('SafeArea: watch failed ' + String(e))
  }
  return () => {
    if (listener !== nextListener) {
      return
    }
    if (bound) {
      try {
        w.off('avoidAreaChange', nextListener)
      } catch (e) {
        Logger.warn('SafeArea: unwatch failed ' + String(e))
      }
    }
    bound = false
    boundWin = null
    listener = null
    onAreaChange = null
  }
}
