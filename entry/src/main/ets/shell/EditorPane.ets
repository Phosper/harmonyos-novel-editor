// 编辑视图 —— 标签栏 + 工具条 + 正文编辑面
import { promptAction } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { tokensFor, WeaverColorSet, WeaverRadii, WeaverSpacing, WeaverMobile, paperLineHeightVp, DEFAULT_THEME_ID, blendHexColor } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { app as globalApp, fireAndLog } from '../store/AppStores'
import { UiStore } from '../store/UiStore'
import { EditorStore } from '../store/EditorStore'
import { Logger } from '../utils/Logger'
import type { OpenDoc, DocItem } from '../store/StoreModels'
import { SaveState } from '../store/StoreModels'
import { ChapterFormat } from '../model/Chapter'
import type { BookModel } from '../model/Book'
import { TextEditorHost } from '../editor/TextEditorHost'
import { CanvasTextEditorController } from '../editor/flowtext/CanvasTextEditor'
import { ScrollPolicy, StyleKind, FormatRun } from '../editor/flowtext/model/EditorTypes'
import { FormatCodec } from '../editor/flowtext/model/FormatCodec'
import { TextFormat, FormatOptions } from '../utils/TextFormat'
import { EditorTools } from './EditorTools'
import { toggleFocusAnimated } from './FocusTransition'
import { glassBarStyle } from './MaterialSurface'
import { startWindowMove, toggleWindowMaximize, isDesktopWindow } from '../utils/WindowDrag'

/** 文稿标记位（收藏 / 灵感池） */
enum DocFlag {
  FAV = 0,
  INSPIRATION = 1
}

@ComponentV2
export struct EditorPane {
  @Param app: AppStores | null = null
  /** 宿主已有文稿标题条（手机/平板 WorkspaceDest）时不再重复显示正文标题 */
  @Param showTitle: boolean = true
  @Local ui: UiStore = globalApp.ui
  @Local editor: EditorStore = globalApp.editor
  /** 查找替换浮层状态 */
  @Local showReplace: boolean = false
  /** 自绘编辑器控制器（格式命令用，T026） */
  @Local editorController: CanvasTextEditorController | null = null
  @Local findText: string = ''
  @Local replaceText: string = ''
  /** 工具条可用宽度（vp）：窄列时收成精简工具条，避免动作被裁切 */
  @Local toolbarWidth: number = 999
  /** 编辑区头部实测宽度（vp）：用于给 EditorTools 计算「扣掉三键避让后的可用空间」 */
  @Local headerWidth: number = 0
  /** 标题行内重命名态 */
  @Local renaming: boolean = false
  @Local draftTitle: string = ''
  private renameDocId: string = ''
  private renameBookId: string = ''
  private renameDoc: OpenDoc | null = null
  private renameRevision: number = 0

  aboutToAppear(): void {
    if (this.app !== null) {
      this.ui = this.app.ui
      this.editor = this.app.editor
    }
  }

  aboutToDisappear(): void {
    this.renameRevision++
    this.renaming = false
    this.renameDoc = null
    if (this.app !== null && this.app.ui.editorController === this.editorController) {
      this.app.ui.editorController = null
    }
    this.editorController = null
  }

  @Monitor('editor.activeId')
  onActiveDocChanged(): void {
    this.showReplace = false
    this.renameRevision++
    this.renaming = false
    this.renameDoc = null
  }

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  /**
   * 打字机模式的"非当前段落"字色。
   * 由当前主题的正文色向纸色混合 50% 得到：明显变淡但仍保持可读，
   * 深浅主题自动适配，不硬编码任何颜色。
   */
  /** 顶栏「查找」→ 打开查找替换面板（工具已上移到顶栏，避免编辑器内再放一条工具条） */
  @Monitor('ui.findRequestTick')
  onFindRequested(): void {
    this.showReplace = true
  }

  /** 撤销/重做不经过 onEdit，但 contentRev 会变化：同步中栏预览 */
  /** 历史深度：撤销/重做按钮的禁用态靠它显式驱动（数组原地 push 不可靠） */
  @Local historyTick: number = 0

  @Monitor('editor.historyVersion')
  onHistoryVersion(): void {
    if (this.app !== null) {
      this.historyTick = this.app.editor.historyVersion
    }
  }

  @Monitor('editor.contentRev')
  onContentRevChanged(): void {
    this.syncActivePreview()
  }

