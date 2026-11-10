// 文稿绑定导图（结构包）
//
// 数据：宿主 publish 一份 OutlineSnapshot（节点带稳定 paraId）；本页只读快照、只发命令。
// 编辑：改名/新建/升降级/删除/移动都发 OutlineCommand 给 core_runtime，宿主改正文后回传新快照。
// 边界：本包不 import entry、不碰正文；折叠与选中是视图态。
import {
  MindMapLayout, OutlineSnapshot, PlacedNode, OutlineCommand, OutlineCommandKind, OutlineWire,
  OUTLINE_NODE_H, OUTLINE_NODE_W, OUTLINE_LAYOUT_BALANCED, OUTLINE_LAYOUT_RIGHT,
  OUTLINE_WIRE_STEPS, OUTLINE_WIRE_CURVE, OUTLINE_WIRE_ELBOW,
  layoutOutline, outlineConnectors, outlineWires,
  OutlineExtras, OutlineExtraCommand, OutlineSummaryBox, OutlineRelationWire,
  OUTLINE_EXTRA_ADD_SUMMARY, OUTLINE_EXTRA_REMOVE_SUMMARY,
  OUTLINE_EXTRA_ADD_RELATION, OUTLINE_EXTRA_REMOVE_RELATION,
  OUTLINE_SUMMARY_TEXT_W,
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
const KEY_DPAD_UP: number = 2012
const KEY_DPAD_DOWN: number = 2013
const KEY_F2: number = 2092
const RENAME_INPUT_ID: string = 'structure-rename-input'
const EXTRA_INPUT_ID: string = 'structure-extra-input'

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
  /** 布局形态：true = 根在中间、一级主题左右分；false = 一直向右 */
  @Local balanced: boolean = true
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
  /** 多选：概要需要"一组兄弟主题"，所以选中不再是单值 */
  @Local selectedIds: string[] = []
  /**
   * 多选模式：Ctrl+单击是快路，但触屏/部分设备拿不到修饰键状态，
   * 这一个开关保证「概要」在任何输入方式下都用得了。
   */
  @Local multiSelect: boolean = false
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
    const layout: MindMapLayout = layoutOutline(snapshot.nodes, collapsedSet, this.zoom,
      this.balanced ? OUTLINE_LAYOUT_BALANCED : OUTLINE_LAYOUT_RIGHT)
    this.placed = layout.nodes
    this.mapW = layout.width
    this.mapH = layout.height
    this.topicCount = layout.nodes.length - 1
    this.wires = outlineWires(outlineConnectors(this.placed), OUTLINE_WIRE_STEPS, this.wireStyle)
    this.layoutRev = this.layoutRev + 1
    this.empty = false
    this.refreshExtras()
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
    if (pending.length < 2) {
      return
    }
    const kind: string = mode === 'summary' ? OUTLINE_EXTRA_ADD_SUMMARY : OUTLINE_EXTRA_ADD_RELATION
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

  /** 换布局形态：左右均衡 ↔ 一直向右（纯布局参数，不动正文） */
  private toggleLayout(): void {
    this.balanced = !this.balanced
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

  private chipBg(n: PlacedNode): string {
    if (n.depth === 0) {
      return this.theme.brand
    }
    return this.nodeStyle === 'card' ? this.theme.card : '#00000000'
  }

  private chipBorderWidth(n: PlacedNode, index: number): number {
    if (this.isSelected(n, index)) {
      return 2
    }
    if (n.depth === 0 || this.nodeStyle === 'plain') {
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
    if (this.nodeStyle === 'line') {
      return this.branchColor(n.branchIndex)
    }
    return this.theme.divider
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
    const code: number = event.keyCode
    if (code === KEY_ESCAPE) {
      this.onClose()
      return true
    }
    if (this.placed.length === 0) {
      return false
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

      Text(this.topicCount.toString() + ' 个主题')
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

      // 附加信息：概要在"同层多选"可用，关系线在"正好两节"可用
      Text('多选')
        .fontSize(12).fontColor(this.multiSelect ? this.theme.text : this.theme.sub)
        .backgroundColor(this.multiSelect ? this.theme.divider : '#00000000')
        .borderRadius(6)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText(this.multiSelect ? '退出多选' : '进入多选（点节点逐个加选）')
        .onClick(() => { this.toggleMultiSelect() })
      Text('概要')
        .fontSize(12)
        .fontColor(this.summaryReady() ? this.theme.text : this.theme.sub)
        .opacity(this.summaryReady() ? 1 : 0.4)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText('给选中的几节加一条概要')
        .onClick(() => { this.openSummaryEditor() })
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
      .stroke(this.branchColor(wire.branchIndex))
      .strokeWidth(1.4)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
  }

  /**
   * 折叠徽标：有子节点才出现；展开时显示「−」，折叠时显示子节点数量（幕布的做法）。
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
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(n.collapsed ? ('展开这一节，共 ' + n.childCount.toString() + ' 项') : '折叠这一节')
      .onClick(() => { this.toggleFold(n.paraId) })
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
      Text(this.extraMode === 'summary' ? '概要' : '关系标签')
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
      if (this.showNumbers && n.orderLabel !== '') {
        Text(n.orderLabel)
          .fontSize(Math.max(9, 11 * n.scale))
          .fontColor(n.depth === 0 ? this.theme.onBrand : this.branchColor(n.branchIndex))
          .margin({ right: 6 })
          .maxLines(1)
      }
      Text(n.title)
        .fontSize(Math.max(9, (n.depth === 0 ? 13 : 12) * n.scale))
        .fontWeight(n.depth === 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(n.depth === 0 ? this.theme.onBrand : this.theme.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width(OUTLINE_NODE_W * n.scale)
    .height(OUTLINE_NODE_H * n.scale)
    .padding({ left: 10, right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.chipBg(n))
    .borderRadius(this.nodeStyle === 'plain' ? 0 : 10)
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
    Scroll() {
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          // 连线层：普通组件（不是画布），坐标与下面的节点同一套，先声明所以在底层
          ForEach(this.wires, (wire: OutlineWire, index: number) => {
            this.wireLine(wire)
          }, (wire: OutlineWire, index: number) => this.wireKey(wire, index))
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
          ForEach(this.placed, (node: PlacedNode) => {
            if (node.childCount > 0) {
              this.foldBadge(node)
            }
          }, (node: PlacedNode) => 'fold' + this.nodeKey(node) + (node.collapsed ? 'c' : 'e'))
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
    if (tag === 'balanced') {
      if (!this.balanced) {
        this.toggleLayout()
      }
      return
    }
    if (tag === 'right') {
      if (this.balanced) {
        this.toggleLayout()
      }
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
    }
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
          this.panelChip('左右', this.balanced, 'balanced')
          this.panelChip('向右', !this.balanced, 'right')
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

        this.panelTitle('节点')
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          this.panelChip('卡片', this.nodeStyle === 'card', 'card')
          this.panelChip('线框', this.nodeStyle === 'line', 'line')
          this.panelChip('无框', this.nodeStyle === 'plain', 'plain')
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

  build() {
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
  }
}
