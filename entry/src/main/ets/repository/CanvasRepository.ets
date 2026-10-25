// 思路板仓储：五张表的读写 + 跨表原子操作（删卡片 / 删项目 / 备份恢复）
//
// 约定：
// - 组合写操作（删卡片要动 placements/links/evidence/topics）自己开独立写事务，
//   且只用事务绑定的 DAO 实例写；读仍走 store（事务内读不到未提交数据，见 BaseDao）。
// - 上层（CanvasStore）只碰这里的粗粒度方法，不直接调 DAO。
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '../database/DatabaseHelper'
import { CanvasBoardDao } from '../database/CanvasBoardDao'
import { CanvasCardDao } from '../database/CanvasCardDao'
import { CanvasEvidenceDao } from '../database/CanvasEvidenceDao'
import { CanvasPlacementDao } from '../database/CanvasPlacementDao'
import { CanvasLinkDao } from '../database/CanvasLinkDao'
import { IdGenerator } from '../utils/IdGenerator'
import { Logger } from '../utils/Logger'
import {
  CanvasBoardItem, CanvasCardItem, CanvasEvidenceItem, CanvasLinkItem, CanvasPlacementItem
} from '../model/CanvasStoreModels'
import type { CanvasBackupBundle, CanvasBackupLooseBundle, CanvasEvidenceInput } from '../model/CanvasStoreModels'
import { CanvasBoardScope, CanvasCardKind, CanvasEvidenceKind, CanvasLinkKind } from '../model/CanvasTypes'
import type {
  CanvasBoardData, CanvasCardData, CanvasEvidenceData, CanvasLinkData, CanvasPlacementData
} from '../model/CanvasTypes'
import { canvasFindPlacement, canvasRemovePlacement } from '../model/CanvasTypes'

export interface CanvasCardSnapshot {
  card: CanvasCardItem
  boardIds: string[]
  placements: CanvasPlacementItem[]
  evidence: CanvasEvidenceItem[]
  links: CanvasLinkItem[]
}

export class CanvasRepository {
  private boardDao: CanvasBoardDao
  private cardDao: CanvasCardDao
  private evidenceDao: CanvasEvidenceDao
  private placementDao: CanvasPlacementDao
  private linkDao: CanvasLinkDao
  /** 非 null = 本实例由事务创建，写操作落在该事务上（恢复/删卡片用）。 */
  private readonly boundTx: relationalStore.Transaction | null

  constructor(tx: relationalStore.Transaction | null = null) {
    this.boundTx = tx
    this.boardDao = new CanvasBoardDao(tx)
    this.cardDao = new CanvasCardDao(tx)
    this.evidenceDao = new CanvasEvidenceDao(tx)
    this.placementDao = new CanvasPlacementDao(tx)
    this.linkDao = new CanvasLinkDao(tx)
  }

  // ===== 白板 =====

  /**
   * 作用域内的白板：本项目的课程白板 + 全部自由白板（白板库要按类别分组）。
   * bookId 为空串（未归类项目）时返回全部白板。
   */
  async loadBoards(bookId: string): Promise<CanvasBoardItem[]> {
    if (bookId === '') {
      return this.boardDao.queryAllBoards()
    }
    const own: CanvasBoardItem[] = await this.boardDao.queryByBook(bookId)
    const free: CanvasBoardItem[] = await this.boardDao.queryFree()
    const all: CanvasBoardItem[] = own.concat(free)
    all.sort((a: CanvasBoardItem, b: CanvasBoardItem): number => a.sortOrder - b.sortOrder)
    return all
  }

  async loadAllBoards(): Promise<CanvasBoardItem[]> {
    return this.boardDao.queryAllBoards()
  }

  async createBoard(scope: CanvasBoardScope, bookId: string, title: string): Promise<CanvasBoardItem> {
    const siblings: CanvasBoardItem[] = await this.loadBoards(bookId)
    let nextOrder: number = 0
    for (let i: number = 0; i < siblings.length; i++) {
      if (siblings[i].sortOrder >= nextOrder) {
        nextOrder = siblings[i].sortOrder + 1
      }
    }
    const now: number = Date.now()
    const item: CanvasBoardItem = new CanvasBoardItem()
    item.id = IdGenerator.generate()
    item.scope = scope
    item.bookId = scope === CanvasBoardScope.COURSE ? bookId : ''
    item.title = title
    item.panX = 0
    item.panY = 0
    item.zoom = 1
    item.sortOrder = nextOrder
    item.createdAt = now
    item.updatedAt = now
    await this.boardDao.insert(item)
    return item
  }

