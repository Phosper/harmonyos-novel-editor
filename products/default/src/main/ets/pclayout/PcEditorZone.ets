// PcEditorZone.ets V2 — Editor zone with press/hover/focus + dual-mode colors
import { PcRadii, PcSpacing, PcInteraction, pcColors, EditorViewMode, type TabItem, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'
import type { CharacterModel, WorldSettingModel, InspirationModel, RelationshipModel } from '@ohos/common'
import { SaveState } from './WeaverViewModel'
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
  @State matchPositions: number[] = []
  @State currentMatchIndex: number = -1
  @State selectionStart: number = 0
  @State selectionEnd: number = 0
  private textAreaController: TextAreaController = new TextAreaController()
  private scrollController: Scroller = new Scroller()
  characters: CharacterModel[] = []
  worldSettings: WorldSettingModel[] = []
  inspirations: InspirationModel[] = []
  relationships: RelationshipModel[] = []

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
  @State dragTabId: string = ''

  onContentChange: (value: string) => void = (value: string): void => { value }
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
          }, (tab: TabItem): string => tab.id)
        }.padding({ left: 4, right: 8 }).alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

      Blank()

      Button() { Text('⛶').fontSize(14).fontColor(this.getColors().TEXT_SECONDARY).accessibilityText('全屏模式') }
      .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
      .stateStyles({
        pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .onHover((isHover: boolean) => { this.hoveredToolId = isHover ? 'fullscreen' : '' })
      .backgroundColor(this.hoveredToolId === 'fullscreen' ? this.getColors().HOVER_BG : Color.Transparent)
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .focusable(true)
      
      .margin({ right: 8 }).onClick(() => { this.onToggleFullscreen() })
    }
    .width('100%').height(36).backgroundColor(this.getColors().TOOLBAR_BG)
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
        .width('100%').constraintSize({ maxWidth: 720 })
        .padding({ left: 48, right: 48, top: 48, bottom: this.isTypewriterMode ? '50%' : 120 })
        .onChange((value: string) => { this.onContentChange(value) })
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
    Scroll() {
      Column() {
        Row() {
          Text('人物').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
          Blank(); Text('+ 添加').fontSize(12).fontColor(this.getColors().EMPHASIZE)
            .onClick(() => { this.onAddCharacter() })
        }.width('100%').margin({ top: 18, bottom: 12 })
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
            }
          }, (char: CharacterModel): string => char.id)
          GridItem() {
            Column() { Text('+').fontSize(24).fontColor(this.getColors().TEXT_TERTIARY) }
            .width('100%').height(150).justifyContent(FlexAlign.Center)
            .border({ width: 1, color: this.getColors().DIVIDER, style: BorderStyle.Dashed })
            .borderRadius(PcRadii.MD).backgroundColor(Color.Transparent)
          }
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(14).rowsGap(14).margin({ bottom: 32 })
        Row() {
          Text('世界观').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
          Blank(); Text('+ 添加').fontSize(12).fontColor(this.getColors().EMPHASIZE)
            .onClick(() => { this.onAddWorldSetting() })
        }.width('100%').margin({ bottom: 12 })
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
            }
          }, (ws: WorldSettingModel): string => ws.id)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(14).rowsGap(14)
      }.width('100%').padding({ left: 44, right: 44, bottom: 44 })
    }.layoutWeight(1)
  }

  @Builder buildGraphView() {
    Column() {
      Row() {
        Text('人物关系图').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
        Blank(); Text('拖动/滚轮缩放').fontSize(12).fontColor(this.getColors().TEXT_SECONDARY)
      }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 8 })
      GraphCanvas({
        nodes: $graphNodes, edges: $graphEdges,
        panOffsetX: $graphPanX, panOffsetY: $graphPanY,
        canvasScale: $graphScale, selectedRelId: $graphSelectedRelId
      })
      .width('100%').layoutWeight(1)
      .backgroundColor(this.getColors().EDITOR_BG).border({ width: { top: 1 }, color: this.getColors().DIVIDER })
    }.width('100%').layoutWeight(1)
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
            placement: Placement.TopLeft
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
      Button('↩ 撤销').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onUndo() })
      Button('↪ 重做').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onRedo() })
      Button(this.sprintRunning ? '⏸ 暂停冲刺' : '▶ 专注写作').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onToggleSprint() })
      Button('🤖 写作伴侣').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onToggleAgent() })
      Button('⌨ 打字机').fontSize(13)
        .fontColor(this.isTypewriterMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.isTypewriterMode = !this.isTypewriterMode })
      Button('◉ 聚焦').fontSize(13)
        .fontColor(this.isSpotlightMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.isSpotlightMode = !this.isSpotlightMode })
      Button('† 沉浸').fontSize(13)
        .fontColor(this.isZenMode ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.isZenMode = !this.isZenMode; this.onToggleFullscreen() })
      Button('⬇ 导出 TXT').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportTxt() })
      Button('⬇ 导出 MD').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportMd() })
      Button('⬇ 导出 JSON').fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
        .backgroundColor(Color.Transparent).width('100%').height(36).padding({ left: 12, right: 12 })
        .onClick(() => { this.onExportJson() })
    }
    .width(160).padding({ top: 8, bottom: 8 })
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: 1, color: this.getColors().DIVIDER }).borderRadius(PcRadii.SM)
  }

  build() {
    Column() {
      this.buildTabBar()
      if (this.showFindBar) { this.buildFindBar() }
      if (this.viewMode === EditorViewMode.EMPTY) { this.buildEmptyView() }
      else if (this.viewMode === EditorViewMode.EDITOR) { this.buildEditorView() }
      else if (this.viewMode === EditorViewMode.MATERIAL) { this.buildMaterialView() }
      else if (this.viewMode === EditorViewMode.GRAPH) { this.buildGraphView() }
      else { this.buildEmptyView() }
      Column() {
        this.buildToolbar()
        this.buildStatusBar()
      }
      .padding({ bottom: 4 })
    }.width('100%').height('100%').backgroundColor(this.getColors().EDITOR_BG)
  }
}