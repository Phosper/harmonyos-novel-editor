// 项目与文稿列表状态
//
// 与旧实现的关键差异：
// 1. 不再把「书名」和「分类名」挤进同一个 docListTitle 字段（旧代码切到"全部文稿"
//    会把项目名覆盖掉），分类名与书名各归其位。
// 2. 列表项是身份稳定的 @ObservedV2 对象，数据变化时就地更新字段而不是重建数组，
//    配合 Repeat 只刷新受影响的行。
import { BookModel, BookMode } from '../model/Book'
import type { ChapterModel } from '../model/Chapter'
import { TRASH_RETENTION_DAYS } from '../model/Chapter'
import { LibId, LibCounts, EMPTY_LIB_COUNTS, DOC_TAB_COLORS, PROJECT_COLORS } from '../constants/DesignTokens'
import { DocItem, ProjectItem } from './StoreModels'
import { bookRepo, chapterRepo } from './Repos'
import { formatRelativeTime } from '../utils/TimeUtil'
import { countChars } from '../utils/TextLimit'

const SUMMARY_MAX: number = 72

@ObservedV2
export class ProjectStore {
  @Trace books: BookModel[] = []
  @Trace currentBookId: string = ''
  @Trace libFilter: LibId = LibId.ALL
  /**
   * 文库作用域：true = 跨项目的全局库（点侧栏「文库」进入），false = 当前项目内。
   * 列表与计数必须共用这一个作用域，否则会出现"侧栏 9 篇、列表只列当前项目 1 篇"。
   */
  @Trace libraryScope: boolean = false
  @Trace libCounts: LibCounts = EMPTY_LIB_COUNTS
  /** 当前筛选下的文稿原始模型 */
  @Trace chapters: ChapterModel[] = []
  /** 列表项（与 chapters 同步、身份稳定） */
  @Trace docItems: DocItem[] = []
  /** 项目列表项 */
  @Trace projects: ProjectItem[] = []
  private chapterLoadRev: number = 0
  private countLoadRev: number = 0
  private projectCountLoadRev: number = 0
  /** 预览字数缓存（每次按键只真正数一次） */
  private previewText: string = ''
  private previewValue: number = 0

  get currentBook(): BookModel | undefined {
    return this.books.find((b: BookModel) => b.id === this.currentBookId)
  }

  get bookName(): string {
    const b: BookModel | undefined = this.currentBook
    return b !== undefined ? b.name : ''
  }

  /** 分类标签（不含书名，避免与项目名互相覆盖） */
  get libLabel(): string {
    if (this.libFilter === LibId.FAV) return '收藏'
    if (this.libFilter === LibId.INSP) return '灵感池'
    if (this.libFilter === LibId.TRASH) return '废纸篓'
    if (this.currentBookId === '') return '未归类'
    return '全部文稿'
  }

  /** 列表头副标题里的作用域：全局库显示「全部项目」，否则显示当前项目名 */
  get scopeLabel(): string {
    return this.libraryScope ? '全部项目' : this.bookName
  }

  findChapter(chapterId: string): ChapterModel | undefined {
    return this.chapters.find((c: ChapterModel) => c.id === chapterId)
  }

  /** 标记当前选中项（由协调层在切换文稿后调用） */
  markSelected(chapterId: string): void {
    for (const item of this.docItems) {
      item.selected = item.id === chapterId
    }
  }

  // ===== 加载 =====

  async loadBooks(): Promise<void> {
    this.books = await bookRepo.getAllBooks()
    this.syncProjects()
  }

  /** 首次启动无项目时建一个（沿用引导页选定的写作模式）；已有项目则用第一个 */
  async ensureCurrentBook(defaultMode: BookMode): Promise<void> {
    if (this.books.length > 0) {
      this.setCurrentBook(this.books[0].id)
      return
    }
    const book: BookModel = await bookRepo.createBook('我的作品', defaultMode)
    this.registerBook(book)
    this.setCurrentBook(book.id)
  }

  /** 已提交的项目先发布，后续刷新失败也不能让用户误以为创建/恢复失败。 */
  registerBook(book: BookModel): void {
    if (!this.books.some((b: BookModel) => b.id === book.id)) {
      this.books.push(book)
    }
    this.syncProjects()
  }

  setCurrentBook(bookId: string): void {
    this.chapterLoadRev++
    this.countLoadRev++
    this.currentBookId = bookId
    this.libFilter = LibId.ALL
    // 选中项目 = 回到项目内视图（文库的全局筛选不跨项目保留）
    this.libraryScope = false
    this.chapters = []
    this.docItems = []
    this.libCounts = { all: 0, fav: 0, insp: 0, trash: 0 }
    this.syncProjects()
  }

  async reload(): Promise<void> {
    await this.loadBooks()
    await this.reloadChapters()
    await this.refreshCounts()
  }

  async reloadChapters(): Promise<void> {
    const request: number = ++this.chapterLoadRev
    const bookId: string = this.currentBookId
    const filter: LibId = this.libFilter
    const scope: boolean = this.libraryScope
    const chapters: ChapterModel[] = scope
      ? await chapterRepo.loadChaptersAll(filter)
      : await chapterRepo.loadChapters(bookId, filter)
    if (request !== this.chapterLoadRev || bookId !== this.currentBookId ||
      filter !== this.libFilter || scope !== this.libraryScope) {
      return
    }
    this.chapters = chapters
    this.syncDocItems()
  }

  async refreshCounts(): Promise<void> {
    const request: number = ++this.countLoadRev
    const bookId: string = this.currentBookId
    // 侧栏「文库」是全局库：计数必须跨项目合计，且与文库列表同一口径
    const counts: LibCounts = await chapterRepo.countsGlobal()
    if (request !== this.countLoadRev || bookId !== this.currentBookId) {
      return
    }
    this.libCounts = counts
    await this.refreshProjectDocCounts()
  }

