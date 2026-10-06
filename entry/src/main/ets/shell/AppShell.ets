// 应用外壳 —— 官方三分栏模型
//
//   SideBarContainer（第一栏：项目 / 文库分类）
//     └ Column
//        Navigation（第二栏 navBar：文稿列表；第三栏 NavDestination：工作区与二级页）
//
// 关键取舍（均有官方依据，见 docs/research/03、04）：
// 1. 断点只用「窗口宽度」，来源是系统的 getWindowWidthBreakpoint()，不自己写 vp 阈值
//    （官方文档说明个别设备会产品化调整阈值）。也**不再**用 deviceInfo.deviceType 判断，
//    那是 CodeLinter `one-multi-breakpoint-check` 明令禁止的写法。
// 2. SideBarContainer 用 AUTO：容器 ≥ minSideBarWidth + minContentWidth 时 Embed，
//    否则 Overlay —— 这正是官方为多设备响应式提供的能力，不必自己算。
// 3. Navigation 显式写死 mode（默认 Auto 会在平板自动分栏，与自绘外壳冲突），
//    hideNavBar 保持 false —— 设为 true 会连同**内容区**一起隐藏，栈空即整屏空白。
// 4. 二级页面用 NavDestination（官方路径），返回键由路由栈接管，无需手写 onBackPress。
import { promptAction, window } from '@kit.ArkUI'
import { BreakPoint, breakPointFrom } from '../utils/BreakPoint'
import { Logger } from '../utils/Logger'
import { WeaverSpacing, tokensFor, WeaverColorSet } from '../constants/DesignTokens'
import { app } from '../store/AppStores'
import { ShellDialog } from '../store/UiStore'
import type { BookModel } from '../model/Book'
import type { ChapterModel } from '../model/Chapter'
import { ExportService, ExportFormat, ExportableChapter } from '../utils/ExportService'
import { ProjectSidebar } from './ProjectSidebar'
import { DocListPane } from './DocListPane'
import { InputDialog } from './InputDialog'
import { PcWindowBar } from './PcWindowBar'
import { WorkspaceDest } from './WorkspaceDest'
import { MobileShell } from './MobileShell'
import { nav, Routes, ensureWorkspace } from './Navigator'
import { SettingsDest } from '../pages/dest/SettingsDest'
import { watchSafeArea, safeTopVp, safeBottomVp } from '../utils/SafeArea'

enum ToolbarAction {
  UNDO = 0,
  REDO = 1
}

@ComponentV2
export struct AppShell {
  @Local loading: boolean = true
  @Local loadError: string = ''
  @Local breakPoint: BreakPoint = BreakPoint.LG
  /** 系统避让区（沉浸式全屏）：顶部状态栏 / 底部导航条高度（vp） */
  @Local safeTop: number = 0
  @Local safeBottom: number = 0

  private sizeChangeBound: boolean = false
  private safeDisposer: (() => void) | null = null

  aboutToAppear(): void {
    // isPcDevice 由 EntryAbility 写入 AppStorage，但此前**从未被读回**，
    // 导致 app.ui.isPc 恒为 false → PcWindowBar 永不渲染 → 系统标题栏一直在。
    // 这里是修复点：显式把 AppStorage 的值同步进 store。
    const pc: boolean | undefined = AppStorage.get<boolean>('isPcDevice')
    app.ui.isPcDevice = pc !== undefined ? pc : false
    // 沉浸式：全设备全屏布局，内容延伸到系统栏区域 → 按避让区推开顶部/底部
    this.safeDisposer = watchSafeArea(() => {
      this.safeTop = safeTopVp()
      this.safeBottom = safeBottomVp()
    })
    this.safeTop = safeTopVp()
    this.safeBottom = safeBottomVp()
    this.syncBreakPoint()
    this.registerSizeChange()
    app.init()
      .then(() => {
        this.loading = false
        // 手机端设计：主页直接打开"最近编辑过"的一篇文稿（sm/md）；宽屏保持原行为
        if (this.breakPoint !== BreakPoint.LG) {
          this.openRecentForMobile()
        }
      })
      .catch((e: Error) => {
        // 初始化失败必须收敛到可见错误态：既不能留下永久 loading，
        // 也不能把异常抛成未处理的 Promise 拒绝（会被系统按 JS 错误杀进程）
        Logger.error('AppShell: app.init failed: ' + String(e))
        this.loadError = String(e)
        this.loading = false
      })
  }

