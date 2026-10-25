// 泛型 DAO 基类 —— 收敛 6 个 DAO 的复制粘贴骨架
// 子类只需实现 getTableName() 与 rowToModel()，并组合下列受保护方法。
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from './DatabaseHelper'
import { Logger } from '../utils/Logger'

export abstract class BaseDao<T> {
  protected abstract getTableName(): string
  protected abstract rowToModel(rs: relationalStore.ResultSet): T

  /** 事务只属于本 DAO 实例，不能重定向全应用单例的写入。 */
  private readonly txTarget: relationalStore.Transaction | null

  constructor(tx: relationalStore.Transaction | null = null) {
    this.txTarget = tx
  }

  protected getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  /**
   * 关闭结果集。close 自身也可能抛（例如事务已提交，其创建的结果集随之关闭），
   * 而在 finally 里抛出会**掩盖真正的异常**，且失败本身已无可挽回 —— 故吞掉并记日志。
   */
  protected closeQuietly(rs: relationalStore.ResultSet | null): void {
    if (rs === null) {
      return
    }
    try {
      rs.close()
    } catch (e) {
      Logger.warn('[' + this.getTableName() + '] resultSet close failed: ' + String(e))
    }
  }

  protected async insertRow(valueBucket: relationalStore.ValuesBucket): Promise<void> {
    const tx: relationalStore.Transaction | null = this.txTarget
    try {
      if (tx !== null) {
        await tx.insert(this.getTableName(), valueBucket)
      } else {
        await this.getStore().insert(this.getTableName(), valueBucket)
      }
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] insert failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  protected async updateRow(valueBucket: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates): Promise<void> {
    const tx: relationalStore.Transaction | null = this.txTarget
    try {
      if (tx !== null) {
        await tx.update(valueBucket, predicates)
      } else {
        await this.getStore().update(valueBucket, predicates)
      }
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] update failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  protected async deleteRow(predicates: relationalStore.RdbPredicates): Promise<void> {
    const tx: relationalStore.Transaction | null = this.txTarget
    try {
      if (tx !== null) {
        await tx.delete(predicates)
      } else {
        await this.getStore().delete(predicates)
      }
    } catch (e) {
      Logger.error('[' + this.getTableName() + '] delete failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  /** 全列查询。列表类查询请改用 queryRowsWithColumns / querySqlRows 做列裁剪。 */
  protected async queryRows(predicates: relationalStore.RdbPredicates): Promise<T[]> {
    return this.queryRowsWithColumns(predicates, null)
  }

  /**
   * 列裁剪查询：只取 columns 指定的列（null = 全部列）。
   *
   * resultSet.close() 放在 finally：官方 ResultSet 文档明确「不关闭可能会引起
   * FD 泄漏和内存泄漏」，而 rowToModel 内部仍可能在缺列/异常结果集上抛出，
   * 只写在末尾会让异常路径永远执行不到 close。
   */
  protected async queryRowsWithColumns(predicates: relationalStore.RdbPredicates,
    columns: string[] | null): Promise<T[]> {
    const rs: relationalStore.ResultSet = columns === null
      ? await this.getStore().query(predicates)
      : await this.getStore().query(predicates, columns)
    try {
      const list: T[] = []
      while (rs.goToNextRow()) {
        list.push(this.rowToModel(rs))
      }
      return list
    } finally {
      this.closeQuietly(rs)
    }
  }

  /**
   * 参数化 SQL 查询（值一律走 bindArgs，不拼字符串），用于聚合、裁剪（substr）等
   * RdbPredicates 表达不了的查询。返回行同样交给 rowToModel 映射。
   */
  protected async querySqlRows(sql: string, args: relationalStore.ValueType[]): Promise<T[]> {
    const rs: relationalStore.ResultSet = await this.getStore().querySql(sql, args)
    try {
      const list: T[] = []
      while (rs.goToNextRow()) {
        list.push(this.rowToModel(rs))
      }
      return list
    } finally {
      this.closeQuietly(rs)
    }
  }

  protected async queryByIdRow(id: string): Promise<T | null> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    const rs: relationalStore.ResultSet = await this.getStore().query(predicates)
    try {
      if (rs.goToFirstRow()) {
        return this.rowToModel(rs)
      }
      return null
    } finally {
      this.closeQuietly(rs)
    }
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
