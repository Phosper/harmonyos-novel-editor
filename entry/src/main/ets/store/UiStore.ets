// 界面状态 —— 主题 / 断点 / 侧栏 / 中部视图 / 对话框请求
import { BookMode } from '../model/Book'
import { prefs } from '../utils/PreferenceHelper'
import { AvatarService } from '../utils/AvatarService'
import { Logger } from '../utils/Logger'
import { BreakPoint } from '../utils/BreakPoint'
import { DeviceClass, DeviceSnapshot } from '../utils/DeviceProfile'
import { applySystemBars, applySystemBarsDimmed } from '../utils/SystemBars'
import { refreshDecorColorScheme, syncDesktopDecorButtons } from '../utils/DesktopWindowChrome'
import { applyAppColorMode } from '../utils/AppChromeMode'
import { EditorViewMode, MobileTab, PAPER_THEMES, PaperTheme, DEFAULT_THEME_ID, themeById, WeaverTheme } from '../constants/DesignTokens'
import type { CanvasTextEditorController } from '../editor/flowtext/CanvasTextEditor'

/**
 * 需要用户输入或确认的对话框。
 * 放在 store 而不是层层回调：列表、素材、侧栏都要发起对话框请求，
 * 集中在这里可以让 AppShell 单点渲染、各面板直接调用，去掉长链透传。
 */
export enum ShellDialog {
  NONE = 0,
  NEW_PROJECT = 1,
  RENAME_DOC = 2,
  NEW_CHARACTER = 3,
  NEW_WORLD = 4,
  DELETE_PROJECT = 5,
  DELETE_DOC = 6
}

@ObservedV2
export class UiStore {
  /** 全局主题 id（驱动整站配色）；见 DesignTokens.THEMES */
  @Trace themeId: string = DEFAULT_THEME_ID
  /** 派生：当前主题是否深色（兼容旧调用） */
  @Trace darkMode: boolean = false
  /** 稿纸字号（编辑器正文字号/行距仍独立于主题配色） */
  @Trace paperTheme: PaperTheme = PAPER_THEMES[0]
  @Trace mode: BookMode = BookMode.PROFESSIONAL
  /** 本地账号昵称：空串 = 未登录（账号服务接入前先做本机身份，见 PreferenceHelper.getNickname） */
  @Trace nickname: string = ''
  /** 自定义头像的沙箱路径（空串 = 系统占位人像）；导入时已复制进 filesDir */
  @Trace avatarPath: string = ''
  /** 记住上次的浅色主题，退出深色时还原 */
  private lastLightThemeId: string = DEFAULT_THEME_ID

  // 断点与设备形态
  //
  // 三条正交判据（见 docs/refactor/multidevice-interaction-refactor.md §1）：
  //   布局层级 ← breakPoint（**只**由窗口宽度断点决定）；
  //   设备形态 ← deviceClass（只决定 chrome 与命中区风格）；
  //   输入形态 ← pointerPrimary（决定 hover / 右键 / 快捷键 / 焦点策略）。
  // 电脑模式判据是 freeWindowMode（window.isInFreeWindowMode()），**不是**设备类型。
  @Trace breakPoint: BreakPoint = BreakPoint.LG
  /** 设备形态归类（PHONE / TABLET / PC）：只用于 chrome 与命中区风格 */
  @Trace deviceClass: DeviceClass = DeviceClass.PHONE
  /** 自由窗口模式（PC 与平板电脑模式均为 true）—— 桌面 chrome 的唯一判据 */
  @Trace freeWindowMode: boolean = false
  /** 是否键鼠优先（modality === POINTER，仅实测到指针输入后为真）：驱动 hover / 右键 / 焦点环 / 快捷键 */
  @Trace pointerPrimary: boolean = false
  /** 软键盘遮挡高度（vp，0 = 未弹出）：页面据此让位，编辑器据此把光标滚进可视区 */
  @Trace keyboardHeight: number = 0
  /** 折叠屏是否处于展开/半折叠（平板级可视面积）；与 deviceClass 一起决定 tabletMode */
  @Trace foldExpanded: boolean = false
  /** 短屏设备（Pura X View 744vp 等）：chrome 更紧凑 */
  @Trace shortScreen: boolean = false
  /** 屏幕最大圆角（vp）：贴边控件让位用 */
  @Trace cornerRadius: number = 0
  /** 阔直板（Pura X View 类）：横竖屏都用更紧凑的 chrome */
  @Trace wideBar: boolean = false

