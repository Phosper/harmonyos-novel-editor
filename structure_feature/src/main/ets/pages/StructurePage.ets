// 文稿绑定导图（结构包）
//
// 数据：宿主 publish 一份 OutlineSnapshot（节点带稳定 paraId）；本页只读快照、只发命令。
// 编辑：改名/新建/升降级/删除/移动都发 OutlineCommand 给 core_runtime，宿主改正文后回传新快照。
// 边界：本包不 import entry、不碰正文；折叠与选中是视图态。
import {
  MindMapLayout, OutlineSnapshot, PlacedNode, OutlineCommand, OutlineCommandKind,
  OUTLINE_NODE_H, OUTLINE_NODE_W, layoutOutline, outlineParents
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

  /** 每个节点在 placed 里的父索引（-1 = 根） */
  private parents: number[] = []
  /**
   * 连线用 Canvas 画，不用 Path（Path 的 commands 单位与组件尺寸不一致，真机上只画出一小段）。
   */
  private connCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

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
      this.mapW = 0
      this.mapH = 0
      this.selectedIndex = -1
      return
    }
    const selectedParaId: string = this.selectedParaId()
    const layout: MindMapLayout = layoutOutline(snapshot.nodes, null, this.zoom)
    this.placed = layout.nodes
    this.mapW = layout.width
    this.mapH = layout.height
    this.topicCount = layout.nodes.length - 1
    this.parents = outlineParents(snapshot.nodes)
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
    this.drawConnections()
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

  /** 画父子连线：三次贝塞尔，端点取父节点右缘中点与子节点左缘中点 */
  private drawConnections(): void {
    const ctx: CanvasRenderingContext2D = this.connCtx
    if (this.mapW <= 0 || this.mapH <= 0 || this.placed.length === 0) {
      return
    }
    ctx.clearRect(0, 0, this.mapW, this.mapH)
    ctx.strokeStyle = this.theme.divider
    ctx.lineWidth = 1.2
    for (let i: number = 1; i < this.placed.length; i++) {
      const parent: number = this.placed[i].parentIndex
      if (parent < 0 || parent >= this.placed.length) {
        continue
      }
      const from: PlacedNode = this.placed[parent]
      const to: PlacedNode = this.placed[i]
      const x1: number = from.x + OUTLINE_NODE_W * from.scale
      const y1: number = from.y + OUTLINE_NODE_H * from.scale / 2
      const x2: number = to.x
      const y2: number = to.y + OUTLINE_NODE_H * to.scale / 2
      const mid: number = (x1 + x2) / 2
      ctx.beginPath()
      ctx.moveTo(x1, y1)
      ctx.bezierCurveTo(mid, y1, mid, y2, x2, y2)
      ctx.stroke()
    }
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
              Canvas(this.connCtx)
                .width(this.mapW)
                .height(this.mapH)
                .hitTestBehavior(HitTestMode.None)
                .accessibilityLevel('no')
                .onReady(() => { this.drawConnections() })
              ForEach(this.placed, (node: PlacedNode, index: number) => {
                this.nodeChip(node, index)
              }, (node: PlacedNode) => node.paraId === '' ? node.id : node.paraId)
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
