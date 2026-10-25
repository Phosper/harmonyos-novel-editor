// 书籍（项目）仓储 —— UI/VM 只依赖此层，不再直接 new Dao
import { relationalStore } from '@kit.ArkData'
import { BookDao } from '../database/BookDao'
import { IdGenerator } from '../utils/IdGenerator'
import type { BookModel } from '../model/Book'
import { BookMode } from '../model/Book'

export class BookRepository {
  private dao: BookDao

  constructor(tx: relationalStore.Transaction | null = null) {
    this.dao = new BookDao(tx)
  }

  async createBook(name: string, mode: BookMode = BookMode.PROFESSIONAL): Promise<BookModel> {
    const book: BookModel = {
      id: IdGenerator.generate(),
      name: name.trim(),
      mode: mode,
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await this.dao.insert(book)
    return book
  }

  async renameBook(id: string, name: string): Promise<void> {
    await this.dao.updateName(id, name.trim())
  }

  async deleteBook(id: string): Promise<void> {
    await this.dao.delete(id)
  }

  async getAllBooks(): Promise<BookModel[]> {
    return this.dao.queryAll()
  }

  async getBook(id: string): Promise<BookModel | null> {
    return this.dao.queryById(id)
  }
}
