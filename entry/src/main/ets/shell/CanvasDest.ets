// 思路板页（全窗口，不再是 NavDestination）
//
// 入口：文稿列表头四点菜单「思路板」→ AppShell 的 canvasOpen 分支。
// 形态：铺满整个应用窗口（左栏/中栏一起盖住），打开/关闭由 CanvasTransition 做一镜到底。
//
// 分工（避免和 CanvasPane 各画一套）：
//   CanvasPane 自带「板名 / 白板 / 卡片库」顶栏与空板态、错误条，本页**不再重复**；
//   本页只负责三件外壳的事：默认打开最近一块白板、手机端的返回条、两个浮层（白板库 / 卡片库）的宿主。
//
// 三条平台红线（docs/design/canvas-contract.md §5 / AI-README §5.3）：
//   1) 画布页**不再** expandSafeArea —— 根容器已经做过，重复会让内容顶进状态栏；
//   2) 键盘避让全局 NONE，输入控件自己让位（本页只有卡片库的搜索框，贴着面板顶部，不顶画布）；
//   3) 形态判据只用 breakPoint/tabletMode/pointerPrimary，deviceType 不参与布局。
//
// 状态归属：当前板 / 相机 / 选中都在 CanvasStore；本组件只留"面板开合"这类纯视图态，
// 断点切换重建子树时最多丢面板开合，不丢画布内容。
import { tokensFor, WeaverColorSet, WeaverRadii, TypeScale, WeaverSpacing } from '../constants/DesignTokens'
import { app } from '../store/AppStores'
import { closeCanvasAnimated, CANVAS_SURFACE_ID } from './CanvasTransition'
import { prefs } from '../utils/PreferenceHelper'
import { Logger } from '../utils/Logger'
import { CanvasPane } from './CanvasPane'
import { CanvasBoardScope, CanvasCardKind } from '../model/CanvasTypes'
import { CanvasSpec } from '../constants/CanvasSpec'
import type { CanvasBoardItem, CanvasCardItem } from '../model/CanvasStoreModels'
import { CanvasBoardLibrary } from './CanvasBoardLibrary'
import { CardLibrary } from './CardLibrary'

interface CanvasPoint {
  x: number
  y: number
}

@ComponentV2
export struct CanvasDest {
  /** 手机/窄屏显示返回条；宽屏占满主区，返回交给系统手势 */
  @Param showBack: boolean = false

  /** 白板库浮层 */
  @Local boardLibOpen: boolean = false
  /** 卡片库抽屉 */
  @Local cardLibOpen: boolean = false
  /** 首帧前不画空态，避免每次进入都闪一下「还没有白板」 */
  @Local booted: boolean = false

  aboutToAppear(): void {
    this.boot().catch((e: Error) => {
      Logger.error('CanvasDest: boot failed: ' + String(e))
    })
  }

  /** 离开时把相机落库（再次进来接着上次的位置） */
  aboutToDisappear(): void {
    app.canvas.saveViewport().catch((e: Error) => {
      Logger.warn('CanvasDest: saveViewport failed: ' + String(e))
    })
  }

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private tablet(): boolean {
    return app.ui.tabletMode
  }

  /**
   * 进入流程：绑定书作用域 → 载入 → 默认打开**最近一块**白板。
   * 最近 id 存 PreferenceHelper（键 canvas_recent_board）；失效（板已删）就退回 Store 选的第一块。
   */
  private async boot(): Promise<void> {
    app.canvas.setBookScope(app.project.currentBookId)
    await app.canvas.load()
    if (app.canvas.boards.length === 0) {
      this.booted = true
      return
    }
    const recent: string = await prefs.getCanvasRecentBoard()
    if (recent !== '' && this.hasBoard(recent)) {
      await app.canvas.selectBoard(recent)
    }
    await prefs.setCanvasRecentBoard(app.canvas.currentBoardId)
    this.booted = true
  }

