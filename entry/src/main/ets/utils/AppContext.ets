// 应用上下文持有者 —— 在 EntryAbility 注入 AbilityContext，供 DatabaseHelper / PreferenceHelper 初始化使用
import { Context } from '@kit.AbilityKit'

let _ctx: Context | null = null

export function setAppContext(ctx: Context): void {
  _ctx = ctx
}

export function getAppContext(): Context | null {
  return _ctx
}
