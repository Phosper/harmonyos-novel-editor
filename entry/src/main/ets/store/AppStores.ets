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
import { bookRepo, chapterRepo, materialRepo, relationRepo, runInTransaction } from './Repos'
import type { TransactionRepos } from './Repos'
import { BookBackupSnapshot, BackupPayload, BackupPayloadLoose } from './BackupTypes'
import { UiStore } from './UiStore'
import { ProjectStore } from './ProjectStore'
import { EditorStore } from './EditorStore'
import type { EditorDraftSnapshot } from './EditorStore'
import { MaterialStore } from './MaterialStore'
import { RelationStore } from './RelationStore'

export class AppStores {
  readonly ui: UiStore = new UiStore()
  readonly project: ProjectStore = new ProjectStore()
  readonly editor: EditorStore = new EditorStore()
  readonly material: MaterialStore = new MaterialStore()
  readonly relation: RelationStore = new RelationStore()

  private inited: boolean = false
  private openRequestRev: number = 0
  private projectRequestRev: number = 0
  private reloadRequestRev: number = 0

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
    const request: number = ++this.reloadRequestRev
    const bookId: string = this.project.currentBookId
    this.material.setBookScope(bookId)
    this.relation.setBookScope(bookId)
    await this.project.reloadChapters()
    if (request !== this.reloadRequestRev || bookId !== this.project.currentBookId) return
    await this.project.refreshCounts()
    if (request !== this.reloadRequestRev || bookId !== this.project.currentBookId) return
    await this.material.load(bookId)
    if (request !== this.reloadRequestRev || bookId !== this.project.currentBookId) return
    await this.relation.load(bookId, this.material.characters)
    if (request !== this.reloadRequestRev || bookId !== this.project.currentBookId) return
    this.syncSelection()
  }

  /** 当前文稿变化后同步列表选中态 */
  private syncSelection(): void {
    this.project.markSelected(this.editor.activeId)
  }

  // ===== 项目 =====

  async selectBook(bookId: string): Promise<void> {
    const request: number = ++this.projectRequestRev
    if (this.project.currentBookId === bookId) {
      return
    }
    await this.editor.flushAllStrict()
    if (request !== this.projectRequestRev) return
    this.openRequestRev++
    this.reloadRequestRev++
    this.project.setCurrentBook(bookId)
    this.material.setBookScope(bookId)
    this.relation.setBookScope(bookId)
    this.editor.reset()
    this.enterEditorIfEmpty()
    await this.reloadAll()
    if (request !== this.projectRequestRev || bookId !== this.project.currentBookId) return
    this.enterEditorIfEmpty()
  }

  async createBook(name: string): Promise<boolean> {
    const trimmed: string = name.trim()
    if (trimmed === '') {
      return false
    }
    // 保存失败必须在 INSERT 前返回，保留对话框重试才不会创建重复项目。
    await this.editor.flushAllStrict()
    const created: BookModel = await bookRepo.createBook(trimmed, this.ui.mode)
    // 已入库就已创建成功。先保留可见项，后续列表查询失败也不能诱导再次创建。
    this.project.registerBook(created)
    try {
      await this.project.loadBooks()
      await this.selectBook(created.id)
    } catch (switchError) {
      Logger.warn('Book created, switching failed: ' + String(switchError))
    }
    return true
  }

  async deleteBook(bookId: string): Promise<void> {
    await this.editor.flushAllStrict()
    this.openRequestRev++
    await bookRepo.deleteBook(bookId)
    await this.project.loadBooks()
    this.editor.reset()
    if (this.project.books.length === 0) {
      await this.project.ensureCurrentBook(this.ui.mode)
    } else if (this.project.currentBookId === bookId) {
      this.project.setCurrentBook(this.project.books[0].id)
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
    const request: number = ++this.openRequestRev
    this.editor.cancelPendingActivation()
    const bookId: string = this.project.currentBookId
    // 必须按 id 取**完整**正文：ProjectStore.chapters 是列表投影（正文只有前缀），
    // 而且内存里的那行可能已经被编辑过 —— 直接拿它当草稿初值，会在
    // 「关掉标签再打开」时把旧正文写回去，覆盖掉此前已保存的内容。
    const ch: ChapterModel | null = await chapterRepo.loadOne(chapterId)
    if (ch === null || request !== this.openRequestRev || bookId !== this.project.currentBookId) {
      return
    }
    await this.editor.openChapter(ch)
    if (request !== this.openRequestRev || bookId !== this.project.currentBookId) {
      return
    }
    this.ui.view = EditorViewMode.EDITOR
    this.syncSelection()
  }

  /** 只切换标签，不改变中部视图（标签栏点击用） */
  async activateChapter(chapterId: string): Promise<void> {
    const request: number = ++this.openRequestRev
    const bookId: string = this.project.currentBookId
    await this.editor.activate(chapterId)
    if (request !== this.openRequestRev || bookId !== this.project.currentBookId) {
      return
    }
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
    this.openRequestRev++
    await this.editor.closeIfOpen(chapterId)
    await chapterRepo.trash(chapterId)
    this.editor.discard(chapterId)
    await this.project.reloadChapters()
    await this.project.refreshCounts()
    this.syncSelection()
  }

  async hardDeleteChapter(chapterId: string): Promise<void> {
    this.openRequestRev++
    await this.editor.closeIfOpen(chapterId)
    await chapterRepo.hardDelete(chapterId)
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
    doc.format = format
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

      let skippedChapters: number = 0
      // 恢复只使用回调专属仓储，普通自动保存不会被并入恢复事务。
      const book: BookModel = await runInTransaction(async (repos: TransactionRepos): Promise<BookModel> => {
        const created: BookModel = await repos.bookRepo.createBook(baseName + '（导入）', mode)
        const charIdMap: Map<string, string> = new Map<string, string>()
        for (const c of characters) {
          const newId: string = IdGenerator.generate()
          charIdMap.set(c.id, newId)
          const model: CharacterModel = {
            id: newId, bookId: created.id, name: c.name, alias: c.alias, age: c.age,
            appearance: c.appearance, personality: c.personality, background: c.background,
            notes: c.notes, characterType: c.characterType,
            createdAt: c.createdAt, updatedAt: c.updatedAt
          }
          await repos.materialRepo.insertCharacter(model)
        }
        for (const w of worldSettings) {
          const model: WorldSettingModel = {
            id: IdGenerator.generate(), bookId: created.id, name: w.name, category: w.category,
            region: w.region, description: w.description, notes: w.notes, content: w.content,
            createdAt: w.createdAt, updatedAt: w.updatedAt
          }
          await repos.materialRepo.insertWorld(model)
        }
        for (const ins of inspirations) {
          const model: InspirationModel = {
            id: IdGenerator.generate(), bookId: created.id, content: ins.content,
            createdAt: ins.createdAt, updatedAt: ins.updatedAt
          }
          await repos.materialRepo.insertInspiration(model)
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
            bookId: created.id,
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
            isTrash: ch.isTrash === true,
            formatRuns: typeof ch.formatRuns === 'string' ? ch.formatRuns : ''
          }
          order++
          await repos.chapterRepo.insertChapter(model)
        }
        for (const r of relationships) {
          const a: string | undefined = charIdMap.get(r.characterIdA)
          const b: string | undefined = charIdMap.get(r.characterIdB)
          if (a === undefined || b === undefined) {
            continue
          }
          const model: RelationshipModel = {
            id: IdGenerator.generate(), bookId: created.id, characterIdA: a, characterIdB: b,
            type: r.type, label: r.label, notes: r.notes,
            createdAt: r.createdAt, updatedAt: r.updatedAt
          }
          await repos.relationRepo.insert(model)
        }
        return created
      })

      this.project.registerBook(book)
      try {
        await this.project.loadBooks()
        await this.selectBook(book.id)
      } catch (switchError) {
        // 事务已经提交：当前草稿保存失败只阻止切项目，不能把成功恢复报告成失败。
        Logger.warn('Backup restored, refresh or switching failed: ' + String(switchError))
        return book.name + '（已恢复，暂时无法切换项目）'
      }
      if (skippedChapters > 0) {
        return book.name + '（' + skippedChapters + ' 篇因超长未导入）'
      }
      return book.name
    } catch (e) {
      Logger.error('Backup restore failed: ' + String(e))
      return ''
    }
  }

  /**
   * 整本导出用：完整文稿叠加调用时的内存草稿，包含未触发防抖保存的内容。
   * 注意不能用 project.chapters —— 那是列表投影，正文只有前缀。
   */
  async loadFullChapters(): Promise<ChapterModel[]> {
    const bookId: string = this.project.currentBookId
    const drafts: Map<string, EditorDraftSnapshot> = new Map<string, EditorDraftSnapshot>()
    for (const draft of this.editor.snapshotDrafts()) {
      drafts.set(draft.id, draft)
    }
    const chapters: ChapterModel[] = await chapterRepo.loadChaptersFull(bookId)
    for (const ch of chapters) {
      const draft: EditorDraftSnapshot | undefined = drafts.get(ch.id)
      if (draft !== undefined) {
        ch.title = draft.title
        ch.content = draft.content
        ch.format = draft.format
        ch.caretOffset = draft.caretOffset
        ch.formatRuns = draft.formatRuns
        ch.wordCount = countChars(draft.content)
      }
    }
    return chapters
  }

  /** 汇总当前项目的全部数据为备份载荷 */
  async exportBackupData(): Promise<BackupPayload> {
    // 书籍与草稿在调用时捕获。素材按相同 bookId 查库，不能依赖正在切项目的 UI 缓存。
    const bookId: string = this.project.currentBookId
    const book: BookModel | undefined = this.project.currentBook
    const snapshot: BookBackupSnapshot | null = book !== undefined
      ? { id: book.id, name: book.name, mode: book.mode }
      : null
    const chapters: ChapterModel[] = await this.loadFullChapters()
    const characters: CharacterModel[] = await materialRepo.loadCharacters(bookId)
    const worldSettings: WorldSettingModel[] = await materialRepo.loadWorldSettings(bookId)
    const inspirations: InspirationModel[] = await materialRepo.loadInspirationsByBook(bookId)
    const relationships: RelationshipModel[] = await relationRepo.loadRelationships(bookId)
    const payload: BackupPayload = {
      app: 'Weaver',
      version: 1,
      exportedAt: Date.now(),
      book: snapshot,
      chapters: chapters,
      characters: characters,
      worldSettings: worldSettings,
      inspirations: inspirations,
      relationships: relationships
    }
    return payload
  }

  // ===== 生命周期 =====

  async flushAll(): Promise<void> {
    await this.editor.flushAll()
  }

  /**
   * 严格落库：任一草稿未保存成功即 reject，供关闭窗口等“不能静默丢稿”的路径使用。
   */
  async flushAllStrict(): Promise<void> {
    await this.editor.flushAllStrict()
  }

  destroy(): void {
    this.editor.flushAll()
    this.editor.stopTimers()
  }
}

// 全局单例：跨页面共享同一份状态
export const app: AppStores = new AppStores()

/**
 * 收敛「不该让异常冒出去」的异步动作（返回 void，调用点无法也不需要等待）。
 *
 * 为什么必须有：项目自身注释（AppShell 处理 app.init 的地方）已指出
 * 「不能把异常抛成未处理的 Promise 拒绝（会被系统按 JS 错误杀进程）」。
 * 而 store 层的写动作（createChapter / openChapter / toggleFav / moveToTrash …）
 * 末端都会走到 DAO 的 throw，从 onClick、长按菜单回调这类无法 await 的位置调用时，
 * 就必须显式接住 —— 否则一次「数据库被锁 (14800024)」或超限就会让整应用退出。
 */
export function fireAndLog<T>(action: Promise<T>, what: string): void {
  action.catch((e: Error): void => {
    Logger.error(what + ' failed: ' + String(e))
  })
}
