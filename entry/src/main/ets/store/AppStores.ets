// 状态层协调入口
//
// 各 Store 只负责自己那片数据（项目 / 编辑器 / 素材 / 关系 / 界面），
// 需要跨片协作的动作（切项目、开文稿、删文稿）集中在这里，
// 使 Store 之间不互相依赖，也避免把"编排"散落到组件里。
import { getAppContext } from '../utils/AppContext'
import { dbHelper } from '../database/DatabaseHelper'
import { prefs } from '../utils/PreferenceHelper'
import { Logger } from '../utils/Logger'
import { IdGenerator } from '../utils/IdGenerator'
import { ImportService, ImportedFile, ImportKind } from '../utils/ImportService'
import { HtmlText } from '../utils/HtmlText'
import { exceedsContentLimit, countChars } from '../utils/TextLimit'
import { EditorViewMode, LibId } from '../constants/DesignTokens'
import { ChapterFormat } from '../model/Chapter'
import { TextFormat, FormatOptions } from '../utils/TextFormat'
import type { ChapterModel } from '../model/Chapter'
import { BookMode } from '../model/Book'
import type { BookModel } from '../model/Book'
import type { CharacterModel } from '../model/Character'
import type { WorldSettingModel } from '../model/WorldSetting'
import type { InspirationModel } from '../model/Inspiration'
import type { RelationshipModel } from '../model/Relationship'
import { RelationshipType } from '../model/Relationship'
import { bookRepo, chapterRepo, materialRepo, relationRepo } from './Repos'
import { BookBackupSnapshot, BackupPayload, BackupPayloadLoose } from './BackupTypes'
import { UiStore } from './UiStore'
import { ProjectStore } from './ProjectStore'
import { EditorStore } from './EditorStore'
import { MaterialStore } from './MaterialStore'
import { RelationStore } from './RelationStore'

export class AppStores {
  readonly ui: UiStore = new UiStore()
  readonly project: ProjectStore = new ProjectStore()
  readonly editor: EditorStore = new EditorStore()
  readonly material: MaterialStore = new MaterialStore()
  readonly relation: RelationStore = new RelationStore()

  private inited: boolean = false

  // ===== 启动 =====

  async init(): Promise<void> {
    if (this.inited) {
      return
    }
    const ctx: Context | null = getAppContext()
    if (ctx === null) {
      Logger.warn('AppStores.init: app context not set, skip infrastructure init')
      return
    }
    await prefs.init(ctx)
    await dbHelper.init(ctx)
    await this.ui.loadFromPrefs()

    await this.project.loadBooks()
    await this.project.ensureCurrentBook(this.ui.mode)
    await chapterRepo.cleanExpiredTrash()
    await this.reloadAll()
    this.editor.startTimers()
    this.inited = true
    Logger.info('AppStores initialized: books=' + this.project.books.length +
      ', chapters=' + this.project.chapters.length)
  }

  get isReady(): boolean {
    return this.inited
  }

  /** 重新载入当前项目的全部数据 */
  async reloadAll(): Promise<void> {
    const bookId: string = this.project.currentBookId
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    await this.material.load(bookId)
    await this.relation.load(bookId, this.material.characters)
    this.syncSelection()
  }

  /** 当前文稿变化后同步列表选中态 */
  private syncSelection(): void {
    this.project.markSelected(this.editor.activeId)
  }

  // ===== 项目 =====

  async selectBook(bookId: string): Promise<void> {
    if (this.project.currentBookId === bookId) {
      return
    }
    await this.flushAll()
    this.project.currentBookId = bookId
    this.project.libFilter = LibId.ALL
    this.editor.reset()
    await this.reloadAll()
    this.enterEditorIfEmpty()
  }

  async createBook(name: string): Promise<boolean> {
    const created: BookModel | null = await this.project.createBook(name, this.ui.mode)
    if (created === null) {
      return false
    }
    await this.selectBook(created.id)
    return true
  }

  async deleteBook(bookId: string): Promise<void> {
    await this.flushAll()
    await bookRepo.deleteBook(bookId)
    await this.project.loadBooks()
    this.editor.reset()
    if (this.project.books.length === 0) {
      await this.project.ensureCurrentBook(this.ui.mode)
    } else if (this.project.currentBookId === bookId) {
      this.project.currentBookId = this.project.books[0].id
      this.project.libFilter = LibId.ALL
    }
    await this.reloadAll()
    this.enterEditorIfEmpty()
  }

  // ===== 文稿 =====

