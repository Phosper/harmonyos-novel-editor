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
import { curves, KeyboardAvoidMode, promptAction, window } from '@kit.ArkUI'
import { BreakPoint } from '../utils/BreakPoint'
import { Motion } from '../constants/Motion'
import { DeviceSnapshot, deviceProfile } from '../utils/DeviceProfile'
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
import { FocusWorkspace } from './FocusWorkspace'
import { EditorTools } from './EditorTools'
import { GlowPageBackground, glassBarStyle } from './MaterialSurface'
import { WorkspaceDest } from './WorkspaceDest'
import { MobileShell } from './MobileShell'
import { nav, Routes, ensureWorkspace } from './Navigator'
import { LongTakeNavParam, takePendingLongTake } from './LongTakeBridge'
import { ezCustomTransition, LongTakeTransitionParam } from '../thirdparty/ezcustomtransition/Index'
import { SettingsDest } from '../pages/dest/SettingsDest'
import { SettingsPanel } from './SettingsPanel'

enum ExportAction {
  CHAPTER_TXT = 0,
  CHAPTER_MD = 1,
  CHAPTER_HTML = 2,
  BOOK_TXT = 3,
  BOOK_MD = 4,
  BACKUP_JSON = 5
}

@ComponentV2
export struct AppShell {
  @Local loading: boolean = true
  @Local loadError: string = ''
  @Local dialogPending: boolean = false
  @Local breakPoint: BreakPoint = BreakPoint.LG
  /** 系统避让区（沉浸式全屏）：顶部状态栏 / 底部导航条高度（vp） */
  @Local safeTop: number = 0
  @Local safeBottom: number = 0
  /** 软键盘遮挡高度（0 = 未弹出）：与 safeBottom 取较大者，避免双重留白 */
  @Local keyboardHeight: number = 0
  /** 自绘标题栏总高（含安全区，vp）：0 表示当前没有自绘标题栏（手机/平板） */
  @Local chromeHeight: number = 0
  /** 是否走桌面沉浸标题栏：= 自由窗口模式（window.isInFreeWindowMode()） */
  @Local usesDesktopChrome: boolean = false
  /** 设置面板（半模态）：打开即从底部/居中浮出，不再从右侧推页面 */
  @Local showSettings: boolean = false
  /** 自定义转场期间禁用 Navigation 交互，避免动画被打断/布局错乱 */
  @Local navInteractive: boolean = true
  /** 历史深度镜像：窗口头工具条的撤销/重做禁用态靠它刷新 */
  @Local historyTick: number = 0

  @Monitor('app.editor.historyVersion')
  onHistoryVersion(): void {
    this.historyTick = app.editor.historyVersion
  }

  /** DeviceProfile 订阅释放器 */
  private profileDisposer: (() => void) | null = null

