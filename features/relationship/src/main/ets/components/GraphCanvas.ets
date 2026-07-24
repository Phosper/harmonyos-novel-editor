import { router } from '@kit.ArkUI'
import { GraphColors, GrayColors, SemanticColors, GreenColors, IdGenerator } from '@ohos/common'
import { RelationshipDao } from '../data/RelationshipDao'
import type { RelationshipModel } from '@ohos/common'

export interface GraphNode {
  characterId: string
  name: string
  type: string
  x: number
  y: number
  radius: number
  isHighlighted: boolean
  isDimmed: boolean
}

export interface GraphEdge {
  id: string
  fromId: string
  toId: string
  type: string
  label: string
}

@Component
export struct GraphCanvas {
  @Link @Watch('onGraphChanged') nodes: GraphNode[]
  @Link @Watch('onGraphChanged') edges: GraphEdge[]
  @Link panOffsetX: number
  @Link panOffsetY: number
  @Link canvasScale: number
  @Link selectedRelId: string
  onNodeTap?: (characterId: string) => void
  onNodeLongPress?: (characterId: string) => void
  onSwipeConnect?: (fromId: string, toId: string) => void
  onDoubleTapCanvas?: () => void

  @State canvasW: number = 300
  @State canvasH: number = 300
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private lastPanX: number = 0
  private lastPanY: number = 0
  private swipeFromNodeId: string = ''
  private isSwipeConnect: boolean = false

  onGraphChanged(): void {
    this.performLayout()
    this.draw()
  }

  performLayout(): void {
    const n: number = this.nodes.length
    if (n === 0) return
    const cx: number = this.canvasW / 2
    const cy: number = this.canvasH / 2
    const layoutRadius: number = Math.min(this.canvasW, this.canvasH) * 0.32
    const nodeRadius: number = Math.max(28, Math.min(40, layoutRadius * 0.25))
    for (let i: number = 0; i < n; i++) {
      const angle: number = (i / n) * Math.PI * 2 - Math.PI / 2
      this.nodes[i].x = cx + layoutRadius * Math.cos(angle)
      this.nodes[i].y = cy + layoutRadius * Math.sin(angle)
      this.nodes[i].radius = nodeRadius
    }
  }

  draw(): void {
    this.ctx.clearRect(0, 0, this.canvasW, this.canvasH)
    this.ctx.save()
    this.ctx.translate(this.panOffsetX, this.panOffsetY)
    this.ctx.scale(this.canvasScale, this.canvasScale)
    this.drawEdges()
    this.drawNodes()
    this.ctx.restore()
  }

  drawEdges(): void {
    if (this.edges.length === 0) return
    for (let i: number = 0; i < this.edges.length; i++) {
      const e: GraphEdge = this.edges[i]
      const fromNode: GraphNode | undefined = this.nodes.find((n: GraphNode) => n.characterId === e.fromId)
      const toNode: GraphNode | undefined = this.nodes.find((n: GraphNode) => n.characterId === e.toId)
      if (fromNode === undefined || toNode === undefined) continue

      const isSelected: boolean = e.id === this.selectedRelId
      this.ctx.beginPath()
      this.ctx.moveTo(fromNode.x, fromNode.y)
      this.ctx.lineTo(toNode.x, toNode.y)

      if (e.type === 'positive') {
        this.ctx.strokeStyle = isSelected ? GraphColors.HIGHLIGHT_RING : GraphColors.LINE_POSITIVE
        this.ctx.lineWidth = isSelected ? 4 : 2.5
        this.ctx.setLineDash([])
      } else if (e.type === 'negative') {
        this.ctx.strokeStyle = isSelected ? GraphColors.HIGHLIGHT_RING : GraphColors.LINE_NEGATIVE
        this.ctx.lineWidth = isSelected ? 3 : 2
        this.ctx.setLineDash([6, 4])
      } else {
        this.ctx.strokeStyle = isSelected ? GraphColors.HIGHLIGHT_RING : GraphColors.LINE_NEUTRAL
        this.ctx.lineWidth = isSelected ? 2.5 : 1.5
        this.ctx.setLineDash(e.type === 'indirect' ? [3, 5] : [])
      }
      this.ctx.stroke()

      if (e.label !== '') {
        const mx: number = (fromNode.x + toNode.x) / 2
        const my: number = (fromNode.y + toNode.y) / 2
        this.ctx.font = '10px sans-serif'
        this.ctx.fillStyle = GrayColors.G500
        this.ctx.textAlign = 'center'
        this.ctx.textBaseline = 'middle'
        this.ctx.fillText(e.label, mx, my - 10)
      }
      this.ctx.setLineDash([])
    }
  }

