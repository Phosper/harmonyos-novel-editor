// common/src/main/ets/constants/Colors.ets
// Weaver 色彩 Token 常量 — 基于规格 7.1-7.3 节

export class GreenColors {
  static readonly G50: string  = '#EDF5EA'
  static readonly G100: string = '#D3E9CB'
  static readonly G300: string = '#A4CE92'
  static readonly G500: string = '#7AB75F'
  static readonly G700: string = '#4A6E39'
  static readonly G900: string = '#2D4423'
}

export class GrayColors {
  static readonly G50: string  = '#F2F2F2'
  static readonly G100: string = '#D5D5D5'
  static readonly G300: string = '#9E9D9D'
  static readonly G500: string = '#6F6E6E'
  static readonly G700: string = '#4A4A4A'
  static readonly G900: string = '#1A1A1A'
}

export class SemanticColors {
  static readonly BG_PRIMARY: string    = GreenColors.G50
  static readonly BG_CARD: string       = '#FFFFFF'
  static readonly BG_SURFACE: string    = GrayColors.G50
  static readonly FONT_PRIMARY: string   = GrayColors.G900
  static readonly FONT_SECONDARY: string = GrayColors.G700
  static readonly FONT_TERTIARY: string  = GrayColors.G300
  static readonly INTERACTIVE_PRIMARY: string   = '#007DFF'
  static readonly INTERACTIVE_HOVER: string     = GreenColors.G700
  static readonly INTERACTIVE_SECONDARY: string = GreenColors.G300
  static readonly BORDER_DEFAULT: string = GrayColors.G100
}

export class GraphColors {
  static readonly NODE_MAIN: string     = '#E67E22'
  static readonly NODE_SUPPORT: string  = '#689F63'
  static readonly NODE_VILLAIN: string  = '#4A4A4A'
  static readonly NODE_ORG: string      = '#A4CE92'
  static readonly NODE_PLACE: string    = '#9E9D9D'
  static readonly LINE_POSITIVE: string = '#A4CE92'
  static readonly LINE_NEUTRAL: string  = '#9E9D9D'
  static readonly LINE_NEGATIVE: string = '#6F6E6E'
  static readonly LINE_INDIRECT: string = '#D5D5D5'
  static readonly HIGHLIGHT_RING: string = '#7AB75F'
  static readonly BG_CANVAS: string     = '#FAFAFA'
}

export class StatusColors {
  static readonly SUCCESS: string = '#4A8C7C'
  static readonly WARNING: string = '#D4A53D'
  static readonly ERROR: string   = '#C0392B'
}