  async setLibFilter(lib: LibId): Promise<void> {
    await this.project.setLibFilter(lib)
    this.syncSelection()
    if (lib === LibId.TRASH) {
      // 进废纸篓只列表，不打开编辑
      this.ui.view = EditorViewMode.EMPTY
    }
  }

  async createChapter(title?: string, format: ChapterFormat = ChapterFormat.TXT): Promise<ChapterModel> {
    const ch: ChapterModel = await chapterRepo.createChapter(this.project.currentBookId, title, format)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    await this.openChapter(ch.id)
    return ch
  }

  /** 打开文稿（进入编辑） */
  async openChapter(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.project.findChapter(chapterId)
    if (ch === undefined) {
      return
    }
    await this.editor.openChapter(ch)
    this.ui.view = EditorViewMode.EDITOR
    this.syncSelection()
  }

  /** 只切换标签，不改变中部视图（标签栏点击用） */
  async activateChapter(chapterId: string): Promise<void> {
    await this.editor.activate(chapterId)
    this.ui.view = EditorViewMode.EDITOR
    this.syncSelection()
  }

  /**
   * 手机端启动：直接打开"最近编辑过"的一篇有效文稿，返回是否成功。
   * 用于"主页一打开就是最近编辑过的某文稿页面"的移动端设计。
   */
  async openMostRecentChapter(): Promise<boolean> {
    const list: ChapterModel[] = this.project.chapters.filter((c: ChapterModel) => !c.isTrash)
    if (list.length === 0) {
      return false
    }
    let best: ChapterModel = list[0]
    for (const c of list) {
      if (c.updatedAt > best.updatedAt) {
        best = c
      }
    }
    await this.openChapter(best.id)
    return true
  }

  async closeTab(chapterId: string): Promise<void> {
    await this.editor.close(chapterId)
    if (this.editor.openDocs.length === 0) {
      this.ui.view = EditorViewMode.EMPTY
    }
    this.syncSelection()
  }

  async renameChapter(chapterId: string, title: string): Promise<void> {
    const trimmed: string = title.trim()
    if (trimmed === '') {
      return
    }
    await chapterRepo.rename(chapterId, trimmed)
    this.editor.rename(chapterId, trimmed)
    await this.project.reloadChapters()
    this.syncSelection()
  }

  async moveToTrash(chapterId: string): Promise<void> {
    await chapterRepo.trash(chapterId)
    await this.editor.closeIfOpen(chapterId)
    this.editor.discard(chapterId)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
  }

  async hardDeleteChapter(chapterId: string): Promise<void> {
    await chapterRepo.hardDelete(chapterId)
    await this.editor.closeIfOpen(chapterId)
    this.editor.discard(chapterId)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
  }

  async restoreChapter(chapterId: string): Promise<void> {
    await chapterRepo.restore(chapterId)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
  }

  async toggleFav(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.project.findChapter(chapterId)
    if (ch === undefined) {
      return
    }
    await chapterRepo.setFav(chapterId, !ch.isFav)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
  }

  async toggleInspiration(chapterId: string): Promise<void> {
    const ch: ChapterModel | undefined = this.project.findChapter(chapterId)
    if (ch === undefined) {
      return
    }
    await chapterRepo.setInspiration(chapterId, !ch.isInspiration)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
  }

  /** 切换当前文稿的正文格式（TXT / MD） */
  async setChapterFormat(format: ChapterFormat): Promise<void> {
    const doc = this.editor.activeDoc
    if (doc === undefined || doc.format === format) {
      return
    }
    await chapterRepo.setFormat(doc.id, format)
    await this.project.reloadChapters()
  }

  // ===== 素材 / 关系（写入后刷新关系图） =====

  async refreshMaterials(): Promise<void> {
    await this.material.load(this.project.currentBookId)
    this.relation.rebuild(this.material.characters)
  }

  /**
   * 删除人物。必须走协调层而不是直接调 material.deleteCharacter：
   * 人物删除会级联删掉它的关系行，若不同步 rebuild，图上会残留指向
   * 已不存在人物的连线与节点（内存里的 nodes/edges 是上一次构建的快照）。
   */
  async deleteCharacter(id: string): Promise<void> {
    await this.material.deleteCharacter(this.project.currentBookId, id)
    await this.relation.reload(this.project.currentBookId, this.material.characters)
  }

  /** 更新人物：改名同样会让关系图上的节点名失效，需一并重建 */
  async updateCharacter(data: CharacterModel): Promise<void> {
    await this.material.updateCharacter(this.project.currentBookId, data)
    await this.relation.reload(this.project.currentBookId, this.material.characters)
  }

