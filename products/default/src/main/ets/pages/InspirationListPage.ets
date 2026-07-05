// InspirationListPage.ets
import { router } from '@kit.ArkUI'
import { SemanticColors, GrayColors, GreenColors } from '@ohos/common'
import { InspirationDao } from '@ohos/material'
import { BookDao } from '@ohos/editor'
import type { InspirationModel, BookModel } from '@ohos/common'

@Entry
@Component
struct InspirationListPage {
  @State inspirations: InspirationModel[] = []
  @State bookFilter: string = 'all'
  @State searchText: string = ''
  @State books: BookModel[] = []

  async aboutToAppear(): Promise<void> {
    const dao: InspirationDao = new InspirationDao()
    this.inspirations = await dao.queryAll()
    const bookDao: BookDao = new BookDao()
    this.books = await bookDao.queryAll()
  }

  getBookName(bookId: string | null): string {
    if (bookId === null) return '暂不归类'
    const book: BookModel | undefined = this.books.find((b: BookModel) => b.id === bookId)
    return book !== undefined ? book.name : '未知书籍'
  }

  get filteredInspirations(): InspirationModel[] {
    let result: InspirationModel[] = this.inspirations
    if (this.bookFilter !== 'all') {
      result = result.filter((item: InspirationModel) => item.bookId === this.bookFilter)
    }
    if (this.searchText.trim() !== '') {
      const keyword: string = this.searchText.trim()
      result = result.filter((item: InspirationModel) =>
        item.content.indexOf(keyword) >= 0
      )
    }
    return result
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() { Text('←').fontSize(20) }.width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
        Text('全部灵感').fontSize(20).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(40)
      }
      .width('100%').height(56).padding({ left: 8, right: 8 })
      .backgroundColor(SemanticColors.BG_CARD)

      // Search
      TextInput({ text: $$this.searchText, placeholder: '搜索灵感...' })
        .fontSize(14).height(40)
        .backgroundColor(GrayColors.G50)
        .borderRadius(8)
        .margin({ left: 12, right: 12, top: 8, bottom: 4 })

      // Book filter chips
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('全部')
          .fontSize(12)
          .fontColor(this.bookFilter === 'all' ? '#FFFFFF' : GrayColors.G700)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.bookFilter === 'all' ? GreenColors.G500 : GrayColors.G50)
          .borderRadius(12)
          .onClick(() => { this.bookFilter = 'all' })

        ForEach(this.books, (book: BookModel) => {
          Text(book.name)
            .fontSize(12)
            .fontColor(this.bookFilter === book.id ? '#FFFFFF' : GrayColors.G700)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.bookFilter === book.id ? GreenColors.G500 : GrayColors.G50)
            .borderRadius(12)
            .onClick(() => { this.bookFilter = book.id })
        }, (book: BookModel) => book.id)
      }
      .width('100%').padding({ left: 12, right: 12, bottom: 8 })

      // List
      List({ space: 1 }) {
        ForEach(this.filteredInspirations, (item: InspirationModel) => {
          ListItem() {
            Column() {
              Text(item.content)
                .fontSize(14).fontColor(GrayColors.G700)
                .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding(12).width('100%')

              Row() {
                Text(this.getBookName(item.bookId))
                  .fontSize(11).fontColor(GreenColors.G500)
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .backgroundColor(GreenColors.G100).borderRadius(4)
                Blank()
                Text(new Date(item.createdAt).toLocaleDateString())
                  .fontSize(11).fontColor(GrayColors.G300)
              }
              .width('100%').padding({ left: 12, right: 12, bottom: 8 })
            }
            .width('100%')
            .backgroundColor(SemanticColors.BG_CARD)
          }
        }, (item: InspirationModel) => item.id)
      }
      .layoutWeight(1).width('100%')
      .backgroundColor(SemanticColors.BG_SURFACE)
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
