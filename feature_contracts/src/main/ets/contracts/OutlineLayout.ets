// 只读大纲/导图的纯数据与布局（用户确认：先做只读版，不做编辑）
//
// 为什么放在契约包：entry 负责"从正文抽标题"，structure 包负责"画出来"，
// 两边必须用同一套节点与坐标规则；这里没有任何 import，可以直接在 Node 里回归。
//
// 限制（明确写死，避免以后误用）：
//  - 节点身份暂时用 startOffset（正文还没有段落 ID）；P5 换成 paraId 后这里升级。
//  - 只处理标题派生；图内额外关系/概要属于后面的阶段。

/** 从正文里抽出来的一个标题（entry 侧产出） */
export interface OutlineHeading {
  /** 标题文字（已去掉行首标记） */
  title: string
  /** 段落种类：1/2/3 = H1/H2/H3 */
  level: number
  startOffset: number
  endOffset: number
}

/** 大纲节点（含合成出来的根节点） */
export class OutlineNode {
  id: string = ''
  title: string = ''
  /** 0 = 根（文稿本身），1–3 = 标题层级 */
  level: number = 0
  /** 树深度：根为 0，标题按层级嵌套 */
  depth: number = 0
  startOffset: number = 0
  endOffset: number = 0
  /** 稳定身份：正文段落 id（root 为空串）。取代早先的 'h'+偏移 */
  paraId: string = ''
  /** 父节点在 nodes 数组里的下标（root 为 -1） */
  parentIndex: number = -1
  /** 这一节最后一个段落结束处的正文偏移（拖动搬运时用） */
  sectionEnd: number = 0

  constructor(id: string = '', title: string = '', level: number = 0, depth: number = 0,
    startOffset: number = 0, endOffset: number = 0, paraId: string = '', parentIndex: number = -1) {
    this.id = id
    this.title = title
    this.level = level
    this.depth = depth
    this.startOffset = startOffset
    this.endOffset = endOffset
    this.paraId = paraId
    this.parentIndex = parentIndex
    this.sectionEnd = endOffset
  }
}

/** 一次快照：宿主在打开导图前发布，导图页只读 */
export class OutlineSnapshot {
  docId: string = ''
  docTitle: string = ''
  /** 正文版本（用于判断快照是否过期；当前用编辑器的 contentRev） */
  version: number = 0
  nodes: OutlineNode[] = []
}

/** 布局后的节点（vp） */
export class PlacedNode {
  id: string = ''
  title: string = ''
  level: number = 0
  depth: number = 0
  x: number = 0
  y: number = 0
  startOffset: number = 0
  /** 稳定身份（正文段落 id） */
  paraId: string = ''
  parentIndex: number = -1
  hasChildren: boolean = false
  collapsed: boolean = false
  /** 本次布局的缩放（渲染层据此算节点框与字号） */
  scale: number = 1
}

export class MindMapLayout {
  width: number = 0
  height: number = 0
  nodes: PlacedNode[] = []
}

/** 节点尺寸与间距（vp）：桌面端优先，手机端后续再单独调 */
export const OUTLINE_NODE_W: number = 220
export const OUTLINE_NODE_H: number = 38
export const OUTLINE_COL_GAP: number = 300
export const OUTLINE_ROW_GAP: number = 52
export const OUTLINE_PAD: number = 24

/**
 * 从"文稿标题 + 扁平标题列表"生成树。
 * 用层级栈决定父子：遇到 level 更小的标题就出栈，回到它的父级。
 */
export function buildOutline(docTitle: string, headings: OutlineHeading[]): OutlineNode[] {
  const root: OutlineNode = new OutlineNode('root', docTitle.trim() === '' ? '未命名文稿' : docTitle,
    0, 0, 0, 0)
  const nodes: OutlineNode[] = [root]
  const stack: number[] = [0]
  for (let i: number = 0; i < headings.length; i++) {
    const h: OutlineHeading = headings[i]
    const level: number = Math.max(1, Math.min(3, h.level))
    while (stack.length > 1 && nodes[stack[stack.length - 1]].level >= level) {
      stack.pop()
    }
    const parentIndex: number = stack[stack.length - 1]
    const node: OutlineNode = new OutlineNode(
      'h' + h.startOffset.toString(), h.title, level, nodes[parentIndex].depth + 1,
      h.startOffset, h.endOffset, '', parentIndex)
    nodes.push(node)
    stack.push(nodes.length - 1)
  }
  return nodes
}

