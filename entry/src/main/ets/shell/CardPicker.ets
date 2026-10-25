// 编辑器选区 → 加到卡片：轻量选卡面板
//
// 只负责“选一张已有卡 / 新建一张概念卡”，不负责贴到白板（捕获不等于上板）。
// 数据全部读 CanvasStore；写动作只有 createCard，素材由调用方落库。
import { tokensFor, WeaverColorSet, WeaverRadii, TypeScale, WeaverSpacing } from '../constants/DesignTokens'
import { CanvasCardKind } from '../model/CanvasTypes'
import type { CanvasCardItem } from '../model/CanvasStoreModels'
import { app, fireAndLog } from '../store/AppStores'

interface PickerRow {
  id: string
  title: string
  meta: string
}

@ComponentV2
export struct CardPicker {
  /** 选中文字预览（只读，避免面板里再复制一份正文） */
  @Param quoteText: string = ''
  @Event onPick: (cardId: string) => void = (cardId: string) => {}
  @Event onClose: () => void = () => {}

  @Local keyword: string = ''
  @Local newTitle: string = ''

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private rows(): PickerRow[] {
    const q: string = this.keyword.trim().toLowerCase()
    const out: PickerRow[] = []
    for (let i: number = 0; i < app.canvas.cards.length; i++) {
      const c: CanvasCardItem = app.canvas.cards[i]
      if (q !== '' && !c.title.toLowerCase().includes(q) &&
        !c.aliases.toLowerCase().includes(q) && !c.tags.toLowerCase().includes(q)) {
        continue
      }
      const kind: string = c.kind === CanvasCardKind.WRITING ? '写作卡' : '概念卡'
      out.push({
        id: c.id,
        title: c.title,
        meta: kind + ' · ' + app.canvas.occurrences(c.id).length.toString() + ' 块白板'
      })
    }
    return out
  }

  private createCard(): void {
    const title: string = this.newTitle.trim()
    if (title === '') {
      return
    }
    fireAndLog(app.canvas.createCard(CanvasCardKind.CONCEPT, title).then((card: CanvasCardItem | undefined) => {
      if (card !== undefined) {
        this.onPick(card.id)
      }
    }), 'CardPicker.createCard')
  }

  @Builder
  rowItem(row: PickerRow) {
    Column() {
      Text(row.title)
        .fontSize(TypeScale.BODY)
        .fontColor(this.colors().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(row.meta)
        .fontSize(TypeScale.CAPTION)
        .fontColor(this.colors().textTertiary)
        .margin({ top: 1 })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .borderRadius(WeaverRadii.SM)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onPick(row.id))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => this.onClose())

      Column() {
        Row() {
          Text('加到卡片')
            .fontSize(TypeScale.HEADLINE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.colors().textPrimary)
            .layoutWeight(1)
          Text('✕')
            .fontSize(15)
            .fontColor(this.colors().textTertiary)
            .padding({ left: 10, right: 4, top: 4, bottom: 4 })
            .onClick(() => this.onClose())
            .accessibilityText('关闭选卡面板')
        }
        .width('100%')

        Text('“' + this.quoteText + '”')
          .fontSize(TypeScale.CAPTION)
          .fontColor(this.colors().textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding(9)
          .backgroundColor(this.colors().activeBg)
          .borderRadius(8)
          .margin({ top: 8 })

        Search({ value: this.keyword, placeholder: '搜索卡片（标题 / 别名 / 标签）' })
          .onChange((value: string) => { this.keyword = value })
          .width('100%')
          .height(38)
          .backgroundColor(this.colors().bgSurface)
          .border({ width: 1, color: this.colors().divider })
          .borderRadius(WeaverRadii.SM)
          .margin({ top: 8 })

        if (this.rows().length === 0) {
          Text(this.keyword.trim() === '' ? '还没有卡片，先在下面新建一张' : '没有匹配的卡片')
            .fontSize(TypeScale.CAPTION)
            .fontColor(this.colors().textTertiary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 18, bottom: 18 })
        } else {
          List() {
            ForEach(this.rows(), (row: PickerRow) => {
              ListItem() {
                this.rowItem(row)
              }
            }, (row: PickerRow): string => row.id)
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 1, color: this.colors().divider })
          .scrollBar(BarState.Auto)
        }

        Row() {
          TextInput({ text: this.newTitle, placeholder: '新建概念卡…' })
            .onChange((value: string) => { this.newTitle = value })
            .onSubmit(() => this.createCard())
            .height(36)
            .layoutWeight(1)
            .backgroundColor(this.colors().bgSurface)
            .border({ width: 1, color: this.colors().divider })
            .borderRadius(WeaverRadii.SM)
          Button('新建并加入')
            .fontSize(TypeScale.CAPTION)
            .height(36)
            .margin({ left: 8 })
            .backgroundColor(this.newTitle.trim() === '' ? this.colors().activeBg : this.colors().brand)
            .fontColor(this.newTitle.trim() === '' ? this.colors().textTertiary : this.colors().onBrand)
            .borderRadius(WeaverRadii.SM)
            .enabled(this.newTitle.trim() !== '')
            .onClick(() => this.createCard())
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('92%')
      .height(440)
      .constraintSize({ maxWidth: 360 })
      .padding(WeaverSpacing.LG)
      .backgroundColor(this.colors().bgCard)
      .borderRadius(16)
      .border({ width: 1, color: this.colors().divider })
      .shadow({ radius: 30, color: this.colors().divider, offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
  }
}