  async addRelation(fromId: string, toId: string, type: RelationshipType,
    label: string, notes: string): Promise<void> {
    await this.relation.add(this.project.currentBookId, fromId, toId, type, label, notes,
      this.material.characters)
  }

  async deleteRelation(id: string): Promise<void> {
    await this.relation.remove(id, this.material.characters)
  }

  // ===== 视图切换 =====

  /** 一键排版当前文稿（返回修改的行数） */
  formatActiveDoc(): number {
    if (!this.editor.hasDoc) {
      return 0
    }
    const res = TextFormat.format(this.editor.content, new FormatOptions())
    if (res.changed > 0) {
      this.editor.applyExternalContent(res.text)
    }
    return res.changed
  }

  showEditor(): void {
    this.ui.view = this.editor.hasDoc ? EditorViewMode.EDITOR : EditorViewMode.EMPTY
  }

  async showMaterials(): Promise<void> {
    this.ui.view = EditorViewMode.MATERIAL
    await this.refreshMaterials()
  }

  async showGraph(): Promise<void> {
    this.ui.view = EditorViewMode.GRAPH
    await this.refreshMaterials()
  }

  private enterEditorIfEmpty(): void {
    this.ui.view = EditorViewMode.EMPTY
  }

  // ===== 导入 / 备份恢复 =====

  /**
   * 批量导入：TXT / MD 建文稿，HTML 抽正文建文稿，JSON（Weaver 备份）恢复为新项目。
   * 返回一句可直接展示的结果摘要。
   */
  async importFiles(): Promise<string> {
    let files: ImportedFile[] = []
    try {
      files = await ImportService.pickAndRead()
    } catch (e) {
      Logger.error('Pick files failed: ' + String(e))
      return '导入失败：无法读取所选文件'
    }
    if (files.length === 0) {
      return ''
    }
    let chapterCount: number = 0
    let backupCount: number = 0
    let skipped: number = 0
    let oversized: number = 0
    for (const file of files) {
      if (file.kind === ImportKind.BACKUP) {
        const restored: string = await this.importBackupText(file.text)
        if (restored !== '') {
          backupCount++
        } else {
          skipped++
        }
        continue
      }
      const content: string = file.kind === ImportKind.HTML
        ? HtmlText.toPlainText(file.text)
        : file.text
      if (content.trim() === '') {
        skipped++
        continue
      }
      // 超过单篇入库上限的文件直接跳过：先建文稿再写内容会在写入处失败，
      // 留下一个空壳文稿，看起来像导入成功实则丢内容。
      if (exceedsContentLimit(content)) {
        Logger.warn('Import skipped, too large: ' + file.fileName)
        oversized++
        continue
      }
      const htmlTitle: string = file.kind === ImportKind.HTML ? HtmlText.titleOf(file.text) : ''
      const title: string = htmlTitle !== '' ? htmlTitle : ImportService.titleOf(file)
      const ch: ChapterModel = await chapterRepo.createChapter(this.project.currentBookId, title, file.format)
      await chapterRepo.updateContent(ch.id, content)
      chapterCount++
    }
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
    const parts: string[] = []
    if (chapterCount > 0) parts.push('导入 ' + chapterCount + ' 篇文稿')
    if (backupCount > 0) parts.push('恢复 ' + backupCount + ' 个备份项目')
    if (oversized > 0) parts.push(oversized + ' 个超过单篇上限未导入')
    if (skipped > 0) parts.push('跳过 ' + skipped + ' 个')
    return parts.length > 0 ? parts.join('，') : '没有可导入的内容'
  }

