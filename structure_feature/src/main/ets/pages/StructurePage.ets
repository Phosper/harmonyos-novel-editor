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
  @Event onClose: () => void = () => {}

  @Local placed: PlacedNode[] = []
  @Local mapW: number = 0
  @Local mapH: number = 0
  @Local empty: boolean = true
  @Local topicCount: number = 0
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
    const layout: MindMapLayout = layoutOutline(snapshot.nodes)
    this.placed = layout.nodes
    this.mapW = layout.width
    this.mapH = layout.height
    this.topicCount = layout.nodes.length - 1
    this.parents = outlineParents(snapshot.nodes)
    this.empty = false
    // 诊断：真机上一眼确认"节点/画布/连线"三组数字，排查渲染问题比看截图快
    console.info('[StructureMap] nodes=' + this.placed.length.toString() +
      ' topics=' + this.topicCount.toString() +
      ' map=' + this.mapW.toFixed(1) + 'x' + this.mapH.toFixed(1) +
      ' links=' + Math.max(0, this.placed.length - 1).toString())
    // Canvas 可能还没 ready（此时绘制会被忽略），onReady 里会再画一次
    this.drawConnections()
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
      const x1: number = from.x + OUTLINE_NODE_W
      const y1: number = from.y + OUTLINE_NODE_H / 2
      const x2: number = to.x
      const y2: number = to.y + OUTLINE_NODE_H / 2
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
        .margin({ right: 16 })

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
    .padding({ left: 20, right: 16 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: this.theme.divider })
  }

  @Builder
  nodeChip(n: PlacedNode) {
    Row() {
      Text(n.title)
        .fontSize(n.depth === 0 ? 13 : 12)
        .fontWeight(n.depth === 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(n.depth === 0 ? this.theme.onBrand : this.theme.text)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width(OUTLINE_NODE_W)
    .height(OUTLINE_NODE_H)
    .padding({ left: 10, right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(n.depth === 0 ? this.theme.brand : this.theme.card)
    .borderRadius(10)
    .border({ width: n.depth === 0 ? 0 : 1, color: this.theme.divider })
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
              ForEach(this.placed, (node: PlacedNode) => {
                this.nodeChip(node)
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
  }
}
