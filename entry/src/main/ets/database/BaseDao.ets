// 泛型 DAO 基类 —— 收敛 6 个 DAO 的复制粘贴骨架
// 子类只需实现 getTableName() 与 rowToModel()，并组合下列受保护方法。
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from './DatabaseHelper'
import { Logger } from '../utils/Logger'

export abstract class BaseDao<T> {
  protected abstract getTableName(): string
  protected abstract rowToModel(rs: relationalStore.ResultSet): T

  protected getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  protected async insertRow(valueBucket: relationalStore.ValuesBucket): Promise<void> {
    try {
      await this.getStore().insert(this.getTableName(), valueBucket)
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] insert failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  protected async updateRow(valueBucket: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.getStore().update(valueBucket, predicates)
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] update failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  protected async deleteRow(predicates: relationalStore.RdbPredicates): Promise<void> {
    try {
      await this.getStore().delete(predicates)
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] delete failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  protected async queryRows(predicates: relationalStore.RdbPredicates): Promise<T[]> {
    const rs: relationalStore.ResultSet = await this.getStore().query(predicates)
    const list: T[] = []
    while (rs.goToNextRow()) {
      list.push(this.rowToModel(rs))
    }
    rs.close()
    return list
  }

  protected async queryByIdRow(id: string): Promise<T | null> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    const rs: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (rs.goToFirstRow()) {
      const model: T = this.rowToModel(rs)
      rs.close()
      return model
    }
    rs.close()
    return null
  }

  protected newPredicates(): relationalStore.RdbPredicates {
    return new relationalStore.RdbPredicates(this.getTableName())
  }

  // ===== 统一的 null 读取助手（替代旧版三种不一致写法）=====
  protected safeGetString(rs: relationalStore.ResultSet, col: string): string {
    try {
      const idx: number = rs.getColumnIndex(col)
      if (idx < 0) return ''
      return rs.getString(idx)
    } catch (e) {
      return ''
    }
  }

  protected safeGetLong(rs: relationalStore.ResultSet, col: string): number {
    try {
      const idx: number = rs.getColumnIndex(col)
      if (idx < 0) return 0
      return rs.getLong(idx)
    } catch (e) {
      return 0
    }
  }

  protected safeGetBool(rs: relationalStore.ResultSet, col: string): boolean {
    return this.safeGetLong(rs, col) !== 0
  }
}