/** 一个标题段落（由宿主从段落模型投影出来，带稳定 id） */
export interface OutlineParagraph {
  id: string
  kind: number
  title: string
  startOffset: number
  endOffset: number
}

/**
 * 从段落模型建树：节点 id = 段落 paraId（不再用偏移），父下标直接写进节点。
 * 这是 M1 之后的主路径；文本版 buildOutline 只作旧数据/回归兜底。
 */
export function buildOutlineFromParagraphs(docTitle: string, paragraphs: OutlineParagraph[]): OutlineNode[] {
  const root: OutlineNode = new OutlineNode('root', docTitle.trim() === '' ? '未命名文稿' : docTitle,
    0, 0, 0, 0, '', -1)
  const nodes: OutlineNode[] = [root]
  const stack: number[] = [0]
  for (let i: number = 0; i < paragraphs.length; i++) {
    const p: OutlineParagraph = paragraphs[i]
    const level: number = Math.max(1, Math.min(3, p.kind))
    while (stack.length > 1 && nodes[stack[stack.length - 1]].level >= level) {
      stack.pop()
    }
    const parentIndex: number = stack[stack.length - 1]
    const node: OutlineNode = new OutlineNode(p.id, p.title, level, nodes[parentIndex].depth + 1,
      p.startOffset, p.endOffset, p.id, parentIndex)
    nodes.push(node)
    stack.push(nodes.length - 1)
  }
  // 一节的范围：到下一个同级或更高级标题之前；没有就用自己的段落结尾
  for (let i: number = nodes.length - 1; i >= 1; i--) {
    let end: number = nodes[i].endOffset
    for (let j: number = i + 1; j < nodes.length; j++) {
      if (nodes[j].level <= nodes[i].level) {
        end = nodes[j].startOffset
        break
      }
    }
    nodes[i].sectionEnd = end
  }
  nodes[0].sectionEnd = nodes.length > 1 ? nodes[nodes.length - 1].sectionEnd : 0
  return nodes
}

/**
 * 树布局：先按"叶子顺序"排 y，内部节点取首末子节点的中点；x = 深度 × 列距。
 * 纯函数，同样的输入永远得到同样的输出（便于回归与快照对比）。
 */
