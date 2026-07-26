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
      is_fav: chapter.isFav ? 1 : 0,
      is_inspiration: chapter.isInspiration ? 1 : 0,
      is_trash: chapter.isTrash ? 1 : 0,
      is_private: chapter.isPrivate ? 1 : 0,
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

  async moveToBook(chapterId: string, bookId: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      book_id: bookId,
      updated_at: Date.now()
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', chapterId)
    await this.getStore().update(valueBucket, predicates)
  }

  async setFav(id: string, fav: boolean): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = { is_fav: fav ? 1 : 0, updated_at: Date.now() }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async setTrash(id: string, trash: boolean): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = { is_trash: trash ? 1 : 0, updated_at: Date.now() }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async setInspiration(id: string, insp: boolean): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = { is_inspiration: insp ? 1 : 0, updated_at: Date.now() }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async setPrivate(id: string, priv: boolean): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = { is_private: priv ? 1 : 0, updated_at: Date.now() }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().update(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    await this.getStore().delete(predicates)
  }

  async deleteExpiredTrash(cutoff: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('is_trash', 1)
    predicates.lessThan('updated_at', cutoff)
    await this.getStore().delete(predicates)
  }

  async queryById(id: string): Promise<ChapterModel | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('id', id)
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    if (resultSet.goToFirstRow()) {
      const chapter: ChapterModel = this.rowToModel(resultSet)
      resultSet.close()
      return chapter
    }
    resultSet.close()
    return null
  }

  async queryAllByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByAsc('sort_order')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryFavByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.equalTo('is_fav', 1)
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryInspByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.equalTo('is_inspiration', 1)
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryGlobal(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', '')
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryGlobalFav(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', '')
    predicates.equalTo('is_fav', 1)
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryGlobalInsp(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', '')
    predicates.equalTo('is_inspiration', 1)
    predicates.equalTo('is_trash', 0)
    predicates.equalTo('is_private', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryGlobalPrivate(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', '')
    predicates.equalTo('is_private', 1)
    predicates.equalTo('is_trash', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryAllTrash(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('is_trash', 1)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryTrashByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.equalTo('is_trash', 1)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryPrivateByBook(bookId: string): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('book_id', bookId)
    predicates.equalTo('is_private', 1)
    predicates.equalTo('is_trash', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async queryAll(): Promise<ChapterModel[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    predicates.equalTo('is_trash', 0)
    predicates.orderByDesc('updated_at')
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    const chapters: ChapterModel[] = []
    while (resultSet.goToNextRow()) {
      chapters.push(this.rowToModel(resultSet))
    }
    resultSet.close()
    return chapters
  }

  async countByCategory(bookId: string): Promise<Record<string, number>> {
    const result: Record<string, number> = { 'all': 0, 'fav': 0, 'insp': 0, 'priv': 0, 'trash': 0 }

    const pAll: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pAll.equalTo('book_id', bookId)
    pAll.equalTo('is_trash', 0)
    result['all'] = await this.countPredicate(pAll)

    const pFav: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pFav.equalTo('book_id', bookId)
    pFav.equalTo('is_fav', 1)
    pFav.equalTo('is_trash', 0)
    result['fav'] = await this.countPredicate(pFav)

    const pPriv: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pPriv.equalTo('book_id', bookId)
    pPriv.equalTo('is_private', 1)
    pPriv.equalTo('is_trash', 0)
    result['priv'] = await this.countPredicate(pPriv)

    const pTrash: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pTrash.equalTo('book_id', bookId)
    pTrash.equalTo('is_trash', 1)
    result['trash'] = await this.countPredicate(pTrash)

    const pInsp: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pInsp.equalTo('book_id', bookId)
    pInsp.equalTo('is_inspiration', 1)
    pInsp.equalTo('is_trash', 0)
    result['insp'] = await this.countPredicate(pInsp)
    return result
  }

  async countPredicate(predicates: relationalStore.RdbPredicates): Promise<number> {
    const resultSet: relationalStore.ResultSet = await this.getStore().query(predicates)
    let count: number = 0
    while (resultSet.goToNextRow()) { count++ }
    resultSet.close()
    return count
  }

  async countGlobalByCategory(): Promise<Record<string, number>> {
    const result: Record<string, number> = { 'all': 0, 'fav': 0, 'insp': 0, 'priv': 0, 'trash': 0 }
    const pAll: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pAll.equalTo('book_id', '')
    pAll.equalTo('is_private', 0)
    pAll.equalTo('is_trash', 0)
    result['all'] = await this.countPredicate(pAll)
    const pFav: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pFav.equalTo('book_id', '')
    pFav.equalTo('is_fav', 1)
    pFav.equalTo('is_trash', 0)
    result['fav'] = await this.countPredicate(pFav)
    const pInsp: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pInsp.equalTo('book_id', '')
    pInsp.equalTo('is_inspiration', 1)
    pInsp.equalTo('is_trash', 0)
    result['insp'] = await this.countPredicate(pInsp)
    const pPriv: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pPriv.equalTo('book_id', '')
    pPriv.equalTo('is_private', 1)
    pPriv.equalTo('is_trash', 0)
    result['priv'] = await this.countPredicate(pPriv)
    const pTrash: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('chapters')
    pTrash.equalTo('is_trash', 1)
    result['trash'] = await this.countPredicate(pTrash)
    return result
  }

  rowToModel(resultSet: relationalStore.ResultSet): ChapterModel {
    const isFavCol: boolean = this.safeGetLong(resultSet, 'is_fav') !== 0
    const isInspCol: boolean = this.safeGetLong(resultSet, 'is_inspiration') !== 0
    const isTrashCol: boolean = this.safeGetLong(resultSet, 'is_trash') !== 0
    const isPrivateCol: boolean = this.safeGetLong(resultSet, 'is_private') !== 0
    return {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      bookId: resultSet.getString(resultSet.getColumnIndex('book_id')),
      title: resultSet.getString(resultSet.getColumnIndex('title')),
      content: resultSet.getString(resultSet.getColumnIndex('content')),
      order: resultSet.getLong(resultSet.getColumnIndex('sort_order')),
      wordCount: resultSet.getLong(resultSet.getColumnIndex('word_count')),
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
      isFav: isFavCol,
      isInspiration: isInspCol,
      isTrash: isTrashCol,
      isPrivate: isPrivateCol
    }
  }

  safeGetLong(resultSet: relationalStore.ResultSet, col: string): number {
    try {
      return resultSet.getLong(resultSet.getColumnIndex(col))
    } catch (e) {
      return 0
    }
  }
}
