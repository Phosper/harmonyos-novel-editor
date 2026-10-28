// 桌面沉浸标题栏（统一窗口头）
//
// 设计目标（2026-10-18 UI 重构）：
//   1. **单一标题来源**：窗口头只出现一次"书名 · 章节"，其它栏不再重复标题；
//   2. 信息分层：左侧"应用导航（侧栏开关）+ 标题"，右侧"应用级动作 + 窗口三键"，
//      文档级动作（撤销/重做/格式/打字机）全部下沉到编辑器工具条；
//   3. 交互统一：所有可点项 44vp 高、hover 高亮、键盘可聚焦、有两态反馈；
//   4. 视觉统一：玻璃材质（沉浸光感）+ 统一字号/间距/颜色令牌。
//
// 窗口拖动只能在 onTouch 的 TouchType.Down 回调里调 startMoving()（官方限制），
// onMouse(Press, Left) 只做鼠标兜底；禁止用 moveWindowTo（不跟手，官方不建议）。
import { promptAction, window } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { Logger } from '../utils/Logger'
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import {
  DESKTOP_CHROME_HEIGHT_VP,
  configureImmersiveDesktopChrome,
  readTitleButtonWidthVp,
  isMaximizedStatus
} from '../utils/DesktopWindowChrome'
import { deviceProfile, DeviceSnapshot } from '../utils/DeviceProfile'
import { BreakPoint } from '../utils/BreakPoint'
import { SaveState } from '../store/StoreModels'
import { exitFocusAnimated } from './FocusTransition'
import { ExportService } from '../utils/ExportService'
import type { AppStores } from '../store/AppStores'
import type { EditorDraftSnapshot } from '../store/EditorStore'

/** 书名尚未加载时的标题兜底 */
const TITLE_FALLBACK: string = '语流'
/** 标题区最大宽度：留出动作与三键的空间，超长省略 */
const TITLE_MAX_WIDTH: number = 340

/**
 * 自绘沉浸标题栏。
 *
 * 结构：[☰ 侧栏] [书名 · 章节] [可拖拽空白] [导出] [导入] [设置] | [—] [□] [✕]
 */
@ComponentV2
export struct DesktopTitleBar {
  @Param app: AppStores | null = null
  /** 顶部安全区（状态栏）高度 vp：由 AppShell 从 DeviceSnapshot.safeTopVp 传入 */
  @Param safeTop: number = 0
  /** 标题栏总高度（含安全区）vp：由 DeviceSnapshot.chromeHeightVp 传入，0 时按常量兜底 */
  @Param chromeHeight: number = 0
  /** 应用级动作由 AppShell 注入（导出/导入逻辑仍归 AppShell 持有） */
  @Event onExport: () => void = () => {}
  @Event onImport: () => void = () => {}

  /** 当前窗口状态（决定"最大化"还是"还原"图标） */
  @Local windowStatus: number = 0
  /** 原生三键区宽度（vp）：自绘三键需右避让，避免压住系统仍保留的三键 */
  @Local titleButtonWidth: number = 0
  /** 顶栏实测宽度（vp）：用于判断是否折叠工具组（断点只看窗口，顶栏还要看自身可用宽） */
  @Local headerWidth: number = 1200

  private statusListener: ((status: window.WindowStatusType) => void) | null = null
  private rectListener: ((rect: window.TitleButtonRect) => void) | null = null
  private profileDisposer: (() => void) | null = null
  private boundWindow: window.Window | undefined = undefined

  aboutToAppear(): void {
    // 1) 先把窗口侧配置做实（原生装饰栏高度/三键样式/隐藏原生标题），再读状态
    this.applyChrome()
    this.windowStatus = this.readStatus()
    this.refreshTitleButtonRect()
    // 2) windowStatusChange / windowTitleButtonRectChange 由本组件监听
    this.bindWindowListeners()
    // 3) avoidAreaChange 等由 DeviceProfile 统一注册，这里只订阅结果
    this.profileDisposer = deviceProfile.onChange((snap: DeviceSnapshot): void => {
      if (snap.windowStatus !== this.windowStatus) {
        this.windowStatus = snap.windowStatus
      }
      this.refreshTitleButtonRect()
    })
  }

