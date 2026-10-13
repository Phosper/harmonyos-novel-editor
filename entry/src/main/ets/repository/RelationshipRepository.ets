// 人物关系仓储
import { relationalStore } from '@kit.ArkData'
import { RelationshipDao } from '../database/RelationshipDao'
import { IdGenerator } from '../utils/IdGenerator'
import type { RelationshipModel } from '../model/Relationship'
import { RelationshipType } from '../model/Relationship'

export class RelationshipRepository {
  private dao: RelationshipDao = new RelationshipDao()

  /** 由 Repos.runInTransaction 调用：把写操作重定向到独立事务对象 */
  setTransaction(tx: relationalStore.Transaction | null): void {
    this.dao.setTransaction(tx)
  }

  async loadRelationships(bookId: string): Promise<RelationshipModel[]> {
    return this.dao.queryByBook(bookId)
  }

  async insert(data: RelationshipModel): Promise<void> {
    await this.dao.insert(data)
  }

  async update(data: RelationshipModel): Promise<void> {
    await this.dao.update(data)
  }

  async delete(id: string): Promise<void> {
    await this.dao.delete(id)
  }

  // 便捷创建（生成 id 与 bookId 封装）
  async create(bookId: string, charA: string, charB: string,
    type: RelationshipType, label: string, notes: string): Promise<RelationshipModel> {
    const now: number = Date.now()
    const model: RelationshipModel = {
      id: IdGenerator.generate(),
      bookId: bookId,
      characterIdA: charA,
      characterIdB: charB,
      type: type,
      label: label,
      notes: notes,
      createdAt: now,
      updatedAt: now
    }
    await this.dao.insert(model)
    return model
  }
}
