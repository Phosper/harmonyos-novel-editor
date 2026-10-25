// 思路板 · 画布面板（全屏）
//
// 规格来源：docs/design/canvas-contract.md §2/§3/§5、AI 施工单 §6.1–§6.8。
//
// 状态划分（契约硬要求）：
// - 相机 panX/panY/zoom、选中卡 selectedCardId 一律走 app.canvas（@Trace）；
//   断点切换会重建组件，@Local 只放"拖动中"的瞬时量，重建后丢失也无所谓。
// - 世界坐标 → 屏幕：screen = world * zoom + pan；平移用 .translate()，
//   缩放不做容器 scale（会糊字），而是改 zoom 让卡片重新排位置与字号。
//
// 手势：卡片/行用 GestureGroup(Exclusive, Pan, Tap)；画布背景用 GestureGroup(Parallel, Pan, Pinch)。
// 所有增量都是「基准 + 累计」：base + offset、baseZoom * scale，绝不逐帧累加 delta。
import {
  CanvasCardData, CanvasEvidenceData, CanvasPlacementData, CanvasLinkData, CanvasCardKind,
  CanvasOutlineRow, canvasChildren, canvasFlatten, canvasFindPlacement, canvasIsAncestor
} from '../model/CanvasTypes'
import { CanvasSpec } from '../constants/CanvasSpec'
import { app, fireAndLog } from '../store/AppStores'
import { Logger } from '../utils/Logger'
import {
  canvasPalette, CanvasPalette, CanvasCardView, CanvasRowView, CanvasDragKind, CanvasHitResult,
  CanvasEdgeLine, CanvasRect, CanvasCardGeometry, CanvasLayout, canvasLinkLabel, canvasCardWidth
} from './CanvasTheme'
import { TopicCard } from './TopicCard'
import { CanvasEdges } from './CanvasEdges'
import { EvidenceDrawer } from './EvidenceDrawer'
import { CanvasDraftWriter } from '../editor/CanvasDraftWriter'
import type { CanvasDraftInput, CanvasDraftResult } from '../editor/CanvasDraftWriter'
import { chapterRepo } from '../store/Repos'
import { ChapterFormat, ChapterModel } from '../model/Chapter'
import type { CanvasCardItem } from '../model/CanvasStoreModels'
import { ensureWorkspace } from './Navigator'
import { closeCanvasAnimated } from './CanvasTransition'
import { startWindowMove, isDesktopWindow } from '../utils/WindowDrag'

/** 契约 §3 冻结签名：C（外壳）只按这个结构传参 */
export interface CanvasPaneParams {
  boardId: string
  onOpenCard: (cardId: string) => void
  onOpenBoardList: () => void
  onOpenCardLibrary: () => void
  /** 关闭思路板（全窗口页的 ✕）；由 CanvasDest 注入一镜到底的退出 */
  onClose: () => void
  /** 2in1 原生三键占位：顶栏右侧要避开 captionInset */
  captionInset: number
}

@ComponentV2
export struct CanvasPane {
  @Require @Param params: CanvasPaneParams

  // ===== 瞬时交互（@Local：重建即丢弃）=====
  @Local dragCardId: string = ''
  /** 拖动累计偏移（屏幕 vp，直接喂给卡片 translate） */
  @Local dragDx: number = 0
  @Local dragDy: number = 0
  /** 张嘴状态：同一目标不重复赋值，避免每帧重建节点 */
  @Local mouthOn: boolean = false
  @Local mouthCardId: string = ''
  @Local mouthInsert: number = 0
  @Local mouthDepth: number = 1
  /** 卡片测量几何（世界坐标高度 + 子卡区起点），用于行命中与连线端点 */
  @Local geos: CanvasCardGeometry[] = []
  @Local canvasW: number = 0
  @Local canvasH: number = 0
  /** 白板内快捷建卡：不离开画布，标题 + 类型即建即落 */
  @Local quickOpen: boolean = false
  @Local quickTitle: string = ''
  @Local quickKind: CanvasCardKind = CanvasCardKind.CONCEPT
  /** 生成初稿弹窗：卡片、是否带上写作卡自身素材 */
  @Local draftOpen: boolean = false
  @Local draftCardId: string = ''
  @Local includeOwnEvidence: boolean = false
  /** 卡片长按/右键菜单与重命名 */
  @Local cardMenuOpen: boolean = false
  @Local menuCardId: string = ''
  @Local renameOpen: boolean = false
  @Local renameCardId: string = ''
  @Local renameTitle: string = ''

