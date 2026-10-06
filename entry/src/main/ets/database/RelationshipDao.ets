// 人物关系 DAO
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import type { RelationshipModel } from '../model/Relationship'
import { RelationshipType } from '../model/Relationship'

// ArkTS 枚举不能当对象用（Object.values 会报 arkts-no-classes-as-obj），故显式列出。
function toRelationshipType(val: string): RelationshipType {
  if (val === RelationshipType.POSITIVE || val === RelationshipType.NEGATIVE ||
    val === RelationshipType.INDIRECT) {
    return val as RelationshipType
  }
  return RelationshipType.NEUTRAL
}

export class RelationshipDao extends BaseDao<RelationshipModel> {
  protected getTableName(): string {
    return 'relationships'
  }

  protected rowToModel(rs: relationalStore.ResultSet): RelationshipModel {
    return {
      id: this.safeGetString(rs, 'id'),
      bookId: this.safeGetString(rs, 'book_id'),
      characterIdA: this.safeGetString(rs, 'char_a_id'),
      characterIdB: this.safeGetString(rs, 'char_b_id'),
      type: toRelationshipType(this.safeGetString(rs, 'type')),
      label: this.safeGetString(rs, 'label'),
      notes: this.safeGetString(rs, 'notes'),
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at')
    }
  }

  async insert(data: RelationshipModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      book_id: data.bookId,
      char_a_id: data.characterIdA,
      char_b_id: data.characterIdB,
      type: data.type,
      label: data.label,
      notes: data.notes,
      created_at: Date.now(),
      updated_at: Date.now()
    }
    await this.insertRow(valueBucket)
  }

  async update(data: RelationshipModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      type: data.type,
      label: data.label,
      notes: data.notes,
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

  async queryById(id: string): Promise<RelationshipModel | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<RelationshipModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    return this.queryRows(p)
  }

  async queryAll(): Promise<RelationshipModel[]> {
    return this.queryRows(this.newPredicates())
  }
}
