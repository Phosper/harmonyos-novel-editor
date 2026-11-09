// 思路板 · 卡片（概念卡 / 写作卡 + C 型子卡行）
//
// 规格来源：docs/design/canvas-contract.md §3/§5、AI 施工单 §6.2/§6.4。
// 本文件只负责「一张卡长什么样 + 卡内手势采集」，所有落库动作都通过 @Event 抛给 CanvasPane，
// 避免叶子组件直接持有 Store（只有取色与编号这类纯函数依赖 CanvasTheme）。
//
// 关键约定：
// - 空卡不显示任何占位或提示（没有素材就不画素材行，没有子卡就不画脊线）。
// - 有子卡才有左侧 3vp 实线脊线，子卡行缩进嵌在脊线内。
// - 拖拽只用「基准 + 累计」：卡片位移动画由 CanvasPane 给的 dragOffsetX/Y（累计 offset）驱动，
//   本组件不自行累加 delta，也不改世界坐标（世界坐标只有在松手后由 Store 落库）。
import { KeyCode } from '@kit.InputKit'
import { CanvasCardData, CanvasPlacementData, CanvasCardKind } from '../model/CanvasTypes'
import { CanvasSpec } from '../constants/CanvasSpec'
import { DEFAULT_THEME_ID } from '../constants/DesignTokens'
import {
  canvasPalette, CanvasPalette, CanvasRowView, CanvasDragKind, CanvasLayout,
  canvasTitleSize, canvasMetaSize, canvasCardWidth
} from './CanvasTheme'

@ComponentV2
export struct TopicCard {
  @Require @Param cardData: CanvasCardData
  @Require @Param placementData: CanvasPlacementData
  @Require @Param rows: CanvasRowView[]
  /** 屏幕坐标（vp）= 世界坐标 * zoom + pan，由 CanvasPane 算好 */
  @Require @Param screenX: number
  @Require @Param screenY: number
  @Require @Param zoom: number
  /** 当前选中的卡（顶栏/抽屉联动） */
  @Param selectedId: string = ''
  /** 当前卡的素材数（由 CanvasPane 从 Store 汇总） */
  @Param materialCount: number = 0
  /** 是否张嘴（只有拖动且放得进去才为 true） */
  @Param mouthOn: boolean = false
  /** 缺口插在第几行之前（>= rows.length 表示末尾） */
  @Param mouthInsert: number = 0
  /** 缺口缩进层级（1..3） */
  @Param mouthDepth: number = 1
  /** 拖动累计偏移（屏幕 vp）；非拖动卡恒为 0 */
  @Param dragOffsetX: number = 0
  @Param dragOffsetY: number = 0
  @Param dragActive: boolean = false
  @Param themeId: string = DEFAULT_THEME_ID

  @Event onOpenCard: (cardId: string) => void = (cardId: string) => {}
  @Event onCardDragStart: (cardId: string, kind: CanvasDragKind, winX: number, winY: number) => void =
    (cardId: string, kind: CanvasDragKind, winX: number, winY: number) => {}
  @Event onDragFrame: (cardId: string, kind: CanvasDragKind, dx: number, dy: number,
    winX: number, winY: number) => void =
    (cardId: string, kind: CanvasDragKind, dx: number, dy: number, winX: number, winY: number) => {}
  @Event onDragFinish: (cardId: string, kind: CanvasDragKind, dx: number, dy: number,
    winX: number, winY: number) => void =
    (cardId: string, kind: CanvasDragKind, dx: number, dy: number, winX: number, winY: number) => {}
  @Event onDragCancel: () => void = () => {}
  @Event onRowUp: (cardId: string) => void = (cardId: string) => {}
  @Event onRowDown: (cardId: string) => void = (cardId: string) => {}
  @Event onRowOut: (cardId: string) => void = (cardId: string) => {}
  @Event onWriteDraft: (cardId: string) => void = (cardId: string) => {}
  @Event onOpenDraft: (cardId: string) => void = (cardId: string) => {}
  @Event onAddChapter: (cardId: string) => void = (cardId: string) => {}
  @Event onRenameCard: (cardId: string) => void = (cardId: string) => {}
  @Event onCardMenu: (cardId: string) => void = (cardId: string) => {}
  /** 卡片实际高度 / 子卡区起点（屏幕 vp，交给 CanvasPane 换算世界坐标） */
  @Event onGeometry: (cardId: string, cardHeight: number, bodyTop: number) => void =
    (cardId: string, cardHeight: number, bodyTop: number) => {}

