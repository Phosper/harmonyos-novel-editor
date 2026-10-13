// 章节（文稿）仓储 —— 用例级方法
//
// 读取分三条路径，别混用：
//   loadChapters()     列表用：正文只取前缀，不读 format_runs（见 ChapterDao.queryList）
//   loadOne()          打开文稿用：按 id 取完整正文与格式边车
//   loadChaptersFull() 备份导出用：整篇正文
import { relationalStore } from '@kit.ArkData'
import { ChapterDao, ChapterFilter } from '../database/ChapterDao'
import type { ChapterOrderStat } from '../database/ChapterDao'
import { IdGenerator } from '../utils/IdGenerator'
import type { ChapterModel } from '../model/Chapter'
import { ChapterFormat, TRASH_RETENTION_DAYS } from '../model/Chapter'
import { LibId, LibCounts } from '../constants/DesignTokens'

export class ChapterRepository {
  private dao: ChapterDao = new ChapterDao()

  /** 由 Repos.runInTransaction 调用：把写操作重定向到独立事务对象 */
  setTransaction(tx: relationalStore.Transaction | null): void {
    this.dao.setTransaction(tx)
  }

  // 按当前书籍与文库分类加载章节。
  // bookId === '' 表示"未归类"视图（book_id 为空串的文稿）；废纸篓不分书籍。
  async loadChapters(bookId: string, lib: LibId): Promise<ChapterModel[]> {
    return this.dao.queryList(ChapterRepository.filterFor(bookId, lib))
  }

  /**
   * 打开文稿：必须按 id 取**完整**正文。
   * 列表投影里的正文只有前缀，且内存里的 chapter 可能已被编辑过；
   * 直接用列表项当草稿初值会把旧正文写回去（关掉标签再打开即丢稿）。
   */
  async loadOne(chapterId: string): Promise<ChapterModel | null> {
    return this.dao.queryById(chapterId)
  }

  /** 整本导出 / 备份：需要每篇的完整正文与格式边车 */
  async loadChaptersFull(bookId: string): Promise<ChapterModel[]> {
    return this.dao.queryFull(ChapterRepository.filterFor(bookId, LibId.ALL))
  }

  private static filterFor(bookId: string, lib: LibId): ChapterFilter {
    const f: ChapterFilter = new ChapterFilter()
    if (lib === LibId.TRASH) {
      f.bookId = bookId === '' ? null : bookId
      f.trash = true
      return f
    }
    f.bookId = bookId
    f.trash = false
    if (lib === LibId.FAV) {
      f.fav = true
    } else if (lib === LibId.INSP) {
      f.inspiration = true
    } else {
      // 全部文稿：书籍内按手动顺序，未归类视图按最近修改
      f.orderBy = bookId === '' ? 'updated_at' : 'sort_order'
      f.ascending = bookId !== ''
    }
    return f
  }

  async createChapter(bookId: string, title?: string,
    format: ChapterFormat = ChapterFormat.TXT): Promise<ChapterModel> {
    // 序号与排序都取书籍内口径：全表口径会让不同项目的「无标题 N」重复，
    // 也会让同一本书内的 sort_order 被别的项目插入打乱。
    const stat: ChapterOrderStat = await this.dao.countAndMaxOrder(bookId)
    const raw: string = title !== undefined && title.trim() !== '' ? title.trim() : '无标题'
    const displayTitle: string = raw === '无标题' ? '无标题 ' + (stat.count + 1) : raw
    const now: number = Date.now()
    const ch: ChapterModel = {
      id: IdGenerator.generate(),
      bookId: bookId,
      title: displayTitle,
      content: '',
      format: format,
      order: stat.maxOrder + 1,
      wordCount: 0,
      caretOffset: 0,
      createdAt: now,
      updatedAt: now,
      isFav: false,
      isInspiration: false,
      isTrash: false
    }
    await this.dao.insert(ch)
    return ch
  }

  /** 直接写入一篇完整章节（备份恢复等场景，保留传入的 id/时间/标记） */
  async insertChapter(chapter: ChapterModel): Promise<void> {
    await this.dao.insert(chapter)
  }

  /** 只改标题：旧实现先读全文再连正文一起写回（改名这类高频操作不该搬动 1.75MB 的 TEXT） */
  async rename(chapterId: string, title: string): Promise<void> {
    await this.dao.updateTitle(chapterId, title.trim())
  }

  async updateContent(chapterId: string, content: string): Promise<void> {
    await this.dao.updateContent(chapterId, content)
  }

  /** 一次自动保存：正文 / 光标 / 格式边车走单条 UPDATE */
  async saveDraft(chapterId: string, content: string, caretOffset: number,
    formatRuns: string): Promise<void> {
    await this.dao.saveDraft(chapterId, content, caretOffset, formatRuns)
  }

  async setFormat(chapterId: string, format: ChapterFormat): Promise<void> {
    await this.dao.setFormat(chapterId, format)
  }

  async hardDelete(chapterId: string): Promise<void> {
    await this.dao.delete(chapterId)
  }

  async moveToBook(chapterId: string, bookId: string): Promise<void> {
    // 归档进某本书时清除全局文库标记（收藏/灵感只在未归类视图中维护）
    if (bookId !== '') {
      await this.dao.setFav(chapterId, false)
      await this.dao.setInspiration(chapterId, false)
    }
    await this.dao.moveToBook(chapterId, bookId)
  }

  async setFav(chapterId: string, value: boolean): Promise<void> {
    if (value) {
      await this.dao.setInspiration(chapterId, false)
    }
    await this.dao.setFav(chapterId, value)
  }

  async setInspiration(chapterId: string, value: boolean): Promise<void> {
    if (value) {
      await this.dao.setFav(chapterId, false)
    }
    await this.dao.setInspiration(chapterId, value)
  }

  async trash(chapterId: string): Promise<void> {
    await this.dao.setTrash(chapterId, true)
  }

  // 从废纸篓恢复，避免与现章节重名
  async restore(chapterId: string): Promise<void> {
    const target: ChapterModel | null = await this.dao.queryById(chapterId)
    if (target !== null) {
      // 重名检测只需要标题：旧实现先取回目标全文，再查询整本书（含全文）
      // 逐个比对，等于用「读全库正文」换一个标题字符串。
      const titles: string[] = await this.dao.activeTitles(target.bookId)
      let newTitle: string = target.title
      let suffix: number = 2
      while (titles.includes(newTitle)) {
        newTitle = target.title + '(' + suffix + ')'
        suffix++
      }
      if (newTitle !== target.title) {
        await this.dao.updateTitle(chapterId, newTitle)
      }
    }
    await this.dao.setTrash(chapterId, false)
  }

  async cleanExpiredTrash(): Promise<void> {
    const cutoff: number = Date.now() - TRASH_RETENTION_DAYS * 24 * 60 * 60 * 1000
    await this.dao.deleteExpiredTrash(cutoff)
  }

  async counts(bookId: string): Promise<LibCounts> {
    return this.dao.counts(bookId)
  }

  /** 每本书的有效文稿数（项目列表用） */
  async countActivePerBook(): Promise<Map<string, number>> {
    return this.dao.countActivePerBook()
  }
}