  async refreshProjectDocCounts(): Promise<void> {
    const request: number = ++this.projectCountLoadRev
    const perBook: Map<string, number> = await chapterRepo.countActivePerBook()
    if (request !== this.projectCountLoadRev) {
      return
    }
    for (const p of this.projects) {
      p.docCount = perBook.get(p.id) ?? 0
    }
  }

  /**
   * 侧栏「文库」筛选：进入**跨项目**的全局库视图。
   * 即使 libFilter 没变（例如已在「全部文稿」的项目内视图里再点一次），
   * 也要从项目内切到全局库，所以这里不能按 lib 值提前 return。
   */
  async setLibFilter(lib: LibId): Promise<void> {
    if (this.libFilter === lib && this.libraryScope) {
      return
    }
    this.libFilter = lib
    this.libraryScope = true
    this.chapters = []
    this.docItems = []
    await this.reloadChapters()
    await this.refreshCounts()
  }

  async createBook(name: string, mode: BookMode): Promise<BookModel | null> {
    const trimmed: string = name.trim()
    if (trimmed === '') {
      return null
    }
    const book: BookModel = await bookRepo.createBook(trimmed, mode)
    await this.loadBooks()
    return book
  }

  // ===== 列表项同步（就地更新，保留身份） =====

  /**
   * 编辑中的实时列表预览：直接就地更新当前 DocItem 的副标题/字数/时间，
   * 不等待数据库防抖保存或 reloadChapters，保证中栏下一帧跟随右栏正文。
   * 只改字段、不重建数组/DocItem，避免整列重渲染。
   */
  updateDocPreview(id: string, content: string): void {
    const wc: number = this.countOf(content)
    const item: DocItem | undefined = this.docItems.find((d: DocItem) => d.id === id)
    if (item !== undefined) {
      item.subTitle = ProjectStore.summaryOf(content)
      item.wordCount = wc
      item.badge = wc > 0 ? wc.toString() + ' 字' : ''
      item.modified = formatRelativeTime(Date.now())
    }
    const chapter: ChapterModel | undefined = this.chapters.find((c: ChapterModel) => c.id === id)
    if (chapter !== undefined) {
      chapter.content = content
      chapter.wordCount = wc
      chapter.updatedAt = Date.now()
    }
  }

  /**
   * 每键都会走的字数统计：正文没变就复用上次结果。
   * 逐键对整篇 countChars 在 5 万字时是白描的开销；同一帧里 store 与预览各算一次更浪费。
   */
  private countOf(content: string): number {
    if (content !== this.previewText) {
      this.previewText = content
      this.previewValue = countChars(content)
    }
    return this.previewValue
  }

  private bookNameOf(bookId: string): string {
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === bookId)
    return book !== undefined ? book.name : ''
  }

  private syncDocItems(): void {
    const existing: Map<string, DocItem> = new Map<string, DocItem>()
    for (const item of this.docItems) {
      existing.set(item.id, item)
    }
    const colors: string[] = DOC_TAB_COLORS
    const next: DocItem[] = []
    for (let i: number = 0; i < this.chapters.length; i++) {
      const ch: ChapterModel = this.chapters[i]
      let item: DocItem | undefined = existing.get(ch.id)
      if (item === undefined) {
        item = new DocItem(ch.id)
      }
      // 旧数据可能没有 word_count，回退时按字符计（与新写入口径一致）
      const wc: number = ch.wordCount > 0 ? ch.wordCount : countChars(ch.content)
      item.title = ch.title
      item.projectName = this.libraryScope ? this.bookNameOf(ch.bookId) : ''
      item.subTitle = ProjectStore.summaryOf(ch.content)
      item.coverColor = colors[i % colors.length]
      item.badge = wc > 0 ? wc.toString() + ' 字' : ''
      item.modified = formatRelativeTime(ch.updatedAt)
      item.wordCount = wc
      item.isTrash = ch.isTrash
      item.expireDays = ch.isTrash
        ? Math.max(0, TRASH_RETENTION_DAYS - Math.floor((Date.now() - ch.updatedAt) / 86400000))
        : 0
      item.isFav = ch.isFav
      item.isInspiration = ch.isInspiration
      item.format = ch.format
      next.push(item)
    }
    this.docItems = next
  }

  private syncProjects(): void {
    const existing: Map<string, ProjectItem> = new Map<string, ProjectItem>()
    for (const item of this.projects) {
      existing.set(item.id, item)
    }
    const colors: string[] = PROJECT_COLORS
    const next: ProjectItem[] = []
    for (let i: number = 0; i < this.books.length; i++) {
      const b: BookModel = this.books[i]
      let item: ProjectItem | undefined = existing.get(b.id)
      if (item === undefined) {
        item = new ProjectItem(b.id)
      }
      item.name = b.name
      item.color = colors[i % colors.length]
      item.active = b.id === this.currentBookId
      next.push(item)
    }
    this.projects = next
  }

  /** 供列表显示的摘要（空白文稿给出引导文案） */
  static summaryOf(content: string): string {
    // 列表摘要最多展示 SUMMARY_MAX 字，只处理前缀即可；
    // 长文实时输入（每键调用）时避免对整篇正文做全局正则替换。
    const head: string = content.length > SUMMARY_MAX * 4
      ? content.substring(0, SUMMARY_MAX * 4) : content
    const flat: string = head.replace(new RegExp('\\s+', 'g'), ' ').trim()
    if (flat === '') {
      return '空白文稿，点击开始写作…'
    }
    return flat.length > SUMMARY_MAX ? flat.substring(0, SUMMARY_MAX) + '…' : flat
  }
}
