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
import { glassBarStyle } from './MaterialSurface'
import { nav, Routes } from './Navigator'
import { EditorTools } from './EditorTools'
import { SaveState } from '../store/StoreModels'
import type { AppStores } from '../store/AppStores'

/** 书名尚未加载时的标题兜底 */
const TITLE_FALLBACK: string = 'Weaver'
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
    const status: (newStatus: window.WindowStatusType) => void = (newStatus: window.WindowStatusType): void => {
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
    const w: window.Window | undefined = this.win()
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
    stores.flushAll()
      .then(() => {
        this.terminate(host)
      })
      .catch((e: Error) => {
        // 落库失败也要能关窗（数据由 30 秒安全网/下次启动兜底），不能把用户困在窗口里
        Logger.warn('DesktopTitleBar: flushAll failed before close: ' + String(e))
        this.terminate(host)
      })
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

  private openSettings(): void {
    nav.pushPath({ name: Routes.SETTINGS })
  }

  private titleMaxWidth(): number {
    return this.compactTools() ? 210 : TITLE_MAX_WIDTH
  }

  private openMoreMenu(): void {
    const menuColor: string = this.colors().textPrimary
    const b1: promptAction.Button = { text: '导出', color: menuColor }
    const b2: promptAction.Button = { text: '导入', color: menuColor }
    const b3: promptAction.Button = { text: '设置', color: menuColor }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '应用',
      buttons: [b1, b2, b3]
    }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0) {
        this.onExport()
      } else if (data.index === 1) {
        this.onImport()
      } else {
        this.openSettings()
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
      this.app.ui.exitImmersiveEditing()
    }
  }

  build() {
    Column() {
      Row() {
        // ① 应用导航：侧栏开关（沉浸模式隐藏，避免误触退出专注）
        if (!this.isImmersive()) {
          Row() {
            Text('☰')
              .fontSize(16)
              .fontColor(this.app !== null && this.app.ui.showSidebar
                ? this.colors().textPrimary : this.colors().textTertiary)
          }
          .width(44)
          .height(DESKTOP_CHROME_HEIGHT_VP)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .accessibilityText(this.app !== null && this.app.ui.showSidebar ? '收起侧栏' : '展开侧栏')
          .hoverEffect(HoverEffect.Highlight)
          .focusable(true)
          .tabStop(true)
          .onClick(() => this.toggleSidebar())
        }

        // ② 标题 + 副标题（章节 · 字数 · 保存状态）：全应用唯一标题来源
        Column() {
          Text(this.barTitle())
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .accessibilityText('书名：' + this.barTitle())
          if (this.subtitle() !== '') {
            Text(this.subtitle())
              .fontSize(11)
              .fontColor(this.colors().textTertiary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 1 })
              .accessibilityText('文档状态：' + this.subtitle())
              .onClick(() => this.onStatusClick())
          }
        }
        .height(DESKTOP_CHROME_HEIGHT_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: this.titleMaxWidth() })
        .margin({ left: 4, right: 8 })

        // ③ 可拖拽空白：占满剩余宽度；双击空白区切换最大化/还原
        Row() { }
          .layoutWeight(1)
          .height('100%')
          .onTouch((event: TouchEvent) => this.onTitleTouch(event))
          .onMouse((event: MouseEvent) => this.onTitleMouse(event))
          .gesture(TapGesture({ count: 2 }).onAction(() => {
            this.toggleMaximize()
          }))

        // ④ 常用工具上移到顶栏（文档级动作集中在这里，编辑器内部不再重复一条工具条）
        if (this.hasDoc() && !this.isImmersive()) {
          EditorTools({ app: this.app, compact: this.compactTools(), immersive: false })
        }

        // ⑤ 沉浸退出 / 应用级动作；窄宽度时低频动作收进「⋯」
        if (this.isImmersive()) {
          this.headerAction('退出专注', () => this.exitImmersive())
        } else if (this.compactTools()) {
          this.headerAction('⋯', () => this.openMoreMenu())
        } else {
          this.headerAction('导出', () => this.onExport())
          this.headerAction('导入', () => this.onImport())
          this.headerAction('设置', () => this.openSettings())
        }

        // ⑥ 窗口三键由系统原生绘制（见 DesktopWindowChrome.setWindowTitleButtonVisible）。
        //    这里不再自绘字符按钮，只在右侧预留三键区宽度（getTitleButtonRect），
        //    既保留华为原生外观，也避免动作区被三键遮挡。
      }
      .width('100%')
      .height(DESKTOP_CHROME_HEIGHT_VP)
      .padding({ right: this.titleButtonWidth })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = Number(newValue.width)
        if (Math.abs(w - this.headerWidth) > 20) {
          this.headerWidth = w
        }
      })
    }
    .width('100%')
    // 总高 = 48 + safeTop：safeTop 由标题栏自己吸纳，AppShell 不再额外加顶部 padding
    .height(this.barHeight())
    .padding({ top: this.safeTop })
    // 沉浸材质背景：模糊 + 渐变 + 下沿 1px 高光（T3 MaterialSurface，自动降级）
    .attributeModifier(glassBarStyle(this.themeId()))
  }

  /** 应用级动作按钮：统一 44vp 命中高度 + hover + 键盘焦点 */
  @Builder
  headerAction(label: string, action: () => void) {
    Row() {
      Text(label).fontSize(12).fontColor(this.colors().textSecondary)
    }
    .height(DESKTOP_CHROME_HEIGHT_VP)
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .accessibilityText(label)
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .tabStop(true)
    .onClick(action)
  }

}
