// 应用入口
//
// Navigation 现在位于 AppShell 内部（作为三分栏模型的第二/三栏，与 SideBarContainer 组合），
// 因此这里不再需要 @Provider 提供 navStack。
//
// 路由栈放在 shell/Navigator.ets 的模块级单例中：二级页面与各面板都能直接发起跳转，
// 避免逐层 @Event 透传。
import { AppShell } from '../shell/AppShell'
import { app } from '../store/AppStores'
import { tokensFor } from '../constants/DesignTokens'
import { fireAndLog } from '../store/AppStores'
import { closeCanvasAnimated } from '../shell/CanvasTransition'

@Entry
@ComponentV2
struct Index {
  /** 思路板是全窗口分支：返回键先收它，再交回系统 */
  onBackPress(): boolean {
    if (app.ui.canvasOpen) {
      closeCanvasAnimated(this.getUIContext())
      return true
    }
    return false
  }

  /** 全局撤销条：画布/编辑器/列表都可见（覆盖初稿后画布已关闭，也必须能撤销）。 */
  @Builder
  undoBar() {
    Row() {
      Text(app.canvas.undoLabel)
        .fontSize(12)
        .fontColor(tokensFor(app.ui.themeId).onBrand)
        .maxLines(1)
        .layoutWeight(1)
      Text('撤销')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(tokensFor(app.ui.themeId).onBrand)
        .padding({ left: 12, right: 6, top: 6, bottom: 6 })
        .onClick(() => {
          fireAndLog(app.canvas.performUndo(), 'Index.undo')
        })
        .accessibilityText('撤销')
    }
    .width(300)
    .height(44)
    .padding({ left: 14, right: 8 })
    .backgroundColor(tokensFor(app.ui.themeId).textPrimary)
    .borderRadius(10)
    .shadow({ radius: 18, color: tokensFor(app.ui.themeId).divider, offsetX: 0, offsetY: 6 })
    .margin({ bottom: 48 })
  }

  build() {
    // @Entry 的 build 根节点必须是容器组件，故包一层 Stack：撤销条要浮在所有页面之上。
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        AppShell()
      }
      .width('100%').height('100%')
      // 页面光感只由 AppShell 的 GlowPageBackground 画一层：
      // 这里再铺一条 linearGradient 会与它叠加，浅色主题下发灰、深色主题下发亮。
      if (app.canvas.undoLabel !== '') {
        this.undoBar()
      }
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