  /**
   * 解析 JSON 备份并恢复为**新项目**：ID 全部重映射（人物关系同步指向新人物），
   * 不覆盖也不改动现有数据，故恢复失败不会破坏当前内容。
   */
  async importBackupText(json: string): Promise<string> {
    try {
      const payload: BackupPayloadLoose = JSON.parse(json) as BackupPayloadLoose
      if (payload === null || payload === undefined || payload.app !== 'Weaver') {
        Logger.warn('Not a Weaver backup, skipped')
        return ''
      }
      const chapters: ChapterModel[] = payload.chapters ?? []
      const characters: CharacterModel[] = payload.characters ?? []
      const worldSettings: WorldSettingModel[] = payload.worldSettings ?? []
      const inspirations: InspirationModel[] = payload.inspirations ?? []
      const relationships: RelationshipModel[] = payload.relationships ?? []

      const snapshot: BookBackupSnapshot | null | undefined = payload.book
      const baseName: string = snapshot !== null && snapshot !== undefined ? snapshot.name : '导入备份'
      const mode: BookMode = snapshot !== null && snapshot !== undefined ? snapshot.mode : this.ui.mode
      const book: BookModel = await bookRepo.createBook(baseName + '（导入）', mode)

      const charIdMap: Map<string, string> = new Map<string, string>()
      let skippedChapters: number = 0
      // 整组写入放进事务：中途失败整组回滚，不留半成品项目
      await dbHelper.runInTransaction(async () => {
        for (const c of characters) {
          const newId: string = IdGenerator.generate()
          charIdMap.set(c.id, newId)
          const model: CharacterModel = {
            id: newId, bookId: book.id, name: c.name, alias: c.alias, age: c.age,
            appearance: c.appearance, personality: c.personality, background: c.background,
            notes: c.notes, characterType: c.characterType,
            createdAt: c.createdAt, updatedAt: c.updatedAt
          }
          await materialRepo.insertCharacter(model)
        }
        for (const w of worldSettings) {
          const model: WorldSettingModel = {
            id: IdGenerator.generate(), bookId: book.id, name: w.name, category: w.category,
            region: w.region, description: w.description, notes: w.notes, content: w.content,
            createdAt: w.createdAt, updatedAt: w.updatedAt
          }
          await materialRepo.insertWorld(model)
        }
        for (const ins of inspirations) {
          const model: InspirationModel = {
            id: IdGenerator.generate(), bookId: book.id, content: ins.content,
            createdAt: ins.createdAt, updatedAt: ins.updatedAt
          }
          await materialRepo.insertInspiration(model)
        }
      let order: number = 0
      for (const ch of chapters) {
        const content: string = ch.content ?? ''
        // 备份里若含超长正文，DAO 守卫会抛错并回滚**整个**恢复。
        // 与其让用户什么都没导入，不如跳过这些篇章、恢复其余内容。
        if (exceedsContentLimit(content)) {
          Logger.warn('Backup restore: skip oversized chapter ' + ch.title)
          skippedChapters++
          continue
        }
        const model: ChapterModel = {
            id: IdGenerator.generate(),
            bookId: book.id,
            title: ch.title !== undefined && ch.title.trim() !== '' ? ch.title : '无标题',
            content: content,
            format: ch.format === ChapterFormat.MD ? ChapterFormat.MD : ChapterFormat.TXT,
            order: order,
            wordCount: ch.wordCount > 0 ? ch.wordCount : countChars(content),
            caretOffset: ch.caretOffset > 0 ? ch.caretOffset : 0,
            createdAt: ch.createdAt,
            updatedAt: ch.updatedAt,
            isFav: ch.isFav === true,
            isInspiration: ch.isInspiration === true,
            isTrash: ch.isTrash === true
          }
          order++
          await chapterRepo.insertChapter(model)
        }
        for (const r of relationships) {
          const a: string | undefined = charIdMap.get(r.characterIdA)
          const b: string | undefined = charIdMap.get(r.characterIdB)
          if (a === undefined || b === undefined) {
            continue
          }
          const model: RelationshipModel = {
            id: IdGenerator.generate(), bookId: book.id, characterIdA: a, characterIdB: b,
            type: r.type, label: r.label, notes: r.notes,
            createdAt: r.createdAt, updatedAt: r.updatedAt
          }
          await relationRepo.insert(model)
        }
      })

      await this.selectBook(book.id)
      if (skippedChapters > 0) {
        return book.name + '（' + skippedChapters + ' 篇因超长未导入）'
      }
      return book.name
    } catch (e) {
      Logger.error('Backup restore failed: ' + String(e))
      return ''
    }
  }

  /** 汇总当前项目的全部数据为备份载荷 */
  async exportBackupData(): Promise<BackupPayload> {
    const bookId: string = this.project.currentBookId
    const chapters: ChapterModel[] = await chapterRepo.loadChapters(bookId, LibId.ALL)
    const book: BookModel | undefined = this.project.currentBook
    const snapshot: BookBackupSnapshot | null = book !== undefined
      ? { id: book.id, name: book.name, mode: book.mode }
      : null
    const payload: BackupPayload = {
      app: 'Weaver',
      version: 1,
      exportedAt: Date.now(),
      book: snapshot,
      chapters: chapters,
      characters: this.material.characters,
      worldSettings: this.material.worldSettings,
      inspirations: this.material.inspirations,
      relationships: this.relation.relationships
    }
    return payload
  }

  // ===== 生命周期 =====

  async flushAll(): Promise<void> {
    await this.editor.flushAll()
  }

  destroy(): void {
    this.editor.flushAll()
    this.editor.stopTimers()
  }
}

// 全局单例：跨页面共享同一份状态
export const app: AppStores = new AppStores()
