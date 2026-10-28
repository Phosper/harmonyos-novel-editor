// 文稿列表 —— 搜索 + 点击打开 + 长按操作菜单
//
// 行内不再堆三个图标按钮：收藏/灵感/重命名/删除收进长按菜单，列表只承载
// 标题、摘要与字数，保持"简洁"，也避免窄栏里按钮挤压标题。
//
// 行的渲染用子组件 DocRow 而不是 @Builder：@Builder 参数是按值传递的，
// 状态变化后其函数体不保证重新执行；用 @ComponentV2 + @Param 则
// 参数变化必然驱动刷新，且能按行建立依赖（改一行只刷新那一行）。
import { promptAction } from '@kit.ArkUI'
import { tokensFor, WeaverColorSet, WeaverRadii, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { fireAndLog } from '../store/AppStores'
import { DocItem } from '../store/StoreModels'
import { ChapterFormat } from '../model/Chapter'
import type { ChapterModel } from '../model/Chapter'
import { Motion } from '../constants/Motion'
import { TopActionButton } from './TopActionButton'
import { MenuButton } from './MenuButton'
import { setPendingLongTake } from './LongTakeBridge'
import { ezCustomTransition } from '../thirdparty/ezcustomtransition/Index'
import { TopIconMetrics, topIconMetrics } from '../constants/LightTokens'
import { startWindowMove, toggleWindowMaximize, isDesktopWindow } from '../utils/WindowDrag'

@ComponentV2
struct DocRow {
  @Param item: DocItem = new DocItem('')
  @Param themeId: string = DEFAULT_THEME_ID
  /** 紧凑两行式（手机端）：标题 + 字数·时间，不显示摘要 */
  @Param compact: boolean = false
  /** 平板形态：字号/行高整体放大，触摸更稳 */
  @Param tabletMode: boolean = false
  @Event onOpen: (id: string) => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId)
  }

  build() {
    Row() {
      Column() {
        Row() {
          Text(this.item.title)
            .fontSize(this.tabletMode ? 17 : 14).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.item.format === ChapterFormat.MD) {
            Text('MD')
              .fontSize(9).fontColor(this.colors().textTertiary)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(WeaverRadii.XS)
              .backgroundColor(this.colors().bgSurface)
              .margin({ left: 6 })
          }
          if (this.item.isFav) {
            Text('★').fontSize(11).fontColor(this.colors().warning).margin({ left: 6 })
          }
        }.width('100%')

        if (!this.compact) {
          Text(this.item.subTitle)
            .fontSize(this.tabletMode ? 13 : 12).fontColor(this.colors().textTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 3 })
        }

        Row() {
          if (this.item.isTrash) {
            Text(this.item.expireDays + ' 天后清理')
              .fontSize(11).fontColor(this.colors().danger)
          } else {
            Text(this.item.modified).fontSize(this.tabletMode ? 12 : 11).fontColor(this.colors().textTertiary)
          }
          if (this.item.badge !== '') {
            Text(this.item.badge).fontSize(11).fontColor(this.colors().textTertiary).margin({ left: 8 })
          }
          if (this.item.isInspiration) {
            Text('灵感').fontSize(10).fontColor(this.colors().brand)
              .margin({ left: 8 })
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor(this.colors().activeBg)
              .borderRadius(WeaverRadii.XS)
          }
        }.width('100%').margin({ top: 5 })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: this.tabletMode ? 18 : 14, right: this.tabletMode ? 18 : 14,
      top: this.tabletMode ? 14 : 11, bottom: this.tabletMode ? 14 : 11 })
    // 触摸设备整行热区更大：平板 ≥64vp，其余 ≥48vp
    .constraintSize({ minHeight: this.tabletMode ? 64 : 56 })
    .accessibilityText(this.item.title)
    // 键鼠形态下悬停高亮（触摸设备无 hover，不产生额外绘制）
    .hoverEffect(HoverEffect.Highlight)
    // 选中态 = 品牌色薄纱（零实时模糊，列表里不做逐行模糊）；未选中透出页面光感
    .backgroundColor(this.item.selected ? this.colors().activeBg : Color.Transparent)
    .animation({ duration: Motion.fast, curve: Motion.standardCurve })
    .onClick(() => this.onOpen(this.item.id))
  }
}

@ComponentV2
export struct DocListPane {
  @Param app: AppStores | null = null
  @Param showHeader: boolean = true
  /** 桌面宽屏：目录开关放在列表头（不在窗口标题栏） */
  @Param showSidebarToggle: boolean = false
  /** 桌面宽屏：应用级“更多”（导出/导入/设置）入口 */
  @Param showMore: boolean = false
  /** 点击行时是否生成一镜到底参数（只在"列表 → 工作区"真的 push 的宿主里开） */
  @Param enableLongTake: boolean = false
  @Event onExport: () => void = () => {}
  @Event onImport: () => void = () => {}
  @Event onOpenDoc: (id: string) => void = () => {}
  @Event onRenameDoc: (id: string, current: string) => void = () => {}
  @Event onDeleteDoc: (id: string, title: string) => void = () => {}

