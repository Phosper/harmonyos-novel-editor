// Weaver 设计令牌 —— 单一来源（北语绿品牌系统，明暗双主题）
// 依据开发规格文档第七节，合并旧版双调色板冲突。
import { CharacterType } from '../model/Character'
import { RelationshipType } from '../model/Relationship'
import { WorldCategory } from '../model/WorldSetting'

export interface WeaverColorSet {
  brand: string            // 品牌主色
  brandPressed: string     // 按下
  onBrand: string          // 品牌色上的文字
  bgPrimary: string        // 全局背景
  bgCard: string           // 卡片/编辑器/弹窗
  bgSurface: string        // 侧栏/Tab栏/次级
  textPrimary: string
  textSecondary: string
  textTertiary: string
  divider: string
  activeBg: string         // 选中浅底
  hoverBg: string
  success: string
  warning: string
  danger: string
  sidebarBg: string
  listBg: string
  toolbarBg: string
  editorBg: string
}

export interface LibCounts {
  all: number
  fav: number
  insp: number
  trash: number
}

export const EMPTY_LIB_COUNTS: LibCounts = { all: 0, fav: 0, insp: 0, trash: 0 }

// 文稿标签 / 项目配色（单一来源，供文档列表与项目列表共用）
// 文稿标签 / 项目配色（用于色点区分，与品牌色同族但不与主色抢眼）
export const DOC_TAB_COLORS: string[] = ['#007DFF', '#FA9D3B', '#64BB5C', '#8E7CC3', '#4EA8A0']
export const PROJECT_COLORS: string[] = ['#007DFF', '#FA9D3B', '#64BB5C', '#8E7CC3', '#4EA8A0', '#C48A5B']

// ================= 全局主题预设（2026-10-05 重构：极简纸墨为默认） =================
//
// 一套主题预设驱动整站配色；编辑器纸色随之联动（字号/行距仍独立）。
// 语义约定：brand = 墨（浅主题）/ 纸白（深主题），用于主按钮与强调；
//          交互选中用 activeBg（淡墨），按压用 hoverBg。

export interface WeaverTheme {
  id: string
  name: string
  dark: boolean
  colors: WeaverColorSet
}

/** 默认主题：极简纸墨 */
export const DEFAULT_THEME_ID: string = 'ink'

// 极简纸墨（默认·浅）：近白纸 + 近黑墨
const INK: WeaverColorSet = {
  brand: '#1C1C1E', brandPressed: '#000000', onBrand: '#FFFFFF',
  bgPrimary: '#FFFFFF', bgCard: '#FFFFFF', bgSurface: '#F6F6F7',
  textPrimary: '#1C1C1E', textSecondary: '#6E6E73', textTertiary: '#A6A6AB',
  divider: '#ECECEE', activeBg: '#0F1C1C1E', hoverBg: '#081C1C1E',
  success: '#248A3D', warning: '#B25000', danger: '#D70015',
  sidebarBg: '#FAFAFB', listBg: '#FFFFFF', toolbarBg: '#FFFFFF', editorBg: '#FFFFFF'
}

// 温暖米纸（浅）：米黄纸 + 深褐字
const WARM: WeaverColorSet = {
  brand: '#4A3A2A', brandPressed: '#332619', onBrand: '#FFFFFF',
  bgPrimary: '#F7F1E6', bgCard: '#FDF9F1', bgSurface: '#EFE7D8',
  textPrimary: '#2E2418', textSecondary: '#6B5B45', textTertiary: '#9C8B72',
  divider: '#E3D8C4', activeBg: '#142E2418', hoverBg: '#0D2E2418',
  success: '#3F7D34', warning: '#8A5A00', danger: '#B3261E',
  sidebarBg: '#F2EBDE', listBg: '#FDF9F1', toolbarBg: '#FBF6EC', editorBg: '#F7F1E6'
}

