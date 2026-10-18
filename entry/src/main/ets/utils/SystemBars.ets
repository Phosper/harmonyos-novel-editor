// 系统栏（状态栏 / 导航条）沉浸式配置
//
// 目标：状态栏区域始终与页面视觉一致——弹层蒙层（bindSheet / 对话框 / 抽屉）
// 压暗页面时状态栏同步压暗，消除"遮罩只暗内容、状态栏仍亮着"的割裂感。
//
// 实现：
//  1. 窗口底色 = 主题底色（不透明）：状态栏区域无论由根容器背景还是窗口底色承托，
//     透出的都是页面底色（EntryAbility 不再把窗口底色设为透明）；
//  2. 常态：系统栏背景**全透明**，直接透出底色。全窗蒙层（bindSheet 系统蒙层、
//     InputDialog 全窗遮罩）会连同状态栏一起压暗，无需逐个弹层适配；
//  3. 蒙层盖不到状态栏条的场景（如抽屉蒙层位于 padding 内容区内）：
//     由 UiStore.overlayDim 驱动 applySystemBarsDimmed，把状态栏底色
//     切成"底色 × 蒙层"的压暗色，与页面被压暗后的观感严格一致。
import { window } from '@kit.ArkUI'
import { Logger } from './Logger'
import { isPcPlatform } from './DeviceProfile'

/** 统一蒙层色：抽屉蒙层 / 对话框蒙层共用（bindSheet 用系统默认蒙层，无需指定） */
export const OVERLAY_MASK_COLOR: string = '#66000000'

/** contentColor 必须是 **8 位 ARGB**（#AARRGGBB）；6 位 #000000 会被系统忽略 */
function contentFor(dark: boolean): string {
  return dark ? '#FFFFFFFF' : '#FF000000'
}

/** 6 位 #RRGGBB → 不透明 8 位 ARGB */
function argbOf(hex6: string): string {
  const hex: string = hex6.startsWith('#') ? hex6.substring(1) : hex6
  return '#FF' + hex.toUpperCase()
}

/** 6 位 #RRGGBB 叠加 OVERLAY_MASK_COLOR（≈40% 黑）后的不透明结果色 */
export function blendWithMask(bgHex6: string): string {
  const hex: string = bgHex6.startsWith('#') ? bgHex6.substring(1) : bgHex6
  if (hex.length !== 6) {
    return argbOf(bgHex6)
  }
  const alpha: number = 0x66 / 0xFF
  const dim = (ch: string): string => {
    const v: number = Math.round(parseInt(ch, 16) * (1 - alpha))
    const s: string = v.toString(16).toUpperCase()
    return s.length === 1 ? '0' + s : s
  }
  return '#FF' + dim(hex.substring(0, 2)) + dim(hex.substring(2, 4)) + dim(hex.substring(4, 6))
}

/**
 * 2in1（PC）没有传统状态栏/导航条，`setWindowSystemBarProperties` 在 2in1 上不可用
 * （编译告警 "This API is unavailable to 2in1"，运行期返回 801）。
 * 桌面 chrome 由窗口装饰与自绘标题栏负责，这里直接跳过，避免无意义的 IPC 与报错。
 */
function barsUnavailable(): boolean {
  return isPcPlatform()
}

function setBars(w: window.Window, barColor: string, content: string): void {
  if (barsUnavailable()) {
    return
  }
  w.setWindowSystemBarProperties({
    statusBarColor: barColor,
    navigationBarColor: barColor,
    statusBarContentColor: content,
    navigationBarContentColor: content,
    enableStatusBarAnimation: true
  }).then(() => {
    Logger.info('setBars ok: bar=' + barColor + ' content=' + content)
  }).catch((e: Error) => {
    Logger.warn('setBars failed: ' + String(e))
  })
}

/** 常态：窗口底色=主题底色；系统栏全透明（透出底色），前景随明暗 */
export function applySystemBars(dark: boolean, bgHex: string): void {
  const w: window.Window | undefined = AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    Logger.info('applySystemBars: mainWindow undefined')
    return
  }
  try {
    w.setWindowBackgroundColor(argbOf(bgHex))
  } catch (e) {
    Logger.warn('setWindowBackgroundColor failed: ' + String(e))
  }
  setBars(w, '#00000000', contentFor(dark))
}

/** 弹层蒙层展示期间：状态栏底色=底色×蒙层（与被压暗的页面一致），前景随明暗 */
export function applySystemBarsDimmed(dark: boolean, bgHex: string): void {
  const w: window.Window | undefined = AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    Logger.info('applySystemBarsDimmed: mainWindow undefined')
    return
  }
  setBars(w, blendWithMask(bgHex), contentFor(dark))
}
