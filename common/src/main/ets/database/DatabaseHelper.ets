// common/src/main/ets/database/DatabaseHelper.ets
import { relationalStore } from '@kit.ArkData'

const DB_NAME: string = 'Weaver.db'
const DB_VERSION: number = 1

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

    this.store = await relationalStore.getRdbStore(context, config)
    await this.createTables()
    return this.store
  }

  private async createTables(): Promise<void> {
    const sqls: string[] = [
      `CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'normal',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        word_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )`,
      `CREATE TABLE IF NOT EXISTS characters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        alias TEXT NOT NULL DEFAULT '',
        age TEXT NOT NULL DEFAULT '',
        appearance TEXT NOT NULL DEFAULT '',
        personality TEXT NOT NULL DEFAULT '',
        background TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )`,
      `CREATE TABLE IF NOT EXISTS world_settings (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'other',
        region TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE
      )`,
      `CREATE TABLE IF NOT EXISTS inspirations (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE SET NULL
      )`,
      `CREATE TABLE IF NOT EXISTS relationships (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        char_a_id TEXT NOT NULL,
        char_b_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'neutral',
        label TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (char_a_id) REFERENCES characters(id) ON DELETE CASCADE,
        FOREIGN KEY (char_b_id) REFERENCES characters(id) ON DELETE CASCADE
      )`
    ]

    for (const sql of sqls) {
      await this.store!.executeSql(sql)
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('Database not initialized. Call init() first.')
    }
    return this.store
  }
}

export const dbHelper: DatabaseHelper = DatabaseHelper.getInstance()
