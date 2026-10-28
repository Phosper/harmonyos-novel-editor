// 顶栏编辑器工具组（桌面窗口头 / 平板宽屏顶栏共用）
//
// 2026-10-21 两轮修订：
//   1) 视觉：全部动作改成 Email 式裸图标（见 TopActionButton），不再有玻璃圆片；
//   2) 布局：按**可用宽度**分档，绝不溢出到窗口右上角被原生三键压住：
//        L0 全量（含「打字机」文字胶囊）
//        L1 全量（打字机只留图标）
//        L2 精简（⋯ 菜单 + 查找 + 专注）
//        L3 极简（⋯ 菜单 + 查找）
//        L4 单个四点菜单（全部动作仍可到达）
//      每档宽度由 rowWidth() 显式计算，level() 取第一个放得下的档位；
//      space 由调用方用「实测列宽 − 右侧原生三键避让」算好后传入。
//   3) 被收起的动作不会丢：⋯ 菜单里始终有 加粗 / 斜体 / 标题 / 打字机 / 专注写作。
import { tokensFor, WeaverColorSet, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import type { AppStores } from '../store/AppStores'
import { ParagraphKind, StyleKind } from '../editor/flowtext/model/EditorTypes'
import { TopActionButton } from './TopActionButton'
import { MenuButton } from './MenuButton'
import { toggleFocusAnimated } from './FocusTransition'
import { TopIconMetrics, topIconMetrics } from '../constants/LightTokens'

interface WeaverToolButtonOptions {
  symbol: Resource
  label: string
  active: boolean
  enabled: boolean
  action: () => void
}

@ComponentV2
export struct EditorTools {
  @Param app: AppStores | null = null
  /**
   * 工具组可用宽度（vp）：调用方用「列宽 − 左内边距 − 原生三键避让」算好传入。
   * 0 表示尚未测量，按全量渲染（首帧可能被裁剪一瞬，下一帧即分档到位）。
   */
  @Param space: number = 0
  /** 沉浸模式下隐藏“进入沉浸”按钮（退出入口由窗口头提供） */
  @Param immersive: boolean = false
  /** 历史深度（由宿主经 @Monitor 推送）：让撤销/重做禁用态可精确刷新 */
  @Param historyTick: number = 0

  /** 空闲淡出：3 秒无操作降到 55%，悬停/输入/选词即恢复 */
  @Local idle: boolean = false
  private idleTimer: number = -1

  aboutToAppear(): void {
    this.scheduleIdle()
  }

  aboutToDisappear(): void {
    if (this.idleTimer !== -1) {
      clearTimeout(this.idleTimer)
      this.idleTimer = -1
    }
  }

  /** 任何输入/选区变化都算“活跃”（editor 每次编辑都会递增 selectionTick） */
  @Monitor('app.ui.selectionTick')
  onSelectionTick(): void {
    this.wake()
  }

  private scheduleIdle(): void {
    if (this.idleTimer !== -1) {
      clearTimeout(this.idleTimer)
    }
    this.idleTimer = setTimeout(() => {
      this.idleTimer = -1
      this.idle = true
    }, 3000)
  }

  private wake(): void {
    if (this.idle) {
      this.idle = false
    }
    this.scheduleIdle()
  }

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  /** 图标形态：电脑 = 方形 40/44/20，平板 = 圆形 44/56/24 */
  private metrics(): TopIconMetrics {
    if (this.app === null) {
      return topIconMetrics(true, false, false)
    }
    return topIconMetrics(this.app.ui.pointerPrimary, this.app.ui.tabletMode,
      this.app.ui.usesDesktopChrome)
  }

  private hitSize(): number {
    return this.metrics().hitSize
  }

  /** 打字机胶囊：平板字号更大，留宽一点 */
  private tabletPill(): boolean {
    return this.app !== null && this.app.ui.tabletMode
  }

  private pillWidth(): number {
    return this.tabletPill() ? 88 : 74
  }

  private hasDoc(): boolean {
    return this.app !== null && this.app.editor.hasDoc
  }

  private canUndo(): boolean {
    if (this.app === null) {
      return false
    }
    // 读宿主推送的 tick + store 版本号，建立稳定的显式依赖
    const tick: number = this.historyTick
    const version: number = this.app.editor.historyVersion
    return tick >= 0 && version >= 0 && this.app.editor.canUndo
  }

  private canRedo(): boolean {
    if (this.app === null) {
      return false
    }
    const tick: number = this.historyTick
    const version: number = this.app.editor.historyVersion
    return tick >= 0 && version >= 0 && this.app.editor.canRedo
  }

  private typewriterOn(): boolean {
    return this.app !== null && this.app.ui.typewriter
  }

  /** 当前格式位掩码；读取 selectionTick 建立订阅 */
  private currentMask(): number {
    if (this.app === null || this.app.ui.editorController === null) {
      return 0
    }
    const tick: number = this.app.ui.selectionTick
    if (tick < 0) {
      return 0
    }
    return this.app.ui.editorController.inlineStyleMask()
  }

  // ── 宽度分档 ──────────────────────────────────────────────
  //
  // 每档都按「图标热区 + 外边距」精算，宁可早一档收起，也不让内容溢出到
  // 窗口右上角（那里是系统绘制的三键区，会把图标压掉一半）。
  // 精简档（L2/L3）去掉图标外边距，44vp 热区贴紧，省出 16vp。

  private gapForLevel(): number {
    return this.level() <= 1 ? this.metrics().gap : 0
  }

  private rowWidth(level: number): number {
    const gap: number = level <= 1 ? this.metrics().gap : 0
    const slot: number = this.hitSize() + gap * 2
    const divider: number = 8
    const menu: number = this.paragraphMenuWidth()
    if (level === 0) {
      // 撤销 重做 | B I 段落▾ | 打字机胶囊 查找 专注
      return 2 * slot + divider + 2 * slot + menu + divider + this.pillWidth() + slot + slot
    }
    if (level === 1) {
      // 打字机改为纯图标
      return 2 * slot + divider + 2 * slot + menu + divider + slot + slot + slot
    }
    if (level === 2) {
      // 撤销 重做 | ⋯ | 查找 专注
      return 2 * slot + divider + slot + divider + slot + slot
    }
    if (level === 3) {
      // 撤销 重做 | ⋯ | 查找
      return 2 * slot + divider + slot + divider + slot
    }
    return slot
  }

  private level(): number {
    const space: number = this.space
    if (space <= 0) {
      return 0
    }
    for (let level: number = 0; level <= 3; level++) {
      if (this.rowWidth(level) <= space) {
        return level
      }
    }
    return 4
  }

  private toggleTypewriter(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const next: boolean = !stores.ui.typewriter
    stores.ui.setTypewriter(next)
    if (stores.ui.editorController !== null) {
      stores.ui.editorController.setTypewriter(next)
    }
  }

  private applyInline(kind: StyleKind): void {
    if (this.app !== null && this.app.ui.editorController !== null) {
      this.app.ui.editorController.toggleInlineStyle(kind)
    }
  }

  /** 设为某段落种类（工具栏下拉 / ⋯ 菜单共用） */
  private applyParagraph(kind: number): void {
    if (this.app !== null && this.app.ui.editorController !== null) {
      this.app.ui.editorController.setParagraphKind(kind)
    }
  }

  /** 当前段落种类（ParagraphKind）：读 selectionTick 建立订阅 */
  private paragraphKind(): number {
    if (this.app === null || this.app.ui.editorController === null) {
      return 0
    }
    if (this.app.ui.selectionTick < 0) {
      return 0
    }
    return this.app.ui.editorController.paragraphKind()
  }

  private paragraphLabel(): string {
    const kind: number = this.paragraphKind()
    if (kind === ParagraphKind.H1) {
      return '标题 1'
    }
    if (kind === ParagraphKind.H2) {
      return '标题 2'
    }
    if (kind === ParagraphKind.H3) {
      return '标题 3'
    }
    if (kind === ParagraphKind.BULLET) {
      return '• 列表'
    }
    if (kind === ParagraphKind.TODO) {
      return '○ 待办'
    }
    if (kind === ParagraphKind.TODO_DONE) {
      return '✓ 已完成'
    }
    return '正文'
  }


  /** 精简档的 ⋯ 菜单：被收起的动作全部在这里，功能不丢 */
  private onOverflowAction(index: number): void {
    if (index === 0) {
      this.undo()
    } else if (index === 1) {
      this.redo()
    } else if (index === 2) {
      this.applyInline(StyleKind.BOLD)
    } else if (index === 3) {
      this.applyInline(StyleKind.ITALIC)
    } else if (index === 4) {
      this.applyParagraph(ParagraphKind.BODY)
    } else if (index === 5) {
      this.applyParagraph(ParagraphKind.H1)
    } else if (index === 6) {
      this.applyParagraph(ParagraphKind.H2)
    } else if (index === 7) {
      this.applyParagraph(ParagraphKind.H3)
    } else if (index === 8) {
      this.applyParagraph(ParagraphKind.BULLET)
    } else if (index === 9) {
      this.applyParagraph(ParagraphKind.TODO)
    } else if (index === 10) {
      this.toggleTypewriter()
    } else if (index === 11) {
      this.requestFind()
    } else if (index === 12) {
      this.toggleFocus()
    }
  }

  private undo(): void {
    if (!this.canUndo() || this.app === null) { return }
    if (this.app.ui.editorController !== null) {
      this.app.ui.editorController.undo()
    } else {
      this.app.editor.undo()
    }
  }

  private redo(): void {
    if (!this.canRedo() || this.app === null) { return }
    if (this.app.ui.editorController !== null) {
      this.app.ui.editorController.redo()
    } else {
      this.app.editor.redo()
    }
  }

  private requestFind(): void {
    if (this.app !== null) { this.app.ui.requestFind() }
  }

  private toggleFocus(): void {
    if (this.app !== null && !this.immersive) {
      toggleFocusAnimated(this.getUIContext())
    }
  }

  @Builder
  overflowMenu() {
    MenuButton({
      label: '更多格式操作',
      themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
      isEnabled: this.hasDoc(),
      pointerPrimary: this.app !== null && this.app.ui.pointerPrimary,
      tabletMode: this.app !== null && this.app.ui.tabletMode,
      desktopMode: this.app !== null && this.app.ui.usesDesktopChrome,
      gapOverride: this.gapForLevel(),
      items: ['撤销', '重做', '加粗', '斜体', '正文', '标题 1', '标题 2', '标题 3',
        '• 列表', '○ 待办', '打字机', '查找', '专注写作'],
      onSelect: (index: number) => this.onOverflowAction(index)
    })
  }

  private paragraphMenuWidth(): number {
    return this.tabletPill() ? 96 : 84
  }

  @Builder
  paragraphMenuView() {
    // 点当前种类 = 回到正文（编辑器侧开关语义）；点其他种类 = 设为该种类
    Menu() {
      MenuItem({ content: '正文' }).onClick(() => this.applyParagraph(ParagraphKind.BODY))
      MenuItem({ content: '标题 1' }).onClick(() => this.applyParagraph(ParagraphKind.H1))
      MenuItem({ content: '标题 2' }).onClick(() => this.applyParagraph(ParagraphKind.H2))
      MenuItem({ content: '标题 3' }).onClick(() => this.applyParagraph(ParagraphKind.H3))
      MenuItem({ content: '• 无序列表' }).onClick(() => this.applyParagraph(ParagraphKind.BULLET))
      MenuItem({ content: '○ 待办清单' }).onClick(() => this.applyParagraph(ParagraphKind.TODO))
    }
    .fontSize(this.tabletPill() ? 16 : 14)
    .fontColor(this.colors().textPrimary)
    .radius(12)
  }

  /** 段落样式下拉：显示当前值的触发器（对齐备忘录「正文▾」） */
  @Builder
  paragraphStyleMenu() {
    Row() {
      Text(this.paragraphLabel())
        .fontSize(this.tabletPill() ? 14 : 13)
        .fontColor(this.colors().textPrimary)
        .maxLines(1)
      Text('⌄')
        .fontSize(12)
        .fontColor(this.colors().textTertiary)
        .margin({ left: 4 })
    }
    .height(this.tabletPill() ? 30 : 26)
    .padding({ left: 10, right: 8 })
    .borderRadius(8)
    .backgroundColor(this.colors().activeBg)
    .margin({ left: 2, right: 2 })
    .enabled(this.hasDoc())
    .opacity(this.hasDoc() ? 1 : 0.38)
    .accessibilityText('段落样式：' + this.paragraphLabel())
    .hoverEffect(HoverEffect.Highlight)
    .bindMenu(this.paragraphMenuView, { placement: Placement.BottomLeft, enableArrow: true })
  }

  @Builder
  toolDivider() {
    Divider()
      .vertical(true).height(14).color(this.colors().divider)
      .margin({ left: 2, right: 2 })
  }

  /** 打字机：L0 用带文字的胶囊（模式开关需要明确文字），L1 收成图标 */
  @Builder
  typewriterPill() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.textformat'))
          .fontSize(this.tabletPill() ? 15 : 14)
          .fontColor([this.typewriterOn() ? this.colors().brand : this.colors().textSecondary])
          .margin({ right: 5 })
        Text('打字机')
          .fontSize(this.tabletPill() ? 12 : 11)
          .fontColor(this.typewriterOn() ? this.colors().brand : this.colors().textSecondary)
      }
      .height(this.tabletPill() ? 30 : 26)
      .padding({ left: this.tabletPill() ? 10 : 8, right: this.tabletPill() ? 11 : 9 })
      .borderRadius(8)
      .backgroundColor(this.typewriterOn() ? this.colors().activeBg : Color.Transparent)
      .border({ width: 1, color: this.typewriterOn() ? this.colors().brand : Color.Transparent })
      .animation({ duration: Motion.fast, curve: Motion.standardCurve })
    }
    .height(this.hitSize())
    .padding({ left: 2, right: 2 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.typewriterOn() ? '打字机模式：已开启，点击关闭' : '打字机模式：已关闭，点击开启')
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.toggleTypewriter())
  }

  @Builder
  iconButton($$: WeaverToolButtonOptions) {
    TopActionButton({
      symbol: $$.symbol,
      label: $$.label,
      themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
      active: $$.active,
      isEnabled: $$.enabled,
      pointerPrimary: this.app !== null && this.app.ui.pointerPrimary,
      tabletMode: this.app !== null && this.app.ui.tabletMode,
      desktopMode: this.app !== null && this.app.ui.usesDesktopChrome,
      gapOverride: this.gapForLevel(),
      onTap: $$.action
    })
  }

  build() {
    Row() {
      if (this.level() <= 3) {
        this.iconButton({ symbol: $r('sys.symbol.undo'), label: '撤销', active: false,
          enabled: this.canUndo(), action: () => this.undo() })
        this.iconButton({ symbol: $r('sys.symbol.redo'), label: '重做', active: false,
          enabled: this.canRedo(), action: () => this.redo() })
      }

      if (this.level() <= 1) {
        this.toolDivider()
        this.iconButton({ symbol: $r('sys.symbol.bold'), label: '加粗', active: (this.currentMask() & 1) !== 0,
          enabled: this.hasDoc(), action: () => this.applyInline(StyleKind.BOLD) })
        this.iconButton({ symbol: $r('sys.symbol.italic'), label: '斜体', active: (this.currentMask() & 2) !== 0,
          enabled: this.hasDoc(), action: () => this.applyInline(StyleKind.ITALIC) })
        this.paragraphStyleMenu()
        this.toolDivider()
        if (this.level() === 0) {
          this.typewriterPill()
        } else {
          this.iconButton({ symbol: $r('sys.symbol.textformat'), label: '打字机', active: this.typewriterOn(),
            enabled: this.hasDoc(), action: () => this.toggleTypewriter() })
        }
        this.iconButton({ symbol: $r('sys.symbol.magnifyingglass'), label: '查找', active: false,
          enabled: this.hasDoc(), action: () => this.requestFind() })
        if (!this.immersive) {
          this.iconButton({ symbol: $r('sys.symbol.fullscreen'), label: '专注写作（隐藏侧栏与列表）', active: false,
            enabled: this.hasDoc(), action: () => this.toggleFocus() })
        }
      } else if (this.level() <= 3) {
        // 精简：格式与打字机进 ⋯ 菜单
        this.toolDivider()
        // 锚定下拉菜单（与 Email 三点菜单同形），不再用模态动作面板
        this.overflowMenu()
        this.toolDivider()
        this.iconButton({ symbol: $r('sys.symbol.magnifyingglass'), label: '查找', active: false,
          enabled: this.hasDoc(), action: () => this.requestFind() })
        if (this.level() === 2 && !this.immersive) {
          this.iconButton({ symbol: $r('sys.symbol.fullscreen'), label: '专注写作（隐藏侧栏与列表）', active: false,
            enabled: this.hasDoc(), action: () => this.toggleFocus() })
        }
      } else {
        this.overflowMenu()
      }
    }
    // 兜底：即使宽度测量晚到一帧，也不会把图标画到右侧原生三键区域外
    .clip(true)
    // 空闲淡出：写作时降低存在感，需要时 hover 立即恢复
    .opacity(this.idle ? 0.3 : 1)
    .animation({ duration: Motion.normal, curve: Motion.standardCurve })
    .onHover((isHover: boolean) => {
      if (isHover) {
        this.wake()
      } else {
        this.scheduleIdle()
      }
    })
  }

}
