// 思路板 Store（状态管理 V2）
//
// 分工：
// - 纯规则（编号/深度/嵌套/展开/重排）全部复用冻结文件 model/CanvasTypes.ets，本文件只做
//   「拿规则 → 改内存 → 落库 → 收错误」；
// - 所有写操作进同一条串行链（writeChain），避免同一贴放的并发 UPDATE 交错、
//   以及拖动连点造成的 parent/ord 覆盖；
// - 所有 async 方法内部消化异常（Logger 记录 + 写 error 给 UI 展示），绝不向组件抛未处理拒绝
//   —— 一次读库失败不该把整个应用按 JS 错误杀掉。
import { Logger } from '../utils/Logger'
import { IdGenerator } from '../utils/IdGenerator'
import {
  CanvasBoardScope, CanvasCardKind, CanvasEvidenceKind, CanvasLinkKind,
  canvasAttach, canvasAttachAt, canvasCanNest, canvasDepthOf, canvasFlatten, canvasNextOrder,
  canvasReorder
} from '../model/CanvasTypes'
import type { CanvasOutlineRow } from '../model/CanvasTypes'
import {
  CanvasBoardItem, CanvasCardItem, CanvasEvidenceItem, CanvasLinkItem, CanvasPlacementItem
} from '../model/CanvasStoreModels'
import type { CanvasCardPatch, CanvasEvidenceInput } from '../model/CanvasStoreModels'
import { canvasRepo } from './Repos'
import { CanvasSpec } from '../constants/CanvasSpec'
import type { CanvasCardSnapshot } from '../repository/CanvasRepository'

@ObservedV2
export class CanvasStore {
  @Trace boards: CanvasBoardItem[] = []
  @Trace cards: CanvasCardItem[] = []
  /** 当前白板的全部贴放（渲染与纯规则都读它） */
  @Trace placements: CanvasPlacementItem[] = []
  /** 同一张卡正在走上板流程时挡住重复点击（防插入两条贴放） */
  private addingCards: Set<string> = new Set<string>()
  private undoTimer: number = -1
  private undoAction: (() => Promise<void>) | null = null
  /** 作用域内**所有**白板的贴放（occurrences / 白板卡数；不要拿来渲染当前板） */
  @Trace allPlacements: CanvasPlacementItem[] = []
  @Trace links: CanvasLinkItem[] = []
  /** 作用域内全部卡片的素材（素材数、抽屉分组都读它，避免逐卡查询） */
  @Trace evidence: CanvasEvidenceItem[] = []
  @Trace currentBoardId: string = ''
  @Trace selectedCardId: string = ''
  /** 撤销条文案（空串 = 不显示）；目前用于删除素材 */
  @Trace undoLabel: string = ''
  @Trace panX: number = 0
  /** 画布视口尺寸（vp），CanvasPane 测量后写入；放卡/定位用 */
  @Trace viewportW: number = 0
  @Trace viewportH: number = 0
  @Trace panY: number = 0
  @Trace zoom: number = 1
  @Trace loading: boolean = false
  @Trace error: string = ''

  /** 当前项目 id；'' = 未作用域（只看到自由白板） */
  private scopeBookId: string = ''
  /** 与 RelationStore 同款：迟到的查询不得覆盖新的选择 */
  private loadRev: number = 0
  /** 写操作串行链（参考 EditorStore.flushChain）：链表自身吞掉拒绝，否则一次失败会卡死后续写 */
  private writeChain: Promise<void> = Promise.resolve()

  // ===== 作用域与载入 =====

  setBookScope(bookId: string): void {
    if (this.scopeBookId === bookId) {
      return
    }
    this.scopeBookId = bookId
    this.loadRev++
    this.boards = []
    this.cards = []
    this.placements = []
    this.allPlacements = []
    this.links = []
    this.evidence = []
    this.currentBoardId = ''
    this.selectedCardId = ''
    this.panX = 0
    this.panY = 0
    this.zoom = 1
    this.error = ''
  }

