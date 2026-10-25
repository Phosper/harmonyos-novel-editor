// 思路板：纯类型与纯规则（不依赖 ArkUI，可被 Node 回归直接执行）
//
// 约定：
// - 父子关系属于「贴放 placement」，不属于卡片 card；同一张卡在不同白板可有不同父。
// - 深度：顶层 placement = 0；写作卡/概念卡本身不计层；子卡最多 3 层（章/节/目）。
// - 命名统一加 Canvas 前缀，避免 arkts 无声明合并导致的跨文件重名。

export enum CanvasCardKind {
  CONCEPT = 'concept',
  WRITING = 'writing'
}

export enum CanvasBoardScope {
  COURSE = 'course',
  FREE = 'free'
}

export enum CanvasEvidenceKind {
  QUOTE = 'quote',
  JUDGEMENT = 'judgement',
  NOTE = 'note'
}

export enum CanvasLinkKind {
  PREMISE = 'premise',
  CAUSE = 'cause',
  CONTRAST = 'contrast',
  EXAMPLE = 'example',
  SEQUENCE = 'sequence',
  RELATE = 'relate'
}

export interface CanvasEvidenceData {
  id: string
  cardId: string
  kind: CanvasEvidenceKind
  docId: string
  paraIndex: number
  startOff: number
  endOff: number
  fingerprint: string
  quoteText: string
  userText: string
  sourceLabel: string
  createdAt: number
}

export interface CanvasCardData {
  id: string
  bookId: string
  kind: CanvasCardKind
  title: string
  aliases: string
  tags: string
  summary: string
  docId: string
  createdAt: number
  updatedAt: number
}

export interface CanvasBoardData {
  id: string
  scope: CanvasBoardScope
  bookId: string
  title: string
  panX: number
  panY: number
  zoom: number
  sortOrder: number
  createdAt: number
  updatedAt: number
}

export interface CanvasPlacementData {
  id: string
  canvasId: string
  cardId: string
  parentId: string
  order: number
  x: number
  y: number
  z: number
  collapsed: boolean
  style: string
}

export interface CanvasLinkData {
  id: string
  canvasId: string
  fromCardId: string
  toCardId: string
  kind: CanvasLinkKind
  label: string
  createdAt: number
}

export interface CanvasOutlineRow {
  cardId: string
  placementId: string
  depth: number
  index: number
  numbering: string
}

/** 子卡最多 3 层：章（一、）/ 节（（一））/ 目（1.） */
export const CANVAS_MAX_DEPTH: number = 3

const CANVAS_CN_NUM: string[] = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十']

/** 自动编号：深度 1 → 一、 深度 2 → （一） 深度 3 → 1. */
export function canvasNumbering(depth: number, index: number): string {
  const cn: string = index >= 0 && index < CANVAS_CN_NUM.length ? CANVAS_CN_NUM[index] : (index + 1).toString()
  if (depth === 1) {
    return cn + '、'
  }
  if (depth === 2) {
    return '（' + cn + '）'
  }
  return (index + 1).toString() + '.'
}

/** 按 order 升序取某个父下的直接子项；parentId 传空串表示顶层。 */
export function canvasChildren(placements: CanvasPlacementData[], parentId: string): CanvasPlacementData[] {
  const out: CanvasPlacementData[] = []
  for (let i: number = 0; i < placements.length; i++) {
    const p: CanvasPlacementData = placements[i]
    if (p.parentId === parentId) {
      out.push(p)
    }
  }
  out.sort((a: CanvasPlacementData, b: CanvasPlacementData): number => a.order - b.order)
  return out
}

/** 在给定数组里按 cardId 找 placement；找不到返回 undefined。 */
export function canvasFindPlacement(placements: CanvasPlacementData[], cardId: string): CanvasPlacementData | undefined {
  for (let i: number = 0; i < placements.length; i++) {
    if (placements[i].cardId === cardId) {
      return placements[i]
    }
  }
  return undefined
}

/** 顶层 = 0；子卡逐级 +1。找不到按 0 处理。 */
export function canvasDepthOf(placements: CanvasPlacementData[], cardId: string): number {
  let depth: number = 0
  let current: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  let guard: number = 0
  while (current !== undefined && current.parentId !== '' && guard < 64) {
    depth++
    guard++
    current = canvasFindPlacement(placements, current.parentId)
  }
  return depth
}

/** 该卡子树的最大相对深度（无子卡 = 0）。 */
export function canvasSubtreeDepth(placements: CanvasPlacementData[], cardId: string): number {
  const kids: CanvasPlacementData[] = canvasChildren(placements, cardId)
  if (kids.length === 0) {
    return 0
  }
  let max: number = 0
  for (let i: number = 0; i < kids.length; i++) {
    const d: number = 1 + canvasSubtreeDepth(placements, kids[i].cardId)
    if (d > max) {
      max = d
    }
  }
  return max
}

/** ancestorCardId 是否是 cardId 的祖先（不含自身）。 */
export function canvasIsAncestor(placements: CanvasPlacementData[], ancestorCardId: string, cardId: string): boolean {
  let current: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  let guard: number = 0
  while (current !== undefined && current.parentId !== '' && guard < 64) {
    if (current.parentId === ancestorCardId) {
      return true
    }
    current = canvasFindPlacement(placements, current.parentId)
    guard++
  }
  return false
}

/**
 * 能否把 dragCardId 放进 targetCardId：
 * - 不能放自己；
 * - 不能放进自己的子孙（环）；
 * - 目标深度 + 1 不超过 3；
 * - 目标深度 + 1 + 被拖子树深度 不超过 3。
 */