  /** 贴边安全间距：大圆角设备（Pura X View）左右至少留 16–28vp，避免被圆角裁切 */
  get cornerInset(): number {
    return Math.max(16, Math.min(this.cornerRadius, 28))
  }
  /** 兼容旧调用：等价于 deviceClass === PC（不再参与布局判断） */
  @Trace isPcDevice: boolean = false
  /** 原生三键区宽度（vp，来自 getTitleButtonRect；0 表示未测到）——顶栏右侧避让用 */
  @Trace titleButtonWidthVp: number = 0

  // 第一栏（侧栏）显隐
  @Trace showSidebar: boolean = true

  // 手机端（sm）底部页签当前选中板块；md/lg 下仍作为内容分段的选中来源
  @Trace mobileTab: MobileTab = MobileTab.DOCS

  // 专注模式：手机端输入时隐藏顶栏与快捷条，停顿片刻后自动恢复
  @Trace immersive: boolean = false
  private immersiveTimer: number = -1

  /** 输入事件：进入专注（隐藏 chrome），并重置"停顿恢复"计时 */
  noteTyping(): void {
    if (this.isWide) {
      return
    }
    this.immersive = true
    if (this.immersiveTimer !== -1) {
      clearTimeout(this.immersiveTimer)
    }
    this.immersiveTimer = setTimeout(() => {
      this.immersiveTimer = -1
      this.immersive = false
    }, 3500)
  }

  // 打字机模式：仅当前段保持正文色，其余段落淡化（默认关闭，仅手机端菜单可切）
  @Trace typewriter: boolean = false

  /**
   * 沉浸编辑：编辑区在**应用窗口内**铺满，隐藏侧栏/列表/顶栏工具等非必要元素。
   * 注意这不是系统全屏（不调用窗口 fullscreen），退出后恢复原布局。
   */
  @Trace immersiveEditing: boolean = false
  /** 顶栏「查找」请求计数：EditorPane 监听后打开查找面板 */
  @Trace findRequestTick: number = 0
  /** 选区/格式状态版本号：顶栏 B/I/H 态按它刷新（不携带具体坐标） */
  @Trace selectionTick: number = 0
  /**
   * 当前编辑器控制器（顶栏/工具条共用）。
   * 由 EditorPane 在 onControllerReady 时注入；未打开文稿时为 null。
   */
  editorController: CanvasTextEditorController | null = null

  toggleImmersiveEditing(): void {
    this.immersiveEditing = !this.immersiveEditing
  }

  exitImmersiveEditing(): void {
    if (this.immersiveEditing) {
      this.immersiveEditing = false
    }
  }

  requestFind(): void {
    this.findRequestTick++
  }

  /** 显式设置打字机模式（控制器/按钮统一走这里，避免只写不读） */
  setTypewriter(on: boolean): void {
    if (this.typewriter !== on) {
      this.typewriter = on
    }
  }

  toggleTypewriter(): void {
    this.setTypewriter(!this.typewriter)
  }

  /**
   * 编辑器滚动状态（T033）：向下滚动隐藏顶栏/工具条（沉浸），向上滚动恢复。
   * state：1 向下 / -1 向上 / 0 停止。宽屏不参与。
   */
  noteScroll(state: number): void {
    if (this.isWide) {
      return
    }
    if (state > 0) {
      this.immersive = true
    } else if (state < 0) {
      this.immersive = false
    }
  }

  // 工作区视图（文稿 / 素材 / 关系图）；EMPTY 表示尚未打开任何文稿
  @Trace view: EditorViewMode = EditorViewMode.EMPTY

