// 界面状态 —— 主题 / 断点 / 侧栏 / 中部视图 / 对话框请求
import { BookMode } from '../model/Book'
import { prefs } from '../utils/PreferenceHelper'
import { Logger } from '../utils/Logger'
import { BreakPoint } from '../utils/BreakPoint'
import { DeviceClass, DeviceSnapshot } from '../utils/DeviceProfile'
import { applySystemBars, applySystemBarsDimmed } from '../utils/SystemBars'
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
  /** 兼容旧调用：等价于 deviceClass === PC（不再参与布局判断） */
  @Trace isPcDevice: boolean = false

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
  }

  // ===== 对话框 =====

  requestDialog(kind: ShellDialog, target: string = '', initial: string = '',
    subject: string = ''): void {
    this.dialogTarget = target
    this.dialogInitial = initial
    this.dialogSubject = subject
    this.dialog = kind
  }

  closeDialog(): void {
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
    this.syncSystemBars()
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
    if (!this.darkMode) {
      this.lastLightThemeId = themeId
    }
    this.mode = await prefs.getMode()
    const paperId: string = await prefs.getPaperTheme()
    const found: PaperTheme | undefined = PAPER_THEMES.find((p: PaperTheme) => p.id === paperId)
    this.paperTheme = found !== undefined ? found : PAPER_THEMES[0]
    Logger.info('UiStore: prefs loaded (theme=' + this.themeId + ', dark=' + this.darkMode +
      ', mode=' + this.mode + ')')
  }
}
