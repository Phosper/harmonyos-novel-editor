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

@ComponentV2
struct DocRow {
  @Param item: DocItem = new DocItem('')
  @Param themeId: string = DEFAULT_THEME_ID
  /** 紧凑两行式（手机端）：标题 + 字数·时间，不显示摘要 */
  @Param compact: boolean = false
  @Event onOpen: (id: string) => void = () => {}
  @Event onMenu: (item: DocItem) => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(this.themeId)
  }

  build() {
    Row() {
      Column() {
        Row() {
          Text(this.item.title)
            .fontSize(14).fontWeight(FontWeight.Medium)
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
            .fontSize(12).fontColor(this.colors().textTertiary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 3 })
        }

        Row() {
          if (this.item.isTrash) {
            Text(this.item.expireDays + ' 天后清理')
              .fontSize(11).fontColor(this.colors().danger)
          } else {
            Text(this.item.modified).fontSize(11).fontColor(this.colors().textTertiary)
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
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    // 保证整行热区 ≥48vp（官方推荐值），窄屏触摸更稳
    .constraintSize({ minHeight: 56 })
    .accessibilityText(this.item.title)
    .backgroundColor(this.item.selected ? this.colors().activeBg : this.colors().bgPrimary)
    .onClick(() => this.onOpen(this.item.id))
    .gesture(LongPressGesture().onAction(() => this.onMenu(this.item)))
  }
}

@ComponentV2
export struct DocListPane {
  @Param app: AppStores | null = null
  @Param showHeader: boolean = true
  @Event onOpenDoc: (id: string) => void = () => {}
  @Event onRenameDoc: (id: string, current: string) => void = () => {}
  @Event onDeleteDoc: (id: string, title: string) => void = () => {}

  @Local keyword: string = ''

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

  // showActionMenu 的 buttons 是定长 tuple（1~6 项）而不是数组，故按分支写字面量元组
  private showRowMenu(item: DocItem): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const prompt = this.getUIContext().getPromptAction()
    if (item.isTrash) {
      const restore: promptAction.Button = { text: '恢复', color: this.colors().textPrimary }
      const purge: promptAction.Button = { text: '彻底删除', color: this.colors().textPrimary }
      prompt.showActionMenu({ title: item.title, buttons: [restore, purge] }, (err, data) => {
        if (err) {
          return
        }
        // 这些动作末端都会走 DAO 的 throw，而这里无法 await → 必须接住拒绝
        if (data.index === 0) {
          fireAndLog(stores.restoreChapter(item.id), 'restoreChapter')
        } else {
          fireAndLog(stores.hardDeleteChapter(item.id), 'hardDeleteChapter')
        }
      })
      return
    }
    const rename: promptAction.Button = { text: '重命名', color: this.colors().textPrimary }
    const fav: promptAction.Button = { text: item.isFav ? '取消收藏' : '收藏', color: this.colors().textPrimary }
    const insp: promptAction.Button = { text: item.isInspiration ? '移出灵感池' : '移入灵感池', color: this.colors().textPrimary }
    const trash: promptAction.Button = { text: '移入废纸篓', color: this.colors().textPrimary }
    prompt.showActionMenu({ title: item.title, buttons: [rename, fav, insp, trash] }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0) {
        this.onRenameDoc(item.id, item.title)
      } else if (data.index === 1) {
        fireAndLog(stores.toggleFav(item.id), 'toggleFav')
      } else if (data.index === 2) {
        fireAndLog(stores.toggleInspiration(item.id), 'toggleInspiration')
      } else {
        fireAndLog(stores.moveToTrash(item.id), 'moveToTrash')
      }
    })
  }

  /** 原生滑动操作：删除按钮 */
  @Builder
  swipeDelete(item: DocItem) {
    Button('删除')
      .fontSize(14).fontColor('#FFFFFF')
      .height('100%').width(88)
      .backgroundColor(this.colors().danger)
      .onClick(() => this.onDeleteDoc(item.id, item.title))
  }

  build() {
    Column() {
      if (this.showHeader) {        Column() {
          Row() {
            Text(this.app !== null ? this.app.project.libLabel : '')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.visibleCount() + ' 篇')
              .fontSize(11).fontColor(this.colors().textTertiary)
          }.width('100%')

          Search({ value: this.keyword, placeholder: '搜索文稿' })
            .onChange((v: string) => { this.keyword = v })
            .width('100%').height(40)
            .backgroundColor(this.colors().bgSurface)
            .borderRadius(WeaverRadii.SM)
            .margin({ top: 10 })
        }
        .width('100%').padding({ left: 14, right: 14, top: 14, bottom: 10 })
      }

      if (this.visibleCount() === 0) {
        Column() {
          Text(this.keyword.trim() === '' ? '还没有文稿' : '没有匹配的文稿')
            .fontSize(13).fontColor(this.colors().textTertiary)
          if (this.keyword.trim() === '') {
            Text('点左下角「新建文稿」开始写作')
              .fontSize(12).fontColor(this.colors().textTertiary).margin({ top: 6 })
          }
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.visibleItems(), (item: DocItem) => {
            ListItem() {
              DocRow({
                item: item,
                themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
                compact: this.app !== null && !this.app.ui.isWide,
                onOpen: (id: string) => this.onOpenDoc(id),
                onMenu: (target: DocItem) => this.showRowMenu(target)
              })
            }
            // 原生滑动操作：左滑删除（移入废纸篓）
            .swipeAction({ end: this.swipeDelete(item) })
          }, (item: DocItem) => item.id)
        }
        .layoutWeight(1).width('100%')
        .backgroundColor(this.colors().listBg)
        .divider({ strokeWidth: 1, color: this.colors().divider })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.colors().bgPrimary)
  }
}
