// 手机端外壳 —— 断点驱动的 sm 单列 / md 双栏
//
// 设计判据（严格遵循官方）：
//   1) 布局档位只由**窗口宽度断点**决定（app.ui.breakPoint），不用设备类型/方向/折叠状态；
//   2) sm（<600vp）：单列内容 + 官方式底部页签；打开文稿时以整屏 NavDestination 覆盖主页；
//   3) md（600–840vp）：侧栏 + 内容双栏，内容区顶部用分段页签（文稿/素材/关系图）；
//   4) lg（≥840vp）：**不走本组件**，由 AppShell 保持现有三栏（零回归）。
//
// 复用既有业务组件（ProjectSidebar / DocListPane / MaterialPane / GraphPane / 二级 Dest），
// 本组件只负责"手机端 chrome 编排 + 路由宿主"。
import { promptAction } from '@kit.ArkUI'
import { BreakPoint } from '../utils/BreakPoint'
import { tokensFor, WeaverColorSet, WeaverMobile, MobileTab } from '../constants/DesignTokens'
import { app, fireAndLog } from '../store/AppStores'
import { ShellDialog } from '../store/UiStore'
import type { BookModel } from '../model/Book'
import { nav, Routes } from './Navigator'
import { LongTakeNavParam, takePendingLongTake } from './LongTakeBridge'
import { ezCustomTransition, LongTakeTransitionParam } from '../thirdparty/ezcustomtransition/Index'
import { ProjectSidebar } from './ProjectSidebar'
import { DocListPane } from './DocListPane'
import { MobileTabBar, MobileTabItem } from './MobileTabBar'
import { WorkspaceDest } from './WorkspaceDest'
import { SettingsDest } from '../pages/dest/SettingsDest'
import { GlowPageBackground, glassBarStyle } from './MaterialSurface'

@ComponentV2
export struct MobileShell {
  /** 导出 / 导入逻辑仍由 AppShell 持有，通过事件回传，避免重复实现 */
  @Event onExport: () => void = () => {}
  @Event onImport: () => void = () => {}
  /** 一镜到底转场期间禁用 Navigation 交互 */
  @Local navInteractive: boolean = true

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private isNarrow(): boolean {
    return app.ui.breakPoint === BreakPoint.SM
  }

  private tabItems(): MobileTabItem[] {
    // 手机端按新设计：只保留 项目 / 文稿 —— 砍掉素材与关系图
    return [
      { id: MobileTab.PROJECT, label: '项目' },
      { id: MobileTab.DOCS, label: '文稿' }
    ]
  }

  private titleText(): string {
    const tab: MobileTab = app.ui.mobileTab
    if (tab === MobileTab.PROJECT) {
      return '项目'
    }
    return app.project.bookName === '' ? '语流' : app.project.bookName
  }

  // ===================== 结构 =====================

  build() {
    Stack() {
      // 页面光感背景（渐变 + 顶部光晕，单层不吃点击）；
      // 内层容器背景置透明，让光感透出（原来是各层各铺一色，玻璃层会盖不住）
      GlowPageBackground(app.ui.themeId)
      Column() {
        if (this.isNarrow()) {
          this.narrowLayout()
        } else {
          this.mediumLayout()
        }
      }
      .width('100%').height('100%')
      .backgroundColor(Color.Transparent)
    }
    .width('100%').height('100%')
  }

  // ===================== sm：单列 + 底部页签 =====================