// 青笺（浅）：淡青绿纸
const GREEN: WeaverColorSet = {
  brand: '#2A3A2A', brandPressed: '#1B271B', onBrand: '#FFFFFF',
  bgPrimary: '#F1F6F0', bgCard: '#FAFDF9', bgSurface: '#E8F0E6',
  textPrimary: '#1F2A1F', textSecondary: '#4F6350', textTertiary: '#85968A',
  divider: '#DCE7DA', activeBg: '#142A3A2A', hoverBg: '#0D2A3A2A',
  success: '#3F7D34', warning: '#8A5A00', danger: '#B3261E',
  sidebarBg: '#EDF3EB', listBg: '#FAFDF9', toolbarBg: '#F8FCF7', editorBg: '#F1F6F0'
}

// 夜读（深）：对齐纯纯写作实测——柔和深灰（非纯黑）+ 浅字，顶栏与正文同底
const NIGHT: WeaverColorSet = {
  brand: '#EDEDED', brandPressed: '#FFFFFF', onBrand: '#1C1C1E',
  bgPrimary: '#282828', bgCard: '#2E2E2E', bgSurface: '#333333',
  textPrimary: '#F2F2F2', textSecondary: '#B0B0B0', textTertiary: '#808080',
  divider: '#3A3A3A', activeBg: '#1FEDEDED', hoverBg: '#14EDEDED',
  success: '#63D471', warning: '#FFB340', danger: '#FF6961',
  sidebarBg: '#242424', listBg: '#282828', toolbarBg: '#282828', editorBg: '#282828'
}

export const THEMES: WeaverTheme[] = [
  { id: 'ink', name: '极简纸墨', dark: false, colors: INK },
  { id: 'warm', name: '温暖米纸', dark: false, colors: WARM },
  { id: 'green', name: '青笺', dark: false, colors: GREEN },
  { id: 'dark', name: '夜读', dark: true, colors: NIGHT }
]

export function themeById(id: string): WeaverTheme {
  const t: WeaverTheme | undefined = THEMES.find((x: WeaverTheme) => x.id === id)
  return t !== undefined ? t : THEMES[0]
}

/** 按主题 id 取语义色集（页面统一入口，依赖 @Trace themeId 保证响应式） */
export function tokensFor(themeId: string): WeaverColorSet {
  return themeById(themeId).colors
}

/** 兼容旧调用：dark ? 夜读 : 极简纸墨 */
export function tokens(dark: boolean): WeaverColorSet {
  return tokensFor(dark ? 'dark' : DEFAULT_THEME_ID)
}

function hexToRgb(hex: string): string[] {
  let h: string = hex.startsWith('#') ? hex.substring(1) : hex
  if (h.length === 8) {
    // 8 位 ARGB：取后 6 位
    h = h.substring(2)
  } else if (h.length === 3) {
    h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2)
  }
  if (h.length !== 6) {
    return ['00', '00', '00']
  }
  return [h.substring(0, 2), h.substring(2, 4), h.substring(4, 6)]
}

/**
 * 十六进制颜色混合：把 fg 按 ratio 向 bg 混合（0 = fg，1 = bg），返回 #RRGGBB。
 * 用于"非当前段落淡化"：不硬编码颜色，始终从当前主题的正文色/纸色推导，
 * 深浅主题都能得到可读的次级色。支持 #RGB / #RRGGBB / #AARRGGBB 输入。
 */
export function blendHexColor(fg: string, bg: string, ratio: number): string {
  const f: string[] = hexToRgb(fg)
  const b: string[] = hexToRgb(bg)
  const t: number = Math.max(0, Math.min(1, ratio))
  const mix = (a: number, c: number): string => {
    const v: number = Math.round(a * (1 - t) + c * t)
    const h: string = v.toString(16).toUpperCase()
    return h.length === 1 ? '0' + h : h
  }
  return '#' + mix(parseInt(f[0], 16), parseInt(b[0], 16)) +
    mix(parseInt(f[1], 16), parseInt(b[1], 16)) +
    mix(parseInt(f[2], 16), parseInt(b[2], 16))
}