  /** 主题切换时同步原生三键的图标配色（深色主题给 DARK，浅色主题给 LIGHT） */
  @Monitor('app.ui.themeId')
  onThemeIdChanged(): void {
    this.applyChrome()
  }

  aboutToDisappear(): void {
    if (this.profileDisposer !== null) {
      this.profileDisposer()
      this.profileDisposer = null
    }
    this.unbindWindowListeners()
  }

  // ===================== 窗口 =====================

  private win(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  /** 重配原生装饰栏：尺寸 + 三键样式 + 隐藏原生标题/三键 + 保留 Dock */
  private applyChrome(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      configureImmersiveDesktopChrome(w, this.app !== null && this.app.ui.darkMode)
    } catch (e) {
      Logger.warn('DesktopTitleBar: configure chrome failed: ' + String(e))
    }
  }

  private readStatus(): number {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return this.windowStatus
    }
    try {
      return w.getWindowStatus()
    } catch (e) {
      Logger.warn('DesktopTitleBar: getWindowStatus failed: ' + String(e))
      return this.windowStatus
    }
  }

  private refreshTitleButtonRect(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    const width: number = readTitleButtonWidthVp(w)
    // 只在真的变了才写 @Local：避让区变化会连续回调，无意义赋值会整栏重绘
    if (width !== this.titleButtonWidth) {
      this.titleButtonWidth = width
    }
  }

  private bindWindowListeners(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    this.boundWindow = w
    const status: (newStatus: window.WindowStatusType) => void = (newStatus: window.WindowStatusType): void => {
      if (this.boundWindow !== w) { return }
      this.windowStatus = newStatus
      this.applyChrome()
      deviceProfile.refresh()
    }
    this.statusListener = status
    try {
      w.on('windowStatusChange', status)
    } catch (e) {
      Logger.warn('DesktopTitleBar: on windowStatusChange failed: ' + String(e))
    }

    const rect: (newRect: window.TitleButtonRect) => void = (newRect: window.TitleButtonRect): void => {
      if (this.boundWindow !== w) { return }
      this.refreshTitleButtonRect()
    }
    this.rectListener = rect
    try {
      w.on('windowTitleButtonRectChange', rect)
    } catch (e) {
      Logger.warn('DesktopTitleBar: on windowTitleButtonRectChange failed: ' + String(e))
    }
  }

  private unbindWindowListeners(): void {
    const w: window.Window | undefined = this.boundWindow
    const statusCb: ((status: window.WindowStatusType) => void) | null = this.statusListener
    const rectCb: ((rect: window.TitleButtonRect) => void) | null = this.rectListener
    if (w !== undefined) {
      if (statusCb !== null) {
        try {
          w.off('windowStatusChange', statusCb)
        } catch (e) {
          Logger.warn('DesktopTitleBar: off windowStatusChange failed: ' + String(e))
        }
      }
      if (rectCb !== null) {
        try {
          w.off('windowTitleButtonRectChange', rectCb)
        } catch (e) {
          Logger.warn('DesktopTitleBar: off windowTitleButtonRectChange failed: ' + String(e))
        }
      }
    }
    this.statusListener = null
    this.rectListener = null
    this.boundWindow = undefined
  }

  // ===================== 三键 =====================

  private startMove(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.startMoving().catch((e: Error) => {
        Logger.warn('startMoving failed: ' + String(e))
      })
    } catch (e) {
      Logger.warn('startMoving failed: ' + String(e))
    }
  }

  private minimize(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      w.minimize().catch((e: Error) => {
        Logger.warn('minimize failed: ' + String(e))
      })
    } catch (e) {
      Logger.warn('minimize failed: ' + String(e))
    }
  }

  private toggleMaximize(): void {
    const w: window.Window | undefined = this.win()
    if (w === undefined) {
      return
    }
    try {
      const status: window.WindowStatusType = w.getWindowStatus()
      if (isMaximizedStatus(status)) {
        w.recover().then(() => {
          this.applyChrome()
        }).catch((e: Error) => {
          Logger.warn('recover failed: ' + String(e))
        })
      } else {
        w.maximize().then(() => {
          this.applyChrome()
        }).catch((e: Error) => {
          Logger.warn('maximize failed: ' + String(e))
        })
      }
    } catch (e) {
      Logger.warn('toggleMaximize failed: ' + String(e))
    }
  }

  /**
   * 关闭：先把内存草稿落库（app.flushAll），再终结 UIAbility。
   * 顺序不能反 —— terminateSelf 之后进程内状态可能已被回收，落库会丢。
   */
  private close(): void {
    const host: common.UIAbilityContext | undefined = this.hostContext()
    const stores: AppStores | null = this.app
    if (stores === null) {
      this.terminate(host)
      return
    }
    // 关闭窗口必须确认所有草稿真正落库：flushAll 会吞掉单篇失败，不能用它判断结果。
    stores.flushAllStrict()
      .then(() => {
        this.terminate(host)
      })
      .catch((e: Error) => {
        Logger.warn('DesktopTitleBar: flushAllStrict failed before close: ' + String(e))
        this.showCloseBlockedDialog(stores, host)
      })
  }

  /**
   * 保存失败时**不关窗**，给出可执行动作：重试保存 / 导出草稿 / 放弃并退出。
   * 放弃是唯一会丢内存草稿的显式选择；点遮罩/返回则继续编辑。
   */
  private showCloseBlockedDialog(stores: AppStores, host: common.UIAbilityContext | undefined): void {
    const retry: promptAction.Button = { text: '重试保存', color: this.colors().brand }
    const exportDraft: promptAction.Button = { text: '导出草稿', color: this.colors().textPrimary }
    const discard: promptAction.Button = { text: '放弃并退出', color: this.colors().danger }
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '尚有未保存内容',
        message: '保存到本地数据库失败，窗口已保持打开。可重试保存，先导出草稿，或明确放弃本次修改。',
        buttons: [retry, exportDraft, discard]
      }).then((res) => {
        if (res.index === 0) {
          this.close()
        } else if (res.index === 1) {
          this.exportDraftsBeforeClose(stores)
        } else if (res.index === 2) {
          this.terminate(host)
        }
      }).catch((e: Error) => {
        Logger.warn('close-blocked dialog failed: ' + String(e))
      })
    } catch (e) {
      Logger.warn('close-blocked dialog unavailable: ' + String(e))
      try {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败，窗口保持打开；请稍后重试' })
      } catch (e2) {
        Logger.warn('close-blocked toast failed: ' + String(e2))
      }
    }
  }

  /** 导出当前内存草稿为 JSON 文件（数据库不可用时的最后一道人工备份）。 */
  private exportDraftsBeforeClose(stores: AppStores): void {
    try {
      const drafts: EditorDraftSnapshot[] = stores.editor.snapshotDrafts()
      const payload: string = JSON.stringify({
        exportedAt: new Date().toISOString(),
        reason: 'close-blocked-unsaved',
        drafts: drafts
      }, null, 2)
      const name: string = '语流-未保存草稿-' + Date.now().toString() + '.json'
      ExportService.saveText(name, payload)
        .then((ok: boolean) => {
          if (ok) {
            this.getUIContext().getPromptAction().showToast({ message: '草稿已导出，可重试保存后再关闭' })
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '导出取消或失败，草稿仍在窗口中' })
          }
        })
        .catch((e: Error) => {
          Logger.warn('export drafts failed: ' + String(e))
        })
    } catch (e) {
      Logger.warn('export drafts unavailable: ' + String(e))
    }
  }

  private hostContext(): common.UIAbilityContext | undefined {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext
    } catch (e) {
      Logger.warn('DesktopTitleBar: getHostContext failed: ' + String(e))
      return undefined
    }
  }

  private terminate(host: common.UIAbilityContext | undefined): void {
    if (host === undefined) {
      return
    }
    try {
      host.terminateSelf().catch((e: BusinessError) => {
        Logger.warn('terminateSelf failed: ' + JSON.stringify(e))
      })
    } catch (e) {
      Logger.warn('terminateSelf failed: ' + String(e))
    }
  }

  private onTitleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      // 官方限制：startMoving 只能在 TouchType.Down 回调内调用
      this.startMove()
    }
  }

  private onTitleMouse(event: MouseEvent): void {
    if (event.action === MouseAction.Press && event.button === MouseButton.Left) {
      // 键鼠兜底：首次鼠标按下即把输入形态校正为键鼠优先（hover / 焦点环随之启用）
      deviceProfile.notePointerActivity()
      this.startMove()
    }
  }

  // ===================== 展示 =====================

  private themeId(): string {
    const stores: AppStores | null = this.app
    return stores !== null ? stores.ui.themeId : DEFAULT_THEME_ID
  }

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId())
  }

  private barHeight(): number {
    return this.chromeHeight > 0 ? this.chromeHeight : DESKTOP_CHROME_HEIGHT_VP + this.safeTop
  }

  /** 书名（标题栏主标题）；保留 barTitle 名称以兼容既有窗口回归 */
  private barTitle(): string {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return TITLE_FALLBACK
    }
    const name: string = stores.project.bookName
    return name.trim() === '' ? TITLE_FALLBACK : name
  }

  /** 章节副标题：仅在有打开文稿且标题非空时显示（信息分层，不做无意义占位） */
  private chapterTitle(): string {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return ''
    }
    return stores.editor.title.trim()
  }

  private maximized(): boolean {
    return isMaximizedStatus(this.windowStatus)
  }

  private maxGlyph(): string {
    return this.maximized() ? '❐' : '□'
  }

  private maxLabel(): string {
    return this.maximized() ? '还原' : '最大化'
  }

  private toggleSidebar(): void {
    const stores: AppStores | null = this.app
    if (stores !== null) {
      stores.ui.toggleSidebar()
    }
  }

  private titleMaxWidth(): number {
    return this.compactTools() ? 170 : TITLE_MAX_WIDTH
  }

  private openMoreMenu(): void {
    const menuColor: string = this.colors().textPrimary
    const b1: promptAction.Button = { text: '导出', color: menuColor }
    const b2: promptAction.Button = { text: '导入', color: menuColor }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '应用',
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

  /** 是否折叠工具组：非 lg 断点或顶栏自身过窄时折叠，避免标题被工具挤掉 */
  private compactTools(): boolean {
    return this.app !== null && (this.app.ui.breakPoint !== BreakPoint.LG || this.headerWidth < 1080)
  }

  private hasDoc(): boolean {
    return this.app !== null && this.app.editor.hasDoc
  }

  private isImmersive(): boolean {
    return this.app !== null && this.app.ui.immersiveEditing
  }

  /** 保存状态文案（与编辑器工具条口径一致） */
  private saveStateText(): string {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return ''
    }
    if (stores.editor.saveState === SaveState.SAVING) {
      return '保存中…'
    }
    if (stores.editor.saveState === SaveState.TOO_LARGE) {
      return '未保存（超长）'
    }
    if (stores.editor.saveState === SaveState.FAILED) {
      return '保存失败'
    }
    return stores.editor.dirtyCount > 0 ? '编辑中…' : '已保存'
  }

  /** 副标题：章节 · 字数 · 保存状态（信息集中在窗口头一处，列表/工具栏不再重复） */
  private subtitle(): string {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return ''
    }
    const parts: string[] = []
    const chapter: string = stores.editor.title.trim()
    if (chapter !== '') {
      parts.push(chapter)
    }
    parts.push(stores.editor.wordCount.toString() + ' 字')
    parts.push(this.saveStateText())
    return parts.join(' · ')
  }

  private onStatusClick(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    if (stores.editor.saveState === SaveState.TOO_LARGE) {
      this.getUIContext().getPromptAction().showDialog({
        title: '正文过长，无法保存',
        message: stores.editor.saveHint,
        buttons: [{ text: '知道了', color: this.colors().textPrimary }]
      })
      return
    }
    stores.editor.retrySave()
  }

  private exitImmersive(): void {
    if (this.app !== null) {
      exitFocusAnimated(this.getUIContext())
    }
  }

  build() {
    // 透明窗口条：只承载窗口拖动与双击最大化，**不再绘制背景、分隔线、品牌或动作**。
    // 品牌在侧栏头部，文稿标题在正文内，目录开关在列表头部；视觉上与内容融为一体。
    Row() {
    }
    .width('100%')
    .height(this.barHeight())
    .padding({ top: this.safeTop, right: this.titleButtonWidth })
    .backgroundColor(Color.Transparent)
    .onTouch((event: TouchEvent) => this.onTitleTouch(event))
    .onMouse((event: MouseEvent) => this.onTitleMouse(event))
    .gesture(TapGesture({ count: 2 }).onAction(() => {
      this.toggleMaximize()
    }))
  }


}
