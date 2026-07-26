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
import { hilog } from '@kit.PerformanceAnalysisKit'
import { router } from '@kit.ArkUI'
import type { BookModel, ChapterModel, CharacterModel, WorldSettingModel,
  InspirationModel, RelationshipModel } from '@ohos/common'
import { IdGenerator } from '@ohos/common'
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
  @State showFullscreen: boolean = false
  @State showControlBtn: boolean = true
  @State showDocList: boolean = true
  @State selectedDetailType: string = ''
  @State selectedWorldId: string = ''
  @State showMidSeg: boolean = false
  @State docListTitle: string = '全部文稿'
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

  getCurrentChapterFav(): boolean {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === this.currentChapterId)
    return ch !== undefined ? ch.isFav : false
  }

  getCurrentChapterInsp(): boolean {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === this.currentChapterId)
    return ch !== undefined ? ch.isInspiration : false
  }

  getCurrentChapterPrivate(): boolean {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === this.currentChapterId)
    return ch !== undefined ? ch.isPrivate : false
  }

  getCurrentChapterExpireDays(): number {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === this.currentChapterId)
    if (ch !== undefined && ch.isTrash) {
      const diff: number = Date.now() - ch.updatedAt
      const days: number = 7 - Math.floor(diff / 86400000)
      return days > 0 ? days : 0
    }
    return 0
  }

  getCurrentProjectName(): string {
    if (this.currentBookId === '') return ''
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === this.currentBookId)
    return book !== undefined ? book.name : ''
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
    await this.vm.createChapter('无标题')
    this.editorViewMode = EditorViewMode.EDITOR
    this.syncFromVm()
  }
  selectDoc(docId: string): void {
    if (this.currentChapterId === docId) return
    const curTab: TabItem | undefined = this.editorTabs.find((t: TabItem) => t.active)
    const isDirty: boolean = curTab !== undefined && curTab.dirty
    if (isDirty) {
      AlertDialog.show({
        title: '保存更改',
        message: '当前文档未保存，是否保存？',
        autoCancel: true,
        primaryButton: {
          value: '保存',
          fontColor: this.getColors().EMPHASIZE,
          action: (): void => {
            this.vm.performAutoSave()
            const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === docId)
            if (ch !== undefined) { this.vm.openChapter(ch); this.editorViewMode = EditorViewMode.EDITOR; this.syncFromVm() }
          }
        },
        secondaryButton: {
          value: '不保存',
          fontColor: '#FA2A2D',
          action: (): void => {
            const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === docId)
            if (ch !== undefined) { this.vm.openChapter(ch); this.editorViewMode = EditorViewMode.EDITOR; this.syncFromVm() }
          }
        }
      })
    } else {
      const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === docId)
      if (ch !== undefined) { this.vm.openChapter(ch); this.editorViewMode = EditorViewMode.EDITOR; this.syncFromVm() }
    }
  }
  closeTab(tabId: string): void {
    const tab: TabItem | undefined = this.editorTabs.find((t: TabItem) => t.id === tabId)
    const isDirty: boolean = tab !== undefined && tab.dirty
    if (isDirty) {
      AlertDialog.show({
        title: '保存更改',
        message: '是否保存当前文档的更改？',
        autoCancel: true,
        primaryButton: {
          value: '保存',
          fontColor: this.getColors().EMPHASIZE,
          action: (): void => {
            this.vm.performAutoSave()
            this.vm.closeTab(tabId)
            this.syncFromVm()
          }
        },
        secondaryButton: {
          value: '不保存',
          fontColor: '#FA2A2D',
          action: (): void => {
            this.vm.closeTab(tabId)
            this.syncFromVm()
          }
        }
      })
    } else {
      this.vm.closeTab(tabId)
      this.syncFromVm()
    }
  }
  selectTab(tabId: string): void { this.vm.selectTab(tabId); this.syncFromVm() }
  async createProject(name: string): Promise<void> { await this.vm.createBook(name); this.editorViewMode = EditorViewMode.PROJECT_DETAIL; this.syncFromVm() }
  async selectProject(bookId: string): Promise<void> {
    if (this.currentBookId === bookId) {
      this.vm.currentBookId = ''
      await this.vm.onSidebarLibChange('all')
      this.syncFromVm()
    } else {
      await this.vm.selectBook(bookId)
      this.vm.editorViewMode = EditorViewMode.EMPTY
      this.syncFromVm()
    }
  }
  async deleteDoc(docId: string): Promise<void> { await this.vm.trashChapter(docId); this.syncFromVm() }
  async hardDeleteDoc(docId: string): Promise<void> { await this.vm.deleteChapter(docId); this.syncFromVm() }
  async restoreDoc(docId: string): Promise<void> { await this.vm.restoreChapter(docId); this.syncFromVm() }
  async moveChapterToBook(docId: string, bookId: string): Promise<void> { await this.vm.moveChapterToBook(docId, bookId); this.syncFromVm() }
  reorderTab(fromId: string, toId: string): void { this.vm.reorderTabs(fromId, toId); this.syncFromVm() }
  async toggleFav(): Promise<void> { await this.vm.toggleFav(this.vm.currentChapterId); this.syncFromVm() }
  async toggleInsp(): Promise<void> { await this.vm.toggleInspiration(this.vm.currentChapterId); this.syncFromVm() }
  async togglePrivate(): Promise<void> { await this.vm.togglePrivate(this.vm.currentChapterId); this.syncFromVm() }
  async renameChapter(chapterId: string, title: string): Promise<void> {
    hilog.info(0x0000, 'Weaver', '[rename] PcShell.renameChapter called, id=%{public}s, title=%{public}s', chapterId, title)
    await this.vm.renameChapter(chapterId, title)
    this.syncFromVm()
  }

  doDeleteWorld(id: string): void {
    const updated: WorldSettingModel[] = []
    for (let i: number = 0; i < this.vm.worldSettings.length; i++) {
      if (this.vm.worldSettings[i].id !== id) {
        updated.push(this.vm.worldSettings[i])
      }
    }
    this.vm.worldSettings = updated
    this.syncFromVm()
    this.vm.deleteWorldOnly(id)
  }

  doUpdateWorld(id: string, content: string): void {
    this.vm.updateWorldContent(id, content)
    for (let i: number = 0; i < this.vm.worldSettings.length; i++) {
      if (this.vm.worldSettings[i].id === id) {
        this.vm.worldSettings[i].content = content
        break
      }
    }
    this.syncFromVm()
  }

  updateDocItemTitle(docId: string, newTitle: string): void {
    const updated: DocListItem[] = []
    for (let i: number = 0; i < this.docItems.length; i++) {
      const d: DocListItem = this.docItems[i]
      updated.push({
        id: d.id,
        title: d.id === docId ? newTitle : d.title,
        subTitle: d.subTitle,
        coverColor: d.coverColor,
        emoji: d.emoji,
        badge: d.badge,
        projectName: d.projectName,
        pinned: d.pinned,
        modified: d.modified,
        wordCount: d.wordCount,
        selected: d.selected,
        progress: d.progress,
        isTrash: d.isTrash,
        expireDays: d.expireDays
      })
    }
    this.docItems = updated
  }
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
    this.vm.onChangeMidTab(mode).then((): void => {
      this.syncFromVm()
      if (mode === MidTabMode.GRAPH) {
        this.buildGraphData()
      }
    })
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

  confirmDeleteProject(bookId: string): void {
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === bookId)
    const name: string = book !== undefined ? book.name : '此项目'
    AlertDialog.show({
      title: '确认删除',
      message: name + ' 及其所有文档将被永久删除，无法恢复',
      primaryButton: { value: '取消', action: (): void => { } },
      secondaryButton: { value: '删除', fontColor: '#FA2A2D',
        action: (): void => {
          this.vm.deleteBook(bookId)
          this.syncFromVm()
        }
      }
    })
  }
  toggleFind(): void { this.vm.showFindBar = !this.vm.showFindBar; this.syncFromVm() }
  toggleSidebar(): void {
    animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
      this.showSidebar = !this.showSidebar
      this.vm.showSidebar = this.showSidebar
    })
    this.syncFromVm()
  }
  toggleDocList(): void { this.vm.showDocList = !this.vm.showDocList; this.syncFromVm() }
  toggleFullscreen(): void {
    animateTo({ duration: 350, curve: Curve.FastOutSlowIn }, () => {
      this.showFullscreen = !this.showFullscreen
      this.showControlBtn = !this.showFullscreen
      this.showSidebar = !this.showFullscreen
      this.showDocList = !this.showFullscreen
    })
    this.vm.showSidebar = this.showSidebar
    this.vm.showDocList = this.showDocList
    this.syncFromVm()
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

  @Builder
  buildEditorColumn() {
    PcEditorZone({
      viewMode: this.editorViewMode, showFindBar: this.showFindBar,
      editorContent: this.editorContent, wordCount: this.wordCount,
      isFullscreen: this.showFullscreen,
      selectedDetailType: this.selectedDetailType,
      isTrashView: this.activeLibId === 'trash',
      chapterIsFav: this.getCurrentChapterFav(), chapterIsInsp: this.getCurrentChapterInsp(),
      chapterIsPrivate: this.getCurrentChapterPrivate(),
      chapterExpireDays: this.getCurrentChapterExpireDays(),
      currentDocId: this.currentChapterId,
      saveStatus: this.saveStatus, saveState: this.saveState,
      sprintRemaining: this.sprintRemaining, sprintRunning: this.sprintRunning,
      characters: this.charactersList,
      worldSettings: this.worldSettings, inspirations: this.inspirations,
      relationships: this.relationships, editorTabs: this.editorTabs,
      graphNodes: $pcGraphNodes, graphEdges: $pcGraphEdges,
      onContentChange: (value: string): void => { this.vm.onContentChange(value); this.syncFromVm() },
      onEditorBlur: (): void => { this.syncFromVm() },
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
      onAddRelation: (fromId: string, toId: string, relType: string, notes: string): void => {
        const rel: RelationshipModel = {
          id: IdGenerator.generate(),
          bookId: this.currentBookId,
          characterIdA: fromId,
          characterIdB: toId,
          type: relType,
          label: notes,
          notes: notes
        }
        this.vm.relationships.push(rel)
        this.syncFromVm()
        this.buildGraphData()
        this.vm.insertRelOnly(rel)
      },
      onDeleteRelation: (relId: string): void => {
        const updated: RelationshipModel[] = []
        for (let i: number = 0; i < this.vm.relationships.length; i++) {
          if (this.vm.relationships[i].id !== relId) {
            updated.push(this.vm.relationships[i])
          }
        }
        this.vm.relationships = updated
        this.syncFromVm()
        this.buildGraphData()
        this.vm.deleteRelOnly(relId)
      },
      onReorderTab: (fromId: string, toId: string): void => { this.reorderTab(fromId, toId) },
      onToggleFav: (): void => { this.toggleFav() },
      onToggleInsp: (): void => { this.toggleInsp() },
      onTogglePrivate: (): void => { this.togglePrivate() },
      onTrashDoc: (chapterId: string): void => { this.deleteDoc(chapterId) },
      onRestoreDoc: (chapterId: string): void => { this.restoreDoc(chapterId) },
      onHardDeleteDoc: (chapterId: string): void => { this.confirmHardDelete(chapterId) },
      onRenameDoc: (chapterId: string, title: string): void => {
        hilog.info(0x0000, 'Weaver', '[rename] onRenameDoc lambda fired')
        this.renameChapter(chapterId, title)
      },
      onTitleEdited: (docId: string, title: string): void => { this.updateDocItemTitle(docId, title) },
      onSaveChar: (data: CharacterModel): void => {
        data.bookId = this.currentBookId
        const updated: CharacterModel[] = []
        for (let i: number = 0; i < this.vm.charactersList.length; i++) {
          updated.push(this.vm.charactersList[i])
        }
        updated.push(data)
        this.vm.charactersList = updated
        this.syncFromVm()
        this.vm.insertCharOnly(data)
      },
      onUpdateChar: (data: CharacterModel): void => {
        data.bookId = this.currentBookId
        for (let i: number = 0; i < this.vm.charactersList.length; i++) {
          if (this.vm.charactersList[i].id === data.id) {
            this.vm.charactersList[i] = data
            break
          }
        }
        this.syncFromVm()
        this.vm.updateCharOnly(data)
      },
      onDeleteChar: (id: string): void => {
        const updated: CharacterModel[] = []
        for (let i: number = 0; i < this.vm.charactersList.length; i++) {
          if (this.vm.charactersList[i].id !== id) {
            updated.push(this.vm.charactersList[i])
          }
        }
        this.vm.charactersList = updated
        this.syncFromVm()
        this.vm.deleteCharOnly(id)
      },
      onEditCharDetail: (charId: string): void => {
        this.vm.editorViewMode = EditorViewMode.MATERIAL_DETAIL
        this.syncFromVm()
      },
      onDeleteCharDetail: (charId: string): void => {
        const updated: CharacterModel[] = []
        for (let i: number = 0; i < this.vm.charactersList.length; i++) {
          if (this.vm.charactersList[i].id !== charId) {
            updated.push(this.vm.charactersList[i])
          }
        }
        this.vm.charactersList = updated
        this.syncFromVm()
        this.vm.deleteCharOnly(charId)
      },
      onBackToMaterial: (): void => {
        this.vm.editorViewMode = EditorViewMode.MATERIAL
        this.selectedDetailType = ''
        this.syncFromVm()
      },
      onEditWorldDetail: (worldId: string): void => {
        this.selectedWorldId = worldId
        this.vm.editorViewMode = EditorViewMode.MATERIAL_DETAIL
        this.selectedDetailType = 'world'
        this.syncFromVm()
      },
      onDeleteWorld: (id: string): void => { this.doDeleteWorld(id) },
      onUpdateWorld: (id: string, content: string): void => { this.doUpdateWorld(id, content) }
    })
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
            isProjectMode: this.currentBookId !== '',
            currentProjectName: this.getCurrentProjectName(),
            statusBarPad: 0,
            onChangeLib: (libId: string): void => { this.changeSidebarLib(libId) },
            onNewDoc: (): void => { this.newDoc() },
            onCreateProject: (name: string): void => { this.createProject(name) },
            onSelectProject: (bookId: string): void => { this.selectProject(bookId) },
            onDeleteProject: (bookId: string): void => { this.confirmDeleteProject(bookId) },
            onToggleFold: (): void => { this.toggleSidebar() }
          })
        }

        Row() {
          PcDocList({
            listTitle: this.docListTitle, docItems: this.docItems,
            showMidSeg: this.showMidSeg, statusBarPad: 0,
            isTrashView: this.activeLibId === 'trash',
            onChangeMidTab: (mode: MidTabMode): void => { this.onChangeMidTab(mode) },
            onSearch: (text: string): void => {
              this.docItems = this.vm.searchDocs(text)
            },
            onSelectDoc: (docId: string): void => { this.selectDoc(docId) },
            onRenameDoc: (docId: string, title: string): void => { this.renameChapter(docId, title) },
            onMoveToBook: (docId: string, bookId: string): void => { this.moveChapterToBook(docId, bookId) },
            projectNames: this.projItems,
            currentBookId: this.currentBookId,
            onNewDoc: (): void => { this.newDoc() },
            onDeleteDoc: (docId: string): void => { this.deleteDoc(docId) },
            onHardDelete: (docId: string): void => { this.confirmHardDelete(docId) },
            onRestoreDoc: (docId: string): void => { this.restoreDoc(docId) }
          }).width(this.showDocList ? 300 : 0).height('100%')
          .clip(true)

          Column() {
            this.buildEditorColumn()
          }.layoutWeight(1).height('100%')

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
      .showSideBar($$this.showSidebar)
      .showControlButton(this.showControlBtn)
      .controlButton({
        left: 4, top: 4, width: 28, height: 28,
        icons: {
          shown: $rawfile('open_sidebar.svg'),
          hidden: $rawfile('close_sidebar.svg')
        }
      })
      .onChange((isShow: boolean) => { this.showSidebar = isShow })
      .layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }
}