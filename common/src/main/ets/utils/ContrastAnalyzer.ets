// common/src/main/ets/utils/ContrastAnalyzer.ets

/**
 * WCAG 2.1 对比度分析器
 * 公式: (L1 + 0.05) / (L2 + 0.05)，其中 L 为相对亮度
 */
export class ContrastAnalyzer {
  static readonly MIN_RATIO_NORMAL: number = 4.5
  static readonly MIN_RATIO_LARGE: number  = 3.0

  static calculateRatio(fg: string, bg: string): number {
    const lumFg: number = ContrastAnalyzer.relativeLuminance(fg)
    const lumBg: number = ContrastAnalyzer.relativeLuminance(bg)
    const lighter: number = Math.max(lumFg, lumBg)
    const darker: number  = Math.min(lumFg, lumBg)
    return (lighter + 0.05) / (darker + 0.05)
  }

  static relativeLuminance(hex: string): number {
    const r: number = ContrastAnalyzer.linearize(ContrastAnalyzer.channel(hex, 1))
    const g: number = ContrastAnalyzer.linearize(ContrastAnalyzer.channel(hex, 3))
    const b: number = ContrastAnalyzer.linearize(ContrastAnalyzer.channel(hex, 5))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  private static channel(hex: string, offset: number): number {
    return parseInt(hex.substring(offset, offset + 2), 16)
  }

  private static linearize(channel: number): number {
    const c: number = channel / 255
    if (c <= 0.03928) {
      return c / 12.92
    }
    return Math.pow((c + 0.055) / 1.055, 2.4)
  }
}