  private syncActivePreview(): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) { return }
    const doc: OpenDoc | undefined = stores.editor.activeDoc
    if (doc === undefined) { return }
    stores.project.updateDocPreview(doc.id, stores.editor.title, stores.editor.content,
      stores.editor.wordCount, doc.dirty)
  }

  private applyEditorChange(text: string, runs: FormatRun[], caret: number, ownerId: string): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc || stores.editor.activeId !== ownerId) { return }
    stores.editor.setEditorState(text, FormatCodec.encode(runs), caret, ownerId)
    stores.ui.noteTyping()
    this.syncActivePreview()
  }

  private typewriterDimColor(): string {
    const c: WeaverColorSet = this.colors()
    return blendHexColor(c.textPrimary, c.editorBg, 0.5)
  }

  /**
   * 是否显示格式工具条：宽屏 / 电脑模式（自由窗口、MatePad Edge 电脑模式）/ 键鼠优先。
   * 手机（触摸为主、非自由窗口）保持最小 chrome —— 与契约 §2.7 一致。
   */
  private showFormatChrome(): boolean {
    if (this.app === null) {
      return false
    }
    // 只按"是否宽屏/电脑模式"给工具条：手机即使接了蓝牙鼠标也不在 360vp 里塞 10 个动作
    return this.app.ui.isWide || this.app.ui.isDesktopMode
  }

  /** 遗留：旧 `editorToolbar()`（已不在 build 中使用）仍按 <700vp 收窄，保留避免死代码引用报错 */
  private compactToolbar(): boolean {
    return this.toolbarWidth < 700
  }

  /**
   * 工具组可用宽度（vp）= 头部实测宽度 − 左内边距 − 原生三键避让。
   * 0 表示尚未测量：EditorTools 会按全量渲染，下一帧再分档。
   */
  private toolSpace(): number {
    if (this.headerWidth <= 0) {
      return 0
    }
    return Math.max(0, this.headerWidth - 12 - this.headerRightInset())
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      if (this.app === null || !this.app.editor.hasDoc) {
        this.emptyState()
      } else {
        // 内容列：工具/标题/正文共享同一条居中阅读列（760vp 上限），
        // 与纯纯写作一致；窄窗口自动占满，不产生横向滚动。
        Column() {
        // 文档级工具：贴在正文顶部右侧，成为编辑区的一部分（不再占用窗口标题栏）
        this.editorHeader()
        // 轻量文稿标题：与正文左边缘对齐，点击可就地重命名（不加卡片/描边）
        if (this.showTitle) {
          this.docTitleRow()
        }
        // 正文编辑面：自绘 FlowText（唯一实现，T037 单引擎收敛）
        Stack({ alignContent: Alignment.TopStart }) {
        TextEditorHost({
            docId: this.app.editor.activeId,
            contentRev: this.app.editor.contentRev,
            typewriter: this.app.ui.typewriter,
            scrollPolicy: this.app.ui.typewriter ? ScrollPolicy.CENTER : ScrollPolicy.NORMAL,
            // 设备分流（契约 §1/§2.7）：电脑模式与键鼠优先由 UiStore 统一判定，
            // 编辑器只接收基本类型，不感知 UiStore/DeviceProfile 实现
            desktopMode: this.app.ui.isDesktopMode,
            pointerPrimary: this.app.ui.pointerPrimary,
            loadFormat: (docId: string): FormatRun[] => {
              if (this.app === null) {
                return []
              }
              const d: OpenDoc | undefined = this.app.editor.openDocs.find((x: OpenDoc) => x.id === docId)
              return d !== undefined ? FormatCodec.decode(d.runsJson) : []
            },
            onSelectionChange: (start: number, end: number) => {
              // 只递增版本号：顶栏 B/I/H 据此重新求值，不把选区坐标塞进 store
              if (this.app !== null) {
                this.app.ui.selectionTick++
              }
            },
            onFormatChange: (runs: FormatRun[]) => {
              if (this.app !== null) {
                this.app.ui.selectionTick++
              }
            },
            onScrollState: (state: number) => {
              if (this.app !== null) {
                this.app.ui.noteScroll(state)
              }
            },
            onControllerReady: (controller: CanvasTextEditorController) => {
              this.editorController = controller
              // 顶栏工具组通过 store 取控制器（格式/打字机动作无需层层透传）
              if (this.app !== null) {
                this.app.ui.editorController = controller
              }
            },
            onRequestFind: (text: string) => {
              this.findText = text
              this.showReplace = true
            },
            onRequestShare: (text: string) => {
              this.shareText(text)
            },
            fontSize: this.app.ui.paperTheme.fontSize,
            lineHeight: paperLineHeightVp(this.app.ui.paperTheme),
            textColor: this.colors().textPrimary,
            bgColor: this.colors().editorBg,
            caretColor: this.colors().brand,
            dimTextColor: this.typewriterDimColor(),
            placeholder: '开始写作…',
            placeholderColor: this.colors().textTertiary,
            loadText: (docId: string): string => {
              if (this.app === null) {
                return ''
              }
              const d: OpenDoc | undefined = this.app.editor.openDocs.find((x: OpenDoc) => x.id === docId)
              return d !== undefined ? d.draft : ''
            },
            loadCaret: (docId: string): number => {
              if (this.app === null) {
                return 0
              }
              const d: OpenDoc | undefined = this.app.editor.openDocs.find((x: OpenDoc) => x.id === docId)
              return d !== undefined ? d.caret : 0
            },
            onEdit: (text: string, runs: FormatRun[], caret: number, ownerId: string) => {
              this.applyEditorChange(text, runs, caret, ownerId)
            },
            onCaretChange: (offset: number, ownerId: string) => {
              if (this.app !== null) {
                this.app.editor.setCaret(offset, ownerId)
              }
            },
            onRequestSave: (ownerId: string) => {
              if (this.app !== null && this.app.editor.activeId === ownerId) {
                this.app.editor.flushActive()
              }
            },
            onUndo: (ownerId: string) => {
              if (this.app !== null && this.app.editor.activeId === ownerId) {
                this.app.editor.undo()
              }
            },
            onRedo: (ownerId: string) => {
              if (this.app !== null && this.app.editor.activeId === ownerId) {
                this.app.editor.redo()
              }
            },
            onToggleImmersive: () => {
              if (this.app !== null) {
                toggleFocusAnimated(this.getUIContext())
              }
            }
          })
            .width('100%').height('100%')
        }
        .layoutWeight(1)
        .width('100%')
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 760 })
      }
      }
      .width('100%').height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.app !== null ? this.colors().editorBg : this.colors().bgPrimary)

      if (this.showReplace) {
        this.replacePanel()
      }

    }
    .width('100%').height('100%')
  }

  private canShowEditorTools(): boolean {
    if (this.app === null) {
      return false
    }
    return this.app.editor.hasDoc && !this.app.ui.immersiveEditing
  }

  private toolsRowHeight(): number {
    if (this.app === null) {
      return 48
    }
    // 平板：图标热区 56，工具行同步加高
    if (this.app.ui.tabletMode) {
      return 56
    }
    // 电脑模式：给原生三键留出 48vp 高度，标题从三键下方开始
    if (this.app.ui.usesDesktopChrome) {
      return 48
    }
    // 阔直板（Pura X View）：高度只有 744vp，工具行压到 44
    if (this.app.ui.wideBar) {
      return 44
    }
    return this.app.ui.pointerPrimary ? 44 : 48
  }

  /** 平板空态要更大、更居中 */
  private tablet(): boolean {
    return this.app !== null && this.app.ui.tabletMode
  }

  /** 工具行右侧避让原生三键（实测宽度 + 缓冲），非桌面窗口只留 12vp 常规边距 */
  private headerRightInset(): number {
    if (this.app === null || !this.app.ui.usesDesktopChrome) {
      return 12
    }
    return this.app.ui.captionInset
  }

  private placeholderSize(): number {
    return this.app === null ? 16 : this.app.ui.paperTheme.fontSize
  }

  @Builder
  editorHeader() {
    if (this.canShowEditorTools()) {
      Row() {
        // 左侧空白 = 窗口拖动/双击最大化热区；右侧是工具，避免按到按钮时拖窗
        Row() {
        }
        .layoutWeight(1)
        .height(this.toolsRowHeight())
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down && isDesktopWindow()) {
            startWindowMove()
          }
        })
        .onMouse((event: MouseEvent) => {
          if (event.action === MouseAction.Press && event.button === MouseButton.Left && isDesktopWindow()) {
            startWindowMove()
          }
        })
        .gesture(TapGesture({ count: 2 }).onAction(() => {
          if (isDesktopWindow()) {
            toggleWindowMaximize()
          }
        }))
        EditorTools({ app: this.app, space: this.toolSpace(), immersive: false, historyTick: this.historyTick })
      }
      .width('100%')
      .height(this.toolsRowHeight())
      .padding({ left: 12, right: this.headerRightInset() })
      .alignItems(VerticalAlign.Center)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width)
        // 只在明显变化时写状态，避免拖动窗口时每帧重渲染
        if (Math.abs(width - this.headerWidth) > 16) {
          this.headerWidth = width
        }
      })
    }
  }

  /** 标题右侧的轻量状态：字数 + 保存态（不重复到窗口头） */
  private docStatus(): string {
    if (this.app === null) {
      return ''
    }
    const state: string = this.app.editor.dirtyCount > 0 ? '编辑中' : '已保存'
    return this.app.editor.wordCount.toString() + ' 字 · ' + state
  }

  /** 当前项目名（用于标题下的归属 chip；没有项目时不显示） */
  private projectName(): string {
    if (this.app === null) {
      return ''
    }
    const book: BookModel | undefined = this.app.project.currentBook
    return book !== undefined ? book.name : ''
  }

  @Builder
  docTitleRow() {
    if (this.app !== null && this.app.editor.hasDoc) {
      Column() {
        Row() {
        if (this.renaming) {
          // 就地重命名：与显示态同一字号、无边框无按钮；回车/失焦保存，Esc 取消
          TextInput({ text: this.draftTitle })
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .height(40)
            .layoutWeight(1)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .caretColor(this.colors().brand)
            .onChange((v: string) => { this.draftTitle = v })
            .onSubmit(() => this.commitRename())
            .onBlur(() => this.commitRename())
            .onKeyEvent((event: KeyEvent) => {
              if (event.type === KeyType.Down && event.keyCode === 2070) {
                this.cancelRename()
                return true
              }
              return false
            })
        } else {
          Text(this.app.editor.title !== '' ? this.app.editor.title : '未命名文稿')
            .fontSize(28).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText('文稿标题，点击重命名')
            .onClick(() => this.beginRename())
        }
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)

        // 元信息：项目 chip + 字数/保存态；标题区在正文上方固定，Canvas 滚动时保持不动（吸顶）
        Row() {
          if (this.projectName() !== '') {
            Row() {
              Column()
                .width(8).height(8).borderRadius(4)
                .backgroundColor(this.colors().brand)
                .margin({ right: 6 })
              Text(this.projectName())
                .fontSize(12).fontColor(this.colors().textSecondary)
                .maxLines(1)
            }
            .height(24)
            .padding({ left: 8, right: 10 })
            .borderRadius(WeaverRadii.LG)
            .backgroundColor(this.colors().bgSurface)
            .margin({ right: 10 })
            .accessibilityText('所属项目：' + this.projectName())
          }
          Text(this.docStatus())
            .fontSize(12).fontColor(this.colors().textTertiary)
        }
        .width('100%')
        .height(28)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 10 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  private beginRename(): void {
    if (this.app === null || !this.app.editor.hasDoc) { return }
    const doc: OpenDoc | undefined = this.app.editor.activeDoc
    if (doc === undefined) { return }
    this.renameRevision++
    this.renameDocId = doc.id
    this.renameBookId = this.app.project.currentBookId
    this.renameDoc = doc
    this.draftTitle = this.app.editor.title
    this.renaming = true
  }

  private cancelRename(): void {
    this.renameRevision++
    this.renaming = false
    this.renameDoc = null
  }

  private commitRename(): void {
    if (!this.renaming) {
      return
    }
    this.renaming = false
    const stores: AppStores | null = this.app
    if (stores === null) { return }
    const id: string = this.renameDocId
    const bookId: string = this.renameBookId
    const doc: OpenDoc | null = this.renameDoc
    const revision: number = this.renameRevision
    const controller: CanvasTextEditorController | null = this.editorController
    if (doc === null || stores.project.currentBookId !== bookId ||
      stores.editor.activeId !== id || stores.editor.activeDoc !== doc) { return }
    const next: string = this.draftTitle.trim()
    if (next === '' || next === doc.title) {
      return
    }
    stores.renameChapter(id, next)
      .then(() => {
        if (this.app === stores && this.renameRevision === revision &&
          stores.project.currentBookId === bookId && stores.editor.activeId === id &&
          stores.editor.activeDoc === doc && this.editorController === controller &&
          controller !== null && stores.ui.editorController === controller) {
          controller.focus()
        }
      })
      .catch((e: Error) => {
        Logger.warn('EditorPane: rename failed: ' + String(e))
      })
  }

  @Builder
  replacePanel() {
    Column() {
      Column() {
        Text('查找替换').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
          .width('100%').margin({ bottom: 12 })
        TextInput({ placeholder: '查找内容', text: this.findText })
          .onChange((v: string) => { this.findText = v })
          .width('100%').height(40).fontSize(14)
          .backgroundColor(this.colors().bgSurface).borderRadius(WeaverRadii.SM)
          .margin({ bottom: 10 })
        TextInput({ placeholder: '替换为（留空即删除）', text: this.replaceText })
          .onChange((v: string) => { this.replaceText = v })
          .width('100%').height(40).fontSize(14)
          .backgroundColor(this.colors().bgSurface).borderRadius(WeaverRadii.SM)
          .margin({ bottom: 16 })
        Row() {
          Button('关闭').layoutWeight(1).height(40).fontSize(14)
            .backgroundColor(this.colors().bgSurface).fontColor(this.colors().textSecondary)
            .borderRadius(WeaverRadii.SM)
            .onClick(() => this.closeReplace())
          Button('全部替换').layoutWeight(2).height(40).fontSize(14).margin({ left: 10 })
            .backgroundColor(this.colors().brand).fontColor(this.colors().onBrand)
            .borderRadius(WeaverRadii.SM)
            .onClick(() => this.replaceAll())
        }.width('100%')
      }
      .width('88%').constraintSize({ maxWidth: 460 })
      .padding(20).backgroundColor(this.colors().bgCard).borderRadius(WeaverRadii.LG)
      .onClick(() => {})
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
    .onClick(() => this.closeReplace())
  }

  private openReplace(): void {
    this.showReplace = true
  }

  /** 施加/取消行内格式（T026） */
  private applyInline(kind: StyleKind): void {
    if (this.editorController !== null) {
      this.editorController.toggleInlineStyle(kind)
    }
  }

  /** 切换段落标题级别（T026） */
  private applyHeading(level: number): void {
    if (this.editorController !== null) {
      this.editorController.toggleParagraphStyle(level)
    }
  }

  private closeReplace(): void {
    this.showReplace = false
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg })
  }

  /** 把选中的文本写入系统剪贴板（可跨应用粘贴）；只有真正成功才提示“已复制”。 */
  private async shareText(text: string): Promise<void> {
    if (text === '') {
      this.toast('无选中文本')
      return
    }
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await board.setData(data)
      this.toast('已复制所选文本到系统剪贴板')
    } catch (e) {
      this.toast('复制失败，请重试或使用导出')
    }
  }

  /** 一键排版（编辑器无关：作用于 store 正文，可撤销） */
  private runFormat(): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return
    }
    const res = TextFormat.format(stores.editor.content, new FormatOptions())
    if (res.changed === 0) {
      this.toast('已是整洁排版，无需整理')
      return
    }
    stores.editor.applyExternalContent(res.text)
    this.toast('已整理排版（修改 ' + res.changed + ' 行）')
  }

  /** 全部替换 */
  private replaceAll(): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return
    }
    const find: string = this.findText
    if (find === '') {
      this.toast('请输入查找内容')
      return
    }
    const src: string = stores.editor.content
    let count: number = 0
    let idx: number = src.indexOf(find)
    let out: string = ''
    let from: number = 0
    while (idx >= 0) {
      out += src.substring(from, idx) + this.replaceText
      from = idx + find.length
      count++
      idx = src.indexOf(find, from)
    }
    out += src.substring(from)
    if (count === 0) {
      this.toast('未找到匹配内容')
      return
    }
    stores.editor.applyExternalContent(out)
    this.closeReplace()
    this.toast('已替换 ' + count + ' 处')
  }

  @Builder
  emptyState() {
    // 外层铺满，内层收进 760vp 阅读列并居中 —— 空态与正文同一条中线
    Column() {
      Column() {
        Text('还没有打开任何文稿')
          .fontSize(this.tablet() ? 20 : 16).fontWeight(FontWeight.Medium)
          .fontColor(this.colors().textPrimary)
        Text('从文稿列表选择一篇，或新建一篇开始写作')
          .fontSize(this.tablet() ? 13 : 12).fontColor(this.colors().textTertiary).margin({ top: 8 })
        Button('新建文稿')
          .height(this.tablet() ? 48 : 36).fontSize(this.tablet() ? 15 : 13).margin({ top: 20 })
          .padding({ left: this.tablet() ? 28 : 20, right: this.tablet() ? 28 : 20 })
          .backgroundColor(this.colors().brand).fontColor(this.colors().onBrand)
          .borderRadius(WeaverRadii.SM)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            if (this.app !== null) {
              // 建文稿要读聚合、写库，onClick 无法 await → 接住拒绝，避免未处理拒绝杀进程
              fireAndLog(this.app.createChapter(), 'createChapter')
            }
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 760 })
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24 })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ── 统一编辑器工具条（电脑/宽屏）：左侧状态，右侧文档动作 ──
  // 与原实现相比：撤销/重做/格式/查找/打字机从"两条栏"合并到一条，去掉重复入口；
  // 打字机是两态按钮（有明确 ON 状态、可再次点击关闭），不再依赖外部菜单。
  @Builder
  editorToolbar() {
    Row() {
      Text((this.app !== null ? this.app.editor.wordCount : 0) + ' 字')
        .fontSize(12).fontColor(this.colors().textSecondary)
      Text(this.saveHintText())
        .fontSize(12)
        .fontColor(this.hintColor())
        .margin({ left: 10 })
        .maxLines(1)
        .accessibilityText('保存状态：' + this.saveHintText())
        .onClick(() => this.onSaveHintClick())

      Blank()

      if (!this.compactToolbar()) {
        this.formatChip(ChapterFormat.TXT, 'TXT')
        this.formatChip(ChapterFormat.MD, 'MD')
        this.flagText(DocFlag.FAV)
        this.flagText(DocFlag.INSPIRATION)

        Divider()
          .vertical(true).height(16).color(this.colors().divider)
          .margin({ left: 8, right: 4 })
      }

      this.toolButton('撤销', this.app !== null && this.app.editor.canUndo, () => {
        if (this.app !== null) {
          this.app.editor.undo()
        }
      })
      this.toolButton('重做', this.app !== null && this.app.editor.canRedo, () => {
        if (this.app !== null) {
          this.app.editor.redo()
        }
      })

      if (!this.compactToolbar()) {
        Divider()
          .vertical(true).height(16).color(this.colors().divider)
          .margin({ left: 6, right: 4 })

        this.toolButton('粗', false, () => this.applyInline(StyleKind.BOLD))
        this.toolButton('斜', false, () => this.applyInline(StyleKind.ITALIC))
        this.toolButton('H1', false, () => this.applyHeading(1))

        Divider()
          .vertical(true).height(16).color(this.colors().divider)
          .margin({ left: 6, right: 4 })
      }

      this.typewriterButton()
      if (!this.compactToolbar()) {
        this.toolButton('查找', this.showReplace, () => this.openReplace())
        this.toolButton('排版', false, () => this.runFormat())
      } else {
        this.moreIconButton()
      }
    }
    .width('100%').constraintSize({ minHeight: WeaverSpacing.TOOLBAR_H })
    .padding({ left: 16, right: 12 })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w: number = Number(newValue.width)
      // 只在真正跨过阈值时写状态，避免拖动窗口时每帧重渲染工具条
      const nextCompact: boolean = w < 700
      if (nextCompact !== this.compactToolbar()) {
        this.toolbarWidth = w
      } else if (Math.abs(w - this.toolbarWidth) > 40) {
        this.toolbarWidth = w
      }
    })
    // 工具条属于 chrome：交给主题玻璃面（与窗口头同一材质，视觉连续）
    .attributeModifier(glassBarStyle(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID))
  }

  /** 文档动作按钮：统一字号/命中高度/禁用态/hover */
  @Builder
  toolButton(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor(active ? this.colors().brand : this.colors().textSecondary)
      .padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .textAlign(TextAlign.Center)
      .borderRadius(WeaverRadii.XS)
      .backgroundColor(active ? this.colors().activeBg : Color.Transparent)
      .accessibilityText(label)
      .hoverEffect(HoverEffect.Highlight)
      .margin({ left: 2 })
      .onClick(action)
  }

  /** 收起态「更多」：鸿蒙四点图标（dot_grid_2x2），与窗口头/列表头同一符号 */
  @Builder
  moreIconButton() {
    SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
      .fontSize(16)
      .fontColor([this.colors().textSecondary])
      .padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .borderRadius(WeaverRadii.XS)
      .accessibilityText('更多')
      .hoverEffect(HoverEffect.Highlight)
      .margin({ left: 2 })
      .onClick(() => this.openMoreMenu())
  }

  /** 打字机两态按钮：开启时品牌色 + 圆点 + 底色，关闭时中性 */
  @Builder
  typewriterButton() {
    Row() {
      Circle({ width: 6, height: 6 })
        .fill(this.typewriterOn() ? this.colors().brand : this.colors().textTertiary)
        .margin({ right: 6 })
      Text('打字机')
        .fontSize(12)
        .fontColor(this.typewriterOn() ? this.colors().brand : this.colors().textSecondary)
    }
    .height(28)
    .padding({ left: 9, right: 10 })
    .borderRadius(14)
    .backgroundColor(this.typewriterOn() ? this.colors().activeBg : Color.Transparent)
    .border({
      width: 1,
      color: this.typewriterOn() ? this.colors().brand : Color.Transparent
    })
    .accessibilityText(this.typewriterOn() ? '打字机模式：已开启，点击关闭' : '打字机模式：已关闭，点击开启')
    .hoverEffect(HoverEffect.Highlight)
    .margin({ left: 2 })
    .onClick(() => this.toggleTypewriterMode())
  }

  private typewriterOn(): boolean {
    return this.app !== null && this.app.ui.typewriter
  }

  /**
   * 切换打字机：同时写 store 与编辑器控制器。
   * 只写 store 时，V1 岛屿的 @Prop 更新时序可能不触发重排，表现为"按钮没反应"；
   * 因此这里直接下发控制器，保证点击后立即产生居中/恢复效果。
   */
  private toggleTypewriterMode(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const next: boolean = !stores.ui.typewriter
    stores.ui.setTypewriter(next)
    if (this.editorController !== null) {
      this.editorController.setTypewriter(next)
    }
    this.toast(next ? '打字机模式已开启' : '打字机模式已关闭')
  }

  // 手机端次级工具条：仅保留字数与保存态，其余操作收进"更多"菜单
  @Builder
  mobileToolBar() {
    Row() {
      Text((this.app !== null ? this.app.editor.wordCount : 0) + ' 字')
        .fontSize(13).fontColor(this.colors().textSecondary)
      Text(this.saveHintText())
        .fontSize(13).fontColor(this.hintColor())
        .margin({ left: 10 }).maxLines(1)
        .onClick(() => this.onSaveHintClick())
      Blank()
      Text('更多')
        .fontSize(14).fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .accessibilityText('更多')
        .onClick(() => this.openMoreMenu())
    }
    .width('100%').height(WeaverMobile.TOOLBAR_H)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.colors().editorBg)
  }

  /** 手机端"更多"：格式 / 收藏 / 灵感 / 撤销 / 重做 */
  private openMoreMenu(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    // color 为必填项（string|Resource）：传空字符串会触发运行时报错 401
    // 「Parameter error」，导致应用退出，故使用主题正文色。
    const menuColor: string = this.colors().textPrimary
    const b1: promptAction.Button = { text: '格式 · TXT', color: menuColor }
    const b2: promptAction.Button = { text: '格式 · Markdown', color: menuColor }
    const b3: promptAction.Button = { text: this.isFav() ? '取消收藏' : '收藏', color: menuColor }
    const b4: promptAction.Button = { text: this.isInspiration() ? '移出灵感池' : '移入灵感池', color: menuColor }
    const b5: promptAction.Button = { text: '一键排版', color: menuColor }
    const b6: promptAction.Button = { text: '查找替换', color: menuColor }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '更多',
      buttons: [b1, b2, b3, b4, b5, b6]
    }, (err, data) => {
      if (err) {
        return
      }
      const i: number = data.index
      if (i === 0) {
        fireAndLog(stores.setChapterFormat(ChapterFormat.TXT), 'setChapterFormat')
      } else if (i === 1) {
        fireAndLog(stores.setChapterFormat(ChapterFormat.MD), 'setChapterFormat')
      } else if (i === 2) {
        fireAndLog(stores.toggleFav(stores.editor.activeId), 'toggleFav')
      } else if (i === 3) {
        fireAndLog(stores.toggleInspiration(stores.editor.activeId), 'toggleInspiration')
      } else if (i === 4) {
        this.runFormat()
      } else if (i === 5) {
        this.openReplace()
      }
    })
  }

  @Builder
  formatChip(format: ChapterFormat, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.isFormat(format) ? this.colors().brand : this.colors().textTertiary)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(WeaverRadii.XS)
      // 未选中透明（原来铺灰底），选中用 10% 品牌色
      .backgroundColor(this.isFormat(format) ? this.colors().activeBg : Color.Transparent)
      .margin({ right: 8 })
      .onClick(() => {
        if (this.app !== null) {
          fireAndLog(this.app.setChapterFormat(format), 'setChapterFormat')
        }
      })
  }

  // @Builder 参数按值传递、不会因状态变化刷新，故只传静态枚举，
  // 收藏/灵感与否在函数体内读当前状态
  @Builder
  flagText(kind: DocFlag) {
    Text(this.flagLabel(kind))
      .fontSize(14)
      .fontColor(this.isFlagOn(kind) ? this.colors().brand : this.colors().textTertiary)
      .padding({ left: 8, right: 8, top: 12, bottom: 12 })
      .margin({ left: 4 })
      .onClick(() => this.toggleFlag(kind))
  }

  private isFlagOn(kind: DocFlag): boolean {
    return kind === DocFlag.FAV ? this.isFav() : this.isInspiration()
  }

  private flagLabel(kind: DocFlag): string {
    const on: boolean = this.isFlagOn(kind)
    if (kind === DocFlag.FAV) {
      return on ? '已收藏' : '收藏'
    }
    return on ? '已在灵感池' : '灵感'
  }

  private toggleFlag(kind: DocFlag): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    if (kind === DocFlag.FAV) {
      fireAndLog(stores.toggleFav(stores.editor.activeId), 'toggleFav')
    } else {
      fireAndLog(stores.toggleInspiration(stores.editor.activeId), 'toggleInspiration')
    }
  }

  private saveHintText(): string {
    if (this.app === null) {
      return ''
    }
    if (this.app.editor.saveState === SaveState.SAVING) {
      return '保存中…'
    }
    if (this.app.editor.saveState === SaveState.TOO_LARGE) {
      return '正文超长，未保存 —— 点击查看'
    }
    if (this.app.editor.saveState === SaveState.FAILED) {
      return '保存失败，点击重试'
    }
    if (this.app.editor.dirtyCount > 0) {
      return '编辑中…'
    }
    return '已保存'
  }

  /**
   * 状态提示的点击行为：超限时弹出完整说明（内容较长，工具条放不下），
   * 其余情况沿用"点击重试保存"。
   */
  private onSaveHintClick(): void {
    if (this.app === null) {
      return
    }
    if (this.app.editor.saveState === SaveState.TOO_LARGE) {
      this.getUIContext().getPromptAction().showDialog({
        title: '正文过长，无法保存',
        message: this.app.editor.saveHint,
        buttons: [{ text: '知道了', color: this.colors().textPrimary }]
      })
      return
    }
    this.app.editor.retrySave()
  }

  /** 提示色：超长与失败都属异常，用警示色区分于普通灰 */
  private hintColor(): string {
    if (this.app === null) {
      return this.colors().textTertiary
    }
    const s: SaveState = this.app.editor.saveState
    return s === SaveState.FAILED ? this.colors().danger
      : (s === SaveState.TOO_LARGE ? this.colors().warning : this.colors().textTertiary)
  }

  private isFormat(format: ChapterFormat): boolean {
    return this.app !== null && this.app.editor.format === format
  }

  private isFav(): boolean {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return false
    }
    const item: DocItem | undefined =
      stores.project.docItems.find((d: DocItem) => d.id === stores.editor.activeId)
    return item !== undefined && item.isFav
  }

  private isInspiration(): boolean {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return false
    }
    const item: DocItem | undefined =
      stores.project.docItems.find((d: DocItem) => d.id === stores.editor.activeId)
    return item !== undefined && item.isInspiration
  }
}
