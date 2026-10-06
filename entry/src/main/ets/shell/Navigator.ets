// 全局路由入口
//
// 为什么用模块级单例而不是层层传回调：二级页面（设置/人物/世界观/灵感）与
// 各面板（列表/素材/关系图）都需要发起跳转，逐层传 @Event 会形成长链透传。
// NavPathStack 本身是"当前导航状态"的载体，放成单例与 store 同性质，且
// Navigation 组件接受任意 NavPathStack 实例。
//
// 官方模型（bpta-multi-device-page-layout 三分栏）：
//   SideBarContainer 第一栏（项目/文库）
//   Navigation 的 navBar 第二栏（文稿列表）
//   NavDestination 第三栏（工作区 / 二级页）
import { app } from '../store/AppStores'
import { EditorViewMode } from '../constants/DesignTokens'

/** 路由名 */
export class Routes {
  /** 工作区：编辑器 + 素材 + 关系图（第三栏内容） */
  static readonly WORKSPACE: string = 'workspace'
  static readonly SETTINGS: string = 'settings'
}

/** 全局导航栈：由 AppShell 的 Navigation 组件消费 */
export const nav: NavPathStack = new NavPathStack()

/** 工作区是否已在栈上 */
export function hasWorkspace(): boolean {
  return nav.getAllPathName().includes(Routes.WORKSPACE)
}

/**
 * 确保工作区在栈上。
 * 宽屏（Split）下它占据第三栏；窄屏（Stack）下它是覆盖文稿列表的整屏页。
 * 路由不携带"当前是哪篇文稿"——那是 store 的状态（app.editor.activeId），
 * 避免路由参数与状态两份真相。
 */
export function ensureWorkspace(): void {
  if (!hasWorkspace()) {
    nav.pushPath({ name: Routes.WORKSPACE })
  }
}

/** 打开某篇文稿并进入工作区 */
export async function openChapter(chapterId: string): Promise<void> {
  await app.openChapter(chapterId)
  ensureWorkspace()
}

/** 切到某个板块（文稿 / 素材 / 关系图）并确保工作区可见 */
export async function openSection(view: EditorViewMode): Promise<void> {
  if (view === EditorViewMode.MATERIAL) {
    await app.showMaterials()
  } else if (view === EditorViewMode.GRAPH) {
    await app.showGraph()
  } else {
    app.showEditor()
  }
  ensureWorkspace()
}

/** 关闭全部文稿后从工作区退回文稿列表 */
export function leaveWorkspaceIfEmpty(): void {
  if (!app.editor.hasDoc && hasWorkspace()) {
    nav.pop()
  }
}

/** 回到根（文稿列表） */
export function backToRoot(): void {
  nav.clear()
}
