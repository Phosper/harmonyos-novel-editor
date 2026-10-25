// 思路板贴放 DAO（canvas_placements 表）
//
// 语义要点（契约 §4.2）：
// - parent_id 指向**同一白板内**的另一个 placement.id，不是 topic.id；
// - ord 只用于同级排序，重排后整体写 0..n-1，不依赖浮点间隙；
// - 坐标 x/y 是 REAL（世界坐标），z 是叠放层序（越大越靠上）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { CanvasPlacementItem, canvasSqlPlaceholders } from '../model/CanvasStoreModels'

export class CanvasPlacementDao extends BaseDao<CanvasPlacementItem> {
  protected getTableName(): string {
    return 'canvas_placements'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CanvasPlacementItem {
    const item: CanvasPlacementItem = new CanvasPlacementItem()
    item.id = this.safeGetString(rs, 'id')
    item.canvasId = this.safeGetString(rs, 'canvas_id')
    item.cardId = this.safeGetString(rs, 'topic_id')
    item.parentId = this.safeGetString(rs, 'parent_id')
    item.order = this.safeGetLong(rs, 'ord')
    item.x = this.numberOf(rs, 'x')
    item.y = this.numberOf(rs, 'y')
    item.z = this.safeGetLong(rs, 'z')
    item.collapsed = this.safeGetBool(rs, 'collapsed')
    item.style = this.safeGetString(rs, 'style')
    return item
  }

  /** REAL 列按 double 读：safeGetLong 会把 12.5 截成 12，卡片会慢慢向左上漂。 */
  private numberOf(rs: relationalStore.ResultSet, col: string): number {
    try {
      const idx: number = rs.getColumnIndex(col)
      if (idx < 0) {
        return 0
      }
      return rs.getDouble(idx)
    } catch (e) {
      return 0
    }
  }

  async insert(data: CanvasPlacementItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      canvas_id: data.canvasId,
      topic_id: data.cardId,
      parent_id: data.parentId,
      ord: data.order,
      x: data.x,
      y: data.y,
      z: data.z,
      collapsed: data.collapsed ? 1 : 0,
      style: data.style
    }
    await this.insertRow(valueBucket)
  }

  /** 只改父子关系与同级序（拖动嵌套 / 移出 / 重排用），不动坐标。 */
  async saveStructure(id: string, parentId: string, order: number): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      parent_id: parentId,
      ord: order
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  /** 只改坐标（拖动落点用）。 */
  async savePosition(id: string, x: number, y: number): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      x: x,
      y: y
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  /**
   * 只改同级序。重排永远不换父，故不碰 parent_id：
   * 父字段在内存里是**卡片 id**，落库要的是**贴放 id**，多写一个字段就多一次翻译错误的机会。
   */
  async saveOrder(id: string, order: number): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      ord: order
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  /** 删卡片时删掉它在**所有白板**上的贴放。 */
  async deleteByCard(cardId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('topic_id', cardId)
    await this.deleteRow(predicates)
  }

  async deleteByBoard(canvasId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('canvas_id', canvasId)
    await this.deleteRow(predicates)
  }

  async queryByBoard(canvasId: string): Promise<CanvasPlacementItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('canvas_id', canvasId)
    p.orderByAsc('ord')
    return this.queryRows(p)
  }

  /** 这张卡在所有白板上的贴放（删卡片时要逐板把子项上提）。 */
  async queryByCard(cardId: string): Promise<CanvasPlacementItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('topic_id', cardId)
    return this.queryRows(p)
  }

  /** 一次取多块白板的贴放（Store 载入 + 备份用）。 */
  async queryByBoards(canvasIds: string[]): Promise<CanvasPlacementItem[]> {
    if (canvasIds.length === 0) {
      return []
    }
    const sql: string = 'SELECT * FROM canvas_placements WHERE canvas_id IN (' +
      canvasSqlPlaceholders(canvasIds.length) + ') ORDER BY canvas_id ASC, ord ASC'
    const args: relationalStore.ValueType[] = []
    for (let i: number = 0; i < canvasIds.length; i++) {
      args.push(canvasIds[i])
    }
    return this.querySqlRows(sql, args)
  }
}