  drawNodes(): void {
    if (this.nodes.length === 0) return
    for (let i: number = 0; i < this.nodes.length; i++) {
      const node: GraphNode = this.nodes[i]

      // Fill
      this.ctx.beginPath()
      this.ctx.arc(node.x, node.y, node.radius, 0, Math.PI * 2)
      if (node.isDimmed) {
        this.ctx.fillStyle = GrayColors.G100
        this.ctx.globalAlpha = 0.4
      } else {
        this.ctx.fillStyle = this.getNodeColor(node.type)
        this.ctx.globalAlpha = 1.0
      }
      this.ctx.fill()
      this.ctx.globalAlpha = 1.0

      // Highlight ring
      if (node.isHighlighted) {
        this.ctx.beginPath()
        this.ctx.arc(node.x, node.y, node.radius + 3, 0, Math.PI * 2)
        this.ctx.strokeStyle = GraphColors.HIGHLIGHT_RING
        this.ctx.lineWidth = 2.5
        this.ctx.stroke()
      }

      // Text (adaptive font size based on node radius)
      const abbr: string = this.getAbbreviation(node.name)
      const fontSize: number = Math.max(18, Math.min(30, node.radius * 0.9))
      this.ctx.font = fontSize.toString() + 'px sans-serif'
      this.ctx.fillStyle = '#FFFFFF'
      this.ctx.textAlign = 'center'
      this.ctx.textBaseline = 'middle'
      this.ctx.fillText(abbr, node.x, node.y)
    }
  }

  getNodeColor(nodeType: string): string {
    if (nodeType === 'protagonist') return GraphColors.NODE_MAIN
    if (nodeType === 'villain') return GraphColors.NODE_VILLAIN
    if (nodeType === 'org') return GraphColors.NODE_ORG
    if (nodeType === 'place') return GraphColors.NODE_PLACE
    return GraphColors.NODE_SUPPORT
  }

  getAbbreviation(name: string): string {
    if (name.length <= 2) return name
    const firstCode: number = name.charCodeAt(0)
    const isLatin: boolean = (firstCode >= 65 && firstCode <= 90) || (firstCode >= 97 && firstCode <= 122)
    if (isLatin) {
      const parts: string[] = name.split(' ')
      if (parts.length >= 2) {
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
      }
      return name.substring(0, 2).toUpperCase()
    }
    return name.substring(0, 2)
  }

  canvasToNodeCoord(localX: number, localY: number): GraphNode | null {
    const cx: number = (localX - this.panOffsetX) / this.canvasScale
    const cy: number = (localY - this.panOffsetY) / this.canvasScale
    for (let i: number = 0; i < this.nodes.length; i++) {
      const node: GraphNode = this.nodes[i]
      const dx: number = cx - node.x
      const dy: number = cy - node.y
      if (dx * dx + dy * dy <= node.radius * node.radius) {
        return node
      }
    }
    return null
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%').height('100%')
        .backgroundColor(GraphColors.BG_CANVAS)
        .onReady(() => {
          this.canvasW = this.ctx.width
          this.canvasH = this.ctx.height
          this.performLayout()
          this.draw()
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionUpdate((event: GestureEvent) => {
                const newScale: number = this.canvasScale * event.scale
                this.canvasScale = Math.max(0.25, Math.min(3.0, newScale))
                this.draw()
              }),
            GestureGroup(GestureMode.Exclusive,
              LongPressGesture({ duration: 500 })
                .onAction((event: GestureEvent) => {
                  const node: GraphNode | null = this.canvasToNodeCoord(event.fingerList[0].localX,
                    event.fingerList[0].localY)
                  if (node !== null && this.onNodeLongPress) {
                    this.onNodeLongPress(node.characterId)
                  }
                }),
              TapGesture({ count: 2 })
                .onAction((event: GestureEvent) => {
                  const node: GraphNode | null = this.canvasToNodeCoord(event.fingerList[0].localX,
                    event.fingerList[0].localY)
                  if (node === null && this.onDoubleTapCanvas) {
                    this.onDoubleTapCanvas()
                  }
                }),
              TapGesture({ count: 1 })
                .onAction((event: GestureEvent) => {
                  const node: GraphNode | null = this.canvasToNodeCoord(event.fingerList[0].localX,
                    event.fingerList[0].localY)
                  if (node !== null && this.onNodeTap) {
                    this.onNodeTap(node.characterId)
                  }
                }),
              PanGesture({ fingers: 1, direction: PanDirection.All })
                .onActionStart((event: GestureEvent) => {
                  const node: GraphNode | null = this.canvasToNodeCoord(event.fingerList[0].localX,
                    event.fingerList[0].localY)
                  if (node !== null && this.onSwipeConnect) {
                    this.swipeFromNodeId = node.characterId
                    this.isSwipeConnect = true
                  } else {
                    this.swipeFromNodeId = ''
                    this.isSwipeConnect = false
                  }
                  this.lastPanX = this.panOffsetX
                  this.lastPanY = this.panOffsetY
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.isSwipeConnect) {
                    this.draw()
                  } else {
                    this.panOffsetX = this.lastPanX + event.offsetX
                    this.panOffsetY = this.lastPanY + event.offsetY
                    this.draw()
                  }
                })
                .onActionEnd((event: GestureEvent) => {
                  if (this.isSwipeConnect && this.swipeFromNodeId !== '' && this.onSwipeConnect) {
                    const toNode: GraphNode | null = this.canvasToNodeCoord(event.fingerList[0].localX,
                      event.fingerList[0].localY)
                    if (toNode !== null && toNode.characterId !== this.swipeFromNodeId) {
                      this.onSwipeConnect(this.swipeFromNodeId, toNode.characterId)
                    }
                  }
                  this.swipeFromNodeId = ''
                  this.isSwipeConnect = false
                })
            )
          )
        )

      // Empty state overlay
      if (this.nodes.length === 0) {
        Column() {
          Text('🕸').fontSize(36).margin({ bottom: 12 })
          Text('暂无人物节点').fontSize(14).fontColor(GrayColors.G500)
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%').height('100%')
  }
}
