// 素材状态：人物 / 世界观 / 灵感
//
// 注意：不再在第一版数据为空时自动塞入「主角」「世界设定」占位记录 ——
// 旧实现进一次素材页就会凭空多出两条假数据，对一个"简洁"的写作工具是噪音。
import type { CharacterModel } from '../model/Character'
import { CharacterType } from '../model/Character'
import type { WorldSettingModel } from '../model/WorldSetting'
import { WorldCategory } from '../model/WorldSetting'
import type { InspirationModel } from '../model/Inspiration'
import { IdGenerator } from '../utils/IdGenerator'
import { materialRepo } from './Repos'

@ObservedV2
export class MaterialStore {
  @Trace characters: CharacterModel[] = []
  @Trace worldSettings: WorldSettingModel[] = []
  @Trace inspirations: InspirationModel[] = []

  get isEmpty(): boolean {
    return this.characters.length === 0 && this.worldSettings.length === 0 &&
      this.inspirations.length === 0
  }

  findCharacter(id: string): CharacterModel | undefined {
    return this.characters.find((c: CharacterModel) => c.id === id)
  }

  findWorld(id: string): WorldSettingModel | undefined {
    return this.worldSettings.find((w: WorldSettingModel) => w.id === id)
  }

  findInspiration(id: string): InspirationModel | undefined {
    return this.inspirations.find((i: InspirationModel) => i.id === id)
  }

  async load(bookId: string): Promise<void> {
    this.characters = await materialRepo.loadCharacters(bookId)
    this.worldSettings = await materialRepo.loadWorldSettings(bookId)
    this.inspirations = await materialRepo.loadInspirationsByBook(bookId)
  }

  async reloadCharacters(bookId: string): Promise<void> {
    this.characters = await materialRepo.loadCharacters(bookId)
  }

  async reloadWorldSettings(bookId: string): Promise<void> {
    this.worldSettings = await materialRepo.loadWorldSettings(bookId)
  }

  async reloadInspirations(bookId: string): Promise<void> {
    this.inspirations = await materialRepo.loadInspirationsByBook(bookId)
  }

  // ===== 人物 =====

  /** 新建一个空白人物并返回，供详情页直接进入编辑 */
  async createCharacter(bookId: string, name: string): Promise<CharacterModel> {
    const now: number = Date.now()
    const model: CharacterModel = {
      id: IdGenerator.generate(),
      bookId: bookId,
      name: name,
      alias: '',
      age: '',
      appearance: '',
      personality: '',
      background: '',
      notes: '',
      characterType: CharacterType.SUPPORT,
      createdAt: now,
      updatedAt: now
    }
    await materialRepo.insertCharacter(model)
    await this.reloadCharacters(bookId)
    return model
  }

  async updateCharacter(bookId: string, data: CharacterModel): Promise<void> {
    await materialRepo.updateCharacter(data)
    await this.reloadCharacters(bookId)
  }

  async deleteCharacter(bookId: string, id: string): Promise<void> {
    await materialRepo.deleteCharacter(id)
    await this.reloadCharacters(bookId)
  }

  // ===== 世界观 =====

  async createWorld(bookId: string, name: string): Promise<WorldSettingModel> {
    const now: number = Date.now()
    const model: WorldSettingModel = {
      id: IdGenerator.generate(),
      bookId: bookId,
      name: name,
      category: WorldCategory.OTHER,
      region: '',
      description: '',
      notes: '',
      content: '',
      createdAt: now,
      updatedAt: now
    }
    await materialRepo.insertWorld(model)
    await this.reloadWorldSettings(bookId)
    return model
  }

  async updateWorld(bookId: string, data: WorldSettingModel): Promise<void> {
    await materialRepo.updateWorld(data)
    await this.reloadWorldSettings(bookId)
  }

  async deleteWorld(bookId: string, id: string): Promise<void> {
    await materialRepo.deleteWorld(id)
    await this.reloadWorldSettings(bookId)
  }

  // ===== 灵感 =====

  async createInspiration(bookId: string, content: string): Promise<InspirationModel> {
    const now: number = Date.now()
    const model: InspirationModel = {
      id: IdGenerator.generate(),
      bookId: bookId,
      content: content,
      createdAt: now,
      updatedAt: now
    }
    await materialRepo.insertInspiration(model)
    await this.reloadInspirations(bookId)
    return model
  }

  async updateInspiration(bookId: string, data: InspirationModel): Promise<void> {
    await materialRepo.updateInspiration(data)
    await this.reloadInspirations(bookId)
  }

  async deleteInspiration(bookId: string, id: string): Promise<void> {
    await materialRepo.deleteInspiration(id)
    await this.reloadInspirations(bookId)
  }
}
