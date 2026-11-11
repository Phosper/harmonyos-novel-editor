// 文稿绑定导图（结构包）
//
// 数据：宿主 publish 一份 OutlineSnapshot（节点带稳定 paraId）；本页只读快照、只发命令。
// 编辑：改名/新建/升降级/删除/移动都发 OutlineCommand 给 core_runtime，宿主改正文后回传新快照。
// 边界：本包不 import entry、不碰正文；折叠与选中是视图态。
import {
  MindMapLayout, OutlineSnapshot, PlacedNode, OutlineCommand, OutlineCommandKind, OutlineWire,
  OUTLINE_NODE_H, OUTLINE_NODE_W, OUTLINE_LAYOUT_BALANCED, OUTLINE_LAYOUT_RIGHT,
  OUTLINE_LAYOUT_DOWN, OUTLINE_LAYOUT_TABLE,
  OUTLINE_WIRE_STEPS, OUTLINE_WIRE_CURVE, OUTLINE_WIRE_ELBOW,
  layoutOutline, outlineConnectors, outlineWires,
  OutlineExtras, OutlineExtraCommand, OutlineSummaryBox, OutlineRelationWire, OutlineNodeStyle,
  OutlineBoundaryBox, outlineBoundaryBoxes,
  OUTLINE_EXTRA_ADD_SUMMARY, OUTLINE_EXTRA_REMOVE_SUMMARY,
  OUTLINE_EXTRA_ADD_RELATION, OUTLINE_EXTRA_REMOVE_RELATION,
  OUTLINE_EXTRA_ADD_BOUNDARY, OUTLINE_EXTRA_REMOVE_BOUNDARY, OUTLINE_EXTRA_SET_NODE_STYLE,
  OUTLINE_SHAPE_CARD, OUTLINE_SHAPE_PILL, OUTLINE_SHAPE_PLAIN,
  OUTLINE_SUMMARY_TEXT_W, findNodeStyle, isBlankNodeStyle, toggleMarker, nodeLabelY,
  outlineSummaryBoxes, outlineRelationWires, summaryRangeOf
} from 'feature_contracts'
import { outlineService } from 'core_runtime'

/** 主题色由宿主注入：结构包不认识 entry 的 DesignTokens */
export class StructureTheme {
  bg: string = '#FFFFFF'
  card: string = '#FFFFFF'
  text: string = '#1C1C1E'
  sub: string = '#6E6E73'
  divider: string = '#ECECEE'
  brand: string = '#1C1C1E'
  onBrand: string = '#FFFFFF'
  danger: string = '#D70015'
  /** 单色连线 */
  line: string = '#C7C7CC'
  /** 分支配色（按一级主题循环取色，同分支永远同色） */
  branches: string[] = ['#D2543F', '#3FA37A', '#3F76C4', '#8B5CD6', '#C99A2E', '#3E9EAE']
}

const KEY_ESCAPE: number = 2070
const KEY_ENTER: number = 2054
const KEY_NUMPAD_ENTER: number = 2116
const KEY_TAB: number = 2049
const KEY_SPACE: number = 2050
const KEY_FORWARD_DEL: number = 2071
const KEY_DPAD_LEFT: number = 2014
const KEY_DPAD_RIGHT: number = 2015
const KEY_DPAD_UP: number = 2012
const KEY_DPAD_DOWN: number = 2013
const KEY_F2: number = 2092
const KEY_0: number = 2000
const KEY_MINUS: number = 2057
const KEY_EQUALS: number = 2058
const KEY_PLUS: number = 2066
const KEY_Y: number = 2037
const KEY_Z: number = 2044
const RENAME_INPUT_ID: string = 'structure-rename-input'
const EXTRA_INPUT_ID: string = 'structure-extra-input'
const NOTE_INPUT_ID: string = 'structure-note-input'
/** 可选的节点标记（图标）：直接存字符，没有字体/图片依赖 */
const NODE_MARKERS: string[] = ['⭐', '❗', '❓', '✅', '🔥']
/** 节点填充色板：与分支配色同一套，整张图看起来是一家的 */
const NODE_FILLS: string[] = ['#D2543F', '#3FA37A', '#3F76C4', '#8B5CD6', '#C99A2E', '#3E9EAE']

@ComponentV2
export struct StructurePage {
  @Param theme: StructureTheme = new StructureTheme()
  @Param docTitle: string = ''
  /** 原生窗口三键区宽度：整页头部的「关闭」要避开，否则被三键压住 */
  @Param captionInset: number = 0
  @Event onClose: () => void = () => {}

  @Local placed: PlacedNode[] = []
  @Local mapW: number = 0
  @Local mapH: number = 0
  @Local empty: boolean = true
  @Local topicCount: number = 0
  /** 缩放档位（0.55–1.8）：节点尺寸、间距、字号同比例 */
  @Local zoom: number = 1
  /** 键盘选中的节点下标（-1 = 无） */
  @Local selectedIndex: number = -1
  @Local viewW: number = 0
  @Local viewH: number = 0
  /** 就地改名 */
  @Local renaming: boolean = false
  @Local renameText: string = ''
  /** 折叠集合（按 paraId 存；视图态，不写正文、不进版本号） */
  @Local collapsedIds: string[] = []
  /** 布局形态：左右均衡 / 一直向右 / 组织架构（向下）/ 树形表格 */
  @Local layoutMode: string = OUTLINE_LAYOUT_BALANCED
  /** 连线是否按层级渐细（XMind 用线的粗细表达重要性） */
  @Local thinLines: boolean = true
  /** 连线画法（曲线 / 折线） */
  @Local wireStyle: string = OUTLINE_WIRE_CURVE
  /** 连线是否按一级分支着色 */
  @Local colorByBranch: boolean = true
  /** 是否显示层级编号（2.1.3） */
  @Local showNumbers: boolean = false
  /** 节点外观：card = 白卡片，line = 线框，plain = 只有文字 */
  @Local nodeStyle: string = 'card'
  /** 右侧样式面板 */
  @Local styleOpen: boolean = true

  /**
   * 附加信息（M5）：概要的括号图元与关系线的曲线图元。
   * 它们是**视图数据**，来自侧车（core_runtime 中转），渲染完就丢，不做持久化。
   */
  @Local summaryBoxes: OutlineSummaryBox[] = []
  @Local relationWires: OutlineRelationWire[] = []
  @Local boundaryBoxes: OutlineBoundaryBox[] = []
  /** 节点级样式（只存改过的段落）：渲染时按 paraId 查，查不到就用全局设置 */
  @Local nodeStyles: OutlineNodeStyle[] = []
  /** 连线在子节点那一端的样式（无 / 圆点 / 箭头） */
  @Local endStyle: string = 'none'
  /** 多选：概要需要"一组兄弟主题"，所以选中不再是单值 */
  @Local selectedIds: string[] = []
  /**
   * 多选模式：Ctrl+单击是快路，但触屏/部分设备拿不到修饰键状态，
   * 这一个开关保证「概要」在任何输入方式下都用得了。
   */
  @Local multiSelect: boolean = false
  /** 专注模式（ZEN）：只突出当前分支，其余淡化；纯视图 */
  @Local zenMode: boolean = false
  /** 专注的段落身份（'' = 还没选，按根算） */
  private focusParaId: string = ''
  /** 当前分支里的段落集合（数组判存，避免 Set 的可观测问题） */
  @Local focusIds: string[] = []
  /** 缩略图（右下角小窗）：整张图的形状一眼可见 */
  @Local showMinimap: boolean = false
  /** 演说模式：按主题顺序逐个聚焦 */
  @Local presentMode: boolean = false
  @Local presentIndex: number = 0
  /** 滚动控制器：演说要能把当前主题滚到视口中间 */
  private hScroller: Scroller = new Scroller()
  private vScroller: Scroller = new Scroller()
  /** 备注抽屉：正在看/写哪一节的备注（'' = 关） */
  @Local noteParaId: string = ''
  @Local noteText: string = ''
  /** 概要/关系线的文字输入浮层：'' = 关，'summary' / 'relation' = 开 */
  @Local extraMode: string = ''
  @Local extraText: string = ''
  @Local extraX: number = 0
  @Local extraY: number = 0
  /** 浮层提交时用的两个端点（概要是首末成员，关系线是起止节点） */
  private extraPending: string[] = []

  /**
   * 连线图元（包围盒 + 采样点）：渲染层只摆一个 Polyline，不自己算坐标。
   *
   * 用 Polyline 而不是 Canvas / Path 的原因（两次真机偏移的教训）：
   *  - `Path().commands()` 的单位是 **px**（SDK 声明写死 px），与布局的 vp 混用会整体缩小；
   *  - `Canvas` 是独立绘制面，尺寸与就绪时机都晚于节点布局，缩放的瞬间"节点已经挪走、线还在旧坐标"。
   * `Polyline.points()` 的单位是 **vp**，与节点的 `.position()` 同一套坐标、同一次布局，不存在时间差。
   */
  @Local wires: OutlineWire[] = []
  /**
   * 布局版本号：每次重排 +1 并拼进 ForEach 的键。
   * 节点身份键（paraId）在缩放/重排时是不变的，只用它 ArkUI 会复用旧子组件、不再执行构建函数，
   * 于是节点停在旧位置——这正是"节点不动、只有线动了"的根源。
   */
  @Local layoutRev: number = 0

  aboutToAppear(): void {
    this.load()
  }

  private load(): void {
    const snapshot: OutlineSnapshot | null = outlineService().current()
    if (snapshot === null) {
      this.empty = true
      this.topicCount = 0
      return
    }
    this.applySnapshot(snapshot)
  }

