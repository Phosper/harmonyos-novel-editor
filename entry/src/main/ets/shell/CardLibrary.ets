// 卡片库抽屉（思路板页内的右侧浮层）
//
// 一张卡可以同时出现在多块白板上，所以这里列的是**全库卡片**，不是当前板的卡：
//   - 按 标题 / 别名 / 标签 过滤；
//   - 每行显示「N 块白板」（来自 CanvasStore.occurrences）；
//   - 「放到当前白板」只负责把卡贴到当前板，已经在板上则禁用（避免重复贴放）。
//
// 放的动作交回 CanvasDest（它知道当前板的落点策略），本组件只读 Store、不改 Store。
import { tokensFor, WeaverColorSet, WeaverRadii, TypeScale, WeaverSpacing } from '../constants/DesignTokens'
import { CanvasSpec } from '../constants/CanvasSpec'
import { CanvasCardKind, canvasFindPlacement } from '../model/CanvasTypes'
import type { CanvasCardItem } from '../model/CanvasStoreModels'
import { app, fireAndLog } from '../store/AppStores'

/** 一行卡片（视图模型）：标题 + 副标题 + 出现板数 + 是否已在当前板 */
interface CanvasCardRow {
  id: string
  title: string
  meta: string
  kind: CanvasCardKind
  boardCount: number
  onCurrentBoard: boolean
  updatedAt: number
}

@ComponentV2
export struct CardLibrary {
  /** 把某张卡放到当前白板（CanvasDest 负责 addPlacement 的坐标） */
  @Event onAdd: (cardId: string) => void = () => {}
  /** 批量放到当前白板 */
  @Event onAddMany: (cardIds: string[]) => void = (cardIds: string[]) => {}
  /** 关闭抽屉 */
  @Event onClose: () => void = () => {}

  @Local keyword: string = ''
  /** 新建卡片表单（首版只收标题 + 类型；别名/标签在卡片抽屉里再补） */
  @Local creating: boolean = false
  @Local newTitle: string = ''
  @Local newKind: CanvasCardKind = CanvasCardKind.CONCEPT
  /** 0 全部 / 1 概念 / 2 写作 */
  @Local kindFilter: number = 0
  /** 0 最近使用 / 1 标题 */
  @Local sortMode: number = 0
  @Local confirmDeleteId: string = ''
  @Local selecting: boolean = false
  @Local selectedIds: string[] = []

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private tablet(): boolean {
    return app.ui.tabletMode
  }

