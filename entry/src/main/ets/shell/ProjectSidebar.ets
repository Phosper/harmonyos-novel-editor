// 侧栏 —— 文库分类 + 项目列表
import { tokensFor, WeaverColorSet, WeaverRadii, LibId, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { fireAndLog } from '../store/AppStores'
import type { ProjectItem } from '../store/StoreModels'

interface LibEntry {
  id: LibId
  label: string
  count: number
}

@ComponentV2
export struct ProjectSidebar {
  @Param app: AppStores | null = null
  @Event onCreateProject: () => void = () => {}
  @Event onDeleteProject: (id: string) => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  private libs(): LibEntry[] {
    if (this.app === null) {
      return []
    }
    const c = this.app.project.libCounts
    return [
      { id: LibId.ALL, label: '全部文稿', count: c.all },
      { id: LibId.FAV, label: '收藏', count: c.fav },
      { id: LibId.INSP, label: '灵感池', count: c.insp },
      { id: LibId.TRASH, label: '废纸篓', count: c.trash }
    ]
  }

  private isActiveLib(id: LibId): boolean {
    return this.app !== null && this.app.project.libFilter === id
  }

  build() {
    Column() {
      Row() {
        Text('Weaver')
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
          .layoutWeight(1)
        Button('新建文稿')
          .fontSize(13).height(30).padding({ left: 12, right: 12 })
          .backgroundColor(Color.Transparent).fontColor(this.colors().brand)
          .borderRadius(WeaverRadii.SM)
          .onClick(() => {
            if (this.app !== null) {
              // 这些动作末端都会走 DAO 的 throw，onClick 无法 await → 必须接住拒绝
              fireAndLog(this.app.createChapter(), 'createChapter')
            }
          })
      }
      .width('100%').padding({ left: 16, right: 12, top: 16, bottom: 12 })

      Text(this.app !== null ? this.app.project.bookName : '')
        .fontSize(12).fontColor(this.colors().textTertiary)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%').padding({ left: 16, bottom: 8 })

      Column() {
        Column() {
          ForEach(this.libs(), (lib: LibEntry) => {
            Row() {
              Text(lib.label)
                .fontSize(14).layoutWeight(1)
                .fontColor(this.isActiveLib(lib.id) ? this.colors().brand : this.colors().textPrimary)
              if (lib.count > 0) {
                Text(lib.count.toString())
                  .fontSize(12).fontColor(this.colors().textTertiary)
                  .padding({ left: 6, right: 6 })
              }
            }
            .width('100%')
            // 热区撑到 48vp（14+14+文本≈20），满足最小可点击热区
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .borderRadius(WeaverRadii.MD)
            // 未选中**透明**而不是铺灰底：官方侧边导航靠"选中态 + hover"表达层级，
            // 每项都铺灰会让整列变成一片灰块（此前观感"重"的主因）
            .backgroundColor(this.isActiveLib(lib.id) ? this.colors().activeBg : Color.Transparent)
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText(lib.label)
            .margin({ bottom: 4 })
            .onClick(() => {
              if (this.app !== null) {
                fireAndLog(this.app.setLibFilter(lib.id), 'setLibFilter')
              }
            })
          }, (lib: LibEntry) => lib.id)

          Divider().color(this.colors().divider).margin({ top: 12, bottom: 12 })

          Text('项目')
            .fontSize(12).fontColor(this.colors().textTertiary)
            .width('100%').padding({ left: 16, bottom: 6 })

          ForEach(this.app !== null ? this.app.project.projects : [], (p: ProjectItem) => {
            Row() {
              Circle({ width: 8, height: 8 })
                .fill(p.color).margin({ right: 10 })
              Text(p.name)
                .fontSize(14).layoutWeight(1)
                .fontColor(p.active ? this.colors().brand : this.colors().textPrimary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(p.docCount.toString())
                .fontSize(12).fontColor(this.colors().textTertiary)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .borderRadius(WeaverRadii.MD)
            .backgroundColor(p.active ? this.colors().activeBg : Color.Transparent)
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText(p.name)
            .margin({ bottom: 4 })
            .onClick(() => {
              if (this.app !== null) {
                fireAndLog(this.app.selectBook(p.id), 'selectBook')
              }
            })
            .gesture(LongPressGesture().onAction(() => this.onDeleteProject(p.id)))
          }, (p: ProjectItem) => p.id)

          Button('+ 新建项目')
            .width('100%').height(40).fontSize(14)
            // 文字按钮不铺底：靠品牌色文字表意，去掉灰块降低视觉重量
            .backgroundColor(Color.Transparent).fontColor(this.colors().brand)
            .borderRadius(WeaverRadii.MD).margin({ top: 8, bottom: 16 })
            .onClick(() => this.onCreateProject())
        }
        .width('100%').padding({ left: 8, right: 8 })
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.colors().bgPrimary)
  }
}