  aboutToAppear(): void {
    // 设备分流统一入口：断点 / 自由窗口 / 避让区 / 窗口状态全部由 DeviceProfile 订阅一次，
    // AppShell 只消费快照。旧实现把 watchSafeArea + windowSizeChange 分两处注册，
    // 且 isPcDevice 只写不读（导致 app.ui.isPc 恒为 false）—— 一并收口在这里。
    // 键盘避让由本页统一处理（读 TYPE_KEYBOARD → 底部 padding）。关掉框架默认的
    // OFFSET 整体上移，否则会与我们的 padding 叠加，出现“抬两次”的跳动。
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE)
    } catch (e) {
      Logger.warn('AppShell: setKeyboardAvoidMode failed: ' + String(e))
    }
    this.bindDeviceProfile()
    app.init()
      .then(() => {
        this.loading = false
        // 手机 / 平板：主页直接打开"最近编辑过"的一篇（平板即使三栏也直接进正文，
        // 避免右侧一大块空态）；桌面宽屏保持原行为（用户可自行挑一篇）
        if (this.breakPoint !== BreakPoint.LG || app.ui.tabletMode) {
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

  /**
   * 退出沉浸后，确保宽屏第三栏仍停在编辑工作区（沉浸期间直接渲染 FocusWorkspace，
   * 不依赖 Navigation 路由栈；若栈里没有 WORKSPACE，退出后要补回来）。
   */
  @Monitor('app.ui.immersiveEditing')
  onImmersiveEditingChanged(): void {
    if (!app.ui.immersiveEditing && this.breakPoint === BreakPoint.LG && app.editor.hasDoc) {
      ensureWorkspace()
    }
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
    // 只摘掉本页的订阅：窗口级监听归 DeviceProfile / EntryAbility 的窗口寿命管理，
    // 页面卸载时解绑窗口监听会让再次进入页面时丢事件。
    if (this.profileDisposer !== null) {
      this.profileDisposer()
      this.profileDisposer = null
    }
    app.flushAll()
  }

  // ===================== 断点 =====================

  private mainWindow(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  /**
   * 订阅设备快照并完成首次 attach。
   * DeviceProfile 内部注册 windowSizeChange / freeWindowModeChange / avoidAreaChange /
   * windowStatusChange；这里拿到的 disposer 只解除本页的订阅。
   */
  private bindDeviceProfile(): void {
    if (this.profileDisposer !== null) {
      return
    }
    this.profileDisposer = deviceProfile.onChange((snap: DeviceSnapshot): void => {
      this.handleSnapshot(snap)
    })
    const win: window.Window | undefined = this.mainWindow()
    try {
      if (win !== undefined) {
        // getUIContext() 只能在 loadContent 之后调用；aboutToAppear 已满足（§0 禁忌）
        deviceProfile.attach(this.getUIContext(), win)
      } else {
        deviceProfile.refresh()
      }
    } catch (e) {
      Logger.error('AppShell: deviceProfile attach failed: ' + String(e))
      // attach 失败也必须落到一份可用快照，否则界面会停在默认值上
      this.handleSnapshot(deviceProfile.snapshot)
    }
  }

  /**
   * 应用一份设备快照（唯一写入口）。
   *
   * 断点档位变化时保留原有副作用：窄屏默认收起侧栏（以 Overlay 抽屉出现）、
   * 宽屏常驻侧栏；宽屏常驻工作区（它自带"还没有打开任何文稿"的空状态）。
   */
  private handleSnapshot(snap: DeviceSnapshot): void {
    const nextBreakPoint: BreakPoint = snap.breakPoint
    if (nextBreakPoint !== this.breakPoint) {
      app.ui.showSidebar = nextBreakPoint !== BreakPoint.SM
    }
    this.breakPoint = nextBreakPoint
    this.safeTop = snap.safeTopVp
    this.safeBottom = snap.safeBottomVp
    this.keyboardHeight = snap.keyboardHeightVp
    this.usesDesktopChrome = snap.isDesktopChrome
    this.chromeHeight = snap.chromeHeightVp
    // store 与 AppShell 用同一份快照：deviceClass / freeWindowMode / pointerPrimary / breakPoint
    app.ui.applyDeviceSnapshot(snap)
    // 仅在宽屏（lg）让工作区常驻第三栏；sm/md 打开文稿时才推入工作区
    if (nextBreakPoint === BreakPoint.LG) {
      ensureWorkspace()
    }
  }

  /**
   * 根容器顶部内边距（vp）—— **只取一种来源，绝不双算**：
   *
   *  · 电脑模式（自由窗口）：取 chromeHeight 这一种。快照里
   *    chromeHeightVp = 48 + safeTopVp，已经含了状态栏高度；
   *    DesktopTitleBar 是根容器的第一个子节点、自身高度就是 chromeHeight，
   *    它已经把后续内容下推了 chromeHeight，所以根容器这里必须补 **0**。
   *    （再加 safeTop 或再加 chromeHeight 都是双算 —— §3 的"防双算"落点在这里。）
   *  · 手机/平板：没有自绘标题栏，仍按 safeTop 撑开；配合 expandSafeArea 的
   *    背景延伸，原有上下避让行为完全不变。
   */
  private topInset(): number {
    // 融合布局下窗口层不再占高度，内容需要自己避让状态栏/刘海；
    // PC 自由窗口 safeTop 通常为 0，平板电脑模式若有状态栏则由这里兜住。
    return this.safeTop
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
  // 三形态分流（只改 chrome/尺寸，不改断点）：
  //   电脑（自由窗口）→ 320：键鼠场景信息密度更高，列表列宽更宽
  //   平板（触摸为主）→ 280：给正文留更多横向空间
  //   md 档（手机横屏/折叠）→ 240
  private navBarWidthVp(): number {
    if (this.breakPoint === BreakPoint.MD) {
      return 240
    }
    // 平板：列表栏加宽（摘要/标题不被过早截断），三栏比例更接近华为电子邮件平板版
    if (app.ui.tabletMode) {
      return 380
    }
    return app.ui.isDesktopMode ? 320 : 280
  }

  /**
   * 平板触摸形态：设备是平板、且当前没有检测到键鼠。
   * 只用于命中区/悬停反馈等**交互**差异，绝不用于断点或布局档位判断
   * （CodeLinter one-multi-breakpoint-check 禁止设备类型参与断点）。
   */
  private isTabletTouch(): boolean {
    return app.ui.isTabletDevice && !app.ui.pointerPrimary
  }

  // SideBarContainer 宽度：官方默认 min240/max280。
  // 电脑自由窗口：默认 260 / 可拉到 400（给中间列表与正文留足空间）；
  // 平板触摸：260/360（命中区更宽）；其余 240/280。
  private sideBarMinWidth(): number {
    return 240
  }

  private sideBarMaxWidth(): number {
    if (app.ui.usesDesktopChrome) {
      return 400
    }
    return this.isTabletTouch() ? 360 : 280
  }

  private sideBarWidthVp(): number {
    return app.ui.usesDesktopChrome ? 260 : 240
  }

  /** 顶栏高度：键鼠 44vp（紧凑）；平板触摸 52vp（命中区）；手机仍走 MobileShell */
  private appBarHeight(): number {
    return this.isTabletTouch() ? 52 : WeaverSpacing.TITLEBAR_H
  }

  /** 悬停反馈只在键鼠形态启用：触摸设备不显示 hover 高亮（无可悬停指针） */
  private barHover(): HoverEffect {
    return app.ui.pointerPrimary ? HoverEffect.Highlight : HoverEffect.None
  }

  // ===================== 结构 =====================

  build() {
    Stack() {
      // 页面光感背景（T3）：底层线性渐变 + 顶部径向光晕，只画一层、不吃点击（hitTest None）。
      // 只覆盖安全区内区域；状态栏条由窗口底色（SystemBars.applySystemBars）承托，同色无断层。
      GlowPageBackground(app.ui.themeId)

      Column() {
        Column() {
          if (this.loading) {
            this.loadingView()
          } else if (this.loadError !== '') {
            this.errorView()
          } else {
            this.mainLayout()
          }
        }
        .layoutWeight(1).width('100%')
      }
      .width('100%').height('100%')
      // 沉浸式（官方两步法）：
      //   ① setWindowLayoutFullScreen(true) 已在 EntryAbility 开启；
      //   ② 这里用 expandSafeArea 让**背景**铺满状态栏/导航条区域，内容再按避让区推开。
      // 底部必须一起避让：官方 FAQ 明确 SafeAreaType.SYSTEM **不含**底部导航栏，
      // 底部高度来自 TYPE_NAVIGATION_INDICATOR；只避让顶部会让列表末行/正文末行
      // 伸到手势条下方，且那片区域的点击优先被系统拦截。
      // 顶部：电脑模式取 0（标题栏已占位，见 topInset 注释）；手机/平板取 safeTop
      // 键盘弹出时内容整体抬高：取 max(导航条, 键盘)，键盘通常已覆盖导航条区域
      .padding({ top: this.topInset(), bottom: Math.max(this.safeBottom, this.keyboardHeight) })
      // 背景交给下面的 GlowPageBackground 光感层，本容器必须透明（否则会把光感整块盖住）。
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (app.ui.dialog !== ShellDialog.NONE) {
        this.dialogView()
      }
    }
    .width('100%').height('100%')
    // 光感背景要盖住状态栏/导航条区域；否则这两条会露出系统/窗口底色（平板实测黑边）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 设置：居中的半模态面板（对齐电子邮件），不是从右侧推一个页面
    .bindSheet(this.showSettings, this.settingsSheet(), {
      preferType: SheetType.CENTER,
      // Pura X View 等短屏（744vp）用 MEDIUM，避免半模态被截断
      height: this.appShortScreen() ? SheetSize.MEDIUM : SheetSize.LARGE,
      showClose: true,
      dragBar: false,
      // 面板背景用次级面（浅灰/深灰），分组卡片才是高一级的 bgCard —— 和电子邮件一致
      backgroundColor: this.colors().bgSurface,
      title: { title: '设置' },
      onWillDismiss: (action: DismissSheetAction) => {
        action.dismiss()
        this.showSettings = false
      }
    })
    // 输入形态探测：鼠标进入窗口才触发（触摸设备不派发 hover），
    // 第一次 hover 即把平板/电脑模式升级为键鼠优先（hover 高亮、光标、快捷键提示随之启用）。
    .onHover((isHover: boolean) => {
      if (isHover) {
        deviceProfile.notePointerActivity()
      }
    })
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
      // 断点分发：lg 及以上三栏；sm/md 走手机端外壳。
      // 电脑模式：统一窗口头（DesktopTitleBar）已包含应用级动作，这里不再叠一条 appBar。
      // 平板宽屏：保留触摸友好的 appBar（无窗口三键）。
      // 沉浸编辑：窗口内只保留正文（桌面保留窗口头，手机/平板由编辑区浮动按钮退出）。
      if (app.ui.immersiveEditing) {
        FocusWorkspace({ app: app })
      } else if (this.breakPoint === BreakPoint.LG) {
        // 融合布局：不再叠一条全宽 appBar；品牌在侧栏头、目录开关/更多在列表头、
        // 文稿工具在编辑区头部。平板/PC 共用同一套 pane header。
        this.wideBody()
      } else {
        MobileShell({
          onExport: () => this.openExportMenu(),
          onImport: () => this.runImport()
        })
      }
    }
    .width('100%').height('100%')
    // 专注切换时两栏在动画中收缩/放大，底色必须由外层补上，否则露出白边
    .backgroundColor(this.colors().bgPrimary)
  }

  // 宽屏（lg）：自绘可动画侧栏 —— SideBarContainer 的 showSideBar 切换是瞬时的，
  // 这里用自己的宽度/位移/透明度过渡，保持三栏结构、内容不重建。
  @Builder
  wideBody() {
    Row() {
      // 第一栏：项目/文库。内层保持固定宽度，外层宽度动画 + clip，
      // 避免侧栏文字在收缩过程中逐帧换行造成抖动。
      Column() {
        // 内层固定宽度 + 独立淡出节奏：宽度走临界阻尼弹簧，文字透明度 180ms 先行，
        // 形成“先柔和退场、再让位”的分阶段动画，避免整块一起被拖拽的僵硬感。
        Column() {
          ProjectSidebar({
            app: app,
            onCreateProject: () => app.ui.requestDialog(ShellDialog.NEW_PROJECT),
            onDeleteProject: (id: string) => this.requestDeleteProject(id),
            // 设置入口已下移到侧栏左下角：宽屏仍用居中半模态，内容与设置页共用
            onSettings: () => { this.showSettings = true }
          })
            .width(this.sideBarWidthVp())
            .height('100%')
        }
        .width(this.sideBarWidthVp())
        .height('100%')
        .opacity(app.ui.showSidebar ? 1 : 0)
        .translate({ x: app.ui.showSidebar ? 0 : -16 })
        .animation({ duration: 180, curve: Motion.standardCurve,
          delay: app.ui.showSidebar ? 40 : 0 })
      }
      .width(app.ui.showSidebar ? this.sideBarWidthVp() : 0)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      .enabled(app.ui.showSidebar)
      .animation({ duration: Motion.sidebar, curve: curves.springMotion(0.4, 1.0, 0) })

      // 第二/三栏：Navigation 保持原结构与状态；宽度由 Row 自动回流。
      Column() {
        Navigation(nav) {
          DocListPane({
            app: app,
            showHeader: true,
            // 融合布局：目录开关与「更多」归列表头，窗口头不再承载应用动作
            showSidebarToggle: true,
            showMore: true,
            onExport: () => this.openExportMenu(),
            onImport: () => this.runImport(),
            enableLongTake: true,
            onOpenDoc: (id: string) => this.openDoc(id),
            onRenameDoc: (id: string, current: string) =>
              app.ui.requestDialog(ShellDialog.RENAME_DOC, id, current, '', app.project.currentBookId),
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
        // 一镜到底：只有注册了动画的 push 才走自定义转场，其余保持系统默认
        .customNavContentTransition((from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation) => {
          return ezCustomTransition.customNavContentTransition(from, to, operation, {
            onTransitionStart: () => {
              this.navInteractive = false
            },
            onTransitionEnd: () => {
              this.navInteractive = true
            }
          })
        })
        .enabled(this.navInteractive)
        .width('100%').height('100%')
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%').height('100%')
  }

  // 命名注意：不要叫 toolbar —— 它是 ArkUI 内置属性名（基类 CustomComponent 已占用），
  // 同名 @Builder 会被解析成属性设置器并报类型错误。
  // 宽屏顶栏：三形态只改"动作集合 / 命中区 / 悬停反馈"，不改断点与栏位结构。
  //   电脑（自由窗口）：撤销 / 重做 / 导出 / 导入 / 设置 全部常驻，键鼠 hover 高亮；
  //   平板（触摸为主）：撤销 / 重做已在编辑工具条（宽屏可见），顶栏只留导出 / 导入 / 设置，
  //                    命中区放大到 48vp，无 hover；
  //   手机：不使用本顶栏（走 MobileShell 的最小 chrome）。
  @Builder
  appBar() {
    Row() {
      Text('☰')
        .fontSize(16)
        .fontColor(app.ui.showSidebar ? this.colors().textPrimary : this.colors().textTertiary)
        .width(44).height(44).textAlign(TextAlign.Center)
        .accessibilityText(app.ui.showSidebar ? '收起侧栏' : '展开侧栏')
        .hoverEffect(this.barHover())
        .onClick(() => app.ui.toggleSidebar())
      Text(this.centerTitle())
        .fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.colors().textPrimary)
        .margin({ left: 8 }).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      if (app.editor.hasDoc) {
        Text(app.editor.wordCount.toString() + ' 字')
          .fontSize(11).fontColor(this.colors().textTertiary)
          .margin({ right: 8 })
        // 平板宽屏：常用工具同样上移到顶栏。
        // 这条顶栏还要放标题/字数/导出导入设置，工具组只能分到固定预算 →
        // 传 260vp，落到 L2（撤销/重做/四点更多/查找/专注），格式动作进更多菜单。
        EditorTools({ app: app, space: 260, immersive: false, historyTick: this.historyTick })
      }

      this.barAction('导出', () => this.openExportMenu())
      this.barAction('导入', () => this.runImport())
      this.barAction('设置', () => { this.showSettings = true })
    }
    .width('100%').height(this.appBarHeight())
    .padding({ left: 6, right: 10 })
    .attributeModifier(glassBarStyle(app.ui.themeId))
  }

  /** 顶栏文字动作：触摸设备用 48vp 命中区，键鼠设备用紧凑间距 + hover 高亮 */
  @Builder
  barAction(label: string, action: () => void) {
    Text(label)
      .fontSize(this.isTabletTouch() ? 15 : 13)
      .fontColor(this.colors().textSecondary)
      .padding({ left: this.isTabletTouch() ? 12 : 6, right: this.isTabletTouch() ? 12 : 6,
        top: 10, bottom: 10 })
      .margin({ left: this.isTabletTouch() ? 4 : 14 })
      .accessibilityText(label)
      .hoverEffect(this.barHover())
      .onClick(action)
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
    try {
      // 点击当下已抓好的转场参数（可能为空：宽屏常驻第三栏时不需要）
      const transition: LongTakeTransitionParam | undefined = takePendingLongTake()
      await app.openChapter(chapterId)
      if (!nav.getAllPathName().includes(Routes.WORKSPACE)) {
        if (transition !== undefined) {
          const navParam: LongTakeNavParam = { longTakeTransitionParam: transition }
          nav.pushPath({ name: Routes.WORKSPACE, param: navParam })
        } else {
          nav.pushPath({ name: Routes.WORKSPACE })
        }
      }
    } catch (e) {
      Logger.error('AppShell: openDoc failed: ' + String(e))
      this.toast('打开文稿失败，请重试')
    }
  }

  // ===================== 对话框 =====================

  private requestDeleteProject(id: string): void {
    const found: BookModel | undefined = app.project.books.find((b: BookModel) => b.id === id)
    const name: string = found !== undefined ? found.name : '该项目'
    app.ui.requestDialog(ShellDialog.DELETE_PROJECT, id, '', name)
  }

  private appShortScreen(): boolean {
    return app.ui.shortScreen
  }

  /** 设置面板内容：半模态宿主只给尺寸与标题，内容与设置页共用 */
  @Builder
  settingsSheet() {
    Column() {
      Scroll() {
        SettingsPanel()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
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
      .enabled(!this.dialogPending)
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
    if (this.dialogPending) {
      return
    }
    const kind: ShellDialog = app.ui.dialog
    const target: string = app.ui.dialogTarget
    const revision: number = app.ui.dialogRevision
    const ownerBookId: string = app.ui.dialogOwnerBookId
    if (kind === ShellDialog.RENAME_DOC && ownerBookId !== '' && ownerBookId !== app.project.currentBookId) {
      app.ui.closeDialog()
      this.toast('项目已切换，请重新选择要重命名的文稿')
      return
    }
    const trimmed: string = value.trim()
    if ((kind === ShellDialog.NEW_PROJECT || kind === ShellDialog.RENAME_DOC) && trimmed === '') {
      this.toast('请输入名称')
      return
    }

    this.dialogPending = true
    try {
      if (kind === ShellDialog.NEW_PROJECT) {
        await app.createBook(trimmed)
      } else if (kind === ShellDialog.RENAME_DOC) {
        await app.renameChapter(target, trimmed)
      } else if (kind === ShellDialog.DELETE_PROJECT) {
        await app.deleteBook(target)
      } else if (kind === ShellDialog.DELETE_DOC) {
        await app.hardDeleteChapter(target)
        this.toast('已删除')
      }
      if (app.ui.dialogRevision === revision) {
        app.ui.closeDialog()
      }
    } catch (e) {
      Logger.error('AppShell: dialog action failed: ' + String(e))
      this.toast('操作失败，请重试')
    } finally {
      this.dialogPending = false
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
      // doExport 现在会按 id 读**完整**正文（列表投影只有前缀），读库可能失败；
      // 必须接住，否则会变成未处理的 Promise 拒绝（项目自身注释：会被系统按 JS 错误杀进程）
      this.doExport(data.index).catch((e: Error) => {
        Logger.error('AppShell: export failed: ' + String(e))
        this.toast('导出失败：' + e.message)
      })
    })
  }

  private async doExport(action: ExportAction): Promise<void> {
    const bookName: string = app.project.bookName === '' ? '语流' : app.project.bookName

    if (action === ExportAction.BACKUP_JSON) {
      const payload = await app.exportBackupData()
      await ExportService.exportBackupJson(bookName, payload)
      return
    }
    let target: ExportFormat = ExportFormat.TXT
    switch (action) {
      case ExportAction.CHAPTER_MD:
      case ExportAction.BOOK_MD:
        target = ExportFormat.MD
        break
      case ExportAction.CHAPTER_HTML:
        target = ExportFormat.HTML
        break
      case ExportAction.CHAPTER_TXT:
      case ExportAction.BOOK_TXT:
        break
      default:
        return
    }
    const wholeBook: boolean = action === ExportAction.BOOK_TXT || action === ExportAction.BOOK_MD

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

    // 必须取完整文稿：project.chapters 是列表投影，正文只有前缀，
    // 直接拿它导出会让整本 TXT/MD/HTML 只剩每篇开头几百字。
    const full: ChapterModel[] = await app.loadFullChapters()
    const chapters: ExportableChapter[] = full
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

  private runImport(): void {
    // 同上：导入会读文件、写库、恢复备份，失败必须收敛到提示而不是未处理拒绝
    app.importFiles()
      .then((result: string) => {
        if (result !== '') {
          this.toast(result)
        }
      })
      .catch((e: Error) => {
        Logger.error('AppShell: import failed: ' + String(e))
        this.toast('导入失败：' + e.message)
      })
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }
}