  /** 载入 boards + 全部 cards/evidence + 当前板 placements/links。失败不清空已加载内容。 */
  async load(): Promise<void> {
    const request: number = ++this.loadRev
    this.loading = true
    this.error = ''
    try {
      const bookId: string = this.scopeBookId
      const boards: CanvasBoardItem[] = await canvasRepo.loadBoards(bookId)
      if (request !== this.loadRev) {
        return
      }
      this.boards = boards
      const cards: CanvasCardItem[] = await canvasRepo.loadCards()
      if (request !== this.loadRev) {
        return
      }
      this.cards = cards
      const cardIds: string[] = cards.map((card: CanvasCardItem): string => card.id)
      const evidence: CanvasEvidenceItem[] = await canvasRepo.loadEvidenceForCards(cardIds)
      if (request !== this.loadRev) {
        return
      }
      this.evidence = evidence
      const boardId: string = this.pickBoardId(boards)
      this.currentBoardId = boardId
      const boardIds: string[] = boards.map((item: CanvasBoardItem): string => item.id)
      const all: CanvasPlacementItem[] = await canvasRepo.loadPlacementsForBoards(boardIds)
      if (request !== this.loadRev) {
        return
      }
      this.allPlacements = all
      this.placements = all.filter((p: CanvasPlacementItem): boolean => p.canvasId === boardId)
      this.applyViewport(this.boardById(boardId))
      if (boardId === '') {
        this.links = []
        return
      }
      const links: CanvasLinkItem[] = await canvasRepo.loadLinks(boardId)
      if (request !== this.loadRev || this.currentBoardId !== boardId) {
        return
      }
      this.links = links
    } catch (e) {
      this.fail('载入思路板失败：' + String(e))
    } finally {
      if (request === this.loadRev) {
        this.loading = false
      }
    }
  }

  async selectBoard(boardId: string): Promise<void> {
    if (this.currentBoardId === boardId) {
      return
    }
    const board: CanvasBoardItem | undefined = this.boardById(boardId)
    if (board === undefined) {
      this.error = '白板不存在'
      return
    }
    this.currentBoardId = boardId
    this.selectedCardId = ''
    this.placements = this.allPlacements.filter((p: CanvasPlacementItem): boolean => p.canvasId === boardId)
    this.applyViewport(board)
    const request: number = this.loadRev
    this.loading = true
    try {
      const links: CanvasLinkItem[] = await canvasRepo.loadLinks(boardId)
      if (request !== this.loadRev || this.currentBoardId !== boardId) {
        return
      }
      this.links = links
    } catch (e) {
      this.fail('切换白板失败：' + String(e))
    } finally {
      if (request === this.loadRev) {
        this.loading = false
      }
    }
  }

  // ===== 白板与卡片 =====

  async createBoard(scope: CanvasBoardScope, title: string): Promise<CanvasBoardItem | undefined> {
    const trimmed: string = title.trim()
    if (trimmed === '') {
      this.error = '白板名称不能为空'
      return undefined
    }
    const bookId: string = scope === CanvasBoardScope.COURSE ? this.scopeBookId : ''
    try {
      const created: CanvasBoardItem = await this.enqueue<CanvasBoardItem>(
        (): Promise<CanvasBoardItem> => canvasRepo.createBoard(scope, bookId, trimmed))
      this.boards = this.boards.concat([created])
      await this.selectBoard(created.id)
      return created
    } catch (e) {
      this.fail('新建白板失败：' + String(e))
      return undefined
    }
  }

  async createCard(kind: CanvasCardKind, title: string): Promise<CanvasCardItem | undefined> {
    const trimmed: string = title.trim()
    if (trimmed === '') {
      this.error = '卡片标题不能为空'
      return undefined
    }
    const bookId: string = this.scopeBookId
    try {
      const created: CanvasCardItem = await this.enqueue<CanvasCardItem>(
        (): Promise<CanvasCardItem> => canvasRepo.createCard(kind, bookId, trimmed))
      this.cards = this.cards.concat([created])
      return created
    } catch (e) {
      this.fail('新建卡片失败：' + String(e))
      return undefined
    }
  }

