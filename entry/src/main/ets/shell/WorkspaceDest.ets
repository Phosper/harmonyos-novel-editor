// 工作区（第三栏 / 手机端编辑页）
//
// 借鉴纯纯写作的形态：
//   - 手机端：正文即主页；顶栏极简「☰ 目录 | 书名·章名 | ⋮」；
//     「文稿列表」用**原生抽屉** `SideBarContainer(Overlay)` 承载（不离开编辑上下文）。
//   - 宽屏：作为第三栏，只承载编辑器。
//
// 原生组件取舍（2026-10-05）：
//   - 抽屉：`SideBarContainer(SideBarContainerType.Overlay)` + `showSideBar`（原生滑出/覆盖）。
//   - 更多：`bindSheet` 底部弹层（替代 showActionMenu）；设置作为**二级页**（nav.pushPath）。
import { inputMethod } from '@kit.IMEKit'
import { tokensFor, WeaverColorSet, WeaverRadii } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import { app, fireAndLog } from '../store/AppStores'
import { ShellDialog, UiStore } from '../store/UiStore'
import { nav } from './Navigator'
import { EditorPane } from './EditorPane'
import { DocListPane } from './DocListPane'
import { FOCUS_EDITOR_ID, toggleFocusAnimated } from './FocusTransition'
import { glassBarStyle, glassVeilStyle } from './MaterialSurface'
import { sheetMaterial } from '../constants/LightTokens'
import { LongTakeSession, LongTakeTransitionDelegate, LongTakeTransitionParam } from '../thirdparty/ezcustomtransition/Index'

@ComponentV2
export struct WorkspaceDest {
  /** 保留参数以兼容调用方（当前仅用于语义） */
  @Param showBack: boolean = false
  /** 可观察的共享状态引用，供 Monitor 同时监听断点变化 */
  @Local ui: UiStore = app.ui
  /** 原生抽屉（文稿目录）是否展开 */
  @Local listOpen: boolean = false
  /** 「更多」底部弹层（bindSheet）显隐 */
  @Local moreOpen: boolean = false
  /** 弹层内的层级：0=更多动作，1=设置（在弹层内二级跳转，非独立页面） */
  private workspaceVisible: boolean = false
  /** 一镜到底：动画会话 + 上一页传入的参数（无参数时走普通转场） */
  @Local longTakeSession: LongTakeSession = new LongTakeSession()
  @Local longTakeParam: LongTakeTransitionParam | undefined = undefined

  /** 抽屉蒙层在 padding 内容区内、盖不到状态栏条：开关抽屉时同步压暗/还原状态栏 */
  @Monitor('listOpen', 'ui.breakPoint')
  onListOpenChange(): void {
    this.syncOverlayDim()
  }

  private syncOverlayDim(): void {
    this.ui.setOverlayDim(this.workspaceVisible && this.ui.isNarrow && this.listOpen)
  }

  private showWorkspace(): void {
    this.workspaceVisible = true
    this.syncOverlayDim()
  }

  private releaseDrawer(): void {
    this.workspaceVisible = false
    this.listOpen = false
    this.ui.setOverlayDim(false)
  }

  aboutToDisappear(): void {
    this.releaseDrawer()
  }

  private closeDrawerForBack(): boolean {
    if (this.ui.isNarrow && this.listOpen) {
      this.listOpen = false
      this.syncOverlayDim()
      return true
    }
    return false
  }

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private titleText(): string {
    const book: string = app.project.bookName
    const doc: string = app.editor.title
    if (doc !== '') {
      return book !== '' ? book + ' · ' + doc : doc
    }
    return book !== '' ? book : '语流'
  }

  /** 收起键盘（开弹层/抽屉前调用，避免键盘顶起面板） */
  private dismissKeyboard(): void {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (e) {
      // 焦点未就绪时忽略
    }
    try {
      inputMethod.getController().hideTextInput()
    } catch (e) {
      // 输入法未连接时忽略
    }
  }

  /** 面板里点某篇：切到该文稿（同页内切换，不 push），并收起抽屉 */
  private openDoc(id: string): void {
    // openChapter 现在按 id 读取完整正文，读库可能失败 → 必须接住拒绝
    fireAndLog(app.openChapter(id), 'WorkspaceDest.openDoc')
    this.listOpen = false
  }

