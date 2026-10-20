// 桌面沉浸标题栏的窗口侧配置（原生装饰栏接管）
//
// 官方接口分工（API 22 / 26）：
//   setWindowDecorVisible(false)               隐藏原生标题栏，页面延伸到标题栏区域
//   setWindowTitleButtonVisible(false,false,false) 隐藏原生三键，由应用关闭入口先保护草稿
//   setWindowDecorHeight(h)                    标题栏高度，取值 [37,112] vp
//   setDecorButtonStyle({buttonIconSize})      原生三键图标尺寸（仅自由窗口生效）
//   setTitleAndDockHoverShown(false, true)     禁用 hover 悬浮标题栏，保留系统 Dock
//   getTitleButtonRect()                       原生三键矩形（相对窗口右上角）
//
// 分层（重要，兼容 tools/window-regression.cjs 的既有断言）：
//   configureDesktopChrome(w)            —— 只做上面三项"显隐/悬浮"配置，调用序列固定（旧契约）；
//   applyDesktopDecorMetrics(w)          —— 新增的尺寸/图标配置（高度、三键图标）；
//   configureImmersiveDesktopChrome(w)   —— 两者合成，供 DesktopTitleBar 在挂载/窗口状态变化时调用。
// 之所以不把尺寸配置塞进 configureDesktopChrome：旧回归对它的**调用序列**做了精确断言，
// 拆分后既能保持旧行为逐字节兼容，又能让新标题栏拿到完整的沉浸配置。
import { window } from '@kit.ArkUI'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { Logger } from './Logger'

/** 自绘沉浸标题栏高度（vp）。原生装饰栏允许区间 [37,112] vp，48 取官方推荐的中等高度 */
export const DESKTOP_CHROME_HEIGHT_VP: number = 48

/**
 * 原生三键图标尺寸（vp）。
 * 官方 DecorButtonStyle.buttonIconSize（API 20+）取值区间 **[16, 24]**，默认 20；
 * 取 18 略小于自绘 48vp 栏高，既不越界也不压满行高。
 */
const TITLE_BUTTON_ICON_SIZE_VP: number = 18

/**
 * 自绘桌面标题栏接管原生标题栏。
 * 仅供自由窗口模式（window.isInFreeWindowMode() === true）的主窗口在
 * loadContent 成功后、或窗口重新进入前台且内容已就绪时调用。
 * 常驻标题、原生三键与全屏热区悬浮标题分别配置；保留系统 Dock。
 */
export function configureDesktopChrome(w: window.Window): void {
  try {
    w.setWindowDecorVisible(false)
  } catch (e) {
    Logger.warn('Desktop window decor config failed: ' + String(e))
  }
  try {
    // 关闭统一由自绘按钮执行严格保存，避免原生关闭按钮绕过草稿保护。
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

/** 离开自由窗口模式后归还系统装饰，避免遗留隐藏的标题栏。 */
export function restoreDesktopChrome(w: window.Window): void {
  try {
    w.setWindowDecorVisible(true)
  } catch (e) {
    Logger.warn('Desktop window decor restore failed: ' + String(e))
  }
  try {
    w.setWindowTitleButtonVisible(true, true, true)
  } catch (e) {
    Logger.warn('Desktop native title buttons restore failed: ' + String(e))
  }
  try {
    w.setTitleAndDockHoverShown(true, true).catch((e: Error) => {
      Logger.warn('Desktop title hover restore failed: ' + String(e))
    })
  } catch (e) {
    Logger.warn('Desktop title hover restore threw: ' + String(e))
  }
}

/**
 * 原生装饰栏尺寸与三键图标样式。
 * 全程 try/catch：老系统 / 非自由窗口下这些接口会抛 1300002、801，
 * 失败只降级（用自绘 48vp 高度、不设图标尺寸），绝不能让标题栏崩掉。
 */
export function applyDesktopDecorMetrics(w: window.Window, dark: boolean = false): void {
  try {
    w.setWindowDecorHeight(DESKTOP_CHROME_HEIGHT_VP)
  } catch (e) {
    Logger.warn('Desktop decor height config failed: ' + String(e))
  }
  try {
    // 原生三键的图标颜色跟随**应用主题**（而不是系统深浅），避免自定义深色主题下黑图标看不清。
    const style: window.DecorButtonStyle = {
      colorMode: dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT,
      buttonIconSize: TITLE_BUTTON_ICON_SIZE_VP
    }
    w.setDecorButtonStyle(style)
  } catch (e) {
    Logger.warn('Desktop decor button style failed: ' + String(e))
  }
}

/** 完整沉浸配置：装饰栏尺寸 + 三键样式 + 原生标题/三键隐藏 + 保留 Dock */
export function configureImmersiveDesktopChrome(w: window.Window, dark: boolean = false): void {
  applyDesktopDecorMetrics(w, dark)
  configureDesktopChrome(w)
}

/**
 * 原生三键区宽度（vp）。
 * 自绘栏的右侧按钮组需要右避让，否则可能与系统仍保留的三键重叠。
 * 官方 `getTitleButtonRect()` 返回 **TitleButtonRect**，其 width/right 已是 **vp**
 * （坐标相对窗口右上角），因此这里**不再做 px2vp 换算**。
 * 拿不到（非自由窗口 / 接口异常）时返回 0，即不避让。
 */
export function readTitleButtonWidthVp(w: window.Window): number {
  try {
    const rect: window.TitleButtonRect = w.getTitleButtonRect()
    return rect.width > 0 ? rect.width : 0
  } catch (e) {
    return 0
  }
}

/** 当前窗口是否最大化/全屏（决定"最大化"还是"还原"图标）；读取失败按未最大化处理 */
export function isMaximizedStatus(status: number): boolean {
  return status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN
}
