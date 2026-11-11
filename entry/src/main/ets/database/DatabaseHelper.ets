// 数据库助手 —— 单例，RelationalStore 初始化与建表
// 建表采用最终 clean schema（book_id 可空）；对已存在的旧库，新增列走 ensureColumns()
// 做幂等的 ALTER TABLE 补齐（只增列、不改列、不删列），不做有损迁移。
import { relationalStore } from '@kit.ArkData'
import { Logger } from '../utils/Logger'

const DB_NAME: string = 'Weaver.db'
const DB_VERSION: number = 2

// 期望存在的列（列名 + 完整列定义）。旧库缺失时由 ensureColumns() 补齐。
const EXPECTED_COLUMNS: string[][] = [
  ['chapters', "format TEXT NOT NULL DEFAULT 'txt'"],
  ['chapters', 'caret_offset INTEGER NOT NULL DEFAULT 0'],
  ['chapters', "format_runs TEXT NOT NULL DEFAULT ''"]
]

export class DatabaseHelper {
  private store: relationalStore.RdbStore | null = null
  private static instance: DatabaseHelper | null = null

  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper()
    }
    return DatabaseHelper.instance
  }

  async init(context: Context): Promise<relationalStore.RdbStore> {
    if (this.store) {
      return this.store
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    }
    try {
      // store 先放局部变量：建表/补列任一句失败时 this.store 必须保持 null。
      // 旧实现先赋值再建表，DDL 失败后 UI 的「重试」会在开头直接返回一个
      // 「建表没做完」的 store，后续所有查询持续报 14800021 且重试永远修不好。
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config)
      await store.executeSql('PRAGMA foreign_keys = ON')
      await this.createTables(store)
      await this.ensureColumns(store)
      await this.ensurePlacementUniqueIndex(store)
      this.store = store
      Logger.info('Database initialized (version ' + DB_VERSION + ')')
    } catch (e) {
      this.store = null
      Logger.error('Database init failed: ' + String(e))
      throw new Error(String(e))
    }
    return this.store
  }

  /**
   * 同板同卡唯一约束：先查是否还有重复，没有才建索引。
   * 有重复时只记日志、跳过，等本轮启动后的读侧 normalizeDuplicates 清完，
   * 下次启动再建——这样既有数据不会把启动流程炸掉。
   */
  private async ensurePlacementUniqueIndex(store: relationalStore.RdbStore): Promise<void> {
    try {
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT canvas_id, topic_id FROM canvas_placements ' +
        'GROUP BY canvas_id, topic_id HAVING COUNT(*) > 1 LIMIT 1')
      let hasDuplicate: boolean = false
      if (rs !== undefined) {
        hasDuplicate = rs.goToFirstRow()
        rs.close()
      }
      if (hasDuplicate) {
        Logger.warn('Canvas: duplicate placements exist, skip unique index until next launch')
        return
      }
      await store.executeSql(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_placement_card ON canvas_placements(canvas_id, topic_id)')
    } catch (e) {
      Logger.warn('Canvas: ensurePlacementUniqueIndex failed: ' + String(e))
    }
  }

  private async createTables(store: relationalStore.RdbStore): Promise<void> {
    const sqls: string[] = [
      'CREATE TABLE IF NOT EXISTS books (' +
        'id TEXT PRIMARY KEY,' +
        'name TEXT NOT NULL,' +
        "mode TEXT NOT NULL DEFAULT 'professional'," +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL' +
        ')',
      'CREATE TABLE IF NOT EXISTS chapters (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT,' +
        'title TEXT NOT NULL,' +
        "content TEXT NOT NULL DEFAULT ''," +
        "format TEXT NOT NULL DEFAULT 'txt'," +
        "format_runs TEXT NOT NULL DEFAULT ''," +
        'sort_order INTEGER NOT NULL DEFAULT 0,' +
        'word_count INTEGER NOT NULL DEFAULT 0,' +
        'caret_offset INTEGER NOT NULL DEFAULT 0,' +
        'is_fav INTEGER NOT NULL DEFAULT 0,' +
        'is_inspiration INTEGER NOT NULL DEFAULT 0,' +
        'is_trash INTEGER NOT NULL DEFAULT 0,' +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL,' +
        'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS characters (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT,' +
        'name TEXT NOT NULL,' +
        "alias TEXT NOT NULL DEFAULT ''," +
        "age TEXT NOT NULL DEFAULT ''," +
        "appearance TEXT NOT NULL DEFAULT ''," +
        "personality TEXT NOT NULL DEFAULT ''," +
        "background TEXT NOT NULL DEFAULT ''," +
        "notes TEXT NOT NULL DEFAULT ''," +
        "character_type TEXT NOT NULL DEFAULT 'support'," +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL,' +
        'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS world_settings (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT,' +
        'name TEXT NOT NULL,' +
        "category TEXT NOT NULL DEFAULT 'other'," +
        "region TEXT NOT NULL DEFAULT ''," +
        "description TEXT NOT NULL DEFAULT ''," +
        "notes TEXT NOT NULL DEFAULT ''," +
        "content TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL,' +
        'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS inspirations (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT,' +
        'content TEXT NOT NULL,' +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL,' +
        'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE SET NULL' +
        ')',
      'CREATE TABLE IF NOT EXISTS relationships (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT NOT NULL,' +
        'char_a_id TEXT NOT NULL,' +
        'char_b_id TEXT NOT NULL,' +
        "type TEXT NOT NULL DEFAULT 'neutral'," +
        "label TEXT NOT NULL DEFAULT ''," +
        "notes TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL,' +
        'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,' +
        'FOREIGN KEY (char_a_id) REFERENCES characters(id) ON DELETE CASCADE,' +
        'FOREIGN KEY (char_b_id) REFERENCES characters(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS topics (' +
        'id TEXT PRIMARY KEY,' +
        'book_id TEXT,' +
        "kind TEXT NOT NULL DEFAULT 'concept'," +
        'title TEXT NOT NULL,' +
        "aliases TEXT NOT NULL DEFAULT ''," +
        "tags TEXT NOT NULL DEFAULT ''," +
        "my_summary TEXT NOT NULL DEFAULT ''," +
        'doc_id TEXT,' +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL' +
        ')',
      'CREATE TABLE IF NOT EXISTS topic_evidence (' +
        'id TEXT PRIMARY KEY,' +
        'topic_id TEXT NOT NULL,' +
        'kind TEXT NOT NULL,' +
        'doc_id TEXT,' +
        'para_index INTEGER NOT NULL DEFAULT 0,' +
        'start_off INTEGER NOT NULL DEFAULT 0,' +
        'end_off INTEGER NOT NULL DEFAULT 0,' +
        "fingerprint TEXT NOT NULL DEFAULT ''," +
        "quote_text TEXT NOT NULL DEFAULT ''," +
        "user_text TEXT NOT NULL DEFAULT ''," +
        "source_label TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS canvases (' +
        'id TEXT PRIMARY KEY,' +
        'scope TEXT NOT NULL,' +
        'book_id TEXT,' +
        "title TEXT NOT NULL DEFAULT ''," +
        'pan_x REAL NOT NULL DEFAULT 0,' +
        'pan_y REAL NOT NULL DEFAULT 0,' +
        'zoom REAL NOT NULL DEFAULT 1,' +
        'sort_order INTEGER NOT NULL DEFAULT 0,' +
        'created_at INTEGER NOT NULL,' +
        'updated_at INTEGER NOT NULL' +
        ')',
      'CREATE TABLE IF NOT EXISTS canvas_placements (' +
        'id TEXT PRIMARY KEY,' +
        'canvas_id TEXT NOT NULL,' +
        'topic_id TEXT NOT NULL,' +
        "parent_id TEXT NOT NULL DEFAULT ''," +
        'ord INTEGER NOT NULL DEFAULT 0,' +
        'x REAL NOT NULL DEFAULT 0,' +
        'y REAL NOT NULL DEFAULT 0,' +
        'z INTEGER NOT NULL DEFAULT 0,' +
        'collapsed INTEGER NOT NULL DEFAULT 0,' +
        "style TEXT NOT NULL DEFAULT ''," +
        'FOREIGN KEY (canvas_id) REFERENCES canvases(id) ON DELETE CASCADE,' +
        'FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS canvas_links (' +
        'id TEXT PRIMARY KEY,' +
        'canvas_id TEXT NOT NULL,' +
        'from_topic_id TEXT NOT NULL,' +
        'to_topic_id TEXT NOT NULL,' +
        'kind TEXT NOT NULL,' +
        "label TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'FOREIGN KEY (canvas_id) REFERENCES canvases(id) ON DELETE CASCADE,' +
        'FOREIGN KEY (from_topic_id) REFERENCES topics(id) ON DELETE CASCADE,' +
        'FOREIGN KEY (to_topic_id) REFERENCES topics(id) ON DELETE CASCADE' +
        ')',
      // P5：段落稳定身份。正文仍以 chapters.content 为旧读路径，段落表先做侧车；
      // 启动迁移把缺侧车的老文稿按换行拆段，写路径切换前不改变编辑器行为。
      'CREATE TABLE IF NOT EXISTS doc_paragraphs (' +
        'doc_id TEXT NOT NULL,' +
        'para_id TEXT NOT NULL,' +
        'ordinal REAL NOT NULL,' +
        'kind INTEGER NOT NULL DEFAULT 0,' +
        'indent INTEGER NOT NULL DEFAULT 0,' +
        "text TEXT NOT NULL DEFAULT ''," +
        'PRIMARY KEY (doc_id, para_id),' +
        'FOREIGN KEY (doc_id) REFERENCES chapters(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS doc_runs (' +
        'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        'doc_id TEXT NOT NULL,' +
        'para_id TEXT NOT NULL,' +
        'start_off INTEGER NOT NULL,' +
        'end_off INTEGER NOT NULL,' +
        'bold INTEGER NOT NULL DEFAULT 0,' +
        'italic INTEGER NOT NULL DEFAULT 0,' +
        'FOREIGN KEY (doc_id, para_id) REFERENCES doc_paragraphs(doc_id, para_id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS schema_meta (' +
        'meta_key TEXT PRIMARY KEY,' +
        "meta_value TEXT NOT NULL DEFAULT ''," +
        'updated_at INTEGER NOT NULL' +
        ')',
      // M5：导图的附加信息。概要与关系线不属于文章结构（不写正文、不进版本号），
      // 所以单独成表，随 chapters 级联删除。
      'CREATE TABLE IF NOT EXISTS doc_map_summary (' +
        'chapter_id TEXT NOT NULL,' +
        'summary_id TEXT NOT NULL,' +
        'start_para_id TEXT NOT NULL,' +
        'end_para_id TEXT NOT NULL,' +
        "text TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'PRIMARY KEY (chapter_id, summary_id),' +
        'FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE' +
        ')',
      'CREATE TABLE IF NOT EXISTS doc_map_relation (' +
        'chapter_id TEXT NOT NULL,' +
        'relation_id TEXT NOT NULL,' +
        'from_para_id TEXT NOT NULL,' +
        'to_para_id TEXT NOT NULL,' +
        "label TEXT NOT NULL DEFAULT ''," +
        "kind TEXT NOT NULL DEFAULT 'relate'," +
        'created_at INTEGER NOT NULL,' +
        'PRIMARY KEY (chapter_id, relation_id),' +
        'FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE' +
        ')',
      // M6：单个主题的样式（形状/填充/加粗/标记/标签）。只存"改过"的段落，
      // 没改过的跟随全局设置，所以这张表通常很小。
      'CREATE TABLE IF NOT EXISTS doc_map_node (' +
        'chapter_id TEXT NOT NULL,' +
        'para_id TEXT NOT NULL,' +
        "shape TEXT NOT NULL DEFAULT ''," +
        "fill TEXT NOT NULL DEFAULT ''," +
        'bold INTEGER NOT NULL DEFAULT 0,' +
        "markers TEXT NOT NULL DEFAULT ''," +
        "label TEXT NOT NULL DEFAULT ''," +
        'updated_at INTEGER NOT NULL,' +
        'PRIMARY KEY (chapter_id, para_id),' +
        'FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE' +
        ')',
      // X2：外框（把同层的一段主题圈起来）
      'CREATE TABLE IF NOT EXISTS doc_map_boundary (' +
        'chapter_id TEXT NOT NULL,' +
        'boundary_id TEXT NOT NULL,' +
        'start_para_id TEXT NOT NULL,' +
        'end_para_id TEXT NOT NULL,' +
        "text TEXT NOT NULL DEFAULT ''," +
        'created_at INTEGER NOT NULL,' +
        'PRIMARY KEY (chapter_id, boundary_id),' +
        'FOREIGN KEY (chapter_id) REFERENCES chapters(id) ON DELETE CASCADE' +
        ')',
      'CREATE INDEX IF NOT EXISTS idx_canvas_book ON canvases(book_id)',
      'CREATE INDEX IF NOT EXISTS idx_topics_book ON topics(book_id)',
      'CREATE INDEX IF NOT EXISTS idx_evidence_topic ON topic_evidence(topic_id)',
      'CREATE INDEX IF NOT EXISTS idx_placement_canvas ON canvas_placements(canvas_id)',
      'CREATE INDEX IF NOT EXISTS idx_placement_parent ON canvas_placements(parent_id)',
      'CREATE INDEX IF NOT EXISTS idx_link_canvas ON canvas_links(canvas_id)',
      'CREATE INDEX IF NOT EXISTS idx_doc_paragraphs_order ON doc_paragraphs(doc_id, ordinal)',
      'CREATE INDEX IF NOT EXISTS idx_doc_runs_para ON doc_runs(doc_id, para_id)',
      'CREATE INDEX IF NOT EXISTS idx_map_summary_doc ON doc_map_summary(chapter_id)',
      'CREATE INDEX IF NOT EXISTS idx_map_relation_doc ON doc_map_relation(chapter_id)',
      'CREATE INDEX IF NOT EXISTS idx_map_node_doc ON doc_map_node(chapter_id)',
      'CREATE INDEX IF NOT EXISTS idx_map_boundary_doc ON doc_map_boundary(chapter_id)'
    ]
    for (const sql of sqls) {
      try {
        await store.executeSql(sql)
      } catch (e) {
        Logger.error('Create table failed: ' + String(e))
        throw new Error(String(e))
      }
    }
  }

  // 幂等补齐新增列：CREATE TABLE IF NOT EXISTS 不会改动已存在的表，
  // 故对旧库需显式 ALTER。只增列，不删列、不改列（is_private 等废弃列留在旧库中即可，
  // 模型层不再读写它们）。
  private async ensureColumns(store: relationalStore.RdbStore): Promise<void> {
    const existing: Map<string, string[]> = new Map<string, string[]>()
    for (const entry of EXPECTED_COLUMNS) {
      const table: string = entry[0]
      const definition: string = entry[1]
      const columnName: string = definition.split(' ')[0]
      let columns: string[] = existing.get(table) ?? []
      if (!existing.has(table)) {
        columns = await this.tableColumns(store, table)
        existing.set(table, columns)
      }
      if (!columns.includes(columnName)) {
        const sql: string = 'ALTER TABLE ' + table + ' ADD COLUMN ' + definition
        try {
          await store.executeSql(sql)
          columns.push(columnName)
          Logger.info('Schema upgraded: ' + sql)
        } catch (e) {
          Logger.error('Add column failed: ' + sql + ' :: ' + String(e))
          throw new Error(String(e))
        }
      }
    }
  }

  // 读取表已有列名（PRAGMA table_info 结果集的 name 列）
  private async tableColumns(store: relationalStore.RdbStore, table: string): Promise<string[]> {
    const names: string[] = []
    let rs: relationalStore.ResultSet | null = null
    try {
      rs = await store.querySql('PRAGMA table_info(' + table + ')')
      const idx: number = rs.getColumnIndex('name')
      if (idx >= 0) {
        while (rs.goToNextRow()) {
          names.push(rs.getString(idx))
        }
      }
      return names
    } catch (e) {
      Logger.error('Read table columns failed: ' + table + ' :: ' + String(e))
      throw new Error(String(e))
    } finally {
      if (rs !== null) {
        // finally 里 close 抛错会掩盖真正的异常，且失败已无可挽回 → 吞掉并记日志
        try {
          rs.close()
        } catch (closeError) {
          Logger.warn('Close table_info result set failed: ' + String(closeError))
        }
      }
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized. Call init() first.')
    }
    return this.store
  }

  /**
   * 开启一个**独立写事务**，调用方负责 commit / rollback。
   *
   * 为什么不用 beginTransaction：官方文档在 createTransaction 条目下明确写着
   * 「与 beginTransaction 的区别在于：createTransaction 接口会返回一个事务对象，
   * 不同事务对象之间是隔离的」，并且「**优先使用 createTransaction，不再推荐使用
   * beginTransaction**」。beginTransaction 把事务建在 store 的共享写连接上，
   * 事务回调里每次 await 的间隙事件循环都会跑其它任务（编辑器防抖保存、30 秒安全网），
   * 那些 UPDATE 会落到同一条写连接并**被并入本事务** —— 恢复一旦失败回滚，
   * 用户刚保存的正文会被一起回滚，而界面已经显示「已保存」，属静默数据丢失。
   *
   * Repos.runInTransaction 为回调创建独立仓储，DAO 在构造时绑定返回的事务对象；
   * 普通仓储始终使用 store，不修改全应用共享的写入目标。
   */
  beginTransaction(): Promise<relationalStore.Transaction> {
    return this.getStore().createTransaction()
  }
}

export const dbHelper: DatabaseHelper = DatabaseHelper.getInstance()
