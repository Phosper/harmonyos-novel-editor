// 全局路由入口
//
// 为什么用模块级单例而不是层层传回调：工作区（正文列表 → 编辑区）与设置页
// 都需要发起跳转，逐层传 @Event 会形成长链透传。
// NavPathStack 本身是"当前导航状态"的载体，放成单例与 store 同性质，且
// Navigation 组件接受任意 NavPathStack 实例。
//
// 官方模型（bpta-multi-device-page-layout 三分栏）：
//   SideBarContainer 第一栏（项目/文库）
//   Navigation 的 navBar 第二栏（文稿列表）
//   NavDestination 第三栏（工作区 / 二级页）
//
// 只保留**真正有人调用**的三个入口（nav / hasWorkspace / ensureWorkspace）。
// 素材、关系图、按章跳转的封装从来没有调用方，已删除（P1 死代码清理）：
// 新增整页功能时按交接稿方案走系统路由，不要在这里再堆特例函数。

/** 路由名 */
export class Routes {
  /** 工作区：文稿列表 + 编辑区（第三栏内容） */
  static readonly WORKSPACE: string = 'workspace'
  static readonly SETTINGS: string = 'settings'
  // 思路板不再是路由：它是 AppShell 的全窗口分支（app.ui.canvasOpen + geometryTransition）。
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
