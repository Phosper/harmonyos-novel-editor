// features/material/src/main/ets/data/WorldSettingDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import type { WorldSettingModel } from '@ohos/common'

export class WorldSettingDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(model: WorldSettingModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: model.id,
      book_id: model.bookId,
      name: model.name,
      category: model.category,
      region: model.region,
      description: model.description,
      notes: model.notes,
      content: model.content
    }
    await this.getStore().insert('world_settings', valueBucket)
  }

  async update(id: string, model: WorldSettingModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: model.name,
      category: model.category,
      region: model.region,
      description: model.description,
      notes: model.notes,
      content: model.content
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async updateContent(id: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = { content: content }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async queryById(id: string): Promise<WorldSettingModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const model: WorldSettingModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        region: resultSet.getString(resultSet.getColumnIndex('region')),
        description: resultSet.getString(resultSet.getColumnIndex('description')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        content: resultSet.getString(resultSet.getColumnIndex('content'))
      }
      resultSet.close()
      return model
    }
    resultSet.close()
    return null
  }

  async queryByBook(bookId: string): Promise<WorldSettingModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    predicates.equalTo('book_id', bookId)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: WorldSettingModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        region: resultSet.getString(resultSet.getColumnIndex('region')),
        description: resultSet.getString(resultSet.getColumnIndex('description')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        content: resultSet.getString(resultSet.getColumnIndex('content'))
      })
    }
    resultSet.close()
    return models
  }

  async queryAll(): Promise<WorldSettingModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('world_settings')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: WorldSettingModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        region: resultSet.getString(resultSet.getColumnIndex('region')),
        description: resultSet.getString(resultSet.getColumnIndex('description')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        content: resultSet.getString(resultSet.getColumnIndex('content'))
      })
    }
    resultSet.close()
    return models
  }
}
