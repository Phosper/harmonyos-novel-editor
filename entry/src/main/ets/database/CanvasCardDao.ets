// 思路板卡片 DAO（topics 表）：概念卡 / 写作卡
//
// 卡片库是全局的（与白板无关），所以除了 queryByBook 还提供 queryAll。
// book_id 为空串表示「跨书 / 未归类」（沿用 inspirations 的空串约定）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { CanvasCardItem } from '../model/CanvasStoreModels'
import { CanvasCardKind } from '../model/CanvasTypes'

// ArkTS 枚举不能当对象用，故显式列出；未知值回退 CONCEPT。
function canvasCardKindOf(value: string): CanvasCardKind {
  if (value === CanvasCardKind.WRITING) {
    return CanvasCardKind.WRITING
  }
  return CanvasCardKind.CONCEPT
}

export class CanvasCardDao extends BaseDao<CanvasCardItem> {
  protected getTableName(): string {
    return 'topics'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CanvasCardItem {
    const item: CanvasCardItem = new CanvasCardItem()
    item.id = this.safeGetString(rs, 'id')
    item.bookId = this.safeGetString(rs, 'book_id')
    item.kind = canvasCardKindOf(this.safeGetString(rs, 'kind'))
    item.title = this.safeGetString(rs, 'title')
    item.aliases = this.safeGetString(rs, 'aliases')
    item.tags = this.safeGetString(rs, 'tags')
    item.summary = this.safeGetString(rs, 'my_summary')
    item.docId = this.safeGetString(rs, 'doc_id')
    item.createdAt = this.safeGetLong(rs, 'created_at')
    item.updatedAt = this.safeGetLong(rs, 'updated_at')
    return item
  }

  async insert(data: CanvasCardItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      book_id: data.bookId,
      kind: data.kind,
      title: data.title,
      aliases: data.aliases,
      tags: data.tags,
      my_summary: data.summary,
      doc_id: data.docId,
      created_at: data.createdAt,
      updated_at: data.updatedAt
    }
    await this.insertRow(valueBucket)
  }

  /** 只更新卡片自身内容（标题/别名/标签/我的一句话/生成的初稿 id）。 */
  async update(data: CanvasCardItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      title: data.title,
      aliases: data.aliases,
      tags: data.tags,
      my_summary: data.summary,
      doc_id: data.docId,
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

  async queryById(id: string): Promise<CanvasCardItem | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<CanvasCardItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    p.orderByAsc('created_at')
    return this.queryRows(p)
  }

  async queryAllCards(): Promise<CanvasCardItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.orderByAsc('created_at')
    return this.queryRows(p)
  }
}