  /**
   * 删卡片：卡片在各块白板上的贴放都删掉、子卡上提（库层事务完成），
   * 内存里同步清掉卡片/素材/连线，再重拉贴放（跨板，逐条改内存容易漏）。
   */
  /** 记录写作卡生成的初稿 id（再次生成时用于提示；旧稿不删）。 */
  /** 复制一张卡（元信息一起复制；素材不复制，避免意外放大）。 */
  async duplicateCard(cardId: string): Promise<CanvasCardItem | undefined> {
    const src: CanvasCardItem | undefined = this.cardOf(cardId)
    if (src === undefined) {
      return undefined
    }
    const copy: CanvasCardItem | undefined = await this.createCard(src.kind, src.title + ' 副本')
    if (copy === undefined) {
      return undefined
    }
    await this.updateCard(copy.id, {
      aliases: src.aliases,
      tags: src.tags,
      summary: src.summary
    })
    const evidence: CanvasEvidenceItem[] = this.evidenceOf(cardId)
    for (let i: number = 0; i < evidence.length; i++) {
      const ev: CanvasEvidenceItem = evidence[i]
      await this.addEvidence(copy.id, ev.kind, {
        docId: ev.docId,
        paraIndex: ev.paraIndex,
        startOff: ev.startOff,
        endOff: ev.endOff,
        fingerprint: ev.fingerprint,
        quoteText: ev.quoteText,
        userText: ev.userText,
        sourceLabel: ev.sourceLabel
      })
    }
    return copy
  }

  /**
   * 写作卡内“加一章”：建概念卡 → 贴到板上 → 挂到父卡。
   * 任何一步失败都返回 false（卡若已建好会留在顶层，UI 可提示重试）。
   */
  async addChildCard(parentCardId: string, title: string, x: number, y: number): Promise<boolean> {
    const card: CanvasCardItem | undefined = await this.createCard(CanvasCardKind.CONCEPT, title)
    if (card === undefined) {
      return false
    }
    await this.addPlacement(card.id, x, y)
    if (this.placementOf(card.id) === undefined) {
      return false
    }
    return await this.attachCard(card.id, parentCardId)
  }

