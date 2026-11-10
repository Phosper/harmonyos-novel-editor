// 导图的"附加信息"（M5）：概要 + 关系线。
//
// 与正文的关系（方案稿 D1/D5）：
//  - 概要是"这一组主题共同的结论"，关系线是"A 论证 B"——它们**不是文章结构**，
//    所以不进正文、不进版本号，落独立侧车表，删文稿时一起删。
//  - 本文件只做数据与纯几何：宿主存/取，渲染层只消费算好的图元。
//  - 没有 import，可直接在 Node 里回归（与 OutlineLayout 同一套约定）。

import { PlacedNode, OUTLINE_NODE_W, OUTLINE_NODE_H } from './OutlineLayout'

/** 一条概要：覆盖同一父节点下、从 startParaId 到 endParaId 的连续主题 */
export class OutlineSummary {
  id: string = ''
  startParaId: string = ''
  endParaId: string = ''
  text: string = ''

  constructor(id: string = '', startParaId: string = '', endParaId: string = '', text: string = '') {
    this.id = id
    this.startParaId = startParaId
    this.endParaId = endParaId
    this.text = text
  }
}

/** 一条关系线：两个主题 + 一句标签（"A 论证 B"） */
export class OutlineRelation {
  id: string = ''
  fromParaId: string = ''
  toParaId: string = ''
  label: string = ''

  constructor(id: string = '', fromParaId: string = '', toParaId: string = '', label: string = '') {
    this.id = id
    this.fromParaId = fromParaId
    this.toParaId = toParaId
    this.label = label
  }
}

/** 一篇文稿的全部附加信息（宿主发布给导图页的只读副本） */
export class OutlineExtras {
  docId: string = ''
  summaries: OutlineSummary[] = []
  relations: OutlineRelation[] = []
}

/** 附加信息的编辑命令：与正文命令分开，永远不触发正文写入 */
export class OutlineExtraCommand {
  kind: string = ''
  extraId: string = ''
  fromId: string = ''
  toId: string = ''
  text: string = ''

  constructor(kind: string = '', extraId: string = '', fromId: string = '', toId: string = '',
    text: string = '') {
    this.kind = kind
    this.extraId = extraId
    this.fromId = fromId
    this.toId = toId
    this.text = text
  }
}

export const OUTLINE_EXTRA_ADD_SUMMARY: string = 'add-summary'
export const OUTLINE_EXTRA_REMOVE_SUMMARY: string = 'remove-summary'
export const OUTLINE_EXTRA_ADD_RELATION: string = 'add-relation'
export const OUTLINE_EXTRA_REMOVE_RELATION: string = 'remove-relation'

/** 括号离节点的距离、文字框宽度、描边留白 */
export const OUTLINE_SUMMARY_GAP: number = 14
export const OUTLINE_SUMMARY_TEXT_W: number = 110
export const OUTLINE_EXTRA_PAD: number = 2

/** 一段概要的渲染图元：括号折线 + 文字锚点 + 删除按钮锚点（全部 vp） */
export class OutlineSummaryBox {
  summaryId: string = ''
  text: string = ''
  originX: number = 0
  originY: number = 0
  width: number = 1
  height: number = 1
  /** 括号折线（相对包围盒）：[外,上] [内,上] [内,下] [外,下] */
  points: number[][] = []
  textX: number = 0
  textY: number = 0
  /** 文字框是否靠右对齐（括号在节点左侧时） */
  alignEnd: boolean = false
  closeX: number = 0
  closeY: number = 0
}

/** 一条关系线的渲染图元：曲线 + 箭头 + 标签锚点 */
export class OutlineRelationWire {
  relationId: string = ''
  label: string = ''
  originX: number = 0
  originY: number = 0
  width: number = 1
  height: number = 1
  points: number[][] = []
  arrow: number[][] = []
  labelX: number = 0
  labelY: number = 0
  closeX: number = 0
  closeY: number = 0
}

function indexByParaId(nodes: PlacedNode[]): Map<string, number> {
  const map: Map<string, number> = new Map<string, number>()
  for (let i: number = 0; i < nodes.length; i++) {
    if (nodes[i].paraId !== '') {
      map.set(nodes[i].paraId, i)
    }
  }
  return map
}

function cubicAt(p0: number, p1: number, p2: number, p3: number, t: number): number {
  const u: number = 1 - t
  return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
}

/**
 * 概要 → 括号图元。
 *
 * 形状照 XMind：一组主题外侧一根竖线 + 两端短横（一个方括号），文字挂在括号外侧中央。
 * 归属判定用"同一父节点 + 落在两个端点之间"，所以折叠/删除后端点缺失就整条不画，
 * 绝不会画到别的分支上。
 */
