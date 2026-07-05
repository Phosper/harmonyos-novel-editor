// InspirationCreatePage.ets
import { router } from '@kit.ArkUI'
import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { InspirationDao } from '@ohos/material'
import { BookDao } from '@ohos/editor'
import type { InspirationModel, BookModel } from '@ohos/common'

@Entry
@Component
struct InspirationCreatePage {
  @State content: string = ''
  @State bookId: string | null = null
  @State bookName: string = '暂不归类'
  @State books: BookModel[] = []
  @State showBookPicker: boolean = false

  async aboutToAppear(): Promise<void> {
    const raw: Object = router.getParams()
    const entries: [string, Object][] = Object.entries(raw)
    for (let i = 0; i < entries.length; i++) {
      if (entries[i][0] === 'bookId') {
        this.bookId = String(entries[i][1])
      }
    }
    const dao: BookDao = new BookDao()
    this.books = await dao.queryAll()
  }

  selectBook(id: string | null, name: string): void {
    this.bookId = id
    this.bookName = name
    this.showBookPicker = false
  }

  async save(): Promise<void> {
    if (this.content.trim() === '') return
    const dao: InspirationDao = new InspirationDao()
    const model: InspirationModel = {
      id: IdGenerator.generate(),
      bookId: this.bookId,
      content: this.content.trim(),
      createdAt: Date.now()
    }
    await dao.insert(model)
    router.back()
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() { Text('←').fontSize(20) }.width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
        Text('新建灵感').fontSize(20).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button('保存').fontSize(14).fontColor(GreenColors.G500).backgroundColor(Color.Transparent)
          .onClick(() => { this.save() })
      }
      .width('100%').height(56).padding({ left: 8, right: 8 })
      .backgroundColor(SemanticColors.BG_CARD)

      // Book attribution
      Row() {
        Text('归属').fontSize(14).fontColor(GrayColors.G500).width(60)
        Row() {
          Text(this.bookName).fontSize(14).fontColor(GreenColors.G500).layoutWeight(1)
          Text('▼').fontSize(12).fontColor(GrayColors.G300)
        }
        .onClick(() => { this.showBookPicker = !this.showBookPicker })
      }
      .width('100%').height(48).padding({ left: 16, right: 16 })
      .backgroundColor(SemanticColors.BG_CARD)

      if (this.showBookPicker) {
        Column() {
          Text('暂不归类').fontSize(14)
            .fontColor(this.bookId === null ? GreenColors.G500 : GrayColors.G700)
            .padding(12)
            .onClick(() => { this.selectBook(null, '暂不归类') })

          ForEach(this.books, (book: BookModel) => {
            Text(book.name).fontSize(14)
              .fontColor(this.bookId === book.id ? GreenColors.G500 : GrayColors.G700)
              .padding(12)
              .onClick(() => { this.selectBook(book.id, book.name) })
          }, (book: BookModel) => book.id)
        }
        .width('100%').backgroundColor(GrayColors.G50).padding({ left: 16 })
      }

      // Content input
      TextArea({ text: $$this.content, placeholder: '记录你的灵感...' })
        .fontSize(16).fontColor(GrayColors.G900)
        .placeholderColor(GrayColors.G300)
        .backgroundColor(SemanticColors.BG_CARD)
        .padding(16)
        .layoutWeight(1)
        .margin({ top: 8 })
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
