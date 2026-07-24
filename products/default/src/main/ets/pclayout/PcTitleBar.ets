// PcTitleBar.ets — HarmonyOS-style custom title bar
import { pcColors, PcInteraction, PcRadii, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'

@Component
export struct PcTitleBar {
  @StorageLink('colorMode') colorMode: number = 1
  @Prop showControls: boolean = true
  @State hoveredBtnId: string = ''
  @State isMaximized: boolean = false

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  getWin(): window.Window | undefined {
    return AppStorage.get<window.Window>('mainWindow')
  }

  async startWindowMove(): Promise<void> {
    const win: window.Window | undefined = this.getWin()
    if (win !== undefined) {
      try { win.startMoving() } catch (e) { }
    }
  }

  async onMinimize(): Promise<void> {
    const win: window.Window | undefined = this.getWin()
    if (win !== undefined) { await win.minimize() }
  }

  async onMaxRestore(): Promise<void> {
    const win: window.Window | undefined = this.getWin()
    if (win !== undefined) {
      if (this.isMaximized) {
        await win.restore()
        this.isMaximized = false
      } else {
        await win.maximize()
        this.isMaximized = true
      }
    }
  }

  async onClose(): Promise<void> {
    const win: window.Window | undefined = this.getWin()
    if (win !== undefined) { await win.destroyWindow() }
  }

  build() {
    Row() {
      Row() { Text('W').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#FFFFFF') }
      .width(20).height(20).borderRadius(5)
      .linearGradient({
        direction: GradientDirection.RightBottom,
        colors: [[this.getColors().EMPHASIZE, 0.0], [this.getColors().EMPHASIZE_PRESSED, 1.0]]
      }).justifyContent(FlexAlign.Center)

      Blank()
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) { this.startWindowMove() }
        })
        .hitTestBehavior(HitTestMode.Default)

      if (this.showControls) {
        Button() { Text('─').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY) }
        .width(32).height(32).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'min' : '' })
        .backgroundColor(this.hoveredBtnId === 'min' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onMinimize() })

        Button() { Text('□').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY) }
        .width(32).height(32).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'max' : '' })
        .backgroundColor(this.hoveredBtnId === 'max' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onMaxRestore() })

        Button() { Text('✕').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY) }
        .width(32).height(32).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'close' : '' })
        .backgroundColor(this.hoveredBtnId === 'close' ? this.getColors().DANGER : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .onClick(() => { this.onClose() })
      }
    }
    .width('100%').height(40).padding({ left: 10, right: 4 })
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
  }
}
