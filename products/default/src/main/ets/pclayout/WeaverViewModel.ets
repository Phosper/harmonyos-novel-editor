// WeaverViewModel.ets — Shared data + CRUD service for Weaver PC layout
import type { BookModel, ChapterModel, CharacterModel, WorldSettingModel,
  InspirationModel, RelationshipModel } from '@ohos/common'
import { IdGenerator, dbHelper } from '@ohos/common'
import { BookDao } from '@ohos/editor'
import { ChapterDao } from '@ohos/editor'
import { CharacterDao } from '@ohos/material'
import { WorldSettingDao } from '@ohos/material'
import { InspirationDao } from '@ohos/material'
import { RelationshipDao } from '@ohos/relationship'
import { PcColors, type TabItem, type DocListItem, type ProjectItem,
  type AgentMessage, EditorViewMode, MidTabMode } from './PcDesignTokens'

export interface PaperThemeConfig {
  backgroundColor: string
  textColor: string
  fontSize: number
  lineHeight: number
  type: string
}

export enum SaveState {
  IDLE = 0,
  SAVING = 1,
  FAILED = 2
}

function formatRelativeTime(timestamp: number): string {
  const now: number = Date.now()
  const diff: number = now - timestamp
  if (diff < 60000) return '刚刚'
  if (diff < 3600000) return Math.floor(diff / 60000).toString() + ' 分钟前'
  if (diff < 86400000) return Math.floor(diff / 3600000).toString() + ' 小时前'
  if (diff < 172800000) return '昨天'
  const date: Date = new Date(timestamp)
  return (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日'
}

@Observed
export class WeaverViewModel {
  books: BookModel[] = []
  chapters: ChapterModel[] = []
  currentBookId: string = ''
  currentChapterId: string = ''
  editorTabs: TabItem[] = []
  editorContent: string = ''
  editorViewMode: EditorViewMode = EditorViewMode.EMPTY
  wordCount: number = 0
  saveStatus: string = '已自动保存'
  saveState: SaveState = SaveState.IDLE
  showAgentPanel: boolean = false
  showFindBar: boolean = false
  showSidebar: boolean = true
  showDocList: boolean = true
  showMidSeg: boolean = false
  docListTitle: string = '全部文稿'
  currentLibFilter: string = 'all'
  libCounts: Record<string, number> = {}
  paperTheme: PaperThemeConfig = {
    backgroundColor: '#F5F5F5',
    textColor: '#182431',
    fontSize: 16,
    lineHeight: 2.1,
    type: 'default'
  }
  charactersList: CharacterModel[] = []
  worldSettings: WorldSettingModel[] = []
  inspirations: InspirationModel[] = []
  relationships: RelationshipModel[] = []

  private bookDao: BookDao = new BookDao()
  private chapterDao: ChapterDao = new ChapterDao()
  private charDao: CharacterDao = new CharacterDao()
  private wsDao: WorldSettingDao = new WorldSettingDao()
  private inspDao: InspirationDao = new InspirationDao()
  private relDao: RelationshipDao = new RelationshipDao()

  // Undo/redo
  private undoStack: string[] = []
  private redoStack: string[] = []
  private readonly MAX_UNDO: number = 100

  // Auto-save
  private autoSaveTimer: number = -1
  private saveRetryCount: number = 0
  private saveRetryTimer: number = -1
  private loadingChapter: boolean = false

  // Sprint timer
  sprintRemaining: number = 1500
  sprintRunning: boolean = false
  private sprintTimerId: number = -1
  private static readonly TRASH_DAYS: number = 7

  async clearAllData(): Promise<void> {
    try {
      const store = dbHelper.getStore()
      await store.executeSql('DELETE FROM chapters')
      await store.executeSql('DELETE FROM books')
    } catch (e) { }
  }

  async init(): Promise<void> {
    await this.loadBooks()
    if (this.currentBookId !== '' && this.chapters.length === 0) {
      await this.loadChapters()
    }
    await this.cleanExpiredTrash()
    this.startAutoSave()
  }

  async loadBooks(): Promise<void> {
    this.books = await this.bookDao.queryAll()
    if (this.currentBookId !== '' && this.chapters.length === 0) {
      await this.loadChapters()
    }
  }

  async ensureDefaultBook(): Promise<void> {
    if (this.books.length > 0) {
      this.currentBookId = this.books[0].id
      this.showMidSeg = true
      this.docListTitle = '📖 ' + this.books[0].name
      return
    }
    const book: BookModel = {
      id: IdGenerator.generate(),
      name: '默认项目',
      mode: 'professional',
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await this.bookDao.insert(book)
    this.books = [book]
    this.currentBookId = book.id
    this.showMidSeg = true
    this.docListTitle = '📖 默认项目'
  }

  async createBook(name: string): Promise<void> {
    if (name.trim() === '') return
    const book: BookModel = {
      id: IdGenerator.generate(),
      name: name.trim(),
      mode: 'professional',
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await this.bookDao.insert(book)
    await this.loadBooks()
  }

  async selectBook(bookId: string): Promise<void> {
    this.currentBookId = bookId
    this.showMidSeg = true
    this.currentLibFilter = 'all'
    this.docListTitle = '全部文稿'
    await this.loadChapters()
    await this.loadAllMaterialData()
    await this.updateLibCounts()
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === bookId)
    if (book !== undefined) {
      this.docListTitle = '📖 ' + book.name
    }
  }

  async loadChapters(): Promise<void> {
    if (this.currentBookId === '') {
      if (this.currentLibFilter === 'fav') {
        this.chapters = await this.chapterDao.queryGlobalFav()
      } else if (this.currentLibFilter === 'insp') {
        this.chapters = await this.chapterDao.queryGlobalInsp()
      } else if (this.currentLibFilter === 'priv') {
        this.chapters = await this.chapterDao.queryGlobalPrivate()
      } else if (this.currentLibFilter === 'trash') {
        this.chapters = await this.chapterDao.queryAllTrash()
      } else {
        this.chapters = await this.chapterDao.queryGlobal()
      }
    } else {
      if (this.currentLibFilter === 'fav') {
        this.chapters = await this.chapterDao.queryFavByBook(this.currentBookId)
      } else if (this.currentLibFilter === 'trash') {
        this.chapters = await this.chapterDao.queryTrashByBook(this.currentBookId)
      } else if (this.currentLibFilter === 'priv') {
        this.chapters = await this.chapterDao.queryPrivateByBook(this.currentBookId)
      } else if (this.currentLibFilter === 'insp') {
        this.chapters = await this.chapterDao.queryInspByBook(this.currentBookId)
      } else {
        this.chapters = await this.chapterDao.queryByBook(this.currentBookId)
      }
    }
  }

  async createChapter(title: string): Promise<void> {
    if (title.trim() === '') return
    const allChapters: ChapterModel[] = await this.chapterDao.queryAll()
    const totalNum: number = allChapters.length + 1
    const displayTitle: string = title.trim() === '无标题' ? '无标题 ' + totalNum : title.trim()
    const ch: ChapterModel = {
      id: IdGenerator.generate(),
      bookId: this.currentBookId,
      title: displayTitle,
      content: '开始你的创作之旅...',
      order: totalNum - 1,
      wordCount: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      isFav: false,
      isInspiration: false,
      isTrash: false,
      isPrivate: false
    }
    await this.chapterDao.insert(ch)
    await this.loadChapters()
    this.openChapter(ch)
    await this.updateLibCounts()
  }

  async deleteChapter(chapterId: string): Promise<void> {
    await this.chapterDao.delete(chapterId)
    this.closeTab(chapterId)
    await this.loadChapters()
    await this.updateLibCounts()
  }

  async moveChapterToBook(chapterId: string, bookId: string): Promise<void> {
    if (bookId !== '') {
      await this.chapterDao.setFav(chapterId, false)
      await this.chapterDao.setInspiration(chapterId, false)
      await this.chapterDao.setPrivate(chapterId, false)
    }
    await this.chapterDao.moveToBook(chapterId, bookId)
    this.closeTab(chapterId)
    await this.loadChapters()
    await this.updateLibCounts()
  }

  async deleteBook(bookId: string): Promise<void> {
    await this.bookDao.delete(bookId)
    if (this.currentBookId === bookId) {
      this.currentBookId = this.books.length > 1 ? this.books[0].id : ''
      this.chapters = []
      this.editorTabs = []
      this.editorViewMode = EditorViewMode.EMPTY
    }
    await this.loadBooks()
  }

  openChapter(ch: ChapterModel): void {
    this.loadingChapter = true
    this.currentChapterId = ch.id
    this.editorContent = ch.content
    this.wordCount = ch.content.length
    this.editorViewMode = EditorViewMode.EDITOR

    const colors: string[] = [PcColors.EMPHASIZE, PcColors.EMPHASIZE_DIMMED, PcColors.ACCENT_ORANGE, PcColors.ACCENT_GREEN, PcColors.ACCENT_BROWN]
    const existingIdx: number = this.editorTabs.findIndex((t: TabItem) => t.id === ch.id)
    if (existingIdx >= 0) {
      const updated: TabItem[] = []
      for (let i: number = 0; i < this.editorTabs.length; i++) {
        const t: TabItem = this.editorTabs[i]
        updated.push({
          id: t.id, title: t.title, color: t.color,
          active: i === existingIdx, pinned: t.pinned, dirty: t.dirty
        })
      }
      this.editorTabs = updated
      return
    }
    const ci: number = this.editorTabs.length % colors.length
    const updated: TabItem[] = []
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      const t: TabItem = this.editorTabs[i]
      updated.push({
        id: t.id, title: t.title, color: t.color,
        active: false, pinned: t.pinned, dirty: t.dirty
      })
    }
    updated.push({
      id: ch.id, title: ch.title, color: colors[ci],
      active: true, pinned: false, dirty: false
    })
    this.editorTabs = updated
  }

  closeTab(tabId: string): void {
    const filtered: TabItem[] = []
    let foundActive: boolean = false
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      const t: TabItem = this.editorTabs[i]
      if (t.id !== tabId) {
        filtered.push(t)
      } else if (t.active) {
        foundActive = true
      }
    }
    if (filtered.length === 0) {
      this.editorTabs = []
      this.editorViewMode = EditorViewMode.EMPTY
      this.editorContent = ''
      this.wordCount = 0
      return
    }
    const updated: TabItem[] = []
    for (let j: number = 0; j < filtered.length; j++) {
      const ft: TabItem = filtered[j]
      updated.push({
        id: ft.id, title: ft.title, color: ft.color,
        active: foundActive && j === 0, pinned: ft.pinned, dirty: ft.dirty
      })
    }
    this.editorTabs = updated
    if (foundActive && updated.length > 0) {
      this.loadTabContent(updated[0].id)
    }
  }

  selectTab(tabId: string): void {
    const updated: TabItem[] = []
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      const t: TabItem = this.editorTabs[i]
      updated.push({
        id: t.id, title: t.title, color: t.color,
        active: t.id === tabId, pinned: t.pinned, dirty: t.dirty
      })
    }
    this.editorTabs = updated
    this.loadTabContent(tabId)
  }

  reorderTabs(fromId: string, toId: string): void {
    const fromIdx: number = this.editorTabs.findIndex((t: TabItem) => t.id === fromId)
    const toIdx: number = this.editorTabs.findIndex((t: TabItem) => t.id === toId)
    if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return
    const tabs: TabItem[] = []
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      tabs.push(this.editorTabs[i])
    }
    const moved: TabItem = tabs[fromIdx]
    tabs.splice(fromIdx, 1)
    tabs.splice(toIdx, 0, moved)
    this.editorTabs = tabs
  }

  loadTabContent(chapterId: string): void {
    this.loadingChapter = true
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      this.currentChapterId = ch.id
      this.editorContent = ch.content
      this.wordCount = ch.content.length
      this.editorViewMode = EditorViewMode.EDITOR
    }
  }

  async renameChapter(chapterId: string, newTitle: string): Promise<void> {
    if (newTitle.trim() === '') return
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      ch.title = newTitle.trim()
      await this.chapterDao.update(chapterId, newTitle.trim(), ch.content)
    }
    const updated: TabItem[] = []
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      const t: TabItem = this.editorTabs[i]
      if (t.id === chapterId) {
        updated.push({
          id: t.id, title: newTitle.trim(), color: t.color,
          active: t.active, pinned: t.pinned, dirty: t.dirty
        })
      } else {
        updated.push(t)
      }
    }
    this.editorTabs = updated
  }

  onContentChange(value: string): void {
    this.editorContent = value
    this.wordCount = value.length
    const chapterId: string = this.currentChapterId
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      ch.content = value
      ch.wordCount = value.length
    }
    if (this.loadingChapter) {
      this.loadingChapter = false
      return
    }
    const updated: TabItem[] = []
    for (let i: number = 0; i < this.editorTabs.length; i++) {
      const t: TabItem = this.editorTabs[i]
      if (t.id === chapterId) {
        updated.push({
          id: t.id, title: t.title, color: t.color,
          active: t.active, pinned: t.pinned, dirty: true
        })
      } else {
        updated.push(t)
      }
    }
    this.editorTabs = updated
  }

  async performAutoSave(): Promise<void> {
    if (this.currentChapterId === '' || this.editorContent.length === 0) return
    this.saveState = SaveState.SAVING
    this.saveStatus = '保存中...'
    const id: string = this.currentChapterId
    try {
      await this.chapterDao.updateContent(id, this.editorContent)
      this.saveState = SaveState.IDLE
      this.saveRetryCount = 0
      this.saveStatus = '已保存'
      const updated: TabItem[] = []
      for (let i: number = 0; i < this.editorTabs.length; i++) {
        const t: TabItem = this.editorTabs[i]
        if (t.id === id) {
          updated.push({
            id: t.id, title: t.title, color: t.color,
            active: t.active, pinned: t.pinned, dirty: false
          })
        } else {
          updated.push(t)
        }
      }
      this.editorTabs = updated
    } catch (e) {
      this.handleSaveFailure()
    }
  }

  private handleSaveFailure(): void {
    this.saveState = SaveState.FAILED
    this.saveRetryCount = this.saveRetryCount + 1
    if (this.saveRetryCount <= 3) {
      this.saveStatus = '保存失败，正在重试(' + this.saveRetryCount + '/3)...'
      const self: WeaverViewModel = this
      this.saveRetryTimer = setTimeout(() => {
        self.performAutoSave()
      }, 5000)
    } else {
      this.saveStatus = '保存失败（点击重试）'
    }
  }

  retrySave(): void {
    if (this.saveState !== SaveState.SAVING) {
      this.saveRetryCount = 0
      this.performAutoSave()
    }
  }

  startAutoSave(): void {
    const self: WeaverViewModel = this
    this.autoSaveTimer = setInterval(() => {
      self.performAutoSave()
    }, 60000)
  }

  destroy(): void {
    if (this.autoSaveTimer !== -1) {
      clearInterval(this.autoSaveTimer)
      this.autoSaveTimer = -1
    }
    if (this.saveRetryTimer !== -1) {
      clearTimeout(this.saveRetryTimer)
      this.saveRetryTimer = -1
    }
    if (this.sprintTimerId !== -1) {
      clearInterval(this.sprintTimerId)
      this.sprintTimerId = -1
    }
  }

  // Undo/redo
  pushUndoState(): void {
    this.undoStack.push(this.editorContent)
    if (this.undoStack.length > this.MAX_UNDO) {
      this.undoStack.splice(0, 1)
    }
    this.redoStack = []
  }

  undo(): void {
    if (this.undoStack.length === 0) return
    this.redoStack.push(this.editorContent)
    const prev: string | undefined = this.undoStack.pop()
    if (prev !== undefined) {
      this.editorContent = prev
      this.wordCount = prev.length
    }
  }

  redo(): void {
    if (this.redoStack.length === 0) return
    this.undoStack.push(this.editorContent)
    const next: string | undefined = this.redoStack.pop()
    if (next !== undefined) {
      this.editorContent = next
      this.wordCount = next.length
    }
  }

  // Search
  searchDocs(query: string): DocListItem[] {
    if (query.trim() === '') return this.getDocListItems()
    const lowerQuery: string = query.toLowerCase()
    const allItems: DocListItem[] = this.getDocListItems()
    const filtered: DocListItem[] = []
    for (let i: number = 0; i < allItems.length; i++) {
      const item: DocListItem = allItems[i]
      if (item.title.toLowerCase().indexOf(lowerQuery) >= 0 ||
        item.subTitle.toLowerCase().indexOf(lowerQuery) >= 0) {
        filtered.push(item)
      }
    }
    return filtered
  }

  // Sprint timer
  startSprint(): void {
    if (this.sprintRunning) return
    this.sprintRunning = true
    this.sprintRemaining = 1500
    const self: WeaverViewModel = this
    this.sprintTimerId = setInterval(() => {
      if (self.sprintRemaining > 0) {
        self.sprintRemaining = self.sprintRemaining - 1
      } else {
        self.pauseSprint()
      }
    }, 1000)
  }

  pauseSprint(): void {
    this.sprintRunning = false
    if (this.sprintTimerId !== -1) {
      clearInterval(this.sprintTimerId)
      this.sprintTimerId = -1
    }
  }

  resetSprint(): void {
    this.pauseSprint()
    this.sprintRemaining = 1500
  }

  async insertChar(data: CharacterModel): Promise<void> {
    await this.charDao.insert(data)
    await this.loadAllMaterialData()
  }

  async updateChar(data: CharacterModel): Promise<void> {
    await this.charDao.update(data.id, data)
    await this.loadAllMaterialData()
  }

  async deleteChar(id: string): Promise<void> {
    await this.charDao.delete(id)
    await this.loadAllMaterialData()
  }

  async insertCharOnly(data: CharacterModel): Promise<void> {
    await this.charDao.insert(data)
  }

  async updateCharOnly(data: CharacterModel): Promise<void> {
    await this.charDao.update(data.id, data)
  }

  async deleteCharOnly(id: string): Promise<void> {
    await this.charDao.delete(id)
  }

  async insertRelOnly(data: RelationshipModel): Promise<void> {
    await this.relDao.insert(data)
  }

  async deleteRelOnly(id: string): Promise<void> {
    await this.relDao.delete(id)
  }

  async updateWorldContent(id: string, content: string): Promise<void> {
    await this.wsDao.updateContent(id, content)
  }

  async deleteWorldOnly(id: string): Promise<void> {
    await this.wsDao.delete(id)
  }

  async loadAllMaterialData(): Promise<void> {
    if (this.currentBookId === '') {
      this.charactersList = await this.charDao.queryAll()
      if (this.charactersList.length === 0) {
        await this.seedDefaultChar()
        this.charactersList = await this.charDao.queryAll()
      }
      this.worldSettings = await this.wsDao.queryAll()
      if (this.worldSettings.length === 0) {
        await this.seedDefaultWorld()
        this.worldSettings = await this.wsDao.queryAll()
      } else {
        await this.cleanWorldDescriptions()
        this.worldSettings = await this.wsDao.queryAll()
      }
      this.inspirations = await this.inspDao.queryAll()
      return
    }
    this.charactersList = await this.charDao.queryByBook(this.currentBookId)
    if (this.charactersList.length === 0) {
      await this.seedDefaultChar()
      this.charactersList = await this.charDao.queryByBook(this.currentBookId)
    }
    this.worldSettings = await this.wsDao.queryByBook(this.currentBookId)
    if (this.worldSettings.length === 0) {
      await this.seedDefaultWorld()
      this.worldSettings = await this.wsDao.queryByBook(this.currentBookId)
    } else {
      await this.cleanWorldDescriptions()
      this.worldSettings = await this.wsDao.queryByBook(this.currentBookId)
    }
    this.inspirations = await this.inspDao.queryByBook(this.currentBookId)
  }

  async seedDefaultChar(): Promise<void> {
    const model: CharacterModel = {
      id: IdGenerator.generate(),
      bookId: this.currentBookId,
      name: '主角',
      alias: '',
      age: '',
      appearance: '',
      personality: '',
      background: '',
      notes: '',
      characterType: 'protagonist'
    }
    await this.charDao.insert(model)
  }

  async cleanWorldDescriptions(): Promise<void> {
    for (let i: number = 0; i < this.worldSettings.length; i++) {
      if (this.worldSettings[i].description === '点击编辑你的世界观...') {
        this.worldSettings[i].description = ''
        await this.wsDao.update(this.worldSettings[i].id, this.worldSettings[i])
      }
    }
  }

  async seedDefaultWorld(): Promise<void> {
    const model: WorldSettingModel = {
      id: IdGenerator.generate(),
      bookId: this.currentBookId,
      name: '世界设定',
      category: '',
      region: '',
      description: '',
      notes: '',
      content: ''
    }
    await this.wsDao.insert(model)
  }

  getDocListItems(): DocListItem[] {
    const items: DocListItem[] = []
    const colors: string[] = [PcColors.EMPHASIZE, PcColors.EMPHASIZE_DIMMED, PcColors.ACCENT_ORANGE, PcColors.ACCENT_BROWN]
    for (let i: number = 0; i < this.chapters.length; i++) {
      const ch: ChapterModel = this.chapters[i]
      const coverColor: string = colors[i % colors.length]
      const wc: number = ch.wordCount > 0 ? ch.wordCount : ch.content.length
      const prog: number = ch.content.length > 0 ? Math.min(1, Math.round(wc / 5000 * 100) / 100) : 0
      const summary: string = ch.content.length > 72 ? ch.content.substring(0, 72) + '...' : ch.content
      const expireMs: number = Date.now() - ch.updatedAt
      const expireDays: number = ch.isTrash ? WeaverViewModel.TRASH_DAYS - Math.floor(expireMs / 86400000) : 0
      items.push({
        id: ch.id,
        title: ch.title,
        subTitle: summary === '' ? '空白文稿，点击开始写作...' : summary,
        coverColor: coverColor,
        emoji: '📝',
        badge: wc > 0 ? wc.toString() + '字' : '',
        projectName: this.getBookName(ch.bookId),
        pinned: false,
        modified: formatRelativeTime(ch.updatedAt),
        wordCount: wc,
        selected: ch.id === this.currentChapterId,
        progress: prog,
        isTrash: ch.isTrash,
        expireDays: expireDays
      })
    }
    return items
  }

  getBookName(bookId: string): string {
    if (bookId === '') return ''
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === bookId)
    return book !== undefined ? book.name : ''
  }

  getProjectItems(): ProjectItem[] {
    const items: ProjectItem[] = []
    const colors: string[] = [PcColors.ACCENT_LIME, PcColors.EMPHASIZE_DIMMED, PcColors.ACCENT_BROWN, PcColors.ACCENT_PURPLE, PcColors.ACCENT_TEAL, PcColors.ACCENT_PINK]
    for (let i: number = 0; i < this.books.length; i++) {
      const b: BookModel = this.books[i]
      items.push({
        id: b.id,
        name: b.name,
        color: colors[i % colors.length],
        docCount: 0,
        active: b.id === this.currentBookId
      })
    }
    return items
  }

  async onSidebarLibChange(libId: string): Promise<void> {
    const libMap: Record<string, string> = {
      'all': '全部文稿', 'fav': '收藏', 'insp': '灵感池',
      'priv': '私密', 'trash': '废纸篓'
    }
    const label: string | undefined = libMap[libId]
    if (label !== undefined) {
      this.docListTitle = label
      this.currentLibFilter = libId
      this.showMidSeg = false
      if (libId === 'insp') {
        await this.loadChapters()
      } else {
        await this.loadChapters()
      }
      await this.updateLibCounts()
    }
  }

  async toggleFav(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      const newVal: boolean = !ch.isFav
      if (newVal) {
        await this.chapterDao.setInspiration(chapterId, false)
        await this.chapterDao.setFav(chapterId, true)
        ch.isInspiration = false
        ch.isFav = true
      } else {
        await this.chapterDao.setFav(chapterId, false)
        ch.isFav = false
      }
      await this.updateLibCounts()
      await this.loadChapters()
    }
  }

  async toggleInspiration(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      const newVal: boolean = !ch.isInspiration
      if (newVal) {
        await this.chapterDao.setFav(chapterId, false)
        await this.chapterDao.setInspiration(chapterId, true)
        ch.isFav = false
        ch.isInspiration = true
      } else {
        await this.chapterDao.setInspiration(chapterId, false)
        ch.isInspiration = false
      }
      await this.updateLibCounts()
      await this.loadChapters()
    }
  }

  async togglePrivate(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === chapterId)
    if (ch !== undefined) {
      const newVal: boolean = !ch.isPrivate
      if (newVal) {
        await this.chapterDao.setFav(chapterId, false)
        await this.chapterDao.setInspiration(chapterId, false)
        await this.chapterDao.setPrivate(chapterId, true)
        ch.isFav = false
        ch.isInspiration = false
        ch.isPrivate = true
      } else {
        await this.chapterDao.setPrivate(chapterId, false)
        ch.isPrivate = false
      }
      await this.updateLibCounts()
      await this.loadChapters()
    }
  }

  async trashChapter(chapterId: string): Promise<void> {
    await this.chapterDao.setTrash(chapterId, true)
    this.closeTab(chapterId)
    await this.cleanExpiredTrash()
    await this.loadChapters()
    await this.updateLibCounts()
  }

  async restoreChapter(chapterId: string): Promise<void> {
    const target: ChapterModel | null = await this.chapterDao.queryById(chapterId)
    if (target !== null) {
      const activeChapters: ChapterModel[] = await this.chapterDao.queryByBook(target.bookId)
      let newTitle: string = target.title
      let suffix: number = 2
      let isConflict: boolean = true
      while (isConflict) {
        isConflict = false
        for (let i: number = 0; i < activeChapters.length; i++) {
          if (activeChapters[i].title === newTitle) {
            newTitle = target.title + '(' + suffix + ')'
            suffix = suffix + 1
            isConflict = true
            break
          }
        }
      }
      if (newTitle !== target.title) {
        await this.chapterDao.update(chapterId, newTitle, target.content)
      }
    }
    await this.chapterDao.setTrash(chapterId, false)
    await this.loadChapters()
    await this.updateLibCounts()
  }

  async cleanExpiredTrash(): Promise<void> {
    const cutoff: number = Date.now() - WeaverViewModel.TRASH_DAYS * 24 * 60 * 60 * 1000
    await this.chapterDao.deleteExpiredTrash(cutoff)
    await this.updateLibCounts()
  }

  async loadTrashChapters(): Promise<void> {
    if (this.currentBookId === '') return
    this.chapters = await this.chapterDao.queryTrashByBook(this.currentBookId)
  }

  async updateLibCounts(): Promise<void> {
    if (this.currentBookId === '') {
      this.libCounts = await this.chapterDao.countGlobalByCategory()
      return
    }
    this.libCounts = await this.chapterDao.countByCategory(this.currentBookId)
  }

  async onChangeMidTab(mode: MidTabMode): Promise<void> {
    if (mode === MidTabMode.CHAPTERS) {
      this.editorViewMode = EditorViewMode.EDITOR
    } else if (mode === MidTabMode.MATERIALS) {
      this.editorViewMode = EditorViewMode.MATERIAL
      await this.loadAllMaterialData()
    } else {
      this.editorViewMode = EditorViewMode.GRAPH
    }
  }
}
