// schema_meta：只存"某个一次性数据任务是否已完成"这类键值。
// 不承载业务数据，也不替代正式的 schema 版本号。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'

export class MetaEntry {
  key: string = ''
  value: string = ''

  constructor(key: string = '', value: string = '') {
    this.key = key
    this.value = value
  }
}

export class MetaDao extends BaseDao<MetaEntry> {
  protected getTableName(): string {
    return 'schema_meta'
  }

  protected rowToModel(rs: relationalStore.ResultSet): MetaEntry {
    return new MetaEntry(this.safeGetString(rs, 'meta_key'), this.safeGetString(rs, 'meta_value'))
  }

  async get(key: string): Promise<string> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('meta_key', key)
    const rows: MetaEntry[] = await this.queryRows(predicates)
    return rows.length > 0 ? rows[0].value : ''
  }

  /**
   * 先删后插：schema_meta 只有主键，没有 upsert 的跨版本稳定写法。
   * 调用方都在一次性任务末尾，重复执行是幂等的。
   */
  async set(key: string, value: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('meta_key', key)
    await this.deleteRow(predicates)
    await this.insertRow({ meta_key: key, meta_value: value, updated_at: Date.now() })
  }
}