  /**
   * 更新卡片元信息（标题/别名/标签/一句话）。空标题拒绝；
   * 乐观更新内存，落库失败回滚并返回 false，UI 保留草稿让用户重试。
   */
  async updateCard(cardId: string, patch: CanvasCardPatch): Promise<boolean> {
    const card: CanvasCardItem | undefined = this.cardOf(cardId)
    if (card === undefined) {
      return false
    }
    const beforeTitle: string = card.title
    const beforeAliases: string = card.aliases
    const beforeTags: string = card.tags
    const beforeSummary: string = card.summary
    if (patch.title !== undefined) {
      const next: string = patch.title.trim()
      if (next === '') {
        return false
      }
      card.title = next
    }
    if (patch.aliases !== undefined) {
      card.aliases = patch.aliases.trim()
    }
    if (patch.tags !== undefined) {
      card.tags = patch.tags.trim()
    }
    if (patch.summary !== undefined) {
      card.summary = patch.summary.trim()
    }
    card.updatedAt = Date.now()
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.updateCard(card))
      return true
    } catch (e) {
      card.title = beforeTitle
      card.aliases = beforeAliases
      card.tags = beforeTags
      card.summary = beforeSummary
      this.fail('保存卡片失败：' + String(e))
      return false
    }
  }

  /** 更新素材正文（引文只改 quoteText，判断/笔记只改 userText），来源字段保留。 */
  async updateEvidenceText(evidenceId: string, quoteText: string, userText: string): Promise<boolean> {
    const item: CanvasEvidenceItem | undefined = this.evidence.find(
      (ev: CanvasEvidenceItem): boolean => ev.id === evidenceId)
    if (item === undefined) {
      return false
    }
    const beforeQuote: string = item.quoteText
    const beforeUser: string = item.userText
    item.quoteText = quoteText
    item.userText = userText
    try {
      await this.enqueue<void>((): Promise<void> =>
        canvasRepo.updateEvidenceText(evidenceId, quoteText, userText))
      return true
    } catch (e) {
      item.quoteText = beforeQuote
      item.userText = beforeUser
      this.fail('保存素材失败：' + String(e))
      return false
    }
  }

  /** 把某张卡移到当前视口中心（卡片库“定位”用）。 */
  focusCard(cardId: string): void {
    const pl: CanvasPlacementItem | undefined = this.placementOf(cardId)
    if (pl === undefined) {
      return
    }
    const z: number = this.zoom > 0 ? this.zoom : 1
    const w: number = this.viewportW > 0 ? this.viewportW : 800
    const h: number = this.viewportH > 0 ? this.viewportH : 600
    this.panX = w / 2 - (pl.x + CanvasSpec.CARD_WIDTH / 2) * z
    this.panY = h / 2 - (pl.y + 80) * z
  }

  async setCardDocId(cardId: string, docId: string): Promise<void> {
    const card: CanvasCardItem | undefined = this.cardOf(cardId)
    if (card === undefined) {
      return
    }
    card.docId = docId
    card.updatedAt = Date.now()
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.updateCard(card))
    } catch (e) {
      this.fail('setCardDocId failed: ' + String(e))
    }
  }

  async deleteCard(cardId: string): Promise<void> {
    let snapshot: CanvasCardSnapshot | null = null
    try {
      snapshot = await canvasRepo.snapshotCard(cardId)
    } catch (e) {
      Logger.warn('Canvas: snapshotCard failed, delete without undo: ' + String(e))
    }
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.deleteCard(cardId))
      this.cards = this.cards.filter((card: CanvasCardItem): boolean => card.id !== cardId)
      this.evidence = this.evidence.filter((item: CanvasEvidenceItem): boolean => item.cardId !== cardId)
      this.links = this.links.filter((item: CanvasLinkItem): boolean =>
        item.fromCardId !== cardId && item.toCardId !== cardId)
      if (this.selectedCardId === cardId) {
        this.selectedCardId = ''
      }
      await this.refreshPlacements()
      if (snapshot !== null) {
        const bundle: CanvasCardSnapshot = snapshot
        this.offerUndo('已删除卡片「' + bundle.card.title + '」', async (): Promise<void> => {
          await this.enqueue<void>((): Promise<void> => canvasRepo.restoreCardSnapshot(bundle))
          await this.load()
        })
      }
    } catch (e) {
      this.fail('删除卡片失败：' + String(e))
    }
  }

  // ===== 贴放 =====

  /** 把卡放到当前白板（已在板上则改为移到落点）。 */
  async addPlacement(cardId: string, x: number, y: number): Promise<void> {
    if (this.currentBoardId === '') {
      this.error = '请先选择一块白板'
      return
    }
    if (this.addingCards.has(cardId)) {
      return
    }
    this.addingCards.add(cardId)
    try {
      const existing: CanvasPlacementItem | undefined = this.placementOf(cardId)
      if (existing !== undefined) {
        await this.movePlacement(cardId, x, y)
        return
      }
      const boardId: string = this.currentBoardId
      const created: CanvasPlacementItem = await this.enqueue<CanvasPlacementItem>(
        (): Promise<CanvasPlacementItem> => this.insertPlacement(boardId, cardId, x, y))
      this.placements = this.placements.concat([created])
      this.allPlacements = this.allPlacements.concat([created])
    } catch (e) {
      this.fail('放入白板失败：' + String(e))
    } finally {
      this.addingCards.delete(cardId)
    }
  }

  private async insertPlacement(boardId: string, cardId: string, x: number,
    y: number): Promise<CanvasPlacementItem> {
    const item: CanvasPlacementItem = new CanvasPlacementItem()
    item.id = IdGenerator.generate()
    item.canvasId = boardId
    item.cardId = cardId
    item.parentId = ''
    item.order = canvasNextOrder(this.placements, '')
    item.x = x
    item.y = y
    item.z = this.nextZ()
    item.collapsed = false
    item.style = ''
    await canvasRepo.insertPlacement(item)
    return item
  }

  /**
   * 拖拽移动：内存立即生效（跟手），落库排队。
   * 不在 move 里改 parent/order —— 嵌套只走 attachCard/detachCard。
   */
  async movePlacement(cardId: string, x: number, y: number): Promise<void> {
    const item: CanvasPlacementItem | undefined = this.placementOf(cardId)
    if (item === undefined) {
      return
    }
    item.x = x
    item.y = y
    const placementId: string = item.id
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.savePosition(placementId, x, y))
    } catch (e) {
      this.fail('移动卡片失败：' + String(e))
    }
  }

  /**
   * 挂成子卡。深度/环/子树深度一律交给 canvasCanNest（冻结规则），
   * 放不进去返回 false（UI 据此不张嘴），不抛异常。
   */
  async attachCard(cardId: string, parentCardId: string): Promise<boolean> {
    return this.attachCardAt(cardId, parentCardId, -1)
  }

  /** index < 0 = 追加到末尾；否则按预览位置插入。 */
  async attachCardAt(cardId: string, parentCardId: string, index: number): Promise<boolean> {
    try {
      return await this.enqueue<boolean>((): Promise<boolean> =>
        this.doAttach(cardId, parentCardId, index))
    } catch (e) {
      this.fail('放入子卡失败：' + String(e))
      return false
    }
  }

  private async doAttach(cardId: string, parentCardId: string, index: number): Promise<boolean> {
    // 排队期间父子关系可能已变，落库前按最新状态再校验一次
    if (parentCardId === '' || !canvasCanNest(this.placements, cardId, parentCardId)) {
      return false
    }
    let item: CanvasPlacementItem | undefined = undefined
    let alreadyParent: boolean = false
    for (let i: number = 0; i < this.placements.length; i++) {
      const p: CanvasPlacementItem = this.placements[i]
      if (p.cardId === cardId && p.parentId === parentCardId) {
        alreadyParent = true
      }
      if (p.cardId === cardId && item === undefined) {
        item = p
      }
    }
    if (alreadyParent && index < 0) {
      return false
    }
    if (item === undefined) {
      return false
    }
    if (index >= 0) {
      canvasAttachAt(this.placements, cardId, parentCardId, index)
    } else {
      canvasAttach(this.placements, cardId, parentCardId)
    }
    // 内存里父字段是卡片 id（冻结纯规则的语义），库里 parent_id 存贴放 id —— 只在落库这一处换
    const parentPlacement: CanvasPlacementItem | undefined = this.placementOf(parentCardId)
    const parentPlacementId: string = parentPlacement === undefined ? '' : parentPlacement.id
    await canvasRepo.saveStructure(item.id, parentPlacementId, item.order)
    // 结构变更后强制重拉：父字段是 @Trace 字段，但 ForEach 的稳定 key 可能让子树复用旧 rows，
    // 重拉会换掉 placements 数组引用，写作卡的「N 章 / 子卡行」才会稳定更新。
    await this.refreshPlacements()
    Logger.info('Canvas: attached ' + cardId + ' under ' + parentCardId)
    return true
  }

  /** 移出子卡（变顶层卡），坐标不动。 */
  async detachCard(cardId: string): Promise<void> {
    try {
      await this.enqueue<void>((): Promise<void> => this.doDetach(cardId))
    } catch (e) {
      this.fail('移出子卡失败：' + String(e))
    }
  }

  private async doDetach(cardId: string): Promise<void> {
    // 必须找“有父的那条”：历史重复贴放里第一条可能是顶层，找错就会出现
    // 「点了移出、写作卡里仍有残留」。
    let item: CanvasPlacementItem | undefined = undefined
    for (let i: number = 0; i < this.placements.length; i++) {
      const p: CanvasPlacementItem = this.placements[i]
      if (p.cardId === cardId && p.parentId !== '') {
        item = p
        break
      }
    }
    if (item === undefined) {
      return
    }
    canvasAttach(this.placements, cardId, '')
    await canvasRepo.saveStructure(item.id, item.parentId, item.order)
    await this.refreshPlacements()
    Logger.info('Canvas: detached ' + cardId)
  }

  /** 同级上移/下移一位，并把同级 ord 整体重写 0..n-1。 */
  async reorderCard(cardId: string, delta: number): Promise<void> {
    if (delta === 0) {
      return
    }
    try {
      await this.enqueue<void>((): Promise<void> => this.doReorder(cardId, delta))
    } catch (e) {
      this.fail('调整顺序失败：' + String(e))
    }
  }

  private async doReorder(cardId: string, delta: number): Promise<void> {
    if (!canvasReorder(this.placements, cardId, delta)) {
      return
    }
    const item: CanvasPlacementItem | undefined = this.placementOf(cardId)
    if (item === undefined) {
      return
    }
    const siblings: CanvasPlacementItem[] = this.placements.filter(
      (p: CanvasPlacementItem): boolean => p.parentId === item.parentId)
    siblings.sort((a: CanvasPlacementItem, b: CanvasPlacementItem): number => a.order - b.order)
    for (let i: number = 0; i < siblings.length; i++) {
      siblings[i].order = i
    }
    await canvasRepo.saveOrders(siblings)
    // ord 是原地改的，换一次数组引用，避免渲染层认为顺序没变
    this.placements = this.placements.slice()
  }

  /** 相机落库（拖动/缩放结束后调一次）。 */
  async saveViewport(): Promise<void> {
    const board: CanvasBoardItem | undefined = this.boardById(this.currentBoardId)
    if (board === undefined) {
      return
    }
    const boardId: string = board.id
    const panX: number = this.panX
    const panY: number = this.panY
    const zoom: number = this.zoom
    board.panX = panX
    board.panY = panY
    board.zoom = zoom
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.saveViewport(boardId, panX, panY, zoom))
    } catch (e) {
      this.fail('保存画布视野失败：' + String(e))
    }
  }

  // ===== 素材 =====

  async addEvidence(cardId: string, kind: CanvasEvidenceKind, payload: CanvasEvidenceInput): Promise<void> {
    try {
      const created: CanvasEvidenceItem = await this.enqueue<CanvasEvidenceItem>(
        (): Promise<CanvasEvidenceItem> => canvasRepo.createEvidence(cardId, kind, payload))
      this.evidence = this.evidence.concat([created])
    } catch (e) {
      this.fail('添加素材失败：' + String(e))
    }
  }

  async deleteEvidence(evidenceId: string): Promise<void> {
    const item: CanvasEvidenceItem | undefined = this.evidence.find(
      (ev: CanvasEvidenceItem): boolean => ev.id === evidenceId)
    if (item === undefined) {
      return
    }
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.deleteEvidence(evidenceId))
      this.evidence = this.evidence.filter((ev: CanvasEvidenceItem): boolean => ev.id !== evidenceId)
      this.offerUndo('已删除素材', async (): Promise<void> => {
        await this.enqueue<void>((): Promise<void> => canvasRepo.restoreEvidence(item))
        this.evidence = this.evidence.concat([item])
      })
    } catch (e) {
      this.fail('删除素材失败：' + String(e))
    }
  }

  /** 5 秒撤销窗口；新操作覆盖旧操作。 */
  offerUndo(label: string, action: () => Promise<void>): void {
    this.clearUndo()
    this.undoLabel = label
    this.undoAction = action
    this.undoTimer = setTimeout(() => {
      this.undoTimer = -1
      this.undoAction = null
      this.undoLabel = ''
    }, 5000)
  }

  async performUndo(): Promise<void> {
    const action: (() => Promise<void>) | null = this.undoAction
    this.clearUndo()
    if (action === null) {
      return
    }
    try {
      await action()
      this.undoLabel = '已撤销'
      this.undoTimer = setTimeout(() => {
        this.undoTimer = -1
        this.undoLabel = ''
      }, 1600)
    } catch (e) {
      this.fail('撤销失败：' + String(e))
    }
  }

  private clearUndo(): void {
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer)
      this.undoTimer = -1
    }
    this.undoAction = null
    this.undoLabel = ''
  }

  // ===== 连线 =====

  async addLink(fromCardId: string, toCardId: string, kind: CanvasLinkKind, label: string): Promise<void> {
    if (this.currentBoardId === '') {
      this.error = '请先选择一块白板'
      return
    }
    if (fromCardId === toCardId) {
      this.error = '不能把卡片连到它自己'
      return
    }
    const boardId: string = this.currentBoardId
    try {
      const created: CanvasLinkItem = await this.enqueue<CanvasLinkItem>(
        (): Promise<CanvasLinkItem> => canvasRepo.createLink(boardId, fromCardId, toCardId, kind, label))
      this.links = this.links.concat([created])
    } catch (e) {
      this.fail('添加连线失败：' + String(e))
    }
  }

  async deleteLink(linkId: string): Promise<void> {
    try {
      await this.enqueue<void>((): Promise<void> => canvasRepo.deleteLink(linkId))
      this.links = this.links.filter((item: CanvasLinkItem): boolean => item.id !== linkId)
    } catch (e) {
      this.fail('删除连线失败：' + String(e))
    }
  }

  // ===== 同步查询（UI 直接用） =====

  /** 某个父贴放下的直接子项，按 order 升序（与 CanvasTypes.canvasChildren 等价）。 */
  childrenOf(parentCardId: string): CanvasPlacementItem[] {
    const out: CanvasPlacementItem[] = this.placements.filter(
      (p: CanvasPlacementItem): boolean => p.parentId === parentCardId)
    out.sort((a: CanvasPlacementItem, b: CanvasPlacementItem): number => a.order - b.order)
    return out
  }

  depthOf(cardId: string): number {
    return canvasDepthOf(this.placements, cardId)
  }

  cardOf(cardId: string): CanvasCardItem | undefined {
    return this.cards.find((card: CanvasCardItem): boolean => card.id === cardId)
  }

  /** 当前白板上的卡片，按大纲顺序（深度优先）返回。 */
  cardsOnBoard(): CanvasCardItem[] {
    const rows: CanvasOutlineRow[] = canvasFlatten(this.placements, '', 0)
    const out: CanvasCardItem[] = []
    for (let i: number = 0; i < rows.length; i++) {
      const card: CanvasCardItem | undefined = this.cardOf(rows[i].cardId)
      if (card !== undefined) {
        out.push(card)
      }
    }
    return out
  }

  /** 这张卡出现在哪几块白板（按白板标题，去重）；数据源是 allPlacements，对全部卡片都准。 */
  occurrences(cardId: string): string[] {
    const out: string[] = []
    for (let i: number = 0; i < this.allPlacements.length; i++) {
      const placement: CanvasPlacementItem = this.allPlacements[i]
      if (placement.cardId !== cardId) {
        continue
      }
      const board: CanvasBoardItem | undefined = this.boardById(placement.canvasId)
      if (board === undefined) {
        continue
      }
      if (!out.includes(board.title)) {
        out.push(board.title)
      }
    }
    return out
  }

  /** 某块白板上有多少张贴放（白板库的「卡数」）。 */
  boardCardCount(boardId: string): number {
    let count: number = 0
    for (let i: number = 0; i < this.allPlacements.length; i++) {
      if (this.allPlacements[i].canvasId === boardId) {
        count++
      }
    }
    return count
  }

  canNest(dragCardId: string, targetCardId: string): boolean {
    return canvasCanNest(this.placements, dragCardId, targetCardId)
  }

  /** 某张卡的素材，按加入时间升序。 */
  evidenceOf(cardId: string): CanvasEvidenceItem[] {
    const out: CanvasEvidenceItem[] = this.evidence.filter(
      (item: CanvasEvidenceItem): boolean => item.cardId === cardId)
    out.sort((a: CanvasEvidenceItem, b: CanvasEvidenceItem): number => a.createdAt - b.createdAt)
    return out
  }

  evidenceCountOf(cardId: string): number {
    let count: number = 0
    for (let i: number = 0; i < this.evidence.length; i++) {
      if (this.evidence[i].cardId === cardId) {
        count++
      }
    }
    return count
  }

  // ===== 生命周期 =====

  /** 应用退出/切换项目：清空内存并丢弃排队中的写结果。 */
  destroy(): void {
    this.loadRev++
    this.scopeBookId = ''
    this.boards = []
    this.cards = []
    this.placements = []
    this.allPlacements = []
    this.links = []
    this.evidence = []
    this.currentBoardId = ''
    this.selectedCardId = ''
    this.panX = 0
    this.panY = 0
    this.zoom = 1
    this.loading = false
    this.error = ''
    this.writeChain = Promise.resolve()
  }

  // ===== 内部 =====

  /**
   * 写操作串行化：每个任务挂在上一条之后执行。
   * 链表本身吞掉拒绝，否则一次失败会让后续所有写被跳过（EditorStore.flushChain 同款）。
   */
  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    const run: Promise<T> = this.writeChain.then(work)
    this.writeChain = run.then((): void => {}, (): void => {})
    return run
  }

  private fail(message: string): void {
    this.error = message
    Logger.error('CanvasStore ' + message)
  }

  /** 重拉作用域内全部贴放（跨板操作后用，避免逐条改内存漏项）。 */
  private async refreshPlacements(): Promise<void> {
    const boardIds: string[] = this.boards.map((item: CanvasBoardItem): string => item.id)
    if (boardIds.length === 0) {
      this.placements = []
      this.allPlacements = []
      return
    }
    const all: CanvasPlacementItem[] = await canvasRepo.loadPlacementsForBoards(boardIds)
    this.allPlacements = all
    this.placements = all.filter((p: CanvasPlacementItem): boolean => p.canvasId === this.currentBoardId)
  }

  private pickBoardId(boards: CanvasBoardItem[]): string {
    if (boards.length === 0) {
      return ''
    }
    for (let i: number = 0; i < boards.length; i++) {
      if (boards[i].id === this.currentBoardId) {
        return this.currentBoardId
      }
    }
    return boards[0].id
  }

  private applyViewport(board: CanvasBoardItem | undefined): void {
    if (board === undefined) {
      this.panX = 0
      this.panY = 0
      this.zoom = 1
      return
    }
    this.panX = board.panX
    this.panY = board.panY
    this.zoom = board.zoom > 0 ? board.zoom : 1
  }

  private boardById(boardId: string): CanvasBoardItem | undefined {
    return this.boards.find((item: CanvasBoardItem): boolean => item.id === boardId)
  }

  private placementOf(cardId: string): CanvasPlacementItem | undefined {
    return this.placements.find((item: CanvasPlacementItem): boolean => item.cardId === cardId)
  }

  private nextZ(): number {
    let max: number = 0
    for (let i: number = 0; i < this.placements.length; i++) {
      if (this.placements[i].z > max) {
        max = this.placements[i].z
      }
    }
    return max + 1
  }

  /** 供「写成初稿」按 ord 深度优先遍历（与画布展示同一套顺序）。 */
  outlineRows(): CanvasOutlineRow[] {
    return canvasFlatten(this.placements, '', 0)
  }

  /**
   * 「从这块白板移除」：只删当前板的贴放，卡片本身与其他白板不受影响；
   * 子项上提、同级重排、散开位置由仓储一次做完，然后整块重拉 ——
   * 内存用卡片 id、库里用贴放 id，这套转换不留在 Store 里手算。
   */
  async removePlacement(cardId: string): Promise<void> {
    const boardId: string = this.currentBoardId
    if (boardId === '') {
      return
    }
    let snapshot: CanvasPlacementItem[] = []
    try {
      snapshot = await canvasRepo.snapshotBoardPlacements(boardId)
    } catch (e) {
      Logger.warn('Canvas: snapshotBoardPlacements failed, remove without undo: ' + String(e))
    }
    try {
      await this.enqueue<void>((): Promise<void> =>
        canvasRepo.removePlacementFromBoard(boardId, cardId))
      await this.refreshPlacements()
      this.offerUndo('已从白板移除', async (): Promise<void> => {
        await this.enqueue<void>((): Promise<void> =>
          canvasRepo.restoreBoardPlacements(boardId, snapshot))
        await this.load()
      })
    } catch (e) {
      this.fail('从白板移除失败：' + String(e))
    }
  }
}
