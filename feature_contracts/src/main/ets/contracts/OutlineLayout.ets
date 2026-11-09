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

  constructor(id: string = '', title: string = '', level: number = 0, depth: number = 0,
    startOffset: number = 0, endOffset: number = 0) {
    this.id = id
    this.title = title
    this.level = level
    this.depth = depth
    this.startOffset = startOffset
    this.endOffset = endOffset
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
}

export class MindMapLayout {
  width: number = 0
  height: number = 0
  nodes: PlacedNode[] = []
}

/** 节点尺寸与间距（vp）：桌面端优先，手机端后续再单独调 */
export const OUTLINE_NODE_W: number = 220
export const OUTLINE_NODE_H: number = 38
export const OUTLINE_COL_GAP: number = 268
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
      h.startOffset, h.endOffset)
    nodes.push(node)
    stack.push(nodes.length - 1)
  }
  return nodes
}

/**
 * 树布局：先按"叶子顺序"排 y，内部节点取首末子节点的中点；x = 深度 × 列距。
 * 纯函数，同样的输入永远得到同样的输出（便于回归与快照对比）。
 */
export function layoutOutline(nodes: OutlineNode[]): MindMapLayout {
  const layout: MindMapLayout = new MindMapLayout()
  if (nodes.length === 0) {
    return layout
  }
  const children: number[][] = []
  for (let i: number = 0; i < nodes.length; i++) {
    children.push([])
  }
  const stack: number[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    const level: number = nodes[i].level
    while (stack.length > 0 && nodes[stack[stack.length - 1]].level >= level) {
      stack.pop()
    }
    if (stack.length > 0) {
      children[stack[stack.length - 1]].push(i)
    }
    stack.push(i)
  }
  const ys: number[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    ys.push(0)
  }
  let rows: number = 0
  const place = (index: number): number => {
    const kids: number[] = children[index]
    if (kids.length === 0) {
      ys[index] = OUTLINE_PAD + rows * OUTLINE_ROW_GAP
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
    const depth: number = nodes[i].depth
    if (depth > maxDepth) {
      maxDepth = depth
    }
    const placed: PlacedNode = new PlacedNode()
    placed.id = nodes[i].id
    placed.title = nodes[i].title
    placed.level = nodes[i].level
    placed.depth = depth
    placed.x = OUTLINE_PAD + depth * OUTLINE_COL_GAP
    placed.y = ys[i]
    placed.startOffset = nodes[i].startOffset
    layout.nodes.push(placed)
  }
  layout.width = OUTLINE_PAD * 2 + maxDepth * OUTLINE_COL_GAP + OUTLINE_NODE_W
  layout.height = OUTLINE_PAD * 2 + Math.max(0, rows - 1) * OUTLINE_ROW_GAP + OUTLINE_NODE_H
  return layout
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
