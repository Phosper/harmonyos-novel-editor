// 只读导图（结构包）
//
// 范围（用户确认）：从标题派生、点主题回到正文；**不做编辑**，不改正文结构。
// 优先级：桌面 / MatePad Edge 电脑模式先可用；手机端等后续再单独排版。
//
// 数据来源：宿主打开本页前把快照 publish 到 core_runtime，这里只读（ADR-003 §2.3）。
// 返回正文：把要跳到的偏移写回宿主，由宿主关闭本页后定位——导图包不直接操作编辑器。
import {
  MindMapLayout, OutlineSnapshot, PlacedNode, OUTLINE_NODE_H, OUTLINE_NODE_W,
  layoutOutline, outlineParents
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
}

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
  /** 每个节点在 placed 里的父索引（-1 = 根） */
  private parents: number[] = []
  /**
   * 连线用 Canvas 画，不用 Path。
   * 原因：Path 的 commands 坐标与组件尺寸单位实测不一致（真机上只画出一小段），
   * 而 CanvasRenderingContext2D 的坐标就是 vp，和思路板点阵背景同一套已验证的画法。
   */
  private connCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))

  aboutToAppear(): void {
    this.load()
  }

  private load(): void {
    const snapshot: OutlineSnapshot | null = outlineService().current()
    // 只有根节点 = 文稿还没有标题：空态引导，不画一张只有一个点的图
    if (snapshot === null || snapshot.nodes.length <= 1) {
      this.empty = true
      this.topicCount = 0
      return
    }
    const layout: MindMapLayout = layoutOutline(snapshot.nodes, null, this.zoom)
    this.placed = layout.nodes
    this.mapW = layout.width
    this.mapH = layout.height
    this.topicCount = layout.nodes.length - 1
    this.parents = outlineParents(snapshot.nodes)
    this.empty = false
    if (this.selectedIndex >= this.placed.length) {
      this.selectedIndex = -1
    }
    // 诊断：真机上一眼确认"节点/画布/连线"三组数字，排查渲染问题比看截图快
    console.info('[StructureMap] nodes=' + this.placed.length.toString() +
      ' topics=' + this.topicCount.toString() +
      ' map=' + this.mapW.toFixed(1) + 'x' + this.mapH.toFixed(1) +
      ' links=' + Math.max(0, this.placed.length - 1).toString())
    // Canvas 可能还没 ready（此时绘制会被忽略），onReady 里会再画一次
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

  /** 键盘：方向键选节点、Enter 回正文、Esc 关闭 */
  private handleKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || this.placed.length === 0) {
      return false
    }
    const code: number = event.keyCode
    if (code === 2070) {
      this.onClose()
      return true
    }
    if (code === 2012 || code === 2013) {
      const step: number = code === 2012 ? -1 : 1
      const base: number = this.selectedIndex < 0 ? (step > 0 ? -1 : this.placed.length) : this.selectedIndex
      const next: number = Math.max(0, Math.min(this.placed.length - 1, base + step))
      this.selectedIndex = next
      return true
    }
    if (code === 2054 || code === 2116) {
      if (this.selectedIndex >= 0 && this.selectedIndex < this.placed.length) {
        this.jumpTo(this.placed[this.selectedIndex].startOffset)
      }
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
      const parent: number = this.parents[i]
      if (parent < 0) {
        continue
      }
      const from: PlacedNode = this.placed[parent]
      const to: PlacedNode = this.placed[i]
      const fromW: number = OUTLINE_NODE_W * from.scale
      const fromH: number = OUTLINE_NODE_H * from.scale
      const toH: number = OUTLINE_NODE_H * to.scale
      const x1: number = from.x + fromW
      const y1: number = from.y + fromH / 2
      const x2: number = to.x
      const y2: number = to.y + toH / 2
      const mid: number = (x1 + x2) / 2
      ctx.beginPath()
      ctx.moveTo(x1, y1)
      ctx.bezierCurveTo(mid, y1, mid, y2, x2, y2)
      ctx.stroke()
    }
  }

  /** 点主题：记下偏移、请求宿主回正文（本包不碰编辑器） */
  private jumpTo(offset: number): void {
    outlineService().requestReveal(offset)
    this.onClose()
  }

  private titleOf(): string {
    const snapshot: OutlineSnapshot | null = outlineService().current()
    if (snapshot !== null && snapshot.docTitle !== '') {
      return snapshot.docTitle
    }
    return this.docTitle === '' ? '结构' : this.docTitle
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
    .accessibilityText('主题：' + n.title + '，点击回到正文')
    .onClick(() => { this.jumpTo(n.startOffset) })
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
        // 桌面端一次看到整棵树：外层横向 + 内层纵向（ScrollDirection.Free 已废弃，改用嵌套）
        Scroll() {
          Scroll() {
            Stack({ alignContent: Alignment.TopStart }) {
              // 连线层在最底下，不参与命中
              Canvas(this.connCtx)
                .width(this.mapW)
                .height(this.mapH)
                .hitTestBehavior(HitTestMode.None)
                .accessibilityLevel('no')
                .onReady(() => { this.drawConnections() })
              ForEach(this.placed, (node: PlacedNode, index: number) => {
                this.nodeChip(node, index)
              }, (node: PlacedNode) => node.id)
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
