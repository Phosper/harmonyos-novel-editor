// 章节（文稿）DAO
// 查询收敛为参数化的 query(filter)：旧版 17 个仅谓词不同的方法（queryByBook / queryFavByBook /
// queryGlobalInsp / ... ）全部由 ChapterFilter 表达，避免复制粘贴。
// 计数改为单条 SQL 聚合（旧版 countWhere 会把整表行连正文一起读出来只为了数个数）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { Logger } from '../utils/Logger'
import { MAX_CONTENT_BYTES, exceedsContentLimit, utf8ByteLength, contentLimitMessage, countChars } from '../utils/TextLimit'
import type { ChapterModel } from '../model/Chapter'
import { ChapterFormat } from '../model/Chapter'
import type { LibCounts } from '../constants/DesignTokens'

function toChapterFormat(val: string): ChapterFormat {
  return val === ChapterFormat.MD ? ChapterFormat.MD : ChapterFormat.TXT
}

/** 书籍内的文稿数量与最大排序值（新建文稿时一次算出序号与 sort_order） */
export interface ChapterOrderStat {
  count: number
  maxOrder: number
}

/** 章节查询条件 */
export class ChapterFilter {
  /** 限定书籍；null = 不限书籍，'' = 仅未归类文稿 */
  bookId: string | null = null
  /** 只取收藏 */
  fav: boolean = false
  /** 只取灵感池 */
  inspiration: boolean = false
  /** true = 取废纸篓；false = 取正常文稿 */
  trash: boolean = false
  /** 排序字段（数据库列名） */
  orderBy: string = 'updated_at'
  /** 是否升序 */
  ascending: boolean = false

  static scoped(bookId: string): ChapterFilter {
    const f: ChapterFilter = new ChapterFilter()
    f.bookId = bookId
    return f
  }
}

export class ChapterDao extends BaseDao<ChapterModel> {
  protected getTableName(): string {
    return 'chapters'
  }

  protected rowToModel(rs: relationalStore.ResultSet): ChapterModel {
    return {
      id: this.safeGetString(rs, 'id'),
      bookId: this.safeGetString(rs, 'book_id'),
      title: this.safeGetString(rs, 'title'),
      content: this.safeGetString(rs, 'content'),
      format: toChapterFormat(this.safeGetString(rs, 'format')),
      order: this.safeGetLong(rs, 'sort_order'),
      wordCount: this.safeGetLong(rs, 'word_count'),
      caretOffset: this.safeGetLong(rs, 'caret_offset'),
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at'),
      isFav: this.safeGetBool(rs, 'is_fav'),
      isInspiration: this.safeGetBool(rs, 'is_inspiration'),
      isTrash: this.safeGetBool(rs, 'is_trash'),
      formatRuns: this.safeGetString(rs, 'format_runs')
    }
  }

  // ===== 写入 =====
  async insert(chapter: ChapterModel): Promise<void> {
    ChapterDao.assertContentWithinLimit(chapter.content)
    const valueBucket: relationalStore.ValuesBucket = {
      id: chapter.id,
      book_id: chapter.bookId,
      title: chapter.title,
      content: chapter.content,
      format: chapter.format,
      sort_order: chapter.order,
      word_count: chapter.wordCount,
      caret_offset: chapter.caretOffset,
      is_fav: chapter.isFav ? 1 : 0,
      is_inspiration: chapter.isInspiration ? 1 : 0,
      is_trash: chapter.isTrash ? 1 : 0,
      format_runs: chapter.formatRuns !== undefined ? chapter.formatRuns : '',
      created_at: chapter.createdAt,
      updated_at: chapter.updatedAt
    }
    await this.insertRow(valueBucket)
  }

  async updateContent(id: string, content: string): Promise<void> {
    ChapterDao.assertContentWithinLimit(content)
    await this.updateColumns(id, {
      content: content,
      word_count: countChars(content),
      updated_at: Date.now()
    })
  }

  async updateTitleAndContent(id: string, title: string, content: string): Promise<void> {
    ChapterDao.assertContentWithinLimit(content)
    await this.updateColumns(id, {
      title: title,
      content: content,
      word_count: countChars(content),
      updated_at: Date.now()
    })
  }

  /** 仅记录光标位置：不改 updated_at，避免光标移动把文稿顶到"最近修改"最前 */
  async updateCaretOffset(id: string, offset: number): Promise<void> {
    await this.updateColumns(id, { caret_offset: offset })
  }

  /** 写入行内/段落格式标注边车（T025） */
  async updateFormatRuns(id: string, json: string): Promise<void> {
    await this.updateColumns(id, { format_runs: json })
  }

  async moveToBook(chapterId: string, bookId: string): Promise<void> {
    await this.updateColumns(chapterId, { book_id: bookId, updated_at: Date.now() })
  }

  setFav(id: string, fav: boolean): Promise<void> {
    return this.updateColumns(id, { is_fav: fav ? 1 : 0, updated_at: Date.now() })
  }

  setInspiration(id: string, insp: boolean): Promise<void> {
    return this.updateColumns(id, { is_inspiration: insp ? 1 : 0, updated_at: Date.now() })
  }