  // 对话框请求
  @Trace dialog: ShellDialog = ShellDialog.NONE
  @Trace dialogTarget: string = ''
  @Trace dialogInitial: string = ''
  @Trace dialogSubject: string = ''
  /** 弹框归属与代次，防止迟到写入影响后来选择的项目和弹框。 */
  @Trace dialogOwnerBookId: string = ''
  @Trace dialogRevision: number = 0

  get isNarrow(): boolean {
    return this.breakPoint === BreakPoint.SM
  }

  /** 手机竖屏档（窄屏）：单列 + 底部页签 */
  get isMobile(): boolean {
    return this.breakPoint === BreakPoint.SM
  }

  /** 中等宽度档：侧栏 + 内容双栏 */
  get isMedium(): boolean {
    return this.breakPoint === BreakPoint.MD
  }

  /** 宽屏档：现有三栏（保持不变） */
  get isWide(): boolean {
    return this.breakPoint === BreakPoint.LG
  }

  /**
   * 是否电脑形态（含平板电脑模式：自由窗口即桌面交互）。
   * 只影响 chrome / 交互风格，**不**参与断点与布局层级判断。
   */
  get isDesktopMode(): boolean {
    return this.deviceClass === DeviceClass.PC || this.freeWindowMode
  }

  /** 是否平板（触摸为主、可用键鼠：命中区 ≥48vp，侧栏抽屉可用） */
  get isTabletDevice(): boolean {
    return this.deviceClass === DeviceClass.TABLET
  }

  /**
   * 是否"平板形态"：平板设备，且**不是** MatePad Edge 电脑模式 / PC 自由窗口。
   * 用于区分电脑与平板两套 chrome：电脑 = 方形状态底 + 紧凑字号；
   * 平板 = 圆形状态底 + 放大字号/热区。
   */
  get tabletMode(): boolean {
    // 折叠屏展开/半折叠的可视面积是平板级；折叠屏在 deviceType 上常被报成 phone，不能只用 deviceClass
    const tabletLike: boolean = this.deviceClass === DeviceClass.TABLET || this.foldExpanded
    return tabletLike && !this.freeWindowMode
  }

  /** 是否走桌面沉浸标题栏：只由自由窗口模式决定（平板电脑模式同样走桌面 chrome） */
  get usesDesktopChrome(): boolean {
    return this.freeWindowMode
  }

  /** 兼容旧调用：语义改为「电脑形态 且 宽屏档」 */
  get isPc(): boolean {
    return this.isDesktopMode && this.isWide
  }

  /**
   * 用一份设备快照整体刷新设备相关状态（AppShell 订阅 DeviceProfile 后调用）。
   * 断点也由快照给出，保证 store 与 AppShell 的 @Local 永远同一份真相。
   */
  /** 软键盘高度写入（去重，避免每帧刷新） */
  setKeyboardHeight(height: number): void {
    if (Math.abs(this.keyboardHeight - height) > 0.5) {
      this.keyboardHeight = height
    }
  }

  applyDeviceSnapshot(snapshot: DeviceSnapshot): void {
    if (this.deviceClass !== snapshot.deviceClass) {
      this.deviceClass = snapshot.deviceClass
      this.isPcDevice = snapshot.deviceClass === DeviceClass.PC
    }
    if (this.freeWindowMode !== snapshot.freeWindow) {
      this.freeWindowMode = snapshot.freeWindow
    }
    if (this.pointerPrimary !== snapshot.pointerPrimary) {
      this.pointerPrimary = snapshot.pointerPrimary
    }
    if (this.breakPoint !== snapshot.breakPoint) {
      this.breakPoint = snapshot.breakPoint
    }
    if (this.titleButtonWidthVp !== snapshot.titleButtonWidthVp) {
      this.titleButtonWidthVp = snapshot.titleButtonWidthVp
    }
    this.setKeyboardHeight(snapshot.keyboardHeightVp)
    this.shortScreen = snapshot.shortScreen
    this.cornerRadius = snapshot.cornerRadiusVp
    this.wideBar = snapshot.wideBar
    if (this.foldExpanded !== snapshot.foldExpanded) {
      this.foldExpanded = snapshot.foldExpanded
    }
  }

