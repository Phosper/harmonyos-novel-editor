// EditorPage.ets — Editor with top bar, writing area, toolbar, and side drawer
import { router } from '@kit.ArkUI'
import { PreferenceHelper, SemanticColors, GrayColors, GreenColors, DEFAULT_THEME, IdGenerator } from '@ohos/common'
import { BookDao, ChapterDao, SideDrawer } from '@ohos/editor'
import type { PaperTheme, BookModel, ChapterModel } from '@ohos/common'

@Component
export struct EditorPage {
  @State chapterContent: string = ''
  @State chapterTitle: string = '未命名章节'
  @State showDrawer: boolean = false
  @State showAgentSheet: boolean = false
  @State paperTheme: PaperTheme = DEFAULT_THEME
  @State currentBookId: string = ''
  @State currentChapterId: string = ''
  @StorageLink('selected_chapter_id') @Watch('onChapterSelected') watchedChapterId: string = ''
  @StorageLink('selected_book_id') @Watch('onBookSelected') watchedBookId: string = ''
  private saveTimer: number | null = null
  private prefsReady: boolean = false
  private textAreaController: TextAreaController = new TextAreaController()

  async saveCurrentChapter(): Promise<void> {
    if (this.currentChapterId === '' || this.chapterContent === '') return
    try {
      const dao: ChapterDao = new ChapterDao()
      await dao.updateContent(this.currentChapterId, this.chapterContent)
    } catch (e) {
      // ignore
    }
  }

  onChapterSelected(): void {
    if (this.watchedChapterId !== '' && this.watchedChapterId !== this.currentChapterId) {
      this.saveCurrentChapter()
      if (this.saveTimer !== null) {
        clearTimeout(this.saveTimer)
        this.saveTimer = null
      }
      this.currentChapterId = this.watchedChapterId
      this.loadChapter()
      if (this.prefsReady) {
        PreferenceHelper.getInstance().setString('last_chapter_id', this.currentChapterId)
      }
    }
  }

  onBookSelected(): void {
    if (this.watchedBookId !== '' && this.watchedBookId !== this.currentBookId) {
      this.currentBookId = this.watchedBookId
      if (this.prefsReady) {
        PreferenceHelper.getInstance().setString('last_book_id', this.currentBookId)
      }
    }
  }

  async aboutToAppear(): Promise<void> {
    // Load paper theme
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.init(getContext(this))
    this.prefsReady = true
    const saved: string = await prefs.getString('paper_theme', '')
    if (saved !== '') {
      try {
        const obj: Object = JSON.parse(saved)
        this.paperTheme = DEFAULT_THEME
        const entries: [string, Object][] = Object.entries(obj)
        for (let i = 0; i < entries.length; i++) {
          const k: string = entries[i][0]
          if (k === 'backgroundColor') { this.paperTheme.backgroundColor = String(entries[i][1]) }
          if (k === 'customImagePath') { this.paperTheme.customImagePath = String(entries[i][1]) }
          if (k === 'textColor') { this.paperTheme.textColor = String(entries[i][1]) }
          if (k === 'needsOverlay') { this.paperTheme.needsOverlay = entries[i][1] === true }
          if (k === 'overlayColor') { this.paperTheme.overlayColor = String(entries[i][1]) }
          if (k === 'overlayOpacity') { this.paperTheme.overlayOpacity = Number(entries[i][1]) }
        }
      } catch (e) {
        this.paperTheme = DEFAULT_THEME
      }
    }

    // Restore last position
    const lastBookId: string = await prefs.getString('last_book_id', '')
    const lastChapterId: string = await prefs.getString('last_chapter_id', '')
    if (lastBookId !== '' && lastChapterId !== '') {
      this.currentBookId = lastBookId
      this.currentChapterId = lastChapterId
      await this.loadChapter()
    }
  }

  async loadChapter(): Promise<void> {
    if (this.currentChapterId === '') return
    try {
      const dao: ChapterDao = new ChapterDao()
      const chapter: ChapterModel | null = await dao.queryById(this.currentChapterId)
      if (chapter !== null) {
        this.chapterContent = chapter.content
        this.chapterTitle = chapter.title
        this.currentBookId = chapter.bookId
      }
    } catch (e) {
      // ignore
    }
  }

  insertMarkdown(syntax: string): void {
    const caret: CaretOffset = this.textAreaController.getCaretOffset()
    if (caret !== null && caret !== undefined && caret.index !== undefined) {
      const pos: number = caret.index
      this.chapterContent =
        this.chapterContent.substring(0, pos) + syntax + this.chapterContent.substring(pos)
    } else {
      this.chapterContent = this.chapterContent + syntax
    }
  }