  @Local hoverRowId: string = ''
  @Local draggingRowId: string = ''
  /** 按下点（window 坐标，vp）：拖动时用它推算指针世界坐标 */
  private pointerWinX: number = 0
  private pointerWinY: number = 0
  /** 最近一次 PanGesture 的累计偏移（onActionEnd 的 event 不保证带 offset，故自己记） */
  private lastDx: number = 0
  private lastDy: number = 0
  private measuredHeight: number = 0
  private measuredBodyTop: number = 0

  private pal(): CanvasPalette {
    return canvasPalette(this.themeId)
  }

  private isWriting(): boolean {
    return this.cardData.kind === CanvasCardKind.WRITING
  }

  private cardW(): number {
    return canvasCardWidth(this.cardData.kind) * this.zoom
  }

  /** 子卡数：rows 已含整棵子树，统计 depth===1 即直接子卡 */
  private childCount(): number {
    let n: number = 0
    for (let i: number = 0; i < this.rows.length; i++) {
      if (this.rows[i].depth === 1) {
        n++
      }
    }
    return n
  }

  private countByDepth(depth: number): number {
    let n: number = 0
    for (let i: number = 0; i < this.rows.length; i++) {
      if (this.rows[i].depth === depth) {
        n++
      }
    }
    return n
  }

  /** 写作卡的「N 章 · M 节 · K 目」 */
  private writingMeta(): string {
    let meta: string = this.countByDepth(1).toString() + ' 章 · ' + this.countByDepth(2).toString() +
      ' 节 · ' + this.countByDepth(3).toString() + ' 目'
    // 有子卡时把总数写进副标题：即使子卡行被滚动/遮挡，也能一眼看出「卡里有东西」
    if (this.rows.length > 0) {
      meta += ' · 含 ' + this.rows.length.toString() + ' 张子卡'
    }
    return meta
  }

  /** 概念卡只写素材数；没有素材就整行不显示（空卡无占位） */
  private conceptMeta(): string {
    return this.materialCount > 0 ? this.materialCount.toString() + ' 条素材' : ''
  }

  private tagList(): string[] {
    const raw: string = this.cardData.tags
    if (raw === '') {
      return []
    }
    const parts: string[] = raw.split(',')
    const out: string[] = []
    for (let i: number = 0; i < parts.length; i++) {
      const one: string = parts[i].trim()
      if (one !== '') {
        out.push(one)
      }
    }
    return out
  }

  private tagKey(tag: string, idx: number): string {
    return this.cardData.id + ':tag:' + idx.toString() + ':' + tag
  }

  private rowKey(row: CanvasRowView): string {
    return row.placementId
  }

  private rowActionsVisible(cardId: string): boolean {
    return this.hoverRowId === cardId || this.selectedId === cardId || this.draggingRowId === cardId
  }

  private rowBg(cardId: string): string {
    if (this.draggingRowId === cardId) {
      return this.pal().hoverBg
    }
    if (this.selectedId === cardId) {
      return this.pal().activeBg
    }
    if (this.hoverRowId === cardId) {
      return this.pal().hoverBg
    }
    return this.pal().cardBg
  }

  private accessibilityLabel(): string {
    return this.cardData.title + '，' + this.childCount().toString() + ' 张子卡，' +
      this.materialCount.toString() + ' 条素材，顶层卡片'
  }

  /** 记录按下点：window 坐标 px → vp；行与卡片共用 */
  private capturePointer(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    this.pointerWinX = this.getUIContext().px2vp(event.touches[0].windowX)
    this.pointerWinY = this.getUIContext().px2vp(event.touches[0].windowY)
  }

  /** 卡片高度与子卡区起点都测量到之后再上报，避免半截几何 */
  private flushGeometry(): void {
    if (this.measuredHeight <= 0) {
      return
    }
    this.onGeometry(this.cardData.id, this.measuredHeight, this.measuredBodyTop)
  }