  @Builder
  narrowLayout() {
    Navigation(nav) {
      this.narrowHome()
    }
    .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
      return ezCustomTransition.customNavContentTransition(from, to, operation, {
        onTransitionStart: () => { this.navInteractive = false },
        onTransitionEnd: () => { this.navInteractive = true }
      })
    })
    .enabled(this.navInteractive)
    .mode(NavigationMode.Stack)
    .hideNavBar(false)
    .hideTitleBar(true)
    .hideToolBar(true)
    .navDestination(this.pageMap)
    .width('100%').height('100%')
  }

  @Builder
  narrowHome() {
    // 手机端：取消"项目"页与底部页签；主页即文稿列表
    // （打开 App 直达编辑页；切稿走编辑页的 ☰ 滑出目录）
    Column() {
      this.titleBar()
      Column() {
        this.docList()
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(Color.Transparent)
  }

  // ===================== md：侧栏 + 内容双栏 =====================

  @Builder
  mediumLayout() {
    SideBarContainer(SideBarContainerType.Embed) {
      this.projectSidebar()
      Column() {
        Navigation(nav) {
          this.mediumHome()
        }
        .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
          return ezCustomTransition.customNavContentTransition(from, to, operation, {
            onTransitionStart: () => { this.navInteractive = false },
            onTransitionEnd: () => { this.navInteractive = true }
          })
        })
        .enabled(this.navInteractive)
        .mode(NavigationMode.Stack)
        .hideNavBar(false)
        .hideTitleBar(true)
        .hideToolBar(true)
        .navDestination(this.pageMap)
        .width('100%').height('100%')
      }
      .width('100%').height('100%')
    }
    .showSideBar(true)
    .showControlButton(false)
    .minSideBarWidth(240)
    .maxSideBarWidth(320)
    .minContentWidth(360)
    .autoHide(false)
    .layoutWeight(1).width('100%').height('100%')
  }

  @Builder
  mediumHome() {
    // 中等宽度（md）：侧栏（项目）+ 文稿列表；素材/关系图已按新设计移除
    Column() {
      this.docList()
    }
    .width('100%').height('100%')
    .backgroundColor(Color.Transparent)
  }

  // ===================== chrome =====================

  @Builder
  titleBar() {
    Row() {
      Text(this.titleText())
        .fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      Text('更多')
        .fontSize(14).fontColor(this.colors().textSecondary)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .accessibilityText('更多')
        .onClick(() => this.openMoreMenu())

      Text('设置')
        .fontSize(14).fontColor(this.colors().textSecondary)
        .margin({ left: 6 })
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .accessibilityText('设置')
        .onClick(() => nav.pushPath({ name: Routes.SETTINGS }))
    }
    // 阔直板（Pura X View）：高度压到 40vp，左右让位大圆角
    .width('100%').height(app.ui.wideBar ? 40 : WeaverMobile.TITLEBAR_H)
    .padding({ left: app.ui.wideBar ? app.ui.cornerInset : 16, right: app.ui.wideBar ? app.ui.cornerInset : 10 })
    // 自绘顶栏不是系统标题栏 → 用 backgroundBlurStyle + 渐变 + 1px 下沿高光
    .attributeModifier(glassBarStyle(app.ui.themeId))
  }

  // ===================== 各板块（复用既有组件） =====================

  @Builder
  projectSidebar() {
    ProjectSidebar({
      app: app,
      onCreateProject: () => app.ui.requestDialog(ShellDialog.NEW_PROJECT),
      onDeleteProject: (id: string) => this.requestDeleteProject(id),
      // 侧栏左下角设置入口：手机/平板走路由页（与顶栏「设置」同一目的地）
      onSettings: () => nav.pushPath({ name: Routes.SETTINGS })
    })
  }

  @Builder
  docList() {
    DocListPane({
      app: app,
      showHeader: true,
      enableLongTake: true,
      onOpenDoc: (id: string) => this.openDoc(id),
      onRenameDoc: (id: string, current: string) => app.ui.requestDialog(ShellDialog.RENAME_DOC, id, current, '', app.project.currentBookId),
      onDeleteDoc: (id: string, title: string) => app.ui.requestDialog(ShellDialog.DELETE_DOC, id, '', title)
    })
  }

  // ===================== 行为 =====================

  private onTabSelect(tab: MobileTab): void {
    app.ui.mobileTab = tab
    if (tab === MobileTab.DOCS) {
      app.showEditor()
    }
  }

  private openDoc(id: string): void {
    // 点击当下抓好的转场参数（宽屏常驻第三栏时为空）
    const transition: LongTakeTransitionParam | undefined = takePendingLongTake()
    // openChapter 现在按 id 读取完整正文，读库可能失败 → then 链末端必须接住拒绝
    fireAndLog(app.openChapter(id).then(() => {
      if (!nav.getAllPathName().includes(Routes.WORKSPACE)) {
        if (transition !== undefined) {
          const navParam: LongTakeNavParam = { longTakeTransitionParam: transition }
          nav.pushPath({ name: Routes.WORKSPACE, param: navParam })
        } else {
          nav.pushPath({ name: Routes.WORKSPACE })
        }
      }
    }), 'MobileShell.openDoc')
  }

  private openMoreMenu(): void {
    // color 必填（string|Resource）：空字符串会触发运行时 401 并退出应用
    const menuColor: string = this.colors().textPrimary
    const b1: promptAction.Button = { text: '导出', color: menuColor }
    const b2: promptAction.Button = { text: '导入', color: menuColor }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '更多',
      buttons: [b1, b2]
    }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0) {
        this.onExport()
      } else {
        this.onImport()
      }
    })
  }

  private requestDeleteProject(id: string): void {
    const found: BookModel | undefined = app.project.books.find((b: BookModel) => b.id === id)
    const name: string = found !== undefined ? found.name : '该项目'
    app.ui.requestDialog(ShellDialog.DELETE_PROJECT, id, '', name)
  }

  // ===================== 路由（手机端 Navigation 的页映射） =====================

  @Builder
  pageMap(name: string, param: Object) {
    if (name === Routes.WORKSPACE) {
      WorkspaceDest({ showBack: true })
    } else if (name === Routes.SETTINGS) {
      SettingsDest({ onBack: () => nav.pop() })
    }
  }
}
