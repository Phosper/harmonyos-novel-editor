// 专注模式一镜到底：把"三分屏 → 编辑区铺满窗口"做成共享元素转场
//
// 思路：WorkSpace 的编辑区与 FocusWorkspace 的编辑区共用 geometryTransition id，
// 状态切换包在 animateTo 里，系统会把旧位置的编辑区平滑"长大"到新位置，
// 视觉上就是右栏向左扩展铺满全窗口（而不是整页硬切）。
import { curves, UIContext } from '@kit.ArkUI'
import { app } from '../store/AppStores'

/** 共享元素 id：WorkspaceDest 与 FocusWorkspace 的编辑区必须一致 */
export const FOCUS_EDITOR_ID: string = 'we-focus-editor'

const FOCUS_DURATION: number = 340

/** 进入/退出专注：统一转场时长与曲线（近临界弹簧，无过冲） */
export function toggleFocusAnimated(ctx: UIContext): void {
  ctx.animateTo({ duration: FOCUS_DURATION, curve: curves.springMotion(0.6, 0.85) }, () => {
    app.ui.toggleImmersiveEditing()
  })
}

export function exitFocusAnimated(ctx: UIContext): void {
  ctx.animateTo({ duration: FOCUS_DURATION, curve: curves.springMotion(0.6, 0.85) }, () => {
    app.ui.exitImmersiveEditing()
  })
}
