// PcDesignTokens.ets — Weaver V2 design tokens, official HarmonyOS SDK color values
export class PcColors {
  // Emphasize Blue (官方 #007DFF)
  static readonly EMPHASIZE: string = '#007DFF'
  static readonly EMPHASIZE_PRESSED: string = '#006CDE'
  static readonly EMPHASIZE_FADED: string = '#19007DFF'

  // Neutral Gray
  static readonly BG_PRIMARY: string = '#F1F3F5'
  static readonly BG_SECONDARY: string = '#FFFFFF'
  static readonly BG_TERTIARY: string = '#F8F8F8'
  static readonly BG_CANVAS: string = '#F5F5F5'

  // Text (official base = #182431)
  static readonly TEXT_PRIMARY: string = '#182431'
  static readonly TEXT_SECONDARY: string = '#99182431'
  static readonly TEXT_TERTIARY: string = '#66182431'
  static readonly TEXT_INVERT: string = '#FFFFFF'

  // Interactive
  static readonly CLICK_EFFECT: string = '#4D182431'
  static readonly HOVER: string = '#26182431'
  static readonly FOCUSED: string = '#007DFF'
  static readonly ACTIVE_BG: string = '#19007DFF'
  static readonly HOVER_BG: string = '#26182431'

  // Divider
  static readonly DIVIDER: string = '#33182431'

  // Editor
  static readonly EDITOR_BG: string = '#F5F5F5'
  static readonly EDITOR_BG_DARK: string = '#1E1E1E'

  // Function
  static readonly SUCCESS: string = '#007DFF'
  static readonly WARNING: string = '#FF7500'
  static readonly DANGER: string = '#FA2A2D'

  // Accent dimmed — forward-compatible replacement for legacy INFO
  static readonly EMPHASIZE_DIMMED: string = '#5B84C4'

  // Layout backgrounds
  static readonly SIDEBAR_BG: string = '#F8F8F8'
  static readonly LIST_BG: string = '#F1F3F5'
  static readonly TOOLBAR_BG: string = '#F8F8F8'

  // Accent colors for project dots, tab covers, etc.
  static readonly ACCENT_ORANGE: string = '#E67E22'
  static readonly ACCENT_GREEN: string = '#689F63'
  static readonly ACCENT_BROWN: string = '#C48A5B'
  static readonly ACCENT_PURPLE: string = '#8E7CC3'
  static readonly ACCENT_TEAL: string = '#4EA8A0'
  static readonly ACCENT_PINK: string = '#B85B7A'
  static readonly ACCENT_LIME: string = '#7AB75F'
}

export class PcInteraction {
  static readonly HOVER_DURATION: number = 100
  static readonly LIGHT_PRESS: string = '#E0E0E0'
}

export interface PcColorSet {
  EMPHASIZE: string
  EMPHASIZE_PRESSED: string
  EMPHASIZE_FADED: string
  EMPHASIZE_DIMMED: string
  BG_PRIMARY: string
  BG_SECONDARY: string
  BG_TERTIARY: string
  SIDEBAR_BG: string
  LIST_BG: string
  TOOLBAR_BG: string
  EDITOR_BG: string
  TEXT_PRIMARY: string
  TEXT_SECONDARY: string
  TEXT_TERTIARY: string
  TEXT_INVERT: string
  DIVIDER: string
  ACTIVE_BG: string
  HOVER_BG: string
  CLICK_EFFECT: string
  HOVER: string
  FOCUSED: string
  SUCCESS: string
  WARNING: string
  DANGER: string
}

