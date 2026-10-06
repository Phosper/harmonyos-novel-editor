// 书籍（项目）DAO
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import type { BookModel } from '../model/Book'
import { BookMode } from '../model/Book'

export class BookDao extends BaseDao<BookModel> {
  protected getTableName(): string {
    return 'books'
  }

  protected rowToModel(rs: relationalStore.ResultSet): BookModel {
    const modeStr: string = this.safeGetString(rs, 'mode')
    return {
      id: this.safeGetString(rs, 'id'),
      name: this.safeGetString(rs, 'name'),
      mode: modeStr === BookMode.NORMAL ? BookMode.NORMAL : BookMode.PROFESSIONAL,
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at')
    }
  }

  async insert(book: BookModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: book.id,
      name: book.name,
      mode: book.mode,
      created_at: book.createdAt,
      updated_at: book.updatedAt
    }
    await this.insertRow(valueBucket)
  }

  async updateName(id: string, name: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: name,
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

  async queryAll(): Promise<BookModel[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.orderByDesc('updated_at')
    return this.queryRows(predicates)
  }

  async queryById(id: string): Promise<BookModel | null> {
    return this.queryByIdRow(id)
  }
}
