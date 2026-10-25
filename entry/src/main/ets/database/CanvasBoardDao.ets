// 思路板白板 DAO（canvases 表）
//
// 与其它 DAO 一致：继承 BaseDao，只写 ValuesBucket / RdbPredicates，不拼 SQL 字符串。
// book_id 为空串表示自由白板（沿用 inspirations 的空串约定）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { CanvasBoardItem } from '../model/CanvasStoreModels'
import { CanvasBoardScope } from '../model/CanvasTypes'

// ArkTS 枚举不能当对象用（Object.values 会报 arkts-no-classes-as-obj），故显式列出合法值；
// 未知值回退 COURSE，保证读到脏数据也不会崩。
function canvasBoardScopeOf(value: string): CanvasBoardScope {
  if (value === CanvasBoardScope.FREE) {
    return CanvasBoardScope.FREE
  }
  return CanvasBoardScope.COURSE
}

export class CanvasBoardDao extends BaseDao<CanvasBoardItem> {
  protected getTableName(): string {
    return 'canvases'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CanvasBoardItem {
    const item: CanvasBoardItem = new CanvasBoardItem()
    item.id = this.safeGetString(rs, 'id')
    item.scope = canvasBoardScopeOf(this.safeGetString(rs, 'scope'))
    item.bookId = this.safeGetString(rs, 'book_id')
    item.title = this.safeGetString(rs, 'title')
    item.panX = this.numberOf(rs, 'pan_x')
    item.panY = this.numberOf(rs, 'pan_y')
    item.zoom = this.numberOf(rs, 'zoom')
    item.sortOrder = this.safeGetLong(rs, 'sort_order')
    item.createdAt = this.safeGetLong(rs, 'created_at')
    item.updatedAt = this.safeGetLong(rs, 'updated_at')
    return item
  }

  /**
   * REAL 列必须按 double 读：safeGetLong 会把 0.75 截成 0，
   * 那样「上次的缩放/相机位置」每次重启都会归零。
   */
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

  async insert(data: CanvasBoardItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      scope: data.scope,
      book_id: data.bookId,
      title: data.title,
      pan_x: data.panX,
      pan_y: data.panY,
      zoom: data.zoom,
      sort_order: data.sortOrder,
      created_at: data.createdAt,
      updated_at: data.updatedAt
    }
    await this.insertRow(valueBucket)
  }

  async saveViewport(id: string, panX: number, panY: number, zoom: number): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      pan_x: panX,
      pan_y: panY,
      zoom: zoom,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  async rename(id: string, title: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      title: title,
      updated_at: Date.now()
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

  async queryById(id: string): Promise<CanvasBoardItem | null> {
    return this.queryByIdRow(id)
  }

  async queryByBook(bookId: string): Promise<CanvasBoardItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', bookId)
    p.orderByAsc('sort_order')
    return this.queryRows(p)
  }

  /** 自由白板（book_id 为空串） */
  async queryFree(): Promise<CanvasBoardItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('book_id', '')
    p.orderByAsc('sort_order')
    return this.queryRows(p)
  }

  async queryAllBoards(): Promise<CanvasBoardItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.orderByAsc('sort_order')
    return this.queryRows(p)
  }
}
