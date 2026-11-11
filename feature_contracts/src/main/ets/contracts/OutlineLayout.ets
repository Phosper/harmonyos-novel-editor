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
  /** 展开方向：1 = 向右侧展开，-1 = 向左侧展开，0 = 根（左右均衡布局才用得上） */
  side: number = 1
  /** 主轴：'x' 左右展开，'y' 上下展开（组织架构/树形表格）；连线端点按它取边 */
  axis: string = OUTLINE_AXIS_X
  /** 一级主题的序号（0 起，根为 -1）：分支配色按它取色，同一分支永远同色 */
  branchIndex: number = -1
  /** 编号（如 2.1.3）：按文档顺序算，不受折叠影响；编号开关打开时才显示 */
  orderLabel: string = ''
  /** 直接子节点数（含被折叠隐藏的）：折叠徽标上显示的数量 */
  childCount: number = 0
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

/** 布局形态：一直向右（逻辑图）／根在中间、一级主题左右分（思维导图）／自上而下（组织架构）／树形表格 */
export const OUTLINE_LAYOUT_RIGHT: string = 'right'
export const OUTLINE_LAYOUT_BALANCED: string = 'balanced'
export const OUTLINE_LAYOUT_DOWN: string = 'down'
export const OUTLINE_LAYOUT_TABLE: string = 'table'

/** 主轴：横向（左右展开）或纵向（上下展开）——连线端点按它取边 */
export const OUTLINE_AXIS_X: string = 'x'
export const OUTLINE_AXIS_Y: string = 'y'

/** 纵向布局的间距：兄弟的水平间距、层与层的垂直间距 */
export const OUTLINE_SIB_GAP: number = 36
export const OUTLINE_LEVEL_GAP: number = 104
/** 树形表格：列宽与行高（比组织架构紧凑，一行一个主题） */
export const OUTLINE_TABLE_COL_W: number = 240
export const OUTLINE_TABLE_ROW_STEP: number = 44

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

/** 一棵子树有几个叶子：左右分配时用它当权重（照 markmap 的 splitBranches） */
function subtreeLeaves(index: number, children: number[][]): number {
  const kids: number[] = children[index]
  if (kids.length === 0) {
    return 1
  }
  let sum: number = 0
  for (let k: number = 0; k < kids.length; k++) {
    sum += subtreeLeaves(kids[k], children)
  }
  return sum
}

/**
 * 每个节点的展开方向：根为 0；一级主题按"叶子权重轮流补到较轻的一侧"分左右（markmap 的思路），
 * 更深层继承父级。只有一侧有节点时退回全向右，避免出现"整棵树长在左边"的怪图。
 */
function assignSides(count: number, children: number[][], mode: string): number[] {
  const sides: number[] = []
  for (let i: number = 0; i < count; i++) {
    sides.push(1)
  }
  if (count === 0) {
    return sides
  }
  sides[0] = 0
  const rootKids: number[] = children[0]
  if (mode !== OUTLINE_LAYOUT_BALANCED || rootKids.length < 2) {
    return sides
  }
  const rootSides: number[] = []
  let rightWeight: number = 0
  let leftWeight: number = 0
  for (let k: number = 0; k < rootKids.length; k++) {
    const w: number = subtreeLeaves(rootKids[k], children)
    if (rightWeight <= leftWeight) {
      rootSides.push(1)
      rightWeight += w
    } else {
      rootSides.push(-1)
      leftWeight += w
    }
  }
  if (rightWeight === 0 || leftWeight === 0) {
    return sides
  }
  const spread = (index: number, side: number): void => {
    sides[index] = side
    const kids: number[] = children[index]
    for (let k: number = 0; k < kids.length; k++) {
      spread(kids[k], side)
    }
  }
  for (let k: number = 0; k < rootKids.length; k++) {
    spread(rootKids[k], rootSides[k])
  }
  return sides
}

/**
 * 树布局：先按"叶子顺序"排 y，内部节点取首末子节点的中点；x = 深度 × 列距。
 * 四种形态：一直向右（逻辑图）／根在中间、一级主题左右分（思维导图）／
 * 自上而下（组织架构）／树形表格（列 = 深度、行 = 文档顺序）。
 * 纯函数，同样的输入永远得到同样的输出（便于回归与快照对比）。
 */
