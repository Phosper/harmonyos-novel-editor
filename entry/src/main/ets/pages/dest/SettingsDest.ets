// 设置页（路由外壳）—— 手机端仍可用；桌面/平板走 AppShell 的半模态面板
//
// 内容统一由 shell/SettingsPanel.ets 提供（分组卡片版式），这里只负责页面外框：
// 光感背景 + 返回栏。两份宿主共用同一份设置内容，避免两套 UI 走样。
import { app } from '../../store/AppStores'
import { tokensFor, WeaverColorSet } from '../../constants/DesignTokens'
import { GlowPageBackground, glassBarStyle } from '../../shell/MaterialSurface'
import { SettingsPanel } from '../../shell/SettingsPanel'

@ComponentV2
export struct SettingsDest {
  @Event onBack: () => void = () => {}

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  build() {
    NavDestination() {
      Stack() {
        // 页面光感背景（渐变 + 顶部光晕，单层装饰）
        GlowPageBackground(app.ui.themeId)
        Column() {
          Row() {
            Text('返回').fontSize(15).fontColor(this.colors().brand).accessibilityText('返回').onClick(() => this.onBack())
            Text('设置').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
              .layoutWeight(1).textAlign(TextAlign.Center)
          }.width('100%').height(48).padding({ left: 16, right: 16 })
          // 自绘返回栏 → 玻璃条（blur + 渐变 + 1px 下沿高光）
          .attributeModifier(glassBarStyle(app.ui.themeId))

          Scroll() {
            SettingsPanel()
          }.layoutWeight(1).width('100%')
        }.width('100%').height('100%').backgroundColor(Color.Transparent)
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