// 字体层级（全局统一；编辑器正文除外，由稿纸字号决定）
export class TypeScale {
  static readonly DISPLAY: number = 24
  static readonly TITLE: number = 17
  static readonly HEADLINE: number = 16
  static readonly BODY: number = 15
  static readonly SUB: number = 13
  static readonly CAPTION: number = 12
  static readonly MICRO: number = 11
  static readonly LINE_DISPLAY: number = 32
  static readonly LINE_TITLE: number = 24
  static readonly LINE_BODY: number = 24
  static readonly LINE_SUB: number = 20
}

// 圆角规范（8vp 基准）
export class WeaverRadii {
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 20
  static readonly XXL: number = 32
}

// 间距/尺寸规范
export class WeaverSpacing {
  static readonly UNIT: number = 4
  static readonly XS: number = 4
  static readonly SM: number = 8
  static readonly MD: number = 12
  static readonly LG: number = 16
  static readonly XL: number = 24
  static readonly XXL: number = 32
  static readonly SIDEBAR_W: number = 240
  static readonly LIST_W: number = 300
  static readonly AGENT_W: number = 320
  static readonly TITLEBAR_H: number = 48
  static readonly TOOLBAR_H: number = 44
  static readonly TABBAR_H: number = 44
}

// 手机端（一多）布局规范
//
// 依据官方《响应式布局》《屏幕类型布局场景》《常见导航样式案例》：
//   - 底部页签栏参考高度 56vp（叠加底部系统避让区）
//   - 栅格基础 Margin 24vp / 卡片栅格 Margin 12vp
//   - 主要可点击热区推荐 48vp、最低 40vp
// 数值集中于此，避免散落在各组件里。
export class WeaverMobile {
  /** 手机端精简标题栏高度 */
  static readonly TITLEBAR_H: number = 56
  /** 手机端底部页签栏高度 */
  static readonly TABBAR_H: number = 56
  /** 手机端编辑器次级工具条高度 */
  static readonly TOOLBAR_H: number = 44
  /** 选中态指示条宽度 */
  static readonly INDICATOR_W: number = 20
  /** 页面基础左右边距（栅格基础 Margin 的手机取值） */
  static readonly PAGE_MARGIN: number = 16
  /** 栅格基础 Margin */
  static readonly GRID_MARGIN: number = 24
  /** 卡片栅格 Margin */
  static readonly CARD_MARGIN: number = 12
  /** 卡片圆角 */
  static readonly CARD_RADIUS: number = 16
  /** 推荐最小热区 */
  static readonly MIN_TOUCH: number = 48
  /** 必须满足的最小热区 */
  static readonly MIN_TOUCH_HARD: number = 40
}

// 手机端底部页签 / 内容分段的板块标识
// 注意：PROJECT 仅在窄屏（sm）底部页签出现；md 侧栏常驻项目，故分段页签不含 PROJECT。
export enum MobileTab {
  PROJECT = 0,
  DOCS = 1,
  MATERIALS = 2,
  GRAPH = 3
}

// 编辑器视图状态机
export enum EditorViewMode {
  EMPTY = 0,
  EDITOR = 1,
  MATERIAL = 2,
  GRAPH = 4
}

// 文稿库分类
export enum LibId {
  ALL = 'all',
  FAV = 'fav',
  INSP = 'insp',
  TRASH = 'trash'
}

// 关系图节点配色 —— 五个类别用五个可区分的色相（与品牌蓝同族），
// 深色下提高亮度，保证在黑底上也清晰。
export function graphNodeColor(type: CharacterType, dark: boolean): string {
  if (dark) {
    switch (type) {
      case CharacterType.PROTAGONIST: return '#4A9EFF' // 主角：亮蓝
      case CharacterType.SUPPORT: return '#7ED07A'     // 配角：亮绿
      case CharacterType.VILLAIN: return '#FF6B6B'     // 反派：亮红
      case CharacterType.ORG: return '#A99AE0'         // 组织：亮紫
      case CharacterType.PLACE: return '#FFB86B'       // 地点：亮橙
      default: return '#7ED07A'
    }
  }
  switch (type) {
    case CharacterType.PROTAGONIST: return '#007DFF'
    case CharacterType.SUPPORT: return '#64BB5C'
    case CharacterType.VILLAIN: return '#FA2A2D'
    case CharacterType.ORG: return '#8E7CC3'
    case CharacterType.PLACE: return '#FA9D3B'
    default: return '#64BB5C'
  }
}