export function outlineSummaryBoxes(nodes: PlacedNode[],
  summaries: OutlineSummary[]): OutlineSummaryBox[] {
  const out: OutlineSummaryBox[] = []
  if (nodes.length === 0 || summaries.length === 0) {
    return out
  }
  const index: Map<string, number> = indexByParaId(nodes)
  for (let s: number = 0; s < summaries.length; s++) {
    const summary: OutlineSummary = summaries[s]
    const i0: number | undefined = index.get(summary.startParaId)
    const i1: number | undefined = index.get(summary.endParaId)
    if (i0 === undefined || i1 === undefined) {
      continue
    }
    const from: number = Math.min(i0, i1)
    const to: number = Math.max(i0, i1)
    const parent: number = nodes[from].parentIndex
    if (nodes[to].parentIndex !== parent || parent < 0) {
      continue
    }
    // 成员：两个端点之间、同一个父节点下的节点
    let top: number = -1
    let bottom: number = -1
    let outerX: number = 0
    let side: number = nodes[from].side
    let memberCount: number = 0
    for (let i: number = from; i <= to; i++) {
      const node: PlacedNode = nodes[i]
      if (node.parentIndex !== parent) {
        continue
      }
      const nodeTop: number = node.y
      const nodeBottom: number = node.y + OUTLINE_NODE_H * node.scale
      const right: number = node.x + OUTLINE_NODE_W * node.scale
      if (memberCount === 0 || nodeTop < top) {
        top = nodeTop
      }
      if (memberCount === 0 || nodeBottom > bottom) {
        bottom = nodeBottom
      }
      if (memberCount === 0 || right > outerX) {
        outerX = right
      }
      if (memberCount === 0) {
        side = node.side
      }
      memberCount++
    }
    if (memberCount < 2) {
      continue
    }
    const box: OutlineSummaryBox = new OutlineSummaryBox()
    box.summaryId = summary.id
    box.text = summary.text
    // 括号贴在成员的外侧（朝右的组在右边，朝左的组在左边）
    const bracketX: number = side < 0 ? nodes[from].x - OUTLINE_SUMMARY_GAP : outerX + OUTLINE_SUMMARY_GAP
    const minY: number = top - OUTLINE_EXTRA_PAD
    const maxY: number = bottom + OUTLINE_EXTRA_PAD
    const minX: number = Math.min(bracketX, bracketX + (side < 0 ? 6 : -6)) - OUTLINE_EXTRA_PAD
    const maxX: number = Math.max(bracketX, bracketX + (side < 0 ? 6 : -6)) + OUTLINE_EXTRA_PAD
    box.originX = minX
    box.originY = minY
    box.width = Math.max(1, maxX - minX)
    box.height = Math.max(1, maxY - minY)
    const outer: number = bracketX + (side < 0 ? 6 : -6)
    box.points.push([outer - minX, top - minY])
    box.points.push([bracketX - minX, top - minY])
    box.points.push([bracketX - minX, bottom - minY])
    box.points.push([outer - minX, bottom - minY])
    box.alignEnd = side < 0
    box.textX = side < 0 ? bracketX - 8 - OUTLINE_SUMMARY_TEXT_W : bracketX + 8
    box.textY = (top + bottom) / 2 - 9
    box.closeX = side < 0 ? box.textX - 20 : box.textX + OUTLINE_SUMMARY_TEXT_W + 4
    box.closeY = box.textY + 1
    out.push(box)
  }
  return out
}

