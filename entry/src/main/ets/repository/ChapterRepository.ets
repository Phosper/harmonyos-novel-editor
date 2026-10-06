// 章节（文稿）仓储 —— 用例级方法
import { ChapterDao, ChapterFilter } from '../database/ChapterDao'
import type { ChapterOrderStat } from '../database/ChapterDao'
import { IdGenerator } from '../utils/IdGenerator'
import type { ChapterModel } from '../model/Chapter'
import { ChapterFormat, TRASH_RETENTION_DAYS } from '../model/Chapter'
import { LibId, LibCounts } from '../constants/DesignTokens'

export class ChapterRepository {
  private dao: ChapterDao = new ChapterDao()

  // 按当前书籍与文库分类加载章节。
  // bookId === '' 表示"未归类"视图（book_id 为空串的文稿）；废纸篓不分书籍。
  async loadChapters(bookId: string, lib: LibId): Promise<ChapterModel[]> {
    const f: ChapterFilter = new ChapterFilter()
    if (lib === LibId.TRASH) {
      f.bookId = bookId === '' ? null : bookId
      f.trash = true
      return this.dao.query(f)
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
    return this.dao.query(f)
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

  async rename(chapterId: string, title: string): Promise<void> {
    const ch: ChapterModel | null = await this.dao.queryById(chapterId)
    if (ch === null) {
      return
    }
    await this.dao.updateTitleAndContent(chapterId, title.trim(), ch.content)
  }

  async updateContent(chapterId: string, content: string): Promise<void> {
    await this.dao.updateContent(chapterId, content)
  }

  async updateCaretOffset(chapterId: string, offset: number): Promise<void> {
    await this.dao.updateCaretOffset(chapterId, offset)
  }

  /** 写入格式标注边车（T025） */
  async updateFormatRuns(chapterId: string, json: string): Promise<void> {
    await this.dao.updateFormatRuns(chapterId, json)
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
      const f: ChapterFilter = new ChapterFilter()
      f.bookId = target.bookId
      f.orderBy = 'sort_order'
      f.ascending = true
      const active: ChapterModel[] = await this.dao.query(f)
      let newTitle: string = target.title
      let suffix: number = 2
      let conflict: boolean = true
      while (conflict) {
        conflict = false
        for (const c of active) {
          if (c.title === newTitle) {
            newTitle = target.title + '(' + suffix + ')'
            suffix++
            conflict = true
            break
          }
        }
      }
      if (newTitle !== target.title) {
        await this.dao.updateTitleAndContent(chapterId, newTitle, target.content)
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