  onContentChange(value: string): void {
    this.chapterContent = value
    if (this.saveTimer !== null) {
      clearTimeout(this.saveTimer)
    }
    const chapterId: string = this.currentChapterId
    this.saveTimer = setTimeout(() => {
      if (chapterId !== '') {
        const dao: ChapterDao = new ChapterDao()
        dao.updateContent(chapterId, this.chapterContent)
      }
    }, 800)
  }

  // ===== Agent Sheet content =====
  @Builder
  buildAgentContent() {
    Column() {
      Text('AI 写作伴侣').fontSize(18).fontWeight(FontWeight.Bold).padding(16)
      Text('你好！我是 Weaver 写作伴侣。')
        .fontSize(14).fontColor(GrayColors.G700).padding(16)
      Text('此功能正在开发中，敬请期待。')
        .fontSize(14).fontColor(GrayColors.G300).padding(16)
      Blank()
      Button('关闭').width('80%')
        .onClick(() => { this.showAgentSheet = false })
        .margin({ bottom: 24 })
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_CARD)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  build() {
    Stack() {
      // === Main Editor Content ===
      Column() {
        // Top Bar
        Row() {
          Button() { Text('←').fontSize(20).fontColor(GrayColors.G900) }
            .width(40).height(40).backgroundColor(Color.Transparent)
            .onClick(() => { router.back() })

          Button() { Text('☰').fontSize(20).fontColor(GrayColors.G900) }
            .width(40).height(40).backgroundColor(Color.Transparent)
            .onClick(() => { this.showDrawer = !this.showDrawer })

          Text(this.chapterTitle)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(GrayColors.G900)

          Button() { Text('🤖').fontSize(20) }
            .width(40).height(40).backgroundColor(Color.Transparent)
            .onClick(() => { this.showAgentSheet = true })
        }
        .width('100%').height(56).padding({ left: 8, right: 8 })
        .backgroundColor(SemanticColors.BG_CARD)
        .border({ width: { bottom: 1 }, color: SemanticColors.BORDER_DEFAULT })

        // Writing Area
        Stack() {
          if (this.paperTheme.type === 'custom_image' && this.paperTheme.customImagePath !== '') {
            Image(this.paperTheme.customImagePath)
              .width('100%').height('100%').objectFit(ImageFit.Cover)
          } else {
            Rect().width('100%').height('100%').fill(this.paperTheme.backgroundColor)
          }

          if (this.paperTheme.needsOverlay && this.paperTheme.overlayOpacity > 0.01) {
            Rect().width('100%').height('100%')
              .fill(this.paperTheme.overlayColor)
              .opacity(this.paperTheme.overlayOpacity)
              .hitTestBehavior(HitTestMode.None)
          }

          TextArea({ text: $$this.chapterContent, placeholder: '开始写作...', controller: this.textAreaController })
            .fontSize(16).fontColor(this.paperTheme.textColor)
            .placeholderColor(GrayColors.G300)
            .backgroundColor(Color.Transparent)
            .padding(16).layoutWeight(1)
            .onChange((value: string) => { this.onContentChange(value) })
        }
        .layoutWeight(1)

        // Toolbar
        Row({ space: 32 }) {
          Button('B').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(GrayColors.G700).backgroundColor(Color.Transparent)
            .onClick(() => { this.insertMarkdown('**粗体**') })
          Button('I').fontSize(18).fontStyle(FontStyle.Italic)
            .fontColor(GrayColors.G700).backgroundColor(Color.Transparent)
            .onClick(() => { this.insertMarkdown('*斜体*') })
          Button('🖼').fontSize(18).backgroundColor(Color.Transparent)
            .onClick(() => { this.insertMarkdown('![描述](url)') })
          Button('🔗').fontSize(18).backgroundColor(Color.Transparent)
            .onClick(() => { this.insertMarkdown('[文字](url)') })
        }
        .width('100%').height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(SemanticColors.BG_SURFACE)
        .border({ width: { top: 1 }, color: SemanticColors.BORDER_DEFAULT })
      }
      .width('100%').height('100%')

      // === Side drawer overlay (translucent dimmer) ===
      if (this.showDrawer) {
        Rect()
          .width('100%').height('100%')
          .fill('#000000').opacity(0.3)
          .onClick(() => { this.showDrawer = false })
      }

      // === Side drawer panel (slides from left) ===
      if (this.showDrawer) {
        // Use a wrapper with translate animation
        Column() {
          SideDrawer()
            .width(260).height('100%')
        }
        .width(260).height('100%')
        .position({ x: 0, y: 0 })
        .translate({ x: this.showDrawer ? 0 : -260 })
        .animation({ duration: 250, curve: Curve.EaseOut })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
    .bindSheet($$this.showAgentSheet, this.buildAgentContent(), {
      height: '40%', showClose: true, dragBar: true
    })
  }
}
