// 思路板的一镜到底：把「工作区」平滑扩到整个窗口，而不是整页硬切。
//
// 与 FocusTransition 同一套做法：源（三栏内容区 / 手机外壳）与目标（CanvasDest 根容器）
// 共用 geometryTransition id，状态切换包在 animateTo 里，系统负责起止位置插值。
// 注意：CanvasDest 不再是路由目的地，因此不能复用 ezcustomtransition 的 NavDestination 转场。
import { curves, UIContext } from '@kit.ArkUI'
import { app } from '../store/AppStores'

/** 共享元素 id：AppShell 的内容区 / MobileShell 外壳 与 CanvasDest 根容器必须一致 */
export const CANVAS_SURFACE_ID: string = 'we-canvas-surface'

const CANVAS_DURATION: number = 340

/** 打开思路板：内容区长大到全窗口 */
export function openCanvasAnimated(ctx: UIContext): void {
  ctx.animateTo({ duration: CANVAS_DURATION, curve: curves.springMotion(0.6, 0.85) }, () => {
    app.ui.enterCanvas()
  })
}

/** 关闭思路板：全窗口收回到内容区 */
export function closeCanvasAnimated(ctx: UIContext): void {
  ctx.animateTo({ duration: CANVAS_DURATION, curve: curves.springMotion(0.6, 0.85) }, () => {
    app.ui.exitCanvas()
  })
}
