// 章节（文稿）DAO
// 查询收敛为参数化的 query(filter)：旧版 17 个仅谓词不同的方法（queryByBook / queryFavByBook /
// queryGlobalInsp / ... ）全部由 ChapterFilter 表达，避免复制粘贴。
// 计数改为单条 SQL 聚合（旧版 countWhere 会把整表行连正文一起读出来只为了数个数）。
//
// 列表与全文两条读取路径：
//   queryList() —— 列表用。正文只取前缀、不读 format_runs，避免把每篇全文搬进内存。
//   queryFull() —— 备份导出等确实需要全文的场景。
//   单篇全文用 queryById()。
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

/**
 * 列表投影里保留的正文前缀长度（码元）。
 * 列表项只显示 72 字摘要，512 足够且能把单行读数从 1.75MB 降到几百字节。
 */
const LIST_CONTENT_CHARS: number = 512

/**
 * 列表投影列。两点取舍：
 * 1. 不含 format_runs（格式边车 JSON 可能很大，列表完全用不到）；
 * 2. 正文用 substr 裁成前缀；word_count 为 0 的旧数据用 length(content) 兜底，
 *    免得列表把有内容的文稿显示成「0 字」。
 */
const LIST_SQL_COLUMNS: string = 'id, book_id, title, format, sort_order, ' +
  'CASE WHEN word_count > 0 THEN word_count ELSE length(content) END AS word_count, ' +
  'caret_offset, is_fav, is_inspiration, is_trash, created_at, updated_at, ' +
  'substr(content, 1, ' + LIST_CONTENT_CHARS + ') AS content'

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

  /**
   * 一次自动保存的正文 / 光标 / 格式边车合并为**单条** UPDATE。
   *
   * 旧实现拆成 3 条（正文 / 光标 / 格式边车），即 3 次写事务：
   * 中途失败会留下「正文已更新、格式边车还是旧的」半更新状态，重试还会重复前两条。
   * 光标位置原本刻意不写 updated_at（避免光标移动把文稿顶到「最近修改」最前），
   * 但正文写入本来就会更新它，合并后语义不变。
   */
  async saveDraft(id: string, content: string, caretOffset: number, formatRuns: string): Promise<void> {
    ChapterDao.assertContentWithinLimit(content)
    await this.updateColumns(id, {
      content: content,
      word_count: countChars(content),
      caret_offset: caretOffset,
      format_runs: formatRuns,
      updated_at: Date.now()
    })
  }

  /** 只改标题：不再为了改名把整篇正文读出来再原样写回去 */
  async updateTitle(id: string, title: string): Promise<void> {
    await this.updateColumns(id, { title: title, updated_at: Date.now() })
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

  /** 单篇**完整**记录（含正文与格式边车）：打开文稿走这里 */
  async queryById(id: string): Promise<ChapterModel | null> {
    return this.queryByIdRow(id)
  }

  /**
   * 列表查询：正文只取前缀、不读 format_runs。
   *
   * 旧实现走 queryRows → SELECT *，会把**当前项目每篇文稿的全文**读进主线程；
   * 单篇上限 1.75MB，而切项目 / 切文库 / 收藏 / 重命名 / 改格式都会重跑它，
   * 20 篇长文即可带来数十 MB 主线程字符串与大量 IO。列表只需要摘要与字数。
   *
   * 排序字段经白名单校验后才拼进 SQL（值一律走 bindArgs，不做字符串拼接）。
   */
  async queryList(filter: ChapterFilter): Promise<ChapterModel[]> {
    const where: string[] = ['is_trash = ?']
    const args: relationalStore.ValueType[] = [filter.trash ? 1 : 0]
    if (filter.bookId !== null) {
      where.push('book_id = ?')
      args.push(filter.bookId)
    }
    if (filter.fav) {
      where.push('is_fav = 1')
    }
    if (filter.inspiration) {
      where.push('is_inspiration = 1')
    }
    const sql: string = 'SELECT ' + LIST_SQL_COLUMNS + ' FROM chapters WHERE ' + where.join(' AND ') +
      ' ORDER BY ' + ChapterDao.safeOrderColumn(filter.orderBy) + (filter.ascending ? ' ASC' : ' DESC')
    return this.querySqlRows(sql, args)
  }

  /** 全文查询：备份导出等确实需要整篇正文的场景 */
  async queryFull(filter: ChapterFilter): Promise<ChapterModel[]> {
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

  /** 排序字段白名单：这个值会被拼进 SQL，只接受已知列名 */
  private static safeOrderColumn(name: string): string {
    return name === 'sort_order' ? 'sort_order' : 'updated_at'
  }

  /** 指定书籍下未删除文稿的标题：恢复重名检测只需标题，不再拉回全表正文 */
  async activeTitles(bookId: string): Promise<string[]> {
    const sql: string = 'SELECT title FROM chapters WHERE is_trash = 0 AND book_id = ?'
    const args: relationalStore.ValueType[] = [bookId]
    const rs: relationalStore.ResultSet = await this.getStore().querySql(sql, args)
    const titles: string[] = []
    try {
      while (rs.goToNextRow()) {
        titles.push(this.safeGetString(rs, 'title'))
      }
      return titles
    } finally {
      this.closeQuietly(rs)
    }
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
    const stat: ChapterOrderStat = { count: 0, maxOrder: -1 }
    try {
      if (rs.goToFirstRow()) {
        stat.count = this.safeGetLong(rs, 'c')
        stat.maxOrder = this.safeGetLong(rs, 'm')
      }
      return stat
    } finally {
      this.closeQuietly(rs)
    }
  }

  /** 各书籍的有效文稿数（一次分组查询，供项目列表显示；不含已删除） */
  async countActivePerBook(): Promise<Map<string, number>> {
    const rs: relationalStore.ResultSet = await this.getStore()
      .querySql('SELECT book_id, COUNT(*) AS c FROM chapters WHERE is_trash = 0 GROUP BY book_id')
    const result: Map<string, number> = new Map<string, number>()
    try {
      while (rs.goToNextRow()) {
        result.set(this.safeGetString(rs, 'book_id'), this.safeGetLong(rs, 'c'))
      }
      return result
    } finally {
      this.closeQuietly(rs)
    }
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
    try {
      if (rs.goToFirstRow()) {
        result.all = this.safeGetLong(rs, 'c_all')
        result.fav = this.safeGetLong(rs, 'c_fav')
        result.insp = this.safeGetLong(rs, 'c_insp')
        result.trash = this.safeGetLong(rs, 'c_trash')
      }
      return result
    } finally {
      this.closeQuietly(rs)
    }
  }
}