  /**
   * 顶栏/工具行右侧需要避让的宽度（vp）。
   *
   * 原生三键由系统绘制在窗口右上角，**压在页面内容之上**。原先写死 148vp 只够
   * 3×48vp 的理论宽度，实际三键区（含系统内边距）更宽，最右侧的「专注」图标
   * 会被最大化按钮盖掉一半（用户实测截图）。这里改为「实测三键宽 + 24vp 呼吸」，
   * 测不到时退回 144 + 24，宁可多留白也不让图标被压住。
   */
  get captionInset(): number {
    if (!this.freeWindowMode) {
      return 0
    }
    // 下限 168：实测宽度可能只算按钮本身（不含系统内边距），偏小时反而比旧值更窄
    const measured: number = this.titleButtonWidthVp > 0 ? this.titleButtonWidthVp : 144
    return Math.max(measured + 24, 168)
  }

  // ===== 对话框 =====

  requestDialog(kind: ShellDialog, target: string = '', initial: string = '',
    subject: string = '', ownerBookId: string = ''): void {
    this.dialogRevision++
    this.dialogOwnerBookId = ownerBookId
    this.dialogTarget = target
    this.dialogInitial = initial
    this.dialogSubject = subject
    this.dialog = kind
  }

  closeDialog(): void {
    this.dialogRevision++
    this.dialogOwnerBookId = ''
    this.dialog = ShellDialog.NONE
    this.dialogTarget = ''
    this.dialogInitial = ''
    this.dialogSubject = ''
  }

  // ===== 主题 =====

  /** 当前全局主题 */
  get theme(): WeaverTheme {
    return themeById(this.themeId)
  }

  /** 按**实际主题**明暗同步系统栏（底色=页面底色，前景随明暗；勿用 darkMode）。
   *  蒙层展示期间（overlayDim）状态栏底色切为"底色×蒙层"压暗色，保持与页面一致。 */
  syncSystemBars(): void {
    const t: WeaverTheme = themeById(this.themeId)
    if (this.overlayDim) {
      applySystemBarsDimmed(t.dark, t.colors.bgPrimary)
    } else {
      applySystemBars(t.dark, t.colors.bgPrimary)
    }
    // 原生三键颜色跟随**实际主题**（不再依赖 DesktopTitleBar 挂载）：
    // 浅色稿纸下必须是深色图标，深色主题下才是白色图标。
    syncDesktopDecorButtons(t.dark)
  }

  /** 是否有"盖不到状态栏条的蒙层"在展示（抽屉）：状态栏需同步压暗/还原。
   *  bindSheet / InputDialog 的蒙层覆盖全窗，透明状态栏下自然同步压暗，无需此开关。 */
  overlayDim: boolean = false

  setOverlayDim(on: boolean): void {
    if (this.overlayDim === on) {
      return
    }
    this.overlayDim = on
    this.syncSystemBars()
  }

  /** 选择全局主题（持久化）；同时派生 darkMode（编辑器稿纸随之联动） */
  async setTheme(id: string): Promise<void> {
    this.themeId = id
    this.darkMode = themeById(id).dark
    if (!this.darkMode) {
      this.lastLightThemeId = id
    }
    // 系统 chrome（窗口三键、系统菜单/对话框）跟随应用主题，而不是系统深浅
    applyAppColorMode(this.darkMode)
    this.syncSystemBars()
    // 明暗变了：让系统按新的 colorMode 重建三键（仅桌面窗口）
    if (this.freeWindowMode) {
      refreshDecorColorScheme(this.darkMode)
    }
    await prefs.setThemeId(id)
  }

  /** 兼容旧入口：切换深/浅（在"夜读"与上次浅色主题间切换并持久化） */
  async setDarkMode(on: boolean): Promise<void> {
    await this.setTheme(on ? 'dark' : this.lastLightThemeId)
    await prefs.setDarkMode(on)
  }

