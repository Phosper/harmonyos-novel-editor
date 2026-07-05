// features/editor/src/main/ets/data/BookDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import { IdGenerator } from '@ohos/common'
import type { BookModel } from '@ohos/common'

export class BookDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(book: BookModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: book.id,
      name: book.name,
      mode: book.mode,
      created_at: book.createdAt,
      updated_at: book.updatedAt
    }
    await this.getStore().insert('books', valueBucket)
  }

  async update(id: string, name: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: name,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('books')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('books')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<BookModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('books')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const book: BookModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        mode: resultSet.getString(resultSet.getColumnIndex('mode')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      }
      resultSet.close()
      return book
    }
    resultSet.close()
    return null
  }

  async queryByMode(mode: string): Promise<BookModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('books')
    predicates.equalTo('mode', mode)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const books: BookModel[] = []
    while (resultSet.goToNextRow()) {
      books.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        mode: resultSet.getString(resultSet.getColumnIndex('mode')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      })
    }
    resultSet.close()
    return books
  }

  async queryAll(): Promise<BookModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('books')
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const books: BookModel[] = []
    while (resultSet.goToNextRow()) {
      books.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        mode: resultSet.getString(resultSet.getColumnIndex('mode')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      })
    }
    resultSet.close()
    return books
  }
}