/** 关系线：两个主题之间的一条弧线 + 标签（重心在中点，弧往一侧鼓） */
export function outlineRelationWires(nodes: PlacedNode[],
  relations: OutlineRelation[]): OutlineRelationWire[] {
  const out: OutlineRelationWire[] = []
  if (nodes.length === 0 || relations.length === 0) {
    return out
  }
  const index: Map<string, number> = indexByParaId(nodes)
  for (let r: number = 0; r < relations.length; r++) {
    const relation: OutlineRelation = relations[r]
    const i0: number | undefined = index.get(relation.fromParaId)
    const i1: number | undefined = index.get(relation.toParaId)
    if (i0 === undefined || i1 === undefined || i0 === i1) {
      continue
    }
    const a: PlacedNode = nodes[i0]
    const b: PlacedNode = nodes[i1]
    const aw: number = OUTLINE_NODE_W * a.scale
    const ah: number = OUTLINE_NODE_H * a.scale
    const bw: number = OUTLINE_NODE_W * b.scale
    const bh: number = OUTLINE_NODE_H * b.scale
    // 端点取朝向对方的那条边：左右错开走竖边，同一列走横边
    let x0: number = 0
    let y0: number = 0
    let x1: number = 0
    let y1: number = 0
    if (Math.abs(b.x - a.x) < 1) {
      const down: boolean = b.y > a.y
      x0 = a.x + aw / 2
      y0 = down ? a.y + ah : a.y
      x1 = b.x + bw / 2
      y1 = down ? b.y : b.y + bh
    } else if (b.x > a.x) {
      x0 = a.x + aw
      y0 = a.y + ah / 2
      x1 = b.x
      y1 = b.y + bh / 2
    } else {
      x0 = a.x
      y0 = a.y + ah / 2
      x1 = b.x + bw
      y1 = b.y + bh / 2
    }
    const mx: number = (x0 + x1) / 2
    const my: number = (y0 + y1) / 2
    const dx: number = x1 - x0
    const dy: number = y1 - y0
    const len: number = Math.sqrt(dx * dx + dy * dy)
    const safe: number = len < 0.001 ? 1 : len
    const bow: number = Math.min(56, len * 0.22)
    const cx: number = mx - dy / safe * bow
    const cy: number = my + dx / safe * bow
    const steps: number = 16
    const raw: number[][] = []
    for (let k: number = 0; k <= steps; k++) {
      const t: number = k / steps
      raw.push([cubicAt(x0, cx, cx, x1, t), cubicAt(y0, cy, cy, y1, t)])
    }
    const midPoint: number[] = raw[Math.floor(steps / 2)]
    // 箭头贴在 b 的端点，方向取曲线在末端的切线
    const tip: number[] = raw[steps]
    const prev: number[] = raw[steps - 1]
    const ang: number = Math.atan2(tip[1] - prev[1], tip[0] - prev[0])
    const ah2: number = 7
    const arrow: number[][] = []
    arrow.push([tip[0] - ah2 * Math.cos(ang - 0.42), tip[1] - ah2 * Math.sin(ang - 0.42)])
    arrow.push([tip[0], tip[1]])
    arrow.push([tip[0] - ah2 * Math.cos(ang + 0.42), tip[1] - ah2 * Math.sin(ang + 0.42)])
    let minX: number = raw[0][0]
    let maxX: number = raw[0][0]
    let minY: number = raw[0][1]
    let maxY: number = raw[0][1]
    for (let k: number = 0; k < raw.length; k++) {
      minX = Math.min(minX, raw[k][0])
      maxX = Math.max(maxX, raw[k][0])
      minY = Math.min(minY, raw[k][1])
      maxY = Math.max(maxY, raw[k][1])
    }
    for (let k: number = 0; k < arrow.length; k++) {
      minX = Math.min(minX, arrow[k][0])
      maxX = Math.max(maxX, arrow[k][0])
      minY = Math.min(minY, arrow[k][1])
      maxY = Math.max(maxY, arrow[k][1])
    }
    const wire: OutlineRelationWire = new OutlineRelationWire()
    wire.relationId = relation.id
    wire.label = relation.label
    wire.originX = minX - OUTLINE_EXTRA_PAD
    wire.originY = minY - OUTLINE_EXTRA_PAD
    wire.width = Math.max(1, maxX - minX + OUTLINE_EXTRA_PAD * 2)
    wire.height = Math.max(1, maxY - minY + OUTLINE_EXTRA_PAD * 2)
    for (let k: number = 0; k < raw.length; k++) {
      wire.points.push([raw[k][0] - wire.originX, raw[k][1] - wire.originY])
    }
    for (let k: number = 0; k < arrow.length; k++) {
      wire.arrow.push([arrow[k][0] - wire.originX, arrow[k][1] - wire.originY])
    }
    wire.labelX = midPoint[0]
    wire.labelY = midPoint[1]
    wire.closeX = midPoint[0] + 46
    wire.closeY = midPoint[1] - 22
    out.push(wire)
  }
  return out
}

/**
 * 多选 → 概要命令所需的端点。
 * 只认"同一个父节点"的一批；按在树上的先后定 start/end，返回 [startParaId, endParaId]，
 * 不满足条件返回空数组（按钮据此灰掉）。
 */
export function summaryRangeOf(nodes: PlacedNode[], paraIds: string[]): string[] {
  if (paraIds.length < 2) {
    return []
  }
  const index: Map<string, number> = indexByParaId(nodes)
  let parent: number = -2
  let first: number = -1
  let last: number = -1
  for (let i: number = 0; i < paraIds.length; i++) {
    const at: number | undefined = index.get(paraIds[i])
    if (at === undefined) {
      return []
    }
    const node: PlacedNode = nodes[at]
    if (parent === -2) {
      parent = node.parentIndex
    } else if (parent !== node.parentIndex) {
      return []
    }
    if (first < 0 || at < first) {
      first = at
    }
    if (last < 0 || at > last) {
      last = at
    }
  }
  if (parent < 0 || first < 0 || last < 0 || last - first + 1 < 2) {
    return []
  }
  return [nodes[first].paraId, nodes[last].paraId]
}
