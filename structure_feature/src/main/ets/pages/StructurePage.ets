// 文稿绑定导图（结构包）
//
// 数据：宿主 publish 一份 OutlineSnapshot（节点带稳定 paraId）；本页只读快照、只发命令。
// 编辑：改名/新建/升降级/删除/移动都发 OutlineCommand 给 core_runtime，宿主改正文后回传新快照。
// 边界：本包不 import entry、不碰正文；折叠与选中是视图态。
import {
  MindMapLayout, OutlineSnapshot, PlacedNode, OutlineCommand, OutlineCommandKind, OutlineWire,
  OUTLINE_NODE_H, OUTLINE_NODE_W, OUTLINE_LAYOUT_BALANCED, OUTLINE_LAYOUT_RIGHT,
  layoutOutline, outlineConnectors, outlineWires
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
    this.wires = outlineWires(outlineConnectors(this.placed))
    this.layoutRev = this.layoutRev + 1
    this.empty = false
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
    this.renaming = false
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
      Text(this.balanced ? '左右' : '向右')
        .fontSize(12).fontColor(this.theme.sub)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .accessibilityText(this.balanced ? '切换为一直向右的布局' : '切换为左右均衡布局')
        .onClick(() => { this.toggleLayout() })
      if (this.collapsedIds.length > 0) {
        Text('展开全部')
          .fontSize(12).fontColor(this.theme.sub)
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .accessibilityText('展开所有折叠的主题')
          .onClick(() => { this.expandAll() })
      }

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
      .stroke(this.theme.divider)
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

  @Builder
  nodeChip(n: PlacedNode, index: number) {
    Row() {
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
    .backgroundColor(n.depth === 0 ? this.theme.brand : this.theme.card)
    .borderRadius(10)
    .border({
      width: this.selectedIndex === index ? 2 : (n.depth === 0 ? 0 : 1),
      color: this.selectedIndex === index ? this.theme.brand : this.theme.divider
    })
    .position({ x: n.x, y: n.y })
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText('主题：' + n.title + '，回车新建同级，Tab 新建子级，双击回到正文')
    .onClick(() => { this.selectAt(index) })
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

  build() {
    Column() {
      this.header()
      if (this.empty) {
        this.emptyView()
      } else {
        // 外层横向 + 内层纵向（ScrollDirection.Free 已废弃）
        Scroll() {
          Scroll() {
            Stack({ alignContent: Alignment.TopStart }) {
              // 连线层：普通组件（不是画布），坐标与下面的节点同一套，先声明所以在底层
              ForEach(this.wires, (wire: OutlineWire, index: number) => {
                this.wireLine(wire)
              }, (wire: OutlineWire, index: number) => this.wireKey(wire, index))
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
        .width('100%')
        .align(Alignment.TopStart)
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
