// PcEditorZone.ets V2 — Editor zone with press/hover/focus + dual-mode colors
import { PcRadii, PcSpacing, PcInteraction, pcColors, EditorViewMode, type TabItem, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import type { CharacterModel, WorldSettingModel, InspirationModel, RelationshipModel } from '@ohos/common'
import { SaveState } from './WeaverViewModel'
import { IdGenerator } from '@ohos/common'
import { GraphCanvas, type GraphNode, type GraphEdge } from '@ohos/relationship'

@Component
export struct PcEditorZone {
  @StorageLink('colorMode') colorMode: number = 1

  @Prop viewMode: EditorViewMode = EditorViewMode.EMPTY
  @Prop showFindBar: boolean = false
  @State findInputText: string = ''
  @State replaceInputText: string = ''
  @Prop wordCount: number = 0
  @Prop saveStatus: string = '已自动保存'
  @Prop saveState: SaveState = SaveState.IDLE
  @Prop sprintRemaining: number = 1500
  @Prop sprintRunning: boolean = false
  @State isTypewriterMode: boolean = false
  @State isSpotlightMode: boolean = false
  @State isZenMode: boolean = false
  @State showMoreMenu: boolean = false
  @Prop editorTabs: TabItem[] = []
  @Prop editorContent: string = ''
  @Prop isFullscreen: boolean = false
  @Prop selectedDetailType: string = ''
  @Prop chapterIsFav: boolean = false
  @Prop chapterIsInsp: boolean = false
  @Prop chapterIsPrivate: boolean = false
  @Prop isTrashView: boolean = false
  @Prop chapterExpireDays: number = 0
  @Prop characters: CharacterModel[] = []
  @Prop worldSettings: WorldSettingModel[] = []
  @Prop inspirations: InspirationModel[] = []
  @Prop relationships: RelationshipModel[] = []
  onToggleFav: () => void = (): void => { }
  onToggleInsp: () => void = (): void => { }
  onTogglePrivate: () => void = (): void => { }
  onTrashDoc: (chapterId: string) => void = (chapterId: string): void => { chapterId }
  onRestoreDoc: (chapterId: string) => void = (chapterId: string): void => { chapterId }
  onHardDeleteDoc: (chapterId: string) => void = (chapterId: string): void => { chapterId }
  onRenameDoc: (chapterId: string, title: string) => void = (chapterId: string, title: string): void => { chapterId; title }
  onTitleEdited: (docId: string, title: string) => void = (docId: string, title: string): void => { docId; title }
  onSaveChar: (data: CharacterModel) => void = (data: CharacterModel): void => { data }
  onUpdateChar: (data: CharacterModel) => void = (data: CharacterModel): void => { data }
  onDeleteChar: (id: string) => void = (id: string): void => { id }
  onEditCharDetail: (charId: string) => void = (charId: string): void => { charId }
  onDeleteCharDetail: (charId: string) => void = (charId: string): void => { charId }
  onBackToMaterial: () => void = (): void => { }
  onEditWorldDetail: (worldId: string) => void = (worldId: string): void => { worldId }
  onDeleteWorld: (worldId: string) => void = (worldId: string): void => { worldId }
  onUpdateWorld: (id: string, content: string) => void = (id: string, content: string): void => { id; content }
  @State selectedCharId: string = ''
  @State selectedWorldId: string = ''
  @State showCharForm: boolean = false
  @State charFormName: string = ''
  @State charFormType: string = 'support'
  @State charFormAlias: string = ''
  @State charFormAge: string = ''
  @State charFormAppearance: string = ''
  @State charFormPersonality: string = ''
  @State charFormBackground: string = ''
  @State charFormNotes: string = ''
  @State editingCharId: string = ''
  @State isNewChar: boolean = true
  @State showRelForm: boolean = false
  @State relLabel: string = ''
  @State relNotes: string = ''
  @State relFromId: string = ''
  @State relToId: string = ''
  @Prop currentDocId: string = ''
  @State editTitleText: string = ''
  @State editDocId: string = ''
  @State isEditingTitle: boolean = false
  @State matchPositions: number[] = []
  @State currentMatchIndex: number = -1
  @State selectionStart: number = 0
  @State selectionEnd: number = 0
  private textAreaController: TextAreaController = new TextAreaController()
  private scrollController: Scroller = new Scroller()

  // Hover tracking
  @State hoveredToolId: string = ''
  @State hoveredTabId: string = ''
  @State pressedToolId: string = ''
  @Link graphNodes: GraphNode[]
  @Link graphEdges: GraphEdge[]
  @State graphPanX: number = 0
  @State graphPanY: number = 0
  @State graphScale: number = 1
  @State graphSelectedRelId: string = ''
  @State isConnecting: boolean = false
  @State connectFromId: string = ''
  @State contextCharId: string = ''
  @State showRelList: boolean = false
  @State relListItems: GraphEdge[] = []
  @State showGraphMenu: boolean = false
  @State graphMenuX: number = 0
  @State graphMenuY: number = 0
  @State dragTabId: string = ''

  onContentChange: (value: string) => void = (value: string): void => { value }
  onEditorBlur: () => void = (): void => { }
  onToggleFind: () => void = (): void => { }
  onToggleAgent: () => void = (): void => { }
  onNewDoc: () => void = (): void => { }
  onCloseTab: (tabId: string) => void = (tabId: string): void => { tabId }
  onSelectTab: (tabId: string) => void = (tabId: string): void => { tabId }
  onToggleFullscreen: () => void = (): void => { }
  onRetrySave: () => void = (): void => { }
  onUndo: () => void = (): void => { }
  onRedo: () => void = (): void => { }
  onPushUndo: () => void = (): void => { }
  onToggleSprint: () => void = (): void => { }
  onExportTxt: () => void = (): void => { }
  onExportMd: () => void = (): void => { }
  onExportJson: () => void = (): void => { }
  onAddCharacter: () => void = (): void => { }
  onAddWorldSetting: () => void = (): void => { }
  onAddRelation: (fromId: string, toId: string, relType: string, notes: string) => void = (fromId: string, toId: string, relType: string, notes: string): void => { fromId; toId; relType; notes }
  onDeleteRelation: (relId: string) => void = (relId: string): void => { relId }
  onReorderTab: (fromId: string, toId: string) => void = (fromId: string, toId: string): void => { fromId; toId }

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  getNodeColor(charType: string): string {
    if (charType === 'protagonist') return '#E67E22'
    if (charType === 'antagonist') return '#4A4A4A'
    if (charType === 'support') return '#689F63'
    return '#A4CE92'
  }

  getTypeLabel(charType: string): string {
    if (charType === 'protagonist') return '主角'; if (charType === 'antagonist') return '反派'
    if (charType === 'support') return '配角'; if (charType === 'organization') return '组织'
    if (charType === 'location') return '地点'; return charType
  }

  // Find/replace logic
  findAll(query: string): number[] {
    const positions: number[] = []
    if (query.length === 0) return positions
    const content: string = this.editorContent
    let idx: number = 0
    while (idx < content.length) {
      const found: number = content.indexOf(query, idx)
      if (found === -1) break
      positions.push(found)
      idx = found + 1
    }
    return positions
  }

  refreshFindMatches(): void {
    if (this.findInputText.length === 0) {
      this.matchPositions = []
      this.currentMatchIndex = -1
      return
    }
    this.matchPositions = this.findAll(this.findInputText)
    if (this.matchPositions.length > 0) {
      this.currentMatchIndex = 0
      this.textAreaController.caretPosition(this.matchPositions[0])
    } else {
      this.currentMatchIndex = -1
    }
  }

  onFindNext(): void {
    if (this.findInputText.length === 0) return
    if (this.matchPositions.length === 0 || this.currentMatchIndex < 0) {
      this.refreshFindMatches()
      return
    }
    this.currentMatchIndex = (this.currentMatchIndex + 1) % this.matchPositions.length
    this.textAreaController.caretPosition(this.matchPositions[this.currentMatchIndex])
  }

  onFindPrev(): void {
    if (this.findInputText.length === 0) return
    if (this.matchPositions.length === 0 || this.currentMatchIndex < 0) {
      this.refreshFindMatches()
      return
    }
    if (this.currentMatchIndex <= 0) {
      this.currentMatchIndex = this.matchPositions.length - 1
    } else {
      this.currentMatchIndex = this.currentMatchIndex - 1
    }
    this.textAreaController.caretPosition(this.matchPositions[this.currentMatchIndex])
  }

  onReplace(): void {
    if (this.findInputText.length === 0 || this.matchPositions.length === 0 || this.currentMatchIndex < 0) return
    this.onPushUndo()
    const pos: number = this.matchPositions[this.currentMatchIndex]
    const searchLen: number = this.findInputText.length
    const newContent: string = this.editorContent.slice(0, pos) + this.replaceInputText +
      this.editorContent.slice(pos + searchLen)
    this.editorContent = newContent
    this.onContentChange(newContent)
    this.matchPositions = this.findAll(this.findInputText)
    if (this.matchPositions.length > 0) {
      if (this.currentMatchIndex >= this.matchPositions.length) {
        this.currentMatchIndex = 0
      }
      this.textAreaController.caretPosition(this.matchPositions[this.currentMatchIndex])
    } else {
      this.currentMatchIndex = -1
    }
  }

  onReplaceAll(): void {
    if (this.findInputText.length === 0) return
    this.onPushUndo()
    const searchStr: string = this.findInputText
    const replaceStr: string = this.replaceInputText
    const parts: string[] = this.editorContent.split(searchStr)
    const newContent: string = parts.join(replaceStr)
    const count: number = parts.length - 1
    this.editorContent = newContent
    this.onContentChange(newContent)
    this.matchPositions = []
    this.currentMatchIndex = -1
  }

  getFindCounter(): string {
    if (this.matchPositions.length === 0 || this.currentMatchIndex < 0) return '0/0'
    return (this.currentMatchIndex + 1) + '/' + this.matchPositions.length
  }

  // Text formatting methods
  applyBold(): void {
    this.onPushUndo()
    this.wrapSelectionWith('**', '**')
  }

  applyItalic(): void {
    this.onPushUndo()
    this.wrapSelectionWith('*', '*')
  }

  applyUnderline(): void {
    this.onPushUndo()
    this.wrapSelectionWith('__', '__')
  }

  private wrapSelectionWith(prefix: string, suffix: string): void {
    const start: number = this.selectionStart
    const end: number = this.selectionEnd
    if (start === end) {
      const newContent: string = this.editorContent.slice(0, start) + prefix + suffix +
        this.editorContent.slice(start)
      this.editorContent = newContent
      this.onContentChange(newContent)
      this.textAreaController.caretPosition(start + prefix.length)
      return
    }
    const selectedText: string = this.editorContent.slice(start, end)
    const newContent: string = this.editorContent.slice(0, start) + prefix + selectedText +
      suffix + this.editorContent.slice(end)
    this.editorContent = newContent
    this.onContentChange(newContent)
    this.textAreaController.caretPosition(end + prefix.length + suffix.length)
  }

  applyHeading(level: number): void {
    this.onPushUndo()
    const content: string = this.editorContent
    const pos: number = this.selectionStart
    let lineStart: number = pos
    while (lineStart > 0 && content.charAt(lineStart - 1) !== '\n') {
      lineStart = lineStart - 1
    }
    let lineEnd: number = pos
    while (lineEnd < content.length && content.charAt(lineEnd) !== '\n') {
      lineEnd = lineEnd + 1
    }
    const line: string = content.slice(lineStart, lineEnd)
    const prefix: string = '#'.repeat(level) + ' '
    let newLine: string
    if (line.startsWith(prefix)) {
      newLine = line.slice(prefix.length)
    } else if (line.startsWith('# ')) {
      newLine = prefix + line.slice(2)
    } else if (line.startsWith('## ')) {
      newLine = prefix + line.slice(3)
    } else if (line.startsWith('### ')) {
      newLine = prefix + line.slice(4)
    } else {
      newLine = prefix + line
    }
    const newContent: string = content.slice(0, lineStart) + newLine + content.slice(lineEnd)
    this.editorContent = newContent
    this.onContentChange(newContent)
  }

  applyQuote(): void {
    this.onPushUndo()
    this.applyLinePrefix('> ')
  }

  applyBulletList(): void {
    this.onPushUndo()
    this.applyLinePrefix('- ')
  }

  private applyLinePrefix(prefix: string): void {
    const content: string = this.editorContent
    const start: number = this.selectionStart
    const end: number = this.selectionEnd
    let lineStart: number = start
    while (lineStart > 0 && content.charAt(lineStart - 1) !== '\n') {
      lineStart = lineStart - 1
    }
    let lineEnd: number = end
    while (lineEnd < content.length && content.charAt(lineEnd) !== '\n') {
      lineEnd = lineEnd + 1
    }
    const selectedBlock: string = content.slice(lineStart, lineEnd)
    const lines: string[] = selectedBlock.split('\n')
    const newLines: string[] = []
    for (let i: number = 0; i < lines.length; i++) {
      const singleLine: string = lines[i]
      if (singleLine.startsWith(prefix)) {
        newLines.push(singleLine.slice(prefix.length))
      } else {
        newLines.push(prefix + singleLine)
      }
    }
    const newContent: string = content.slice(0, lineStart) + newLines.join('\n') + content.slice(lineEnd)
    this.editorContent = newContent
    this.onContentChange(newContent)
  }

  stripLinePrefixes(): void {
    this.onPushUndo()
    const content: string = this.editorContent
    const pos: number = this.selectionStart
    let lineStart: number = pos
    while (lineStart > 0 && content.charAt(lineStart - 1) !== '\n') {
      lineStart = lineStart - 1
    }
    let lineEnd: number = pos
    while (lineEnd < content.length && content.charAt(lineEnd) !== '\n') {
      lineEnd = lineEnd + 1
    }
    let line: string = content.slice(lineStart, lineEnd)
    const prefixes: string[] = ['### ', '## ', '# ', '> ', '- ']
    for (let i: number = 0; i < prefixes.length; i++) {
      const pfx: string = prefixes[i]
      if (line.startsWith(pfx)) {
        line = line.slice(pfx.length)
        break
      }
    }
    const newContent: string = content.slice(0, lineStart) + line + content.slice(lineEnd)
    this.editorContent = newContent
    this.onContentChange(newContent)
  }

  @Builder buildTabBar() {
    Row() {
      Button() {
        Image($rawfile(this.isFullscreen ? 'arrow_down_right_and_arrow_up_left.svg' : 'arrow_up_left_and_arrow_down_right.svg'))
          .width(16).height(16)
      }
      .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
      .stateStyles({
        pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'fullscreen' : '' })
      .backgroundColor(this.hoveredToolId === 'fullscreen' ? '#0D000000' : Color.Transparent)
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .focusable(true)
      
      .margin({ left: 4, right: 4 }).onClick(() => { this.onToggleFullscreen() })

      Scroll() {
        Row({ space: 2 }) {
          ForEach(this.editorTabs, (tab: TabItem) => {
            Row() {
              Text(tab.title).fontSize(13)
                .fontColor(tab.active ? this.getColors().TEXT_PRIMARY : this.getColors().TEXT_SECONDARY)
                .fontWeight(tab.active ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ minWidth: 60, maxWidth: 180 })
              if (tab.dirty) { Text(' ●').fontSize(10).fontColor(this.getColors().EMPHASIZE) }
              if (!tab.pinned) {
                Button() { Text('×').fontSize(12).fontColor(this.getColors().TEXT_TERTIARY).accessibilityText('关闭标签') }
                .width(22).height(22).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
                .stateStyles({
                  pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
                  normal: { .backgroundColor(Color.Transparent) }
                })
                .onHover((isHover: boolean) => { this.hoveredTabId = isHover ? 'close_' + tab.id : '' })
                .backgroundColor(this.hoveredTabId === 'close_' + tab.id ? this.getColors().HOVER_BG : Color.Transparent)
                .animation({ duration: PcInteraction.HOVER_DURATION })
                .onClick(() => { this.onCloseTab(tab.id) })
              }
            }
            .height(30).padding({ left: 10, right: 4 }).borderRadius(PcRadii.SM)
            .backgroundColor(
              this.hoveredTabId === tab.id ? this.getColors().HOVER_BG :
              tab.active ? this.getColors().BG_SECONDARY : Color.Transparent
            )
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.hoveredTabId = tab.id }
              else { this.hoveredTabId = '' }
            })
            .onHover((isHover: boolean) => { this.hoveredTabId = isHover ? tab.id : '' })
            .animation({ duration: PcInteraction.HOVER_DURATION })
            .focusable(true)
            
            .draggable(true)
            .onDragStart((event: DragEvent, extraParams: string): DragItemInfo => {
              this.dragTabId = tab.id
              return { pixelMap: undefined, extraInfo: tab.id }
            })
            .onDrop((event: DragEvent, extraParams: string): void => {
              if (this.dragTabId !== '' && this.dragTabId !== tab.id) {
                this.onReorderTab(this.dragTabId, tab.id)
              }
              this.dragTabId = ''
            })
            .onClick(() => { this.onSelectTab(tab.id) }).margin({ top: 2, bottom: 2 })
            .gesture(
              TapGesture({ count: 2 })
                .onAction(() => {
                  this.editTitleText = tab.title
                  this.editDocId = tab.id
                })
            )
          }, (tab: TabItem): string => tab.id)
        }.padding({ left: 4, right: 8 }).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%').height(36).justifyContent(FlexAlign.Start).backgroundColor(this.getColors().TOOLBAR_BG)
    .hitTestBehavior(HitTestMode.Default)
    .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
  }

  @Builder buildFindBar() {
    Row({ space: 8 }) {
      Text('⌕').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY)
      TextInput({ text: $$this.findInputText, placeholder: '查找' }).fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).width(170).height(34)
        .onChange(() => { this.refreshFindMatches() })
      Text(this.getFindCounter()).fontSize(12).fontColor(this.getColors().TEXT_TERTIARY)
      Button('↑').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
        })
        .focusable(true)
        .borderRadius(PcRadii.SM).height(30).padding({ left: 10, right: 10 })
        .onClick(() => { this.onFindPrev() })
      Button('↓').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
        })
        .focusable(true)
        .borderRadius(PcRadii.SM).height(30).padding({ left: 10, right: 10 })
        .onClick(() => { this.onFindNext() })
      TextInput({ text: $$this.replaceInputText, placeholder: '替换为' }).fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).width(170).height(34)
      Button('替换').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
        })
        .focusable(true)
        .borderRadius(PcRadii.SM).height(30).padding({ left: 10, right: 10 })
        .onClick(() => { this.onReplace() })
      Button('全部').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
        .backgroundColor(this.getColors().BG_SECONDARY).border({ width: 1, color: this.getColors().DIVIDER })
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
        })
        .focusable(true)
        .borderRadius(PcRadii.SM).height(30).padding({ left: 10, right: 10 })
        .onClick(() => { this.onReplaceAll() })
      Blank()
      Button() { Text('✕').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY).accessibilityText('关闭查找') }
      .backgroundColor(Color.Transparent).height(30).padding({ left: 8, right: 8 })
      .stateStyles({
        pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'findclose' : '' })
      .backgroundColor(this.hoveredToolId === 'findclose' ? this.getColors().HOVER_BG : Color.Transparent)
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .focusable(true)
      
      .onClick(() => { this.onToggleFind() })
    }.width('100%').height(44).padding({ left: 16, right: 16 })
    .backgroundColor(this.getColors().BG_SECONDARY).border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: -44 }).combine(TransitionEffect.OPACITY)
        .animation({ duration: 200, curve: Curve.FastOutSlowIn }),
      TransitionEffect.translate({ y: -44 }).combine(TransitionEffect.OPACITY)
        .animation({ duration: 150, curve: Curve.FastOutLinearIn })
    ))
  }

  @Builder buildEmptyView() {
    Column() {
      Column() {
        Text('✎').fontSize(48).fontColor(this.getColors().EMPHASIZE_FADED)
      }
      .width(160).height(160).borderRadius(80)
      .backgroundColor(this.getColors().EMPHASIZE_FADED)
      .justifyContent(FlexAlign.Center).margin({ bottom: 24 })

      Text('没有打开的文稿').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().TEXT_PRIMARY).margin({ bottom: 6 })

      Text('从左侧列表选择一份开始阅读')
        .fontSize(14).fontColor(this.getColors().TEXT_SECONDARY).margin({ bottom: 4 })
      Text('或点击「+ 新建文稿」开始写作')
        .fontSize(14).fontColor(this.getColors().TEXT_SECONDARY).margin({ bottom: 32 })

      Button('+ 新建文稿')
        .fontSize(14).fontColor(this.getColors().EMPHASIZE)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.getColors().DIVIDER, style: BorderStyle.Dashed })
        .borderRadius(PcRadii.MD)
        .padding({ left: 24, right: 24, top: 10, bottom: 10 })
        .onClick(() => { this.onNewDoc() })
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).backgroundColor(this.getColors().EDITOR_BG)
  }

  @Builder buildEditorView() {
    Scroll(this.scrollController) {
      TextArea({ text: $$this.editorContent, placeholder: '开始写作...', controller: this.textAreaController })
        .fontSize(16).fontColor(this.getColors().TEXT_PRIMARY).placeholderColor(this.getColors().TEXT_TERTIARY)
        .backgroundColor(this.isSpotlightMode ? this.getColors().EDITOR_BG : this.getColors().EDITOR_BG)
        .opacity(this.isSpotlightMode ? 0.4 : 1.0)
        .width('100%').height('100%')
        .padding({ left: 48, right: 48, top: 24, bottom: this.isTypewriterMode ? '50%' : 48 })
        .onChange((value: string) => { this.onContentChange(value) })
        .onBlur(() => { this.onEditorBlur() })
        .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
          this.selectionStart = selectionStart
          this.selectionEnd = selectionEnd
          if (this.isTypewriterMode) {
            this.scrollController.scrollEdge(Edge.Top)
          }
        })
    }.scrollBar(BarState.Auto).width('100%').layoutWeight(1).backgroundColor(this.getColors().EDITOR_BG)
  }

  @Builder buildMaterialView() {
    Column() {
      Row() {
        Text('人物').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
      }.width('100%').padding({ left: 44, right: 44 }).margin({ top: 18, bottom: 12 })

      Scroll() {
        Grid() {
          ForEach(this.characters, (char: CharacterModel) => {
            GridItem() {
              Column({ space: 0 }) {
                Row() { Text('👤').fontSize(18) }.width(46).height(46).borderRadius(23)
                  .backgroundColor(this.getNodeColor(char.characterType))
                  .justifyContent(FlexAlign.Center).margin({ bottom: 12 })
                Text(char.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ bottom: 5 })
                Text(char.personality !== '' ? char.personality : char.notes).fontSize(13)
                  .fontColor(this.getColors().TEXT_SECONDARY).maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(1.6)
                  .constraintSize({ maxHeight: 62 })
                if (char.characterType !== '') {
                  Text(this.getTypeLabel(char.characterType)).fontSize(10).fontColor(this.getColors().TEXT_SECONDARY)
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 }).borderRadius(PcRadii.SM)
                    .backgroundColor(this.getColors().BG_PRIMARY).margin({ top: 8 })
                }
              }.width('100%').padding(18).backgroundColor(this.getColors().BG_SECONDARY)
              .border({ width: 1, color: this.getColors().DIVIDER }).borderRadius(PcRadii.MD)
              .onMouse((event: MouseEvent) => {
                if (event.button === MouseButton.Right) {
                  this.selectedCharId = char.id
                }
              })
              .bindContextMenu(this.buildCharMenu, ResponseType.RightClick)
            }
          }, (char: CharacterModel): string => char.id)
          GridItem() {
            Column() { Text('+').fontSize(24).fontColor(this.getColors().TEXT_TERTIARY) }
            .width('100%').height(150).justifyContent(FlexAlign.Center)
            .border({ width: 1, color: this.getColors().DIVIDER, style: BorderStyle.Dashed })
            .borderRadius(PcRadii.MD).backgroundColor(Color.Transparent)
            .onClick(() => { this.openNewCharForm() })
          }
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(14).rowsGap(14)
        .padding({ left: 44, right: 44, bottom: 18 })
        .width('100%')
      }
      .scrollBar(BarState.Auto).layoutWeight(1)
      .bindPopup($$this.showCharForm, { builder: this.buildCharForm })

      Row() {
        Text('世界观').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
      }.width('100%').padding({ left: 44, right: 44 }).margin({ top: 18, bottom: 12 })

      Scroll() {
        Grid() {
          ForEach(this.worldSettings, (ws: WorldSettingModel) => {
            GridItem() {
              Column({ space: 0 }) {
                Row() { Text('🌐').fontSize(18) }.width(46).height(46).borderRadius(23)
                  .backgroundColor('#5B84C4').justifyContent(FlexAlign.Center).margin({ bottom: 12 })
                Text(ws.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
                  .margin({ bottom: 5 })
                Text(ws.description !== '' ? ws.description : ws.notes).fontSize(13)
                  .fontColor(this.getColors().TEXT_SECONDARY).maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(1.6)
                  .constraintSize({ maxHeight: 62 })
                if (ws.category !== '') {
                  Text(ws.category).fontSize(10).fontColor(this.getColors().TEXT_SECONDARY)
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 }).borderRadius(PcRadii.SM)
                    .backgroundColor(this.getColors().BG_PRIMARY).margin({ top: 8 })
                }
              }.width('100%').padding(18).backgroundColor(this.getColors().BG_SECONDARY)
              .border({ width: 1, color: this.getColors().DIVIDER }).borderRadius(PcRadii.MD)
              .onClick((): void => {
                this.showCharForm = false
                this.selectedWorldId = ws.id
                this.charFormNotes = ws.content
                this.onEditWorldDetail(ws.id)
              })
              .onMouse((event: MouseEvent) => {
                if (event.button === MouseButton.Right) {
                  this.selectedWorldId = ws.id
                }
              })
              .bindContextMenu(this.buildWorldMenu, ResponseType.RightClick)
            }
          }, (ws: WorldSettingModel): string => ws.id)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(14).rowsGap(14)
        .padding({ left: 44, right: 44, bottom: 18 })
        .width('100%')
      }
      .scrollBar(BarState.Auto).layoutWeight(1)
    }
    .width('100%').layoutWeight(1)
  }

      @Builder buildGraphView() {
    Stack() {
      Column() {
        Row() {
          Text('人物关系图').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
          Blank()
          Text('拖动/滚轮缩放').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
        }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 8 })
        GraphCanvas({
          nodes: $graphNodes, edges: $graphEdges,
          panOffsetX: $graphPanX, panOffsetY: $graphPanY,
          canvasScale: $graphScale, selectedRelId: $graphSelectedRelId,
          isConnecting: $isConnecting, connectFromId: $connectFromId,
          onNodeTap: (charId: string): void => { this.onGraphNodeTap(charId) },
        onNodeRightClick: (charId: string, x: number, y: number): void => {
          console.info('[menu] onNodeRightClick charId:', charId, 'showGraphMenu:', this.showGraphMenu)
          this.contextCharId = charId
          this.graphMenuX = x
          this.graphMenuY = y
          this.showGraphMenu = false
          animateTo({ duration: 0 }, () => {
            this.showGraphMenu = true
          })
          console.info('[menu] after set showGraphMenu:', this.showGraphMenu)
        },
          onDoubleTapCanvas: (): void => { this.cancelConnecting() },
          onBlankTap: (): void => { this.cancelConnecting() }
        })
        .width('100%').layoutWeight(1)
        .backgroundColor(this.getColors().EDITOR_BG).border({ width: { top: 1 }, color: this.getColors().DIVIDER })
      }
      .width('100%').layoutWeight(1)

      if (this.showGraphMenu) {
        Column() {
          this.buildGraphNodeMenu()
        }
        .position({ x: this.graphMenuX + 8, y: this.graphMenuY + 8 })
        .onClick(() => { this.showGraphMenu = false })
      }

      if (this.showRelForm) {
        Column() {
          Column() {
            this.buildRelForm()
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#40000000')
        .onClick(() => { this.cancelConnecting(); this.showRelForm = false })
      }

      if (this.showRelList) {
        Column() {
          Column() {
            this.buildRelListView()
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#40000000')
        .onClick(() => { this.showRelList = false })
      }
    }
    .width('100%').layoutWeight(1)
  }

  @Builder buildToolbar() {
    Scroll() {
      Row({ space: 1 }) {
        Button('H1').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'H1' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'H1' ? this.getColors().HOVER_BG : this.getColors().BG_PRIMARY
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'H1' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'H1' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyHeading(1) })
        Button('H2').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'H2' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'H2' ? this.getColors().HOVER_BG : this.getColors().BG_PRIMARY
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'H2' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'H2' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyHeading(2) })
        Button('H3').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'H3' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'H3' ? this.getColors().HOVER_BG : this.getColors().BG_PRIMARY
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'H3' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'H3' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyHeading(3) })
        Button('¶').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'P' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'P' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'P' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'P' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.stripLinePrefixes() })
        Divider().vertical(true).height(22).margin({ left: 6, right: 6 }).color(this.getColors().TEXT_TERTIARY)
        Button('B').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'B' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'B' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'B' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'B' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyBold() })
        Button('I').fontSize(13).fontStyle(FontStyle.Italic).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'I' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'I' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'I' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'I' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyItalic() })
        Button('U').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'U' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'U' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'U' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'U' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyUnderline() })
        Divider().vertical(true).height(22).margin({ left: 6, right: 6 }).color(this.getColors().TEXT_TERTIARY)
        Button('" "').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'quote' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'quote' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'quote' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'quote' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyQuote() })
        Button('• 列表').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(
            this.pressedToolId === 'list' ? this.getColors().CLICK_EFFECT :
            this.hoveredToolId === 'list' ? this.getColors().HOVER_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedToolId = 'list' }
            else { this.pressedToolId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'list' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onClick(() => { this.applyBulletList() })
        Divider().vertical(true).height(22).margin({ left: 6, right: 6 }).color(this.getColors().TEXT_TERTIARY)
        Blank()
        Button('▸ 更多').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
          .backgroundColor(Color.Transparent)
          .borderRadius(PcRadii.SM).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'more' : '' })
          .backgroundColor(this.hoveredToolId === 'more' ? this.getColors().HOVER_BG : Color.Transparent)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .bindPopup(this.showMoreMenu, {
            builder: this.buildMoreMenu,
            placement: Placement.TopLeft,
            onStateChange: (e) => { this.showMoreMenu = e.isVisible }
          })
          .onClick(() => {
            this.showMoreMenu = !this.showMoreMenu
          })
      }.padding({ left: 14, right: 14, top: 4, bottom: 4 })
    }    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .height(PcSpacing.TOOLBAR_H).backgroundColor(this.getColors().TOOLBAR_BG)
    .hitTestBehavior(HitTestMode.Default)
    .border({ width: { top: 1 }, color: this.getColors().DIVIDER })
  }

  getSprintTimeText(): string {
    const mins: number = Math.floor(this.sprintRemaining / 60)
    const secs: number = this.sprintRemaining % 60
    const secsStr: string = secs < 10 ? '0' + secs : secs.toString()
    return mins + ':' + secsStr
  }

  @Builder buildStatusBar() {
    Row({ space: 20 }) {
      Text(this.wordCount.toString() + ' 字').fontSize(12).fontColor(this.getColors().TEXT_TERTIARY)
      if (this.sprintRunning) {
        Row({ space: 6 }) {
          Circle({ width: 7, height: 7 }).fill(this.getColors().EMPHASIZE)
          Text('⏱ ' + this.getSprintTimeText()).fontSize(12).fontColor(this.getColors().EMPHASIZE)
        }
      }
      Row({ space: 6 }) {
        if (this.saveState === SaveState.IDLE) {
          Circle({ width: 7, height: 7 }).fill(this.getColors().EMPHASIZE)
        } else if (this.saveState === SaveState.SAVING) {
          Circle({ width: 7, height: 7 }).fill(this.getColors().WARNING)
        } else {
          Circle({ width: 7, height: 7 }).fill(this.getColors().DANGER)
        }
        Text(this.saveStatus).fontSize(12)
          .fontColor(this.saveState === SaveState.FAILED ? this.getColors().DANGER : this.getColors().TEXT_TERTIARY)
      }
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.hoveredToolId = 'save' }
        else { this.hoveredToolId = '' }
      })
      .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'save' : '' })
      .backgroundColor(this.hoveredToolId === 'save' ? this.getColors().HOVER_BG : Color.Transparent)
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .onClick(() => {
        if (this.saveState === SaveState.FAILED) {
          this.onRetrySave()
        }
      })
    }.width('100%').height(PcSpacing.STATUSBAR_H).justifyContent(FlexAlign.End).padding({ right: 16 })
    .backgroundColor(this.getColors().TOOLBAR_BG)
    .border({ width: { top: 1 }, color: this.getColors().DIVIDER })
  }

  @Builder buildMoreMenu() {
    Column({ space: 2 }) {
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('undo.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('撤销').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onUndo() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('redo.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('重做').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onRedo() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile(this.sprintRunning ? 'record_circle.svg' : 'stopwatch.svg'))
            .width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text(this.sprintRunning ? '停止专注' : '专注写作').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onToggleSprint() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('paintbrush_fill.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('写作伴侣').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onToggleAgent() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('celiakeyboard_elevate.svg')).width(14).height(14)
            .fillColor(this.isTypewriterMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
          Text('打字机').fontSize(13)
            .fontColor(this.isTypewriterMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        }
      }
        .fontColor(this.isTypewriterMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.isTypewriterMode = !this.isTypewriterMode })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('livephoto.svg')).width(14).height(14)
            .fillColor(this.isSpotlightMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
          Text('聚焦').fontSize(13)
            .fontColor(this.isSpotlightMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        }
      }
        .fontColor(this.isSpotlightMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.isSpotlightMode = !this.isSpotlightMode })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('save.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('导出 TXT').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportTxt() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('save.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('导出 MD').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportMd() })
      Button() {
        Row({ space: 8 }) {
          Image($rawfile('save.svg')).width(14).height(14).fillColor(this.getColors().TEXT_PRIMARY)
          Text('导出 JSON').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        }
      }
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportJson() })
    }
    .width(160).padding({ top: 8, bottom: 8 })
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: 1, color: this.getColors().DIVIDER }).borderRadius(PcRadii.SM)
  }

  @Builder buildDocActionBar() {
    Row({ space: 4 }) {
      Blank()

      if (this.isTrashView) {
        if (this.chapterExpireDays > 0) {
          Text('还剩 ' + this.chapterExpireDays.toString() + ' 天自动删除')
            .fontSize(11).fontColor('#757575')
        }
        Blank()

        Button() { Image($rawfile('undo.svg')).width(16).height(16).fillColor(this.getColors().EMPHASIZE) }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'restore' : '' })
        .backgroundColor(this.hoveredToolId === 'restore' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onRestoreDoc(this.getActiveTabId()) })

        Divider().vertical(true).height(16).color(this.getColors().DIVIDER)

        Button() { Text('✕').fontSize(14).fontColor('#FA2A2D') }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'delete' : '' })
        .backgroundColor(this.hoveredToolId === 'delete' ? '#19FA2A2D' : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onHardDeleteDoc(this.getActiveTabId()) })
      } else {
        Button() {
          Image($rawfile(this.chapterIsFav ? 'star_fill.svg' : 'star.svg'))
            .width(16).height(16)
            .fillColor(this.chapterIsFav ? this.getColors().EMPHASIZE : this.getColors().TEXT_TERTIARY)
        }
          .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'fav' : '' })
        .backgroundColor(this.hoveredToolId === 'fav' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onToggleFav() })

        Divider().vertical(true).height(16).color(this.getColors().DIVIDER)

        Button() {
          Image($rawfile(this.chapterIsInsp ? 'lightbulb.svg' : 'lightbulb_slash.svg'))
            .width(16).height(16)
            .fillColor(this.chapterIsInsp ? this.getColors().EMPHASIZE : this.getColors().TEXT_TERTIARY)
        }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'insp' : '' })
        .backgroundColor(this.hoveredToolId === 'insp' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onToggleInsp() })

        Divider().vertical(true).height(16).color(this.getColors().DIVIDER)

        Button() {
          Image($rawfile(this.chapterIsPrivate ? 'lock_fill.svg' : 'lock_open_fill.svg'))
            .width(16).height(16)
            .fillColor(this.chapterIsPrivate ? this.getColors().EMPHASIZE : this.getColors().TEXT_TERTIARY)
        }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'priv' : '' })
        .backgroundColor(this.hoveredToolId === 'priv' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onTogglePrivate() })

        Divider().vertical(true).height(16).color(this.getColors().DIVIDER)

        Button() { Image($rawfile('trash_fill.svg')).width(16).height(16).fillColor(this.getColors().TEXT_TERTIARY) }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'trash' : '' })
        .backgroundColor(this.hoveredToolId === 'trash' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onTrashDoc(this.getActiveTabId()) })
      }
    }
    .width('100%').height(36).padding({ left: 12, right: 12 })
    .backgroundColor(this.getColors().TOOLBAR_BG)
    .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
  }

  @Builder buildCharMenu() {
    Menu() {
      MenuItem({ content: '✏️ 编辑人物' })
        .onClick((): void => {
          this.showCharForm = false
          const ch: CharacterModel | undefined = this.characters.find((c: CharacterModel) => c.id === this.selectedCharId)
          if (ch !== undefined) {
            this.populateCharDetail(ch)
          }
          this.onEditCharDetail(this.selectedCharId)
        })
      MenuItem({ content: '删除人物' })
        .onClick((): void => { this.onDeleteCharDetail(this.selectedCharId) })
    }
  }

  @Builder buildWorldMenu() {
    Menu() {
      MenuItem({ content: '✏️ 编辑世界观' })
        .onClick((): void => { this.showCharForm = false; this.onEditWorldDetail(this.selectedWorldId) })
      MenuItem({ content: '删除世界观' })
        .onClick((): void => { this.onDeleteWorld(this.selectedWorldId) })
    }
  }

  @Builder buildRelForm() {
    Column({ space: 12 }) {
      Text('添加关系').fontSize(16).fontWeight(FontWeight.Bold)
      TextInput({ text: $$this.relLabel, placeholder: '关系类型（如：师徒、敌对、恋人）' })
      TextInput({ text: $$this.relNotes, placeholder: '备注（可选）' })
      Row({ space: 8 }) {
        Button('取消').onClick(() => { this.cancelConnecting(); this.showRelForm = false })
        Button('添加')
          .fontColor('#007DFF')
          .backgroundColor('#FFFFFF')
          .onClick(() => { this.confirmAddRel() })
      }
    }.width(280).padding(16)
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: 1, color: this.getColors().DIVIDER })
    .borderRadius(PcRadii.MD)
  }

  @Builder buildGraphNodeMenu() {
    Column() {
      Row() {
        Text('➕ 添加关系').fontSize(14).fontColor(this.getColors().TEXT_PRIMARY)
      }.padding(12).width('100%')
      .onClick((): void => {
        this.showGraphMenu = false
        this.startConnecting(this.contextCharId)
      })
      Row() {
        Text('删除关系').fontSize(14).fontColor(this.getColors().TEXT_PRIMARY)
      }.padding(12).width('100%')
      .onClick((): void => {
        this.showGraphMenu = false
        this.showRelationsForNode(this.contextCharId)
      })
    }.width(160).padding(4)
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: 1, color: this.getColors().DIVIDER })
    .borderRadius(PcRadii.MD)
  }

  @Builder buildRelListView() {
    Column({ space: 8 }) {
      Text('删除关系').fontSize(16).fontWeight(FontWeight.Bold)
      ForEach(this.relListItems, (item: GraphEdge) => {
        Row() {
          Text(this.getCharName(item.fromId) + ' ➜ ' + this.getCharName(item.toId) + '  ' + item.type)
            .fontSize(13).fontColor(this.getColors().TEXT_PRIMARY).layoutWeight(1)
          Button('删除').fontSize(12).fontColor('#FA2A2D')
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.confirmDeleteRel(item.id) })
        }.width('100%').padding(8)
      }, (item: GraphEdge): string => item.id)
      Button('关闭').fontSize(13).width('100%')
        .onClick(() => { this.showRelList = false })
    }
    .width(320).padding(16)
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: 1, color: this.getColors().DIVIDER })
    .borderRadius(PcRadii.MD)
  }

  confirmAddRel(): void {
    if (this.relLabel.trim() === '') return
    this.onAddRelation(this.connectFromId, this.relToId, this.relLabel, this.relNotes)
    this.showRelForm = false
    this.cancelConnecting()
  }

  startConnecting(charId: string): void {
    this.isConnecting = true
    this.connectFromId = charId
  }

  cancelConnecting(): void {
    this.isConnecting = false
    this.connectFromId = ''
  }

  onGraphNodeTap(charId: string): void {
    if (this.isConnecting && charId !== this.connectFromId) {
      this.relToId = charId
      this.relLabel = ''
      this.relNotes = ''
      this.isConnecting = false
      this.showRelForm = true
    }
  }

  showRelationsForNode(charId: string): void {
    const items: GraphEdge[] = []
    for (let i: number = 0; i < this.graphEdges.length; i++) {
      if (this.graphEdges[i].fromId === charId || this.graphEdges[i].toId === charId) {
        items.push(this.graphEdges[i])
      }
    }
    this.relListItems = items
    this.showRelList = true
  }

  confirmDeleteRel(relId: string): void {
    AlertDialog.show({
      title: '确认删除',
      message: '确定要删除该关系吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#FA2A2D',
        action: (): void => {
          this.onDeleteRelation(relId)
          this.showRelList = false
        }
      }
    })
  }

  getCharName(charId: string): string {
    const ch: CharacterModel | undefined = this.characters.find((c: CharacterModel) => c.id === charId)
    return ch !== undefined ? ch.name : ''
  }

  getEditingChar(): CharacterModel | undefined {
    return this.characters.find((c: CharacterModel) => c.id === this.selectedCharId)
  }

  getEditingWorld(): WorldSettingModel | undefined {
    return this.worldSettings.find((w: WorldSettingModel) => w.id === this.selectedWorldId)
  }

  @Builder buildWorldDetailView() {
    Column({ space: 12 }) {
      Row() {
        Button('← 返回').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showCharForm = false; this.onBackToMaterial() })
        Blank()
      }.width('100%').padding(16)

      Text(this.getEditingWorld()?.name ?? '世界观').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().TEXT_PRIMARY).padding({ left: 16, right: 16 })

      TextArea({ text: $$this.charFormNotes, placeholder: '输入世界观内容...' })
        .fontSize(15).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).width('100%').layoutWeight(1)
        .padding(16)
        .onChange((value: string) => {
          if (this.selectedWorldId !== '') {
            this.onUpdateWorld(this.selectedWorldId, value)
          }
        })
    }
    .width('100%').layoutWeight(1).backgroundColor(this.getColors().EDITOR_BG)
  }

  @Builder buildCharDetailView() {
    Column({ space: 12 }) {
      Row() {
        Button('← 返回').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showCharForm = false; this.onBackToMaterial() })
        Blank()
      }.width('100%').padding(16)

      TextInput({ text: $$this.charFormName, placeholder: '姓名' })
        .fontSize(16).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormAlias, placeholder: '别名' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormAge, placeholder: '年龄' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormAppearance, placeholder: '外貌' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormPersonality, placeholder: '性格' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormBackground, placeholder: '背景' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      TextInput({ text: $$this.charFormNotes, placeholder: '备注' })
        .fontSize(14).width('100%').height(44)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      Button('保存').fontSize(14).fontColor('#FFFFFF')
        .backgroundColor(this.getColors().EMPHASIZE).borderRadius(PcRadii.SM)
        .width('100%').height(44)
        .onClick(() => {
          if (this.charFormName.trim() === '') return
          const model: CharacterModel = {
            id: this.selectedCharId,
            bookId: '',
            name: this.charFormName.trim(),
            alias: this.charFormAlias.trim(),
            age: this.charFormAge.trim(),
            appearance: this.charFormAppearance.trim(),
            personality: this.charFormPersonality.trim(),
            background: this.charFormBackground.trim(),
            notes: this.charFormNotes.trim(),
            characterType: 'support'
          }
          this.onUpdateChar(model)
          this.onBackToMaterial()
        })
    }
    .width('100%').layoutWeight(1).backgroundColor(this.getColors().EDITOR_BG)
  }

  resetCharForm(): void {
    this.charFormName = ''
    this.charFormType = 'support'
    this.charFormAlias = ''
    this.charFormAge = ''
    this.charFormAppearance = ''
    this.charFormPersonality = ''
    this.charFormBackground = ''
    this.charFormNotes = ''
    this.editingCharId = ''
  }

  openNewCharForm(): void {
    this.isNewChar = true
    this.resetCharForm()
    this.showCharForm = true
  }

  populateCharDetail(ch: CharacterModel): void {
    this.isNewChar = false
    this.editingCharId = ch.id
    this.charFormName = ch.name
    this.charFormType = ch.characterType
    this.charFormAlias = ch.alias
    this.charFormAge = ch.age
    this.charFormAppearance = ch.appearance
    this.charFormPersonality = ch.personality
    this.charFormBackground = ch.background
    this.charFormNotes = ch.notes
  }

  openEditCharForm(ch: CharacterModel): void {
    this.populateCharDetail(ch)
    this.showCharForm = true
  }

  saveChar(): void {
    if (this.charFormName.trim() === '') return
    const model: CharacterModel = {
      id: this.isNewChar ? IdGenerator.generate() : this.editingCharId,
      bookId: '',
      name: this.charFormName.trim(),
      alias: this.charFormAlias.trim(),
      age: this.charFormAge.trim(),
      appearance: this.charFormAppearance.trim(),
      personality: this.charFormPersonality.trim(),
      background: this.charFormBackground.trim(),
      notes: this.charFormNotes.trim(),
      characterType: this.charFormType
    }
    if (this.isNewChar) {
      this.onSaveChar(model)
    } else {
      this.onUpdateChar(model)
    }
    this.showCharForm = false
  }

  deleteEditingChar(): void {
    if (this.editingCharId !== '') {
      this.onDeleteChar(this.editingCharId)
    }
    this.showCharForm = false
  }

  @Builder buildCharForm() {
    Column({ space: 12 }) {
      Text(this.isNewChar ? '新建人物' : '编辑人物').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().TEXT_PRIMARY).margin({ bottom: 8 })

      TextInput({ text: $$this.charFormName, placeholder: '姓名（必填）' })
        .fontSize(14).width('100%').height(40)
        .backgroundColor(this.getColors().BG_SECONDARY)
        .border({ width: 1, color: this.getColors().DIVIDER })
        .borderRadius(PcRadii.SM).padding({ left: 12 })

      Row({ space: 8 }) {
        Text('类型:').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
        Button('主角').fontSize(12)
          .fontColor(this.charFormType === 'protagonist' ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
          .backgroundColor(this.charFormType === 'protagonist' ? '#E67E22' : Color.Transparent)
          .border({ width: 1, color: '#E67E22' }).borderRadius(PcRadii.SM).height(28)
          .onClick(() => { this.charFormType = 'protagonist' })
        Button('配角').fontSize(12)
          .fontColor(this.charFormType === 'support' ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
          .backgroundColor(this.charFormType === 'support' ? '#689F63' : Color.Transparent)
          .border({ width: 1, color: '#689F63' }).borderRadius(PcRadii.SM).height(28)
          .onClick(() => { this.charFormType = 'support' })
        Button('反派').fontSize(12)
          .fontColor(this.charFormType === 'antagonist' ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
          .backgroundColor(this.charFormType === 'antagonist' ? '#4A4A4A' : Color.Transparent)
          .border({ width: 1, color: '#4A4A4A' }).borderRadius(PcRadii.SM).height(28)
          .onClick(() => { this.charFormType = 'antagonist' })
      }

      Button('保存').fontSize(14).fontColor('#FFFFFF')
        .backgroundColor(this.getColors().EMPHASIZE).borderRadius(PcRadii.SM)
        .width('100%').height(40).margin({ top: 8 })
        .onClick(() => { this.saveChar() })

      if (!this.isNewChar) {
        Button('删除').fontSize(14).fontColor('#FA2A2D')
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: '#FA2A2D' }).borderRadius(PcRadii.SM)
          .width('100%').height(40)
          .onClick(() => { this.deleteEditingChar() })
      }
    }
    .width(280).padding(20)
    .backgroundColor(this.getColors().BG_SECONDARY)
    .borderRadius(PcRadii.MD)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.12)', offsetY: 4 })
  }

  getActiveTabId(): string {
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      if (this.editorTabs[i].active) return this.editorTabs[i].id
    }
    return ''
  }

  getActiveTabTitle(): string {
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      if (this.editorTabs[i].active) return this.editorTabs[i].title
    }
    return ''
  }

  @Builder buildTitleBar() {
    Row() {
      if (this.isEditingTitle) {
        TextInput({ text: $$this.editTitleText })
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().TEXT_PRIMARY)
          .backgroundColor(Color.Transparent)
          .border({ width: 0 })
          .layoutWeight(1).height(44)
          .padding({ left: 48 })
          .onSubmit(() => {
            this.commitTitleEdit()
          })
        Button('保存').fontSize(12).fontColor(this.getColors().EMPHASIZE)
        .height(32).padding({ left: 10, right: 10 })
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.getColors().EMPHASIZE })
        .borderRadius(PcRadii.SM)
        .margin({ right: 8 })
        .onClick(() => { this.commitTitleEdit() })
      } else {
        Text(this.getActiveTabTitle())
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().TEXT_PRIMARY)
          .layoutWeight(1).height(44)
          .padding({ left: 48 })
          .onClick(() => {
            this.editTitleText = this.getActiveTabTitle()
            this.editDocId = this.getActiveTabId()
            this.isEditingTitle = true
          })
      }
    }
    .width('100%').height(44)
    .backgroundColor(this.getColors().EDITOR_BG)
    .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
  }

  commitTitleEdit(): void {
    hilog.info(0x0000, 'Weaver', '[rename] commitTitleEdit called, editDocId=%{public}s, editTitleText=%{public}s', this.editDocId, this.editTitleText)
    const newTitle: string = this.editTitleText.trim()
    if (newTitle === '') return

    this.isEditingTitle = false
    this.onRenameDoc(this.editDocId, newTitle)
  }

  build() {
    Column() {
      if (this.viewMode !== EditorViewMode.EDITOR) {
        Row() {
          Button() {
            Image($rawfile(this.isFullscreen ? 'arrow_down_right_and_arrow_up_left.svg' : 'arrow_up_left_and_arrow_down_right.svg'))
              .width(16).height(16)
          }
          .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(Color.Transparent) }
          })
          .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'fullscreen' : '' })
          .backgroundColor(this.hoveredToolId === 'fullscreen' ? '#0D000000' : Color.Transparent)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          .margin({ left: 4, right: 4 }).onClick(() => { this.onToggleFullscreen() })
          Blank()
        }
        .width('100%').height(36).padding({ left: 8 })
        .backgroundColor(this.getColors().TOOLBAR_BG)
      }

      if (this.viewMode === EditorViewMode.EMPTY) { this.buildEmptyView() }
      else if (this.viewMode === EditorViewMode.EDITOR) {
        Column() {
          this.buildTabBar()
          if (this.editorTabs.length > 0) { this.buildDocActionBar() }
          if (this.editorTabs.length > 0) { this.buildTitleBar() }
          if (this.showFindBar) { this.buildFindBar() }
          this.buildEditorView()
          Column() {
            this.buildToolbar()
            this.buildStatusBar()
          }
          .padding({ bottom: 4 })
        }
      } else if (this.viewMode === EditorViewMode.MATERIAL) { this.buildMaterialView() }
      else if (this.viewMode === EditorViewMode.MATERIAL_DETAIL) {
        if (this.selectedDetailType === 'world') {
          this.buildWorldDetailView()
        } else {
          this.buildCharDetailView()
        }
      }
      else if (this.viewMode === EditorViewMode.GRAPH) { this.buildGraphView() }
      else { this.buildEmptyView() }
    }.width('100%').height('100%').backgroundColor(this.getColors().EDITOR_BG)
  }
}