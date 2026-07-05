// SideDrawer.ets — Side drawer for book/chapter management
import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { BookDao } from '../data/BookDao'
import { ChapterDao } from '../data/ChapterDao'
import type { BookModel, ChapterModel } from '@ohos/common'

@Component
export struct SideDrawer {
  @State books: BookModel[] = []
  @State chapters: ChapterModel[] = []
  @State currentBookId: string = ''
  @State currentChapterId: string = ''
  @State showNewBookDialog: boolean = false
  @State showNewChapterDialog: boolean = false
  @State newBookName: string = ''
  @State newChapterTitle: string = ''
  // Chapter/Book selection communicated via AppStorage in full integration

  async aboutToAppear(): Promise<void> {
    await this.loadBooks()
  }

  async loadBooks(): Promise<void> {
    const dao: BookDao = new BookDao()
    this.books = await dao.queryAll()
    if (this.books.length > 0 && this.currentBookId === '') {
      this.currentBookId = this.books[0].id
      await this.loadChapters()
    }
  }

  async loadChapters(): Promise<void> {
    if (this.currentBookId === '') return
    const dao: ChapterDao = new ChapterDao()
    this.chapters = await dao.queryByBook(this.currentBookId)
  }

  async createBook(): Promise<void> {
    if (this.newBookName.trim() === '') return
    const dao: BookDao = new BookDao()
    const book: BookModel = {
      id: IdGenerator.generate(),
      name: this.newBookName.trim(),
      mode: 'normal',
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await dao.insert(book)
    this.newBookName = ''
    this.showNewBookDialog = false
    await this.loadBooks()
  }

  async deleteBook(bookId: string): Promise<void> {
    try {
      const dao: BookDao = new BookDao()
      await dao.delete(bookId)
      if (this.currentBookId === bookId) {
        this.currentBookId = ''
        this.chapters = []
        AppStorage.setOrCreate('selected_book_id', '')
        AppStorage.setOrCreate('selected_chapter_id', '')
      }
      await this.loadBooks()
    } catch (e) {
      // ignore
    }
  }

  async deleteChapter(chapterId: string): Promise<void> {
    try {
      const dao: ChapterDao = new ChapterDao()
      await dao.delete(chapterId)
      if (this.currentChapterId === chapterId) {
        this.currentChapterId = ''
        AppStorage.setOrCreate('selected_chapter_id', '')
      }
      await this.loadChapters()
    } catch (e) {
      // ignore
    }
  }
  async createChapter(): Promise<void> {
    if (this.newChapterTitle.trim() === '' || this.currentBookId === '') return
    const dao: ChapterDao = new ChapterDao()
    const order: number = this.chapters.length
    const chapter: ChapterModel = {
      id: IdGenerator.generate(),
      bookId: this.currentBookId,
      title: this.newChapterTitle.trim(),
      content: '',
      order: order,
      wordCount: 0,
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    await dao.insert(chapter)
    this.newChapterTitle = ''
    this.showNewChapterDialog = false
    await this.loadChapters()
  }

  selectBook(bookId: string): void {
    this.currentBookId = bookId
    this.loadChapters()
    AppStorage.setOrCreate('selected_book_id', bookId)
    AppStorage.setOrCreate('selected_chapter_id', '')
  }

  selectChapter(chapterId: string): void {
    this.currentChapterId = chapterId
    AppStorage.setOrCreate('selected_chapter_id', chapterId)
  }

  build() {
    Column() {
      // Current book header
      Text(this.books.find((b: BookModel) => b.id === this.currentBookId)?.name ?? '选择书籍')
        .fontSize(16).fontWeight(FontWeight.Bold)
        .fontColor(GrayColors.G900)
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Divider().width('100%')

      // Book list (compact)
      if (this.books.length > 0) {
        Text('书籍').fontSize(12).fontColor(GrayColors.G300)
          .padding({ left: 16, top: 8 })

        List() {
          ForEach(this.books, (book: BookModel) => {
            ListItem() {
              Row() {
                Text(book.name).fontSize(14)
                  .fontColor(book.id === this.currentBookId ? GreenColors.G500 : GrayColors.G700)
                  .layoutWeight(1)
                if (book.id === this.currentBookId) {
                  Text('✓').fontSize(14).fontColor(GreenColors.G500).margin({ right: 4 })
                }
                Text('✕').fontSize(12).fontColor(GrayColors.G300)
                  .onClick(() => { this.deleteBook(book.id) })
              }
              .width('100%').height(44).padding({ left: 16, right: 16 })
              .onClick(() => { this.selectBook(book.id) })
            }
          }, (book: BookModel) => book.id)
        }
        .height(120)
      }

      Divider().width('100%')

      // Chapter list
      Text('章节').fontSize(12).fontColor(GrayColors.G300)
        .padding({ left: 16, top: 8 })

      List() {
        ForEach(this.chapters, (chapter: ChapterModel) => {
          ListItem() {
            Row() {
              Text(chapter.title).fontSize(14)
                .fontColor(chapter.id === this.currentChapterId ? GreenColors.G500 : GrayColors.G700)
                .layoutWeight(1)
              Text(chapter.wordCount.toString() + '字').fontSize(11).fontColor(GrayColors.G300)
                .margin({ right: 4 })
              Text('✕').fontSize(12).fontColor(GrayColors.G300)
                .onClick(() => { this.deleteChapter(chapter.id) })
            }
            .width('100%').height(44).padding({ left: 16, right: 16 })
            .onClick(() => { this.selectChapter(chapter.id) })
          }
        }, (chapter: ChapterModel) => chapter.id)
      }
      .layoutWeight(1)

      // New book input (conditional)
      if (this.showNewBookDialog) {
        Column() {
          TextInput({ text: $$this.newBookName, placeholder: '输入书名' })
            .fontSize(14).height(40)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ left: 8, right: 8, top: 4 })
          Row({ space: 8 }) {
            Button('取消')
              .fontSize(12).height(32).layoutWeight(1)
              .backgroundColor(GrayColors.G50).fontColor(GrayColors.G700)
              .onClick(() => {
                this.showNewBookDialog = false
                this.newBookName = ''
              })
            Button('确认')
              .fontSize(12).height(32).layoutWeight(1)
              .backgroundColor(GreenColors.G500).fontColor('#FFFFFF')
              .onClick(() => { this.createBook() })
          }
          .width('100%').padding({ left: 8, right: 8, bottom: 4 })
        }
        .width('100%')
        .border({ width: { top: 1 }, color: SemanticColors.BORDER_DEFAULT })
      }

      // New chapter input (conditional)
      if (this.showNewChapterDialog) {
        Column() {
          TextInput({ text: $$this.newChapterTitle, placeholder: '输入章节名' })
            .fontSize(14).height(40)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ left: 8, right: 8, top: 4 })
          Row({ space: 8 }) {
            Button('取消')
              .fontSize(12).height(32).layoutWeight(1)
              .backgroundColor(GrayColors.G50).fontColor(GrayColors.G700)
              .onClick(() => {
                this.showNewChapterDialog = false
                this.newChapterTitle = ''
              })
            Button('确认')
              .fontSize(12).height(32).layoutWeight(1)
              .backgroundColor(GreenColors.G500).fontColor('#FFFFFF')
              .onClick(() => { this.createChapter() })
          }
          .width('100%').padding({ left: 8, right: 8, bottom: 4 })
        }
        .width('100%')
        .border({ width: { top: 1 }, color: SemanticColors.BORDER_DEFAULT })
      }

      // Action buttons
      Row({ space: 8 }) {
        Button('+ 新书')
          .fontSize(12).height(36).layoutWeight(1)
          .backgroundColor(GrayColors.G50).fontColor(GrayColors.G700)
          .onClick(() => { this.showNewBookDialog = !this.showNewBookDialog })

        Button('+ 新章')
          .fontSize(12).height(36).layoutWeight(1)
          .backgroundColor(GreenColors.G100).fontColor(GreenColors.G700)
          .onClick(() => { this.showNewChapterDialog = !this.showNewChapterDialog })
      }
      .width('100%').padding(8)
    }
    .width(260)
    .height('100%')
    .backgroundColor(SemanticColors.BG_SURFACE)
    .border({ width: { right: 1 }, color: SemanticColors.BORDER_DEFAULT })
  }
}