  async saveViewport(boardId: string, panX: number, panY: number, zoom: number): Promise<void> {
    await this.boardDao.saveViewport(boardId, panX, panY, zoom)
  }

  // ===== 卡片 =====

  /** 全部卡片（卡片库与白板无关，一次全取）。 */
  async loadCards(): Promise<CanvasCardItem[]> {
    return this.cardDao.queryAllCards()
  }

  async loadCard(cardId: string): Promise<CanvasCardItem | null> {
    return this.cardDao.queryById(cardId)
  }

  async createCard(kind: CanvasCardKind, bookId: string, title: string): Promise<CanvasCardItem> {
    const now: number = Date.now()
    const item: CanvasCardItem = new CanvasCardItem()
    item.id = IdGenerator.generate()
    item.bookId = bookId
    item.kind = kind
    item.title = title
    item.aliases = ''
    item.tags = ''
    item.summary = ''
    item.docId = ''
    item.createdAt = now
    item.updatedAt = now
    await this.cardDao.insert(item)
    return item
  }

  /**
   * 删卡片：它在**每块**白板上的贴放都删掉，子项上提一层并散开位置；
   * 素材与连线一并清理。整组操作在一个事务里，任一步失败全部回滚
   * （否则可能出现「卡没了、贴放还在」的空卡位）。
   */
  /** 更新卡片自身内容（含生成的初稿 doc_id）。 */
  async updateCard(card: CanvasCardItem): Promise<void> {
    await this.cardDao.update(card)
  }

  /** 删卡前的完整快照：卡 + 受影响白板的全部贴放/连线 + 它的素材。撤销按原 id 写回。 */
  async snapshotCard(cardId: string): Promise<CanvasCardSnapshot | null> {
    const card: CanvasCardItem | null = await this.cardDao.queryById(cardId)
    if (card === null) {
      return null
    }
    const own: CanvasPlacementItem[] = await this.placementDao.queryByCard(cardId)
    const boardIds: string[] = []
    for (let i: number = 0; i < own.length; i++) {
      if (!boardIds.includes(own[i].canvasId)) {
        boardIds.push(own[i].canvasId)
      }
    }
    const placements: CanvasPlacementItem[] = boardIds.length === 0 ? [] :
      await this.placementDao.queryByBoards(boardIds)
    const evidence: CanvasEvidenceItem[] = await this.evidenceDao.queryByCard(cardId)
    const links: CanvasLinkItem[] = boardIds.length === 0 ? [] :
      await this.linkDao.queryByBoards(boardIds)
    return { card: card, boardIds: boardIds, placements: placements, evidence: evidence, links: links }
  }

  async restoreCardSnapshot(snapshot: CanvasCardSnapshot): Promise<void> {
    for (let i: number = 0; i < snapshot.boardIds.length; i++) {
      await this.placementDao.deleteByBoard(snapshot.boardIds[i])
      await this.linkDao.deleteByBoard(snapshot.boardIds[i])
    }
    await this.cardDao.insert(snapshot.card)
    for (let i: number = 0; i < snapshot.placements.length; i++) {
      await this.placementDao.insert(snapshot.placements[i])
    }
    for (let i: number = 0; i < snapshot.evidence.length; i++) {
      await this.evidenceDao.insert(snapshot.evidence[i])
    }
    for (let i: number = 0; i < snapshot.links.length; i++) {
      await this.linkDao.insert(snapshot.links[i])
    }
  }

  /** 移出白板前的快照：整块板的贴放（子项上提/ord 重写后要能原样恢复）。 */
  async snapshotBoardPlacements(boardId: string): Promise<CanvasPlacementItem[]> {
    return await this.placementDao.queryByBoard(boardId)
  }