  private hasBoard(boardId: string): boolean {
    const boards = app.canvas.boards
    for (let i: number = 0; i < boards.length; i++) {
      if (boards[i].id === boardId) {
        return true
      }
    }
    return false
  }

  private hasAnyBoard(): boolean {
    return app.canvas.boards.length > 0
  }

  /** 切板：selectBoard 之后记住最近板；面板关掉，让画布整屏 */
  private selectBoard(boardId: string): void {
    app.canvas.selectBoard(boardId).then(() => {
      this.boardLibOpen = false
      prefs.setCanvasRecentBoard(boardId).catch((e: Error) => {
        Logger.warn('CanvasDest: remember board failed: ' + String(e))
      })
    }).catch((e: Error) => {
      Logger.error('CanvasDest: selectBoard failed: ' + String(e))
    })
  }

  /**
   * 从卡片库放到当前白板：落点按已有贴放数做轻微错位，避免全叠在同一个点。
   * 真正的拖拽定位由画布自己接管。
   */
  /** 批量放卡：逐张排队，全部完成后关抽屉（避免每张都关一次）。 */
  private placeCards(cardIds: string[]): void {
    if (cardIds.length === 0) {
      return
    }
    let chain: Promise<void> = Promise.resolve()
    for (let i: number = 0; i < cardIds.length; i++) {
      const cardId: string = cardIds[i]
      const point: CanvasPoint = this.placePoint(i)
      chain = chain.then((): Promise<void> => app.canvas.addPlacement(cardId, point.x, point.y))
    }
    chain.then(() => {
      this.cardLibOpen = false
      this.getUIContext().getPromptAction().showToast({
        message: '已加入 ' + cardIds.length.toString() + ' 张，可用卡片库「定位」找回'
      })
    }).catch((e: Error) => {
      Logger.error('CanvasDest: placeCards failed: ' + String(e))
    })
  }

  /** 当前视口中心的网格落点：按卡宽留间距，避免固定 120+28 叠在一起。 */
  private placePoint(index: number): CanvasPoint {
    const z: number = app.canvas.zoom > 0.01 ? app.canvas.zoom : 1
    const vw: number = app.canvas.viewportW > 0 ? app.canvas.viewportW : 900
    const vh: number = app.canvas.viewportH > 0 ? app.canvas.viewportH : 700
    const stepX: number = CanvasSpec.CARD_WIDTH + 24
    const stepY: number = 180
    const cols: number = Math.max(1, Math.floor(vw / stepX))
    const col: number = index % cols
    const row: number = Math.floor(index / cols)
    const cx: number = (vw / 2 - app.canvas.panX) / z - CanvasSpec.CARD_WIDTH / 2
    const cy: number = (vh / 2 - app.canvas.panY) / z - 80
    return { x: cx + col * stepX, y: cy + row * stepY }
  }

  private placeCard(cardId: string): void {
    const point: CanvasPoint = this.placePoint(0)
    app.canvas.addPlacement(cardId, point.x, point.y).then(() => {
      this.cardLibOpen = false
    }).catch((e: Error) => {
      Logger.error('CanvasDest: addPlacement failed: ' + String(e))
    })
  }

  /**
   * 点卡钩子。选中态由 CanvasPane 自己写进 Store（它先写再回调），
   * 宿主这一层暂时不需要额外动作——保留钩子是为了契约 §3 的签名和后续埋点。
   */
  /** 首次开始：建课程板 + 一张可改名的写作提纲，直接进入编辑。 */
  private startFirstBoard(): void {
    app.canvas.createBoard(CanvasBoardScope.COURSE, '新课程白板').then(async (board: CanvasBoardItem | undefined) => {
      if (board === undefined) {
        return
      }
      const card: CanvasCardItem | undefined = await app.canvas.createCard(CanvasCardKind.WRITING, '未命名提纲')
      if (card !== undefined) {
        await app.canvas.addPlacement(card.id, 160, 140)
        app.canvas.selectedCardId = card.id
      }
      this.booted = true
    }).catch((e: Error) => {
      Logger.error('CanvasDest: startFirstBoard failed: ' + String(e))
    })
  }

