// 普通仓储始终使用 store；事务使用独立实例，不改变全应用单例。
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

/** 只在一次恢复回调内使用。读仍走 store，不能读取本事务未提交的数据。 */
export class TransactionRepos {
  readonly bookRepo: BookRepository
  readonly chapterRepo: ChapterRepository
  readonly materialRepo: MaterialRepository
  readonly relationRepo: RelationshipRepository

  constructor(tx: relationalStore.Transaction) {
    this.bookRepo = new BookRepository(tx)
    this.chapterRepo = new ChapterRepository(tx)
    this.materialRepo = new MaterialRepository(tx)
    this.relationRepo = new RelationshipRepository(tx)
  }
}

/**
 * 恢复写入全部成功才提交，任一失败整组回滚。
 * 回调必须使用传入的仓储；定时保存继续走普通 chapterRepo，遇到写锁保留 dirty 重试。
 */
export async function runInTransaction<T>(work: (repos: TransactionRepos) => Promise<T>): Promise<T> {
  const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
  try {
    const result: T = await work(new TransactionRepos(tx))
    await tx.commit()
    return result
  } catch (e) {
    try {
      await tx.rollback()
    } catch (rollbackError) {
      Logger.error('Rollback failed: ' + String(rollbackError))
    }
    Logger.error('Transaction rolled back: ' + String(e))
    throw new Error(String(e))
  }
}