  async restoreBoardPlacements(boardId: string, rows: CanvasPlacementItem[]): Promise<void> {
    await this.placementDao.deleteByBoard(boardId)
    for (let i: number = 0; i < rows.length; i++) {
      await this.placementDao.insert(rows[i])
    }
  }

  async deleteCard(cardId: string): Promise<void> {
    if (this.boundTx !== null) {
      await this.deleteCardRows(cardId)
      return
    }
    const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
    const scoped: CanvasRepository = new CanvasRepository(tx)
    try {
      await scoped.deleteCardRows(cardId)
      await tx.commit()
    } catch (e) {
      try {
        await tx.rollback()
      } catch (rollbackError) {
        Logger.error('Canvas deleteCard rollback failed: ' + String(rollbackError))
      }
      Logger.error('Canvas deleteCard failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  private async deleteCardRows(cardId: string): Promise<void> {
    const placedOn: CanvasPlacementItem[] = await this.placementDao.queryByCard(cardId)
    const boardIds: string[] = []
    for (let i: number = 0; i < placedOn.length; i++) {
      const boardId: string = placedOn[i].canvasId
      if (!boardIds.includes(boardId)) {
        boardIds.push(boardId)
      }
    }
    for (let i: number = 0; i < boardIds.length; i++) {
      await this.removePlacementFromBoard(boardIds[i], cardId)
    }
    await this.evidenceDao.deleteByCard(cardId)
    await this.linkDao.deleteByFrom(cardId)
    await this.linkDao.deleteByTo(cardId)
    await this.cardDao.delete(cardId)
  }

  /**
   * 单块白板内移除一个贴放（「从这块白板移除」/删卡片的单板步骤）：
   * 子项上提一层、散开位置、同级 ord 重写。
   */
  async removePlacementFromBoard(boardId: string, cardId: string): Promise<void> {
    const rows: CanvasPlacementItem[] = await this.toCardParents(
      await this.normalizeDuplicates(await this.placementDao.queryByBoard(boardId)))
    const doomed: CanvasPlacementData | undefined = canvasFindPlacement(rows, cardId)
    if (doomed === undefined) {
      return
    }
    const doomedId: string = doomed.id
    const kids: CanvasPlacementItem[] = rows.filter((p: CanvasPlacementItem): boolean => p.parentId === cardId)
    canvasRemovePlacement(rows, cardId)
    // 子项上提后若沿用原坐标会全叠在被删卡的位置上，按网格散开
    for (let i: number = 0; i < kids.length; i++) {
      kids[i].x = doomed.x + 40 * (i + 1)
      kids[i].y = doomed.y + 60 * (i + 1)
    }
    await this.placementDao.delete(doomedId)
    // 剩下的行里父字段是卡片 id，回写前换回贴放 id
    const placementOfCard: Map<string, string> = new Map<string, string>()
    for (let i: number = 0; i < rows.length; i++) {
      placementOfCard.set(rows[i].cardId, rows[i].id)
    }
    for (let i: number = 0; i < rows.length; i++) {
      const row: CanvasPlacementItem = rows[i]
      const parentCard: string = row.parentId
      let parentPlacementId: string = ''
      if (parentCard !== '') {
        const mapped: string | undefined = placementOfCard.get(parentCard)
        parentPlacementId = mapped === undefined ? '' : mapped
      }
      if (kids.includes(row)) {
        await this.placementDao.savePosition(row.id, row.x, row.y)
        await this.placementDao.saveStructure(row.id, parentPlacementId, row.order)
      } else {
        await this.placementDao.saveStructure(row.id, parentPlacementId, row.order)
      }
    }
  }

  /** 删项目时清掉它名下的白板与卡片（表间无级联外键，靠这里收尾）。 */
  async deleteBookScope(bookId: string): Promise<void> {
    if (bookId === '') {
      return
    }
    if (this.boundTx !== null) {
      await this.deleteBookScopeRows(bookId)
      return
    }
    const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
    const scoped: CanvasRepository = new CanvasRepository(tx)
    try {
      await scoped.deleteBookScopeRows(bookId)
      await tx.commit()
    } catch (e) {
      try {
        await tx.rollback()
      } catch (rollbackError) {
        Logger.error('Canvas deleteBookScope rollback failed: ' + String(rollbackError))
      }
      Logger.error('Canvas deleteBookScope failed: ' + String(e))
      throw new Error(String(e))
    }
  }

  private async deleteBookScopeRows(bookId: string): Promise<void> {
    const boards: CanvasBoardItem[] = await this.boardDao.queryByBook(bookId)
    for (let i: number = 0; i < boards.length; i++) {
      await this.placementDao.deleteByBoard(boards[i].id)
      await this.linkDao.deleteByBoard(boards[i].id)
      await this.boardDao.delete(boards[i].id)
    }
    const cards: CanvasCardItem[] = await this.cardDao.queryByBook(bookId)
    for (let i: number = 0; i < cards.length; i++) {
      await this.placementDao.deleteByCard(cards[i].id)
      await this.linkDao.deleteByFrom(cards[i].id)
      await this.linkDao.deleteByTo(cards[i].id)
      await this.evidenceDao.deleteByCard(cards[i].id)
      await this.cardDao.delete(cards[i].id)
    }
  }

  // ===== 贴放 =====

  /**
   * 读贴放。库里 parent_id 存的是**贴放 id**（契约 §4.2），但冻结的纯规则
   * （CanvasTypes.canvasChildren/canvasCanNest/canvasFlatten）按**卡片 id** 判父子。
   * 两边的语义只在仓储这一层转换，不让 UI 或 Store 记两套 id。
   */
  async loadPlacements(boardId: string): Promise<CanvasPlacementItem[]> {
    const rows: CanvasPlacementItem[] = await this.placementDao.queryByBoard(boardId)
    return this.toCardParents(await this.normalizeDuplicates(rows))
  }

  /** 一次取多块白板的贴放（Store 载入用；同一白板内的父子映射按整块板算）。 */
  async loadPlacementsForBoards(boardIds: string[]): Promise<CanvasPlacementItem[]> {
    const rows: CanvasPlacementItem[] = await this.placementDao.queryByBoards(boardIds)
    return this.toCardParents(await this.normalizeDuplicates(rows))
  }

  /**
   * 同一块白板里一张卡只应有一条贴放。历史并发/重复点击可能插入两条
   * （一条子卡、一条顶层），会让写作卡残留子卡行、移出只移掉其中一条。
   * 读侧收敛：优先保留有父的那条（子卡），其余从库里删掉；不同白板不受影响。
   */
  private hasChildIn(rows: CanvasPlacementItem[], placementId: string): boolean {
    for (let i: number = 0; i < rows.length; i++) {
      if (rows[i].parentId === placementId) {
        return true
      }
    }
    return false
  }

  private async normalizeDuplicates(rows: CanvasPlacementItem[]): Promise<CanvasPlacementItem[]> {
    const keep: CanvasPlacementItem[] = []
    const at: Map<string, number> = new Map<string, number>()
    for (let i: number = 0; i < rows.length; i++) {
      const row: CanvasPlacementItem = rows[i]
      const key: string = row.canvasId + '|' + row.cardId
      const slot: number | undefined = at.get(key)
      if (slot === undefined) {
        at.set(key, keep.length)
        keep.push(row)
        continue
      }
      const prev: CanvasPlacementItem = keep[slot]
      // 谁留谁删：优先留“有父的”（子卡），否则留“被别的行当父引用的”那条。
      // 只按先来后到会出现：留的那条没人引用、被删的那条才是子卡的父，
      // 子卡 parent 落空 → toCardParents 降级成顶层，写作卡里的行就消失了。
      const prevHasKids: boolean = this.hasChildIn(rows, prev.id)
      const rowHasKids: boolean = this.hasChildIn(rows, row.id)
      let winner: CanvasPlacementItem = prev
      let loser: CanvasPlacementItem = row
      if (prev.parentId === '' && row.parentId !== '') {
        winner = row
        loser = prev
      } else if (prev.parentId === '' && row.parentId === '' && !prevHasKids && rowHasKids) {
        winner = row
        loser = prev
      }
      // 被删那条的子卡，父引用改指保留的那条（内存 + 库）
      for (let j: number = 0; j < rows.length; j++) {
        if (rows[j].parentId === loser.id) {
          rows[j].parentId = winner.id
          await this.placementDao.saveStructure(rows[j].id, winner.id, rows[j].order)
          Logger.warn('Canvas: repointed child ' + rows[j].id + ' from ' + loser.id + ' to ' + winner.id)
        }
      }
      keep[slot] = winner
      at.set(key, slot)
      await this.placementDao.delete(loser.id)
      Logger.warn('Canvas: dropped duplicate placement ' + loser.id + ' (card ' + loser.cardId + ')')
    }
    return keep
  }

  /** 贴放 id → 卡片 id；找不到父项（跨板/已删）降级为顶层，避免留下断链的父子关系。 */
  private toCardParents(rows: CanvasPlacementItem[]): CanvasPlacementItem[] {
    const cardOfPlacement: Map<string, string> = new Map<string, string>()
    for (let i: number = 0; i < rows.length; i++) {
      cardOfPlacement.set(rows[i].id, rows[i].cardId)
    }
    for (let i: number = 0; i < rows.length; i++) {
      const rawParent: string = rows[i].parentId
      if (rawParent === '') {
        continue
      }
      const parentCard: string | undefined = cardOfPlacement.get(rawParent)
      rows[i].parentId = parentCard === undefined ? '' : parentCard
    }
    return rows
  }

  async insertPlacement(item: CanvasPlacementItem): Promise<void> {
    await this.placementDao.insert(item)
  }

  /** parentPlacementId 是**贴放 id**（库里的 parent_id），空串 = 顶层。 */
  async updateEvidenceText(evidenceId: string, quoteText: string, userText: string): Promise<void> {
    await this.evidenceDao.updateText(evidenceId, quoteText, userText)
  }

  /** 撤销删除素材：按原 id 写回（不生成新 id，避免撤销后引用变化）。 */
  async restoreEvidence(item: CanvasEvidenceItem): Promise<void> {
    await this.evidenceDao.insert(item)
  }

  async saveStructure(placementId: string, parentPlacementId: string, order: number): Promise<void> {
    await this.placementDao.saveStructure(placementId, parentPlacementId, order)
  }

  async savePosition(placementId: string, x: number, y: number): Promise<void> {
    await this.placementDao.savePosition(placementId, x, y)
  }

  /** 同级重排后 ord 整体写 0..n-1（只动 ord，不动 parent_id）。 */
  async saveOrders(items: CanvasPlacementItem[]): Promise<void> {
    for (let i: number = 0; i < items.length; i++) {
      await this.placementDao.saveOrder(items[i].id, items[i].order)
    }
  }

  // ===== 连线 =====

  async loadLinks(boardId: string): Promise<CanvasLinkItem[]> {
    return this.linkDao.queryByBoard(boardId)
  }

  async createLink(canvasId: string, fromCardId: string, toCardId: string,
    kind: CanvasLinkKind, label: string): Promise<CanvasLinkItem> {
    const item: CanvasLinkItem = new CanvasLinkItem()
    item.id = IdGenerator.generate()
    item.canvasId = canvasId
    item.fromCardId = fromCardId
    item.toCardId = toCardId
    item.kind = kind
    item.label = label
    item.createdAt = Date.now()
    await this.linkDao.insert(item)
    return item
  }

  async deleteLink(linkId: string): Promise<void> {
    await this.linkDao.delete(linkId)
  }

  // ===== 素材 =====

  async loadEvidenceForCards(cardIds: string[]): Promise<CanvasEvidenceItem[]> {
    return this.evidenceDao.queryByCards(cardIds)
  }

  async loadEvidence(cardId: string): Promise<CanvasEvidenceItem[]> {
    return this.evidenceDao.queryByCard(cardId)
  }

  async createEvidence(cardId: string, kind: CanvasEvidenceKind,
    input: CanvasEvidenceInput): Promise<CanvasEvidenceItem> {
    const item: CanvasEvidenceItem = new CanvasEvidenceItem()
    item.id = IdGenerator.generate()
    item.cardId = cardId
    item.kind = kind
    item.docId = input.docId
    item.paraIndex = input.paraIndex
    item.startOff = input.startOff
    item.endOff = input.endOff
    item.fingerprint = input.fingerprint
    item.quoteText = input.quoteText
    item.userText = input.userText
    item.sourceLabel = input.sourceLabel
    item.createdAt = Date.now()
    await this.evidenceDao.insert(item)
    return item
  }

  async deleteEvidence(evidenceId: string): Promise<void> {
    await this.evidenceDao.delete(evidenceId)
  }

  // ===== 备份 =====

  /**
   * 导出整本：本项目名下的白板、这些白板上的贴放与连线、这些卡片的素材，
   * 外加被贴到本板上的跨书卡片（否则恢复后出现空卡位）。
   */
  async exportBundle(bookId: string): Promise<CanvasBackupBundle> {
    const boards: CanvasBoardItem[] = await this.boardDao.queryByBook(bookId)
    const boardIds: string[] = []
    for (let i: number = 0; i < boards.length; i++) {
      boardIds.push(boards[i].id)
    }
    const ownCards: CanvasCardItem[] = await this.cardDao.queryByBook(bookId)
    const placements: CanvasPlacementItem[] = await this.placementDao.queryByBoards(boardIds)
    const links: CanvasLinkItem[] = await this.linkDao.queryByBoards(boardIds)
    const seen: Set<string> = new Set<string>()
    const cards: CanvasCardItem[] = []
    for (let i: number = 0; i < ownCards.length; i++) {
      seen.add(ownCards[i].id)
      cards.push(ownCards[i])
    }
    for (let i: number = 0; i < placements.length; i++) {
      const cardId: string = placements[i].cardId
      if (seen.has(cardId)) {
        continue
      }
      seen.add(cardId)
      const extra: CanvasCardItem | null = await this.cardDao.queryById(cardId)
      if (extra !== null) {
        cards.push(extra)
      }
    }
    const cardIds: string[] = []
    for (let i: number = 0; i < cards.length; i++) {
      cardIds.push(cards[i].id)
    }
    const evidence: CanvasEvidenceItem[] = await this.evidenceDao.queryByCards(cardIds)
    const topics: CanvasCardData[] = []
    for (let i: number = 0; i < cards.length; i++) {
      topics.push(this.plainCard(cards[i]))
    }
    const boardRows: CanvasBoardData[] = []
    for (let i: number = 0; i < boards.length; i++) {
      boardRows.push(this.plainBoard(boards[i]))
    }
    const placementRows: CanvasPlacementData[] = []
    for (let i: number = 0; i < placements.length; i++) {
      placementRows.push(this.plainPlacement(placements[i]))
    }
    const linkRows: CanvasLinkData[] = []
    for (let i: number = 0; i < links.length; i++) {
      linkRows.push(this.plainLink(links[i]))
    }
    const evidenceRows: CanvasEvidenceData[] = []
    for (let i: number = 0; i < evidence.length; i++) {
      evidenceRows.push(this.plainEvidence(evidence[i]))
    }
    const bundle: CanvasBackupBundle = {
      topics: topics,
      topicEvidence: evidenceRows,
      canvases: boardRows,
      canvasPlacements: placementRows,
      canvasLinks: linkRows
    }
    return bundle
  }

  /**
   * 恢复：全部重新生成 id，并按 topicIdMap / canvasIdMap / placementIdMap 重映射引用
   * （parent_id 必须指向新 placement，否则父子链会断在旧 id 上）。
   * 卡片与素材的 doc_id 走 chapterIdMap —— 章节也换了新 id，不重指向就会丢「跳回原文」。
   * 必须在调用方的事务里执行（AppStores.importBackupText 传的是事务绑定的实例）。
   */
  async restoreBundle(input: CanvasBackupLooseBundle, bookId: string,
    chapterIdMap: Map<string, string>): Promise<void> {
    const boardRows: CanvasBoardData[] = input.canvases ?? []
    const cardRows: CanvasCardData[] = input.topics ?? []
    const placementRows: CanvasPlacementData[] = input.canvasPlacements ?? []
    const linkRows: CanvasLinkData[] = input.canvasLinks ?? []
    const evidenceRows: CanvasEvidenceData[] = input.topicEvidence ?? []

    const canvasIdMap: Map<string, string> = new Map<string, string>()
    for (let i: number = 0; i < boardRows.length; i++) {
      const source: CanvasBoardData = boardRows[i]
      const item: CanvasBoardItem = new CanvasBoardItem()
      item.id = IdGenerator.generate()
      canvasIdMap.set(source.id, item.id)
      item.scope = source.scope === CanvasBoardScope.FREE ? CanvasBoardScope.FREE : CanvasBoardScope.COURSE
      item.bookId = bookId
      item.title = typeof source.title === 'string' && source.title.trim() !== '' ? source.title : '导入白板'
      item.panX = typeof source.panX === 'number' ? source.panX : 0
      item.panY = typeof source.panY === 'number' ? source.panY : 0
      item.zoom = typeof source.zoom === 'number' && source.zoom > 0 ? source.zoom : 1
      item.sortOrder = typeof source.sortOrder === 'number' ? source.sortOrder : i
      item.createdAt = typeof source.createdAt === 'number' ? source.createdAt : Date.now()
      item.updatedAt = typeof source.updatedAt === 'number' ? source.updatedAt : item.createdAt
      await this.boardDao.insert(item)
    }

    const topicIdMap: Map<string, string> = new Map<string, string>()
    for (let i: number = 0; i < cardRows.length; i++) {
      const source: CanvasCardData = cardRows[i]
      const item: CanvasCardItem = new CanvasCardItem()
      item.id = IdGenerator.generate()
      topicIdMap.set(source.id, item.id)
      item.bookId = bookId
      item.kind = source.kind === CanvasCardKind.WRITING ? CanvasCardKind.WRITING : CanvasCardKind.CONCEPT
      item.title = typeof source.title === 'string' && source.title.trim() !== '' ? source.title : '未命名卡片'
      item.aliases = typeof source.aliases === 'string' ? source.aliases : ''
      item.tags = typeof source.tags === 'string' ? source.tags : ''
      item.summary = typeof source.summary === 'string' ? source.summary : ''
      item.docId = this.remapDocId(source.docId, chapterIdMap)
      item.createdAt = typeof source.createdAt === 'number' ? source.createdAt : Date.now()
      item.updatedAt = typeof source.updatedAt === 'number' ? source.updatedAt : item.createdAt
      await this.cardDao.insert(item)
    }

    const placementIdMap: Map<string, string> = new Map<string, string>()
    for (let i: number = 0; i < placementRows.length; i++) {
      placementIdMap.set(placementRows[i].id, IdGenerator.generate())
    }
    for (let i: number = 0; i < placementRows.length; i++) {
      const source: CanvasPlacementData = placementRows[i]
      const newId: string | undefined = placementIdMap.get(source.id)
      const canvasId: string | undefined = canvasIdMap.get(source.canvasId)
      const cardId: string | undefined = topicIdMap.get(source.cardId)
      if (newId === undefined || canvasId === undefined || cardId === undefined) {
        continue
      }
      const oldParent: string = typeof source.parentId === 'string' ? source.parentId : ''
      let parentId: string = ''
      if (oldParent !== '') {
        const mapped: string | undefined = placementIdMap.get(oldParent)
        // 父项缺失时降级为顶层，宁可位置变，也不要留下指向不存在贴放的父子链
        parentId = mapped === undefined ? '' : mapped
      }
      const item: CanvasPlacementItem = new CanvasPlacementItem()
      item.id = newId
      item.canvasId = canvasId
      item.cardId = cardId
      item.parentId = parentId
      item.order = typeof source.order === 'number' ? source.order : 0
      item.x = typeof source.x === 'number' ? source.x : 0
      item.y = typeof source.y === 'number' ? source.y : 0
      item.z = typeof source.z === 'number' ? source.z : 0
      item.collapsed = source.collapsed === true
      item.style = typeof source.style === 'string' ? source.style : ''
      await this.placementDao.insert(item)
    }

    for (let i: number = 0; i < evidenceRows.length; i++) {
      const source: CanvasEvidenceData = evidenceRows[i]
      const cardId: string | undefined = topicIdMap.get(source.cardId)
      if (cardId === undefined) {
        continue
      }
      const item: CanvasEvidenceItem = new CanvasEvidenceItem()
      item.id = IdGenerator.generate()
      item.cardId = cardId
      item.kind = source.kind === CanvasEvidenceKind.QUOTE || source.kind === CanvasEvidenceKind.JUDGEMENT
        ? source.kind : CanvasEvidenceKind.NOTE
      item.docId = this.remapDocId(source.docId, chapterIdMap)
      item.paraIndex = typeof source.paraIndex === 'number' ? source.paraIndex : 0
      item.startOff = typeof source.startOff === 'number' ? source.startOff : 0
      item.endOff = typeof source.endOff === 'number' ? source.endOff : 0
      item.fingerprint = typeof source.fingerprint === 'string' ? source.fingerprint : ''
      item.quoteText = typeof source.quoteText === 'string' ? source.quoteText : ''
      item.userText = typeof source.userText === 'string' ? source.userText : ''
      item.sourceLabel = typeof source.sourceLabel === 'string' ? source.sourceLabel : ''
      item.createdAt = typeof source.createdAt === 'number' ? source.createdAt : Date.now()
      await this.evidenceDao.insert(item)
    }

    for (let i: number = 0; i < linkRows.length; i++) {
      const source: CanvasLinkData = linkRows[i]
      const canvasId: string | undefined = canvasIdMap.get(source.canvasId)
      const fromId: string | undefined = topicIdMap.get(source.fromCardId)
      const toId: string | undefined = topicIdMap.get(source.toCardId)
      if (canvasId === undefined || fromId === undefined || toId === undefined) {
        continue
      }
      const item: CanvasLinkItem = new CanvasLinkItem()
      item.id = IdGenerator.generate()
      item.canvasId = canvasId
      item.fromCardId = fromId
      item.toCardId = toId
      item.kind = source.kind
      item.label = typeof source.label === 'string' ? source.label : ''
      item.createdAt = typeof source.createdAt === 'number' ? source.createdAt : Date.now()
      await this.linkDao.insert(item)
    }
  }

  /** 旧文稿 id → 恢复时新建的文稿 id；找不到（超长被跳过）返回空串，交给 UI 显示失效。 */
  private remapDocId(docId: string, chapterIdMap: Map<string, string>): string {
    if (typeof docId !== 'string' || docId === '') {
      return ''
    }
    const mapped: string | undefined = chapterIdMap.get(docId)
    return mapped === undefined ? '' : mapped
  }

  // ===== 备份用纯数据副本（@ObservedV2 实例不直接进 JSON 载荷） =====

  private plainCard(item: CanvasCardItem): CanvasCardData {
    const data: CanvasCardData = {
      id: item.id, bookId: item.bookId, kind: item.kind, title: item.title,
      aliases: item.aliases, tags: item.tags, summary: item.summary, docId: item.docId,
      createdAt: item.createdAt, updatedAt: item.updatedAt
    }
    return data
  }

  private plainBoard(item: CanvasBoardItem): CanvasBoardData {
    const data: CanvasBoardData = {
      id: item.id, scope: item.scope, bookId: item.bookId, title: item.title,
      panX: item.panX, panY: item.panY, zoom: item.zoom, sortOrder: item.sortOrder,
      createdAt: item.createdAt, updatedAt: item.updatedAt
    }
    return data
  }

  private plainPlacement(item: CanvasPlacementItem): CanvasPlacementData {
    const data: CanvasPlacementData = {
      id: item.id, canvasId: item.canvasId, cardId: item.cardId, parentId: item.parentId,
      order: item.order, x: item.x, y: item.y, z: item.z,
      collapsed: item.collapsed, style: item.style
    }
    return data
  }

  private plainLink(item: CanvasLinkItem): CanvasLinkData {
    const data: CanvasLinkData = {
      id: item.id, canvasId: item.canvasId, fromCardId: item.fromCardId,
      toCardId: item.toCardId, kind: item.kind, label: item.label, createdAt: item.createdAt
    }
    return data
  }

  private plainEvidence(item: CanvasEvidenceItem): CanvasEvidenceData {
    const data: CanvasEvidenceData = {
      id: item.id, cardId: item.cardId, kind: item.kind, docId: item.docId,
      paraIndex: item.paraIndex, startOff: item.startOff, endOff: item.endOff,
      fingerprint: item.fingerprint, quoteText: item.quoteText, userText: item.userText,
      sourceLabel: item.sourceLabel, createdAt: item.createdAt
    }
    return data
  }
}
