// MaterialTabPage.ets — Settings + Inspiration sub-tabs
import { router } from '@kit.ArkUI'
import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { CharacterDao, CharacterCard, WorldSettingDao, WorldSettingCard, InspirationDao, InspirationCard } from '@ohos/material'
import { BookDao } from '@ohos/editor'
import type { CharacterModel, WorldSettingModel, InspirationModel, BookModel } from '@ohos/common'

@Component
export struct MaterialTabPage {
  @State subTabIndex: number = 0
  @State currentBookId: string = ''
  @State currentBookName: string = '无书籍'
  @State books: BookModel[] = []
  @State showBookPicker: boolean = false

  // Settings data
  @State characters: CharacterModel[] = []
  @State worldSettings: WorldSettingModel[] = []

  // Inspiration data
  @State bookInspirations: InspirationModel[] = []
  @State allInspirations: InspirationModel[] = []

  async aboutToAppear(): Promise<void> {
    await this.refreshAll()
  }

  onPageShow(): void {
    this.refreshAll()
  }

  async refreshAll(): Promise<void> {
    const bookDao: BookDao = new BookDao()
    this.books = await bookDao.queryAll()
    if (this.books.length > 0) {
      if (this.currentBookId === '') {
        this.currentBookId = this.books[0].id
        this.currentBookName = this.books[0].name
      } else {
        // Verify current book still exists
        const found: BookModel | undefined = this.books.find(
          (b: BookModel) => b.id === this.currentBookId)
        if (found === undefined) {
          this.currentBookId = this.books[0].id
          this.currentBookName = this.books[0].name
        }
      }
    } else {
      this.currentBookId = ''
      this.currentBookName = '无书籍'
    }
    await this.loadData()
  }

  async loadData(): Promise<void> {
    if (this.currentBookId === '') {
      this.characters = []
      this.worldSettings = []
      this.bookInspirations = []
      this.allInspirations = []
      return
    }
    const charDao: CharacterDao = new CharacterDao()
    this.characters = await charDao.queryByBook(this.currentBookId)
    const wsDao: WorldSettingDao = new WorldSettingDao()
    this.worldSettings = await wsDao.queryByBook(this.currentBookId)
    const inspDao: InspirationDao = new InspirationDao()
    this.bookInspirations = await inspDao.queryByBook(this.currentBookId)
    this.allInspirations = await inspDao.queryAll()
  }

  async createBookAndSelect(): Promise<void> {
    const dao: BookDao = new BookDao()
    const book: BookModel = {
      id: IdGenerator.generate(),
      name: '新书',
      mode: 'normal',
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await dao.insert(book)
    this.currentBookId = book.id
    this.currentBookName = book.name
    AppStorage.setOrCreate('last_book_id', book.id)
    this.books = await dao.queryAll()
    await this.loadData()
  }

  selectBook(bookId: string, bookName: string): void {
    this.currentBookId = bookId
    this.currentBookName = bookName
    this.showBookPicker = false
    AppStorage.setOrCreate('last_book_id', bookId)
    this.loadData()
  }

  // ===== Shared book selector bar =====
  @Builder
  buildBookSelector() {
    Column() {
      Row() {
        Text(this.currentBookName).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.books.length > 0 ? GrayColors.G900 : GrayColors.G300)
          .layoutWeight(1)
          .onClick(() => {
            if (this.books.length > 1) {
              this.showBookPicker = !this.showBookPicker
            }
          })
        if (this.books.length > 1) {
          Text(this.showBookPicker ? '▲' : '▼').fontSize(12).fontColor(GreenColors.G500)
            .onClick(() => { this.showBookPicker = !this.showBookPicker })
        }
      }
      .width('100%').height(44).padding({ left: 16, right: 16 })
      .backgroundColor(SemanticColors.BG_CARD)

      // Book picker dropdown
      if (this.showBookPicker && this.books.length > 1) {
        Column() {
          ForEach(this.books, (book: BookModel) => {
            Row() {
              Text(book.name).fontSize(14)
                .fontColor(book.id === this.currentBookId ? GreenColors.G500 : GrayColors.G700)
                .layoutWeight(1)
              if (book.id === this.currentBookId) {
                Text('✓').fontSize(14).fontColor(GreenColors.G500)
              }
            }
            .width('100%').height(44).padding({ left: 16, right: 16 })
            .backgroundColor(SemanticColors.BG_CARD)
            .onClick(() => { this.selectBook(book.id, book.name) })
          }, (book: BookModel) => book.id)
        }
        .width('100%')
        .border({ width: { bottom: 1 }, color: SemanticColors.BORDER_DEFAULT })
      }
    }
  }