export function layoutOutline(nodes: OutlineNode[], collapsedIds: Set<string> | null = null,
  scale: number = 1, mode: string = OUTLINE_LAYOUT_RIGHT): MindMapLayout {
  const layout: MindMapLayout = new MindMapLayout()
  if (nodes.length === 0) {
    return layout
  }
  // 缩放按"尺寸一起缩"处理：节点宽高、行/列间距、内边距同比例，
  // 这样字号随档位变、文字不会挤在固定框里（与思路板"不缩放容器"的结论一致）。
  const z: number = Math.max(0.5, Math.min(2, scale))
  const prep: OutlineTreePrep = prepareTree(nodes, collapsedIds)
  if (mode === OUTLINE_LAYOUT_DOWN || mode === OUTLINE_LAYOUT_TABLE) {
    return layoutVertical(nodes, prep, z, mode)
  }
  const pad: number = OUTLINE_PAD * z
  const colGap: number = OUTLINE_COL_GAP * z
  const rowGap: number = OUTLINE_ROW_GAP * z
  const nodeW: number = OUTLINE_NODE_W * z
  const nodeH: number = OUTLINE_NODE_H * z
  const children: number[][] = prep.children
  const visible: boolean[] = prep.visible
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
  const sides: number[] = assignSides(nodes.length, children, mode)
  // 根要留出左侧子树占的列：否则左边的节点会跑到 x<0，被滚出可视区
  let maxRightDepth: number = 0
  let maxLeftDepth: number = 0
  for (let i: number = 1; i < nodes.length; i++) {
    if (!visible[i]) {
      continue
    }
    if (sides[i] < 0) {
      if (nodes[i].depth > maxLeftDepth) {
        maxLeftDepth = nodes[i].depth
      }
    } else if (nodes[i].depth > maxRightDepth) {
      maxRightDepth = nodes[i].depth
    }
  }
  const rootX: number = pad + maxLeftDepth * colGap
  for (let i: number = 0; i < nodes.length; i++) {
    if (!visible[i]) {
      continue
    }
    const depth: number = nodes[i].depth
    // 左侧按"根中心镜像"：左缘 x = 根 x − 深度 × 列距，这样两边的列间距与连线长度一致
    const x: number = sides[i] < 0 ? rootX - depth * colGap : rootX + depth * colGap
    pushPlaced(layout, nodes, prep, i, x, ys[i], z, sides[i], OUTLINE_AXIS_X)
  }
  layout.width = rootX + maxRightDepth * colGap + nodeW + pad
  layout.height = pad * 2 + Math.max(0, rows - 1) * rowGap + nodeH
  return layout
}

/** 纵向布局（组织架构 / 树形表格）：x 由列决定，y 由层或序号决定 */
function layoutVertical(nodes: OutlineNode[], prep: OutlineTreePrep, z: number,
  mode: string): MindMapLayout {
  const layout: MindMapLayout = new MindMapLayout()
  const pad: number = OUTLINE_PAD * z
  const nodeW: number = OUTLINE_NODE_W * z
  const nodeH: number = OUTLINE_NODE_H * z
  const sibGap: number = OUTLINE_SIB_GAP * z
  const levelGap: number = (mode === OUTLINE_LAYOUT_TABLE ? OUTLINE_TABLE_ROW_STEP : OUTLINE_LEVEL_GAP) * z
  const colW: number = OUTLINE_TABLE_COL_W * z
  const xs: number[] = []
  const ys: number[] = []
  for (let i: number = 0; i < nodes.length; i++) {
    xs.push(0)
    ys.push(0)
  }
  let maxDepth: number = 0
  for (let i: number = 0; i < nodes.length; i++) {
    if (!prep.visible[i]) {
      continue
    }
    if (nodes[i].depth > maxDepth) {
      maxDepth = nodes[i].depth
    }
  }
  let width: number = 0
  let height: number = 0
  if (mode === OUTLINE_LAYOUT_TABLE) {
    // 表格：一行一个主题（文档顺序），一列一层；比组织架构紧凑，适合"读"不适合"改"
    let row: number = 0
    const emit = (index: number): void => {
      xs[index] = pad + nodes[index].depth * colW
      ys[index] = pad + row * levelGap
      row++
      const kids: number[] = prep.children[index]
      for (let k: number = 0; k < kids.length; k++) {
        emit(kids[k])
      }
    }
    emit(0)
    width = pad * 2 + maxDepth * colW + nodeW
    height = pad * 2 + Math.max(0, row - 1) * levelGap + nodeH
  } else {
    // 组织架构：子树按叶子宽度占位，父节点居中在子节点上方
    const widths: number[] = []
    for (let i: number = 0; i < nodes.length; i++) {
      widths.push(nodeW)
    }
    const measure = (index: number): number => {
      const kids: number[] = prep.children[index]
      if (kids.length === 0) {
        widths[index] = nodeW
        return nodeW
      }
      let sum: number = 0
      for (let k: number = 0; k < kids.length; k++) {
        sum += measure(kids[k])
        if (k > 0) {
          sum += sibGap
        }
      }
      widths[index] = Math.max(nodeW, sum)
      return widths[index]
    }
    const place = (index: number, left: number): void => {
      ys[index] = pad + nodes[index].depth * levelGap
      const kids: number[] = prep.children[index]
      if (kids.length === 0) {
        xs[index] = left
        return
      }
      let cursor: number = left
      for (let k: number = 0; k < kids.length; k++) {
        place(kids[k], cursor)
        cursor += widths[kids[k]] + sibGap
      }
      xs[index] = left + (widths[index] - nodeW) / 2
    }
    measure(0)
    place(0, pad)
    width = widths[0] + pad * 2
    height = pad * 2 + maxDepth * levelGap + nodeH
  }
  for (let i: number = 0; i < nodes.length; i++) {
    if (!prep.visible[i]) {
      continue
    }
    pushPlaced(layout, nodes, prep, i, xs[i], ys[i], z, 1, OUTLINE_AXIS_Y)
  }
  layout.width = width
  layout.height = height
  return layout
}

