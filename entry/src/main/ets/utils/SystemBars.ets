// 系统栏（状态栏 / 导航条）沉浸式配置
//
// 配合 window.setWindowLayoutFullScreen(true)：系统栏背景透明，让页面内容透出；
// 图标与时间颜色随明暗主题切换，保证可读。
import { window } from '@kit.ArkUI'
import { Logger } from './Logger'

/** 应用系统栏样式：状态栏底色=页面底色（无缝沉浸），前景色随明暗 */
export function applySystemBars(dark: boolean, bgHex: string): void {
  const w: window.Window | undefined = AppStorage.get<window.Window>('mainWindow')
  if (w === undefined) {
    Logger.info('applySystemBars: mainWindow undefined')
    return
  }
  // 注意：contentColor 必须是 **8 位 ARGB**（#AARRGGBB）；6 位 #000000 会被系统忽略。
  // 状态栏底色必须**不透明**，否则系统会自动改用白图标并忽略 contentColor。
  const bgArgb: string = bgHex.startsWith('#') ? '#FF' + bgHex.substring(1) : bgHex
  const content: string = dark ? '#FFFFFFFF' : '#FF000000'
  Logger.info('applySystemBars: dark=' + dark + ' bg=' + bgArgb + ' content=' + content)
  try {
    w.setWindowSystemBarProperties({
      statusBarColor: bgArgb,
      navigationBarColor: bgArgb,
      statusBarContentColor: content,
      navigationBarContentColor: content
    }).then(() => {
      Logger.info('applySystemBars: ok')
    }).catch((e: Error) => {
      Logger.warn('applySystemBars failed: ' + String(e))
    })
  } catch (e) {
    Logger.warn('applySystemBars threw: ' + String(e))
  }
}
