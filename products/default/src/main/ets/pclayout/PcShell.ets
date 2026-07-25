// PcShell.ets — Three-column shell with dual-mode colors + custom title bar
import { PcRadii, PcInteraction, pcColors, type DocListItem, type ProjectItem, type TabItem, type PcColorSet,
  EditorViewMode, MidTabMode } from './PcDesignTokens'
import { WeaverViewModel, SaveState } from './WeaverViewModel'
import { ExportService } from './ExportService'
import { PcSidebar } from './PcSidebar'
import { PcDocList } from './PcDocList'
import { PcEditorZone } from './PcEditorZone'
import { PcAgentPanel } from './PcAgentPanel'
import { PcTitleBar } from './PcTitleBar'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'
import type { BookModel, ChapterModel, CharacterModel, WorldSettingModel,
  InspirationModel, RelationshipModel } from '@ohos/common'
import type { GraphNode, GraphEdge } from '@ohos/relationship'

@Component
export struct PcShell {
  private vm: WeaverViewModel = new WeaverViewModel()
  @StorageLink('colorMode') colorMode: number = 1

  @State books: BookModel[] = []
  @State chapters: ChapterModel[] = []
  @State currentBookId: string = ''
  @State currentChapterId: string = ''
  @State editorTabs: TabItem[] = []
  @State editorContent: string = ''
  @State editorViewMode: EditorViewMode = EditorViewMode.EMPTY
  @State wordCount: number = 0
  @State saveStatus: string = '已自动保存'
  @State saveState: SaveState = SaveState.IDLE
  @State sprintRemaining: number = 1500
  @State sprintRunning: boolean = false
  @State showAgentPanel: boolean = false
  @State showFindBar: boolean = false
  @State showSidebar: boolean = true
  @State showDocList: boolean = true
  @State showMidSeg: boolean = false
  @State docListTitle: string = '📄 全部文稿'
  @State charactersList: CharacterModel[] = []
  @State worldSettings: WorldSettingModel[] = []
  @State inspirations: InspirationModel[] = []
  @State relationships: RelationshipModel[] = []
  @State projItems: ProjectItem[] = []
  @State docItems: DocListItem[] = []
  @State activeLibId: string = 'all'
  @State libCounts: Record<string, number> = {}
  @State pcGraphNodes: GraphNode[] = []
  @State pcGraphEdges: GraphEdge[] = []

  // Hover tracking for Rail
  @State hoveredRailId: string = ''

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  statusBarPad(): number {
    const h: number = AppStorage.get<number>('statusBarHeight') ?? 0
    return h > 0 ? h : 0
  }

  syncFromVm(): void {
    this.books = this.vm.books
    this.chapters = this.vm.chapters
    this.currentBookId = this.vm.currentBookId
    this.currentChapterId = this.vm.currentChapterId
    this.editorTabs = this.vm.editorTabs
    this.editorContent = this.vm.editorContent
    this.editorViewMode = this.vm.editorViewMode
    this.wordCount = this.vm.wordCount
    this.saveStatus = this.vm.saveStatus
    this.saveState = this.vm.saveState
    this.sprintRemaining = this.vm.sprintRemaining
    this.sprintRunning = this.vm.sprintRunning
    this.showAgentPanel = this.vm.showAgentPanel
    this.showFindBar = this.vm.showFindBar
    this.showSidebar = this.vm.showSidebar
    this.showDocList = this.vm.showDocList
    this.showMidSeg = this.vm.showMidSeg
    this.docListTitle = this.vm.docListTitle
    this.charactersList = this.vm.charactersList
    this.worldSettings = this.vm.worldSettings
    this.inspirations = this.vm.inspirations
    this.relationships = this.vm.relationships
    this.projItems = this.vm.getProjectItems()
    this.docItems = this.vm.getDocListItems()
    this.libCounts = this.vm.libCounts
  }