/** 把一颗树在布局前的公共信息准备好：父子、可见性、分支色号、编号 */
class OutlineTreePrep {
  parents: number[] = []
  visible: boolean[] = []
  children: number[][] = []
  childrenAll: number[][] = []
  hasChildren: boolean[] = []
  branchIndex: number[] = []
  labels: string[] = []
  collapsed: Set<string> = new Set<string>()
}

function prepareTree(nodes: OutlineNode[], collapsedIds: Set<string> | null): OutlineTreePrep {
  const prep: OutlineTreePrep = new OutlineTreePrep()
  prep.parents = outlineParents(nodes)
  prep.collapsed = collapsedIds === null ? new Set<string>() : collapsedIds
  // 折叠：自己或任一祖先被折叠 → 本次不参与布局
  for (let i: number = 0; i < nodes.length; i++) {
    let seen: boolean = true
    let cursor: number = prep.parents[i]
    let guard: number = 0
    while (cursor >= 0 && guard < 256) {
      if (prep.collapsed.has(nodes[cursor].id)) {
        seen = false
        break
      }
      cursor = prep.parents[cursor]
      guard++
    }
    prep.visible.push(seen)
    prep.children.push([])
    prep.childrenAll.push([])
    prep.hasChildren.push(false)
    prep.branchIndex.push(-1)
    prep.labels.push('')
  }
  for (let i: number = 0; i < nodes.length; i++) {
    const parent: number = prep.parents[i]
    if (parent >= 0) {
      prep.hasChildren[parent] = true
      prep.childrenAll[parent].push(i)
      if (prep.visible[i]) {
        prep.children[parent].push(i)
      }
    }
  }
  // 分支配色与编号：沿树走一遍（深度 ≤ 3，递归不成问题）
  const walk = (index: number, branch: number, prefix: string): void => {
    prep.branchIndex[index] = branch
    prep.labels[index] = prefix
    const kids: number[] = prep.childrenAll[index]
    for (let k: number = 0; k < kids.length; k++) {
      const step: string = (k + 1).toString()
      walk(kids[k], branch, prefix === '' ? step : prefix + '.' + step)
    }
  }
  const tops: number[] = prep.childrenAll[0]
  for (let k: number = 0; k < tops.length; k++) {
    walk(tops[k], k, (k + 1).toString())
  }
  return prep
}

