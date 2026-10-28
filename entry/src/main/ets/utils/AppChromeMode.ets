// 系统 chrome 的明暗跟随应用主题（不是系统深浅）
//
// 为什么需要：
//   本应用的内容全部自绘（主题 token 驱动），但**系统绘制**的部分——右上角窗口三键、
//   系统动作菜单（showActionMenu）、系统对话框——跟随的是应用 colorMode，
//   而应用默认跟随系统深浅。于是「系统深色 + 应用浅色纸墨」时会出现：
//     · 网页纸上的最小化/还原/关闭是白色，几乎看不见；
//     · showActionMenu 是深色底，我们传的深色文字直接看不清。
// 解决：用户选了什么主题，就把应用 colorMode 设成同一明暗，系统 chrome 自然对齐。
//
// 注意：这不会改变自绘 UI 的配色（配色来自 DesignTokens），只影响系统绘制的部分。
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { Logger } from './Logger'

const APP_CONTEXT_KEY: string = 'appApplicationContext'

/** 应用启动时登记 ApplicationContext，供主题切换时下发 colorMode */
export function rememberAppContext(ctx: common.ApplicationContext): void {
  AppStorage.setOrCreate<common.ApplicationContext>(APP_CONTEXT_KEY, ctx)
}

/** 让系统 chrome（三键 / 系统菜单 / 系统对话框）跟随应用主题明暗 */
export function applyAppColorMode(dark: boolean): void {
  const ctx: common.ApplicationContext | undefined =
    AppStorage.get<common.ApplicationContext>(APP_CONTEXT_KEY)
  if (ctx === undefined) {
    return
  }
  try {
    ctx.setColorMode(dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
  } catch (e) {
    Logger.warn('applyAppColorMode failed: ' + String(e))
  }
}