  /** 手机端启动：打开最近编辑过的文稿并进入编辑页（无文稿则停留在文稿列表） */
  private openRecentForMobile(): void {
    app.openMostRecentChapter()
      .then(async (opened: boolean) => {
        if (!opened) {
          // 没有任何文稿：直接新建一篇并进入编辑页（打开 App 即写作）
          await app.createChapter()
        }
        ensureWorkspace()
      })
      .catch((e: Error) => {
        Logger.warn('AppShell: openRecentForMobile failed: ' + String(e))
      })
  }

  aboutToDisappear(): void {
    this.releaseSizeChange()
    if (this.safeDisposer !== null) {
      this.safeDisposer()
      this.safeDisposer = null
    }
    app.flushAll()
  }

  // ===================== 断点 =====================

  private mainWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  private syncBreakPoint(): void {
    try {
      const bp: WidthBreakpoint = this.getUIContext().getWindowWidthBreakpoint()
      const next: BreakPoint = breakPointFrom(bp)
      if (next !== this.breakPoint) {
        // 断点档位变化时重置侧栏默认显隐：窄屏默认收起（以 Overlay 抽屉出现），宽屏默认常驻
        app.ui.showSidebar = next !== BreakPoint.SM
      }
      this.breakPoint = next
      app.ui.breakPoint = next
      // 仅在宽屏（lg）让工作区常驻第三栏：它自带"还没有打开任何文稿"的空状态，
      // 等价于官方的分栏占位页（splitPlaceholder）。
      // sm/md 不再预置工作区 —— 手机端以底部页签/分段页签为首页，打开文稿时才推入工作区。
      if (next === BreakPoint.LG) {
        ensureWorkspace()
      }
    } catch (e) {
      Logger.error('syncBreakPoint failed, keep current: ' + String(e))
    }
  }

  private registerSizeChange(): void {
    const win: window.Window | undefined = this.mainWindow()
    if (win === undefined) {
      return
    }
    try {
      win.on('windowSizeChange', () => {
        this.syncBreakPoint()
      })
      this.sizeChangeBound = true
      Logger.info('AppShell: windowSizeChange bound')
    } catch (e) {
      Logger.error('bind windowSizeChange failed: ' + String(e))
    }
  }

  private releaseSizeChange(): void {
    const win: window.Window | undefined = this.mainWindow()
    if (win === undefined || !this.sizeChangeBound) {
      return
    }
    try {
      win.off('windowSizeChange')
    } catch (e) {
      Logger.warn('unbind windowSizeChange failed: ' + String(e))
    }
    this.sizeChangeBound = false
  }

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  // 官方推荐 Auto：容器宽 ≥600vp 自动分栏（Split），不足则堆叠（Stack），
  // 不再自己按断点硬切，避免与系统应用的自由窗口表现不一致
  private navMode(): NavigationMode {
    return NavigationMode.Auto
  }

  // 官方默认 navBarWidth 240vp（可调范围 [240, min(组件宽40%, 432)]）
  private navBarWidthVp(): number {
    return this.breakPoint === BreakPoint.MD ? 240 : 300
  }

  // SideBarContainer 宽度：官方默认 min240/max280；平板和 2in1 最佳实践给 320/500
  private sideBarMinWidth(): number {
    return app.ui.isPc ? 320 : 240
  }

  private sideBarMaxWidth(): number {
    return app.ui.isPc ? 500 : 280
  }

  // ===================== 结构 =====================