  /**
   * 跟随系统深浅色：只改内存，不做"用户已显式选择"标记（EntryAbility 调用）。
   */
  async applySystemDarkMode(on: boolean): Promise<void> {
    if (this.darkMode === on) {
      return
    }
    await this.setTheme(on ? 'dark' : this.lastLightThemeId)
  }

  /** 稿纸字号（编辑器正文字号/行距，独立于主题配色） */
  async setPaperTheme(theme: PaperTheme): Promise<void> {
    this.paperTheme = theme
    await prefs.setPaperTheme(theme.id)
  }

  /**
   * 写作模式已统一：入口不再让用户选「专业 / 普通」。
   * 此方法保留为唯一的模式写入口（备份恢复、内部初始化会调用），
   * 但固定落到专业版 —— 素材、世界观、关系图等能力一律开放。
   */
  async setMode(_mode: BookMode): Promise<void> {
    this.mode = BookMode.PROFESSIONAL
    await prefs.setMode(this.mode)
  }

  // ===== 账号（本机身份） =====

  /**
   * 是否已登录。
   * 只是昵称非空的派生判断 —— 不要另存一个 loggedIn 布尔量，两份真相会不一致。
   */
  isLoggedIn(): boolean {
    return this.nickname !== ''
  }

  /** 登录：昵称写内存 + 首选项；空昵称视为取消，不写入 */
  async signIn(name: string): Promise<void> {
    const trimmed: string = name.trim()
    if (trimmed === '') {
      return
    }
    this.nickname = trimmed
    await prefs.setNickname(trimmed)
    Logger.info('UiStore: signIn nickname=' + trimmed)
  }

  async signOut(): Promise<void> {
    // 只清身份，不删头像文件：重新登录同一昵称时头像还在；文件在换头像/移除时清理
    this.nickname = ''
    await prefs.setNickname('')
    Logger.info('UiStore: signOut')
  }

  /** 设置自定义头像（调用方负责把图片复制进沙箱后传绝对路径） */
  async setAvatar(path: string): Promise<void> {
    this.avatarPath = path
    await prefs.setAvatarPath(path)
    Logger.info('UiStore: avatar updated')
  }

  async removeAvatar(): Promise<void> {
    this.avatarPath = ''
    await prefs.setAvatarPath('')
    Logger.info('UiStore: avatar removed')
  }

  // ===== 侧栏 =====

  toggleSidebar(): void {
    this.showSidebar = !this.showSidebar
  }

  async loadFromPrefs(): Promise<void> {
    // 主题：优先读全局主题 id；旧数据无该键时按"是否显式选过深色"回退
    let themeId: string = await prefs.getThemeId()
    if (themeId === '') {
      const explicit: boolean = await prefs.isDarkExplicit()
      const dark: boolean = explicit ? await prefs.getDarkMode() : this.darkMode
      themeId = dark ? 'dark' : DEFAULT_THEME_ID
    }
    this.themeId = themeId
    this.darkMode = themeById(themeId).dark
    // 首帧前就把系统 chrome 的对齐关系定下来，避免启动瞬间白三键/深色菜单
    applyAppColorMode(this.darkMode)
    if (!this.darkMode) {
      this.lastLightThemeId = themeId
    }
    this.mode = await prefs.getMode()
    this.nickname = await prefs.getNickname()
    this.avatarPath = await prefs.getAvatarPath()
    // 沙箱文件被系统清掉（清理缓存/换机恢复）时不要把死路径留在界面上
    if (this.avatarPath !== '' && !AvatarService.exists(this.avatarPath)) {
      this.avatarPath = ''
      await prefs.setAvatarPath('')
    }
    const paperId: string = await prefs.getPaperTheme()
    const found: PaperTheme | undefined = PAPER_THEMES.find((p: PaperTheme) => p.id === paperId)
    this.paperTheme = found !== undefined ? found : PAPER_THEMES[0]
    Logger.info('UiStore: prefs loaded (theme=' + this.themeId + ', dark=' + this.darkMode +
      ', mode=' + this.mode + ')')
  }
}