  /** 用一份快照重排（首次打开与每次命令成功后都走这里） */
  private applySnapshot(snapshot: OutlineSnapshot): void {
    if (snapshot.nodes.length <= 1) {
      this.empty = true
      this.topicCount = 0
      this.placed = []
      this.wires = []
      this.summaryBoxes = []
      this.relationWires = []
      this.boundaryBoxes = []
      this.selectedIds = []
      this.mapW = 0
      this.mapH = 0
      this.selectedIndex = -1
      this.layoutRev = this.layoutRev + 1
      return
    }
    const selectedParaId: string = this.selectedParaId()
    const collapsedSet: Set<string> = new Set<string>()
    for (let i: number = 0; i < this.collapsedIds.length; i++) {
      collapsedSet.add(this.collapsedIds[i])
    }
    const layout: MindMapLayout = layoutOutline(snapshot.nodes, collapsedSet, this.zoom, this.layoutMode)
    this.placed = layout.nodes
    this.mapW = layout.width
    this.mapH = layout.height
    this.topicCount = layout.nodes.length - 1
    this.wires = outlineWires(outlineConnectors(this.placed), OUTLINE_WIRE_STEPS, this.wireStyle)
    this.layoutRev = this.layoutRev + 1
    this.empty = false
    this.refreshExtras()
    this.rebuildFocus()
    // 命令后重建时尽量把选中保持在同一个节点上（段落身份不变，索引会变）
    if (selectedParaId !== '') {
      let kept: number = -1
      for (let i: number = 0; i < this.placed.length; i++) {
        if (this.placed[i].paraId === selectedParaId) {
          kept = i
          break
        }
      }
      this.selectedIndex = kept
    }
    if (this.selectedIndex >= this.placed.length) {
      this.selectedIndex = -1
    }
  }

  // ===== 附加信息（概要 / 关系线）：只读侧车，改之前先确认端点还在 ——

  /** 用当前布局重新算一遍概要括号与关系线（宿主每次回传新副本后都要走） */
  private refreshExtras(): void {
    const extras: OutlineExtras = outlineService().currentExtras()
    this.summaryBoxes = outlineSummaryBoxes(this.placed, extras.summaries)
    this.relationWires = outlineRelationWires(this.placed, extras.relations)
    this.boundaryBoxes = outlineBoundaryBoxes(this.placed, extras.boundaries)
    this.nodeStyles = extras.nodeStyles
  }

  /**
   * 重算"当前分支"：专注节点 + 它的祖先链 + 它的整棵子树。
   * 纯视图，不进快照、不改正文。
   */
  private rebuildFocus(): void {
    if (!this.zenMode) {
      this.focusIds = []
      return
    }
    let anchor: number = -1
    for (let i: number = 0; i < this.placed.length; i++) {
      if (this.placed[i].paraId === this.focusParaId) {
        anchor = i
        break
      }
    }
    if (anchor < 0) {
      // 专注目标没了（被删/被折叠）：退回根，别把整张图淡成看不见
      this.focusParaId = ''
      anchor = 0
    }
    const keep: string[] = []
    const push = (index: number): void => {
      if (index < 0 || index >= this.placed.length) {
        return
      }
      const id: string = this.placed[index].paraId
      if (id !== '' && keep.indexOf(id) < 0) {
        keep.push(id)
      }
    }
    // 祖先链
    let cursor: number = anchor
    let guard: number = 0
    while (cursor >= 0 && guard < 256) {
      push(cursor)
      cursor = this.placed[cursor].parentIndex
      guard++
    }
    // 子树（placed 里只有可见节点，被折叠的自然不在其中）
    const collect = (index: number): void => {
      push(index)
      for (let i: number = 0; i < this.placed.length; i++) {
        if (this.placed[i].parentIndex === index) {
          collect(i)
        }
      }
    }
    collect(anchor)
    this.focusIds = keep
  }

  /** 一个节点在当前视图里的不透明度：专注模式下，分支外的一律淡化 */
  private focusOpacity(paraId: string): number {
    if (!this.zenMode || paraId === '') {
      return 1
    }
    return this.focusIds.indexOf(paraId) >= 0 ? 1 : 0.18
  }

  /** 进入/退出专注：进入时以当前选中（否则根）为焦点，并收起样式面板 */
  private toggleZen(): void {
    this.zenMode = !this.zenMode
    if (this.zenMode) {
      this.focusParaId = this.selectedParaId()
      this.styleOpen = false
    } else {
      this.focusParaId = ''
    }
    this.rebuildFocus()
    this.layoutRev = this.layoutRev + 1
  }

  /** 撤销/重做：结构改动都在正文撤销栈里，这里只是转一道手 */
  private dispatchHistory(redo: boolean): void {
    const next: OutlineSnapshot | null = outlineService().dispatchHistory(redo)
    if (next === null) {
      this.toast(redo ? '没有可重做的改动' : '没有可撤销的改动')
      return
    }
    this.selectedIds = []
    this.applySnapshot(next)
  }

  /** 演说步骤：先根、再按文档顺序深度优先走一遍（和"讲一遍结构"的顺序一致） */
  private presentSteps(): string[] {
    const out: string[] = []
    const walk = (index: number): void => {
      out.push(this.placed[index].paraId)
      for (let i: number = 0; i < this.placed.length; i++) {
        if (this.placed[i].parentIndex === index) {
          walk(i)
        }
      }
    }
    if (this.placed.length > 0) {
      walk(0)
    }
    return out
  }

  private enterPresent(): void {
    if (this.placed.length <= 1) {
      this.toast('先写几个标题再来演说')
      return
    }
    this.presentMode = true
    this.styleOpen = false
    this.zenMode = true
    this.presentIndex = 0
    this.goToStep(0)
  }

  private exitPresent(): void {
    this.presentMode = false
    this.zenMode = false
    this.focusParaId = ''
    this.rebuildFocus()
    this.layoutRev = this.layoutRev + 1
  }

  /** 走到第 n 步：聚焦它、重排（淡化其余），等布局落定再把镜头挪过去 */
  private goToStep(index: number): void {
    const steps: string[] = this.presentSteps()
    if (steps.length === 0) {
      return
    }
    this.presentIndex = Math.max(0, Math.min(steps.length - 1, index))
    const paraId: string = steps[this.presentIndex]
    this.focusParaId = paraId
    this.selectedIndex = -1
    this.selectedIds = paraId === '' ? [] : [paraId]
    this.rebuildFocus()
    this.layoutRev = this.layoutRev + 1
    // 布局（缩放/淡化）落定后才好算偏移；40ms 足够一帧
    setTimeout(() => {
      this.centerOn(paraId)
    }, 40)
  }

  /** 把某个主题滚到视口中间（内容坐标与滚动偏移同一套 vp） */
  private centerOn(paraId: string): void {
    let node: PlacedNode | undefined = undefined
    for (let i: number = 0; i < this.placed.length; i++) {
      if (this.placed[i].paraId === paraId) {
        node = this.placed[i]
        break
      }
    }
    if (node === undefined && this.placed.length > 0) {
      node = this.placed[0]
    }
    if (node === undefined) {
      return
    }
    const headerH: number = 64
    const viewportW: number = this.viewW > 0 ? this.viewW : 800
    const viewportH: number = (this.viewH > 0 ? this.viewH : 600) - headerH
    const centerX: number = node.x + OUTLINE_NODE_W * node.scale / 2
    const centerY: number = node.y + OUTLINE_NODE_H * node.scale / 2
    const maxX: number = Math.max(0, this.mapW - viewportW)
    const maxY: number = Math.max(0, this.mapH - viewportH)
    try {
      this.hScroller.scrollTo({
        xOffset: Math.max(0, Math.min(maxX, centerX - viewportW / 2)),
        yOffset: 0,
        animation: true
      })
      this.vScroller.scrollTo({
        xOffset: 0,
        yOffset: Math.max(0, Math.min(maxY, centerY - viewportH / 2)),
        animation: true
      })
    } catch (e) {
      // 滚动失败不影响演说（镜头不动而已）
    }
  }

  /** 缩略图缩放比：整张图塞进 150×104 的小窗 */
  private miniScale(): number {
    if (this.mapW <= 0 || this.mapH <= 0) {
      return 0.01
    }
    return Math.min(150 / this.mapW, 104 / this.mapH)
  }

  private styleOf(paraId: string): OutlineNodeStyle | undefined {
    return findNodeStyle(this.nodeStyles, paraId)
  }

  /** 深色填充上用白字，浅色填充上用深字（否则彩色主题读不出字） */
  private readableOn(fill: string): string {
    if (fill.length < 7) {
      return this.theme.text
    }
    const r: number = parseInt(fill.substring(1, 3), 16)
    const g: number = parseInt(fill.substring(3, 5), 16)
    const b: number = parseInt(fill.substring(5, 7), 16)
    if (isNaN(r) || isNaN(g) || isNaN(b)) {
      return this.theme.text
    }
    // 相对亮度（sRGB 近似）：0.299/0.587/0.114 的加权
    const luma: number = (r * 0.299 + g * 0.587 + b * 0.114) / 255
    return luma > 0.6 ? this.theme.text : this.theme.onBrand
  }

  /** 把选中节点的样式整份发下去（侧车，不碰正文） */
  private pushNodeStyle(style: OutlineNodeStyle): void {
    const command: OutlineExtraCommand = new OutlineExtraCommand(OUTLINE_EXTRA_SET_NODE_STYLE, '', '', '', '')
    command.style = style
    const next: OutlineExtras | null = outlineService().dispatchExtra(command)
    if (next === null) {
      this.toast('样式没存上（先在正文里保存一下再试）')
      return
    }
    this.layoutRev = this.layoutRev + 1
    this.refreshExtras()
  }

