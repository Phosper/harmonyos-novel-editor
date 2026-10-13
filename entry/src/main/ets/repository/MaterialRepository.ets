// 素材仓储 —— 人物 / 世界观 / 灵感
import { relationalStore } from '@kit.ArkData'
import { CharacterDao } from '../database/CharacterDao'
import { WorldSettingDao } from '../database/WorldSettingDao'
import { InspirationDao } from '../database/InspirationDao'
import { IdGenerator } from '../utils/IdGenerator'
import type { CharacterModel } from '../model/Character'
import { CharacterType } from '../model/Character'
import type { WorldSettingModel } from '../model/WorldSetting'
import { WorldCategory } from '../model/WorldSetting'
import type { InspirationModel } from '../model/Inspiration'

export class MaterialRepository {
  private charDao: CharacterDao = new CharacterDao()
  private worldDao: WorldSettingDao = new WorldSettingDao()
  private inspDao: InspirationDao = new InspirationDao()

  /** 由 Repos.runInTransaction 调用：把写操作重定向到独立事务对象 */
  setTransaction(tx: relationalStore.Transaction | null): void {
    this.charDao.setTransaction(tx)
    this.worldDao.setTransaction(tx)
    this.inspDao.setTransaction(tx)
  }

  // ===== 人物 =====
  async loadCharacters(bookId: string): Promise<CharacterModel[]> {
    return bookId === '' ? this.charDao.queryAll() : this.charDao.queryByBook(bookId)
  }

  async insertCharacter(data: CharacterModel): Promise<void> {
    await this.charDao.insert(data)
  }

  async updateCharacter(data: CharacterModel): Promise<void> {
    await this.charDao.update(data)
  }

  async deleteCharacter(id: string): Promise<void> {
    await this.charDao.delete(id)
  }

  // ===== 世界观 =====
  async loadWorldSettings(bookId: string): Promise<WorldSettingModel[]> {
    return bookId === '' ? this.worldDao.queryAll() : this.worldDao.queryByBook(bookId)
  }

  async insertWorld(data: WorldSettingModel): Promise<void> {
    await this.worldDao.insert(data)
  }

  async updateWorld(data: WorldSettingModel): Promise<void> {
    await this.worldDao.update(data)
  }

  async updateWorldContent(id: string, content: string): Promise<void> {
    await this.worldDao.updateContent(id, content)
  }

  async deleteWorld(id: string): Promise<void> {
    await this.worldDao.delete(id)
  }

  // ===== 灵感 =====
  async loadInspirationsByBook(bookId: string): Promise<InspirationModel[]> {
    return this.inspDao.queryByBook(bookId)
  }

  async loadUncategorizedInspirations(): Promise<InspirationModel[]> {
    return this.inspDao.queryUncategorized()
  }

  async loadAllInspirations(): Promise<InspirationModel[]> {
    return this.inspDao.queryAll()
  }

  async insertInspiration(data: InspirationModel): Promise<void> {
    await this.inspDao.insert(data)
  }

  async updateInspiration(data: InspirationModel): Promise<void> {
    await this.inspDao.update(data)
  }

  async deleteInspiration(id: string): Promise<void> {
    await this.inspDao.delete(id)
  }
}
