// 桌面沉浸标题栏的窗口侧配置（原生装饰栏接管）
//
// 官方接口分工（API 22 / 26）：
//   setWindowDecorVisible(false)               隐藏原生标题栏，页面延伸到标题栏区域
//   setWindowTitleButtonVisible(false,false,false) 隐藏原生三键，改由自绘 WindowControls 接管
//                                              （原生三键在隐藏装饰栏时恒为白色，无法换色）
//   setWindowDecorHeight(h)                    标题栏高度，取值 [37,112] vp
//   setDecorButtonStyle({colorMode})           原生三键的明暗（仅自由窗口生效；尺寸/间距交还系统）
//   setTitleAndDockHoverShown(false, true)     禁用 hover 悬浮标题栏，保留系统 Dock
//   getTitleButtonRect()                       原生三键矩形（相对窗口右上角）
//
// 分层（重要，兼容 tools/window-regression.cjs 的既有断言）：
//   configureDesktopChrome(w)            —— 只做上面三项"显隐/悬浮"配置，调用序列固定（旧契约）；
//   applyDesktopDecorMetrics(w, dark)    —— 尺寸/图标配置（高度 + 三键图标的明暗与大小）；
//   syncDesktopDecorButtons(dark)        —— 主工作台专用：按应用主题同步三键颜色
//                                          （UiStore.syncSystemBars 末尾调用）；
//   configureImmersiveDesktopChrome(w)   —— 两者合成，供 DesktopTitleBar 在挂载/窗口状态变化时调用。
// 之所以不把尺寸配置塞进 configureDesktopChrome：旧回归对它的**调用序列**做了精确断言，
// 拆分后既能保持旧行为逐字节兼容，又能让新标题栏拿到完整的沉浸配置。
import { window } from '@kit.ArkUI'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { Logger } from './Logger'

/** 自绘沉浸标题栏高度（vp）。原生装饰栏允许区间 [37,112] vp，48 取官方推荐的中等高度 */
export const DESKTOP_CHROME_HEIGHT_VP: number = 48

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
    // 保留系统原生三键（华为原生 hover / 贴边 / 无障碍 / 最大化还原语义）。
    // 颜色由系统按窗口 colorMode 决定：应用浅色主题时系统应画深色图标。
    w.setWindowTitleButtonVisible(true, true, true)
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

/** 离开自由窗口时归还系统装饰，保留系统原生三键。 */
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
    // 只改明暗，**不覆盖图案尺寸/按钮间距**：
    //   - 颜色跟随应用主题（而不是系统深浅），避免浅色稿纸上的白图标/深色主题下的黑图标；
    //   - 尺寸与间距一旦被 app 指定，系统会按新值重排，三个按钮会挤在一起、看起来像重叠
    //     （用户实测截图）；交还系统默认值才能保持华为原生的观感（同电子邮件）。
    const style: window.DecorButtonStyle = {
      colorMode: dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    }
    w.setDecorButtonStyle(style)
  } catch (e) {
    Logger.warn('Desktop decor button style failed: ' + String(e))
  }
}

/**
 * 按**当前主题明暗**同步原生三键（最小化 / 还原 / 关闭）的图标颜色。
 *
 * 主工作台已不再挂载 DesktopTitleBar，因此三键样式必须由主题层单独下发：
 * 否则系统沿用默认（跟随系统深浅），在浅色稿纸/列表上仍画白色图标，几乎看不见。
 * 非桌面窗口（手机、平板普通窗口）没有三键，直接跳过，避免每次同步都刷 801 警告。
 */
/**
 * 让系统按**当前 colorMode** 重新生成三键。
 *
 * 三键（最小化/还原/关闭）由系统绘制，颜色取窗口 colorMode；而窗口在创建时就固定了
 * 当时的 colorMode，之后应用改 colorMode（浅色主题覆盖系统深色）不会自动重绘，
 * 于是浅色稿纸上留下白色三键。切一次装饰栏显隐可让系统重建标题按钮区。
 * 只在启动完成、以及明暗真正变化时调用，避免可见闪烁。
 */
export function refreshDecorColorScheme(dark: boolean): void {
  // 首帧前不要动装饰栏：那会在启动画面上闪一下原生标题栏
  if (AppStorage.get<boolean>('uiReady') !== true) {
    return
  }
  const w: window.Window | undefined = AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    return
  }
  try {
    // setDecorButtonStyle 只对"带窗口标题"的窗口生效：先显示装饰栏、下发样式、再隐藏。
    // 这样窗口重建标题按钮区时会用新的 colorMode，浅色主题即可得到深色三键。
    w.setWindowDecorVisible(true)
    applyDesktopDecorMetrics(w, dark)
    w.setWindowDecorVisible(false)
  } catch (e) {
    Logger.warn('Decor color refresh failed: ' + String(e))
  }
}

export function syncDesktopDecorButtons(dark: boolean): void {
  const w: window.Window | undefined = AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    return
  }
  const pc: boolean | undefined = AppStorage.get<boolean>('isPcDevice')
  const free: boolean | undefined = AppStorage.get<boolean>('freeWindowMode')
  if (pc !== true && free !== true) {
    return
  }
  applyDesktopDecorMetrics(w, dark)
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
