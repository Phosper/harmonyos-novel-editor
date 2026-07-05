// MyTabPage.ets — Settings tab
import { router } from '@kit.ArkUI'
import { PreferenceHelper, PrefKeys, SemanticColors, GrayColors, GreenColors } from '@ohos/common'

@Component
export struct MyTabPage {
  @StorageLink('weaver_mode') weaverMode: string = 'normal'
  @State privacyShieldOn: boolean = false
  @State fontSize: number = 16

  async aboutToAppear(): Promise<void> {
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.init(getContext(this))
    this.weaverMode = await prefs.getString(PrefKeys.MODE, 'normal')
    this.privacyShieldOn = await prefs.getBoolean(PrefKeys.PRIVACY_SHIELD, false)
    this.fontSize = await prefs.getNumber(PrefKeys.FONT_SIZE, 16)
  }

  async switchMode(mode: string): Promise<void> {
    this.weaverMode = mode
    AppStorage.setOrCreate('weaver_mode', mode)
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.setMode(mode)
  }

  async togglePrivacy(value: boolean): Promise<void> {
    this.privacyShieldOn = value
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.setBoolean(PrefKeys.PRIVACY_SHIELD, value)
    // window.setWindowPrivacyMode(value) — TODO
  }

  build() {
    Column() {
      List({ space: 1 }) {
        // Mode switch
        ListItem() {
          Row() {
            Text('写作模式').fontSize(16).fontColor(GrayColors.G900).layoutWeight(1)
            Row({ space: 8 }) {
              Text(this.weaverMode === 'normal' ? '日常写作' : '小说创作')
                .fontSize(14).fontColor(GrayColors.G300)
              Text('→').fontSize(14).fontColor(GrayColors.G300)
            }
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
          .onClick(() => {
            const newMode: string = this.weaverMode === 'normal' ? 'professional' : 'normal'
            this.switchMode(newMode)
          })
        }

        // Paper theme entry
        ListItem() {
          Row() {
            Text('稿纸主题').fontSize(16).fontColor(GrayColors.G900).layoutWeight(1)
            Text('→').fontSize(14).fontColor(GrayColors.G300)
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
          .onClick(() => { router.pushUrl({ url: 'pages/ThemePage' }) })
        }

        // Font size
        ListItem() {
          Row() {
            Text('字体大小').fontSize(16).fontColor(GrayColors.G900).layoutWeight(1)
            Text(this.fontSize.toString() + 'fp')
              .fontSize(14).fontColor(GrayColors.G300)
            Text('→').fontSize(14).fontColor(GrayColors.G300)
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
          .onClick(() => { /* TODO: bindSheet Slider in detail */ })
        }

        // Privacy shield
        ListItem() {
          Row() {
            Text('隐私防窥').fontSize(16).fontColor(GrayColors.G900).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: $$this.privacyShieldOn })
              .onChange((value: boolean) => { this.togglePrivacy(value) })
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
        }

        // About
        ListItem() {
          Row() {
            Text('关于').fontSize(16).fontColor(GrayColors.G900).layoutWeight(1)
            Text('→').fontSize(14).fontColor(GrayColors.G300)
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
        }
      }
      .width('100%').layoutWeight(1)
      .backgroundColor(SemanticColors.BG_SURFACE)
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
