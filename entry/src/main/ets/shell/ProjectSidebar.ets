// 侧栏 —— 项目列表 + 文库筛选
//
// 2026-10-21 视觉/动画修订：
//   - 项目行、文库入口使用 HarmonyOS Symbol（folder / doc_text / star / lightbulb / trash）；
//   - 列表内容显式顶对齐（constraintSize minHeight 100% + FlexAlign.Start），
//     修复项目数量变化时内容块被 Scroll 居中、整块上下跳动（“从底部出现”）的问题；
//   - 选中态只用低饱和 activeBg + 字重差，不再叠加渐变/投影。
import { tokensFor, WeaverColorSet, WeaverRadii, LibId, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import { UserAvatar } from './UserAvatar'
import { TopActionButton } from './TopActionButton'
import { startWindowMove, toggleWindowMaximize, isDesktopWindow } from '../utils/WindowDrag'
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
  /**
   * 左下角账号行是**唯一**的设置入口：
   * 账号已并入设置页（设置页顶部分组），不再单列「设置」行，避免同一目的地两个入口。
   */
  @Event onSettings: () => void = () => {}

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

  private libSymbol(id: LibId): Resource {
    if (id === LibId.FAV) {
      return $r('sys.symbol.star')
    }
    if (id === LibId.INSP) {
      return $r('sys.symbol.lightbulb')
    }
    if (id === LibId.TRASH) {
      return $r('sys.symbol.trash')
    }
    return $r('sys.symbol.doc_text')
  }

  private hitSize(): number {
    if (this.tablet()) {
      return 56
    }
    return this.app !== null && this.app.ui.pointerPrimary ? 44 : 48
  }

  /** 平板形态：行高与字号整体放大，触摸更稳 */
  private tablet(): boolean {
    return this.app !== null && this.app.ui.tabletMode
  }

  private projects(): ProjectItem[] {
    return this.app !== null ? this.app.project.projects : []
  }

  build() {
    Column() {
      // ── 品牌头：Logo + Weaver（标题栏融合后，品牌归属侧栏而不是全宽窗口条）
      Row() {
        Image($r('app.media.startIcon'))
          .width(this.tablet() ? 24 : 20).height(this.tablet() ? 24 : 20)
          .objectFit(ImageFit.Contain)
          .accessibilityText('语流')
        Text('语流')
          .fontSize(this.tablet() ? 16 : 14).fontWeight(FontWeight.Medium)
          .fontColor(this.colors().textPrimary)
          .letterSpacing(0.2)
          .margin({ left: 8 })
        Blank()
      }
      .width('100%')
      .height(this.tablet() ? 56 : 48)
      .padding({ left: 16, right: 12 })
      .alignItems(VerticalAlign.Center)
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

      // ── 项目段头：标题 + 新建
      Row() {
        Text('项目')
          .fontSize(this.tablet() ? 13 : 12).fontWeight(FontWeight.Medium)
          .fontColor(this.colors().textTertiary)
          .layoutWeight(1)
        TopActionButton({
          symbol: $r('sys.symbol.plus'),
          label: '新建项目',
          themeId: this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID,
          pointerPrimary: this.app !== null && this.app.ui.pointerPrimary,
          tabletMode: this.tablet(),
          desktopMode: this.app !== null && this.app.ui.usesDesktopChrome,
          onTap: () => this.onCreateProject()
        })
      }
      .width('100%')
      .height(this.hitSize() + 4)
      .padding({ left: 16, right: 8 })

      Scroll() {
        Column() {
          // ── 项目列表（显式顶对齐；内容不足一屏时不会被居中）
          ForEach(this.projects(), (p: ProjectItem) => {
            Row() {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(15)
                .fontColor([p.color])
                .margin({ right: 10 })
              Text(p.name)
                .fontSize(13).layoutWeight(1)
                .fontColor(p.active ? this.colors().textPrimary : this.colors().textSecondary)
                .fontWeight(p.active ? FontWeight.Medium : FontWeight.Regular)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(p.docCount.toString())
                .fontSize(11).fontColor(this.colors().textTertiary)
            }
            .width('100%')
            .height(this.tablet() ? 52 : 44)
            .padding({ left: 14, right: 16 })
            .borderRadius(WeaverRadii.MD)
            .backgroundColor(p.active ? this.colors().activeBg : Color.Transparent)
            .animation({ duration: Motion.fast, curve: Motion.standardCurve })
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
            .margin({ left: 16, right: 16, top: 8, bottom: 8 })

          // ── 文库段头
          Row() {
            SymbolGlyph($r('sys.symbol.bookshelf'))
              .fontSize(13)
              .fontColor([this.colors().textTertiary])
              .margin({ right: 6 })
            Text('文库')
              .fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.colors().textTertiary)
          }
          .width('100%')
          .padding({ left: 16, bottom: 4 })

          ForEach(this.libs(), (lib: LibEntry) => {
            Row() {
              SymbolGlyph(this.libSymbol(lib.id))
                .fontSize(15)
                .fontColor([this.isActiveLib(lib.id) ? this.colors().brand : this.colors().textTertiary])
                .margin({ right: 10 })
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
            .height(this.tablet() ? 48 : 40)
            .padding({ left: 14, right: 16 })
            .borderRadius(WeaverRadii.MD)
            .backgroundColor(this.isActiveLib(lib.id) ? this.colors().activeBg : Color.Transparent)
            .animation({ duration: Motion.fast, curve: Motion.standardCurve })
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
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, right: 8, top: 2, bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      // 显式顶对齐：Scroll 内容不足一屏时默认可能被居中，项目数量变化会导致整块上下跳动
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // ── 左下角账号行（唯一入口：账号 + 设置已合并到设置页）
      //    固定在侧栏底部而不是跟着列表滚走 —— 入口位置必须可预期。
      Column() {
        Divider()
          .color(this.colors().divider)
          .margin({ left: 12, right: 12, bottom: 6 })

        // 用户行：头像 + 昵称；未登录时昵称位置是「请登录」文字按钮（同一入口）
        Row() {
          UserAvatar({ avatarSize: this.tablet() ? 28 : 26 })
            .margin({ right: 10 })

          if (this.loggedIn()) {
            Text(this.nickname())
              .fontSize(this.tablet() ? 14 : 13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.colors().textPrimary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text('请登录')
              .fontSize(this.tablet() ? 14 : 13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.colors().brand)
              .layoutWeight(1)
              .accessibilityText('请登录')
          }
        }
        .width('100%')
        .height(this.tablet() ? 56 : 50)
        .padding({ left: 14, right: 14 })
        .borderRadius(WeaverRadii.MD)
        .hoverEffect(HoverEffect.Highlight)
        .animation({ duration: Motion.fast, curve: Motion.standardCurve })
        .accessibilityText(this.loggedIn() ? this.nickname() + '，打开设置' : '请登录，打开设置')
        .onClick(() => {
          this.onSettings()
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 10 })
    }
    .width('100%').height('100%')
    .backgroundColor(this.colors().bgSurface)
    .border({ width: { right: 1 }, color: this.colors().divider })
  }

  private loggedIn(): boolean {
    return this.app !== null && this.app.ui.isLoggedIn()
  }

  private nickname(): string {
    return this.app !== null ? this.app.ui.nickname : ''
  }

}