  /** 宽屏抽屉宽度按契约（CanvasSpec.DRAWER_WIDTH）；手机整屏，由 build 里的 '100%' 决定 */
  private panelWidth(): number {
    return CanvasSpec.DRAWER_WIDTH
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

  /** 标题/别名/标签 任一命中即保留 */
  private matches(title: string, aliases: string, tags: string, q: string): boolean {
    if (q === '') {
      return true
    }
    return title.toLowerCase().includes(q) || aliases.toLowerCase().includes(q) || tags.toLowerCase().includes(q)
  }

  private rows(): CanvasCardRow[] {
    const out: CanvasCardRow[] = []
    const q: string = this.keyword.trim().toLowerCase()
    const cards = app.canvas.cards
    for (let i: number = 0; i < cards.length; i++) {
      const card = cards[i]
      if (!this.matches(card.title, card.aliases, card.tags, q)) {
        continue
      }
      if (this.kindFilter === 1 && card.kind !== CanvasCardKind.CONCEPT) {
        continue
      }
      if (this.kindFilter === 2 && card.kind !== CanvasCardKind.WRITING) {
        continue
      }
      const placed: boolean = canvasFindPlacement(app.canvas.placements, card.id) !== undefined
      const row: CanvasCardRow = {
        id: card.id,
        title: card.title,
        meta: card.aliases,
        kind: card.kind,
        boardCount: app.canvas.occurrences(card.id).length,
        onCurrentBoard: placed,
        updatedAt: card.updatedAt
      }
      out.push(row)
    }
    if (this.sortMode === 0) {
      out.sort((a: CanvasCardRow, b: CanvasCardRow): number => b.updatedAt - a.updatedAt)
    } else {
      out.sort((a: CanvasCardRow, b: CanvasCardRow): number => a.title < b.title ? -1 : 1)
    }
    return out
  }

  private toggleSelect(cardId: string): void {
    const at: number = this.selectedIds.indexOf(cardId)
    if (at >= 0) {
      this.selectedIds = this.selectedIds.filter((id: string): boolean => id !== cardId)
    } else {
      this.selectedIds = this.selectedIds.concat([cardId])
    }
  }

  private boardCountLabel(row: CanvasCardRow): string {
    if (row.boardCount === 0) {
      return '还没放到白板'
    }
    return row.boardCount.toString() + ' 块白板'
  }

  private submitCreate(): void {
    const title: string = this.newTitle.trim()
    if (title === '') {
      return
    }
    fireAndLog(app.canvas.createCard(this.newKind, title).then((card: CanvasCardItem | undefined) => {
      if (card === undefined) {
        return
      }
      this.newTitle = ''
      this.creating = false
      this.onAdd(card.id)
    }), 'CardLibrary.createCard')
  }

  @Builder
  filterChip(label: string, value: number) {
    Text(label)
      .fontSize(this.captionFont())
      .fontColor(this.kindFilter === value ? this.colors().onBrand : this.colors().textSecondary)
      .backgroundColor(this.kindFilter === value ? this.colors().textPrimary : this.colors().bgSurface)
      .borderRadius(99)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .margin({ right: 6 })
      .onClick(() => {
        this.kindFilter = value
      })
  }

  @Builder
  kindChip(label: string, kind: CanvasCardKind) {
    Text(label)
      .fontSize(this.captionFont())
      .fontColor(this.newKind === kind ? this.colors().onBrand : this.colors().textSecondary)
      .backgroundColor(this.newKind === kind ? this.colors().brand : this.colors().bgSurface)
      .border({ width: 1, color: this.newKind === kind ? this.colors().brand : this.colors().divider })
      .borderRadius(WeaverRadii.SM)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .onClick(() => {
        this.newKind = kind
      })
  }

  @Builder
  createForm() {
    Column() {
      TextInput({ text: this.newTitle, placeholder: '卡片标题，例如「均势」' })
        .onChange((value: string) => {
          this.newTitle = value
        })
        .height(this.tablet() ? 44 : 38)
        .backgroundColor(this.colors().bgSurface)
        .border({ width: 1, color: this.colors().divider })
        .borderRadius(WeaverRadii.SM)
      Row() {
        this.kindChip('概念卡', CanvasCardKind.CONCEPT)
        this.kindChip('写作卡', CanvasCardKind.WRITING)
        Blank()
        Button('创建')
          .fontSize(this.captionFont())
          .height(this.tablet() ? 36 : 32)
          .backgroundColor(this.newTitle.trim() === '' ? this.colors().activeBg : this.colors().brand)
          .fontColor(this.newTitle.trim() === '' ? this.colors().textTertiary : this.colors().onBrand)
          .borderRadius(WeaverRadii.SM)
          .enabled(this.newTitle.trim() !== '')
          .onClick(() => {
            this.submitCreate()
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .margin({ top: 8 })
  }

  private emptyText(): string {
    return this.keyword.trim() === '' ? '还没有卡片' : '没有匹配的卡片'
  }

  @Builder
  cardRow(row: CanvasCardRow) {
    Row() {
      Column() {
        Row() {
          if (this.selecting) {
            Text(this.selectedIds.includes(row.id) ? '✓' : '○')
              .fontSize(this.rowFont())
              .fontColor(this.selectedIds.includes(row.id) ? this.colors().brand : this.colors().textTertiary)
              .margin({ right: 6 })
              .onClick(() => {
                this.toggleSelect(row.id)
              })
              .accessibilityText(this.selectedIds.includes(row.id) ? '取消选择' : '选择卡片')
          }
          Text(row.kind === CanvasCardKind.WRITING ? '写作' : '概念')
            .fontSize(this.captionFont() - 1)
            .fontColor(this.colors().textTertiary)
            .backgroundColor(this.colors().activeBg)
            .borderRadius(4)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .margin({ right: 6 })
          Text(row.title)
            .fontSize(this.rowFont())
          .fontColor(this.colors().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        Row() {
          Text(this.boardCountLabel(row))
            .fontSize(this.captionFont())
            .fontColor(this.colors().textTertiary)
          if (row.meta !== '') {
            Text(row.meta)
              .fontSize(this.captionFont())
              .fontColor(this.colors().textTertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .margin({ top: 2 })
        Row() {
          Text('复制')
            .fontSize(this.captionFont() - 1)
            .fontColor(this.colors().textTertiary)
            .padding({ right: 10, top: 3, bottom: 3 })
            .onClick(() => {
              fireAndLog(app.canvas.duplicateCard(row.id), 'CardLibrary.duplicateCard')
            })
          if (row.onCurrentBoard) {
            Text('从当前白板移除')
              .fontSize(this.captionFont() - 1)
              .fontColor(this.colors().textTertiary)
              .padding({ right: 10, top: 3, bottom: 3 })
              .onClick(() => {
                fireAndLog(app.canvas.removePlacement(row.id), 'CardLibrary.removePlacement')
              })
          }
          Text(this.confirmDeleteId === row.id ? '再点一次删除' : '删除')
            .fontSize(this.captionFont() - 1)
            .fontColor(this.colors().danger)
            .padding({ top: 3, bottom: 3 })
            .onClick(() => {
              if (this.confirmDeleteId !== row.id) {
                this.confirmDeleteId = row.id
                return
              }
              this.confirmDeleteId = ''
              fireAndLog(app.canvas.deleteCard(row.id), 'CardLibrary.deleteCard')
            })
        }
        .width('100%')
        .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(row.onCurrentBoard ? '已在当前白板' : '放到当前白板')
        .fontSize(this.captionFont())
        .height(this.tablet() ? 36 : 32)
        .backgroundColor(row.onCurrentBoard ? this.colors().activeBg : this.colors().brand)
        .fontColor(row.onCurrentBoard ? this.colors().textTertiary : this.colors().onBrand)
        .borderRadius(WeaverRadii.SM)
        .enabled(!row.onCurrentBoard)
        .accessibilityText(row.onCurrentBoard ? '已在当前白板' : '放到当前白板')
        .onClick(() => this.onAdd(row.id))
    }
    .width('100%')
    .constraintSize({ minHeight: this.tablet() ? 64 : 56 })
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(WeaverRadii.SM)
    .hoverEffect(HoverEffect.Highlight)
  }

  build() {
    Column() {
      Row() {
        Text('卡片库')
          .fontSize(this.titleFont())
          .fontWeight(FontWeight.Bold)
          .fontColor(this.colors().textPrimary)
          .layoutWeight(1)
        Text('✕')
          .fontSize(15)
          .fontColor(this.colors().textTertiary)
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .accessibilityText('关闭卡片库')
          .onClick(() => this.onClose())
      }
      .width('100%')
      .padding({ left: WeaverSpacing.LG, right: WeaverSpacing.LG, top: WeaverSpacing.MD, bottom: WeaverSpacing.SM })

      Row() {
        this.filterChip('全部', 0)
        this.filterChip('概念', 1)
        this.filterChip('写作', 2)
        Blank()
        Text(this.sortMode === 0 ? '最近' : '标题')
          .fontSize(this.captionFont())
          .fontColor(this.colors().textSecondary)
          .padding({ left: 8, right: 4, top: 3, bottom: 3 })
          .onClick(() => {
            this.sortMode = this.sortMode === 0 ? 1 : 0
          })
        Text(this.selecting ? '取消' : '选择')
          .fontSize(this.captionFont())
          .fontColor(this.selecting ? this.colors().brand : this.colors().textSecondary)
          .padding({ left: 8, right: 2, top: 3, bottom: 3 })
          .onClick(() => {
            this.selecting = !this.selecting
            this.selectedIds = []
          })
      }
      .width('100%')
      .padding({ left: WeaverSpacing.LG, right: WeaverSpacing.LG, bottom: WeaverSpacing.SM })

      Row() {
        Text(this.creating ? '收起新建' : '＋ 新建卡片')
          .fontSize(this.captionFont())
          .fontColor(this.colors().brand)
          .padding({ top: 4, bottom: 4 })
          .onClick(() => {
            this.creating = !this.creating
          })
        Blank()
      }
      .width('100%')
      .margin({ top: 2, bottom: 2 })

      if (this.creating) {
        this.createForm()
      }

      Search({ value: this.keyword, placeholder: '搜索卡片（标题 / 别名 / 标签）' })
        .onChange((v: string) => { this.keyword = v })
        .width('100%')
        .height(this.tablet() ? 44 : 36)
        .backgroundColor(this.colors().bgSurface)
        .border({ width: 1, color: this.colors().divider })
        .borderRadius(WeaverRadii.SM)

      if (this.rows().length === 0) {
        Column() {
          Text(this.emptyText())
            .fontSize(this.captionFont())
            .fontColor(this.colors().textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows(), (row: CanvasCardRow) => {
            ListItem() {
              this.cardRow(row)
            }
          }, (row: CanvasCardRow): string => row.id)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .divider({ strokeWidth: 1, color: this.colors().divider })
        .scrollBar(BarState.Auto)
      }
      if (this.selecting) {
        Row() {
          Text('已选 ' + this.selectedIds.length.toString() + ' 张')
            .fontSize(this.captionFont())
            .fontColor(this.colors().textSecondary)
            .layoutWeight(1)
          Button('放到当前白板')
            .fontSize(this.captionFont())
            .height(this.tablet() ? 36 : 32)
            .backgroundColor(this.selectedIds.length === 0 ? this.colors().activeBg : this.colors().brand)
            .fontColor(this.selectedIds.length === 0 ? this.colors().textTertiary : this.colors().onBrand)
            .borderRadius(WeaverRadii.SM)
            .enabled(this.selectedIds.length > 0)
            .onClick(() => {
              const ids: string[] = this.selectedIds.slice()
              this.selecting = false
              this.selectedIds = []
              this.onAddMany(ids)
            })
        }
        .width('100%')
        .padding({ left: WeaverSpacing.LG, right: WeaverSpacing.LG, top: 8, bottom: 8 })
        .border({ width: { top: 1 }, color: { top: this.colors().divider } })
      }
    }
    .width(this.tablet() ? this.panelWidth() : '100%')
    .height('100%')
    // 抽屉面：卡片面 + 1px 边框；零实时模糊（模糊预算留给顶栏）
    .backgroundColor(this.colors().bgCard)
    .borderRadius(this.cardRadius())
    .border({ width: 1, color: this.colors().divider })
    .clip(true)
    .padding({ left: WeaverSpacing.SM, right: WeaverSpacing.SM, bottom: WeaverSpacing.SM })
  }
}
