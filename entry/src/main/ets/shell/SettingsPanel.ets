// 设置面板（可复用）—— 由 bindSheet 底部弹层承载，替代整页跳转
import { app } from '../store/AppStores'
import { tokensFor, WeaverColorSet, THEMES, WeaverTheme } from '../constants/DesignTokens'
import { sheenGlass, GLASS_NONE_GRADIENT } from '../constants/LightTokens'

@ComponentV2
export struct SettingsPanel {
  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  build() {
    Column() {
      Text('设置')
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.colors().textPrimary)
        .width('100%').padding({ left: 16, top: 4, bottom: 10 })

      Text('主题')
        .fontSize(13).fontColor(this.colors().textSecondary)
        .width('100%').padding({ left: 16, bottom: 4 })

      ForEach(THEMES, (t: WeaverTheme) => {
        Row() {
          Text(t.name).fontSize(16).fontColor(this.colors().textPrimary)
          Row() { }.layoutWeight(1)
          if (app.ui.themeId === t.id) {
            Text('✓').fontSize(18).fontColor(this.colors().brand)
          }
        }
        .width('100%').height(52).padding({ left: 16, right: 16 })
        // 选中态用品牌薄纱（零模糊），未选中透出弹层玻璃
        .linearGradient({
          angle: 180,
          colors: app.ui.themeId === t.id ? sheenGlass(app.ui.themeId).gradient : GLASS_NONE_GRADIENT
        })
        .border({ width: { bottom: 1 }, color: this.colors().divider })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { app.ui.setTheme(t.id) })
      }, (t: WeaverTheme) => t.id)

      Row() {
        Text('打字机模式（当前段居中）').fontSize(16).fontColor(this.colors().textPrimary)
        Row() { }.layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: app.ui.typewriter })
          .onChange((on: boolean) => { app.ui.typewriter = on })
      }
      .width('100%').height(52).padding({ left: 16, right: 16 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
    }
    .width('100%')
  }
}
