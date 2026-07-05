// features/relationship/src/main/ets/data/RelationshipDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import type { RelationshipModel } from '@ohos/common'

export class RelationshipDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(model: RelationshipModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: model.id,
      book_id: model.bookId,
      char_a_id: model.characterIdA,
      char_b_id: model.characterIdB,
      type: model.type,
      label: model.label,
      notes: model.notes
    }
    await this.getStore().insert('relationships', valueBucket)
  }

  async update(id: string, model: RelationshipModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      type: model.type,
      label: model.label,
      notes: model.notes
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<RelationshipModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const model: RelationshipModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        characterIdA: resultSet.getString(resultSet.getColumnIndex('char_a_id')),
        characterIdB: resultSet.getString(resultSet.getColumnIndex('char_b_id')),
        type: resultSet.getString(resultSet.getColumnIndex('type')),
        label: resultSet.getString(resultSet.getColumnIndex('label')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes'))
      }
      resultSet.close()
      return model
    }
    resultSet.close()
    return null
  }

  async queryByBook(bookId: string): Promise<RelationshipModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    predicates.equalTo('book_id', bookId)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: RelationshipModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        characterIdA: resultSet.getString(resultSet.getColumnIndex('char_a_id')),
        characterIdB: resultSet.getString(resultSet.getColumnIndex('char_b_id')),
        type: resultSet.getString(resultSet.getColumnIndex('type')),
        label: resultSet.getString(resultSet.getColumnIndex('label')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes'))
      })
    }
    resultSet.close()
    return models
  }

  async queryByCharacter(charId: string): Promise<RelationshipModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    predicates.equalTo('char_a_id', charId)
    predicates.or()
    predicates.equalTo('char_b_id', charId)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: RelationshipModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        characterIdA: resultSet.getString(resultSet.getColumnIndex('char_a_id')),
        characterIdB: resultSet.getString(resultSet.getColumnIndex('char_b_id')),
        type: resultSet.getString(resultSet.getColumnIndex('type')),
        label: resultSet.getString(resultSet.getColumnIndex('label')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes'))
      })
    }
    resultSet.close()
    return models
  }

  async queryAll(): Promise<RelationshipModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('relationships')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const models: RelationshipModel[] = []
    while (resultSet.goToNextRow()) {
      models.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        characterIdA: resultSet.getString(resultSet.getColumnIndex('char_a_id')),
        characterIdB: resultSet.getString(resultSet.getColumnIndex('char_b_id')),
        type: resultSet.getString(resultSet.getColumnIndex('type')),
        label: resultSet.getString(resultSet.getColumnIndex('label')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes'))
      })
    }
    resultSet.close()
    return models
  }
}