  /** C 型脊线：只在有子卡时出现 */
  @Builder
  ridgeBody() {
    Column() {
      ForEach(this.rows, (row: CanvasRowView, index: number) => {
        if (this.mouthOn && this.mouthInsert === index) {
          this.mouthGap()
        }
        this.rowItem(row)
      }, (row: CanvasRowView): string => this.rowKey(row))
      if (this.mouthOn && this.mouthInsert >= this.rows.length) {
        this.mouthGap()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: CanvasLayout.BODY_LEFT * this.zoom, top: 2 * this.zoom, bottom: 2 * this.zoom })
    .border({ width: { left: CanvasLayout.RIDGE_WIDTH * this.zoom }, color: { left: this.pal().ridge } })
    .margin({ top: 10 * this.zoom })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.measuredBodyTop = Number(newValue.position.y)
      this.flushGeometry()
    })
  }

  /** 张嘴缺口：30vp 虚线块，插在目标行的子树之后，缩进比目标行深一级 */
  @Builder
  mouthGap() {
    Column()
      .width(this.depthIndent(this.mouthDepth))
      .height(CanvasSpec.MOUTH_HEIGHT * this.zoom)
      .borderRadius(8 * this.zoom)
      .border({
        width: 1.5 * this.zoom,
        color: this.pal().accent,
        style: BorderStyle.Dashed
      })
      .backgroundColor(this.pal().accentSoft)
      .margin({ top: 6 * this.zoom, bottom: 2 * this.zoom })
  }

  /** 缺口缩进：相对子卡区左缘，按层级递进 */
  private depthIndent(depth: number): number {
    const level: number = depth >= 1 ? depth - 1 : 0
    return this.cardW() - CanvasLayout.BODY_CONTENT_LEFT * this.zoom -
      level * CanvasSpec.INDENT * this.zoom - CanvasLayout.ROW_PAD_X * this.zoom
  }

  private rowIndent(depth: number): number {
    const level: number = depth >= 1 ? depth - 1 : 0
    return level * CanvasSpec.INDENT * this.zoom + CanvasLayout.ROW_PAD_X * this.zoom
  }

  @Builder
  rowItem(row: CanvasRowView) {
    Row() {
      Text(row.numbering)
        .fontSize(11 * this.zoom)
        .fontColor(this.pal().accent)
        .fontWeight(FontWeight.Medium)
        .width(CanvasLayout.NUM_W * this.zoom)
        .maxLines(1)
      Text(row.title)
        .fontSize(13 * this.zoom)
        .fontColor(this.pal().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (row.isWriting) {
        Text('写作卡')
          .fontSize(10 * this.zoom)
          .fontColor(this.pal().accent)
          .margin({ left: 4 * this.zoom })
      } else if (row.materialCount > 0) {
        Text(row.materialCount.toString())
          .fontSize(10.5 * this.zoom)
          .fontColor(this.pal().textTertiary)
          .margin({ left: 4 * this.zoom })
      }
      if (this.rowActionsVisible(row.cardId)) {
        this.rowActions(row)
      }
    }
    .width('100%')
    .height(CanvasSpec.ROW_HEIGHT * this.zoom)
    .padding({ left: this.rowIndent(row.depth), right: CanvasLayout.ROW_PAD_X * this.zoom })
    .backgroundColor(this.rowBg(row.cardId))
    .borderRadius(7 * this.zoom)
    .opacity(this.draggingRowId === row.cardId ? 0.5 : 1)
    .focusable(true)
    .onFocus(() => {
      this.hoverRowId = row.cardId
    })
    .onBlur(() => {
      if (this.hoverRowId === row.cardId) {
        this.hoverRowId = ''
      }
    })
    .onHover((isHover: boolean) => {
      this.hoverRowId = isHover ? row.cardId : ''
    })
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ENTER) {
        this.onOpenCard(row.cardId)
        return true
      }
      return false
    })
    .onTouch((event: TouchEvent) => {
      this.capturePointer(event)
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: CanvasLayout.DRAG_DISTANCE })
          .onActionStart((event: GestureEvent) => {
            this.lastDx = 0
            this.lastDy = 0
            this.draggingRowId = row.cardId
            this.onCardDragStart(row.cardId, CanvasDragKind.ROW, this.pointerWinX, this.pointerWinY)
          })
          .onActionUpdate((event: GestureEvent) => {
            this.lastDx = event.offsetX
            this.lastDy = event.offsetY
            this.onDragFrame(row.cardId, CanvasDragKind.ROW, this.lastDx, this.lastDy,
              this.pointerWinX, this.pointerWinY)
          })
          .onActionEnd((event: GestureEvent) => {
            this.draggingRowId = ''
            this.onDragFinish(row.cardId, CanvasDragKind.ROW, this.lastDx, this.lastDy,
              this.pointerWinX, this.pointerWinY)
          })
          .onActionCancel(() => {
            this.draggingRowId = ''
            this.onDragCancel()
          }),
        TapGesture({ fingers: 1, count: 1 })
          .onAction(() => {
            this.onOpenCard(row.cardId)
          })
      )
    )
    .onMouse((event: MouseEvent) => {
      if (event.action === MouseAction.Press && event.button === MouseButton.Right) {
        this.onCardMenu(row.cardId)
      }
    })
    .accessibilityText(row.numbering + row.title + '，' + this.depthLabelOf(row.depth) +
      '，' + row.materialCount.toString() + ' 条素材')
    .accessibilityLevel('yes')
  }

  private depthLabelOf(depth: number): string {
    if (depth === 1) {
      return '章'
    }
    if (depth === 2) {
      return '节'
    }
    return '目'
  }

  /** 行尾 ▲▼↗：悬停/选中才出现；点击不冒泡到行的打开手势（子组件优先） */
  @Builder
  rowActions(row: CanvasRowView) {
    Row() {
      Text('▲')
        .fontSize(10 * this.zoom)
        .fontColor(this.pal().textTertiary)
        .width(CanvasLayout.ROW_ACTION_W * this.zoom)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onRowUp(row.cardId)
        })
        .accessibilityText('上移')
      Text('▼')
        .fontSize(10 * this.zoom)
        .fontColor(this.pal().textTertiary)
        .width(CanvasLayout.ROW_ACTION_W * this.zoom)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onRowDown(row.cardId)
        })
        .accessibilityText('下移')
      Text('↗')
        .fontSize(10 * this.zoom)
        .fontColor(this.pal().textTertiary)
        .width(CanvasLayout.ROW_ACTION_W * this.zoom)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onRowOut(row.cardId)
        })
        .accessibilityText('移出到画布')
      Text('✎')
        .fontSize(10 * this.zoom)
        .fontColor(this.pal().textTertiary)
        .width(CanvasLayout.ROW_ACTION_W * this.zoom)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onRenameCard(row.cardId)
        })
        .accessibilityText('重命名')
    }
    .margin({ left: 2 * this.zoom })
  }

  @Builder
  writingBadge() {
    Text('写作卡')
      .fontSize(10 * this.zoom)
      .fontColor(this.pal().accent)
      .backgroundColor(this.pal().accentSoft)
      .borderRadius(99)
      .border({ width: 1, color: this.pal().accentLine })
      .padding({ left: 7 * this.zoom, right: 7 * this.zoom, top: 1 * this.zoom, bottom: 1 * this.zoom })
      .margin({ bottom: 6 * this.zoom })
  }

  @Builder
  tagRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.tagList(), (tag: string, idx: number) => {
        Text(tag)
          .fontSize(10.5 * this.zoom)
          .fontColor(this.pal().textSecondary)
          .backgroundColor(this.pal().activeBg)
          .borderRadius(99)
          .padding({ left: 7 * this.zoom, right: 7 * this.zoom, top: 1 * this.zoom, bottom: 1 * this.zoom })
          .margin({ right: 4 * this.zoom, bottom: 4 * this.zoom })
      }, (tag: string, idx: number): string => this.tagKey(tag, idx))
    }
    .width('100%')
    .margin({ top: 8 * this.zoom })
  }

  @Builder
  writingFoot() {
    Row() {
      Text(this.countByDepth(1).toString() + ' 章')
        .fontSize(11.5 * this.zoom)
        .fontColor(this.pal().textSecondary)
      Blank()
      if (this.cardData.docId !== '') {
        Text('打开初稿')
          .fontSize(11.5 * this.zoom)
          .fontColor(this.pal().textSecondary)
          .borderRadius(8 * this.zoom)
          .border({ width: 1, color: this.pal().divider })
          .padding({ left: 8 * this.zoom, right: 8 * this.zoom, top: 5 * this.zoom, bottom: 5 * this.zoom })
          .margin({ right: 6 * this.zoom })
          .onClick(() => {
            this.onOpenDraft(this.cardData.id)
          })
          .accessibilityText('打开初稿')
      }
      Text('写成初稿')
        .fontSize(11.5 * this.zoom)
        .fontColor(this.pal().onBrand)
        .backgroundColor(this.pal().textPrimary)
        .borderRadius(8 * this.zoom)
        .padding({ left: 10 * this.zoom, right: 10 * this.zoom, top: 5 * this.zoom, bottom: 5 * this.zoom })
        .onClick(() => {
          this.onWriteDraft(this.cardData.id)
        })
        .accessibilityText('写成初稿，新建一篇文稿')
    }
    .width('100%')
    .margin({ top: 9 * this.zoom })
    .padding({ top: 8 * this.zoom })
    .border({ width: { top: 1 }, color: { top: this.pal().divider } })
  }

  build() {
    Column() {
      if (this.isWriting()) {
        this.writingBadge()
      }
      Text(this.cardData.title)
        .fontSize(canvasTitleSize(this.cardData.kind, this.zoom))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal().textPrimary)
        .lineHeight(canvasTitleSize(this.cardData.kind, this.zoom) * 1.35)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.isWriting()) {
        Text(this.writingMeta())
          .fontSize(canvasMetaSize(this.zoom))
          .fontColor(this.pal().textTertiary)
          .margin({ top: 2 * this.zoom })
          .width('100%')
      } else if (this.conceptMeta() !== '') {
        Text(this.conceptMeta())
          .fontSize(canvasMetaSize(this.zoom))
          .fontColor(this.pal().textTertiary)
          .margin({ top: 2 * this.zoom })
          .width('100%')
      }
      if (!this.isWriting() && this.tagList().length > 0) {
        this.tagRow()
      }
      if (this.rows.length > 0) {
        this.ridgeBody()
      }
      if (this.isWriting()) {
        this.writingFoot()
        Text('＋ 添加一章')
          .fontSize(11.5 * this.zoom)
          .fontColor(this.pal().accent)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6 * this.zoom, bottom: 6 * this.zoom })
          .border({ width: 1, color: this.pal().divider, style: BorderStyle.Dashed })
          .borderRadius(7 * this.zoom)
          .margin({ top: 7 * this.zoom })
          .onClick(() => {
            this.onAddChapter(this.cardData.id)
          })
          .accessibilityText('添加一章')
      }
    }
    .id('canvas-card-' + this.placementData.id)
    .width(this.cardW())
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: CanvasLayout.CARD_PAD * this.zoom,
      right: CanvasLayout.CARD_PAD * this.zoom,
      top: CanvasLayout.CARD_PAD * this.zoom,
      bottom: CanvasLayout.CARD_PAD * this.zoom
    })
    .backgroundColor(this.pal().cardBg)
    .borderRadius(CanvasLayout.CARD_RADIUS * this.zoom)
    .border({
      width: 1,
      color: this.selectedId === this.cardData.id || this.mouthOn
        ? this.pal().cardBorderActive
        : this.pal().cardBorder
    })
    .shadow({
      radius: this.dragActive ? 18 : 6,
      color: this.pal().divider,
      offsetX: 0,
      offsetY: this.dragActive ? 8 : 2
    })
    .opacity(this.dragActive ? 0.94 : 1)
    .position({ x: this.screenX, y: this.screenY })
    .translate({ x: this.dragOffsetX, y: this.dragOffsetY })
    .zIndex(this.dragActive ? 10 : 1)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.measuredHeight = Number(newValue.height)
      this.flushGeometry()
    })
    .onTouch((event: TouchEvent) => {
      this.capturePointer(event)
    })
    .onMouse((event: MouseEvent) => {
      if (event.action === MouseAction.Press && event.button === MouseButton.Right) {
        this.onCardMenu(this.cardData.id)
      }
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: CanvasLayout.DRAG_DISTANCE })
          .onActionStart((event: GestureEvent) => {
            this.lastDx = 0
            this.lastDy = 0
            this.onCardDragStart(this.cardData.id, CanvasDragKind.CARD, this.pointerWinX, this.pointerWinY)
          })
          .onActionUpdate((event: GestureEvent) => {
            this.lastDx = event.offsetX
            this.lastDy = event.offsetY
            this.onDragFrame(this.cardData.id, CanvasDragKind.CARD, this.lastDx, this.lastDy,
              this.pointerWinX, this.pointerWinY)
          })
          .onActionEnd((event: GestureEvent) => {
            this.onDragFinish(this.cardData.id, CanvasDragKind.CARD, this.lastDx, this.lastDy,
              this.pointerWinX, this.pointerWinY)
          })
          .onActionCancel(() => {
            this.onDragCancel()
          }),
        TapGesture({ fingers: 1, count: 1 })
          .onAction(() => {
            this.onOpenCard(this.cardData.id)
          }),
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.onCardMenu(this.cardData.id)
          })
      )
    )
    .focusable(true)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ENTER) {
        this.onOpenCard(this.cardData.id)
        return true
      }
      return false
    })
    .accessibilityText(this.accessibilityLabel())
    .accessibilityLevel('yes')
  }
}