export function canvasCanNest(placements: CanvasPlacementData[], dragCardId: string, targetCardId: string): boolean {
  if (dragCardId === targetCardId) {
    return false
  }
  if (canvasIsAncestor(placements, dragCardId, targetCardId)) {
    return false
  }
  const targetDepth: number = canvasDepthOf(placements, targetCardId)
  const nextDepth: number = targetDepth + 1
  if (nextDepth < 1 || nextDepth > CANVAS_MAX_DEPTH) {
    return false
  }
  if (nextDepth + canvasSubtreeDepth(placements, dragCardId) > CANVAS_MAX_DEPTH) {
    return false
  }
  return true
}

/** 同级下一个 order。 */
export function canvasNextOrder(placements: CanvasPlacementData[], parentId: string): number {
  const kids: CanvasPlacementData[] = canvasChildren(placements, parentId)
  if (kids.length === 0) {
    return 0
  }
  let max: number = 0
  for (let i: number = 0; i < kids.length; i++) {
    if (kids[i].order > max) {
      max = kids[i].order
    }
  }
  return max + 1
}

/** 深度优先展开成大纲行（含自动编号），用于渲染缩进行和生成初稿。 */
export function canvasFlatten(placements: CanvasPlacementData[], parentId: string, depth: number): CanvasOutlineRow[] {
  const rows: CanvasOutlineRow[] = []
  const kids: CanvasPlacementData[] = canvasChildren(placements, parentId)
  for (let i: number = 0; i < kids.length; i++) {
    const p: CanvasPlacementData = kids[i]
    const row: CanvasOutlineRow = {
      cardId: p.cardId,
      placementId: p.id,
      depth: depth,
      index: i,
      numbering: canvasNumbering(depth, i)
    }
    rows.push(row)
    const nested: CanvasOutlineRow[] = canvasFlatten(placements, p.cardId, depth + 1)
    for (let j: number = 0; j < nested.length; j++) {
      rows.push(nested[j])
    }
  }
  return rows
}

/**
 * 把 cardId 挂到 newParentId（空串=顶层）下，追加为最后一个。
 * 只改 parentId/order，不碰坐标；调用方负责持久化。
 */
export function canvasAttach(placements: CanvasPlacementData[], cardId: string, newParentId: string): void {
  const target: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  if (target === undefined) {
    return
  }
  // 先算 order：若先改 parentId，目标会被算进兄弟里，order 永远多 1
  const nextOrder: number = canvasNextOrder(placements, newParentId)
  target.parentId = newParentId
  target.order = nextOrder
}

/**
 * 把 cardId 挂到 newParentId 下，并插入到 siblings 的第 index 位（0 基）。
 * 与 canvasAttach 的区别：落点预览的 index 就是最终顺序，不再一律追加。
 */
export function canvasAttachAt(placements: CanvasPlacementData[], cardId: string,
  newParentId: string, index: number): void {
  const target: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  if (target === undefined) {
    return
  }
  const allSiblings: CanvasPlacementData[] = canvasChildren(placements, newParentId)
  let currentIndex: number = -1
  for (let i: number = 0; i < allSiblings.length; i++) {
    if (allSiblings[i].cardId === cardId) {
      currentIndex = i
      break
    }
  }
  const siblings: CanvasPlacementData[] = allSiblings.filter(
    (p: CanvasPlacementData): boolean => p.cardId !== cardId)
  // index 是按“含被拖卡”的兄弟列表算的；同父移动时先移除自己，后面的位置要回退一位
  let adjusted: number = index
  if (currentIndex >= 0 && currentIndex < index) {
    adjusted = index - 1
  }
  const at: number = Math.max(0, Math.min(adjusted, siblings.length))
  target.parentId = newParentId
  const ordered: CanvasPlacementData[] = siblings.slice()
  ordered.splice(at, 0, target)
  for (let i: number = 0; i < ordered.length; i++) {
    ordered[i].order = i
  }
}

/**
 * 从白板移除一个 placement：其子项上提一层，并重排同级 order。
 * 只处理传入数组（同一块白板的全部 placement）。
 */
export function canvasRemovePlacement(placements: CanvasPlacementData[], cardId: string): void {
  const target: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  if (target === undefined) {
    return
  }
  const newParent: string = target.parentId
  const kids: CanvasPlacementData[] = canvasChildren(placements, cardId)
  let order: number = canvasNextOrder(placements, newParent)
  for (let i: number = 0; i < kids.length; i++) {
    kids[i].parentId = newParent
    kids[i].order = order
    order++
  }
  const index: number = placements.indexOf(target)
  if (index >= 0) {
    placements.splice(index, 1)
  }
}

/** 同级重排：把 cardId 在兄弟中上移/下移一位；返回是否发生变化。 */
export function canvasReorder(placements: CanvasPlacementData[], cardId: string, delta: number): boolean {
  const target: CanvasPlacementData | undefined = canvasFindPlacement(placements, cardId)
  if (target === undefined) {
    return false
  }
  const siblings: CanvasPlacementData[] = canvasChildren(placements, target.parentId)
  let index: number = -1
  for (let i: number = 0; i < siblings.length; i++) {
    if (siblings[i].cardId === cardId) {
      index = i
    }
  }
  const nextIndex: number = index + delta
  if (index < 0 || nextIndex < 0 || nextIndex >= siblings.length) {
    return false
  }
  const a: CanvasPlacementData = siblings[index]
  const b: CanvasPlacementData = siblings[nextIndex]
  const tmp: number = a.order
  a.order = b.order
  b.order = tmp
  return true
}
