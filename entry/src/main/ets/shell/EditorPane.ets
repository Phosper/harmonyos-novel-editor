// 编辑视图 —— 标签栏 + 工具条 + 正文编辑面
import { promptAction } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { tokensFor, WeaverColorSet, WeaverRadii, WeaverSpacing, WeaverMobile, paperLineHeightVp, DEFAULT_THEME_ID, blendHexColor } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { app as globalApp, fireAndLog } from '../store/AppStores'
import { UiStore } from '../store/UiStore'
import { EditorStore } from '../store/EditorStore'
import type { OpenDoc, DocItem } from '../store/StoreModels'
import { SaveState } from '../store/StoreModels'
import { ChapterFormat } from '../model/Chapter'
import { TextEditorHost } from '../editor/TextEditorHost'
import { CanvasTextEditorController } from '../editor/flowtext/CanvasTextEditor'
import { ScrollPolicy, StyleKind, FormatRun } from '../editor/flowtext/model/EditorTypes'
import { FormatCodec } from '../editor/flowtext/model/FormatCodec'
import { TextFormat, FormatOptions } from '../utils/TextFormat'

/** 文稿标记位（收藏 / 灵感池） */
enum DocFlag {
  FAV = 0,
  INSPIRATION = 1
}

@ComponentV2
export struct EditorPane {
  @Param app: AppStores | null = null
  @Local ui: UiStore = globalApp.ui
  @Local editor: EditorStore = globalApp.editor
  /** 查找替换浮层状态 */
  @Local showReplace: boolean = false
  /** 自绘编辑器控制器（格式命令用，T026） */
  @Local editorController: CanvasTextEditorController | null = null
  @Local findText: string = ''
  @Local replaceText: string = ''
  /** 标题行内重命名态 */
  @Local renaming: boolean = false
  @Local draftTitle: string = ''
  private renameDocId: string = ''

  aboutToAppear(): void {
    if (this.app !== null) {
      this.ui = this.app.ui
      this.editor = this.app.editor
    }
  }

  aboutToDisappear(): void {
    if (this.app !== null && this.app.ui.editorController === this.editorController) {
      this.app.ui.editorController = null
    }
    this.editorController = null
    this.renaming = false
    this.renameDocId = ''
  }

  @Monitor('editor.activeId')
  onActiveDocChanged(): void {
    this.renaming = false
    this.renameDocId = ''
    this.showReplace = false
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

  private typewriterDimColor(): string {
    const c: WeaverColorSet = this.colors()
    return blendHexColor(c.textPrimary, c.editorBg, 0.5)
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      if (this.app === null || !this.app.editor.hasDoc) {
        this.emptyState()
      } else {
        // 轻量文稿标题：与正文左边缘对齐，点击可就地重命名（不加卡片/描边）
        this.docTitleRow()
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
              if (this.app !== null) {
                this.app.editor.setEditorState(text, FormatCodec.encode(runs), caret, ownerId)
                if (this.app.editor.activeId === ownerId) { this.app.ui.noteTyping() }
              }
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
                this.app.ui.toggleImmersiveEditing()
              }
            }
          })
            .width('100%').height('100%')
          if (this.app !== null && this.app.editor.content.length === 0) {
            Text('开始写作…')
              .fontSize(this.app.ui.paperTheme.fontSize)
              .fontColor(this.colors().textTertiary)
              .padding({ left: 12, top: 8 })
              .hitTestBehavior(HitTestMode.None)
              .accessibilityText('开始写作')
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      }
      .width('100%').height('100%')
      .backgroundColor(this.app !== null ? this.colors().editorBg : this.colors().bgPrimary)

      // 手机端浮动字数（桌面/平板已在顶栏显示字数与保存状态，避免重复）
      if (this.app !== null && this.app.editor.hasDoc && !this.app.ui.immersive && !this.app.ui.immersiveEditing && !this.app.ui.isWide) {
        Text((this.app.editor.wordCount) + ' 字')
          .fontSize(12).fontColor(this.colors().textTertiary)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.colors().bgSurface)
          .borderRadius(12)
          .margin({ top: 10, right: 12 })
      }

      if (this.showReplace) {
        this.replacePanel()
      }

      // 沉浸编辑退出入口：桌面窗口头已有「退出专注」，这里只服务平板/手机
      if (this.app !== null && this.app.ui.immersiveEditing && !this.app.ui.usesDesktopChrome) {
        Text('退出专注')
          .fontSize(12).fontColor(this.colors().textSecondary)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.colors().bgSurface)
          .borderRadius(14)
          .margin({ top: 12, right: 12 })
          .hoverEffect(HoverEffect.Highlight)
          .accessibilityText('退出专注模式')
          .onClick(() => {
            if (this.app !== null) {
              this.app.ui.exitImmersiveEditing()
            }
          })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  docTitleRow() {
    if (this.app !== null && this.app.editor.hasDoc) {
      Row() {
        if (this.renaming) {
          TextInput({ text: this.draftTitle })
            .fontSize(15)
            .height(28)
            .width(240)
            .backgroundColor(this.colors().bgSurface)
            .borderRadius(WeaverRadii.XS)
            .onChange((v: string) => { this.draftTitle = v })
            .onSubmit(() => this.commitRename())
            .onBlur(() => this.commitRename())
          Text('完成')
            .fontSize(12).fontColor(this.colors().brand)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.commitRename())
        } else {
          Text(this.app.editor.title !== '' ? this.app.editor.title : '未命名文稿')
            .fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText('文稿标题，点击重命名')
            .onClick(() => this.beginRename())
        }
        Blank()
        Text('⋯')
          .fontSize(16).fontColor(this.colors().textSecondary)
          .width(48).height(36).textAlign(TextAlign.Center)
          .accessibilityText('文稿格式、收藏与排版')
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.openMoreMenu())
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
  }

  private beginRename(): void {
    if (this.app === null) {
      return
    }
    this.draftTitle = this.app.editor.title
    this.renameDocId = this.app.editor.activeId
    this.renaming = true
  }

  private commitRename(): void {
    if (!this.renaming) {
      return
    }
    this.renaming = false
    const app: AppStores | null = this.app
    const ownerId: string = this.renameDocId
    this.renameDocId = ''
    if (app === null || ownerId === '' || app.editor.activeId !== ownerId) {
      return
    }
    const next: string = this.draftTitle.trim()
    if (next === '' || next === app.editor.title) {
      return
    }
    app.renameChapter(ownerId, next)
      .then(() => {
        if (app.editor.activeId === ownerId && this.editorController !== null) {
          this.editorController.focus()
        }
      })
      .catch(() => { this.toast('重命名失败，请重试') })
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
    Column() {
      // 统一空状态版式：一句主文案 + 一句说明 + 一个主行动（居中，留白 24/8/20）
      Text('还没有打开任何文稿')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
      Text('从文稿列表选择一篇，或新建一篇开始写作')
        .fontSize(12).fontColor(this.colors().textTertiary).margin({ top: 8 })
      Button('新建文稿')
        .height(36).fontSize(13).margin({ top: 20 })
        .padding({ left: 20, right: 20 })
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
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
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