// 关系图连线配色：正面=绿、负面=红、中立/间接=灰阶
export function graphEdgeColor(type: RelationshipType, dark: boolean): string {
  if (dark) {
    switch (type) {
      case RelationshipType.POSITIVE: return '#7ED07A'
      case RelationshipType.NEUTRAL: return '#99FFFFFF'
      case RelationshipType.NEGATIVE: return '#FF6B6B'
      case RelationshipType.INDIRECT: return '#66FFFFFF'
      default: return '#99FFFFFF'
    }
  }
  switch (type) {
    case RelationshipType.POSITIVE: return '#64BB5C'
    case RelationshipType.NEUTRAL: return '#8C8C8C'
    case RelationshipType.NEGATIVE: return '#FA2A2D'
    case RelationshipType.INDIRECT: return '#BFBFBF'
    default: return '#8C8C8C'
  }
}

// 连线是否虚线
export function graphEdgeDashed(type: RelationshipType): boolean {
  return type === RelationshipType.NEGATIVE || type === RelationshipType.INDIRECT
}

// 人物类型展示名
export function characterTypeName(type: CharacterType): string {
  switch (type) {
    case CharacterType.PROTAGONIST: return '主角'
    case CharacterType.SUPPORT: return '配角'
    case CharacterType.VILLAIN: return '反派'
    case CharacterType.ORG: return '组织/势力'
    case CharacterType.PLACE: return '地点'
    default: return '配角'
  }
}

// 关系类型展示名
export function relationshipTypeName(type: RelationshipType): string {
  switch (type) {
    case RelationshipType.POSITIVE: return '正面'
    case RelationshipType.NEUTRAL: return '中立'
    case RelationshipType.NEGATIVE: return '负面'
    case RelationshipType.INDIRECT: return '间接'
    default: return '中立'
  }
}

// 世界设定类别展示名
export function worldCategoryName(category: WorldCategory): string {
  switch (category) {
    case 'geography': return '地理'
    case 'politics': return '政治'
    case 'history': return '历史'
    case 'magic_tech': return '魔法科技'
    case 'race': return '种族'
    case 'culture': return '文化'
    default: return '其他'
  }
}

// 稿纸主题预设
//
// 注意 lineHeightRatio 是**倍数**（行高 ÷ 字号），不是绝对行高。
// 旧实现的 EditorZone 直接把它当绝对值传给 TextArea.lineHeight()，
// 于是 2.1 被当成 2.1vp —— 远小于字号，字形被行框裁掉，编辑区只剩一条缝。
// 使用处必须经 paperLineHeightVp() 换算。
export interface PaperTheme {
  id: string
  name: string
  backgroundColor: string
  textColor: string
  fontSize: number
  /** 行高倍数 */
  lineHeightRatio: number
}

export const PAPER_THEMES: PaperTheme[] = [
  { id: 'default', name: '素白', backgroundColor: '#FFFFFF', textColor: '#182431', fontSize: 18, lineHeightRatio: 1.9 },
  { id: 'green', name: '青笺', backgroundColor: '#EDF5EA', textColor: '#1A2818', fontSize: 18, lineHeightRatio: 1.9 },
  { id: 'sepia', name: '茶墨', backgroundColor: '#F5ECD8', textColor: '#3A2E1A', fontSize: 18, lineHeightRatio: 1.9 },
  { id: 'dark', name: '夜读', backgroundColor: '#1E1E1E', textColor: '#E8E8E8', fontSize: 18, lineHeightRatio: 1.9 }
]

/** 行高倍数 → TextArea 需要的绝对行高（vp） */
export function paperLineHeightVp(theme: PaperTheme): number {
  return Math.round(theme.fontSize * theme.lineHeightRatio)
}