  private openCard(cardId: string): void {
    if (cardId === '') {
      Logger.warn('CanvasDest: onOpenCard got empty cardId')
    }
  }

  private openFromLibrary(cardId: string): void {
    app.canvas.selectedCardId = cardId
    this.cardLibOpen = false
  }

  private locateFromLibrary(cardId: string): void {
    app.canvas.focusCard(cardId)
    this.cardLibOpen = false
  }

  /** 手机端返回条：只有返回动作，板名与「白板/卡片库」由 CanvasPane 的顶栏负责 */
  @Builder
  backBar() {
    Row() {
      Text('返回')
        .fontSize(this.tablet() ? 16 : TypeScale.BODY)
        .fontColor(this.colors().brand)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .accessibilityText('返回文稿列表')
        .onClick(() => closeCanvasAnimated(this.getUIContext()))
      Blank()
    }
    .width('100%')
    .height(this.tablet() ? 48 : 44)
    .backgroundColor(this.colors().bgPrimary)
  }

  /** 一块板都没有：给主按钮（"板存在但没有卡"的空态由 CanvasPane 负责） */
  @Builder
  noBoardState() {
    Column() {
      Text('还没有白板')
        .fontSize(TypeScale.HEADLINE)
        .fontColor(this.colors().textPrimary)
      Text('课程白板放课程线索，自由白板随手摊开')
        .fontSize(TypeScale.CAPTION)
        .fontColor(this.colors().textTertiary)
        .margin({ top: 6 })
      Button('开始整理思路')
        .fontSize(TypeScale.BODY)
        .height(this.tablet() ? 44 : 40)
        .margin({ top: 16 })
        .backgroundColor(this.colors().brand)
        .fontColor(this.colors().onBrand)
        .borderRadius(WeaverRadii.SM)
        .accessibilityText('创建课程白板并开始')
        .onClick(() => {
          this.startFirstBoard()
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  boardLayer() {
    Row() {
      CanvasBoardLibrary({
        onSelect: (boardId: string) => this.selectBoard(boardId),
        onClose: () => { this.boardLibOpen = false }
      })
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: WeaverSpacing.MD, top: WeaverSpacing.SM, bottom: WeaverSpacing.SM })
    // 轻蒙层：只压暗画布，不抢焦点（点空白处不关面板，避免拖动时误触）
    .backgroundColor('#33000000')
  }

  @Builder
  cardLayer() {
    Row() {
      Blank()
      CardLibrary({
        onAdd: (cardId: string) => this.placeCard(cardId),
        onAddMany: (cardIds: string[]) => this.placeCards(cardIds),
        onOpen: (cardId: string) => this.openFromLibrary(cardId),
        onLocate: (cardId: string) => this.locateFromLibrary(cardId),
        onClose: () => { this.cardLibOpen = false }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: WeaverSpacing.MD, top: WeaverSpacing.SM, bottom: WeaverSpacing.SM })
    .backgroundColor('#33000000')
  }

  build() {
    Column() {
      if (this.showBack) {
        this.backBar()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.hasAnyBoard()) {
          CanvasPane({
            params: {
              boardId: app.canvas.currentBoardId,
              onOpenCard: (cardId: string) => this.openCard(cardId),
              onOpenBoardList: () => { this.boardLibOpen = true },
              onOpenCardLibrary: () => { this.cardLibOpen = true },
              onClose: () => closeCanvasAnimated(this.getUIContext()),
              captionInset: app.ui.captionInset
            }
          })
            .layoutWeight(1)
            .width('100%')
            .height('100%')
        } else if (this.booted) {
          this.noBoardState()
        }
        if (this.boardLibOpen) {
          this.boardLayer()
        }
        if (this.cardLibOpen) {
          this.cardLayer()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.colors().bgPrimary)
    .geometryTransition(CANVAS_SURFACE_ID)
  }
}
