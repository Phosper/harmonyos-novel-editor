// 人物 DAO
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import type { CharacterModel } from '../model/Character'
import { CharacterType } from '../model/Character'

// ArkTS 枚举不能当对象用（Object.values 会报 arkts-no-classes-as-obj），
// 故显式列出合法值。未知值一律回退到 SUPPORT，保证读到脏数据也不会崩。
function toCharacterType(val: string): CharacterType {
  if (val === CharacterType.PROTAGONIST || val === CharacterType.VILLAIN ||
    val === CharacterType.ORG || val === CharacterType.PLACE) {
    return val as CharacterType
  }
  return CharacterType.SUPPORT
}

export class CharacterDao extends BaseDao<CharacterModel> {
  protected getTableName(): string {
    return 'characters'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CharacterModel {
    return {
      id: this.safeGetString(rs, 'id'),
      bookId: this.safeGetString(rs, 'book_id'),
      name: this.safeGetString(rs, 'name'),
      alias: this.safeGetString(rs, 'alias'),
      age: this.safeGetString(rs, 'age'),
      appearance: this.safeGetString(rs, 'appearance'),
      personality: this.safeGetString(rs, 'personality'),
      background: this.safeGetString(rs, 'background'),
      notes: this.safeGetString(rs, 'notes'),
      characterType: toCharacterType(this.safeGetString(rs, 'character_type')),
      createdAt: this.safeGetLong(rs, 'created_at'),
      updatedAt: this.safeGetLong(rs, 'updated_at')
    }
  }

  async insert(data: CharacterModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      book_id: data.bookId,
      name: data.name,
      alias: data.alias,
      age: data.age,
      appearance: data.appearance,
      personality: data.personality,
      background: data.background,
      notes: data.notes,
      character_type: data.characterType,
      created_at: Date.now(),
      updated_at: Date.now()
    }
    await this.insertRow(valueBucket)
  }

  async update(data: CharacterModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      name: data.name,
      alias: data.alias,
      age: data.age,
      appearance: data.appearance,
      personality: data.personality,
      background: data.background,
      notes: data.notes,
      character_type: data.characterType,
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

  async queryById(id: string): Promise<CharacterModel | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<CharacterModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    p.orderByAsc('name')
    return this.queryRows(p)
  }

  async queryAll(): Promise<CharacterModel[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.orderByAsc('name')
    return this.queryRows(p)
  }
}
