// ThemePage.ets — Paper theme selection: presets + custom image upload
import { router } from '@kit.ArkUI'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { PreferenceHelper, PrefKeys, PRESET_THEMES, DEFAULT_THEME, SemanticColors, GrayColors, GreenColors } from '@ohos/common'
import { ImageLuminanceAnalyzer } from '@ohos/common'
import type { PaperTheme, ImageReadabilityResult } from '@ohos/common'

@Entry
@Component
struct ThemePage {
  @State selectedTheme: PaperTheme = DEFAULT_THEME
  @State previewText: string = '这是示例文字，用于预览稿纸效果。文字对比度将自动分析。'
  @State analysisText: string = '✅ 对比度良好，无需遮罩'
  @State analysisColor: string = GreenColors.G500
  @State hasCustomImage: boolean = false

  async aboutToAppear(): Promise<void> {
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.init(getContext(this))
    const saved: string = await prefs.getString(PrefKeys.PAPER_THEME, '')
    if (saved !== '') {
      try {
        const theme: PaperTheme = JSON.parse(saved) as PaperTheme
        this.selectedTheme = theme
        this.hasCustomImage = theme.type === 'custom_image'
        this.updateAnalysis()
      } catch (e) {
        this.selectedTheme = DEFAULT_THEME
      }
    }
  }

  selectPreset(theme: PaperTheme): void {
    this.selectedTheme = theme
    this.hasCustomImage = false
    this.analysisText = '✅ 对比度良好，无需遮罩'
    this.analysisColor = GreenColors.G500
    this.saveTheme(theme)
  }

  async pickCustomImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      })
      if (result.photoUris.length === 0) return

      const uri: string = result.photoUris[0]
      const sandboxDir: string = getContext(this).filesDir + '/backgrounds'
      fileIo.mkdirSync(sandboxDir, true)
      const fileName: string = 'bg_' + Date.now().toString() + '.jpg'
      const destPath: string = sandboxDir + '/' + fileName

      // Copy file to sandbox via copyFile (handles content:// URIs)
      await fileIo.copyFile(uri, destPath)

      // Analyze luminance
      const imageSource: image.ImageSource = image.createImageSource(destPath)
      const opts: image.DecodingOptions = {
        desiredSize: { width: 400, height: 400 },
        desiredPixelFormat: 3 // RGBA_8888
      }
      const pixelMap: image.PixelMap = await imageSource.createPixelMap(opts)
      const analysis: ImageReadabilityResult =
        await ImageLuminanceAnalyzer.analyzeBackgroundImage(pixelMap, '#1A1A1A')

      // Build theme
      const theme: PaperTheme = {
        id: 'custom_' + Date.now().toString(),
        name: '自定义图片',
        type: 'custom_image',
        backgroundColor: '#EDF5EA',
        customImagePath: destPath,
        gridType: 'none',
        gridColor: null,
        textColor: '#1A1A1A',
        needsOverlay: analysis.needsOverlay,
        overlayColor: analysis.overlayColor,
        overlayOpacity: analysis.overlayOpacity
      }

      this.selectedTheme = theme
      this.hasCustomImage = true
      if (analysis.pass) {
        this.analysisText = '✅ 对比度 ' + analysis.worstContrast.toFixed(1) + ':1  无需遮罩'
        this.analysisColor = GreenColors.G500
      } else {
        this.analysisText = '⚠ 对比度 ' + analysis.worstContrast.toFixed(1) + ':1  已启用遮罩(' +
          Math.round(analysis.overlayOpacity * 100).toString() + '%)'
        this.analysisColor = '#D4A53D'
      }
      this.saveTheme(theme)
    } catch (err) {
      // silently fail for MVP
    }
  }

  updateAnalysis(): void {
    if (this.selectedTheme.needsOverlay) {
      this.analysisText = '⚠ 已启用自适应遮罩'
      this.analysisColor = '#D4A53D'
    } else {
      this.analysisText = '✅ 对比度良好，无需遮罩'
      this.analysisColor = GreenColors.G500
    }
  }

  async saveTheme(theme: PaperTheme): Promise<void> {
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.setString(PrefKeys.PAPER_THEME, JSON.stringify(theme))
  }

  async removeCustomBackground(): Promise<void> {
    this.selectedTheme = DEFAULT_THEME
    this.hasCustomImage = false
    this.analysisText = '✅ 对比度良好，无需遮罩'
    this.analysisColor = GreenColors.G500
    await this.saveTheme(DEFAULT_THEME)
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() { Text('←').fontSize(20) }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
        Text('稿纸主题').fontSize(20).fontWeight(FontWeight.Bold)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Blank().width(40)
      }
      .width('100%').height(56).padding({ left: 8, right: 8 })
      .backgroundColor(SemanticColors.BG_CARD)

      Column() {
        // Preview area
        Column() {
          Text(this.previewText)
            .fontSize(16)
            .fontColor(this.selectedTheme.textColor)
            .padding(20)
          Text(this.analysisText)
            .fontSize(12)
            .fontColor(this.analysisColor)
            .padding({ left: 20, bottom: 12 })
        }
        .width('90%')
        .borderRadius(8)
        .backgroundColor(this.selectedTheme.type === 'custom_image' && this.selectedTheme.customImagePath !== ''
          ? Color.Transparent : this.selectedTheme.backgroundColor)
        .margin({ top: 20, bottom: 16 })

        // Preset themes
        Text('预设主题').fontSize(14).fontColor(GrayColors.G700)
          .width('90%').margin({ bottom: 8 })

        Grid() {
          ForEach(PRESET_THEMES, (theme: PaperTheme) => {
            GridItem() {
              Column() {
                Text(theme.name).fontSize(13).fontColor(GrayColors.G900)
                  .padding(10)
              }
              .width('100%').height(60)
              .borderRadius(8)
              .backgroundColor(theme.backgroundColor)
              .border({ width: this.selectedTheme.id === theme.id ? 2 : 0, color: GreenColors.G500 })
              .onClick(() => { this.selectPreset(theme) })
            }
          }, (theme: PaperTheme) => theme.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('90%')

        Divider().width('90%').margin({ top: 20, bottom: 20 })

        // Custom image upload
        Button('📷 从相册选择自定义背景')
          .width('80%').height(44)
          .fontSize(14).fontColor(GrayColors.G900)
          .backgroundColor(GrayColors.G50)
          .borderRadius(8)
          .onClick(() => { this.pickCustomImage() })

        // Remove custom background
        if (this.hasCustomImage) {
          Button('移除自定义背景')
            .width('80%').height(44)
            .fontSize(14).fontColor('#C0392B')
            .backgroundColor(GrayColors.G50)
            .borderRadius(8)
            .margin({ top: 8 })
            .onClick(() => { this.removeCustomBackground() })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
