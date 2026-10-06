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
      this.store = await relationalStore.getRdbStore(context, config)
      await this.store.executeSql('PRAGMA foreign_keys = ON')
      await this.createTables()
      await this.ensureColumns()
      Logger.info('Database initialized (version ' + DB_VERSION + ')')
    } catch (e) {
      Logger.error('Database init failed: ' + String(e))
      throw new Error(String(e))
    }
    return this.store
  }

  private async createTables(): Promise<void> {
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
        ')'
    ]
    for (const sql of sqls) {
      try {
        await this.store!.executeSql(sql)
      } catch (e) {
        Logger.error('Create table failed: ' + String(e))
        throw new Error(String(e))
      }
    }
  }

  // 幂等补齐新增列：CREATE TABLE IF NOT EXISTS 不会改动已存在的表，
  // 故对旧库需显式 ALTER。只增列，不删列、不改列（is_private 等废弃列留在旧库中即可，
  // 模型层不再读写它们）。
  private async ensureColumns(): Promise<void> {
    const existing: Map<string, string[]> = new Map<string, string[]>()
    for (const entry of EXPECTED_COLUMNS) {
      const table: string = entry[0]
      const definition: string = entry[1]
      const columnName: string = definition.split(' ')[0]
      let columns: string[] = existing.get(table) ?? []
      if (!existing.has(table)) {
        columns = await this.tableColumns(table)
        existing.set(table, columns)
      }
      if (!columns.includes(columnName)) {
        const sql: string = 'ALTER TABLE ' + table + ' ADD COLUMN ' + definition
        try {
          await this.store!.executeSql(sql)
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
  private async tableColumns(table: string): Promise<string[]> {
    const names: string[] = []
    try {
      const rs: relationalStore.ResultSet =
        await this.store!.querySql('PRAGMA table_info(' + table + ')')
      const idx: number = rs.getColumnIndex('name')
      if (idx >= 0) {
        while (rs.goToNextRow()) {
          names.push(rs.getString(idx))
        }
      }
      rs.close()
    } catch (e) {
      Logger.error('Read table columns failed: ' + table + ' :: ' + String(e))
      throw new Error(String(e))
    }
    return names
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized. Call init() first.')
    }
    return this.store
  }

  /**
   * 以事务执行一组写操作：全部成功才提交，任一失败整组回滚。
   *
   * 备份恢复要连写项目 / 人物 / 世界观 / 灵感 / 文稿 / 关系若干张表，
   * 逐条 await 写入时一旦中途失败（例如磁盘满、进程被杀），
   * 库里会留下一个"半成品项目"——项目名在、文稿缺一半、关系全无，
   * 用户既看不出来也删不干净。整组回滚可避免这种脏数据。
   */
  async runInTransaction(work: () => Promise<void>): Promise<void> {
    const store: relationalStore.RdbStore = this.getStore()
    await store.beginTransaction()
    try {
      await work()
      await store.commit()
    } catch (e) {
      try {
        await store.rollBack()
      } catch (rollbackError) {
        // 回滚本身失败已无法挽回，记日志后按原异常抛出
        Logger.error('Rollback failed: ' + String(rollbackError))
      }
      Logger.error('Transaction rolled back: ' + String(e))
      throw new Error(String(e))
    }
  }
}

export const dbHelper: DatabaseHelper = DatabaseHelper.getInstance()