  // ===== 非渲染状态（私有，不需要响应式）=====
  private mouthKey: string = ''
  private dragBaseWorldX: number = 0
  private dragBaseWorldY: number = 0
  private dragStartWinX: number = 0
  private dragStartWinY: number = 0
  private canvasOriginX: number = 0
  private canvasOriginY: number = 0
  private panBaseX: number = 0
  private panBaseY: number = 0
  private pinchBaseZoom: number = 1
  private pinchBasePanX: number = 0
  private pinchBasePanY: number = 0
  private dotsCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true))

  // ===================== 基础取值 =====================

  private pal(): CanvasPalette {
    return canvasPalette(app.ui.themeId)
  }

  private zoomValue(): number {
    const z: number = app.canvas.zoom
    return z > 0.01 ? z : 1
  }

  private boardTitle(): string {
    const id: string = app.canvas.currentBoardId
    for (let i: number = 0; i < app.canvas.boards.length; i++) {
      if (app.canvas.boards[i].id === id) {
        return app.canvas.boards[i].title
      }
    }
    return '思路板'
  }

  private boardSubtitle(): string {
    const n: number = app.canvas.cardsOnBoard().length
    return n.toString() + ' 张卡 · ' + Math.round(this.zoomValue() * 100).toString() + '%'
  }

  private isEmptyBoard(): boolean {
    return !app.canvas.loading && app.canvas.cardsOnBoard().length === 0
  }

  private topPlacements(): CanvasPlacementData[] {
    return canvasChildren(app.canvas.placements, '')
  }

  /** 顶层卡 → 渲染视图（卡被删时跳过，避免把 undefined 传给 @Require @Param） */
  private cardViews(): CanvasCardView[] {
    const tops: CanvasPlacementData[] = this.topPlacements()
    const out: CanvasCardView[] = []
    for (let i: number = 0; i < tops.length; i++) {
      const pl: CanvasPlacementData = tops[i]
      const c: CanvasCardData | undefined = app.canvas.cardOf(pl.cardId)
      if (c === undefined) {
        continue
      }
      out.push({
        card: c,
        placement: pl,
        rows: this.rowsOf(pl.cardId),
        materialCount: app.canvas.evidenceCountOf(pl.cardId)
      })
    }
    return out
  }

  /** 子卡行：深度优先 + 自动编号（编号来自冻结的 canvasFlatten） */
  private rowsOf(cardId: string): CanvasRowView[] {
    const rows: CanvasOutlineRow[] = canvasFlatten(app.canvas.placements, cardId, 1)
    const out: CanvasRowView[] = []
    for (let i: number = 0; i < rows.length; i++) {
      const r: CanvasOutlineRow = rows[i]
      const c: CanvasCardData | undefined = app.canvas.cardOf(r.cardId)
      if (c === undefined) {
        continue
      }
      out.push({
        cardId: r.cardId,
        placementId: r.placementId,
        depth: r.depth,
        index: r.index,
        numbering: r.numbering,
        title: c.title,
        isWriting: c.kind === CanvasCardKind.WRITING,
        materialCount: app.canvas.evidenceCountOf(r.cardId),
        hasChildren: canvasChildren(app.canvas.placements, r.cardId).length > 0
      })
    }
    return out
  }

  private screenX(worldX: number): number {
    return worldX * this.zoomValue() + app.canvas.panX
  }

  private screenY(worldY: number): number {
    return worldY * this.zoomValue() + app.canvas.panY
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  // ===================== 几何 =====================

  private geoOf(cardId: string): CanvasCardGeometry | undefined {
    for (let i: number = 0; i < this.geos.length; i++) {
      if (this.geos[i].cardId === cardId) {
        return this.geos[i]
      }
    }
    return undefined
  }

  /** 卡片世界矩形：宽度由规格决定，高度用测量值（首帧用兜底高度） */
  private cardRectOf(pl: CanvasPlacementData): CanvasRect {
    const c: CanvasCardData | undefined = app.canvas.cardOf(pl.cardId)
    const w: number = c === undefined ? CanvasSpec.CARD_WIDTH : canvasCardWidth(c.kind)
    const g: CanvasCardGeometry | undefined = this.geoOf(pl.cardId)
    const h: number = g === undefined ? CanvasLayout.FALLBACK_CARD_H : g.worldHeight
    return { x: pl.x, y: pl.y, w: w, h: h }
  }

  /** 子卡行世界矩形：行是固定行高的流式兄弟节点，可由子卡区起点推出 */
  private rowRectsOf(pl: CanvasPlacementData, rows: CanvasRowView[]): CanvasRect[] {
    const out: CanvasRect[] = []
    if (rows.length === 0) {
      return out
    }
    const g: CanvasCardGeometry | undefined = this.geoOf(pl.cardId)
    if (g === undefined) {
      return out
    }
    const c: CanvasCardData | undefined = app.canvas.cardOf(pl.cardId)
    const cardW: number = c === undefined ? CanvasSpec.CARD_WIDTH : canvasCardWidth(c.kind)
    for (let i: number = 0; i < rows.length; i++) {
      const level: number = rows[i].depth >= 1 ? rows[i].depth - 1 : 0
      out.push({
        x: pl.x + CanvasLayout.BODY_CONTENT_LEFT + level * CanvasSpec.INDENT,
        y: pl.y + g.bodyTop + CanvasLayout.ROW_GAP_TOP + i * CanvasSpec.ROW_HEIGHT,
        w: cardW - CanvasLayout.BODY_CONTENT_LEFT - level * CanvasSpec.INDENT - CanvasLayout.ROW_PAD_X,
        h: CanvasSpec.ROW_HEIGHT
      })
    }
    return out
  }

  /** 该卡（可能是嵌套卡）当前的世界矩形：嵌套卡用行矩形 */
  private rectOfCard(cardId: string): CanvasRect | undefined {
    const pl: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, cardId)
    if (pl === undefined) {
      return undefined
    }
    if (pl.parentId === '') {
      return this.cardRectOf(pl)
    }
    const tops: CanvasPlacementData[] = this.topPlacements()
    for (let t: number = 0; t < tops.length; t++) {
      const rows: CanvasRowView[] = this.rowsOf(tops[t].cardId)
      for (let r: number = 0; r < rows.length; r++) {
        if (rows[r].cardId === cardId) {
          const rects: CanvasRect[] = this.rowRectsOf(tops[t], rows)
          if (r < rects.length) {
            return rects[r]
          }
        }
      }
    }
    return undefined
  }

  /** 指针命中：行优先（外扩 8），其次卡片（外扩 30），最近者胜 */
  private hitTest(dragId: string, worldX: number, worldY: number): CanvasHitResult | undefined {
    const zoom: number = this.zoomValue()
    const inflateRow: number = CanvasSpec.ROW_INFLATE / zoom
    const inflateCard: number = CanvasSpec.MOUTH_INFLATE / zoom
    const tops: CanvasPlacementData[] = this.topPlacements()
    let bestRow: CanvasHitResult | undefined = undefined
    let bestRowDist: number = 0
    let bestCard: CanvasHitResult | undefined = undefined
    let bestCardDist: number = 0
    for (let i: number = 0; i < tops.length; i++) {
      const pl: CanvasPlacementData = tops[i]
      const rows: CanvasRowView[] = this.rowsOf(pl.cardId)
      const rects: CanvasRect[] = this.rowRectsOf(pl, rows)
      for (let r: number = 0; r < rows.length && r < rects.length; r++) {
        const rc: CanvasRect = rects[r]
        if (worldX < rc.x - inflateRow || worldX > rc.x + rc.w + inflateRow) {
          continue
        }
        if (worldY < rc.y - inflateRow || worldY > rc.y + rc.h + inflateRow) {
          continue
        }
        const dist: number = Math.abs(worldY - (rc.y + rc.h / 2))
        if (bestRow === undefined || dist < bestRowDist) {
          bestRowDist = dist
          const parentCard: string = this.parentOf(rows[r].cardId)
          const rel: number = rc.h > 1 ? (worldY - rc.y) / rc.h : 0.5
          if (rel < 0.28 || rel > 0.72) {
            // 行的上下边缘：插到该行前/后（同级），不改变层级
            const after: boolean = rel > 0.72
            bestRow = {
              cardId: parentCard,
              rowCardId: rows[r].cardId,
              insertIndex: this.siblingIndex(parentCard, rows[r].cardId) + (after ? 1 : 0),
              previewIndex: after ? this.subtreeEndIndex(rows, r) : r,
              depth: rows[r].depth,
              isRow: true
            }
          } else {
            // 行的中间：挂成该行的子卡（保留章→节→目的拖拽嵌套）
            const kids: CanvasPlacementData[] = canvasChildren(app.canvas.placements, rows[r].cardId)
            bestRow = {
              cardId: rows[r].cardId,
              rowCardId: rows[r].cardId,
              insertIndex: kids.length,
              previewIndex: this.subtreeEndIndex(rows, r),
              depth: rows[r].depth + 1,
              isRow: true
            }
          }
        }
      }
      const cr: CanvasRect = this.cardRectOf(pl)
      if (worldX < cr.x - inflateCard || worldX > cr.x + cr.w + inflateCard) {
        continue
      }
      if (worldY < cr.y - inflateCard || worldY > cr.y + cr.h + inflateCard) {
        continue
      }
      const dx: number = worldX - (cr.x + cr.w / 2)
      const dy: number = worldY - (cr.y + cr.h / 2)
      const d: number = Math.sqrt(dx * dx + dy * dy)
      if (bestCard === undefined || d < bestCardDist) {
        bestCardDist = d
        bestCard = {
          cardId: pl.cardId,
          rowCardId: '',
          insertIndex: rows.length,
          previewIndex: rows.length,
          depth: 1,
          isRow: false
        }
      }
    }
    if (bestRow !== undefined && this.peekCanNest(dragId, bestRow.cardId, true)) {
      return bestRow
    }
    if (bestCard !== undefined && this.peekCanNest(dragId, bestCard.cardId, false)) {
      return bestCard
    }
    return undefined
  }

  /** 是否可放：自己 / 当前父卡 / 子孙 / 深度超限 一律不张嘴 */
  private peekCanNest(dragId: string, targetCardId: string, allowSameParent: boolean): boolean {
    if (dragId === '' || dragId === targetCardId) {
      return false
    }
    if (!allowSameParent && targetCardId === this.parentOf(dragId)) {
      return false
    }
    return app.canvas.canNest(dragId, targetCardId)
  }

  /** 行 i 的子树结束位置（其后第一条不更深的行为止），缺口就插在这里 */
  private subtreeEndIndex(rows: CanvasRowView[], i: number): number {
    let j: number = i + 1
    while (j < rows.length && rows[j].depth > rows[i].depth) {
      j++
    }
    return j
  }

  private siblingIndex(parentCardId: string, cardId: string): number {
    const kids: CanvasPlacementData[] = canvasChildren(app.canvas.placements, parentCardId)
    for (let i: number = 0; i < kids.length; i++) {
      if (kids[i].cardId === cardId) {
        return i
      }
    }
    return kids.length
  }

  private parentOf(cardId: string): string {
    const pl: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, cardId)
    return pl === undefined ? '' : pl.parentId
  }

  private noteGeometry(cardId: string, heightScreen: number, bodyTopScreen: number): void {
    const zoom: number = this.zoomValue()
    const hWorld: number = heightScreen / zoom
    const bodyWorld: number = (CanvasLayout.CARD_PAD + bodyTopScreen) / zoom
    const list: CanvasCardGeometry[] = this.geos.slice()
    let found: number = -1
    for (let i: number = 0; i < list.length; i++) {
      if (list[i].cardId === cardId) {
        found = i
      }
    }
    if (found >= 0) {
      const old: CanvasCardGeometry = list[found]
      if (Math.abs(old.worldHeight - hWorld) < 0.5 && Math.abs(old.bodyTop - bodyWorld) < 0.5) {
        return
      }
      list[found] = { cardId: cardId, worldHeight: hWorld, bodyTop: bodyWorld }
    } else {
      list.push({ cardId: cardId, worldHeight: hWorld, bodyTop: bodyWorld })
    }
    this.geos = list
  }

  // ===================== 连线 =====================

  private fmt(n: number): string {
    return (Math.round(n * 10) / 10).toString()
  }

  /** 矩形边缘上朝向 toward 点的锚点（取中心射线与边框的交点） */
  private anchorX(rect: CanvasRect, towardX: number, towardY: number): number {
    const cx: number = rect.x + rect.w / 2
    const cy: number = rect.y + rect.h / 2
    const dx: number = towardX - cx
    const dy: number = towardY - cy
    if (dx === 0 && dy === 0) {
      return cx
    }
    const sx: number = Math.abs(dx) < 0.0001 ? Number.MAX_VALUE : (rect.w / 2) / Math.abs(dx)
    const sy: number = Math.abs(dy) < 0.0001 ? Number.MAX_VALUE : (rect.h / 2) / Math.abs(dy)
    const s: number = Math.min(sx, sy)
    return cx + dx * s
  }

  private anchorY(rect: CanvasRect, towardX: number, towardY: number): number {
    const cx: number = rect.x + rect.w / 2
    const cy: number = rect.y + rect.h / 2
    const dx: number = towardX - cx
    const dy: number = towardY - cy
    if (dx === 0 && dy === 0) {
      return cy
    }
    const sx: number = Math.abs(dx) < 0.0001 ? Number.MAX_VALUE : (rect.w / 2) / Math.abs(dx)
    const sy: number = Math.abs(dy) < 0.0001 ? Number.MAX_VALUE : (rect.h / 2) / Math.abs(dy)
    const s: number = Math.min(sx, sy)
    return cy + dy * s
  }

  private screenRect(r: CanvasRect): CanvasRect {
    const zoom: number = this.zoomValue()
    return {
      x: r.x * zoom + app.canvas.panX,
      y: r.y * zoom + app.canvas.panY,
      w: r.w * zoom,
      h: r.h * zoom
    }
  }

  private edgeLines(): CanvasEdgeLine[] {
    const out: CanvasEdgeLine[] = []
    const links: CanvasLinkData[] = app.canvas.links
    if (links.length === 0) {
      return out
    }
    const worldRects: Map<string, CanvasRect> = new Map<string, CanvasRect>()
    const tops: CanvasPlacementData[] = this.topPlacements()
    for (let t: number = 0; t < tops.length; t++) {
      const pl: CanvasPlacementData = tops[t]
      worldRects.set(pl.cardId, this.cardRectOf(pl))
      const rows: CanvasRowView[] = this.rowsOf(pl.cardId)
      const rects: CanvasRect[] = this.rowRectsOf(pl, rows)
      for (let r: number = 0; r < rows.length; r++) {
        if (r < rects.length) {
          worldRects.set(rows[r].cardId, rects[r])
        }
      }
    }
    for (let i: number = 0; i < links.length; i++) {
      const link: CanvasLinkData = links[i]
      const fromWorld: CanvasRect | undefined = worldRects.get(link.fromCardId)
      const toWorld: CanvasRect | undefined = worldRects.get(link.toCardId)
      if (fromWorld === undefined || toWorld === undefined) {
        continue
      }
      const a: CanvasRect = this.screenRect(fromWorld)
      const b: CanvasRect = this.screenRect(toWorld)
      const acx: number = a.x + a.w / 2
      const acy: number = a.y + a.h / 2
      const bcx: number = b.x + b.w / 2
      const bcy: number = b.y + b.h / 2
      const p1x: number = this.anchorX(a, bcx, bcy)
      const p1y: number = this.anchorY(a, bcx, bcy)
      const p2x: number = this.anchorX(b, acx, acy)
      const p2y: number = this.anchorY(b, acx, acy)
      const mx: number = (p1x + p2x) / 2
      const my: number = (p1y + p2y) / 2
      const dx: number = p2x - p1x
      const dy: number = p2y - p1y
      const len: number = Math.sqrt(dx * dx + dy * dy)
      const safeLen: number = len < 0.001 ? 1 : len
      const nx: number = -dy / safeLen
      const ny: number = dx / safeLen
      const bow: number = Math.min(CanvasLayout.EDGE_BOW_MAX, len * 0.18)
      const c1x: number = mx + nx * bow
      const c1y: number = my + ny * bow
      const ang: number = Math.atan2(p2y - c1y, p2x - c1x)
      const ah: number = 8
      const labelText: string = link.label !== '' ? link.label : canvasLinkLabel(link.kind)
      const labelX: number = mx + nx * bow * 0.55
      const labelY: number = my + ny * bow * 0.55
      out.push({
        linkId: link.id,
        commands: 'M' + this.fmt(p1x) + ' ' + this.fmt(p1y) +
          ' C' + this.fmt(c1x) + ' ' + this.fmt(c1y) + ' ' + this.fmt(c1x) + ' ' + this.fmt(c1y) +
          ' ' + this.fmt(p2x) + ' ' + this.fmt(p2y) +
          ' M' + this.fmt(p2x - ah * Math.cos(ang - 0.42)) + ' ' + this.fmt(p2y - ah * Math.sin(ang - 0.42)) +
          ' L' + this.fmt(p2x) + ' ' + this.fmt(p2y) +
          ' L' + this.fmt(p2x - ah * Math.cos(ang + 0.42)) + ' ' + this.fmt(p2y - ah * Math.sin(ang + 0.42)),
        label: labelText,
        labelX: labelX,
        labelY: labelY,
        labelWidth: labelText.length * 11 + 14,
        dashed: false
      })
    }
    return out
  }

  // ===================== 拖动 =====================

  private onCardOpen(cardId: string): void {
    app.canvas.selectedCardId = cardId
    this.params.onOpenCard(cardId)
  }

  private closeDrawer(): void {
    app.canvas.selectedCardId = ''
  }

  private onCardDragStart(cardId: string, kind: CanvasDragKind, winX: number, winY: number): void {
    const pl: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, cardId)
    if (pl === undefined) {
      return
    }
    this.dragCardId = cardId
    this.dragDx = 0
    this.dragDy = 0
    this.dragBaseWorldX = pl.x
    this.dragBaseWorldY = pl.y
    this.dragStartWinX = winX
    this.dragStartWinY = winY
  }

  /** 当前指针的世界坐标 = （按下点 + 累计偏移 - 画布原点 - pan）/ zoom */
  private pointerWorldX(dx: number): number {
    return (this.dragStartWinX + dx - this.canvasOriginX - app.canvas.panX) / this.zoomValue()
  }

  private pointerWorldY(dy: number): number {
    return (this.dragStartWinY + dy - this.canvasOriginY - app.canvas.panY) / this.zoomValue()
  }

  private onDragFrame(cardId: string, kind: CanvasDragKind, dx: number, dy: number,
    winX: number, winY: number): void {
    this.dragDx = dx
    this.dragDy = dy
    const target: CanvasHitResult | undefined =
      this.hitTest(cardId, this.pointerWorldX(dx), this.pointerWorldY(dy))
    const key: string = target === undefined
      ? ''
      : target.cardId + '#' + target.insertIndex.toString() + '#' +
        target.previewIndex.toString() + '#' + target.depth.toString()
    if (key === this.mouthKey) {
      return
    }
    this.mouthKey = key
    if (target === undefined) {
      this.mouthOn = false
      this.mouthCardId = ''
      return
    }
    this.mouthCardId = target.cardId
    this.mouthInsert = target.previewIndex
    this.mouthDepth = target.depth
    this.mouthOn = true
  }

  private resetDrag(): void {
    this.dragCardId = ''
    this.dragDx = 0
    this.dragDy = 0
    this.mouthKey = ''
    this.mouthOn = false
    this.mouthCardId = ''
  }

  private onDragFinish(cardId: string, kind: CanvasDragKind, dx: number, dy: number,
    winX: number, winY: number): void {
    const wx: number = this.pointerWorldX(dx)
    const wy: number = this.pointerWorldY(dy)
    const currentParent: string = this.parentOf(cardId)
    const target: CanvasHitResult | undefined = this.hitTest(cardId, wx, wy)
    const inside: boolean = this.pointerInsideCanvas(winX, winY)
    if (target !== undefined) {
      const title: string = this.titleOf(target.cardId)
      const sameParent: boolean = target.cardId === currentParent
      if (sameParent && !target.isRow) {
        // 拖回当前父卡本体：不改父级，也不重排
        this.resetDrag()
        return
      }
      app.canvas.attachCardAt(cardId, target.cardId, target.insertIndex).then((ok: boolean) => {
        if (ok) {
          this.toast(sameParent ? '已调整顺序' : '已放进「' + title + '」')
        } else {
          this.toast(sameParent ? '顺序调整失败' : '这张卡放不进「' + title + '」')
        }
      }).catch((e: Error) => {
        Logger.error('CanvasPane.attachCard failed: ' + String(e))
      })
    } else if (kind === CanvasDragKind.ROW) {
      if (this.isOverParentCard(currentParent, wx, wy)) {
        // 行拖到父卡本体：不改变结构，也不误移出
        this.resetDrag()
        return
      }
      if (inside) {
        fireAndLog(this.detachAtPointer(cardId, wx, wy), 'CanvasPane.detachAtPointer')
        this.toast('已移出，成为画布上的独立卡片')
      } else {
        this.explainReject(cardId, wx, wy)
      }
    } else if (inside) {
      const toX: number = this.dragBaseWorldX + dx / this.zoomValue()
      const toY: number = this.dragBaseWorldY + dy / this.zoomValue()
      fireAndLog(app.canvas.movePlacement(cardId, toX, toY), 'CanvasPane.movePlacement')
      this.explainReject(cardId, wx, wy)
    } else {
      this.explainReject(cardId, wx, wy)
    }
    this.resetDrag()
  }

  private async detachAndPlace(cardId: string, worldX: number, worldY: number): Promise<void> {
    await app.canvas.detachCard(cardId)
    await app.canvas.movePlacement(cardId, worldX, worldY)
  }

  /** 拖行到空白：落点对齐指针（卡片左上角略偏左上，避免正压在指针下） */
  private async detachAtPointer(cardId: string, worldX: number, worldY: number): Promise<void> {
    await app.canvas.detachCard(cardId)
    await app.canvas.movePlacement(cardId, worldX - CanvasSpec.CARD_WIDTH / 2, worldY - 20)
  }

  /** 行拖动时，指针是否落在当前父卡本体（不含行区）——用于避免误移出。 */
  private isOverParentCard(parentId: string, worldX: number, worldY: number): boolean {
    if (parentId === '') {
      return false
    }
    const rect: CanvasRect | undefined = this.rectOfCard(parentId)
    if (rect === undefined) {
      return false
    }
    const inflate: number = CanvasSpec.MOUTH_INFLATE / this.zoomValue()
    return worldX >= rect.x - inflate && worldX <= rect.x + rect.w + inflate &&
      worldY >= rect.y - inflate && worldY <= rect.y + rect.h + inflate
  }

  private titleOf(cardId: string): string {
    const c: CanvasCardData | undefined = app.canvas.cardOf(cardId)
    return c === undefined ? '' : c.title
  }

  private pointerInsideCanvas(winX: number, winY: number): boolean {
    return winX >= this.canvasOriginX && winY >= this.canvasOriginY &&
      winX <= this.canvasOriginX + this.canvasW && winY <= this.canvasOriginY + this.canvasH
  }

  /** 没有张嘴就松手时给一句解释（拖回父卡/环/超深），避免"什么都没发生" */
  private explainReject(cardId: string, worldX: number, worldY: number): void {
    const raw: CanvasHitResult | undefined = this.rawNearest(cardId, worldX, worldY)
    if (raw === undefined) {
      return
    }
    if (raw.cardId === this.parentOf(cardId)) {
      this.toast('已经在这张卡里了')
      return
    }
    if (canvasIsAncestor(app.canvas.placements, cardId, raw.cardId)) {
      this.toast('不能把卡塞进它自己里面')
      return
    }
    this.toast('最多三层（章 / 节 / 目），再深建议拆成独立写作卡')
  }

  /** 只做几何最近命中，不判 canNest —— 给拒绝原因用 */
  private rawNearest(cardId: string, worldX: number, worldY: number): CanvasHitResult | undefined {
    const tops: CanvasPlacementData[] = this.topPlacements()
    for (let i: number = 0; i < tops.length; i++) {
      if (tops[i].cardId === cardId) {
        continue
      }
      const cr: CanvasRect = this.cardRectOf(tops[i])
      const zoom: number = this.zoomValue()
      const inflate: number = CanvasSpec.MOUTH_INFLATE / zoom
      if (worldX >= cr.x - inflate && worldX <= cr.x + cr.w + inflate &&
        worldY >= cr.y - inflate && worldY <= cr.y + cr.h + inflate) {
        const rows: CanvasRowView[] = this.rowsOf(tops[i].cardId)
        return {
          cardId: tops[i].cardId,
          rowCardId: '',
          insertIndex: rows.length,
          previewIndex: rows.length,
          depth: 1,
          isRow: false
        }
      }
    }
    return undefined
  }

  /** 行尾 ↗：从父卡移出，落在父卡右侧（世界坐标） */
  private rowOut(cardId: string): void {
    const pl: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, cardId)
    if (pl === undefined) {
      return
    }
    const parent: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, pl.parentId)
    const wx: number = parent === undefined ? 120 : parent.x + CanvasSpec.WRITING_WIDTH + 40
    const wy: number = parent === undefined ? 120 : parent.y + 40
    fireAndLog(this.detachAndPlace(cardId, wx, wy), 'CanvasPane.rowOut')
    this.toast('已移出，成为画布上的独立卡片')
  }

  private onDragCancel(): void {
    this.resetDrag()
  }

  // ===================== 相机 =====================

  private applyZoom(next: number): void {
    const clamped: number = Math.min(CanvasSpec.MAX_ZOOM, Math.max(CanvasSpec.MIN_ZOOM, next))
    const current: number = this.zoomValue()
    if (Math.abs(clamped - current) < 0.001) {
      return
    }
    const cx: number = this.canvasW / 2
    const cy: number = this.canvasH / 2
    app.canvas.panX = cx - (cx - app.canvas.panX) * (clamped / current)
    app.canvas.panY = cy - (cy - app.canvas.panY) * (clamped / current)
    app.canvas.zoom = clamped
    fireAndLog(app.canvas.saveViewport(), 'CanvasPane.saveViewport')
  }

  private resetZoom(): void {
    app.canvas.zoom = 1
    fireAndLog(app.canvas.saveViewport(), 'CanvasPane.saveViewport')
  }

  // ===================== 点阵背景 =====================

  private dotShiftX(): number {
    const gap: number = CanvasSpec.DOT_GAP
    let m: number = app.canvas.panX % gap
    if (m > 0) {
      m = m - gap
    }
    return m
  }

  private dotShiftY(): number {
    const gap: number = CanvasSpec.DOT_GAP
    let m: number = app.canvas.panY % gap
    if (m > 0) {
      m = m - gap
    }
    return m
  }

  private drawDots(): void {
    const w: number = this.canvasW + CanvasSpec.DOT_GAP
    const h: number = this.canvasH + CanvasSpec.DOT_GAP
    if (w <= 0 || h <= 0) {
      return
    }
    const ctx: CanvasRenderingContext2D = this.dotsCtx
    ctx.clearRect(0, 0, w, h)
    ctx.fillStyle = this.pal().dot
    const gap: number = CanvasSpec.DOT_GAP
    for (let x: number = gap; x < w; x += gap) {
      for (let y: number = gap; y < h; y += gap) {
        ctx.beginPath()
        ctx.arc(x, y, 1, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }

  // ===================== 写成初稿（D 的生成器接在这里） =====================

  /** 点「写成初稿」先弹选项：新建/覆盖 + 是否带上写作卡自己的素材。 */
  private async writeDraft(cardId: string): Promise<void> {
    const card: CanvasCardData | undefined = app.canvas.cardOf(cardId)
    if (card === undefined) {
      return
    }
    const rows: CanvasOutlineRow[] = canvasFlatten(app.canvas.placements, cardId, 1)
    if (rows.length === 0) {
      this.toast('写作卡里还没有章，先把卡片拖进去')
      return
    }
    this.draftCardId = cardId
    this.includeOwnEvidence = false
    this.draftOpen = true
  }

  private async confirmWriteDraft(overwrite: boolean): Promise<void> {
    const cardId: string = this.draftCardId
    const card: CanvasCardData | undefined = app.canvas.cardOf(cardId)
    if (card === undefined) {
      return
    }
    const rows: CanvasOutlineRow[] = canvasFlatten(app.canvas.placements, cardId, 1)
    if (rows.length === 0) {
      this.toast('写作卡里还没有章，先把卡片拖进去')
      return
    }
    const evidence: CanvasEvidenceData[] = []
    for (let i: number = 0; i < rows.length; i++) {
      const list = app.canvas.evidenceOf(rows[i].cardId)
      for (let j: number = 0; j < list.length; j++) {
        evidence.push(list[j])
      }
    }
    const input: CanvasDraftInput = {
      rows: rows,
      evidence: evidence,
      cardOf: (id: string): CanvasCardData | undefined => app.canvas.cardOf(id)
    }
    if (this.includeOwnEvidence) {
      input.rootEvidence = app.canvas.evidenceOf(cardId)
    }
    const result: CanvasDraftResult = CanvasDraftWriter.build(input)
    this.draftOpen = false
    try {
      if (overwrite && card.docId !== '') {
        const docId: string = card.docId
        const old: ChapterModel | null = await chapterRepo.loadOne(docId)
        await chapterRepo.saveDraft(docId, result.content, 0, result.runsJson)
        await app.project.reloadChapters()
        await app.openChapter(docId)
        ensureWorkspace()
        closeCanvasAnimated(this.getUIContext())
        if (old !== null) {
          const oldContent: string = old.content
          const oldRuns: string = old.formatRuns === undefined ? '' : old.formatRuns
          app.canvas.offerUndo('已覆盖初稿', async (): Promise<void> => {
            await chapterRepo.saveDraft(docId, oldContent, 0, oldRuns)
            await app.project.reloadChapters()
          })
        }
        this.toast('已覆盖初稿，共 ' + rows.length.toString() + ' 节')
        return
      }
      const rawTitle: string = card.title.trim()
      const title: string = rawTitle === '' ? '未命名论文' : rawTitle
      const ch: ChapterModel = await chapterRepo.createChapter(app.project.currentBookId, title, ChapterFormat.MD)
      await chapterRepo.saveDraft(ch.id, result.content, 0, result.runsJson)
      await app.canvas.setCardDocId(cardId, ch.id)
      await app.project.reloadChapters()
      await app.openChapter(ch.id)
      ensureWorkspace()
      closeCanvasAnimated(this.getUIContext())
      this.toast('已生成初稿《' + ch.title + '》，共 ' + rows.length.toString() + ' 节')
    } catch (e) {
      Logger.error('CanvasPane.writeDraft failed: ' + String(e))
      this.toast('生成初稿失败，请重试')
    }
  }

  private openCardMenu(cardId: string): void {
    this.menuCardId = cardId
    this.cardMenuOpen = true
  }

  private openRename(cardId: string): void {
    const card: CanvasCardData | undefined = app.canvas.cardOf(cardId)
    if (card === undefined) {
      return
    }
    this.cardMenuOpen = false
    this.renameCardId = cardId
    this.renameTitle = card.title
    this.renameOpen = true
  }

  private confirmRename(): void {
    const title: string = this.renameTitle.trim()
    if (title === '' || this.renameCardId === '') {
      return
    }
    app.canvas.updateCard(this.renameCardId, { title: title }).then((ok: boolean) => {
      if (ok) {
        this.renameOpen = false
      } else {
        this.toast('重命名失败，请重试')
      }
    })
  }

  @Builder
  renameDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.renameOpen = false
        })
      Column() {
        Text('重命名卡片')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textPrimary)
        TextInput({ text: this.renameTitle, placeholder: '卡片标题' })
          .onChange((value: string) => {
            this.renameTitle = value
          })
          .onSubmit(() => {
            this.confirmRename()
          })
          .height(38)
          .backgroundColor(this.pal().paper)
          .border({ width: 1, color: this.pal().divider })
          .borderRadius(8)
          .margin({ top: 12 })
          .accessibilityText('卡片标题')
        Row() {
          Text('取消')
            .fontSize(12)
            .fontColor(this.pal().textSecondary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.renameOpen = false
            })
          Blank()
          Text('保存')
            .fontSize(12)
            .fontColor(this.pal().onBrand)
            .backgroundColor(this.pal().textPrimary)
            .borderRadius(8)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              this.confirmRename()
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width(320)
      .padding(18)
      .backgroundColor(this.pal().cardBg)
      .borderRadius(14)
      .border({ width: 1, color: this.pal().divider })
      .shadow({ radius: 28, color: this.pal().divider, offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  cardMenuPanel() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#22000000')
        .onClick(() => {
          this.cardMenuOpen = false
        })
      Column() {
        Text('卡片操作')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textPrimary)
          .width('100%')
          .margin({ bottom: 6 })
        Text('打开').fontSize(13).fontColor(this.pal().textPrimary).width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.cardMenuOpen = false
            this.onCardOpen(this.menuCardId)
          })
        Text('重命名').fontSize(13).fontColor(this.pal().textPrimary).width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.openRename(this.menuCardId)
          })
        Text('复制（含素材）').fontSize(13).fontColor(this.pal().textPrimary).width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.cardMenuOpen = false
            fireAndLog(app.canvas.duplicateCard(this.menuCardId), 'CanvasPane.duplicateCard')
          })
        Text('从这块白板移除').fontSize(13).fontColor(this.pal().textPrimary).width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.cardMenuOpen = false
            fireAndLog(app.canvas.removePlacement(this.menuCardId), 'CanvasPane.removePlacement')
          })
        Text('删除卡片').fontSize(13).fontColor(this.pal().danger).width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.cardMenuOpen = false
            fireAndLog(app.canvas.deleteCard(this.menuCardId), 'CanvasPane.deleteCard')
          })
        Text('取消').fontSize(13).fontColor(this.pal().textTertiary).width('100%')
          .padding({ top: 9, bottom: 4 })
          .onClick(() => {
            this.cardMenuOpen = false
          })
      }
      .width(260)
      .padding(16)
      .backgroundColor(this.pal().cardBg)
      .borderRadius(14)
      .border({ width: 1, color: this.pal().divider })
      .shadow({ radius: 28, color: this.pal().divider, offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
  }

  private draftPreviewLines(): string[] {
    const rows: CanvasOutlineRow[] = canvasFlatten(app.canvas.placements, this.draftCardId, 1)
    const out: string[] = []
    for (let i: number = 0; i < rows.length && i < 4; i++) {
      const c: CanvasCardData | undefined = app.canvas.cardOf(rows[i].cardId)
      const title: string = c === undefined ? '' : c.title
      const n: number = app.canvas.evidenceCountOf(rows[i].cardId)
      out.push(rows[i].numbering + title + (n > 0 ? ' · ' + n.toString() + ' 条素材' : ''))
    }
    return out
  }

  private draftHasDoc(): boolean {
    const c: CanvasCardData | undefined = app.canvas.cardOf(this.draftCardId)
    return c !== undefined && c.docId !== ''
  }

  @Builder
  draftDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.draftOpen = false
        })
      Column() {
        Text('生成初稿')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal().textPrimary)
        Text('按当前大纲生成；每个节点末尾会留【待展开】占位。')
          .fontSize(11.5)
          .fontColor(this.pal().textTertiary)
          .margin({ top: 4 })
        Text('生成是快照：正文与卡片不会自动双向同步。')
          .fontSize(11)
          .fontColor(this.pal().textTertiary)
          .margin({ top: 2 })
        ForEach(this.draftPreviewLines(), (line: string, index: number) => {
          Text(line)
            .fontSize(11.5)
            .fontColor(this.pal().textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 3 })
        }, (line: string, index: number): string => index.toString() + ':' + line)
        if (app.canvas.evidenceCountOf(this.draftCardId) > 0) {
          Row() {
            Text('把这张卡自己的素材写入开篇')
              .fontSize(12)
              .fontColor(this.pal().textSecondary)
              .layoutWeight(1)
            Text(this.includeOwnEvidence ? '开' : '关')
              .fontSize(12)
              .fontColor(this.includeOwnEvidence ? this.pal().onBrand : this.pal().textSecondary)
              .backgroundColor(this.includeOwnEvidence ? this.pal().textPrimary : this.pal().activeBg)
              .borderRadius(6)
              .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              .onClick(() => {
                this.includeOwnEvidence = !this.includeOwnEvidence
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        Row() {
          Text('取消')
            .fontSize(12)
            .fontColor(this.pal().textSecondary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.draftOpen = false
            })
          Blank()
          if (this.draftHasDoc()) {
            Text('打开文稿')
              .fontSize(12)
              .fontColor(this.pal().onBrand)
              .backgroundColor(this.pal().textPrimary)
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin({ right: 8 })
              .onClick(() => {
                this.draftOpen = false
                this.openDraft(this.draftCardId)
              })
            Text('覆盖现有文稿')
              .fontSize(12)
              .fontColor(this.pal().danger)
              .border({ width: 1, color: this.pal().danger })
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin({ right: 8 })
              .onClick(() => {
                fireAndLog(this.confirmWriteDraft(true), 'CanvasPane.overwriteDraft')
              })
          }
          Text(this.draftHasDoc() ? '新建副本' : '生成初稿')
            .fontSize(12)
            .fontColor(this.draftHasDoc() ? this.pal().textPrimary : this.pal().onBrand)
            .backgroundColor(this.draftHasDoc() ? this.pal().activeBg : this.pal().textPrimary)
            .border({ width: 1, color: this.draftHasDoc() ? this.pal().divider : this.pal().textPrimary })
            .borderRadius(8)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              fireAndLog(this.confirmWriteDraft(false), 'CanvasPane.newDraft')
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width(340)
      .padding(18)
      .backgroundColor(this.pal().cardBg)
      .borderRadius(14)
      .border({ width: 1, color: this.pal().divider })
      .shadow({ radius: 28, color: this.pal().divider, offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
  }

  /** 写作卡内加一章：新卡默认“第 N 章”，放在父卡右下方再挂进去。 */
  private nextChapterTitle(cardId: string): string {
    const kids: CanvasPlacementData[] = canvasChildren(app.canvas.placements, cardId)
    let max: number = 0
    for (let i: number = 0; i < kids.length; i++) {
      const c: CanvasCardData | undefined = app.canvas.cardOf(kids[i].cardId)
      if (c === undefined) {
        continue
      }
      const t: string = c.title.trim()
      if (t.startsWith('第 ') && t.endsWith(' 章')) {
        const n: number = parseInt(t.substring(2, t.length - 2), 10)
        if (!Number.isNaN(n) && n > max) {
          max = n
        }
      }
    }
    return '第 ' + (max + 1).toString() + ' 章'
  }

  private addChapter(cardId: string): void {
    const parent: CanvasPlacementData | undefined = canvasFindPlacement(app.canvas.placements, cardId)
    const x: number = parent === undefined ? 120 : parent.x + 48
    const y: number = parent === undefined ? 160 : parent.y + 72
    fireAndLog(app.canvas.addChildCard(cardId, this.nextChapterTitle(cardId), x, y)
      .then((ok: boolean) => {
        if (!ok) {
          const depth: number = canvasDepthOf(app.canvas.placements, cardId)
          this.toast(depth >= 3 ? '已到最深层，建议拆成独立写作卡' : '加章失败，请重试')
        }
      }), 'CanvasPane.addChapter')
  }

  /** 打开写作卡已经生成的初稿；没有 docId 时只提示，不跳转。 */
  private openDraft(cardId: string): void {
    const card: CanvasCardData | undefined = app.canvas.cardOf(cardId)
    if (card === undefined) {
      return
    }
    if (card.docId === '') {
      this.toast('这张写作卡还没有初稿')
      return
    }
    fireAndLog(this.openDraftDoc(card.docId), 'CanvasPane.openDraft')
  }

  private async openDraftDoc(docId: string): Promise<void> {
    try {
      await app.openChapter(docId)
      ensureWorkspace()
      closeCanvasAnimated(this.getUIContext())
    } catch (e) {
      Logger.error('CanvasPane.openDraft failed: ' + String(e))
      this.toast('初稿已不存在或无法打开')
    }
  }

  // ===================== 生命周期 =====================

  aboutToAppear(): void {
    Logger.info('CanvasPane mount board=' + app.canvas.currentBoardId +
      ', cards=' + app.canvas.cardsOnBoard().length.toString())
  }

  aboutToDisappear(): void {
    fireAndLog(app.canvas.saveViewport(), 'CanvasPane.saveViewport')
    this.resetDrag()
  }

  @Monitor('params.boardId')
  onBoardIdChanged(): void {
    const id: string = this.params.boardId
    if (id !== '' && id !== app.canvas.currentBoardId) {
      fireAndLog(app.canvas.selectBoard(id), 'CanvasPane.selectBoard')
    }
  }

  @Monitor('app.ui.themeId')
  onThemeChanged(): void {
    this.drawDots()
  }

  // ===================== 视图 =====================

  @Builder
  dotLayer() {
    Canvas(this.dotsCtx)
      .width(this.canvasW + CanvasSpec.DOT_GAP)
      .height(this.canvasH + CanvasSpec.DOT_GAP)
      .position({ x: 0, y: 0 })
      .translate({ x: this.dotShiftX(), y: this.dotShiftY() })
      .onReady(() => {
        this.drawDots()
      })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }

  @Builder
  topBar() {
    Row() {
      Column() {
        Text(this.boardTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.boardSubtitle())
          .fontSize(11)
          .fontColor(this.pal().textTertiary)
          .margin({ top: 1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 标题区兼作窗口拖动热区（2in1 自由窗口）：只在按下时调 startMoving
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down && isDesktopWindow()) {
          startWindowMove()
        }
      })
      Text('＋ 卡片')
        .fontSize(12.5)
        .fontColor(this.pal().onBrand)
        .backgroundColor(this.pal().textPrimary)
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.toggleQuickCreate()
        })
        .accessibilityText('新建卡片')
      Text('白板')
        .fontSize(12.5)
        .fontColor(this.pal().textSecondary)
        .backgroundColor(this.pal().chipBg)
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.params.onOpenBoardList()
        })
      Text('卡片库')
        .fontSize(12.5)
        .fontColor(this.pal().textSecondary)
        .backgroundColor(this.pal().chipBg)
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .margin({ left: 6 })
        .onClick(() => {
          this.params.onOpenCardLibrary()
        })
      Text('✕')
        .fontSize(15)
        .fontColor(this.pal().textSecondary)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .margin({ left: 6 })
        .accessibilityText('关闭思路板')
        .onClick(() => {
          this.params.onClose()
        })
    }
    .width('100%')
    .padding({
      left: 14, right: 14 + this.params.captionInset, top: 10, bottom: 10
    })
    .backgroundColor(this.pal().cardBg)
    .border({ width: { bottom: 1 }, color: { bottom: this.pal().divider } })
    .position({ x: 0, y: 0 })
  }

  private toggleQuickCreate(): void {
    this.quickOpen = !this.quickOpen
    if (this.quickOpen) {
      this.closeDrawer()
    }
  }

  private async quickCreate(): Promise<void> {
    const title: string = this.quickTitle.trim()
    if (title === '') {
      return
    }
    const card: CanvasCardItem | undefined = await app.canvas.createCard(this.quickKind, title)
    if (card === undefined) {
      return
    }
    const z: number = this.zoomValue()
    const cx: number = (this.canvasW / 2 - app.canvas.panX) / z - CanvasSpec.CARD_WIDTH / 2
    const cy: number = (this.canvasH / 2 - app.canvas.panY) / z - 70
    await app.canvas.addPlacement(card.id, Math.max(40, cx), Math.max(40, cy))
    this.quickTitle = ''
    this.quickOpen = false
    this.toast('已新建「' + card.title + '」')
  }

  @Builder
  quickKindChip(label: string, kind: CanvasCardKind) {
    Text(label)
      .fontSize(11.5)
      .fontColor(this.quickKind === kind ? this.pal().onBrand : this.pal().textSecondary)
      .backgroundColor(this.quickKind === kind ? this.pal().textPrimary : this.pal().paper)
      .border({ width: 1, color: this.quickKind === kind ? this.pal().textPrimary : this.pal().divider })
      .borderRadius(7)
      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      .onClick(() => {
        this.quickKind = kind
      })
  }

  @Builder
  quickCreatePanel() {
    Column() {
      Row() {
        Text('新建卡片')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().textPrimary)
        Blank()
        Text('✕')
          .fontSize(13)
          .fontColor(this.pal().textTertiary)
          .padding({ left: 8, right: 2, top: 2, bottom: 2 })
          .onClick(() => {
            this.quickOpen = false
          })
          .accessibilityText('关闭新建卡片')
      }
      .width('100%')
      TextInput({ text: this.quickTitle, placeholder: '标题，例如「均势」' })
        .onChange((value: string) => {
          this.quickTitle = value
        })
        .height(38)
        .backgroundColor(this.pal().paper)
        .border({ width: 1, color: this.pal().divider })
        .borderRadius(8)
        .margin({ top: 10 })
      Row() {
        this.quickKindChip('概念卡', CanvasCardKind.CONCEPT)
        this.quickKindChip('写作卡', CanvasCardKind.WRITING)
        Blank()
        Button('创建')
          .fontSize(12)
          .height(32)
          .backgroundColor(this.quickTitle.trim() === '' ? this.pal().activeBg : this.pal().textPrimary)
          .fontColor(this.quickTitle.trim() === '' ? this.pal().textTertiary : this.pal().onBrand)
          .borderRadius(8)
          .enabled(this.quickTitle.trim() !== '')
          .onClick(() => {
            fireAndLog(this.quickCreate(), 'CanvasPane.quickCreate')
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width(this.quickPanelWidth())
    .padding(14)
    .backgroundColor(this.pal().cardBg)
    .borderRadius(12)
    .border({ width: 1, color: this.pal().divider })
    .shadow({ radius: 24, color: this.pal().divider, offsetX: 0, offsetY: 8 })
    .position({
      x: Math.max(16, this.canvasW - this.quickPanelWidth() - 16 - this.params.captionInset),
      y: 62
    })
  }

  private quickPanelWidth(): number {
    return Math.min(320, Math.max(240, this.canvasW - 48))
  }

  @Builder
  errorBanner() {
    Row() {
      Text(app.canvas.error)
        .fontSize(11.5)
        .fontColor(this.pal().danger)
        .maxLines(2)
        .layoutWeight(1)
      Text('重试')
        .fontSize(11.5)
        .fontColor(this.pal().textPrimary)
        .padding({ left: 10, right: 4, top: 4, bottom: 4 })
        .onClick(() => {
          fireAndLog(app.canvas.load(), 'CanvasPane.retry')
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(this.pal().accentSoft)
    .position({ x: 0, y: 56 })
  }

  @Builder
  emptyState() {
    Column() {
      Text('从卡片库新建或放一张卡')
        .fontSize(13)
        .fontColor(this.pal().textSecondary)
      Text('打开卡片库 · 新建 / 放卡')
        .fontSize(12.5)
        .fontColor(this.pal().onBrand)
        .backgroundColor(this.pal().textPrimary)
        .borderRadius(8)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .margin({ top: 12 })
        .onClick(() => {
          this.params.onOpenCardLibrary()
        })
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  zoomBar() {
    Row() {
      Text('−')
        .fontSize(15)
        .fontColor(this.pal().textSecondary)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.applyZoom(this.zoomValue() - 0.1)
        })
        .accessibilityText('缩小')
      Text(Math.round(this.zoomValue() * 100).toString() + '%')
        .fontSize(11)
        .fontColor(this.pal().textTertiary)
        .width(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.resetZoom()
        })
        .accessibilityText('恢复 100%')
      Text('＋')
        .fontSize(15)
        .fontColor(this.pal().textSecondary)
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.applyZoom(this.zoomValue() + 0.1)
        })
        .accessibilityText('放大')
    }
    .backgroundColor(this.pal().cardBg)
    .borderRadius(9)
    .border({ width: 1, color: this.pal().divider })
    .padding({ left: 4, right: 4 })
    .position({ x: this.canvasW - 132, y: this.canvasH - 52 })
  }

  @Builder
  hintPill() {
    Text('拖动卡片移动 · 靠近另一张卡会张开缺口，松手即嵌套 · 行尾 ↗ 移出 · 拖空白平移')
      .fontSize(11)
      .fontColor(this.pal().textTertiary)
      .backgroundColor(this.pal().cardBg)
      .borderRadius(8)
      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      .position({ x: 14, y: this.canvasH - 44 })
      .maxLines(1)
  }

  /**
   * 背景层：点阵 + 平移/缩放手势。
   * 手势挂在这一层而不是根 Stack：卡片/抽屉是它的兄弟节点，命中优先，
   * 从根上挂会和卡片的 PanGesture 抢同一串触点。
   */
  @Builder
  backgroundLayer() {
    Stack() {
      this.dotLayer()
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: CanvasLayout.DRAG_DISTANCE })
          .onActionStart((event: GestureEvent) => {
            this.panBaseX = app.canvas.panX
            this.panBaseY = app.canvas.panY
          })
          .onActionUpdate((event: GestureEvent) => {
            app.canvas.panX = this.panBaseX + event.offsetX
            app.canvas.panY = this.panBaseY + event.offsetY
          })
          .onActionEnd((event: GestureEvent) => {
            fireAndLog(app.canvas.saveViewport(), 'CanvasPane.saveViewport')
          }),
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent) => {
            this.pinchBaseZoom = this.zoomValue()
            this.pinchBasePanX = app.canvas.panX
            this.pinchBasePanY = app.canvas.panY
          })
          .onActionUpdate((event: GestureEvent) => {
            const scale: number = event.scale !== undefined ? event.scale : 1
            const raw: number = this.pinchBaseZoom * scale
            const next: number = Math.min(CanvasSpec.MAX_ZOOM, Math.max(CanvasSpec.MIN_ZOOM, raw))
            const cx: number = event.pinchCenterX !== undefined ? event.pinchCenterX : this.canvasW / 2
            const cy: number = event.pinchCenterY !== undefined ? event.pinchCenterY : this.canvasH / 2
            app.canvas.panX = cx - (cx - this.pinchBasePanX) * (next / this.pinchBaseZoom)
            app.canvas.panY = cy - (cy - this.pinchBasePanY) * (next / this.pinchBaseZoom)
            app.canvas.zoom = next
          })
          .onActionEnd((event: GestureEvent) => {
            fireAndLog(app.canvas.saveViewport(), 'CanvasPane.saveViewport')
          })
      )
    )
  }

  build() {
    Stack() {
      this.backgroundLayer()
      CanvasEdges({
        lines: this.edgeLines(),
        canvasWidth: this.canvasW,
        canvasHeight: this.canvasH,
        themeId: app.ui.themeId
      })
      ForEach(this.cardViews(), (view: CanvasCardView) => {
        TopicCard({
          cardData: view.card,
          placementData: view.placement,
          rows: view.rows,
          screenX: this.screenX(view.placement.x),
          screenY: this.screenY(view.placement.y),
          zoom: this.zoomValue(),
          selectedId: app.canvas.selectedCardId,
          materialCount: view.materialCount,
          mouthOn: this.mouthOn && this.mouthCardId === view.card.id,
          mouthInsert: this.mouthInsert,
          mouthDepth: this.mouthDepth,
          dragOffsetX: this.dragCardId === view.card.id ? this.dragDx : 0,
          dragOffsetY: this.dragCardId === view.card.id ? this.dragDy : 0,
          dragActive: this.dragCardId === view.card.id,
          themeId: app.ui.themeId,
          onOpenCard: (cardId: string) => {
            this.onCardOpen(cardId)
          },
          onCardDragStart: (cardId: string, kind: CanvasDragKind, winX: number, winY: number) => {
            this.onCardDragStart(cardId, kind, winX, winY)
          },
          onDragFrame: (cardId: string, kind: CanvasDragKind, dx: number, dy: number,
            winX2: number, winY2: number) => {
            this.onDragFrame(cardId, kind, dx, dy, winX2, winY2)
          },
          onDragFinish: (cardId: string, kind: CanvasDragKind, dx: number, dy: number,
            winX2: number, winY2: number) => {
            this.onDragFinish(cardId, kind, dx, dy, winX2, winY2)
          },
          onDragCancel: () => {
            this.onDragCancel()
          },
          onRowUp: (cardId: string) => {
            fireAndLog(app.canvas.reorderCard(cardId, -1), 'CanvasPane.reorderUp')
          },
          onRowDown: (cardId: string) => {
            fireAndLog(app.canvas.reorderCard(cardId, 1), 'CanvasPane.reorderDown')
          },
          onRowOut: (cardId: string) => {
            this.rowOut(cardId)
          },
          onWriteDraft: (cardId: string) => {
            fireAndLog(this.writeDraft(cardId), 'CanvasPane.writeDraft')
          },
          onOpenDraft: (cardId: string) => {
            this.openDraft(cardId)
          },
          onAddChapter: (cardId: string) => {
            this.addChapter(cardId)
          },
          onRenameCard: (cardId: string) => {
            this.openRename(cardId)
          },
          onCardMenu: (cardId: string) => {
            this.openCardMenu(cardId)
          },
          onGeometry: (cardId: string, cardHeight: number, bodyTop: number) => {
            this.noteGeometry(cardId, cardHeight, bodyTop)
          }
        })
      }, (view: CanvasCardView): string => view.placement.id)

      this.topBar()
      if (this.quickOpen) {
        this.quickCreatePanel()
      }
      if (this.draftOpen) {
        this.draftDialog()
      }
      if (this.cardMenuOpen) {
        this.cardMenuPanel()
      }
      if (this.renameOpen) {
        this.renameDialog()
      }
      if (app.canvas.error !== '') {
        this.errorBanner()
      }
      if (this.isEmptyBoard()) {
        this.emptyState()
      }
      if (this.canvasW > 200) {
        this.zoomBar()
        this.hintPill()
      }
      if (app.canvas.selectedCardId !== '') {
        EvidenceDrawer({
          cardId: app.canvas.selectedCardId,
          narrow: app.ui.isNarrow,
          themeId: app.ui.themeId,
          captionInset: this.params.captionInset,
          onClose: () => {
            this.closeDrawer()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal().paper)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.canvasOriginX = Number(newValue.globalPosition.x)
      this.canvasOriginY = Number(newValue.globalPosition.y)
      const w: number = Number(newValue.width)
      const h: number = Number(newValue.height)
      if (Math.abs(w - this.canvasW) > 0.5 || Math.abs(h - this.canvasH) > 0.5) {
        this.canvasW = w
        this.canvasH = h
        app.canvas.viewportW = w
        app.canvas.viewportH = h
        setTimeout(() => {
          this.drawDots()
        }, 0)
      }
    })
  }
}
