// 灵感 DAO（bookId 为 '' 表示暂不归类）
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import type { InspirationModel } from '../model/Inspiration'

export class InspirationDao extends BaseDao<InspirationModel> {
  protected getTableName(): string {
    return 'inspirations'
  }

  protected rowToModel(rs: relationalStore.ResultSet): InspirationModel {
    const bookId: string = this.safeGetString(rs, 'book_id')
    return {
      id: this.safeGetString(rs, 'id'),
      bookId: bookId === '' ? null : bookId,
      content: this.safeGetString(rs, 'content'),
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at')
    }
  }

  async insert(data: InspirationModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      book_id: data.bookId ?? '',
      content: data.content,
      created_at: data.createdAt,
      updated_at: data.createdAt
    }
    await this.insertRow(valueBucket)
  }

  async update(data: InspirationModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      book_id: data.bookId ?? '',
      content: data.content,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', data.id)
    await this.updateRow(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  async queryById(id: string): Promise<InspirationModel | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<InspirationModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    p.orderByDesc('created_at')
    return this.queryRows(p)
  }

  // 暂不归类的灵感
  async queryUncategorized(): Promise<InspirationModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', '')
    p.orderByDesc('created_at')
    return this.queryRows(p)
  }

  async queryAll(): Promise<InspirationModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.orderByDesc('created_at')
    return this.queryRows(p)
  }
}
