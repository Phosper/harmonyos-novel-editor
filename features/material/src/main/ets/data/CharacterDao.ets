// features/material/src/main/ets/data/CharacterDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import type { CharacterModel } from '@ohos/common'

export class CharacterDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(model: CharacterModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: model.id,
      book_id: model.bookId,
      name: model.name,
      alias: model.alias,
      age: model.age,
      appearance: model.appearance,
      personality: model.personality,
      background: model.background,
      notes: model.notes,
      character_type: model.characterType
    }
    await this.getStore().insert('characters', valueBucket)
  }

  async update(id: string, model: CharacterModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: model.name,
      alias: model.alias,
      age: model.age,
      appearance: model.appearance,
      personality: model.personality,
      background: model.background,
      notes: model.notes,
      character_type: model.characterType
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('characters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('characters')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<CharacterModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('characters')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const model: CharacterModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        alias: resultSet.getString(resultSet.getColumnIndex('alias')),
        age: resultSet.getString(resultSet.getColumnIndex('age')),
        appearance: resultSet.getString(resultSet.getColumnIndex('appearance')),
        personality: resultSet.getString(resultSet.getColumnIndex('personality')),
        background: resultSet.getString(resultSet.getColumnIndex('background')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        characterType: this.getColumnString(resultSet, 'character_type', 'support')
      }
      resultSet.close()
      return model
    }
    resultSet.close()
    return null
  }

  async queryByBook(bookId: string): Promise<CharacterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('characters')
    predicates.equalTo('book_id', bookId)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: CharacterModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        alias: resultSet.getString(resultSet.getColumnIndex('alias')),
        age: resultSet.getString(resultSet.getColumnIndex('age')),
        appearance: resultSet.getString(resultSet.getColumnIndex('appearance')),
        personality: resultSet.getString(resultSet.getColumnIndex('personality')),
        background: resultSet.getString(resultSet.getColumnIndex('background')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        characterType: this.getColumnString(resultSet, 'character_type', 'support')
      })
    }
    resultSet.close()
    return models
  }

  async queryAll(): Promise<CharacterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('characters')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: CharacterModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        alias: resultSet.getString(resultSet.getColumnIndex('alias')),
        age: resultSet.getString(resultSet.getColumnIndex('age')),
        appearance: resultSet.getString(resultSet.getColumnIndex('appearance')),
        personality: resultSet.getString(resultSet.getColumnIndex('personality')),
        background: resultSet.getString(resultSet.getColumnIndex('background')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        characterType: this.getColumnString(resultSet, 'character_type', 'support')
      })
    }
    resultSet.close()
    return models
  }

  private getColumnString(rs: relationalStore.ResultSet, column: string, defaultValue: string): string {
    const idx: number = rs.getColumnIndex(column)
    if (idx < 0) {
      return defaultValue
    }
    const val: string = rs.getString(idx)
    return val !== '' ? val : defaultValue
  }
}
