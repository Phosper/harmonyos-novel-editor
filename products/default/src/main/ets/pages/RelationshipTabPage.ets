// RelationshipTabPage.ets — Relationship graph visualization with Canvas
import { router } from '@kit.ArkUI'
import { PreferenceHelper, SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { CharacterDao } from '@ohos/material'
import { RelationshipDao, GraphCanvas, RelationLabelSheet } from '@ohos/relationship'
import type { GraphNode, GraphEdge } from '@ohos/relationship'
import { BookDao, ChapterDao } from '@ohos/editor'
import type { CharacterModel, RelationshipModel, BookModel, ChapterModel } from '@ohos/common'

@Component
export struct RelationshipTabPage {
  @State characters: CharacterModel[] = []
  @State relationships: RelationshipModel[] = []
  @State currentBookId: string = ''
  @State showAddSheet: boolean = false
  @State graphNodes: GraphNode[] = []
  @State graphEdges: GraphEdge[] = []
  @State panOffsetX: number = 0
  @State panOffsetY: number = 0
  @State canvasScale: number = 1.0
  @State selectedRelId: string = ''
  @State isConnecting: boolean = false
  @State connectFromId: string = ''
  @State contextNodeId: string = ''
  @State showContextMenu: boolean = false
  @StorageLink('active_tab_index') @Watch('onTabVisited') activeTabIndex: number = 0
  @State contextMenuX: number = 0
  @State contextMenuY: number = 0
  @State chapters: ChapterModel[] = []
  @State selectedChapterId: string = ''
  @State showChapterPicker: boolean = false
  @State showNewCharDialog: boolean = false
  @State newCharName: string = ''
  private swipeConnectFromId: string = ''
  private swipeConnectToId: string = ''

  onTabVisited(): void {
    // Relationship tab is index 2 in professional mode
    if (this.activeTabIndex === 2 && this.currentBookId !== '') {
      this.loadData()
    }
  }

  async aboutToAppear(): Promise<void> {
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.init(getContext(this))
    let bookId: string = await prefs.getString('last_book_id', '')
    if (bookId === '') {
      const bookDao: BookDao = new BookDao()
      const books: BookModel[] = await bookDao.queryAll()
      if (books.length > 0) {
        bookId = books[0].id
      }
    }
    if (bookId !== '') {
      this.currentBookId = bookId
      await this.loadData()
      await this.loadChapters()
    }
  }

  onPageShow(): void {
    if (this.currentBookId !== '') {
      this.loadData()
    }
  }

  async loadData(): Promise<void> {
    if (this.currentBookId === '') return
    const charDao: CharacterDao = new CharacterDao()
    this.characters = await charDao.queryByBook(this.currentBookId)
    const relDao: RelationshipDao = new RelationshipDao()
    this.relationships = await relDao.queryByBook(this.currentBookId)
    this.buildGraphData()
  }

  buildGraphData(): void {
    const chapterContent: string = this.getSelectedChapterContent()
    const nodes: GraphNode[] = []
    for (let i: number = 0; i < this.characters.length; i++) {
      const ch: CharacterModel = this.characters[i]
      const nodeType: string = ch.characterType !== '' ? ch.characterType : 'support'
      const isInChapter: boolean = chapterContent !== '' && chapterContent.indexOf(ch.name) >= 0
      nodes.push({
        characterId: ch.id,
        name: ch.name,
        type: nodeType,
        x: 0,
        y: 0,
        radius: 30,
        isHighlighted: chapterContent !== '' && isInChapter,
        isDimmed: chapterContent !== '' && !isInChapter
      })
    }
    this.graphNodes = nodes

    const edges: GraphEdge[] = []
    for (let i: number = 0; i < this.relationships.length; i++) {
      const rel: RelationshipModel = this.relationships[i]
      edges.push({
        id: rel.id,
        fromId: rel.characterIdA,
        toId: rel.characterIdB,
        type: rel.type,
        label: rel.label
      })
    }
    this.graphEdges = edges
  }

  getSelectedChapterContent(): string {
    if (this.selectedChapterId === '') {
      return ''
    }
    const chapter: ChapterModel | undefined = this.chapters.find(
      (c: ChapterModel) => c.id === this.selectedChapterId
    )
    return chapter !== undefined ? chapter.content : ''
  }

  async loadChapters(): Promise<void> {
    if (this.currentBookId === '') {
      return
    }
    const dao: ChapterDao = new ChapterDao()
    this.chapters = await dao.queryByBook(this.currentBookId)
  }

  onChapterFilterChange(chapterId: string): void {
    this.selectedChapterId = chapterId
    this.showChapterPicker = false
    this.buildGraphData()
  }

  clearChapterFilter(): void {
    this.selectedChapterId = ''
    this.buildGraphData()
  }

  handleSwipeConnect(fromId: string, toId: string): void {
    this.swipeConnectFromId = fromId
    this.swipeConnectToId = toId
    this.showAddSheet = true
  }

  handleDoubleTapCanvas(): void {
    this.showNewCharDialog = true
    this.newCharName = ''
  }

  async createCharacterFromCanvas(): Promise<void> {
    if (this.newCharName.trim() === '' || this.currentBookId === '') {
      return
    }
    const dao: CharacterDao = new CharacterDao()
    const model: CharacterModel = {
      id: IdGenerator.generate(),
      bookId: this.currentBookId,
      name: this.newCharName.trim(),
      alias: '',
      age: '',
      appearance: '',
      personality: '',
      background: '',
      notes: '',
      characterType: 'support'
    }
    await dao.insert(model)
    this.showNewCharDialog = false
    this.newCharName = ''
    await this.loadData()
  }

  async deleteRelationship(relId: string): Promise<void> {
    const dao: RelationshipDao = new RelationshipDao()
    await dao.delete(relId)
    await this.loadData()
  }

  getCharacterName(id: string): string {
    const ch: CharacterModel | undefined = this.characters.find(
      (c: CharacterModel) => c.id === id
    )
    return ch !== undefined ? ch.name : '未知'
  }

  relTypeLabel(type: string): string {
    const labels: Record<string, string> = {
      'positive': '正面', 'neutral': '中立', 'negative': '负面', 'indirect': '间接'
    }
    return labels[type] ?? type
  }

  relTypeColor(type: string): string {
    const colors: Record<string, string> = {
      'positive': '#A4CE92', 'neutral': '#9E9D9D', 'negative': '#6F6E6E', 'indirect': '#D5D5D5'
    }
    return colors[type] ?? '#D5D5D5'
  }

  @Builder
  buildAddSheet() {
    RelationLabelSheet({
      characters: this.characters,
      bookId: this.currentBookId,
      initialCharAId: this.swipeConnectFromId,
      initialCharBId: this.swipeConnectToId,
      onChange: () => {
        this.showAddSheet = false
        this.swipeConnectFromId = ''
        this.swipeConnectToId = ''
        this.loadData()
      }
    })
  }

  // Canvas callbacks
  handleNodeTap(characterId: string): void {
    router.pushUrl({
      url: 'pages/CharacterDetailPage',
      params: { characterId: characterId }
    })
  }

  handleNodeLongPress(characterId: string): void {
    this.contextNodeId = characterId
    this.showContextMenu = true
  }

  build() {
    Stack() {
      Column() {
        // Top bar
        Row() {
          Text('关系图').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(GrayColors.G900).layoutWeight(1)
          Button('+ 添加关系')
            .fontSize(13).height(32)
            .fontColor('#FFFFFF')
            .backgroundColor(GreenColors.G500)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.swipeConnectFromId = ''
              this.swipeConnectToId = ''
              this.showAddSheet = true
            })
        }
        .width('100%').height(48).padding({ left: 16, right: 16 })
        .backgroundColor(SemanticColors.BG_CARD)

        // Chapter filter bar (only visible when chapters exist)
        if (this.chapters.length > 0 && this.currentBookId !== '') {
          Row() {
            Column() {
              Row() {
                Text(this.selectedChapterId === '' ? '全部章节' : '筛选：' +
                  (this.chapters.find((c: ChapterModel) => c.id === this.selectedChapterId)?.title ?? ''))
                  .fontSize(12).fontColor(GrayColors.G500).layoutWeight(1)
                Text(this.showChapterPicker ? '▲' : '▼').fontSize(10).fontColor(GrayColors.G300)
              }
              .width('100%').height(32).padding({ left: 12, right: 12 })
              .borderRadius(8)
              .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
              .backgroundColor(SemanticColors.BG_CARD)
              .onClick(() => { this.showChapterPicker = !this.showChapterPicker })

              if (this.showChapterPicker) {
                Column() {
                  Row() {
                    Text('全部章节').fontSize(13)
                      .fontColor(this.selectedChapterId === '' ? GreenColors.G500 : GrayColors.G700)
                      .layoutWeight(1)
                    if (this.selectedChapterId === '') {
                      Text('✓').fontSize(13).fontColor(GreenColors.G500)
                    }
                  }
                  .width('100%').height(36).padding({ left: 12, right: 12 })
                  .onClick(() => { this.clearChapterFilter() })

                  ForEach(this.chapters, (ch: ChapterModel) => {
                    Row() {
                      Text(ch.title).fontSize(13)
                        .fontColor(ch.id === this.selectedChapterId ? GreenColors.G500 : GrayColors.G700)
                        .layoutWeight(1)
                      if (ch.id === this.selectedChapterId) {
                        Text('✓').fontSize(13).fontColor(GreenColors.G500)
                      }
                    }
                    .width('100%').height(36).padding({ left: 12, right: 12 })
                    .onClick(() => { this.onChapterFilterChange(ch.id) })
                  }, (ch: ChapterModel) => ch.id)
                }
                .width('100%')
                .constraintSize({ maxHeight: 200 })
                .borderRadius(8)
                .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
                .backgroundColor(SemanticColors.BG_CARD)
                .position({ x: 0, y: 33 })
              }
            }
            .width(180)
            .zIndex(10)

            if (this.selectedChapterId !== '') {
              Button('清除筛选')
                .fontSize(11).height(26)
                .fontColor(GrayColors.G300).backgroundColor(Color.Transparent)
                .onClick(() => { this.clearChapterFilter() })
            }
          }
          .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .justifyContent(FlexAlign.Start)
        }

        if (this.characters.length === 0) {
          Column() {
            Column() {
              Text('🕸').fontSize(40)
            }
            .width(80).height(80)
            .borderRadius(40)
            .backgroundColor(GreenColors.G50)
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 20 })

            Text('暂无人物').fontSize(20).fontWeight(FontWeight.Bold)
              .fontColor(GrayColors.G900)
              .margin({ bottom: 8 })

            Text('先在「素材」页中为当前书籍添加人物，或双击画布创建')
              .fontSize(14).fontColor(GrayColors.G500)
              .textAlign(TextAlign.Center)
              .width('80%')
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            // Canvas graph
            Column() {
              GraphCanvas({
                nodes: $graphNodes,
                edges: $graphEdges,
                panOffsetX: $panOffsetX,
                panOffsetY: $panOffsetY,
                canvasScale: $canvasScale,
                selectedRelId: $selectedRelId,
                isConnecting: $isConnecting,
                connectFromId: $connectFromId,
                onNodeTap: (characterId: string) => { this.handleNodeTap(characterId) },
                onNodeLongPress: (characterId: string) => { this.handleNodeLongPress(characterId) },
                onNodeRightClick: (charId: string, x: number, y: number) => { this.handleNodeLongPress(charId) },
                onSwipeConnect: (fromId: string, toId: string) => { this.handleSwipeConnect(fromId, toId) },
                onDoubleTapCanvas: () => { this.handleDoubleTapCanvas() },
                onBlankTap: () => { this.isConnecting = false; this.connectFromId = '' }
              })
            }
            .width('100%').height(0).layoutWeight(1)
            .border({ width: { bottom: 1 }, color: SemanticColors.BORDER_DEFAULT })

            // Edge count & reset button
            Row() {
              Text('关系连线 (' + this.relationships.length.toString() + ')')
                .fontSize(13).fontColor(GrayColors.G500)
                .layoutWeight(1)
              Button('重置视图')
                .fontSize(11).height(26)
                .fontColor(GreenColors.G500)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.panOffsetX = 0
                  this.panOffsetY = 0
                  this.canvasScale = 1.0
                })
            }
            .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 })

            // Relationship list
            List({ space: 4 }) {
              ForEach(this.relationships, (rel: RelationshipModel) => {
                ListItem() {
                  Row() {
                    Text(this.getCharacterName(rel.characterIdA))
                      .fontSize(13).fontColor(GrayColors.G900)
                    Text(' —' + rel.label + '→ ')
                      .fontSize(11).fontColor(GrayColors.G500)
                    Text(this.getCharacterName(rel.characterIdB))
                      .fontSize(13).fontColor(GrayColors.G900)
                    Blank()
                    Text(this.relTypeLabel(rel.type))
                      .fontSize(10).fontColor('#FFFFFF')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .backgroundColor(this.relTypeColor(rel.type))
                      .margin({ right: 8 })
                    Text('✕').fontSize(13).fontColor(GrayColors.G300)
                      .onClick(() => { this.deleteRelationship(rel.id) })
                  }
                  .width('100%').height(40).padding({ left: 16, right: 16 })
                  .backgroundColor(rel.id === this.selectedRelId ? SemanticColors.BG_CARD : Color.Transparent)
                  .onClick(() => {
                    this.selectedRelId = this.selectedRelId === rel.id ? '' : rel.id
                  })
                }
              }, (rel: RelationshipModel) => rel.id)
            }
            .layoutWeight(1).width('100%')
          }
          .layoutWeight(1).width('100%')
        }
      }
      .width('100%').height('100%')

      // Context menu for long-press on node
      if (this.showContextMenu && this.contextNodeId !== '') {
        Column() {
          Row() {
            Text('添加关系').fontSize(14).fontColor(GrayColors.G900)
          }
          .width('100%').height(44).padding({ left: 16, right: 16 })
          .onClick(() => {
            this.showContextMenu = false
            this.showAddSheet = true
          })

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          Row() {
            Text('查看人物详情').fontSize(14).fontColor(GrayColors.G900)
          }
          .width('100%').height(44).padding({ left: 16, right: 16 })
          .onClick(() => {
            this.showContextMenu = false
            router.pushUrl({
              url: 'pages/CharacterDetailPage',
              params: { characterId: this.contextNodeId }
            })
          })

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          Row() {
            Text('取消').fontSize(14).fontColor(GrayColors.G500)
          }
          .width('100%').height(44).padding({ left: 16, right: 16 })
          .onClick(() => { this.showContextMenu = false })
        }
        .width(180)
        .borderRadius(12)
        .backgroundColor(SemanticColors.BG_CARD)
        .shadow({ radius: 16, color: '#10000000', offsetY: 4 })
        .position({ x: '50%', y: '40%' })
        .translate({ x: -90, y: 0 })
      }

      // New character dialog from canvas double-tap
      if (this.showNewCharDialog) {
        Column() {
          Column() {
            Text('新建人物').fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(GrayColors.G900)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: 20, bottom: 16 })

            TextInput({ text: $$this.newCharName, placeholder: '输入人物姓名' })
              .fontSize(14)
              .height(44)
              .borderRadius(8)
              .backgroundColor(SemanticColors.BG_SURFACE)
              .padding({ left: 12, right: 12 })
              .margin({ left: 16, right: 16, bottom: 16 })

            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14).height(40).layoutWeight(1)
                .fontColor(GrayColors.G700).backgroundColor(GrayColors.G50).borderRadius(8)
                .onClick(() => {
                  this.showNewCharDialog = false
                  this.newCharName = ''
                })
              Button('创建')
                .fontSize(14).height(40).layoutWeight(1)
                .fontColor('#FFFFFF').backgroundColor(GreenColors.G500).borderRadius(8)
                .onClick(() => { this.createCharacterFromCanvas() })
            }
            .width('100%').padding({ left: 16, right: 16, bottom: 20 })
          }
          .width('80%')
          .borderRadius(16)
          .backgroundColor(SemanticColors.BG_CARD)
          .shadow({ radius: 20, color: '#20000000', offsetY: 8 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#40000000')
        .onClick(() => {
          this.showNewCharDialog = false
          this.newCharName = ''
        })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
    .bindSheet($$this.showAddSheet, this.buildAddSheet(), {
      height: '65%',
      showClose: true,
      dragBar: true
    })
  }
}