  // ===== Settings sub-tab =====
  @Builder
  buildSettingsTab() {
    Column() {
      this.buildBookSelector()

      if (this.books.length === 0) {
        Column() {
          Column() {
            Text('📚').fontSize(40)
          }
          .width(80).height(80)
          .borderRadius(40)
          .backgroundColor(GreenColors.G50)
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: 20 })

          Text('还没有书籍').fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor(GrayColors.G900)
            .margin({ bottom: 8 })

          Text('创建一本书，开始构建你的角色、世界与故事')
            .fontSize(14).fontColor(GrayColors.G500)
            .textAlign(TextAlign.Center)
            .width('80%')
            .margin({ bottom: 24 })

          Button('创建第一本书')
            .fontSize(15).fontColor('#FFFFFF')
            .backgroundColor(GreenColors.G500)
            .borderRadius(24)
            .padding({ left: 32, right: 32, top: 12, bottom: 12 })
            .shadow({ radius: 8, color: '#20000000', offsetY: 4 })
            .onClick(() => { this.createBookAndSelect() })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.currentBookId === '') {
        Text('请点击上方选择一本书').fontSize(14).fontColor(GrayColors.G300)
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center).margin({ top: 60 })
      } else {
        Scroll() {
          Column() {
          // Characters section
          Row() {
            Text('▎人物').fontSize(14).fontWeight(FontWeight.Bold).fontColor(GrayColors.G900)
            Blank()
            Text('+ 添加').fontSize(12).fontColor(GreenColors.G500)
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/CharacterDetailPage',
                  params: { bookId: this.currentBookId, isNew: true }
                })
              })
          }
          .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 8 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.characters, (char: CharacterModel) => {
                CharacterCard({ character: char })
                  .onClick(() => {
                    router.pushUrl({
                      url: 'pages/CharacterDetailPage',
                      params: { characterId: char.id, bookId: this.currentBookId, isNew: false }
                    })
                  })
              }, (char: CharacterModel) => char.id)

              if (this.characters.length === 0) {
                Text('暂无人物，点击右上角添加').fontSize(13).fontColor(GrayColors.G300).padding(20)
              }
            }
            .padding({ left: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .height(120)

          // WorldSettings section
          Row() {
            Text('▎世界观').fontSize(14).fontWeight(FontWeight.Bold).fontColor(GrayColors.G900)
            Blank()
            Text('+ 添加').fontSize(12).fontColor(GreenColors.G500)
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/WorldSettingDetailPage',
                  params: { bookId: this.currentBookId, isNew: true }
                })
              })
          }
          .width('100%').padding({ left: 16, right: 16, top: 20, bottom: 8 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.worldSettings, (ws: WorldSettingModel) => {
                WorldSettingCard({ setting: ws })
                  .onClick(() => {
                    router.pushUrl({
                      url: 'pages/WorldSettingDetailPage',
                      params: { settingId: ws.id, bookId: this.currentBookId, isNew: false }
                    })
                  })
              }, (ws: WorldSettingModel) => ws.id)

              if (this.worldSettings.length === 0) {
                Text('暂无世界设定，点击右上角添加').fontSize(13).fontColor(GrayColors.G300).padding(20)
              }
            }
            .padding({ left: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .height(150)
        }
      }
      .layoutWeight(1)
    }
  }
  .width('100%').height('100%')
  }

  // ===== Inspiration sub-tab =====
  @Builder
  buildInspirationTab() {
    Column() {
      this.buildBookSelector()

      Scroll() {
        Column() {
          // Book inspirations
          Text('本书灵感 · ' + this.currentBookName)
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(GrayColors.G900)
            .width('100%').padding({ left: 16, top: 16, bottom: 8 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.bookInspirations.slice(0, 6), (insp: InspirationModel) => {
                InspirationCard({ inspiration: insp })
              }, (insp: InspirationModel) => insp.id)

              if (this.bookInspirations.length > 6) {
                Column() {
                  Text('更多').fontSize(13).fontColor(GreenColors.G500)
                }
                .width(80).height(100).borderRadius(16)
                .backgroundColor(GrayColors.G50).justifyContent(FlexAlign.Center)
                .onClick(() => { router.pushUrl({ url: 'pages/InspirationListPage' }) })
              }

              if (this.bookInspirations.length === 0) {
                Text('暂无灵感').fontSize(13).fontColor(GrayColors.G300).padding(20)
              }
            }
            .padding({ left: 16 })
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(120)

          // All inspirations
          Text('全部灵感')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(GrayColors.G900)
            .width('100%').padding({ left: 16, top: 20, bottom: 8 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.allInspirations.slice(0, 6), (insp: InspirationModel) => {
                InspirationCard({ inspiration: insp })
              }, (insp: InspirationModel) => insp.id)

              if (this.allInspirations.length > 6) {
                Column() {
                  Text('更多').fontSize(13).fontColor(GreenColors.G500)
                }
                .width(80).height(100).borderRadius(16)
                .backgroundColor(GrayColors.G50).justifyContent(FlexAlign.Center)
                .onClick(() => { router.pushUrl({ url: 'pages/InspirationListPage' }) })
              }
            }
            .padding({ left: 16 })
          }
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(120)
        }
      }
      .layoutWeight(1)

      // FAB for new inspiration
      Button() {
        Text('+').fontSize(24).fontColor('#FFFFFF')
      }
      .width(56).height(56).borderRadius(28)
      .backgroundColor(GreenColors.G500)
      .position({ x: '85%', y: '85%' })
      .onClick(() => {
        router.pushUrl({
          url: 'pages/InspirationCreatePage',
          params: { bookId: this.currentBookId }
        })
      })
    }
    .width('100%').height('100%')
  }

  build() {
    Stack() {
      Tabs({ index: $$this.subTabIndex }) {
        TabContent() { this.buildSettingsTab() }.tabBar('设定')
        TabContent() { this.buildInspirationTab() }.tabBar('灵感')
      }
      .barHeight(44)
      .backgroundColor(SemanticColors.BG_PRIMARY)
    }
    .width('100%').height('100%')
  }
}
