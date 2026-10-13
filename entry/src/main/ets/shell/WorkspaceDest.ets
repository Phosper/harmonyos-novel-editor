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
import { app, fireAndLog } from '../store/AppStores'
import { ShellDialog } from '../store/UiStore'
import { nav } from './Navigator'
import { EditorPane } from './EditorPane'
import { DocListPane } from './DocListPane'
import { SettingsPanel } from './SettingsPanel'

@ComponentV2
export struct WorkspaceDest {
  /** 保留参数以兼容调用方（当前仅用于语义） */
  @Param showBack: boolean = false
  /** 原生抽屉（文稿目录）是否展开 */
  @Local listOpen: boolean = false
  /** 「更多」底部弹层（bindSheet）显隐 */
  @Local moreOpen: boolean = false
  /** 弹层内的层级：0=更多动作，1=设置（在弹层内二级跳转，非独立页面） */
  @Local sheetPage: number = 0

  /** 抽屉蒙层在 padding 内容区内、盖不到状态栏条：开关抽屉时同步压暗/还原状态栏 */
  @Monitor('listOpen')
  onListOpenChange(): void {
    app.ui.setOverlayDim(app.ui.isNarrow && this.listOpen)
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
    return book !== '' ? book : 'Weaver'
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

  build() {
    NavDestination() {
      if (app.ui.isWide) {
        // 宽屏：第三栏只承载编辑器（列表/侧栏在其它栏）
        Column() {
          this.topBar()
          EditorPane({ app: app }).layoutWeight(1)
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
                app.ui.requestDialog(ShellDialog.RENAME_DOC, id, current),
              onDeleteDoc: (id: string, title: string) =>
                app.ui.requestDialog(ShellDialog.DELETE_DOC, id, '', title)
            })
              .layoutWeight(1)
          }
          .width('100%').height('100%')
          .backgroundColor(this.colors().bgPrimary)

          // 内容区：编辑页（抽屉展开时其右侧加一层点击即收起的遮罩）
          Stack() {
            Column() {
              this.topBar()
              EditorPane({ app: app }).layoutWeight(1)
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
    .hideTitleBar(true)
    .width('100%').height('100%')
    // 「更多」：原生底部弹层（设置作为二级页从中进入）
    .bindSheet(this.moreOpen, this.moreSheet(), {
      height: 400,
      dragBar: true,
      showClose: true,
      backgroundColor: this.colors().bgPrimary,
      onDisappear: () => { this.moreOpen = false }
    })
  }

  @Builder
  moreSheet() {
    if (this.sheetPage === 1) {
      // 二级：设置（在弹层内跳转，带返回）
      Column() {
        Row() {
          Text('‹ 更多')
            .fontSize(16).fontColor(this.colors().brand)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => { this.sheetPage = 0 })
        }
        .width('100%')
        SettingsPanel()
      }
      .width('100%')
    } else {
      // 一级：更多动作
      Column() {
        Text('更多')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
          .width('100%').padding({ left: 16, top: 4, bottom: 8 })

        Text('撤销').fontSize(16).fontColor(this.colors().textPrimary)
          .width('100%').height(52).padding({ left: 16, right: 16 })
          .onClick(() => { this.moreOpen = false; app.editor.undo() })
        Text('重做').fontSize(16).fontColor(this.colors().textPrimary)
          .width('100%').height(52).padding({ left: 16, right: 16 })
          .onClick(() => { this.moreOpen = false; app.editor.redo() })
        Text('一键排版').fontSize(16).fontColor(this.colors().textPrimary)
          .width('100%').height(52).padding({ left: 16, right: 16 })
          .onClick(() => { this.moreOpen = false; app.formatActiveDoc() })
        Text('收藏 / 取消收藏').fontSize(16).fontColor(this.colors().textPrimary)
          .width('100%').height(52).padding({ left: 16, right: 16 })
          .onClick(() => { this.moreOpen = false; fireAndLog(app.toggleFav(app.editor.activeId), 'toggleFav') })
        Text('移入 / 移出灵感池').fontSize(16).fontColor(this.colors().textPrimary)
          .width('100%').height(52).padding({ left: 16, right: 16 })
          .onClick(() => { this.moreOpen = false; fireAndLog(app.toggleInspiration(app.editor.activeId), 'toggleInspiration') })

        // 设置：在弹层内进入二级（保持同一个弹层，不跳独立页）
        Row() {
          Text('设置').fontSize(16).fontColor(this.colors().textPrimary).layoutWeight(1)
          Text('>').fontSize(15).fontColor(this.colors().textTertiary)
        }
        .width('100%').height(52).padding({ left: 16, right: 16 })
        .onClick(() => { this.sheetPage = 1 })
      }
      .width('100%')
    }
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
          Text('☰ 目录')
            .fontSize(15).fontColor(this.colors().brand)
            .padding({ right: 10, top: 10, bottom: 10 })
            .accessibilityText('文稿目录')
            .onClick(() => {
              this.dismissKeyboard()
              this.listOpen = true
            })
        }
        Text(this.titleText())
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
          .layoutWeight(1).maxLines(1).textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('⋮')
          .fontSize(20).fontColor(this.colors().textSecondary)
          .padding({ left: 10, top: 4, bottom: 4 })
          .accessibilityText('更多')
          .onClick(() => {
            this.dismissKeyboard()
            this.sheetPage = 0
            this.moreOpen = true
          })
      }
    }
    .width('100%')
    .height(app.ui.isWide || !app.ui.immersive ? 52 : 0)
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.colors().editorBg)
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
