// 仓储单例 —— Repository 本身无状态（只包一层 DAO），全应用共用一份即可，
// 避免各处 new XxxRepository() 造成重复实例与潜在状态漂移。
import { relationalStore } from '@kit.ArkData'
import { BookRepository } from '../repository/BookRepository'
import { ChapterRepository } from '../repository/ChapterRepository'
import { MaterialRepository } from '../repository/MaterialRepository'
import { RelationshipRepository } from '../repository/RelationshipRepository'
import { dbHelper } from '../database/DatabaseHelper'
import { Logger } from '../utils/Logger'

export const bookRepo: BookRepository = new BookRepository()
export const chapterRepo: ChapterRepository = new ChapterRepository()
export const materialRepo: MaterialRepository = new MaterialRepository()
export const relationRepo: RelationshipRepository = new RelationshipRepository()

/**
 * 在**独立写事务**中执行一组写入：全部成功才提交，任一失败整组回滚。
 *
 * 为什么必须是 createTransaction（而不是 store.beginTransaction）：
 * 官方文档在 createTransaction 条目下写明「与 beginTransaction 的区别在于：
 * createTransaction 接口会返回一个事务对象，不同事务对象之间是隔离的」，并且
 * 「优先使用 createTransaction，不再推荐使用 beginTransaction」。
 *
 * 旧实现的问题不是写法过时，而是**真会丢数据**：beginTransaction 把事务建在 store 的
 * 共享写连接上，而事务回调里每次 await 的间隙，事件循环都会去跑别的任务 ——
 * 编辑器的防抖保存与 30 秒安全网正好会发出 `UPDATE chapters ...`，这些写会落到同一条
 * 写连接并**被并入本事务**。备份恢复一旦中途失败回滚，用户刚保存的正文会被一起回滚，
 * 而 EditorStore 已经把 dirty 清成 false、界面显示「已保存」，静默丢失。
 *
 * 换成独立事务对象后，事务占用写事务期间，事务外的写入会拿到 14800024
 * （SQLite: The database file is locked）—— 这是**可重试的显式失败**，
 * EditorStore 会保留 dirty 让安全网稍后重试，比静默并入后被回滚安全得多。
 *
 * 事务内的写由 BaseDao.setTransaction 重定向到事务对象；读仍走 store
 * （当前唯一调用方不在事务内读，无需处理未提交可见性）。
 */
export async function runInTransaction<T>(work: () => Promise<T>): Promise<T> {
  const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
  setTransactionTargets(tx)
  try {
    const result: T = await work()
    await tx.commit()
    return result
  } catch (e) {
    try {
      await tx.rollback()
    } catch (rollbackError) {
      // 回滚本身失败已无法挽回，记日志后按原异常抛出
      Logger.error('Rollback failed: ' + String(rollbackError))
    }
    Logger.error('Transaction rolled back: ' + String(e))
    throw new Error(String(e))
  } finally {
    setTransactionTargets(null)
  }
}

function setTransactionTargets(tx: relationalStore.Transaction | null): void {
  bookRepo.setTransaction(tx)
  chapterRepo.setTransaction(tx)
  materialRepo.setTransaction(tx)
  relationRepo.setTransaction(tx)
}