  @Builder
  contentBody() {
      if (app.ui.isWide) {
        // 宽屏/电脑：第三栏承载编辑器；文稿标题内联在正文上方（窗口头已透明融合）。
        Column() {
          EditorPane({ app: app }).layoutWeight(1)
            .geometryTransition(FOCUS_EDITOR_ID)
        }
        .width('100%').height('100%')
        .backgroundColor(this.colors().bgPrimary)
      } else {
        // 手机/平板：原生侧边栏容器（AUTO）
        //   大屏/折叠屏展开 → Embed：**常驻左侧栏**
        //   手机窄屏 → Overlay：**抽屉覆盖**（showSideBar 触发滑入动画）
        SideBarContainer(SideBarContainerType.AUTO) {
          // 侧栏：文稿目录
          Column() {
            this.panelHeader()
            DocListPane({
              app: app,
              showHeader: true,
              onOpenDoc: (id: string) => this.openDoc(id),
              onRenameDoc: (id: string, current: string) =>
                app.ui.requestDialog(ShellDialog.RENAME_DOC, id, current, '', app.project.currentBookId),
              onDeleteDoc: (id: string, title: string) =>
                app.ui.requestDialog(ShellDialog.DELETE_DOC, id, '', title)
            })
              .layoutWeight(1)
          }
          .width('100%').height('100%')
          // 抽屉面板：次级面配色（零模糊，靠色阶与编辑区分开）
          .backgroundColor(this.colors().bgSurface)

          // 内容区：编辑页（抽屉展开时其右侧加一层点击即收起的遮罩）
          Stack() {
            Column() {
              this.topBar()
              EditorPane({ app: app, showTitle: false }).layoutWeight(1)
                .geometryTransition(FOCUS_EDITOR_ID)
            }
            .width('100%').height('100%')
            .backgroundColor(this.colors().bgPrimary)

            if (app.ui.isNarrow && this.listOpen) {
              Column()
                .width('100%').height('100%')
                .backgroundColor('#66000000')
                .onClick(() => { this.listOpen = false })
            }
          }
          .width('100%').height('100%')
        }
        .showSideBar(app.ui.isNarrow ? this.listOpen : true)
        .onChange((v: boolean) => {
          if (app.ui.isNarrow) {
            this.listOpen = v
          } else {
            // 宽屏侧栏常驻（Embed）无蒙层；断点切换瞬间纠正状态栏压暗态
            app.ui.setOverlayDim(false)
          }
        })
        .showControlButton(false)
        .sideBarWidth(300)
        .minSideBarWidth(240)
        .maxSideBarWidth(340)
        .minContentWidth(360)
        .autoHide(false)
        .width('100%').height('100%')
      }
  }

  build() {
    NavDestination() {
      if (this.longTakeParam) {
        // 一镜到底：由 delegate 在动画期间接管布局与背景
        LongTakeTransitionDelegate({
          longTakeSession: this.longTakeSession,
          contentBuilder: (): void => {
            this.contentBody()
          }
        })
      } else {
        this.contentBody()
      }
    }
    // 动画期间背景色由 session 动态管理；普通进入用主题底色
    .backgroundColor(this.longTakeParam ? this.longTakeSession.navDestinationBgColor : this.colors().bgPrimary)
    .hideTitleBar(true)
    .onReady((navDestContext: NavDestinationContext) => {
      const info = navDestContext.pathInfo
      if (info !== undefined && info.param !== undefined) {
        const record = info.param as Record<string, Object>
        this.longTakeParam = record['longTakeTransitionParam'] as LongTakeTransitionParam
      }
      if (this.longTakeParam) {
        this.longTakeSession.init(navDestContext, this.longTakeParam, {
          pop: () => { nav.pop() }
        })
      }
    })
    .onShown(() => this.showWorkspace())
    .onHidden(() => this.releaseDrawer())
    .onBackPressed(() => this.closeDrawerForBack())
    .width('100%').height('100%')
    // 「更多」：原生底部弹层（设置不再从这里进：唯一入口是侧栏左下角账号行）
    .bindSheet(this.moreOpen, this.moreSheet(), {
      height: 400,
      dragBar: true,
      showClose: true,
      // 半模态属于"弹窗类"，是 systemMaterial 真正生效的位置（全页面生效）；
      // 材质对象按档位缓存，不会每次 build 都 new。不支持的设备无效果，自动回落下面的 backgroundColor。
      systemMaterial: sheetMaterial(),
      backgroundColor: this.colors().bgPrimary,
      onDisappear: () => { this.moreOpen = false }
    })
  }