  @Local keyword: string = ''
  /** 列表滚动器：横滑动作执行后用它收起展开行 */
  private listScroller: ListScroller = new ListScroller()

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  private visibleItems(): DocItem[] {
    if (this.app === null) {
      return []
    }
    const all: DocItem[] = this.app.project.docItems
    const q: string = this.keyword.trim().toLowerCase()
    if (q === '') {
      return all
    }
    return all.filter((item: DocItem) =>
      item.title.toLowerCase().includes(q) || item.subTitle.toLowerCase().includes(q))
  }

  /**
   * 筛选后的条数（供表头"N 篇"显示）。
   * 单独提供而不复用 visibleItems().length：表头只需要计数，
   * 无需构建完整数组。
   *
   * 注意：ArkTS 的 build() 内**不允许声明语句**（报10905210 单根校验），
   * 所以不能在 build 里 `const items = this.visibleItems()` 复用结果——
   * 只能通过方法调用取值，这也是本文件所有取值都走方法的原因。
   */
  private visibleCount(): number {
    if (this.app === null) {
      return 0
    }
    const all: DocItem[] = this.app.project.docItems
    const q: string = this.keyword.trim().toLowerCase()
    if (q === '') {
      return all.length
    }
    let n: number = 0
    for (const item of all) {
      if (item.title.toLowerCase().includes(q) || item.subTitle.toLowerCase().includes(q)) {
        n++
      }
    }
    return n
  }

