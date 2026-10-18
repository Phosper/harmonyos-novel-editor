// 设置页 —— 状态管理 V2 版本
//
// 主题为全局唯一来源（DesignTokens.THEMES）：选中态由 app.ui.themeId 派生；
// 编辑器纸色随全局主题联动（正文字号/行距仍独立）。
import { app } from '../../store/AppStores'
import { tokensFor, WeaverColorSet, THEMES, WeaverTheme } from '../../constants/DesignTokens'
import { GlowPageBackground, glassBarStyle } from '../../shell/MaterialSurface'
import { sheenGlass, GLASS_NONE_GRADIENT } from '../../constants/LightTokens'

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
            Column() {
              // 主题（全局）
              Text('主题').fontSize(13).fontColor(this.colors().textSecondary)
                .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 4 })
              ForEach(THEMES, (t: WeaverTheme) => {
                Row() {
                  Text(t.name).fontSize(16).fontColor(this.colors().textPrimary)
                  Row() { }.layoutWeight(1)
                  if (app.ui.themeId === t.id) {
                    Text('✓').fontSize(18).fontColor(this.colors().brand)
                  }
                }
                .width('100%').height(52).padding({ left: 16, right: 16 })
                .linearGradient({
                  angle: 180,
                  colors: app.ui.themeId === t.id ? sheenGlass(app.ui.themeId).gradient : GLASS_NONE_GRADIENT
                })
                .border({ width: { bottom: 1 }, color: this.colors().divider })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { app.ui.setTheme(t.id) })
              }, (t: WeaverTheme) => t.id)

              // 写作体验
              Row() {
                Text('打字机模式（当前段居中）').fontSize(16).fontColor(this.colors().textPrimary)
                Row() { }.layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: app.ui.typewriter })
                  .onChange((on: boolean) => { app.ui.typewriter = on })
              }.width('100%').height(52).padding({ left: 16, right: 16 })
              .border({ width: { bottom: 1 }, color: this.colors().divider })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
            }.width('100%')
          }.layoutWeight(1).width('100%')
        }.width('100%').height('100%').backgroundColor(Color.Transparent)
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