  /** 取选中节点"当前生效"的样式副本，供面板改一项后整体提交 */
  private selectedStyleCopy(): OutlineNodeStyle {
    return this.styleCopyOf(this.selectedParaId())
  }

  private styleCopyOf(paraId: string): OutlineNodeStyle {
    const existing: OutlineNodeStyle | undefined = this.styleOf(paraId)
    const style: OutlineNodeStyle = new OutlineNodeStyle(paraId)
    if (existing !== undefined) {
      style.shape = existing.shape
      style.fill = existing.fill
      style.bold = existing.bold
      style.label = existing.label
      for (let i: number = 0; i < existing.markers.length; i++) {
        style.markers.push(existing.markers[i])
      }
    }
    return style
  }

  private selectedShape(): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(this.selectedParaId())
    return style === undefined ? '' : style.shape
  }

  private selectedFill(): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(this.selectedParaId())
    return style === undefined ? '' : style.fill
  }

  private selectedBold(): boolean {
    const style: OutlineNodeStyle | undefined = this.styleOf(this.selectedParaId())
    return style === undefined ? false : style.bold
  }

  private selectedLabel(): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(this.selectedParaId())
    return style === undefined ? '' : style.label
  }

  private selectedHasMarker(marker: string): boolean {
    const style: OutlineNodeStyle | undefined = this.styleOf(this.selectedParaId())
    if (style === undefined) {
      return false
    }
    return style.markers.indexOf(marker) >= 0
  }

  private hasOneSelection(): boolean {
    return this.selectedIds.length <= 1 && this.selectedParaId() !== ''
  }

  private markersText(style: OutlineNodeStyle | undefined): string {
    if (style === undefined) {
      return ''
    }
    let out: string = ''
    for (let i: number = 0; i < style.markers.length; i++) {
      out = out + style.markers[i]
    }
    return out
  }

  private isSelected(node: PlacedNode, index: number): boolean {
    if (this.selectedIndex === index) {
      return true
    }
    return node.paraId !== '' && this.selectedIds.indexOf(node.paraId) >= 0
  }

  /** Ctrl+单击：加选/减选（多选只服务概要，不改任何正文） */
  private toggleSelect(index: number): void {
    if (index < 0 || index >= this.placed.length) {
      return
    }
    const paraId: string = this.placed[index].paraId
    if (paraId === '') {
      return
    }
    this.selectedIndex = index
    const next: string[] = []
    let found: boolean = false
    for (let i: number = 0; i < this.selectedIds.length; i++) {
      if (this.selectedIds[i] === paraId) {
        found = true
      } else {
        next.push(this.selectedIds[i])
      }
    }
    if (!found) {
      next.push(paraId)
    }
    this.selectedIds = next
    this.renaming = false
  }

  /** 多选开关（关掉时把选中收回到当前节点） */
  private toggleMultiSelect(): void {
    this.multiSelect = !this.multiSelect
    if (!this.multiSelect) {
      const paraId: string = this.selectedParaId()
      this.selectedIds = paraId === '' ? [] : [paraId]
    }
  }

  /** 概要多选是否已经够用（同父、至少两个、中间没有别的分支） */
  private summaryReady(): boolean {
    return summaryRangeOf(this.placed, this.selectedIds).length === 2
  }

  private relationReady(): boolean {
    return this.selectedIds.length === 2 && this.selectedIds[0] !== this.selectedIds[1]
  }

  /** 打开"新建概要"浮层：文字在浮层里填，端点此时就定下来（首末成员） */
  private openSummaryEditor(): void {
    const range: string[] = summaryRangeOf(this.placed, this.selectedIds)
    if (range.length !== 2) {
      this.toast('概要要选同一层里的两节以上')
      return
    }
    this.extraPending = range
    this.extraMode = 'summary'
    this.extraText = ''
    const anchor: PlacedNode | undefined = this.selectedNode()
    this.extraX = anchor === undefined ? 24 : anchor.x
    this.extraY = anchor === undefined ? 24 : anchor.y + OUTLINE_NODE_H * this.zoom + 8
    this.focusExtraInput()
  }

  /** 打开"新建外框"浮层：端点与概要一致（同层的一段），标题可留空 */
  private openBoundaryEditor(): void {
    const range: string[] = summaryRangeOf(this.placed, this.selectedIds)
    if (range.length !== 2) {
      this.toast('外框要圈住同一层里的两节以上')
      return
    }
    this.extraPending = range
    this.extraMode = 'boundary'
    this.extraText = ''
    const anchor: PlacedNode | undefined = this.selectedNode()
    this.extraX = anchor === undefined ? 24 : anchor.x
    this.extraY = anchor === undefined ? 24 : anchor.y + OUTLINE_NODE_H * this.zoom + 8
    this.focusExtraInput()
  }

  private openRelationEditor(): void {
    if (!this.relationReady()) {
      this.toast('关系线要正好选两节')
      return
    }
    this.extraPending = [this.selectedIds[0], this.selectedIds[1]]
    this.extraMode = 'relation'
    this.extraText = ''
    const node: PlacedNode | undefined = this.selectedNode()
    this.extraX = node === undefined ? 24 : node.x
    this.extraY = node === undefined ? 24 : node.y + OUTLINE_NODE_H * this.zoom + 8
    this.focusExtraInput()
  }

  /** 浮层刚挂载时拿不到焦点，稍后再请求一次；requestFocus 必须包 try/catch（150002 前科） */
  private focusExtraInput(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(EXTRA_INPUT_ID)
      } catch (e) {
        // 拿不到焦点不影响提交（回车仍可从输入框冒泡）
      }
    }, 40)
  }

  private cancelExtra(): void {
    this.extraMode = ''
    this.extraText = ''
    this.extraPending = []
  }

  /** 提交浮层：发一条附加信息命令（不走正文写入，也不进撤销栈） */
  private commitExtra(): void {
    if (this.extraMode === '') {
      return
    }
    const mode: string = this.extraMode
    const text: string = this.extraText
    const pending: string[] = this.extraPending
    this.cancelExtra()
    if (mode === 'label') {
      if (pending.length < 1) {
        return
      }
      const style: OutlineNodeStyle = this.styleCopyOf(pending[0])
      style.label = text.trim()
      this.pushNodeStyle(style)
      return
    }
    if (pending.length < 2) {
      return
    }
    let kind: string = OUTLINE_EXTRA_ADD_RELATION
    if (mode === 'summary') {
      kind = OUTLINE_EXTRA_ADD_SUMMARY
    } else if (mode === 'boundary') {
      kind = OUTLINE_EXTRA_ADD_BOUNDARY
    }
    const command: OutlineExtraCommand = new OutlineExtraCommand(kind, '', pending[0], pending[1], text)
    const next: OutlineExtras | null = outlineService().dispatchExtra(command)
    if (next === null) {
      this.toast('这次没建成（先在正文里保存一下再试）')
      return
    }
    this.selectedIds = []
    this.layoutRev = this.layoutRev + 1
    this.refreshExtras()
  }

  /** 打开备注抽屉：直接读侧车里的当前内容 */
  private openNote(paraId: string): void {
    if (paraId === '') {
      return
    }
    const style: OutlineNodeStyle | undefined = this.styleOf(paraId)
    this.noteParaId = paraId
    this.noteText = style === undefined ? '' : style.note
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(NOTE_INPUT_ID)
      } catch (e) {
        // 拿不到焦点不影响写（点「保存」也行）
      }
    }, 40)
  }

  private closeNote(): void {
    this.noteParaId = ''
    this.noteText = ''
  }

  /** 保存备注：走节点样式那条侧车通道（备注就是这一节的一部分"备注信息"） */
  private saveNote(): void {
    const paraId: string = this.noteParaId
    if (paraId === '') {
      return
    }
    const style: OutlineNodeStyle = this.styleCopyOf(paraId)
    style.note = this.noteText.trim()
    this.closeNote()
    this.pushNodeStyle(style)
  }

  /** 节点上有没有备注（决定要不要画角标） */
  private noteOf(node: PlacedNode): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(node.paraId)
    return style === undefined ? '' : style.note
  }

  private removeExtra(kind: string, id: string): void {
    const command: OutlineExtraCommand = new OutlineExtraCommand(kind, id, '', '', '')
    const next: OutlineExtras | null = outlineService().dispatchExtra(command)
    if (next === null) {
      return
    }
    this.layoutRev = this.layoutRev + 1
    this.refreshExtras()
  }

  /** 改缩放：按档位重排一次（不缩放容器，避免文字发糊） */
  private setZoom(next: number): void {
    const clamped: number = Math.max(0.55, Math.min(1.8, next))
    if (Math.abs(clamped - this.zoom) < 0.001) {
      return
    }
    this.zoom = clamped
    this.load()
  }

  /** 换布局形态（纯布局参数，不动正文） */
  private setLayoutMode(mode: string): void {
    if (this.layoutMode === mode) {
      return
    }
    this.layoutMode = mode
    this.load()
  }

  /** 线条等粗 ↔ 渐细 */
  private setThinLines(on: boolean): void {
    if (this.thinLines === on) {
      return
    }
    this.thinLines = on
    this.load()
  }

  /** 折叠/展开一节：只改视图集合，不碰正文 */
  private toggleFold(paraId: string): void {
    if (paraId === '') {
      return
    }
    const next: string[] = []
    let found: boolean = false
    for (let i: number = 0; i < this.collapsedIds.length; i++) {
      if (this.collapsedIds[i] === paraId) {
        found = true
      } else {
        next.push(this.collapsedIds[i])
      }
    }
    if (!found) {
      next.push(paraId)
    }
    this.collapsedIds = next
    this.load()
  }

  /** 展开全部：折叠多了要能一键恢复 */
  private expandAll(): void {
    if (this.collapsedIds.length === 0) {
      return
    }
    this.collapsedIds = []
    this.load()
  }

  /** 换连线画法：曲线 ↔ 折线 */
  private setWireStyle(style: string): void {
    if (this.wireStyle === style) {
      return
    }
    this.wireStyle = style
    this.load()
  }

  private setColorByBranch(on: boolean): void {
    if (this.colorByBranch === on) {
      return
    }
    this.colorByBranch = on
    this.load()
  }

  private setShowNumbers(on: boolean): void {
    if (this.showNumbers === on) {
      return
    }
    this.showNumbers = on
    this.load()
  }

  private setNodeStyle(style: string): void {
    if (this.nodeStyle === style) {
      return
    }
    this.nodeStyle = style
    this.load()
  }

  /** 一条连线/一段编号的颜色：按分支取色，或退回单色 */
  private branchColor(index: number): string {
    if (!this.colorByBranch || index < 0) {
      return this.theme.line
    }
    const list: string[] = this.theme.branches
    if (list.length === 0) {
      return this.theme.line
    }
    return list[index % list.length]
  }

  /** 单个节点的形状：节点样式优先，其次全局设置 */
  private chipRadius(n: PlacedNode): number {
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    const shape: string = style === undefined || style.shape === '' ? '' : style.shape
    if (shape === OUTLINE_SHAPE_PILL) {
      return OUTLINE_NODE_H * n.scale / 2
    }
    if (shape === OUTLINE_SHAPE_PLAIN || (shape === '' && this.nodeStyle === 'plain')) {
      return 0
    }
    return 10
  }

  private chipBg(n: PlacedNode): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    if (style !== undefined && style.fill !== '') {
      return style.fill
    }
    if (n.depth === 0) {
      return this.theme.brand
    }
    const shape: string = style === undefined ? '' : style.shape
    if (shape === OUTLINE_SHAPE_PLAIN || (shape === '' && this.nodeStyle === 'plain')) {
      return '#00000000'
    }
    return this.nodeStyle === 'card' || shape !== '' ? this.theme.card : '#00000000'
  }

  /** 文字颜色：自定义填充时按亮度自动取深/浅，保证读得清 */
  private chipTextColor(n: PlacedNode): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    if (style !== undefined && style.fill !== '') {
      return this.readableOn(style.fill)
    }
    return n.depth === 0 ? this.theme.onBrand : this.theme.text
  }

  private chipBold(n: PlacedNode): boolean {
    if (n.depth === 0) {
      return true
    }
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    return style === undefined ? false : style.bold
  }

  private chipBorderWidth(n: PlacedNode, index: number): number {
    if (this.isSelected(n, index)) {
      return 2
    }
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    const shape: string = style === undefined ? '' : style.shape
    if (n.depth === 0 || shape === OUTLINE_SHAPE_PLAIN ||
      (shape === '' && this.nodeStyle === 'plain')) {
      return 0
    }
    if (style !== undefined && style.fill !== '') {
      return 0
    }
    return 1
  }

  private chipBorderColor(n: PlacedNode, index: number): string {
    if (this.selectedIndex === index) {
      return this.theme.brand
    }
    if (this.isSelected(n, index)) {
      // 多选里的次级选中：用分支色描边，和"当前节点"区分开
      return this.branchColor(n.branchIndex)
    }
    const style: OutlineNodeStyle | undefined = this.styleOf(n.paraId)
    const shape: string = style === undefined ? '' : style.shape
    if (shape === '') {
      if (this.nodeStyle === 'line') {
        return this.branchColor(n.branchIndex)
      }
      return this.theme.divider
    }
    return shape === OUTLINE_SHAPE_PLAIN ? this.theme.divider : this.branchColor(n.branchIndex)
  }

  /** 适应窗口：按当前视口把整棵树缩到看得全 */
  private fitToWindow(): void {
    if (this.viewW <= 0 || this.viewH <= 0 || this.mapW <= 0 || this.mapH <= 0) {
      return
    }
    const baseW: number = this.mapW / this.zoom
    const baseH: number = this.mapH / this.zoom
    const z: number = Math.min((this.viewW - 32) / baseW, (this.viewH - 96) / baseH)
    this.setZoom(z)
  }

  private selectedNode(): PlacedNode | undefined {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.placed.length) {
      return undefined
    }
    return this.placed[this.selectedIndex]
  }

  private selectedParaId(): string {
    const node: PlacedNode | undefined = this.selectedNode()
    return node === undefined ? '' : node.paraId
  }

  private selectedX(): number {
    const node: PlacedNode | undefined = this.selectedNode()
    return node === undefined ? 0 : node.x
  }

  private selectedY(): number {
    const node: PlacedNode | undefined = this.selectedNode()
    return node === undefined ? 0 : node.y
  }

  /** 折叠徽标的横坐标：贴在节点外侧（朝左展开的节点贴在左边） */
  private badgeX(n: PlacedNode): number {
    return n.side < 0 ? n.x - 22 : n.x + OUTLINE_NODE_W * n.scale + 6
  }

  private badgeY(n: PlacedNode): number {
    return n.y + OUTLINE_NODE_H * n.scale / 2 - 8
  }

  private selectAt(index: number): void {
    if (index < 0 || index >= this.placed.length) {
      return
    }
    this.selectedIndex = index
    const paraId: string = this.placed[index].paraId
    this.selectedIds = paraId === '' ? [] : [paraId]
    this.renaming = false
  }

  /** 单击时读 Ctrl：部分设备不给修饰键信息，异常按"没按"处理 */
  private clickHasCtrl(event: ClickEvent): boolean {
    try {
      if (event.getModifierKeyState === undefined) {
        return false
      }
      return event.getModifierKeyState(['Ctrl'])
    } catch (e) {
      return false
    }
  }

  /** 发一条命令；成功后用宿主回传的快照重排 */
  private dispatchCommand(kind: OutlineCommandKind, text: string = '', level: number = 1): boolean {
    const node: PlacedNode | undefined = this.selectedNode()
    if (node === undefined) {
      return false
    }
    const command: OutlineCommand = new OutlineCommand(kind, node.paraId, text, level)
    const next: OutlineSnapshot | null = outlineService().dispatch(command)
    if (next === null) {
      this.toast('这次修改没有生效（正文可能刚被改动）')
      return false
    }
    this.applySnapshot(next)
    return true
  }

  private startRename(): void {
    const node: PlacedNode | undefined = this.selectedNode()
    if (node === undefined) {
      return
    }
    this.renameText = node.title
    this.renaming = true
    // 浮层刚挂载时还拿不到焦点，稍后再请求一次；requestFocus 必须包 try/catch（150002 前科）
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(RENAME_INPUT_ID)
      } catch (e) {
        // 拿不到焦点不影响保存（回车仍可从输入框冒泡）
      }
    }, 40)
  }

  private commitRename(): void {
    if (!this.renaming) {
      return
    }
    this.renaming = false
    const text: string = this.renameText.trim()
    const node: PlacedNode | undefined = this.selectedNode()
    if (node === undefined || text === '' || text === node.title) {
      return
    }
    this.dispatchCommand(OutlineCommandKind.RENAME, text)
  }

  /** 删除整节：二次确认后执行（正文里的删除仍可撤销） */
  private confirmDelete(): void {
    const node: PlacedNode | undefined = this.selectedNode()
    if (node === undefined) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '删除这一节？',
        message: '「' + node.title + '」及其下的正文会一起删除；可以在正文里撤销。',
        buttons: [
          { text: '取消', color: this.theme.sub },
          { text: '删除', color: this.theme.danger }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.dispatchCommand(OutlineCommandKind.DELETE_SECTION)
        }
      }).catch(() => {})
    } catch (e) {
      this.toast('无法打开确认框')
    }
  }

  private jumpTo(offset: number): void {
    outlineService().requestReveal(offset)
    this.onClose()
  }

  /** 读修饰键；部分键位没有修饰键信息，异常时按未按下处理 */
  private hasModifier(event: KeyEvent, name: string): boolean {
    try {
      // getModifierKeyState 在部分 SDK 声明为可选：先判存在再调用
      if (event.getModifierKeyState === undefined) {
        return false
      }
      return event.getModifierKeyState([name])
    } catch (e) {
      return false
    }
  }

  /** 键盘：结构编辑与导航分离——Enter 新建同级，双击回正文，Alt+↑↓ 搬整节 */
  private handleKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false
    }
    if (this.renaming) {
      return false
    }
    if (this.extraMode !== '') {
      // 浮层里正在打字：只有 Esc 归页面处理，其余按键交给输入框
      if (event.keyCode === KEY_ESCAPE) {
        this.cancelExtra()
        return true
      }
      return false
    }
    if (this.noteParaId !== '') {
      if (event.keyCode === KEY_ESCAPE) {
        this.closeNote()
        return true
      }
      return false
    }
    if (this.zenMode && event.keyCode === KEY_ESCAPE) {
      // 专注模式先退专注：Esc 不该直接把导图关掉
      this.toggleZen()
      return true
    }
    const code: number = event.keyCode
    if (this.presentMode) {
      // 演说模式：先把这几种键接管，别让它们触发结构编辑
      if (code === KEY_ESCAPE) {
        this.exitPresent()
        return true
      }
      if (code === KEY_DPAD_RIGHT || code === KEY_SPACE || code === KEY_ENTER) {
        this.goToStep(this.presentIndex + 1)
        return true
      }
      if (code === KEY_DPAD_LEFT) {
        this.goToStep(this.presentIndex - 1)
        return true
      }
      return false
    }
    if (code === KEY_ESCAPE) {
      this.onClose()
      return true
    }
    if (this.placed.length === 0) {
      return false
    }
    const ctrl: boolean = this.hasModifier(event, 'ctrl')
    if (ctrl && (code === KEY_Z || code === KEY_Y)) {
      // Ctrl+Z 撤销、Ctrl+Shift+Z / Ctrl+Y 重做（与正文编辑器一致）
      const redo: boolean = code === KEY_Y || this.hasModifier(event, 'shift')
      this.dispatchHistory(redo)
      return true
    }
    if (ctrl && code === KEY_0) {
      this.fitToWindow()
      return true
    }
    if (ctrl && (code === KEY_EQUALS || code === KEY_PLUS)) {
      this.setZoom(this.zoom * 1.15)
      return true
    }
    if (ctrl && code === KEY_MINUS) {
      this.setZoom(this.zoom / 1.15)
      return true
    }
    const alt: boolean = this.hasModifier(event, 'alt')
    if ((code === KEY_DPAD_UP || code === KEY_DPAD_DOWN) && alt) {
      // Alt+方向：搬整节（正文跟着走）；没有修饰键时才是移动选中
      if (this.selectedIndex >= 0) {
        this.dispatchCommand(code === KEY_DPAD_UP ? OutlineCommandKind.MOVE_UP : OutlineCommandKind.MOVE_DOWN)
      }
      return true
    }
    if (code === KEY_DPAD_UP || code === KEY_DPAD_DOWN) {
      const step: number = code === KEY_DPAD_UP ? -1 : 1
      const base: number = this.selectedIndex < 0 ? (step > 0 ? -1 : this.placed.length) : this.selectedIndex
      this.selectAt(Math.max(0, Math.min(this.placed.length - 1, base + step)))
      return true
    }
    if (this.selectedIndex < 0) {
      return false
    }
    if (code === KEY_SPACE) {
      // 空格 = 折叠/展开选中节（只改视图）
      const target: PlacedNode | undefined = this.selectedNode()
      if (target !== undefined && target.childCount > 0) {
        this.toggleFold(target.paraId)
      }
      return true
    }
    if (code === KEY_ENTER) {
      this.dispatchCommand(OutlineCommandKind.INSERT_SIBLING)
      return true
    }
    if (code === KEY_TAB) {
      const shift: boolean = this.hasModifier(event, 'shift')
      const node: PlacedNode | undefined = this.selectedNode()
      if (shift) {
        // Shift+Tab：升一级（H3→H2→H1），到 H1 就不再变
        if (node !== undefined && node.level > 1) {
          this.dispatchCommand(OutlineCommandKind.SET_KIND, '', node.level - 1)
        }
        return true
      }
      this.dispatchCommand(OutlineCommandKind.INSERT_CHILD)
      return true
    }
    if (code === KEY_F2) {
      this.startRename()
      return true
    }
    if (code === KEY_FORWARD_DEL) {
      this.confirmDelete()
      return true
    }
    return false
  }

  /**
   * ForEach 的键：节点身份 + 布局版本。
   * 只写身份的话，缩放/重排后键不变，ArkUI 复用旧子组件、不重跑构建函数 → 节点停在旧位置。
   */
  private nodeKey(node: PlacedNode): string {
    return this.layoutRev.toString() + '|' + (node.paraId === '' ? node.id : node.paraId)
  }

  /** 连线的键：包围盒与版本一起，几何一变就重建 */
  private wireKey(wire: OutlineWire, index: number): string {
    return this.layoutRev.toString() + '|' + index.toString() + '|' + wire.originX.toFixed(1) +
      '|' + wire.originY.toFixed(1) + '|' + wire.width.toFixed(1) + '|' + wire.height.toFixed(1)
  }

  private titleOf(): string {
    const snapshot: OutlineSnapshot | null = outlineService().current()
    if (snapshot !== null && snapshot.docTitle !== '') {
      return snapshot.docTitle
    }
    return this.docTitle === '' ? '结构' : this.docTitle
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      // 提示失败不影响主流程
    }
  }

  @Builder
  header() {
    Row() {
      Column() {
        Text('导图').fontSize(11).fontColor(this.theme.sub)
        Text(this.titleOf())
          .fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.theme.text)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.selectedIds.length > 1
        ? ('已选 ' + this.selectedIds.length.toString() + ' / ' + this.topicCount.toString() + ' 个主题')
        : (this.topicCount.toString() + ' 个主题'))
        .fontSize(12).fontColor(this.theme.sub)
        .margin({ right: 12 })

      // 布局形态与折叠：都只改视图，不动正文
      if (this.collapsedIds.length > 0) {
        Text('展开全部')
          .fontSize(12).fontColor(this.theme.sub)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .accessibilityText('展开所有折叠的主题')
          .onClick(() => { this.expandAll() })
      }

      // 专注（ZEN）：进入后只留「退出专注」和缩放，别的控件都收起来
      Text(this.zenMode ? '专注中' : '专注')
        .fontSize(12).fontColor(this.zenMode ? this.theme.text : this.theme.sub)
        .backgroundColor(this.zenMode ? this.theme.divider : '#00000000')
        .borderRadius(6)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText(this.zenMode ? '退出专注' : '只突出当前分支（专注模式）')
        .onClick(() => { this.toggleZen() })

      // 附加信息：概要在"同层多选"可用，关系线在"正好两节"可用
      if (!this.zenMode && !this.presentMode) {
        Text('多选')
          .fontSize(12).fontColor(this.multiSelect ? this.theme.text : this.theme.sub)
          .backgroundColor(this.multiSelect ? this.theme.divider : '#00000000')
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .accessibilityText(this.multiSelect ? '退出多选' : '进入多选（点节点逐个加选）')
          .onClick(() => { this.toggleMultiSelect() })
      }
      Text('概要')
        .fontSize(12)
        .fontColor(this.summaryReady() ? this.theme.text : this.theme.sub)
        .opacity(this.summaryReady() ? 1 : 0.4)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText('给选中的几节加一条概要')
        .onClick(() => { this.openSummaryEditor() })
      Text('外框')
        .fontSize(12)
        .fontColor(this.summaryReady() ? this.theme.text : this.theme.sub)
        .opacity(this.summaryReady() ? 1 : 0.4)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText('把选中的几节圈进一个外框')
        .onClick(() => { this.openBoundaryEditor() })
      Text('关系')
        .fontSize(12)
        .fontColor(this.relationReady() ? this.theme.text : this.theme.sub)
        .opacity(this.relationReady() ? 1 : 0.4)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText('给选中的两节连一条关系线')
        .onClick(() => { this.openRelationEditor() })

      // 样式面板开合
      Text('样式')
        .fontSize(12).fontColor(this.styleOpen ? this.theme.text : this.theme.sub)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .backgroundColor(this.styleOpen ? this.theme.divider : '#00000000')
        .borderRadius(6)
        .accessibilityText(this.styleOpen ? '收起样式面板' : '展开样式面板')
        .onClick(() => { this.styleOpen = !this.styleOpen })

      // 缩放：按档位重排（文字不糊）；「适应」把整棵树缩进视口
      Row() {
        Text('−')
          .fontSize(15).fontColor(this.theme.text)
          .width(28).height(28).textAlign(TextAlign.Center)
          .accessibilityText('缩小')
          .onClick(() => { this.setZoom(this.zoom / 1.15) })
        Text(Math.round(this.zoom * 100).toString() + '%')
          .fontSize(12).fontColor(this.theme.sub)
          .width(48).textAlign(TextAlign.Center)
        Text('＋')
          .fontSize(14).fontColor(this.theme.text)
          .width(28).height(28).textAlign(TextAlign.Center)
          .accessibilityText('放大')
          .onClick(() => { this.setZoom(this.zoom * 1.15) })
        Text('适应')
          .fontSize(12).fontColor(this.theme.sub)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .accessibilityText('适应窗口')
          .onClick(() => { this.fitToWindow() })
      }
      .margin({ right: 12 })

      Text('↶')
        .fontSize(15).fontColor(this.theme.text)
        .width(28).height(28).textAlign(TextAlign.Center)
        .accessibilityText('撤销上一次结构改动')
        .onClick(() => { this.dispatchHistory(false) })
      Text('↷')
        .fontSize(15).fontColor(this.theme.text)
        .width(28).height(28).textAlign(TextAlign.Center)
        .margin({ right: 8 })
        .accessibilityText('重做')
        .onClick(() => { this.dispatchHistory(true) })

      Text('关闭')
        .fontSize(13).fontColor(this.theme.text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(8)
        .border({ width: 1, color: this.theme.divider })
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('关闭导图，回到正文')
        .onClick(() => { this.onClose() })
    }
    .width('100%')
    .height(64)
    .padding({ left: 20, right: 16 + this.captionInset })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: this.theme.divider })
  }

  /**
   * 一条连线：一个 Polyline。
   * `points` 的单位与 `.position()`/`.width()` 一样是 vp，所以它和节点在同一套坐标里，
   * 只需要摆到包围盒左上角——不依赖画布尺寸、不依赖重画时机。
   */
  @Builder
  wireLine(wire: OutlineWire) {
    Polyline()
      .width(wire.width)
      .height(wire.height)
      .position({ x: wire.originX, y: wire.originY })
      .points(wire.points)
      .fillOpacity(0)
      .opacity(this.focusOpacity(wire.toParaId))
      .stroke(this.branchColor(wire.branchIndex))
      .strokeWidth(this.wireWidth(wire))
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }

  /** 线条粗细：渐细模式按深度递减，等粗模式统一 1.4vp */
  private wireWidth(wire: OutlineWire): number {
    if (!this.thinLines) {
      return 1.4
    }
    return Math.max(1, 2.4 - wire.depth * 0.45)
  }

  /** 连线终点样式：圆点 / 箭头（XMind 的"分支终点"） */
  @Builder
  wireTip(wire: OutlineWire) {
    if (this.endStyle === 'dot') {
      Circle()
        .width(6)
        .height(6)
        .fill(this.branchColor(wire.branchIndex))
        .position({ x: wire.endX - 3, y: wire.endY - 3 })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    } else if (this.endStyle === 'arrow') {
      Polyline()
        .width(18)
        .height(18)
        .position({ x: wire.endX - 9, y: wire.endY - 9 })
        .points(this.arrowPoints(wire))
        .fillOpacity(0)
        .opacity(this.focusOpacity(wire.toParaId))
        .stroke(this.branchColor(wire.branchIndex))
        .strokeWidth(this.wireWidth(wire))
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
  }

  /** 箭头三个点在 18×18 盒子里的坐标（盒子中心正对连线终点） */
  private arrowPoints(wire: OutlineWire): number[][] {
    const size: number = 7
    const spread: number = 0.45
    const out: number[][] = []
    out.push([9 - size * Math.cos(wire.endAngle - spread), 9 - size * Math.sin(wire.endAngle - spread)])
    out.push([9, 9])
    out.push([9 - size * Math.cos(wire.endAngle + spread), 9 - size * Math.sin(wire.endAngle + spread)])
    return out
  }

  private labelKeyOf(node: PlacedNode): string {
    return this.nodeKey(node) + '|' + this.labelOf(node)
  }

  /** 节点标签（ForEach 的构建函数里不能写局部变量，所以查询单独成方法） */
  private labelOf(node: PlacedNode): string {
    const style: OutlineNodeStyle | undefined = this.styleOf(node.paraId)
    return style === undefined ? '' : style.label
  }

  /** 备注角标：节点右侧留白处的小方块，点开抽屉看/写（图上不显示正文，避免撑高节点） */
  @Builder
  noteBadge(n: PlacedNode) {
    Text('❏')
      .fontSize(10)
      .fontColor(this.theme.sub)
      .width(14)
      .height(14)
      .textAlign(TextAlign.Center)
      .position({ x: n.x + OUTLINE_NODE_W * n.scale - 18, y: n.y + OUTLINE_NODE_H * n.scale / 2 - 7 })
      .opacity(this.focusOpacity(n.paraId))
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('查看备注')
      .onClick(() => { this.openNote(n.paraId) })
  }

  /** 折叠徽标：有子节点才出现；展开时显示「−」，折叠时显示子节点数量（幕布的做法）。
   * 独立组件压在节点层之上，点它不会误触「选中 / 双击回正文」。
   */
  @Builder
  foldBadge(n: PlacedNode) {
    Text(n.collapsed ? n.childCount.toString() : '−')
      .fontSize(9)
      .fontColor(this.theme.sub)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.theme.card)
      .borderRadius(8)
      .border({ width: 1, color: this.theme.divider })
      .position({ x: this.badgeX(n), y: this.badgeY(n) })
      .opacity(this.focusOpacity(n.paraId))
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(n.collapsed ? ('展开这一节，共 ' + n.childCount.toString() + ' 项') : '折叠这一节')
      .onClick(() => { this.toggleFold(n.paraId) })
  }

  /** 外框：圆角虚线矩形 + 左上标题 + 右上去掉按钮（压在最底层，不抢命中） */
  @Builder
  boundaryMark(box: OutlineBoundaryBox) {
    Column()
      .width(box.width)
      .height(box.height)
      .position({ x: box.x, y: box.y })
      .borderRadius(14)
      .border({ width: 1, color: this.theme.sub, style: BorderStyle.Dashed })
      .backgroundColor('#00000000')
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    Text(box.text === '' ? '外框' : box.text)
      .fontSize(10)
      .fontColor(this.theme.sub)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width(box.width - 44)
      .position({ x: box.textX, y: box.textY })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    Text('×')
      .fontSize(11)
      .fontColor(this.theme.sub)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(this.theme.card)
      .border({ width: 1, color: this.theme.divider })
      .position({ x: box.closeX, y: box.closeY })
      .accessibilityText('删除这个外框')
      .onClick(() => { this.removeExtra(OUTLINE_EXTRA_REMOVE_BOUNDARY, box.boundaryId) })
  }

  /** 概要：括号折线 + 文字 + 删除（文字挂在括号外侧中央，照 XMind 的样子） */
  @Builder
  summaryMark(box: OutlineSummaryBox) {
    Polyline()
      .width(box.width)
      .height(box.height)
      .position({ x: box.originX, y: box.originY })
      .points(box.points)
      .fillOpacity(0)
      .stroke(this.theme.sub)
      .strokeWidth(1.2)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    Text(box.text)
      .fontSize(11)
      .fontColor(this.theme.sub)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .textAlign(box.alignEnd ? TextAlign.End : TextAlign.Start)
      .width(OUTLINE_SUMMARY_TEXT_W)
      .backgroundColor(this.theme.bg)
      .borderRadius(4)
      .padding({ left: 3, right: 3, top: 1, bottom: 1 })
      .position({ x: box.textX, y: box.textY })
      .accessibilityText('概要：' + box.text)
    Text('×')
      .fontSize(11)
      .fontColor(this.theme.sub)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(this.theme.card)
      .border({ width: 1, color: this.theme.divider })
      .position({ x: box.closeX, y: box.closeY })
      .accessibilityText('删除这条概要')
      .onClick(() => { this.removeExtra(OUTLINE_EXTRA_REMOVE_SUMMARY, box.summaryId) })
  }

  /** 关系线：虚线曲线 + 箭头 + 标签 + 删除（用虚线区别于父子连线） */
  @Builder
  relationMark(wire: OutlineRelationWire) {
    Polyline()
      .width(wire.width)
      .height(wire.height)
      .position({ x: wire.originX, y: wire.originY })
      .points(wire.points)
      .fillOpacity(0)
      .stroke(this.theme.sub)
      .strokeWidth(1.2)
      .strokeDashArray([4, 3])
      .strokeLineCap(LineCapStyle.Round)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    Polyline()
      .width(wire.width)
      .height(wire.height)
      .position({ x: wire.originX, y: wire.originY })
      .points(wire.arrow)
      .fillOpacity(0)
      .stroke(this.theme.sub)
      .strokeWidth(1.2)
      .strokeLineCap(LineCapStyle.Round)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    Text(wire.label)
      .fontSize(10)
      .fontColor(this.theme.sub)
      .backgroundColor(this.theme.bg)
      .borderRadius(4)
      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
      .maxLines(1)
      .position({ x: wire.labelX - 40, y: wire.labelY - 9 })
      .accessibilityText('关系：' + wire.label)
    Text('×')
      .fontSize(11)
      .fontColor(this.theme.sub)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(this.theme.card)
      .border({ width: 1, color: this.theme.divider })
      .position({ x: wire.closeX, y: wire.closeY })
      .accessibilityText('删除这条关系线')
      .onClick(() => { this.removeExtra(OUTLINE_EXTRA_REMOVE_RELATION, wire.relationId) })
  }

  /** 概要/关系线的文字浮层：就地出现在选中的位置，回车提交、Esc 取消 */
  @Builder
  extraEditor() {
    Column() {
      Text(this.extraMode === 'summary' ? '概要' : (this.extraMode === 'label' ? '标签'
        : (this.extraMode === 'boundary' ? '外框标题（可留空）' : '关系标签')))
        .fontSize(11)
        .fontColor(this.theme.sub)
      TextInput({ text: this.extraText })
        .id(EXTRA_INPUT_ID)
        .width(196)
        .height(30)
        .fontSize(12)
        .margin({ top: 6 })
        .backgroundColor(this.theme.card)
        .borderRadius(6)
        .border({ width: 1, color: this.theme.divider })
        .onChange((value: string) => { this.extraText = value })
        .onSubmit(() => { this.commitExtra() })
      Row() {
        Text('取消')
          .fontSize(11)
          .fontColor(this.theme.sub)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => { this.cancelExtra() })
        Text('确定')
          .fontSize(11)
          .fontColor(this.theme.onBrand)
          .backgroundColor(this.theme.brand)
          .borderRadius(4)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 6 })
          .onClick(() => { this.commitExtra() })
      }
      .margin({ top: 8 })
      .justifyContent(FlexAlign.End)
      .width(196)
    }
    .width(220)
    .padding(12)
    .backgroundColor(this.theme.bg)
    .borderRadius(10)
    .border({ width: 1, color: this.theme.divider })
    .alignItems(HorizontalAlign.Start)
    .position({ x: this.extraX, y: this.extraY })
  }

  @Builder
  nodeChip(n: PlacedNode, index: number) {
    Row() {
      if (this.markersText(this.styleOf(n.paraId)) !== '') {
        Text(this.markersText(this.styleOf(n.paraId)))
          .fontSize(Math.max(9, 11 * n.scale))
          .margin({ right: 4 })
          .maxLines(1)
      }
      if (this.showNumbers && n.orderLabel !== '') {
        Text(n.orderLabel)
          .fontSize(Math.max(9, 11 * n.scale))
          .fontColor(this.chipTextColor(n))
          .opacity(0.75)
          .margin({ right: 6 })
          .maxLines(1)
      }
      Text(n.title)
        .fontSize(Math.max(9, (n.depth === 0 ? 13 : 12) * n.scale))
        .fontWeight(this.chipBold(n) ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.chipTextColor(n))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width(OUTLINE_NODE_W * n.scale)
    .height(OUTLINE_NODE_H * n.scale)
    .padding({ left: 10, right: this.noteOf(n) !== '' ? 22 : 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.chipBg(n))
    .opacity(this.focusOpacity(n.paraId))
    .borderRadius(this.chipRadius(n))
    .border({ width: this.chipBorderWidth(n, index), color: this.chipBorderColor(n, index) })
    .position({ x: n.x, y: n.y })
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText('主题：' + n.title + '，回车新建同级，Tab 新建子级，双击回到正文')
    .onClick((event: ClickEvent) => {
      // 多选：Ctrl+单击是快路，多选开关兜底（触屏没有修饰键）
      if (this.multiSelect || this.clickHasCtrl(event)) {
        this.toggleSelect(index)
      } else {
        this.selectAt(index)
      }
    })
    .gesture(TapGesture({ count: 2 }).onAction(() => { this.jumpTo(n.startOffset) }))
  }

  /** 标签：挂在节点下方的一行小字（XMind 的 label 位置） */
  @Builder
  nodeLabel(n: PlacedNode, text: string) {
    Text(text)
      .fontSize(9)
      .fontColor(this.theme.sub)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width(OUTLINE_NODE_W * n.scale)
      .position({ x: n.x, y: nodeLabelY(n) })
      .opacity(this.focusOpacity(n.paraId))
      .hitTestBehavior(HitTestMode.None)
      .accessibilityText('标签：' + text)
  }

  /** 就地改名浮层：压在节点原来的位置上 */
  @Builder
  renameOverlay() {
    TextInput({ text: this.renameText })
      .id(RENAME_INPUT_ID)
      .width(OUTLINE_NODE_W * this.zoom)
      .height(OUTLINE_NODE_H * this.zoom)
      .fontSize(Math.max(10, 13 * this.zoom))
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.theme.card)
      .borderRadius(10)
      .border({ width: 2, color: this.theme.brand })
      .position({ x: this.selectedX(), y: this.selectedY() })
      .onChange((value: string) => { this.renameText = value })
      .onSubmit(() => { this.commitRename() })
      .onBlur(() => { this.commitRename() })
  }

  @Builder
  emptyView() {
    Column() {
      Text('还没有可展示的结构')
        .fontSize(15).fontColor(this.theme.text)
      Text('在正文里把几句设成标题（H1–H3），再打开导图就会长成一棵树。')
        .fontSize(12).fontColor(this.theme.sub)
        .margin({ top: 8 })
        .textAlign(TextAlign.Center)
      Text('↶')
        .fontSize(15).fontColor(this.theme.text)
        .width(28).height(28).textAlign(TextAlign.Center)
        .accessibilityText('撤销上一次结构改动')
        .onClick(() => { this.dispatchHistory(false) })
      Text('↷')
        .fontSize(15).fontColor(this.theme.text)
        .width(28).height(28).textAlign(TextAlign.Center)
        .margin({ right: 8 })
        .accessibilityText('重做')
        .onClick(() => { this.dispatchHistory(true) })

      Text('关闭')
        .fontSize(13).fontColor(this.theme.text)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(8)
        .border({ width: 1, color: this.theme.divider })
        .margin({ top: 20 })
        .onClick(() => { this.onClose() })
    }
    .width('100%').layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24 })
  }

  /** 地图本体：外层横向 + 内层纵向（ScrollDirection.Free 已废弃） */
  @Builder
  mapView() {
    Scroll(this.hScroller) {
      Scroll(this.vScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 外框最底层：它是个大矩形，压在连线和节点下面才不会盖住内容
          ForEach(this.boundaryBoxes, (box: OutlineBoundaryBox, index: number) => {
            this.boundaryMark(box)
          }, (box: OutlineBoundaryBox, index: number) => 'bd' + index.toString() + '|' + box.boundaryId + '|' +
            box.x.toFixed(1) + '|' + box.y.toFixed(1) + '|' + box.width.toFixed(1) + '|' + box.height.toFixed(1))
          // 连线层：普通组件（不是画布），坐标与下面的节点同一套，先声明所以在底层
          ForEach(this.wires, (wire: OutlineWire, index: number) => {
            this.wireLine(wire)
          }, (wire: OutlineWire, index: number) => this.wireKey(wire, index))
          if (this.endStyle !== 'none') {
            ForEach(this.wires, (wire: OutlineWire, index: number) => {
              this.wireTip(wire)
            }, (wire: OutlineWire, index: number) => 'tip' + this.wireKey(wire, index))
          }
          // 附加信息（概要括号 / 关系线）：和连线同一层，压在节点下面
          ForEach(this.summaryBoxes, (box: OutlineSummaryBox, index: number) => {
            this.summaryMark(box)
          }, (box: OutlineSummaryBox, index: number) => 'sm' + index.toString() + '|' + box.summaryId + '|' +
            box.originX.toFixed(1) + '|' + box.originY.toFixed(1) + '|' + box.width.toFixed(1) + '|' + box.height.toFixed(1))
          ForEach(this.relationWires, (wire: OutlineRelationWire, index: number) => {
            this.relationMark(wire)
          }, (wire: OutlineRelationWire, index: number) => 'rl' + index.toString() + '|' + wire.relationId + '|' +
            wire.originX.toFixed(1) + '|' + wire.originY.toFixed(1) + '|' + wire.width.toFixed(1) + '|' + wire.height.toFixed(1))
          ForEach(this.placed, (node: PlacedNode, index: number) => {
            this.nodeChip(node, index)
          }, (node: PlacedNode) => this.nodeKey(node))
          // 标签：挂在节点下方（只画有标签的）
          ForEach(this.placed, (node: PlacedNode) => {
            if (this.labelOf(node) !== '') {
              this.nodeLabel(node, this.labelOf(node))
            }
          }, (node: PlacedNode) => 'lb' + this.labelKeyOf(node))
          ForEach(this.placed, (node: PlacedNode) => {
            if (node.childCount > 0) {
              this.foldBadge(node)
            }
          }, (node: PlacedNode) => 'fold' + this.nodeKey(node) + (node.collapsed ? 'c' : 'e'))
          ForEach(this.placed, (node: PlacedNode) => {
            if (this.noteOf(node) !== '') {
              this.noteBadge(node)
            }
          }, (node: PlacedNode) => 'note' + this.nodeKey(node))
          if (this.renaming && this.selectedIndex >= 0) {
            this.renameOverlay()
          }
          if (this.extraMode !== '') {
            this.extraEditor()
          }
        }
        .width(this.mapW)
        .height(this.mapH)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .width(this.mapW)
      .height('100%')
      .align(Alignment.TopStart)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .layoutWeight(1)
    .height('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  panelTitle(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(this.theme.sub)
      .margin({ top: 16, bottom: 8 })
  }

  /** 样式面板里的一个可选块：选中态反色，点一下把视图参数换掉 */
  @Builder
  panelChip(label: string, active: boolean, tag: string) {
    Text(label)
      .fontSize(12)
      .fontColor(active ? this.theme.onBrand : this.theme.text)
      .backgroundColor(active ? this.theme.brand : this.theme.card)
      .border({ width: 1, color: active ? this.theme.brand : this.theme.divider })
      .borderRadius(6)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .margin({ right: 8, bottom: 8 })
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label + (active ? '（当前）' : ''))
      .onClick(() => { this.applyStyleTag(tag) })
  }

  private applyStyleTag(tag: string): void {
    if (tag.indexOf('layout-') === 0) {
      this.setLayoutMode(tag.substring(7))
      return
    }
    if (tag === 'minimap') {
      this.showMinimap = !this.showMinimap
      return
    }
    if (tag === 'thin') {
      this.setThinLines(true)
      return
    }
    if (tag === 'evenline') {
      this.setThinLines(false)
      return
    }
    if (tag === 'curve') {
      this.setWireStyle(OUTLINE_WIRE_CURVE)
      return
    }
    if (tag === 'elbow') {
      this.setWireStyle(OUTLINE_WIRE_ELBOW)
      return
    }
    if (tag === 'branch') {
      this.setColorByBranch(true)
      return
    }
    if (tag === 'mono') {
      this.setColorByBranch(false)
      return
    }
    if (tag === 'num') {
      this.setShowNumbers(true)
      return
    }
    if (tag === 'nonum') {
      this.setShowNumbers(false)
      return
    }
    if (tag === 'card' || tag === 'line' || tag === 'plain') {
      this.setNodeStyle(tag)
      return
    }
    if (tag === 'end-none') {
      this.endStyle = 'none'
      return
    }
    if (tag === 'end-dot') {
      this.endStyle = 'dot'
      return
    }
    if (tag === 'end-arrow') {
      this.endStyle = 'arrow'
      return
    }
    // 以下都作用在"当前选中的那一个主题"上（侧车，不改正文）
    if (!this.hasOneSelection()) {
      this.toast('先在图上选一个主题')
      return
    }
    if (tag === 'shape-follow') {
      const style: OutlineNodeStyle = this.selectedStyleCopy()
      style.shape = ''
      this.pushNodeStyle(style)
      return
    }
    if (tag === 'shape-card' || tag === 'shape-pill' || tag === 'shape-plain') {
      const style: OutlineNodeStyle = this.selectedStyleCopy()
      style.shape = OUTLINE_SHAPE_CARD
      if (tag === 'shape-pill') {
        style.shape = OUTLINE_SHAPE_PILL
      }
      if (tag === 'shape-plain') {
        style.shape = OUTLINE_SHAPE_PLAIN
      }
      this.pushNodeStyle(style)
      return
    }
    if (tag === 'fill-follow') {
      const style: OutlineNodeStyle = this.selectedStyleCopy()
      style.fill = ''
      this.pushNodeStyle(style)
      return
    }
    if (tag.indexOf('fill:') === 0) {
      const style: OutlineNodeStyle = this.selectedStyleCopy()
      style.fill = tag.substring(5)
      this.pushNodeStyle(style)
      return
    }
    if (tag === 'bold') {
      const style: OutlineNodeStyle = this.selectedStyleCopy()
      style.bold = !style.bold
      this.pushNodeStyle(style)
      return
    }
    if (tag.indexOf('mark:') === 0) {
      const marker: string = tag.substring(5)
      const current: OutlineNodeStyle = this.selectedStyleCopy()
      this.pushNodeStyle(toggleMarker(current, marker))
      return
    }
    if (tag === 'label') {
      const paraId: string = this.selectedParaId()
      if (paraId === '') {
        return
      }
      this.extraPending = [paraId]
      this.extraMode = 'label'
      this.extraText = this.selectedLabel()
      const node: PlacedNode | undefined = this.selectedNode()
      this.extraX = node === undefined ? 24 : node.x
      this.extraY = node === undefined ? 24 : node.y + OUTLINE_NODE_H * this.zoom + 8
      this.focusExtraInput()
    }
  }

  /** 面板里的一块颜色：点一下把选中主题填成这个色 */
  @Builder
  colorChip(fill: string, active: boolean) {
    Column()
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor(fill)
      .border({ width: active ? 2 : 1, color: active ? this.theme.text : this.theme.divider })
      .margin({ right: 8, bottom: 8 })
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('填充 ' + fill)
      .onClick(() => { this.applyStyleTag('fill:' + fill) })
  }

  /** 右侧样式面板：只承载"看起来怎样"，没有一个开关会改正文 */
  @Builder
  stylePanel() {
    Scroll() {
      Column() {
        Text('样式')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.text)

        this.panelTitle('结构')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('左右', this.layoutMode === OUTLINE_LAYOUT_BALANCED, 'layout-' + OUTLINE_LAYOUT_BALANCED)
          this.panelChip('向右', this.layoutMode === OUTLINE_LAYOUT_RIGHT, 'layout-' + OUTLINE_LAYOUT_RIGHT)
          this.panelChip('向下', this.layoutMode === OUTLINE_LAYOUT_DOWN, 'layout-' + OUTLINE_LAYOUT_DOWN)
          this.panelChip('表格', this.layoutMode === OUTLINE_LAYOUT_TABLE, 'layout-' + OUTLINE_LAYOUT_TABLE)
        }

        this.panelTitle('线条')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('渐细', this.thinLines, 'thin')
          this.panelChip('等粗', !this.thinLines, 'evenline')
        }

        this.panelTitle('连线')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('曲线', this.wireStyle === OUTLINE_WIRE_CURVE, 'curve')
          this.panelChip('折线', this.wireStyle === OUTLINE_WIRE_ELBOW, 'elbow')
        }

        this.panelTitle('配色')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('按分支', this.colorByBranch, 'branch')
          this.panelChip('单色', !this.colorByBranch, 'mono')
        }

        this.panelTitle('编号')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('显示', this.showNumbers, 'num')
          this.panelChip('隐藏', !this.showNumbers, 'nonum')
        }

        this.panelTitle('分支终点')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('无', this.endStyle === 'none', 'end-none')
          this.panelChip('圆点', this.endStyle === 'dot', 'end-dot')
          this.panelChip('箭头', this.endStyle === 'arrow', 'end-arrow')
        }

        this.panelTitle('视图')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('缩略图', this.showMinimap, 'minimap')
        }

        this.panelTitle('节点')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('卡片', this.nodeStyle === 'card', 'card')
          this.panelChip('线框', this.nodeStyle === 'line', 'line')
          this.panelChip('无框', this.nodeStyle === 'plain', 'plain')
        }

        // 选中一个主题时，下面这些只作用于它（落侧车，不进正文）
        if (this.hasOneSelection()) {
          this.panelTitle('选中主题')
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            this.panelChip('默认', this.selectedShape() === '', 'shape-follow')
            this.panelChip('卡片', this.selectedShape() === OUTLINE_SHAPE_CARD, 'shape-card')
            this.panelChip('胶囊', this.selectedShape() === OUTLINE_SHAPE_PILL, 'shape-pill')
            this.panelChip('无框', this.selectedShape() === OUTLINE_SHAPE_PLAIN, 'shape-plain')
          }
          Text('填充')
            .fontSize(10).fontColor(this.theme.sub)
            .margin({ top: 2, bottom: 6 })
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            this.panelChip('默认', this.selectedFill() === '', 'fill-follow')
            ForEach(NODE_FILLS, (fill: string) => {
              this.colorChip(fill, this.selectedFill() === fill)
            }, (fill: string) => 'fill' + fill)
          }
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            this.panelChip('加粗', this.selectedBold(), 'bold')
            this.panelChip('标签', this.selectedLabel() !== '', 'label')
          }
          Text('标记')
            .fontSize(10).fontColor(this.theme.sub)
            .margin({ top: 2, bottom: 6 })
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(NODE_MARKERS, (marker: string) => {
              this.panelChip(marker, this.selectedHasMarker(marker), 'mark:' + marker)
            }, (marker: string) => 'mk' + marker)
          }
        }

        Text('这里只改变看法，不写进正文；结构改动仍然走命令回写。')
          .fontSize(10)
          .fontColor(this.theme.sub)
          .margin({ top: 18 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 8, top: 14, bottom: 24 })
    }
    .width(216)
    .height('100%')
    .align(Alignment.TopStart)
    .scrollBar(BarState.Off)
    .border({ width: { left: 1 }, color: this.theme.divider })
  }

  /** 缩略图：按布局把整张图缩成小色块（不抓屏，纯计算，滚动/缩放都跟得上） */
  @Builder
  minimap() {
    Column() {
      Row() {
        Text('缩略图')
          .fontSize(10).fontColor(this.theme.sub)
        Blank()
        Text('×')
          .fontSize(11).fontColor(this.theme.sub)
          .width(16).height(16).textAlign(TextAlign.Center)
          .onClick(() => { this.showMinimap = false })
      }
      .width('100%')
      .padding({ left: 8, right: 4, top: 2 })

      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.placed, (node: PlacedNode, index: number) => {
          Column()
            .width(Math.max(2, OUTLINE_NODE_W * node.scale * this.miniScale()))
            .height(Math.max(1.5, OUTLINE_NODE_H * node.scale * this.miniScale()))
            .backgroundColor(node.depth === 0 ? this.theme.brand : this.branchColor(node.branchIndex))
            .opacity(node.depth === 0 ? 1 : 0.6)
            .position({
              x: node.x * this.miniScale(),
              y: node.y * this.miniScale()
            })
        }, (node: PlacedNode, index: number) => 'mini' + this.layoutRev.toString() + '|' + index.toString())
      }
      .width(154)
      .height(108)
      .margin({ left: 8, right: 8, bottom: 8 })
      .backgroundColor(this.theme.bg)
      .borderRadius(6)
      .border({ width: 1, color: this.theme.divider })
      .clip(true)
    }
    .width(170)
    .backgroundColor(this.theme.bg)
    .borderRadius(10)
    .border({ width: 1, color: this.theme.divider })
    .margin({ right: 16, bottom: 16 })
  }

  /** 备注抽屉：从右侧浮出，不占地图布局（浮层关掉后地图位置不变） */
  @Builder
  noteDrawer() {
    Column() {
      Row() {
        Text('备注')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.theme.text)
        Blank()
        Text('×')
          .fontSize(13).fontColor(this.theme.sub)
          .width(20).height(20).textAlign(TextAlign.Center)
          .onClick(() => { this.closeNote() })
      }
      .width('100%')

      Text(this.noteTitle())
        .fontSize(11).fontColor(this.theme.sub)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4, bottom: 8 })
        .width('100%')

      TextArea({ text: this.noteText, placeholder: '这一节要补充的说明（不进正文）' })
        .id(NOTE_INPUT_ID)
        .width('100%')
        .height(170)
        .fontSize(12)
        .backgroundColor(this.theme.bg)
        .borderRadius(8)
        .border({ width: 1, color: this.theme.divider })
        .onChange((value: string) => { this.noteText = value })

      Row() {
        Text('清空')
          .fontSize(11).fontColor(this.theme.danger)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .onClick(() => {
            this.noteText = ''
            this.saveNote()
          })
        Blank()
        Text('取消')
          .fontSize(11).fontColor(this.theme.sub)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .onClick(() => { this.closeNote() })
        Text('保存')
          .fontSize(11).fontColor(this.theme.onBrand)
          .backgroundColor(this.theme.brand)
          .borderRadius(4)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .margin({ left: 8 })
          .onClick(() => { this.saveNote() })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width(340)
    .padding(16)
    .margin({ top: 72, right: 16 })
    .backgroundColor(this.theme.bg)
    .borderRadius(12)
    .border({ width: 1, color: this.theme.divider })
    .alignItems(HorizontalAlign.Start)
  }

  /** 抽屉顶部的上下文标题：正在给哪一节写备注 */
  private noteTitle(): string {
    for (let i: number = 0; i < this.placed.length; i++) {
      if (this.placed[i].paraId === this.noteParaId) {
        return '「' + this.placed[i].title + '」'
      }
    }
    return ''
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        this.header()
        if (this.empty) {
          this.emptyView()
        } else {
          Row() {
            this.mapView()
            if (this.styleOpen) {
              this.stylePanel()
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%').height('100%')
      .backgroundColor(this.theme.bg)
      .focusable(true)
      .defaultFocus(true)
      .onKeyEvent((event: KeyEvent) => this.handleKey(event))
      .onAreaChange((_old: Area, now: Area) => {
        this.viewW = Number(now.width)
        this.viewH = Number(now.height)
      })

      if (this.noteParaId !== '') {
        this.noteDrawer()
      }
      if (this.showMinimap && !this.empty) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.minimap()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%').height('100%')
  }
}
