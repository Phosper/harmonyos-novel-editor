// features/editor/src/main/ets/data/ChapterDao.ets
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '@ohos/common'
import { IdGenerator } from '@ohos/common'
import type { ChapterModel } from '@ohos/common'

export class ChapterDao {
  private getStore(): relationalStore.RdbStore {
    return dbHelper.getStore()
  }

  async insert(chapter: ChapterModel): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: chapter.id,
      book_id: chapter.bookId,
      title: chapter.title,
      content: chapter.content,
      sort_order: chapter.order,
      word_count: chapter.wordCount,
      created_at: chapter.createdAt,
      updated_at: chapter.updatedAt
    }
    await this.getStore().insert('chapters', valueBucket)
  }

  async update(id: string, title: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      title: title,
      content: content,
      word_count: content.length,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async updateContent(id: string, content: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      word_count: content.length,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<ChapterModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const chapter: ChapterModel = {
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        title: resultSet.getString(resultSet.getColumnIndex('title')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        order: resultSet.getLong(resultSet.getColumnIndex('sort_order')),
        wordCount: resultSet.getLong(resultSet.getColumnIndex('word_count')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      }
      resultSet.close()
      return chapter
    }
    resultSet.close()
    return null
  }

  async queryByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.orderByAsc('sort_order')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        title: resultSet.getString(resultSet.getColumnIndex('title')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        order: resultSet.getLong(resultSet.getColumnIndex('sort_order')),
        wordCount: resultSet.getLong(resultSet.getColumnIndex('word_count')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      })
    }
    resultSet.close()
    return chapters
  }

  async queryAll(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
        title: resultSet.getString(resultSet.getColumnIndex('title')),
        content: resultSet.getString(resultSet.getColumnIndex('content')),
        order: resultSet.getLong(resultSet.getColumnIndex('sort_order')),
        wordCount: resultSet.getLong(resultSet.getColumnIndex('word_count')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      })
    }
    resultSet.close()
    return chapters
  }
}
