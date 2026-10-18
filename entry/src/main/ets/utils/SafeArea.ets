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

let bound: boolean = false
let listener: ((data: window.AvoidAreaOptions) => void) | null = null
let onAreaChange: (() => void) | null = null
let cachedWin: window.Window | null = null

/**
 * px → vp。
 * 不用全局 `px2vp`：该接口已废弃（编译警告 deprecated），官方建议用 UIContext 的
 * `px2vp()`；本模块是无 UIContext 的工具函数，因此按定义换算 `vp = px / densityPixels`。
 * 密度读取失败时按 1:1 退化，至少不会因为异常中断页面。
 */
let cachedDensity: number = 0

function density(): number {
  if (cachedDensity > 0) {
    return cachedDensity
  }
  try {
    const d: number = display.getDefaultDisplaySync().densityPixels
    cachedDensity = d > 0 ? d : 1
  } catch (e) {
    cachedDensity = 1
  }
  return cachedDensity
}

function toVp(px: number): number {
  return px / density()
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
  cachedWin = w
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
}

export function safeTopVp(): number {
  return cachedTopVp
}

export function safeBottomVp(): number {
  return cachedBottomVp
}

/**
 * 监听避让区变化。返回的 disposer 必须在页面 aboutToDisappear 中调用。
 *
 * 注意：只保留**一个**监听（AppShell 单例），多次注册会互相覆盖，
 * 故此处用模块级 bound 标志做幂等。
 */
export function watchSafeArea(onChange: () => void, win?: window.Window): () => void {
  readSafeArea(win)
  onAreaChange = onChange
  const w: window.Window | null = cachedWin
  if (w === null || bound) {
    return () => {
      onAreaChange = null
    }
  }
  listener = (data: window.AvoidAreaOptions): void => {
    if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      cachedTopVp = toVp(data.area.topRect.height)
    } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      cachedBottomVp = toVp(data.area.bottomRect.height)
    }
    if (onAreaChange !== null) {
      onAreaChange()
    }
  }
  try {
    w.on('avoidAreaChange', listener)
    bound = true
  } catch (e) {
    Logger.warn('SafeArea: watch failed ' + String(e))
  }
  return () => {
    if (cachedWin !== null && listener !== null && bound) {
      try {
        cachedWin.off('avoidAreaChange', listener)
      } catch (e) {
        Logger.warn('SafeArea: unwatch failed ' + String(e))
      }
    }
    bound = false
    listener = null
    onAreaChange = null
  }
}
