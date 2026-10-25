// 世界设定 DAO
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import type { WorldSettingModel } from '../model/WorldSetting'
import { WorldCategory } from '../model/WorldSetting'

// ArkTS 枚举不能当对象用（Object.values 会报 arkts-no-classes-as-obj），故显式列出。
function toWorldCategory(val: string): WorldCategory {
  if (val === WorldCategory.GEOGRAPHY || val === WorldCategory.POLITICS ||
    val === WorldCategory.HISTORY || val === WorldCategory.MAGIC_TECH ||
    val === WorldCategory.RACE || val === WorldCategory.CULTURE) {
    return val as WorldCategory
  }
  return WorldCategory.OTHER
}

export class WorldSettingDao extends BaseDao<WorldSettingModel> {
  protected getTableName(): string {
    return 'world_settings'
  }

  protected rowToModel(rs: relationalStore.ResultSet): WorldSettingModel {
    return {
      id: this.safeGetString(rs, 'id'),
      bookId: this.safeGetString(rs, 'book_id'),
      name: this.safeGetString(rs, 'name'),
      category: toWorldCategory(this.safeGetString(rs, 'category')),
      region: this.safeGetString(rs, 'region'),
      description: this.safeGetString(rs, 'description'),
      notes: this.safeGetString(rs, 'notes'),
      content: this.safeGetString(rs, 'content'),
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at')
    }
  }

  async insert(data: WorldSettingModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      book_id: data.bookId,
      name: data.name,
      category: data.category,
      region: data.region,
      description: data.description,
      notes: data.notes,
      content: data.content,
      created_at: Date.now(),
      updated_at: Date.now()
    }
    await this.insertRow(valueBucket)
  }

  async update(data: WorldSettingModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: data.name,
      category: data.category,
      region: data.region,
      description: data.description,
      notes: data.notes,
      content: data.content,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', data.id)
    await this.updateRow(valueBucket, predicates)
  }

  async updateContent(id: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  async queryById(id: string): Promise<WorldSettingModel | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<WorldSettingModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    p.orderByAsc('name')
    return this.queryRows(p)
  }

  async queryAll(): Promise<WorldSettingModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.orderByAsc('name')
    return this.queryRows(p)
  }
}