/** 产出一个已布局节点（两种布局只差 x/y/方向，其余字段一样） */
function pushPlaced(layout: MindMapLayout, nodes: OutlineNode[], prep: OutlineTreePrep, index: number,
  x: number, y: number, scale: number, side: number, axis: string): void {
  const node: OutlineNode = nodes[index]
  const placed: PlacedNode = new PlacedNode()
  placed.id = node.id
  placed.title = node.title
  placed.level = node.level
  placed.depth = node.depth
  placed.x = x
  placed.y = y
  placed.startOffset = node.startOffset
  placed.paraId = node.paraId
  placed.parentIndex = prep.parents[index]
  placed.hasChildren = prep.hasChildren[index]
  placed.collapsed = prep.collapsed.has(node.id)
  placed.side = side
  placed.axis = axis
  placed.branchIndex = prep.branchIndex[index]
  placed.orderLabel = prep.labels[index]
  placed.childCount = prep.childrenAll[index].length
  placed.scale = scale
  layout.nodes.push(placed)
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
  /** 纵向布局用的控制点 y（横向布局留 0） */
  controlY: number = 0
  /** 主轴：'x' = 左右展开的连线，'y' = 上下展开的连线 */
  axis: string = OUTLINE_AXIS_X
  /** 所属一级分支（取色用）；根的直接子节点起算，0 起 */
  branchIndex: number = -1
  /** 子节点深度（1 起）：渲染层据此做"线条渐细" */
  depth: number = 1
  /** 两端的段落身份：专注模式据此判断"这条线在不在当前分支里" */
  fromParaId: string = ''
  toParaId: string = ''
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
    connector.axis = to.axis
    connector.depth = to.depth
    connector.branchIndex = to.branchIndex
    connector.fromParaId = from.paraId
    connector.toParaId = to.paraId
    if (to.axis === OUTLINE_AXIS_Y) {
      // 上下展开：父下沿中点 → 子上沿中点
      connector.fromX = from.x + OUTLINE_NODE_W * from.scale / 2
      connector.fromY = from.y + OUTLINE_NODE_H * from.scale
      connector.toX = to.x + OUTLINE_NODE_W * to.scale / 2
      connector.toY = to.y
      connector.controlX = (connector.fromX + connector.toX) / 2
      connector.controlY = (connector.fromY + connector.toY) / 2
      out.push(connector)
      continue
    }
    // 朝左展开时端点镜像：父左缘 → 子右缘；朝右时是父右缘 → 子左缘
    if (to.side < 0) {
      connector.fromX = from.x
      connector.toX = to.x + OUTLINE_NODE_W * to.scale
    } else {
      connector.fromX = from.x + OUTLINE_NODE_W * from.scale
      connector.toX = to.x
    }
    connector.fromY = from.y + OUTLINE_NODE_H * from.scale / 2
    connector.toY = to.y + OUTLINE_NODE_H * to.scale / 2
    connector.controlX = (connector.fromX + connector.toX) / 2
    out.push(connector)
  }
  return out
}

/**
 * 一段连线的"可直接渲染"形态：最小包围盒 + 相对该盒的采样点（全部 vp）。
 *
 * 为什么不再用 Path / Canvas 画：
 *  - `Path().commands()` 的单位是 **px**（SDK 声明里写死为 px），与布局的 vp 坐标混用会整体缩小/错位；
 *  - `Canvas` 是一块独立绘制面，尺寸与就绪时机都不在节点那一帧里，缩放/窗口变化时容易出现
 *    "节点已经挪走、线还停在旧坐标"。
 * `Polyline().points()` 的单位是 **vp**，而且它和节点一样是普通组件——同一套坐标、同一次布局，
 * 只要坐标算对就不存在错位。
 */
export class OutlineWire {
  /** 包围盒左上角（vp，地图坐标系） */
  originX: number = 0
  originY: number = 0
  width: number = 1
  height: number = 1
  /** 采样点（vp，相对 originX/originY）：[x, y] 序列，Polyline 直接消费 */
  points: number[][] = []
  /** 所属一级分支（渲染层据此取色） */
  branchIndex: number = -1
  /** 子节点深度（1 起）：线条渐细按它算粗细 */
  depth: number = 1
  /** 子节点的段落身份：专注模式据此淡化不属于当前分支的线 */
  toParaId: string = ''
  /** 连线在子节点那一端的绝对坐标与切线角（弧度）：画箭头/圆点用 */
  endX: number = 0
  endY: number = 0
  endAngle: number = 0
}

