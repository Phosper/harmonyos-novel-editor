// features/material/src/main/ets/data/InspirationDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import type { InspirationModel } from '@ohos/common'

export class InspirationDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(model: InspirationModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: model.id,
      book_id: model.bookId,
      content: model.content,
      created_at: model.createdAt
    }
    await this.getStore().insert('inspirations', valueBucket)
  }

  async update(id: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      content: content
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('inspirations')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('inspirations')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<InspirationModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('inspirations')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const model: InspirationModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.isColumnNull(resultSet.getColumnIndex('book_id'))
          ? null : resultSet.getString(resultSet.getColumnIndex('book_id')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      }
      resultSet.close()
      return model
    }
    resultSet.close()
    return null
  }

  async queryByBook(bookId: string): Promise<InspirationModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('inspirations')
    predicates.equalTo('book_id', bookId)
    predicates.orderByDesc('created_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: InspirationModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.isColumnNull(resultSet.getColumnIndex('book_id'))
          ? null : resultSet.getString(resultSet.getColumnIndex('book_id')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      })
    }
    resultSet.close()
    return models
  }

  async queryAll(): Promise<InspirationModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('inspirations')
    predicates.orderByDesc('created_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: InspirationModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.isColumnNull(resultSet.getColumnIndex('book_id'))
          ? null : resultSet.getString(resultSet.getColumnIndex('book_id')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      })
    }
    resultSet.close()
    return models
  }
}
