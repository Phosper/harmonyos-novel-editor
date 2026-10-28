// 一镜到底转场参数的中转站
//
// 参数必须在**点击当下**生成（要抓被点行的截图与几何），而真正 pushPath 发生在
// 异步读库之后。这里暂存一次参数，由 AppShell 在 push 时取走；
// 只有真的发生 push 才消费，避免参数泄漏到下一次无关跳转。
import type { LongTakeTransitionParam } from '../thirdparty/ezcustomtransition/Index'

/** pushPath 的 param 载体（ArkTS 要求对象字面量有明确类型） */
export interface LongTakeNavParam {
  longTakeTransitionParam: LongTakeTransitionParam
}

let pending: LongTakeTransitionParam | undefined = undefined

export function setPendingLongTake(param: LongTakeTransitionParam | undefined): void {
  pending = param
}

export function takePendingLongTake(): LongTakeTransitionParam | undefined {
  const current: LongTakeTransitionParam | undefined = pending
  pending = undefined
  return current
}