/** 描边留白：Polyline 以路径为中心描边，留够半个笔宽，别被自己的包围盒裁掉 */
export const OUTLINE_WIRE_PAD: number = 2
/** 每条连线的采样段数：12 段在 80vp 的列间距上已经看不出折线 */
export const OUTLINE_WIRE_STEPS: number = 12
/** 连线画法：平滑曲线（曲线肘）／折线（先横后竖再横，XMind 的"折线"） */
export const OUTLINE_WIRE_CURVE: string = 'curve'
export const OUTLINE_WIRE_ELBOW: string = 'elbow'

/** 三次贝塞尔按 t 取值（控制点都在端点水平中线上，所以 x 单调、y 夹在两端之间） */
function cubicAt(p0: number, p1: number, p2: number, p3: number, t: number): number {
  const u: number = 1 - t
  return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
}

/**
 * 连线图元 → 可渲染图元（包围盒 + 采样点）。纯函数，可在 Node 里回归：
 * 采样点必须全部落在包围盒内，否则组件会把线裁掉。
 */
export function outlineWires(connectors: OutlineConnector[], steps: number = OUTLINE_WIRE_STEPS,
  style: string = OUTLINE_WIRE_CURVE): OutlineWire[] {
  const out: OutlineWire[] = []
  const n: number = Math.max(2, Math.floor(steps))
  for (let i: number = 0; i < connectors.length; i++) {
    const c: OutlineConnector = connectors[i]
    const minX: number = Math.min(c.fromX, c.toX)
    const maxX: number = Math.max(c.fromX, c.toX)
    const minY: number = Math.min(c.fromY, c.toY)
    const maxY: number = Math.max(c.fromY, c.toY)
    const wire: OutlineWire = new OutlineWire()
    wire.branchIndex = c.branchIndex
    wire.depth = c.depth
    wire.toParaId = c.toParaId
    wire.originX = minX - OUTLINE_WIRE_PAD
    wire.originY = minY - OUTLINE_WIRE_PAD
    wire.width = Math.max(1, maxX - minX + OUTLINE_WIRE_PAD * 2)
    wire.height = Math.max(1, maxY - minY + OUTLINE_WIRE_PAD * 2)
    const vertical: boolean = c.axis === OUTLINE_AXIS_Y
    if (style === OUTLINE_WIRE_ELBOW) {
      // 折线：父缘 → 中缝 → 中缝 → 子缘（朝左/朝上展开时方向自然反向）
      wire.points.push([c.fromX - wire.originX, c.fromY - wire.originY])
      if (vertical) {
        wire.points.push([c.fromX - wire.originX, c.controlY - wire.originY])
        wire.points.push([c.toX - wire.originX, c.controlY - wire.originY])
      } else {
        wire.points.push([c.controlX - wire.originX, c.fromY - wire.originY])
        wire.points.push([c.controlX - wire.originX, c.toY - wire.originY])
      }
      wire.points.push([c.toX - wire.originX, c.toY - wire.originY])
      wire.endX = c.toX
      wire.endY = c.toY
      if (vertical) {
        wire.endAngle = c.toY >= c.fromY ? Math.PI / 2 : -Math.PI / 2
      } else {
        wire.endAngle = c.toX >= c.fromX ? 0 : Math.PI
      }
      out.push(wire)
      continue
    }
    for (let k: number = 0; k <= n; k++) {
      const t: number = k / n
      let x: number = 0
      let y: number = 0
      if (vertical) {
        // 控制点 (fromX, controlY) 与 (toX, controlY)：先竖着出去，再拐到子的中线
        x = cubicAt(c.fromX, c.fromX, c.toX, c.toX, t) - wire.originX
        y = cubicAt(c.fromY, c.controlY, c.controlY, c.toY, t) - wire.originY
      } else {
        x = cubicAt(c.fromX, c.controlX, c.controlX, c.toX, t) - wire.originX
        y = cubicAt(c.fromY, c.fromY, c.toY, c.toY, t) - wire.originY
      }
      wire.points.push([x, y])
    }
    // 末端切线按控制点算（采样弦会带上最后一段的抖动，箭头会歪）：
    // 横向布局指向左右，纵向布局指向上下
    wire.endX = c.toX
    wire.endY = c.toY
    wire.endAngle = vertical ? (c.toY >= c.fromY ? Math.PI / 2 : -Math.PI / 2)
      : (c.toX >= c.fromX ? 0 : Math.PI)
    out.push(wire)
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