  /** API 26 原生菜单同时支持触摸长按与鼠标右键，并捕获打开时的归属。 */
  private rowMenuItems(item: DocItem): MenuElement[] {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return []
    }
    const bookId: string = stores.project.currentBookId
    const isTrash: boolean = item.isTrash
    const labels: string[] = isTrash ? ['恢复', '彻底删除'] : [
      '重命名', item.isFav ? '取消收藏' : '收藏',
      item.isInspiration ? '移出灵感池' : '移入灵感池', '移入废纸篓'
    ]
    return labels.map((label: string, index: number): MenuElement => ({
      value: label,
      action: () => this.onRowMenuAction(item, index, bookId, isTrash)
    }))
  }

  private onRowMenuAction(item: DocItem, index: number, bookId: string, isTrash: boolean): void {
    const stores: AppStores | null = this.app
    if (stores === null || stores.project.currentBookId !== bookId) {
      return
    }
    const chapter: ChapterModel | undefined = stores.project.findChapter(item.id)
    if (chapter === undefined || chapter.bookId !== bookId || chapter.isTrash !== isTrash) { return }
    if (isTrash) {
      if (index === 0) {
        fireAndLog(stores.restoreChapter(item.id), 'restoreChapter')
      } else if (index === 1) {
        this.onDeleteDoc(item.id, chapter.title)
      }
    } else if (index === 0) {
      this.onRenameDoc(item.id, chapter.title)
    } else if (index === 1) {
      fireAndLog(stores.toggleFav(item.id), 'toggleFav')
    } else if (index === 2) {
      fireAndLog(stores.toggleInspiration(item.id), 'toggleInspiration')
    } else if (index === 3) {
      this.moveDocToTrash(item.id)
    }
  }

  /** 原生滑动操作：删除按钮 */
  /**
   * 默认删除 = 移入废纸篓（可恢复），并提供短时撤销。
   * 彻底删除只在废纸篓筛选的菜单里提供。
   */
  private moveDocToTrash(id: string): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    stores.moveToTrash(id)
      .then(() => {
        this.offerTrashUndo(stores, id)
      })
      .catch(() => {
        // 失败不能提示“已移入”；给出可重试反馈
        try {
          this.getUIContext().getPromptAction().showToast({ message: '移入废纸篓失败，请重试' })
        } catch (e) {
        }
      })
  }

  private offerTrashUndo(stores: AppStores, id: string): void {
    try {
      const undo: promptAction.Button = { text: '撤销', color: this.colors().brand }
      const ok: promptAction.Button = { text: '知道了', color: this.colors().textSecondary }
      this.getUIContext().getPromptAction().showDialog({
        title: '已移入废纸篓',
        message: '可在废纸篓中恢复；也可以立即撤销。',
        buttons: [undo, ok]
      }).then((res) => {
        if (res.index === 0) {
          fireAndLog(stores.restoreChapter(id), 'restoreChapter')
        }
      }).catch(() => {})
    } catch (e) {
      // 对话框不可用不影响移动本身
    }
  }

  /** 电脑端（PC / MatePad Edge 电脑模式）不提供横滑，只用弹出菜单 */
  private canSwipe(): boolean {
    return this.app !== null && !this.app.ui.usesDesktopChrome
  }

  private swipeCircleSize(): number {
    return this.app !== null && this.app.ui.tabletMode ? 48 : 44
  }

  private toggleFavOf(item: DocItem): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    fireAndLog(stores.toggleFav(item.id), 'toggleFav')
  }

  private toggleInspirationOf(item: DocItem): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    fireAndLog(stores.toggleInspiration(item.id), 'toggleInspiration')
  }

  /**
   * 触摸端（手机 / 平板 / 折叠屏）的横滑动作，对齐备忘录：
   * 行左滑后露出**一组圆形图标按钮**，行本身保持圆角，不再是整条红色方按钮。
   */
  @Builder
  swipeActionCircle(symbol: Resource, label: string, bg: string, run: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([Color.White])
    }
    .width(this.swipeCircleSize())
    .height(this.swipeCircleSize())
    .borderRadius(this.swipeCircleSize() / 2)
    .backgroundColor(bg)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick(() => {
      // 动作执行后收起横滑，不留展开态
      this.listScroller.closeAllSwipeActions()
      run()
    })
  }

  @Builder
  swipeActions(item: DocItem) {
    Row({ space: 10 }) {
      // 与备忘录一致：动作色是固定的强调色（不随主题明暗走），白字才保证对比度
      this.swipeActionCircle($r('sys.symbol.star'), '收藏', '#E8A33D',
        () => this.toggleFavOf(item))
      this.swipeActionCircle($r('sys.symbol.lightbulb'), '移入灵感池', '#4C8DFF',
        () => this.toggleInspirationOf(item))
      this.swipeActionCircle($r('sys.symbol.square_and_pencil'), '重命名', '#8B8B90',
        () => this.onRenameDoc(item.id, item.title))
      this.swipeActionCircle($r('sys.symbol.trash'), '移入废纸篓', '#E04B4B',
        () => this.moveDocToTrash(item.id))
    }
    .height('100%')
    .padding({ left: 12, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 列表头标题：当前文库筛选（全部文稿/收藏/灵感池/废纸篓）。
   * 书名已经在窗口头出现，这里作为"作用域"的副标题，避免同一标题重复两次。
   */
  private headerTitle(): string {
    return this.app !== null ? this.app.project.libLabel : ''
  }

  /** 列表头副标题：书名 · 条数（书名为空时只显示条数） */
  private headerSubtitle(): string {
    if (this.app === null) {
      return ''
    }
    const count: string = this.visibleCount().toString() + ' 篇'
    const book: string = this.app.project.bookName
    if (book.trim() === '') {
      return count
    }
    return book + ' · ' + count
  }

  private metrics(): TopIconMetrics {
    if (this.app === null) {
      return topIconMetrics(true, false, false)
    }
    return topIconMetrics(this.app.ui.pointerPrimary, this.app.ui.tabletMode,
      this.app.ui.usesDesktopChrome)
  }

  private hitSize(): number {
    return this.metrics().hitSize
  }

  private tablet(): boolean {
    return this.app !== null && this.app.ui.tabletMode
  }

  private sidebarSymbol(): Resource {
    return this.app !== null && this.app.ui.showSidebar
      ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar')
  }

  private canToggleSidebar(): boolean {
    return this.app !== null && this.app.ui.isWide
  }

  private sidebarToggleLabel(): string {
    return this.app !== null && this.app.ui.showSidebar ? '收起目录' : '展开目录'
  }

  private toggleSidebar(): void {
    if (this.app !== null) {
      this.app.ui.toggleSidebar()
    }
  }

  /** 菜单动作：与 Email 的三点菜单一致，锚定在按钮下方展开 */
  private onMoreAction(index: number): void {
    if (index === 0) {
      this.onExport()
    } else if (index === 1) {
      this.onImport()
    }
  }

  private createDoc(): void {
    if (this.app !== null) {
      // createChapter 末端会走 DAO throw，onClick 无法 await → 必须接住拒绝
      fireAndLog(this.app.createChapter(), 'createChapter')
    }
  }

  /** 头部「更多」：四点图标（dot_grid_2x2），与全项目一致 */
  @Builder
  headerMoreIcon(label: string) {
    MenuButton({
      label: label,
      themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
      pointerPrimary: this.app !== null && this.app.ui.pointerPrimary,
      tabletMode: this.app !== null && this.app.ui.tabletMode,
      desktopMode: this.app !== null && this.app.ui.usesDesktopChrome,
      isEnabled: this.app !== null,
      // 设置不再从这里进：账号与设置已合并，唯一入口是左下角账号行
      items: ['导出', '导入'],
      onSelect: (index: number) => this.onMoreAction(index)
    })
  }

  /** 打开行：先抓一镜到底参数（需要点击当下的截图），再交给宿主决定是否 push */
  private openRow(item: DocItem): void {
    if (this.enableLongTake && this.app !== null && !this.app.ui.isWide) {
      const param = ezCustomTransition.generateLongTakeParam(
        this.getUIContext(), 'doc_row_' + item.id, 0)
      setPendingLongTake(param)
    } else {
      setPendingLongTake(undefined)
    }
    this.onOpenDoc(item.id)
  }

  @Builder
  docRow(item: DocItem) {
    DocRow({
      item: item,
      themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
      compact: this.app !== null && !this.app.ui.isWide,
      tabletMode: this.tablet(),
      onOpen: (id: string) => this.openRow(item)
    })
  }

  @Builder
  headerIcon(symbol: Resource, label: string, action: () => void) {
    TopActionButton({
      symbol: symbol,
      label: label,
      themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
      pointerPrimary: this.app !== null && this.app.ui.pointerPrimary,
      tabletMode: this.app !== null && this.app.ui.tabletMode,
      desktopMode: this.app !== null && this.app.ui.usesDesktopChrome,
      onTap: action
    })
  }

  build() {
    Column() {
      if (this.showHeader) {
        Column() {
          Row() {
            if (this.showSidebarToggle && this.canToggleSidebar()) {
              this.headerIcon(this.sidebarSymbol(), this.sidebarToggleLabel(), () => this.toggleSidebar())
            }
            Blank()
            this.headerIcon($r('sys.symbol.plus'), '新建文稿', () => this.createDoc())
            if (this.showMore) {
              this.headerMoreIcon('更多应用操作')
            }
          }
          .width('100%')
          .height(this.hitSize())
          .padding({ left: this.tablet() ? 14 : 8, right: this.tablet() ? 14 : 8 })

          Column() {
            Text(this.headerTitle())
              .fontSize(this.tablet() ? 28 : 20).fontWeight(FontWeight.Bold)
              .fontColor(this.colors().textPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.headerSubtitle())
              .fontSize(this.tablet() ? 12 : 11).fontColor(this.colors().textTertiary)
              .margin({ top: 2 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 2, bottom: 4 })
          .alignItems(HorizontalAlign.Start)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down && isDesktopWindow()) {
              startWindowMove()
            }
          })
          .onMouse((event: MouseEvent) => {
            if (event.action === MouseAction.Press && event.button === MouseButton.Left && isDesktopWindow()) {
              startWindowMove()
            }
          })
          .gesture(TapGesture({ count: 2 }).onAction(() => {
            if (isDesktopWindow()) {
              toggleWindowMaximize()
            }
          }))

          Search({ value: this.keyword, placeholder: '搜索文稿' })
            .onChange((v: string) => { this.keyword = v })
            .width('100%').height(this.tablet() ? 44 : 36)
            .backgroundColor(this.colors().bgSurface)
            .border({ width: 1, color: this.colors().divider })
            .borderRadius(WeaverRadii.SM)
            .margin({ top: 6 })
        }
        .width('100%').padding({ left: this.tablet() ? 20 : 16, right: this.tablet() ? 16 : 12,
          top: this.tablet() ? 12 : 8, bottom: this.tablet() ? 12 : 10 })
        // 列表头：平整底色 + 1px 分隔，避免与正文争夺视觉层级
        .backgroundColor(this.colors().bgPrimary)
        .border({ width: { bottom: 1 }, color: this.colors().divider })
      }

      if (this.visibleCount() === 0) {
        Column() {
          Text(this.keyword.trim() === '' ? '还没有文稿' : '没有匹配的文稿')
            .fontSize(13).fontColor(this.colors().textTertiary)
          if (this.keyword.trim() === '') {
            Text('点右上角「+」新建文稿开始写作')
              .fontSize(12).fontColor(this.colors().textTertiary).margin({ top: 6 })
          }
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.visibleItems(), (item: DocItem) => {
            if (this.canSwipe()) {
              ListItem() {
                this.docRow(item)
              }
              .id('doc_row_' + item.id)
              .swipeAction({ end: this.swipeActions(item) })
              .bindContextMenuWithResponse(this.rowMenuItems(item))
            } else {
              // 电脑端：不支持横滑，动作全部走右键菜单
              ListItem() {
                this.docRow(item)
              }
              .id('doc_row_' + item.id)
              .bindContextMenuWithResponse(this.rowMenuItems(item))
            }
          }, (item: DocItem) => item.id)
        }
        .layoutWeight(1).width('100%')
        .backgroundColor(Color.Transparent)
        .divider({ strokeWidth: 1, color: this.colors().divider })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    // 列表是"一级面"：与侧栏(bgSurface)拉开色阶；右分隔线明确栏边界
    .backgroundColor(this.colors().bgPrimary)
    .border({ width: { right: 1 }, color: this.colors().divider })
  }
}
