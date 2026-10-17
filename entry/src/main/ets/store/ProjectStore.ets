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
    const chapters: ChapterModel[] = await chapterRepo.loadChapters(bookId, filter)
    if (request !== this.chapterLoadRev || bookId !== this.currentBookId || filter !== this.libFilter) {
      return
    }
    this.chapters = chapters
    this.syncDocItems()
  }

  async refreshCounts(): Promise<void> {
    const request: number = ++this.countLoadRev
    const bookId: string = this.currentBookId
    const counts: LibCounts = await chapterRepo.counts(bookId)
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

  async setLibFilter(lib: LibId): Promise<void> {
    if (this.libFilter === lib) {
      return
    }
    this.libFilter = lib
    this.chapters = []
    this.docItems = []
    await this.reloadChapters()
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
    const flat: string = content.replace(new RegExp('\\s+', 'g'), ' ').trim()
    if (flat === '') {
      return '空白文稿，点击开始写作…'
    }
    return flat.length > SUMMARY_MAX ? flat.substring(0, SUMMARY_MAX) + '…' : flat
  }
}