  async changeSidebarLib(libId: string): Promise<void> { await this.vm.onSidebarLibChange(libId); this.activeLibId = libId; this.syncFromVm() }
  async newDoc(): Promise<void> {
    const num: number = this.chapters.length + 1
    await this.vm.createChapter('无标题 ' + num)
    this.editorViewMode = EditorViewMode.EDITOR
    this.syncFromVm()
  }
  selectDoc(docId: string): void {
    const ch = this.vm.chapters.find((c) => c.id === docId)
    if (ch !== undefined) { this.vm.openChapter(ch); this.editorViewMode = EditorViewMode.EDITOR; this.syncFromVm() }
  }
  closeTab(tabId: string): void { this.vm.closeTab(tabId); this.syncFromVm() }
  selectTab(tabId: string): void { this.vm.selectTab(tabId); this.syncFromVm() }
  async createProject(name: string): Promise<void> { await this.vm.createBook(name); this.editorViewMode = EditorViewMode.PROJECT_DETAIL; this.syncFromVm() }
  async selectProject(bookId: string): Promise<void> { await this.vm.selectBook(bookId); this.syncFromVm() }
  async deleteDoc(docId: string): Promise<void> { await this.vm.trashChapter(docId); this.syncFromVm() }
  async hardDeleteDoc(docId: string): Promise<void> { await this.vm.deleteChapter(docId); this.syncFromVm() }
  async restoreDoc(docId: string): Promise<void> { await this.vm.restoreChapter(docId); this.syncFromVm() }
  reorderTab(fromId: string, toId: string): void { this.vm.reorderTabs(fromId, toId); this.syncFromVm() }
  confirmHardDelete(docId: string): void {
    AlertDialog.show({
      title: '确认删除',
      message: '该文档将被永久删除，无法恢复',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#FA2A2D',
        action: (): void => {
          this.vm.deleteChapter(docId)
          this.syncFromVm()
        }
      }
    })
  }
  onChangeMidTab(mode: MidTabMode): void {
    this.vm.onChangeMidTab(mode)
    if (mode === MidTabMode.GRAPH) {
      this.buildGraphData()
    }
    this.syncFromVm()
  }
  toggleAgent(): void { this.vm.showAgentPanel = !this.vm.showAgentPanel; this.syncFromVm() }
  buildGraphData(): void {
    const charMap: Record<string, CharacterModel> = {}
    const nodes: GraphNode[] = []
    for (let i: number = 0; i < this.charactersList.length; i++) {
      const c: CharacterModel = this.charactersList[i]
      charMap[c.id] = c
      nodes.push({
        characterId: c.id,
        name: c.name,
        type: c.characterType,
        x: 0, y: 0, radius: 34,
        isHighlighted: false, isDimmed: false
      })
    }
    this.pcGraphNodes = nodes
    const edges: GraphEdge[] = []
    for (let i: number = 0; i < this.relationships.length; i++) {
      const rel: RelationshipModel = this.relationships[i]
      if (charMap[rel.characterIdA] !== undefined && charMap[rel.characterIdB] !== undefined) {
        edges.push({
          id: rel.id,
          fromId: rel.characterIdA,
          toId: rel.characterIdB,
          type: rel.type,
          label: rel.label
        })
      }
    }
    this.pcGraphEdges = edges
  }
  toggleFind(): void { this.vm.showFindBar = !this.vm.showFindBar; this.syncFromVm() }
  toggleSidebar(): void { this.vm.showSidebar = !this.vm.showSidebar; this.syncFromVm() }
  toggleDocList(): void { this.vm.showDocList = !this.vm.showDocList; this.syncFromVm() }
  toggleFullscreen(): void {
    const isFullscreen: boolean = !this.vm.showSidebar || !this.vm.showDocList
    animateTo({ duration: 250, curve: Curve.FastOutSlowIn }, () => {
      if (isFullscreen) {
        this.vm.showSidebar = true
        this.vm.showDocList = true
      } else {
        this.vm.showSidebar = false
        this.vm.showDocList = false
      }
      this.syncFromVm()
    })
  }

  retrySave(): void { this.vm.retrySave(); this.syncFromVm() }
  undo(): void { this.vm.pushUndoState(); this.vm.undo(); this.syncFromVm() }
  redo(): void { this.vm.redo(); this.syncFromVm() }
  pushUndo(): void { this.vm.pushUndoState() }
  addCharacter(): void {
    router.pushUrl({ url: 'pages/CharacterDetailPage', params: { bookId: this.vm.currentBookId, isNew: true } })
  }
  addWorldSetting(): void {
    router.pushUrl({ url: 'pages/WorldSettingDetailPage', params: { bookId: this.vm.currentBookId, isNew: true } })
  }
  refreshMaterialData(): void { this.vm.loadAllMaterialData(); this.syncFromVm() }
  toggleSprint(): void {
    if (this.vm.sprintRunning) { this.vm.pauseSprint() }
    else { this.vm.startSprint() }
    this.syncFromVm()
  }

  async exportTxt(): Promise<void> {
    const currentTab: TabItem | undefined = this.editorTabs.find((t: TabItem): boolean => t.active)
    const title: string = currentTab !== undefined ? currentTab.title : 'document'
    await ExportService.exportTxt(this.vm.editorContent, title)
  }

  async exportMd(): Promise<void> {
    const currentTab: TabItem | undefined = this.editorTabs.find((t: TabItem): boolean => t.active)
    const title: string = currentTab !== undefined ? currentTab.title : 'document'
    await ExportService.exportMd(this.vm.editorContent, title)
  }

  async exportJson(): Promise<void> {
    const currentBook: BookModel | undefined = this.books.find((b: BookModel): boolean => b.id === this.vm.currentBookId)
    const bookName: string = currentBook !== undefined ? currentBook.name : 'book'
    const chaptersData: string = JSON.stringify(this.vm.chapters)
    await ExportService.exportJson(bookName, this.vm.editorContent, chaptersData)
  }

  async aboutToAppear(): Promise<void> {
    await this.vm.init()
    this.syncFromVm()
  }

  aboutToDisappear(): void {
    this.vm.destroy()
  }

  build() {
    Column() {
      PcTitleBar()
      SideBarContainer(SideBarContainerType.Embed) {
        Column() {
          PcSidebar({
            projects: this.projItems,
            activeLibId: this.activeLibId,
            libCounts: this.libCounts,
            statusBarPad: 0,
            onChangeLib: (libId: string): void => { this.changeSidebarLib(libId) },
            onNewDoc: (): void => { this.newDoc() },
            onCreateProject: (name: string): void => { this.createProject(name) },
            onSelectProject: (bookId: string): void => { this.selectProject(bookId) },
            onToggleFold: (): void => { this.toggleSidebar() }
          })
        }

        Row() {
          if (this.showDocList) {
            PcDocList({
              listTitle: this.docListTitle, docItems: this.docItems,
              showMidSeg: this.showMidSeg, statusBarPad: 0,
              isTrashView: this.activeLibId === 'trash',
              onChangeMidTab: (mode: MidTabMode): void => { this.onChangeMidTab(mode) },
              onSearch: (text: string): void => {
                this.docItems = this.vm.searchDocs(text)
              },
              onSelectDoc: (docId: string): void => { this.selectDoc(docId) },
              onNewDoc: (): void => { this.newDoc() },
              onDeleteDoc: (docId: string): void => { this.deleteDoc(docId) },
              onHardDelete: (docId: string): void => { this.confirmHardDelete(docId) },
              onRestoreDoc: (docId: string): void => { this.restoreDoc(docId) }
            }).width(300).height('100%')
            .transition(TransitionEffect.translate({ x: -300 }).combine(TransitionEffect.OPACITY)
              .animation({ duration: 250, curve: Curve.FastOutSlowIn }))
          }

          PcEditorZone({
            viewMode: this.editorViewMode, showFindBar: this.showFindBar,
            editorContent: this.editorContent, wordCount: this.wordCount,
            saveStatus: this.saveStatus, saveState: this.saveState,
            sprintRemaining: this.sprintRemaining, sprintRunning: this.sprintRunning,
            characters: this.charactersList,
            worldSettings: this.worldSettings, inspirations: this.inspirations,
            relationships: this.relationships, editorTabs: this.editorTabs,
            graphNodes: $pcGraphNodes, graphEdges: $pcGraphEdges,
            onContentChange: (value: string): void => { this.vm.onContentChange(value); this.syncFromVm() },
            onToggleFind: (): void => { this.toggleFind() },
            onToggleAgent: (): void => { this.toggleAgent() },
            onNewDoc: (): void => { this.newDoc() },
            onCloseTab: (tabId: string): void => { this.closeTab(tabId) },
            onSelectTab: (tabId: string): void => { this.selectTab(tabId) },
            onToggleFullscreen: (): void => { this.toggleFullscreen() },
            onRetrySave: (): void => { this.retrySave() },
            onUndo: (): void => { this.undo() },
            onRedo: (): void => { this.redo() },
            onPushUndo: (): void => { this.pushUndo() },
            onToggleSprint: (): void => { this.toggleSprint() },
            onExportTxt: (): void => { this.exportTxt() },
            onExportMd: (): void => { this.exportMd() },
            onExportJson: (): void => { this.exportJson() },
            onAddCharacter: (): void => { this.addCharacter() },
            onAddWorldSetting: (): void => { this.addWorldSetting() },
            onReorderTab: (fromId: string, toId: string): void => { this.reorderTab(fromId, toId) }
          }).layoutWeight(1).height('100%')

          if (this.showAgentPanel) {
            PcAgentPanel({ show: this.showAgentPanel,
              onClose: (): void => { this.vm.showAgentPanel = false; this.syncFromVm() },
              onSend: (text: string): void => { text }
            }).width(320).height('100%')
          }
        }.width('100%').height('100%')
      }
      .sideBarWidth(240)
      .minSideBarWidth(200)
      .maxSideBarWidth(320)
      .showSideBar(this.showSidebar)
      .onChange((isShow: boolean) => { this.showSidebar = isShow })
      .controlButton({
        left: 4,
        top: 4,
        width: 28,
        height: 28
      })
      .layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }
}