// common/src/main/ets/utils/ImageLuminanceAnalyzer.ets
import { image } from '@kit.ImageKit'
import { ContrastAnalyzer } from './ContrastAnalyzer'

export interface ImageReadabilityResult {
  pass: boolean
  worstContrast: number
  criticalLuminance: number
  needsOverlay: boolean
  overlayColor: string
  overlayOpacity: number
}

export class ImageLuminanceAnalyzer {

  static async analyzeBackgroundImage(
    pixelMap: image.PixelMap,
    textColor: string
  ): Promise<ImageReadabilityResult> {

    const luminanceGrid: number[] = await ImageLuminanceAnalyzer.sampleLuminance(pixelMap, 20)

    const textLum: number = ContrastAnalyzer.relativeLuminance(textColor)
    const isDarkText: boolean = textLum < 0.5

    const criticalLuminance: number = isDarkText
      ? Math.min(...luminanceGrid)
      : Math.max(...luminanceGrid)

    const criticalBgHex: string = ImageLuminanceAnalyzer.luminanceToGrayHex(criticalLuminance)
    const ratio: number = ContrastAnalyzer.calculateRatio(textColor, criticalBgHex)

    if (ratio >= ContrastAnalyzer.MIN_RATIO_NORMAL) {
      return {
        pass: true,
        worstContrast: ratio,
        criticalLuminance: criticalLuminance,
        needsOverlay: false,
        overlayColor: '#FFFFFF',
        overlayOpacity: 0
      }
    }

    const overlayColor: string = isDarkText ? '#FFFFFF' : '#1A1A1A'
    const opacity: number = ImageLuminanceAnalyzer.binarySearchOpacity(
      textColor, criticalBgHex, overlayColor
    )

    return {
      pass: false,
      worstContrast: ratio,
      criticalLuminance: criticalLuminance,
      needsOverlay: true,
      overlayColor: overlayColor,
      overlayOpacity: Math.min(opacity, 0.6)
    }
  }

  private static async sampleLuminance(
    pixelMap: image.PixelMap,
    gridSize: number
  ): Promise<number[]> {
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    const width: number = info.size.width
    const height: number = info.size.height
    const results: number[] = []

    for (let row: number = 0; row < gridSize; row++) {
      for (let col: number = 0; col < gridSize; col++) {
        const x: number = Math.floor((col + 0.5) * width / gridSize)
        const y: number = Math.floor((row + 0.5) * height / gridSize)
        const pixelBuffer: ArrayBuffer = new ArrayBuffer(4)
        const area: image.PositionArea = {
          pixels: pixelBuffer,
          offset: 0,
          stride: 4,
          region: { size: { width: 1, height: 1 }, x: x, y: y }
        }
        await pixelMap.readPixels(area)
        const pixels: Uint8Array = new Uint8Array(pixelBuffer)
        results.push(ImageLuminanceAnalyzer.rgbToLuminance(pixels[0], pixels[1], pixels[2]))
      }
    }
    return results
  }

  private static rgbToLuminance(r: number, g: number, b: number): number {
    const linearize = (c: number): number => {
      const v: number = c / 255
      if (v <= 0.03928) {
        return v / 12.92
      }
      return Math.pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
  }

  private static luminanceToGrayHex(lum: number): string {
    const linear: number = lum
    const srgb: number = linear <= 0.0031308
      ? 12.92 * linear
      : 1.055 * Math.pow(linear, 1 / 2.4) - 0.055
    const v: number = Math.round(Math.max(0, Math.min(255, srgb * 255)))
    const hex: string = v.toString(16).padStart(2, '0')
    return '#' + hex + hex + hex
  }

  private static mixColors(bg: string, overlay: string, alpha: number): string {
    const ch = (h: string, o: number): number => parseInt(h.substring(o, o + 2), 16)
    const r: number = Math.round(ch(bg, 1) * (1 - alpha) + ch(overlay, 1) * alpha)
    const g: number = Math.round(ch(bg, 3) * (1 - alpha) + ch(overlay, 3) * alpha)
    const b: number = Math.round(ch(bg, 5) * (1 - alpha) + ch(overlay, 5) * alpha)
    return '#' + r.toString(16).padStart(2, '0') + g.toString(16).padStart(2, '0') + b.toString(16).padStart(2, '0')
  }

  private static binarySearchOpacity(
    textColor: string,
    criticalBg: string,
    overlayColor: string
  ): number {
    const targetRatio: number = ContrastAnalyzer.MIN_RATIO_NORMAL
    let low: number = 0.0
    let high: number = 1.0
    for (let i: number = 0; i < 12; i++) {
      const mid: number = (low + high) / 2
      const masked: string = ImageLuminanceAnalyzer.mixColors(criticalBg, overlayColor, mid)
      const ratio: number = ContrastAnalyzer.calculateRatio(textColor, masked)
      if (ratio >= targetRatio) {
        high = mid
      } else {
        low = mid
      }
    }
    return high
  }
}
