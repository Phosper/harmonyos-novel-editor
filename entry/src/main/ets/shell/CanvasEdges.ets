// 思路板 · 连线层
//
// 规格来源：AI 施工单 §6.1 / §6.4（连线段），契约 §5。
// 只画「已有连线」：几何全部由 CanvasPane 在世界坐标算好后乘 zoom + pan 传进来，
// 本组件不读 Store、不做命中（hitTestBehavior None，绝不抢卡片手势）。
// 端点取卡片或行的实际矩形（嵌套卡用行矩形），由 CanvasPane 决定，这里只认屏幕坐标。
import { DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { canvasPalette, CanvasPalette, CanvasEdgeLine } from './CanvasTheme'

@ComponentV2
export struct CanvasEdges {
  /** 每条线的 commands 已是屏幕坐标（vp），label 位置同样 */
  @Require @Param lines: CanvasEdgeLine[]
  @Require @Param canvasWidth: number
  @Require @Param canvasHeight: number
  @Param themeId: string = DEFAULT_THEME_ID

  private pal(): CanvasPalette {
    return canvasPalette(this.themeId)
  }

  private lineKey(line: CanvasEdgeLine): string {
    return line.linkId
  }

  private labelKey(line: CanvasEdgeLine): string {
    return 'label:' + line.linkId
  }

  /** 一条连线：贝塞尔主曲线 + 箭头（同一 Path 的多段子路径） */
  @Builder
  edgePath(line: CanvasEdgeLine) {
    Path()
      .width(this.canvasWidth)
      .height(this.canvasHeight)
      .position({ x: 0, y: 0 })
      .commands(line.commands)
      .fillOpacity(0)
      .stroke(this.pal().textSecondary)
      .strokeWidth(1.4)
      .opacity(0.85)
  }

  /** 关系标签：小圆角底 + 文本，压在曲线中点附近 */
  @Builder
  edgeLabel(line: CanvasEdgeLine) {
    Text(line.label)
      .fontSize(10.5)
      .fontColor(this.pal().textSecondary)
      .backgroundColor(this.pal().paper)
      .borderRadius(9)
      .border({ width: 1, color: this.pal().divider })
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .position({ x: line.labelX - line.labelWidth / 2, y: line.labelY - 9 })
  }

  build() {
    Stack() {
      ForEach(this.lines, (line: CanvasEdgeLine) => {
        this.edgePath(line)
      }, (line: CanvasEdgeLine): string => this.lineKey(line))
      ForEach(this.lines, (line: CanvasEdgeLine) => {
        if (line.label !== '') {
          this.edgeLabel(line)
        }
      }, (line: CanvasEdgeLine): string => this.labelKey(line))
    }
    .width(this.canvasWidth)
    .height(this.canvasHeight)
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