export function pcColors(dark: boolean): PcColorSet {
  if (dark) {
    return {
      EMPHASIZE: '#007DFF',
      EMPHASIZE_PRESSED: '#006CDE',
      EMPHASIZE_FADED: '#26007DFF',
      EMPHASIZE_DIMMED: '#7BA4E0',
      BG_PRIMARY: '#1A1A1A',
      BG_SECONDARY: '#242424',
      BG_TERTIARY: '#2A2A2A',
      SIDEBAR_BG: '#1E1E1E',
      LIST_BG: '#1A1A1A',
      TOOLBAR_BG: '#2A2A2A',
      EDITOR_BG: '#1E1E1E',
      TEXT_PRIMARY: '#E8E8E8',
      TEXT_SECONDARY: '#B0B0B0',
      TEXT_TERTIARY: '#808080',
      TEXT_INVERT: '#FFFFFF',
      DIVIDER: '#3A3A3A',
      ACTIVE_BG: '#26007DFF',
      HOVER_BG: '#33FFFFFF',
      CLICK_EFFECT: '#4DFFFFFF',
      HOVER: '#33FFFFFF',
      FOCUSED: '#007DFF',
      SUCCESS: '#007DFF',
      WARNING: '#FF7500',
      DANGER: '#FA2A2D'
    }
  } else {
    return {
      EMPHASIZE: '#007DFF',
      EMPHASIZE_PRESSED: '#006CDE',
      EMPHASIZE_FADED: '#19007DFF',
      EMPHASIZE_DIMMED: '#5B84C4',
      BG_PRIMARY: '#F1F3F5',
      BG_SECONDARY: '#FFFFFF',
      BG_TERTIARY: '#F8F8F8',
      SIDEBAR_BG: '#F8F8F8',
      LIST_BG: '#F1F3F5',
      TOOLBAR_BG: '#F8F8F8',
      EDITOR_BG: '#F5F5F5',
      TEXT_PRIMARY: '#182431',
      TEXT_SECONDARY: '#99182431',
      TEXT_TERTIARY: '#66182431',
      TEXT_INVERT: '#FFFFFF',
      DIVIDER: '#33182431',
      ACTIVE_BG: '#19007DFF',
      HOVER_BG: '#26182431',
      CLICK_EFFECT: '#4D182431',
      HOVER: '#26182431',
      FOCUSED: '#007DFF',
      SUCCESS: '#007DFF',
      WARNING: '#FF7500',
      DANGER: '#FA2A2D'
    }
  }
}

export class PcRadii {
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 24
}

export class PcShadow {
  static readonly CARD: ShadowOptions = { radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 2 }
  static readonly FLOAT: ShadowOptions = { radius: 8, color: 'rgba(0,0,0,0.10)', offsetY: 4 }
  static readonly NONE: ShadowOptions = { radius: 0, color: 'rgba(0,0,0,0)', offsetY: 0 }
}

export class PcSpacing {
  /** 间距基数 4vp */
  static readonly BASE_UNIT: number = 4
  /** 快捷引用: 4/8/12/16/20/24/32/48 */
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 24
  static readonly XXL: number = 32
  static readonly XXXL: number = 48
  static readonly BASE: number = 4
  static readonly SIDEBAR_W: number = 240
  static readonly LIST_W: number = 300
  static readonly AGENT_W: number = 320
  static readonly GLASS_TOP_H: number = 48
  static readonly TAB_BAR_H: number = 44
  static readonly TOOLBAR_H: number = 44
  static readonly STATUSBAR_H: number = 36
}

export interface LibItem {
  id: string
  label: string
  icon: string
  count: number
  active: boolean
}

export interface ProjectItem {
  id: string
  name: string
  color: string
  docCount: number
  active: boolean
}

export interface DocListItem {
  id: string
  title: string
  subTitle: string
  coverColor: string
  emoji: string
  badge: string
  pinned: boolean
  modified: string
  wordCount: number
  selected: boolean
  progress: number
  isTrash: boolean
  expireDays: number
}

export interface TabItem {
  id: string
  title: string
  color: string
  active: boolean
  pinned: boolean
  dirty: boolean
}

export interface AgentMessage {
  role: string
  text: string
}

export enum EditorViewMode {
  EMPTY = 0,
  EDITOR = 1,
  MATERIAL = 2,
  MATERIAL_DETAIL = 3,
  GRAPH = 4,
  PROJECT_DETAIL = 5
}

export enum MidTabMode {
  CHAPTERS = 0,
  MATERIALS = 1,
  GRAPH = 2
}
