// 侧栏 —— 项目列表 + 文库筛选
//
// 2026-10-18 电脑模式 UI 重构：
//   - 去掉与窗口标题/列表头重复的「Weaver / 新建文稿 / 当前项目名」三处信息；
//   - 信息层级：项目（一级，含"新建项目"）→ 文库（二级筛选）；
//   - 统一 44vp 行高、8px 内边距、1px 分隔线与 hover/选中两态；
//   - 内容放进 Scroll：项目多时不再溢出（旧实现是无滚动 Column，超长会被裁掉）。
import { tokensFor, WeaverColorSet, WeaverRadii, LibId, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { fireAndLog } from '../store/AppStores'
import type { ProjectItem } from '../store/StoreModels'
import { sheenGlass, GLASS_NONE_GRADIENT } from '../constants/LightTokens'

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

  private themeId(): string {
    return this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID
  }

  private projects(): ProjectItem[] {
    return this.app !== null ? this.app.project.projects : []
  }

  build() {
    Column() {
      // ── 项目段头：标题 + 新建（唯一入口，替代旧 header 的"新建文稿"错位按钮）
      Row() {
        Text('项目')
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(this.colors().textTertiary)
          .layoutWeight(1)
        Text('+')
          .fontSize(18)
          .fontColor(this.colors().textSecondary)
          .width(32).padding({ top: 4, bottom: 4 }).textAlign(TextAlign.Center)
          .borderRadius(WeaverRadii.SM)
          .accessibilityText('新建项目')
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onCreateProject())
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 8 })

      Scroll() {
        Column() {
          // ── 项目列表
          ForEach(this.projects(), (p: ProjectItem) => {
            Row() {
              Circle({ width: 8, height: 8 })
                .fill(p.color).margin({ right: 10 })
              Text(p.name)
                .fontSize(13).layoutWeight(1)
                .fontColor(p.active ? this.colors().textPrimary : this.colors().textSecondary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(p.docCount.toString())
                .fontSize(11).fontColor(this.colors().textTertiary)
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .borderRadius(WeaverRadii.MD)
            .backgroundColor(Color.Transparent)
            .linearGradient({
              angle: 180,
              colors: p.active ? sheenGlass(this.themeId()).gradient : GLASS_NONE_GRADIENT
            })
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText(p.name + (p.active ? '（当前项目）' : ''))
            .margin({ bottom: 2 })
            .onClick(() => {
              if (this.app !== null) {
                fireAndLog(this.app.selectBook(p.id), 'selectBook')
              }
            })
            .gesture(LongPressGesture().onAction(() => this.onDeleteProject(p.id)))
          }, (p: ProjectItem): string => p.id)

          Divider()
            .color(this.colors().divider)
            .margin({ left: 16, right: 16, top: 10, bottom: 10 })

          // ── 文库段头
          Text('文库')
            .fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textTertiary)
            .width('100%')
            .padding({ left: 16, bottom: 4 })

          ForEach(this.libs(), (lib: LibEntry) => {
            Row() {
              Text(lib.label)
                .fontSize(13).layoutWeight(1)
                .fontColor(this.isActiveLib(lib.id) ? this.colors().textPrimary : this.colors().textSecondary)
              if (lib.count > 0) {
                Text(lib.count.toString())
                  .fontSize(11).fontColor(this.colors().textTertiary)
                  .padding({ left: 6, right: 6 })
              }
            }
            .width('100%')
            .height(40)
            .padding({ left: 16, right: 16 })
            .borderRadius(WeaverRadii.MD)
            .backgroundColor(Color.Transparent)
            .linearGradient({
              angle: 180,
              colors: this.isActiveLib(lib.id) ? sheenGlass(this.themeId()).gradient : GLASS_NONE_GRADIENT
            })
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText(lib.label)
            .margin({ bottom: 1 })
            .onClick(() => {
              if (this.app !== null) {
                fireAndLog(this.app.setLibFilter(lib.id), 'setLibFilter')
              }
            })
          }, (lib: LibEntry): string => lib.id)
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%').height('100%')
    // 侧栏是"次级面"：bgSurface 与正文拉开色阶，右侧 1px 分隔线明确栏边界
    .backgroundColor(this.colors().bgSurface)
    .border({ width: { right: 1 }, color: this.colors().divider })
  }
}
