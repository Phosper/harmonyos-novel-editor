// 编辑视图 —— 标签栏 + 工具条 + 正文编辑面
import { promptAction } from '@kit.ArkUI'
import { pasteboard } from '@kit.BasicServicesKit'
import { tokensFor, WeaverColorSet, WeaverRadii, WeaverSpacing, WeaverMobile, paperLineHeightVp, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { fireAndLog } from '../store/AppStores'
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
  /** 查找替换浮层状态 */
  @Local showReplace: boolean = false
  /** 自绘编辑器控制器（格式命令用，T026） */
  @Local editorController: CanvasTextEditorController | null = null
  @Local findText: string = ''
  @Local replaceText: string = ''

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
      if (this.app === null || !this.app.editor.hasDoc) {
        this.emptyState()
      } else {
        // 仅宽屏保留工具条；手机端不常驻状态行（纯纯写作式最小 chrome）
        if (this.app !== null && this.app.ui.isWide) {
          this.toolBar()
        }
        // 仅宽屏保留快捷动作条；手机端动作全部收进 ⋮ 菜单（纯纯写作式最小 chrome）
        if (this.app !== null && this.app.ui.isWide) {
          this.quickBar()
        }
        // 正文编辑面：自绘 FlowText（唯一实现，T037 单引擎收敛）
        TextEditorHost({
            docId: this.app.editor.activeId,
            contentRev: this.app.editor.contentRev,
            typewriter: this.app.ui.typewriter,
            scrollPolicy: this.app.ui.typewriter ? ScrollPolicy.CENTER : ScrollPolicy.NORMAL,
            loadFormat: (docId: string): FormatRun[] => {
              if (this.app === null) {
                return []
              }
              const d: OpenDoc | undefined = this.app.editor.openDocs.find((x: OpenDoc) => x.id === docId)
              return d !== undefined ? FormatCodec.decode(d.runsJson) : []
            },
            onSelectionChange: (start: number, end: number) => {
              // Phase A：仅承载选区态（工具栏态在 US2 使用）
            },
            onFormatChange: (runs: FormatRun[]) => {
              if (this.app !== null) {
                // onEdit persists text and format together.
              }
            },
            onScrollState: (state: number) => {
              if (this.app !== null) {
                this.app.ui.noteScroll(state)
              }
            },
            onControllerReady: (controller: CanvasTextEditorController) => {
              this.editorController = controller
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
            }
          })
            .layoutWeight(1)
      }
      }
      .width('100%').height('100%')
      .backgroundColor(this.app !== null ? this.colors().editorBg : this.colors().bgPrimary)

      // 浮动字数（纯纯写作式：右上角弱化小浮标，不占用正文行）
      if (this.app !== null && this.app.editor.hasDoc && !this.app.ui.immersive) {
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
    }
    .width('100%').height('100%')
  }

  @Builder
  quickBar() {
    Row() {
      Text('撤销').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => { if (this.app !== null) { this.app.editor.undo() } })
      Text('重做').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => { if (this.app !== null) { this.app.editor.redo() } })
      // 行内/段落格式（T026）
      Text('粗').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .onClick(() => this.applyInline(StyleKind.BOLD))
      Text('斜').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .onClick(() => this.applyInline(StyleKind.ITALIC))
      Text('标题').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .onClick(() => this.applyHeading(1))
      Text('排版').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => this.runFormat())
      Text('查找').fontSize(13).fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => this.openReplace())
      // 打字机模式开关：开启后仅当前段保持正文色，其余段落淡化
      Text('打字机').fontSize(13)
        .fontColor(this.app !== null && this.app.ui.typewriter ? this.colors().brand : this.colors().textTertiary)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onClick(() => { if (this.app !== null) { this.app.ui.toggleTypewriter() } })
      Blank()
    }
    .width('100%')
    .height(this.app === null || !this.app.ui.immersive ? 44 : 0)
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.colors().editorBg)
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

  /** 分享所选文本：写入系统剪贴板（可跨应用粘贴）并提示 */
  private shareText(text: string): void {
    if (text === '') {
      this.toast('无选中文本')
      return
    }
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard()
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      board.setData(data).catch(() => {})
    } catch (e) {
      // 忽略：剪贴板不可用时仍给出提示
    }
    this.toast('已复制所选文本，可粘贴分享')
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
      Text('还没有打开任何文稿')
        .fontSize(15).fontColor(this.colors().textSecondary)
      Text('从左侧文稿列表选择一篇，或新建一篇开始写作')
        .fontSize(13).fontColor(this.colors().textTertiary).margin({ top: 8 })
      Button('新建文稿')
        .height(40).fontSize(14).margin({ top: 22 })
        .backgroundColor(this.colors().brand).fontColor(this.colors().onBrand)
        .borderRadius(WeaverRadii.SM)
        .onClick(() => {
          if (this.app !== null) {
            // 建文稿要读聚合、写库，onClick 无法 await → 接住拒绝，避免未处理拒绝杀进程
            fireAndLog(this.app.createChapter(), 'createChapter')
          }
        })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  @Builder
  toolBar() {
    Row() {
      Text((this.app !== null ? this.app.editor.wordCount : 0) + ' 字')
        .fontSize(14).fontColor(this.colors().textSecondary)
      Text(this.saveHintText())
        .fontSize(14)
        .fontColor(this.hintColor())
        .margin({ left: 10 })
        .maxLines(1)
        .onClick(() => this.onSaveHintClick())

      Blank()

      this.formatChip(ChapterFormat.TXT, 'TXT')
      this.formatChip(ChapterFormat.MD, 'MD')
      this.flagText(DocFlag.FAV)
      this.flagText(DocFlag.INSPIRATION)
      Text('撤销')
        .fontSize(14)
        .fontColor(this.app !== null && this.app.editor.canUndo
          ? this.colors().textSecondary : this.colors().textTertiary)
        .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        .margin({ left: 8 })
        .onClick(() => {
          if (this.app !== null) {
            this.app.editor.undo()
          }
        })
      Text('重做')
        .fontSize(14)
        .fontColor(this.app !== null && this.app.editor.canRedo
          ? this.colors().textSecondary : this.colors().textTertiary)
        .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        .margin({ left: 4 })
        .onClick(() => {
          if (this.app !== null) {
            this.app.editor.redo()
          }
        })
    }
    .width('100%').height(WeaverSpacing.TOOLBAR_H)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.colors().toolbarBg)
    .border({ width: { bottom: 1 }, color: this.colors().divider })
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