  @Builder
  moreSheet() {
    // 一级动作。设置入口已收敛到侧栏左下角账号行（账号 + 设置同一页），这里不再重复。
    Column() {
      Text('更多')
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
        .width('100%').padding({ left: 16, top: 4, bottom: 8 })

      Text('撤销').fontSize(16).fontColor(this.colors().textPrimary)
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.moreOpen = false; app.editor.undo() })
      Text('重做').fontSize(16).fontColor(this.colors().textPrimary)
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.moreOpen = false; app.editor.redo() })
      Text('一键排版').fontSize(16).fontColor(this.colors().textPrimary)
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.moreOpen = false; app.formatActiveDoc() })
      Text('收藏 / 取消收藏').fontSize(16).fontColor(this.colors().textPrimary)
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.moreOpen = false; fireAndLog(app.toggleFav(app.editor.activeId), 'toggleFav') })
      Text('移入 / 移出灵感池').fontSize(16).fontColor(this.colors().textPrimary)
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.moreOpen = false; fireAndLog(app.toggleInspiration(app.editor.activeId), 'toggleInspiration') })

      // 专注写作：手机/平板进入窗口内沉浸编辑（桌面还可用窗口头顶栏按钮与 F11）
      Row() {
        Text('专注写作').fontSize(16).fontColor(this.colors().textPrimary).layoutWeight(1)
        Text('隐藏侧栏与列表').fontSize(12).fontColor(this.colors().textTertiary)
      }
      .width('100%').height(52).padding({ left: 16, right: 16 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.moreOpen = false
        toggleFocusAnimated(this.getUIContext())
      })
    }
    .width('100%')
  }

  @Builder
  topBar() {
    Row() {
      if (app.ui.isWide) {
        // 宽屏：第三栏只显示标题
        Text(this.titleText())
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        // 手机（窄屏）：☰ 目录；大屏/折叠屏展开时侧栏常驻，不显示 ☰
        if (app.ui.isNarrow) {
          Row() {
            SymbolGlyph($r('sys.symbol.open_sidebar'))
              .fontSize(18)
              .fontColor([this.colors().brand])
            Text('目录')
              .fontSize(14).fontColor(this.colors().brand)
              .margin({ left: 4 })
          }
          .height(44)
          .padding({ left: 4, right: 10 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText('文稿目录')
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.dismissKeyboard()
            this.listOpen = true
          })
        }
        Text(this.titleText())
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
          .layoutWeight(1).maxLines(1).textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
            .fontSize(18)
            .fontColor([this.colors().textSecondary])
        }
        .width(44).height(44)
        .justifyContent(FlexAlign.Center)
        .accessibilityText('更多')
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.dismissKeyboard()
          this.moreOpen = true
        })
      }
    }
    .width('100%')
    .height(app.ui.isWide || !app.ui.immersive ? (app.ui.wideBar ? 48 : 52) : 0)
    .clip(true)
    .animation({ duration: Motion.normal, curve: Motion.standardCurve })
    .padding({ left: 16, right: 16 })
    // 自绘顶栏：手机/平板上它是本屏第 ① 层实时模糊（专注模式高度为 0，不产生绘制）；
    // lg 三栏下桌面标题栏已占第 ① 层，这里降成薄纱（零模糊），守住"每屏 ≤2 层模糊"的预算。
    .attributeModifier(app.ui.isWide ? glassVeilStyle(app.ui.themeId) : glassBarStyle(app.ui.themeId))
  }

  @Builder
  panelHeader() {
    Column() {
      Row() {
        Text(this.titleText())
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('✕')
          .fontSize(16).fontColor(this.colors().textTertiary)
          .padding({ left: 10, top: 4, bottom: 4 })
          .accessibilityText('收起目录')
          .onClick(() => { this.listOpen = false })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 6 })

      Row() {
        Text('+ 新建文稿')
          .fontSize(13).fontColor(this.colors().brand)
          .padding({ top: 4, bottom: 4 })
          .onClick(() => { fireAndLog(app.createChapter(), 'createChapter') })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 10 })

      Divider().color(this.colors().divider)
    }
    .width('100%')
  }
}