  build() {
    Stack() {
      Column() {
        if (this.loading) {
          this.loadingView()
        } else if (this.loadError !== '') {
          this.errorView()
        } else {
          this.mainLayout()
        }
      }
      .width('100%').height('100%')
      // 沉浸式（官方两步法）：
      //   ① setWindowLayoutFullScreen(true) 已在 EntryAbility 开启；
      //   ② 这里用 expandSafeArea 让**背景**铺满状态栏/导航条区域，内容再按顶部避让。
      .padding({ top: this.safeTop })
      .backgroundColor(this.colors().bgPrimary)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (app.ui.dialog !== ShellDialog.NONE) {
        this.dialogView()
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  loadingView() {
    Column() {
      LoadingProgress().width(40).height(40).color(this.colors().brand)
      Text('正在打开你的稿纸…')
        .fontSize(13).fontColor(this.colors().textTertiary).margin({ top: 12 })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  errorView() {
    Column() {
      Text('数据初始化失败').fontSize(16).fontColor(this.colors().textPrimary)
      Text(this.loadError)
        .fontSize(12).fontColor(this.colors().textTertiary)
        .maxLines(6).textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 10, left: 32, right: 32 })
      Button('重试')
        .height(40).fontSize(14).margin({ top: 20 })
        .backgroundColor(this.colors().brand).fontColor(this.colors().onBrand)
        .borderRadius(8)
        .onClick(() => {
          this.loadError = ''
          this.loading = true
          app.init()
            .then(() => { this.loading = false })
            .catch((e: Error) => {
              this.loadError = String(e)
              this.loading = false
            })
        })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  mainLayout() {
    Column() {
      if (app.ui.isPc) {
        PcWindowBar({ app: app })
      }
      // 断点分发：lg 及以上走现有三栏（完全不变）；sm/md 走手机端外壳。
      if (this.breakPoint === BreakPoint.LG) {
        this.appBar()
        this.wideBody()
      } else {
        MobileShell({
          onExport: () => this.openExportMenu(),
          onImport: () => this.runImport()
        })
      }
    }
    .width('100%').height('100%')
  }

  // 宽屏（lg）现有三分栏 —— 原样保留，零回归。
  @Builder
  wideBody() {
    SideBarContainer(SideBarContainerType.AUTO) {
      ProjectSidebar({
        app: app,
        onCreateProject: () => app.ui.requestDialog(ShellDialog.NEW_PROJECT),
        onDeleteProject: (id: string) => this.requestDeleteProject(id)
      })

      Column() {
        Navigation(nav) {
          DocListPane({
            app: app,
            showHeader: true,
            onOpenDoc: (id: string) => this.openDoc(id),
            onRenameDoc: (id: string, current: string) =>
              app.ui.requestDialog(ShellDialog.RENAME_DOC, id, current),
            onDeleteDoc: (id: string, title: string) =>
              app.ui.requestDialog(ShellDialog.DELETE_DOC, id, '', title)
          })
        }
        .mode(this.navMode())
        .navBarWidth(this.navBarWidthVp())
        .minContentWidth(360)
        .hideNavBar(false)
        .hideTitleBar(true)
        .hideToolBar(true)
        .navDestination(this.pageMap)
        .width('100%').height('100%')
      }
      .width('100%').height('100%')
    }
    .showSideBar(app.ui.showSidebar)
    .showControlButton(false)
    .minSideBarWidth(this.sideBarMinWidth())
    .maxSideBarWidth(this.sideBarMaxWidth())
    .minContentWidth(360)
    .autoHide(false)
    .onChange((shown: boolean) => {
      app.ui.showSidebar = shown
    })
    .layoutWeight(1)
    .width('100%')
  }

  // 命名注意：不要叫 toolbar —— 它是 ArkUI 内置属性名（基类 CustomComponent 已占用），
  // 同名 @Builder 会被解析成属性设置器并报类型错误。
  @Builder
  appBar() {
    Row() {
      Text('侧栏')
        .fontSize(13)
        .fontColor(app.ui.showSidebar ? this.colors().brand : this.colors().textSecondary)
        .onClick(() => app.ui.toggleSidebar())
      Text(this.centerTitle())
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
        .margin({ left: 16 }).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      this.toolbarAction(ToolbarAction.UNDO, '撤销')
      this.toolbarAction(ToolbarAction.REDO, '重做')
      Text('导出').fontSize(13).fontColor(this.colors().textSecondary)
        .margin({ left: 18 }).onClick(() => this.openExportMenu())
      Text('导入').fontSize(13).fontColor(this.colors().textSecondary)
        .margin({ left: 18 }).onClick(() => this.runImport())
      Text('设置').fontSize(13).fontColor(this.colors().textSecondary)
        .margin({ left: 18 }).onClick(() => nav.pushPath({ name: Routes.SETTINGS }))
    }
    .width('100%').height(WeaverSpacing.TITLEBAR_H)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.colors().bgCard)
    .border({ width: { bottom: 1 }, color: this.colors().divider })
  }

  @Builder
  toolbarAction(kind: ToolbarAction, label: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.isToolbarEnabled(kind) ? this.colors().textSecondary : this.colors().textTertiary)
      .margin({ left: 18 })
      .onClick(() => this.runToolbar(kind))
  }

  private isToolbarEnabled(kind: ToolbarAction): boolean {
    return kind === ToolbarAction.UNDO ? app.editor.canUndo : app.editor.canRedo
  }

  private runToolbar(kind: ToolbarAction): void {
    if (kind === ToolbarAction.UNDO) {
      app.editor.undo()
    } else {
      app.editor.redo()
    }
  }

  private centerTitle(): string {
    return app.project.bookName
  }

  // ===================== 路由 =====================

  @Builder
  pageMap(name: string, param: Object) {
    if (name === Routes.WORKSPACE) {
      WorkspaceDest({ showBack: this.breakPoint === BreakPoint.SM })
    } else if (name === Routes.SETTINGS) {
      SettingsDest({ onBack: () => nav.pop() })
    }
  }

  private async openDoc(chapterId: string): Promise<void> {
    await app.openChapter(chapterId)
    if (!nav.getAllPathName().includes(Routes.WORKSPACE)) {
      nav.pushPath({ name: Routes.WORKSPACE })
    }
  }

  // ===================== 对话框 =====================

  private requestDeleteProject(id: string): void {
    const found: BookModel | undefined = app.project.books.find((b: BookModel) => b.id === id)
    const name: string = found !== undefined ? found.name : '该项目'
    app.ui.requestDialog(ShellDialog.DELETE_PROJECT, id, '', name)
  }

  @Builder
  dialogView() {
    InputDialog({
      app: app,
      title: this.dialogTitle(),
      message: this.dialogMessage(),
      placeholder: this.dialogPlaceholder(),
      initialValue: app.ui.dialogInitial,
      confirmLabel: this.dialogConfirmLabel(),
      danger: app.ui.dialog === ShellDialog.DELETE_PROJECT || app.ui.dialog === ShellDialog.DELETE_DOC,
      withInput: app.ui.dialog !== ShellDialog.DELETE_PROJECT && app.ui.dialog !== ShellDialog.DELETE_DOC,
      onConfirm: (value: string) => this.handleDialogConfirm(value),
      onCancel: () => app.ui.closeDialog()
    })
  }

  private dialogTitle(): string {
    const d: ShellDialog = app.ui.dialog
    if (d === ShellDialog.NEW_PROJECT) return '新建项目'
    if (d === ShellDialog.RENAME_DOC) return '重命名文稿'
    if (d === ShellDialog.NEW_CHARACTER) return '新建人物'
    if (d === ShellDialog.NEW_WORLD) return '新建世界观条目'
    if (d === ShellDialog.DELETE_PROJECT) return '删除项目'
    if (d === ShellDialog.DELETE_DOC) return '删除文稿'
    return ''
  }

  private dialogMessage(): string {
    const d: ShellDialog = app.ui.dialog
    if (d === ShellDialog.DELETE_PROJECT) {
      return '「' + app.ui.dialogSubject + '」及其全部文稿将被永久删除，无法恢复。'
    }
    if (d === ShellDialog.DELETE_DOC) {
      return '「' + app.ui.dialogSubject + '」将被永久删除，无法恢复。'
    }
    return ''
  }

  private dialogPlaceholder(): string {
    const d: ShellDialog = app.ui.dialog
    if (d === ShellDialog.NEW_PROJECT) return '项目名称'
    if (d === ShellDialog.NEW_CHARACTER) return '人物名称'
    if (d === ShellDialog.NEW_WORLD) return '条目名称'
    return '文稿标题'
  }

  private dialogConfirmLabel(): string {
    const d: ShellDialog = app.ui.dialog
    if (d === ShellDialog.DELETE_PROJECT || d === ShellDialog.DELETE_DOC) return '删除'
    return '确定'
  }

  private async handleDialogConfirm(value: string): Promise<void> {
    const kind: ShellDialog = app.ui.dialog
    const target: string = app.ui.dialogTarget
    app.ui.closeDialog()
    const trimmed: string = value.trim()

    if (kind === ShellDialog.NEW_PROJECT) {
      if (trimmed === '') return
      await app.createBook(trimmed)
      return
    }
    if (kind === ShellDialog.RENAME_DOC) {
      if (trimmed === '') return
      await app.renameChapter(target, trimmed)
      return
    }
    if (kind === ShellDialog.DELETE_PROJECT) {
      await app.deleteBook(target)
      return
    }
    if (kind === ShellDialog.DELETE_DOC) {
      await app.hardDeleteChapter(target)
      this.toast('已删除')
    }
  }

  // ===================== 导出 / 导入 =====================

  private openExportMenu(): void {
    // showActionMenu 的 buttons 是定长 tuple（1~6 项），必须写成字面量元组；
    // color 为必填项，空字符串会触发运行时 401「Parameter error」并退出应用。
    const menuColor: string = this.colors().textPrimary
    const b1: promptAction.Button = { text: '当前文稿 · TXT', color: menuColor }
    const b2: promptAction.Button = { text: '当前文稿 · Markdown', color: menuColor }
    const b3: promptAction.Button = { text: '当前文稿 · HTML', color: menuColor }
    const b4: promptAction.Button = { text: '整本导出 · TXT', color: menuColor }
    const b5: promptAction.Button = { text: '整本导出 · Markdown', color: menuColor }
    const b6: promptAction.Button = { text: '整本导出 · JSON 备份', color: menuColor }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '导出',
      buttons: [b1, b2, b3, b4, b5, b6]
    }, (err, data) => {
      if (err) {
        return
      }
      this.doExport(data.index)
    })
  }

  private async doExport(index: number): Promise<void> {
    const wholeBook: boolean = index >= 3
    const pick: number = wholeBook ? index - 3 : index
    const bookName: string = app.project.bookName === '' ? 'Weaver' : app.project.bookName

    if (pick === 3) {
      const payload = await app.exportBackupData()
      await ExportService.exportBackupJson(bookName, payload)
      return
    }
    const target: ExportFormat = pick === 1
      ? ExportFormat.MD
      : (pick === 2 ? ExportFormat.HTML : ExportFormat.TXT)

    if (!wholeBook) {
      if (!app.editor.hasDoc) {
        this.toast('当前没有打开的文稿')
        return
      }
      const chapter: ExportableChapter = {
        title: app.editor.title,
        content: app.editor.content,
        format: app.editor.format,
        runsJson: app.editor.runsJson
      }
      const text: string = ExportService.renderChapter(chapter, target, chapter.title)
      await ExportService.saveText(chapter.title + ExportService.extensionOf(target), text)
      return
    }

    const chapters: ExportableChapter[] = app.project.chapters
      .filter((c: ChapterModel) => !c.isTrash)
      .map((c: ChapterModel): ExportableChapter => ({
        title: c.title, content: c.content, format: c.format,
        runsJson: c.formatRuns !== undefined ? c.formatRuns : ''
      }))
    if (chapters.length === 0) {
      this.toast('当前项目没有可导出的文稿')
      return
    }
    const text: string = ExportService.renderBook(bookName, chapters, target)
    await ExportService.saveText(bookName + ExportService.extensionOf(target), text)
  }

  private async runImport(): Promise<void> {
    const result: string = await app.importFiles()
    if (result !== '') {
      this.toast(result)
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}
