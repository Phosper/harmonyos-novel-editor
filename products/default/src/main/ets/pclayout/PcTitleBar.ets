// PcTitleBar.ets — Custom title bar, system window controls on right
import { pcColors, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'

@Component
export struct PcTitleBar {
  @StorageLink('colorMode') colorMode: number = 1
  @State titleButtonWidth: number = 138

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

      Row() { }
      .width(this.titleButtonWidth).height('100%')
    }
    .width('100%').height(40).padding({ left: 10 })
    .backgroundColor(this.getColors().BG_SECONDARY)
    .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
  }
}
