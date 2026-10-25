// 白板库面板（思路板页内的浮层）
//
// 只做三件事：按「课程白板 / 自由白板」两类列出现有白板、标出当前板、新建。
// 数据只读 CanvasStore（app.canvas），本组件不回写 Store 之外的任何状态：
// 选中与新建都通过 @Event 交回 CanvasDest，由它去 selectBoard / 落首选项。
//
// 形态：竖长条浮层（宽屏 360vp / 手机 320vp），圆角与字号沿用 SettingsPanel 的写法。
import { tokensFor, WeaverColorSet, WeaverRadii, TypeScale, WeaverSpacing } from '../constants/DesignTokens'
import { CanvasBoardScope } from '../model/CanvasTypes'
import { Logger } from '../utils/Logger'
import { app } from '../store/AppStores'

/** 一行白板（视图模型）：模板里不直接摸 Store 的字段，Store 换实现也不影响这里 */
interface CanvasBoardRow {
  id: string
  title: string
  count: number
}

@ComponentV2
export struct CanvasBoardLibrary {
  /** 选中某块白板（回调里做 selectBoard + 记住最近板） */
  @Event onSelect: (boardId: string) => void = () => {}
  /** 关闭面板 */
  @Event onClose: () => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private tablet(): boolean {
    return app.ui.tabletMode
  }

  private panelWidth(): number {
    return this.tablet() ? 360 : 320
  }

  private titleFont(): number {
    return this.tablet() ? 17 : TypeScale.HEADLINE
  }

  private rowFont(): number {
    return this.tablet() ? 16 : TypeScale.BODY
  }

  private captionFont(): number {
    return this.tablet() ? 13 : TypeScale.CAPTION
  }

  private cardRadius(): number {
    return this.tablet() ? 18 : 14
  }

  /** 该类别的白板行；类别过滤在这里做，模板只负责画 */
  private rowsOf(scope: CanvasBoardScope): CanvasBoardRow[] {
    const out: CanvasBoardRow[] = []
    const boards = app.canvas.boards
    for (let i: number = 0; i < boards.length; i++) {
      const board = boards[i]
      if (board.scope === scope) {
        // 卡数走 store 的同步查询（A 确认：基于全量贴放，不滞后、不需要 COUNT 查询）
        const row: CanvasBoardRow = { id: board.id, title: board.title, count: app.canvas.boardCardCount(board.id) }
        out.push(row)
      }
    }
    return out
  }

  private isCurrent(boardId: string): boolean {
    return app.canvas.currentBoardId === boardId
  }

  private countLabel(row: CanvasBoardRow): string {
    return row.count.toString() + ' 张卡'
  }

  /**
   * 新建白板：标题先给默认名（重命名走白板自身的后续入口，不在这里弹输入框，
   * 避免在画布页叠第二层模态）。失败只记日志并保持面板不动。
   */
  private createBoard(scope: CanvasBoardScope): void {
    const title: string = scope === CanvasBoardScope.COURSE ? '新课程白板' : '新白板'
    app.canvas.createBoard(scope, title).then((created) => {
      if (created !== undefined) {
        this.onSelect(created.id)
      }
    }).catch((e: Error) => {
      Logger.error('CanvasBoardLibrary: createBoard failed: ' + String(e))
    })
  }

  @Builder
  groupHeader(text: string) {
    Text(text)
      .fontSize(this.captionFont())
      .fontColor(this.colors().textTertiary)
      .width('100%')
      .padding({ left: WeaverSpacing.XS, top: WeaverSpacing.MD, bottom: WeaverSpacing.SM })
  }

  @Builder
  boardRow(row: CanvasBoardRow) {
    Row() {
      Column() {
        Text(row.title)
          .fontSize(this.rowFont())
          .fontWeight(this.isCurrent(row.id) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.isCurrent(row.id) ? this.colors().brand : this.colors().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.countLabel(row))
          .fontSize(this.captionFont())
          .fontColor(this.colors().textTertiary)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isCurrent(row.id)) {
        Text('当前')
          .fontSize(TypeScale.MICRO)
          .fontColor(this.colors().brand)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.colors().activeBg)
          .borderRadius(WeaverRadii.XS)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.tablet() ? 56 : 52 })
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(WeaverRadii.SM)
    .backgroundColor(this.isCurrent(row.id) ? this.colors().activeBg : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(row.title + '，' + this.countLabel(row) + (this.isCurrent(row.id) ? '，当前白板' : ''))
    .onClick(() => this.onSelect(row.id))
  }

  @Builder
  createRow(scope: CanvasBoardScope, text: string) {
    Row() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(13)
        .fontColor([this.colors().brand])
      Text(text)
        .fontSize(this.captionFont())
        .fontColor(this.colors().brand)
        .margin({ left: 6 })
    }
    .width('100%')
    .constraintSize({ minHeight: this.tablet() ? 48 : 44 })
    .padding({ left: 10, right: 10 })
    .borderRadius(WeaverRadii.SM)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(text)
    .onClick(() => this.createBoard(scope))
  }

  @Builder
  group(scope: CanvasBoardScope, header: string, createText: string, emptyText: string) {
    this.groupHeader(header)
    if (this.rowsOf(scope).length === 0) {
      Text(emptyText)
        .fontSize(this.captionFont())
        .fontColor(this.colors().textTertiary)
        .width('100%')
        .padding({ left: 10, top: 4, bottom: 6 })
    } else {
      ForEach(this.rowsOf(scope), (row: CanvasBoardRow) => {
        this.boardRow(row)
      }, (row: CanvasBoardRow): string => row.id)
    }
    this.createRow(scope, createText)
  }

  build() {
    Column() {
      Row() {
        Text('白板')
          .fontSize(this.titleFont())
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors().textPrimary)
          .layoutWeight(1)
        Text('✕')
          .fontSize(15)
          .fontColor(this.colors().textTertiary)
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .accessibilityText('关闭白板库')
          .onClick(() => this.onClose())
      }
      .width('100%')
      .padding({ left: WeaverSpacing.LG, right: WeaverSpacing.LG, top: WeaverSpacing.MD, bottom: WeaverSpacing.SM })

      Scroll() {
        Column() {
          this.group(CanvasBoardScope.COURSE, '课程白板', '新建课程白板', '还没有课程白板')
          this.group(CanvasBoardScope.FREE, '自由白板', '新建自由白板', '还没有自由白板')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
      .padding({ left: WeaverSpacing.SM, right: WeaverSpacing.SM, bottom: WeaverSpacing.SM })
    }
    .width(this.panelWidth())
    .height('100%')
    // 浮层用卡片面 + 1px 边框分出层级；不做实时模糊（每屏模糊预算留给顶栏）
    .backgroundColor(this.colors().bgCard)
    .borderRadius(this.cardRadius())
    .border({ width: 1, color: this.colors().divider })
    .clip(true)
  }
}
