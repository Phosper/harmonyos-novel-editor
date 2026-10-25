// 思路板连线 DAO（canvas_links 表）
//
// 连线是同一块白板内卡片之间的关系（前提/因果/对比…），不跨板。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { CanvasLinkItem, canvasSqlPlaceholders } from '../model/CanvasStoreModels'
import { CanvasLinkKind } from '../model/CanvasTypes'

// ArkTS 枚举不能当对象用，故显式列出全部合法值；未知值回退 RELATE。
function canvasLinkKindOf(value: string): CanvasLinkKind {
  if (value === CanvasLinkKind.PREMISE) {
    return CanvasLinkKind.PREMISE
  }
  if (value === CanvasLinkKind.CAUSE) {
    return CanvasLinkKind.CAUSE
  }
  if (value === CanvasLinkKind.CONTRAST) {
    return CanvasLinkKind.CONTRAST
  }
  if (value === CanvasLinkKind.EXAMPLE) {
    return CanvasLinkKind.EXAMPLE
  }
  if (value === CanvasLinkKind.SEQUENCE) {
    return CanvasLinkKind.SEQUENCE
  }
  return CanvasLinkKind.RELATE
}

export class CanvasLinkDao extends BaseDao<CanvasLinkItem> {
  protected getTableName(): string {
    return 'canvas_links'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CanvasLinkItem {
    const item: CanvasLinkItem = new CanvasLinkItem()
    item.id = this.safeGetString(rs, 'id')
    item.canvasId = this.safeGetString(rs, 'canvas_id')
    item.fromCardId = this.safeGetString(rs, 'from_topic_id')
    item.toCardId = this.safeGetString(rs, 'to_topic_id')
    item.kind = canvasLinkKindOf(this.safeGetString(rs, 'kind'))
    item.label = this.safeGetString(rs, 'label')
    item.createdAt = this.safeGetLong(rs, 'created_at')
    return item
  }

  async insert(data: CanvasLinkItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      canvas_id: data.canvasId,
      from_topic_id: data.fromCardId,
      to_topic_id: data.toCardId,
      kind: data.kind,
      label: data.label,
      created_at: data.createdAt
    }
    await this.insertRow(valueBucket)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  async deleteByBoard(canvasId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('canvas_id', canvasId)
    await this.deleteRow(predicates)
  }

  /** 删卡片时清掉以它为起点/终点的连线（RdbPredicates 的 or 在旧库里不稳，分两条删）。 */
  async deleteByFrom(cardId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('from_topic_id', cardId)
    await this.deleteRow(predicates)
  }

  async deleteByTo(cardId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('to_topic_id', cardId)
    await this.deleteRow(predicates)
  }

  async queryByBoard(canvasId: string): Promise<CanvasLinkItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('canvas_id', canvasId)
    p.orderByAsc('created_at')
    return this.queryRows(p)
  }

  async queryByBoards(canvasIds: string[]): Promise<CanvasLinkItem[]> {
    if (canvasIds.length === 0) {
      return []
    }
    const sql: string = 'SELECT * FROM canvas_links WHERE canvas_id IN (' +
      canvasSqlPlaceholders(canvasIds.length) + ') ORDER BY created_at ASC'
    const args: relationalStore.ValueType[] = []
    for (let i: number = 0; i < canvasIds.length; i++) {
      args.push(canvasIds[i])
    }
    return this.querySqlRows(sql, args)
  }
}