  setTrash(id: string, trash: boolean): Promise<void> {
    return this.updateColumns(id, { is_trash: trash ? 1 : 0, updated_at: Date.now() })
  }

  async setFormat(id: string, format: ChapterFormat): Promise<void> {
    await this.updateColumns(id, { format: format })
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  async deleteExpiredTrash(cutoff: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('is_trash', 1)
    predicates.lessThan('updated_at', cutoff)
    await this.deleteRow(predicates)
  }

  /**
   * 正文容量守卫：DAO 是最后一道防线，导入、自动保存、备份恢复都从这里过。
   * 超限时直接抛错，避免"写进去了但读不出来"的静默损坏。
   */
  private static assertContentWithinLimit(content: string): void {
    if (exceedsContentLimit(content)) {
      const bytes: number = utf8ByteLength(content)
      Logger.error('Chapter content too large: ' + bytes + ' bytes > ' + MAX_CONTENT_BYTES)
      throw new Error(contentLimitMessage())
    }
  }

  private async updateColumns(id: string, values: relationalStore.ValuesBucket): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(values, predicates)
  }

  // ===== 查询 =====
  async queryById(id: string): Promise<ChapterModel | null> {
    return this.queryByIdRow(id)
  }

  async query(filter: ChapterFilter): Promise<ChapterModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    if (filter.bookId !== null) {
      p.equalTo('book_id', filter.bookId)
    }
    if (filter.fav) {
      p.equalTo('is_fav', 1)
    }
    if (filter.inspiration) {
      p.equalTo('is_inspiration', 1)
    }
    p.equalTo('is_trash', filter.trash ? 1 : 0)
    if (filter.ascending) {
      p.orderByAsc(filter.orderBy)
    } else {
      p.orderByDesc(filter.orderBy)
    }
    return this.queryRows(p)
  }

  /**
   * 指定书籍下的未删除文稿数与最大 sort_order（一次聚合）。
   *
   * 新建文稿的序号与排序都必须是**书籍内**口径：旧实现用全表 countActive()
   * 既让「无标题 N」在不同项目间重复，又让 sort_order 跨项目交错，
   * 结果是同一本书里的顺序不连续、且随别的项目新增而变化。
   */
  async countAndMaxOrder(bookId: string): Promise<ChapterOrderStat> {
    const sql: string = 'SELECT COUNT(*) AS c, COALESCE(MAX(sort_order), -1) AS m ' +
      'FROM chapters WHERE is_trash = 0 AND book_id = ?'
    const args: relationalStore.ValueType[] = [bookId]
    const rs: relationalStore.ResultSet = await this.getStore().querySql(sql, args)
    let stat: ChapterOrderStat = { count: 0, maxOrder: -1 }
    if (rs.goToFirstRow()) {
      stat.count = this.safeGetLong(rs, 'c')
      stat.maxOrder = this.safeGetLong(rs, 'm')
    }
    rs.close()
    return stat
  }

  /** 各书籍的有效文稿数（一次分组查询，供项目列表显示；不含已删除） */
  async countActivePerBook(): Promise<Map<string, number>> {
    const rs: relationalStore.ResultSet = await this.getStore()
      .querySql('SELECT book_id, COUNT(*) AS c FROM chapters WHERE is_trash = 0 GROUP BY book_id')
    const result: Map<string, number> = new Map<string, number>()
    while (rs.goToNextRow()) {
      result.set(this.safeGetString(rs, 'book_id'), this.safeGetLong(rs, 'c'))
    }
    rs.close()
    return result
  }

  /**
   * 一次聚合出各文库计数（旧版 4~5 次查询，且每次都要读全表行）。
   * 计数口径以 bookId 为界：'' → 仅未归类文稿，其余 → 该书籍。
   */
  async counts(bookId: string): Promise<LibCounts> {
    const sql: string = 'SELECT ' +
      'COALESCE(SUM(CASE WHEN is_trash = 0 THEN 1 ELSE 0 END), 0) AS c_all, ' +
      'COALESCE(SUM(CASE WHEN is_fav = 1 AND is_trash = 0 THEN 1 ELSE 0 END), 0) AS c_fav, ' +
      'COALESCE(SUM(CASE WHEN is_inspiration = 1 AND is_trash = 0 THEN 1 ELSE 0 END), 0) AS c_insp, ' +
      'COALESCE(SUM(CASE WHEN is_trash = 1 THEN 1 ELSE 0 END), 0) AS c_trash ' +
      'FROM chapters WHERE book_id = ?'
    const args: relationalStore.ValueType[] = [bookId]
    const rs: relationalStore.ResultSet = await this.getStore().querySql(sql, args)
    const result: LibCounts = { all: 0, fav: 0, insp: 0, trash: 0 }
    if (rs.goToFirstRow()) {
      result.all = this.safeGetLong(rs, 'c_all')
      result.fav = this.safeGetLong(rs, 'c_fav')
      result.insp = this.safeGetLong(rs, 'c_insp')
      result.trash = this.safeGetLong(rs, 'c_trash')
    }
    rs.close()
    return result
  }
}