export function layoutOutline(nodes: OutlineNode[], collapsedIds: Set<string> | null = null,
  scale: number = 1): MindMapLayout {
  const layout: MindMapLayout = new MindMapLayout()
  if (nodes.length === 0) {
    return layout
  }
  // 缩放按"尺寸一起缩"处理：节点宽高、行/列间距、内边距同比例，
  // 这样字号随档位变、文字不会挤在固定框里（与思路板"不缩放容器"的结论一致）。
  const z: number = Math.max(0.5, Math.min(2, scale))
  const pad: number = OUTLINE_PAD * z
  const colGap: number = OUTLINE_COL_GAP * z
  const rowGap: number = OUTLINE_ROW_GAP * z
  const nodeW: number = OUTLINE_NODE_W * z
  const nodeH: number = OUTLINE_NODE_H * z
  const parents: number[] = outlineParents(nodes)
  const collapsed: Set<string> = collapsedIds === null ? new Set<string>() : collapsedIds
  // 折叠：自己或任一祖先被折叠 → 本次不参与布局
  const visible: boolean[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    let seen: boolean = true
    let cursor: number = parents[i]
    let guard: number = 0
    while (cursor >= 0 && guard < 256) {
      if (collapsed.has(nodes[cursor].id)) {
        seen = false
        break
      }
      cursor = parents[cursor]
      guard++
    }
    visible.push(seen)
  }
  const children: number[][] = []
  for (let i: number = 0; i < nodes.length; i++) {
    children.push([])
  }
  const hasChildren: boolean[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    hasChildren.push(false)
  }
  for (let i: number = 0; i < nodes.length; i++) {
    if (parents[i] >= 0) {
      hasChildren[parents[i]] = true
      if (visible[i]) {
        children[parents[i]].push(i)
      }
    }
  }
  const ys: number[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    ys.push(0)
  }
  let rows: number = 0
  const place = (index: number): number => {
    const kids: number[] = children[index]
    if (kids.length === 0) {
      ys[index] = pad + rows * rowGap
      rows++
      return ys[index]
    }
    let min: number = 0
    let max: number = 0
    for (let k: number = 0; k < kids.length; k++) {
      const y: number = place(kids[k])
      if (k === 0) {
        min = y
      }
      max = y
    }
    ys[index] = (min + max) / 2
    return ys[index]
  }
  place(0)
  let maxDepth: number = 0
  for (let i: number = 0; i < nodes.length; i++) {
    if (!visible[i]) {
      continue
    }
    const depth: number = nodes[i].depth
    if (depth > maxDepth) {
      maxDepth = depth
    }
    const placed: PlacedNode = new PlacedNode()
    placed.id = nodes[i].id
    placed.title = nodes[i].title
    placed.level = nodes[i].level
    placed.depth = depth
    placed.x = pad + depth * colGap
    placed.y = ys[i]
    placed.startOffset = nodes[i].startOffset
    placed.paraId = nodes[i].paraId
    placed.parentIndex = parents[i]
    placed.hasChildren = hasChildren[i]
    placed.collapsed = collapsed.has(nodes[i].id)
    placed.scale = z
    layout.nodes.push(placed)
  }
  layout.width = pad * 2 + maxDepth * colGap + nodeW
  layout.height = pad * 2 + Math.max(0, rows - 1) * rowGap + nodeH
  return layout
}

/**
 * 一条连线（vp）：布局的纯产物，渲染层只负责画。
 * 思路来自 markmap 的"布局输出图元、渲染器只是消费者"与 simple-mind-map 的
 * "父右缘中点 → 子左缘中点、三次贝塞尔"。
 */
export class OutlineConnector {
  fromX: number = 0
  fromY: number = 0
  toX: number = 0
  toY: number = 0
  /** 三段贝塞尔的中间控制点（水平方向上取两端中点） */
  controlX: number = 0
}

/**
 * 由**已布局节点**算出全部连线。
 * 单独成函数的意义：连线永远跟着节点矩形走，缩放/折叠只要重排就自动一致，
 * 不会出现"线画在旧位置、节点已经挪走"的偏移。
 */
export function outlineConnectors(nodes: PlacedNode[]): OutlineConnector[] {
  const out: OutlineConnector[] = []
  for (let i: number = 1; i < nodes.length; i++) {
    const parentIndex: number = nodes[i].parentIndex
    if (parentIndex < 0 || parentIndex >= nodes.length) {
      continue
    }
    const from: PlacedNode = nodes[parentIndex]
    const to: PlacedNode = nodes[i]
    const connector: OutlineConnector = new OutlineConnector()
    connector.fromX = from.x + OUTLINE_NODE_W * from.scale
    connector.fromY = from.y + OUTLINE_NODE_H * from.scale / 2
    connector.toX = to.x
    connector.toY = to.y + OUTLINE_NODE_H * to.scale / 2
    connector.controlX = (connector.fromX + connector.toX) / 2
    out.push(connector)
  }
  return out
}

/** 父节点索引（-1 = 无父）；连线绘制用，与 buildOutline 的层级规则保持一致 */
export function outlineParents(nodes: OutlineNode[]): number[] {
  const parents: number[] = []
  const stack: number[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    const level: number = nodes[i].level
    while (stack.length > 0 && nodes[stack[stack.length - 1]].level >= level) {
      stack.pop()
    }
    parents.push(stack.length > 0 ? stack[stack.length - 1] : -1)
    stack.push(i)
  }
  return parents
}
