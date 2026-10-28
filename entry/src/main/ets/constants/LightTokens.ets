// Weaver 沉浸光感令牌（HarmonyOS 空间化视觉 / API 26.0.0）
//
// 官方能力与限制（见 docs/refactor/multidevice-interaction-refactor.md §0 / §4）：
//   1) `uiMaterial.isImmersiveMaterialSupported()` / `getGlobalMaterialLevel()` 由设备决定，运行期不变，
//      调用一次后模块内缓存；`getMaterialInfo().state === DISABLE` 时系统级材质被关闭。
//   2) `uiMaterial.ImmersiveMaterial` + `.systemMaterial()` 只对
//      Navigation/NavDestination 标题栏、横向 Tabs(barPosition=End) 底部 TabBar、
//      以及弹窗类（Dialog / Toast / Menu / Popup / Sheet / SelectionMenu …）**全页面**生效。
//      本工程的自绘 chrome（手机顶栏、列表头、侧栏、卡片）不是系统标题栏，
//      因此在那些位置统一用 `backgroundBlurStyle` + `linearGradient` + 1px 描边复刻同等观感，
//      只有在真正是系统标题栏 / 弹窗 options 的地方才传 systemMaterial（见 chromeMaterial / sheetMaterial）。
//   3) 降级：设备不支持沉浸材质 → OFF；支持但低算力(SMOOTH) → REDUCED。
//      两档都**关闭实时模糊**，只用（近）不透明渐变 + 1px 描边，正文对比度仍 ≥ 4.5:1。
//
// 性能预算：每屏实时模糊层 ≤ GLASS_MAX_BLUR_LAYERS（2 层：顶部 chrome + 底部/浮层）；
//          列表行、卡片、分段页签一律零模糊（薄纱 veil / 选中 sheen），避免过度绘制。
import { uiMaterial } from '@kit.ArkUI'
import { tokensFor, themeById, THEMES, WeaverColorSet, WeaverTheme } from './DesignTokens'

/** 玻璃档位：FULL 实时模糊 / REDUCED 低算力（关实时模糊）/ OFF 设备不支持沉浸材质 */
export enum WeaverGlassLevel {
  FULL = 0,
  REDUCED = 1,
  OFF = 2
}

/** 玻璃面种类：决定基调色、模糊档与实色兜底策略 */
export enum WeaverGlassKind {
  CHROME = 0,
  CARD = 1,
  PANEL = 2,
  VEIL = 3,
  SHEEN = 4
}

/** 全站玻璃动效时长（与既有规范一致：180ms / Curve.EaseOut） */
export const GLASS_ANIM_DURATION: number = 180
/** 每屏实时模糊层上限 */
export const GLASS_MAX_BLUR_LAYERS: number = 2

/**
 * 顶栏操作图标（以华为电子邮件标准电脑应用为准）。
 * 注意：这些只是布局尺寸，**不是玻璃材质** —— 顶栏按钮按 Email 做裸图标，
 * 没有底色/描边/阴影/实时模糊，圆只作为 hover/按下时的极淡反馈底。
 */
export const TOP_ICON_SIZE: number = 40
export const TOP_ICON_HIT_POINTER: number = 44
export const TOP_ICON_HIT_TOUCH: number = 48
export const TOP_ICON_FONT: number = 20
export const TOP_ICON_MARGIN: number = 4
/**
 * 状态底圆角：桌面应用用**方形/圆角矩形**（Email 的「更多」高亮就是 8vp 圆角矩形），
 * 圆形底是平板 App 的语言，电脑模式不使用。
 */
export const TOP_ICON_RADIUS: number = 8

/** 平板触摸档：更大的视觉圆与热区（44 / 56 / 24 / 6） */
export const TOP_ICON_SIZE_TOUCH: number = 44
export const TOP_ICON_HIT_TABLET: number = 56
export const TOP_ICON_FONT_TOUCH: number = 24
export const TOP_ICON_MARGIN_TOUCH: number = 6

/**
 * 顶栏图标的形态参数（由设备形态 + 输入形态决定，组件不自己拍数字）：
 *   · 桌面（PC / MatePad Edge 电脑模式）：40vp **方形**（8vp 圆角）、44/48 热区、20vp 图标；
 *   · 平板（触摸平板、非电脑模式）：44vp **圆形**、56 热区、24vp 图标。
 * 圆形底是平板 App 的语言，方形底是电脑 App 的语言 —— 两者不能混用。
 */
export class TopIconMetrics {
  visualSize: number = TOP_ICON_SIZE
  hitSize: number = TOP_ICON_HIT_POINTER
  iconSize: number = TOP_ICON_FONT
  gap: number = TOP_ICON_MARGIN
  circular: boolean = false
}

export function topIconMetrics(pointerPrimary: boolean, tabletMode: boolean,
  desktopMode: boolean): TopIconMetrics {
  const metrics: TopIconMetrics = new TopIconMetrics()
  if (tabletMode) {
    metrics.visualSize = TOP_ICON_SIZE_TOUCH
    metrics.hitSize = TOP_ICON_HIT_TABLET
    metrics.iconSize = TOP_ICON_FONT_TOUCH
    metrics.gap = TOP_ICON_MARGIN_TOUCH
    metrics.circular = true
    return metrics
  }
  // 电脑（PC / MatePad Edge 电脑模式）：不论鼠标还是触摸都保持方形底；
  // 非电脑（手机）仍用圆形，触摸热区 48。
  metrics.hitSize = pointerPrimary ? TOP_ICON_HIT_POINTER : TOP_ICON_HIT_TOUCH
  metrics.circular = !desktopMode
  return metrics
}

/**
 * 单块玻璃面的完整描述。
 * 用 class 而不是 interface：字段都有默认值，`new WeaverGlassSpec()` 后再赋值即可，
 * 避免每帧构造大对象字面量（ArkTS 也要求对象字面量有明确类型上下文）。
 */
export class WeaverGlassSpec {
  /** 沉浸材质样式（仅用于真正的系统标题栏 / 弹窗 options，自绘 chrome 上不生效） */
  style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR
  /** 实时模糊档（BlurStyle.COMPONENT_*）；BlurStyle.NONE 表示该面永不模糊 */
  blur: BlurStyle = BlurStyle.NONE
  /** FULL 档：半透明渐变（叠在实时模糊之上） */
  gradient: Array<[ResourceColor, number]> = []
  /** REDUCED / OFF 档：不透明渐变（零模糊，保证对比度） */
  gradientSolid: Array<[ResourceColor, number]> = []
  /** 1px 高光描边 / 分隔线颜色 */
  borderColor: string = '#1F000000'
  /** 材质层主色不透明度（渐变主 stop 的 alpha） */
  opacity: number = 0.9
  /** 模糊颜色模式：跟随本工程主题，而不是系统深浅 */
  colorMode: ThemeColorMode = ThemeColorMode.LIGHT
  /** 该面是否允许实时模糊（列表行 / 卡片 / 分段页签 = false） */
  blurEnabled: boolean = false
  /** 阴影（材质 elevation）；0 表示不加 */
  shadowColor: string = '#00000000'
  shadowRadius: number = 0
  shadowOffsetY: number = 0
}

// ===================== 颜色工具 =====================

const HEX_DIGITS: string = '0123456789ABCDEF'

function hex2(value: number): string {
  const v: number = Math.max(0, Math.min(255, Math.round(value)))
  return HEX_DIGITS.charAt(Math.floor(v / 16)) + HEX_DIGITS.charAt(v % 16)
}

/**
 * 6/8 位十六进制颜色 + 0~1 透明度 → 8 位 ARGB 字符串。
 * 统一在这里做 alpha 合成，避免在 4 个主题里手写 20 个 8 位色值（易错且难同步）。
 */
export function glassAlpha(rgb: string, alpha: number): string {
  const raw: string = rgb.charAt(0) === '#' ? rgb.substring(1) : rgb
  const base: string = raw.length > 6 ? raw.substring(raw.length - 6) : raw
  return '#' + hex2(Math.max(0, Math.min(1, alpha)) * 255) + base
}

/** 主题 id → 缓存槽位（0..3）；未知 id 回落到第一个主题 */
export function themeSlot(themeId: string): number {
  const index: number = THEMES.findIndex((t: WeaverTheme) => t.id === themeId)
  return index < 0 ? 0 : index
}

// ===================== 设备能力（模块内缓存一次） =====================

let supportedCached: boolean = false
let supportedReady: boolean = false

/** 设备是否支持沉浸式材质（缓存；设备能力运行期不变） */
export function immersiveSupported(): boolean {
  if (!supportedReady) {
    supportedReady = true
    try {
      supportedCached = uiMaterial.isImmersiveMaterialSupported()
    } catch (e) {
      supportedCached = false
    }
  }
  return supportedCached
}

let levelCached: uiMaterial.MaterialLevel = uiMaterial.MaterialLevel.SMOOTH
let levelReady: boolean = false

/** 设备材质档位：EXQUISITE / GENTLE / SMOOTH（缓存） */
export function materialLevel(): uiMaterial.MaterialLevel {
  if (!levelReady) {
    levelReady = true
    try {
      levelCached = uiMaterial.getGlobalMaterialLevel()
    } catch (e) {
      levelCached = uiMaterial.MaterialLevel.SMOOTH
    }
  }
  return levelCached
}

let stateReady: boolean = false
let stateEnabled: boolean = true

/** 应用级材质是否被系统/配置禁用（module.json5 metadata = disable 时为 false） */
export function materialAvailable(): boolean {
  if (!stateReady) {
    stateReady = true
    try {
      stateEnabled = uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE
    } catch (e) {
      stateEnabled = true
    }
  }
  return immersiveSupported() && stateEnabled
}

/**
 * 玻璃降级档位。
 * themeId 参数按 §4 契约保留：算力档位由设备决定，与主题无关（保留以便后续按主题微调）。
 */
export function glassLevel(themeId: string): WeaverGlassLevel {
  if (!immersiveSupported()) {
    return WeaverGlassLevel.OFF
  }
  if (materialLevel() === uiMaterial.MaterialLevel.SMOOTH) {
    return WeaverGlassLevel.REDUCED
  }
  return WeaverGlassLevel.FULL
}

/** 当前设备是否允许实时模糊（只有 FULL 档允许；REDUCED/OFF 一律零模糊） */
export function blurEnabled(): boolean {
  return materialAvailable() && materialLevel() !== uiMaterial.MaterialLevel.SMOOTH
}

// ===================== 沉浸材质对象（按档位缓存，不每帧 new） =====================

function styleIndex(style: uiMaterial.ImmersiveStyle): number {
  let index: number = 2
  if (style === uiMaterial.ImmersiveStyle.ULTRA_THIN) {
    index = 0
  } else if (style === uiMaterial.ImmersiveStyle.THIN) {
    index = 1
  } else if (style === uiMaterial.ImmersiveStyle.REGULAR) {
    index = 2
  } else if (style === uiMaterial.ImmersiveStyle.THICK) {
    index = 3
  } else if (style === uiMaterial.ImmersiveStyle.ULTRA_THICK) {
    index = 4
  }
  return index
}

/** 5 档样式 × 2 种 interactivity */
const MATERIAL_CACHE: Array<uiMaterial.ImmersiveMaterial | null> =
  [null, null, null, null, null, null, null, null, null, null]

/**
 * 取（并缓存）一个沉浸材质对象。
 * 设备不支持 / 材质被禁用时返回 undefined（调用方据此回落到自绘玻璃）。
 */
export function immersiveMaterial(style: uiMaterial.ImmersiveStyle,
  interactive: boolean): uiMaterial.ImmersiveMaterial | undefined {
  if (!materialAvailable()) {
    return undefined
  }
  const key: number = styleIndex(style) * 2 + (interactive ? 1 : 0)
  const cached: uiMaterial.ImmersiveMaterial | null = MATERIAL_CACHE[key]
  if (cached !== null) {
    return cached
  }
  const options: uiMaterial.ImmersiveOptions = { style: style }
  if (interactive) {
    options.interactive = true
    // 启用默认光感交互反馈（color 不指定 = 用系统默认白色光感，官方示例写法）
    options.lightEffect = { color: undefined }
  }
  const made: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial(options)
  MATERIAL_CACHE[key] = made
  return made
}

/** 半模态 / 弹窗 options 用：较厚的材质，不做交互形变 */
export function sheetMaterial(): uiMaterial.ImmersiveMaterial | undefined {
  return immersiveMaterial(uiMaterial.ImmersiveStyle.THICK, false)
}

/** 真·系统标题栏 / 对话框 options 用：薄材质 + 交互光感（浅色更薄，深色略厚） */
export function chromeMaterial(themeId: string): uiMaterial.ImmersiveMaterial | undefined {
  const dark: boolean = themeById(themeId).dark
  return immersiveMaterial(dark ? uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.ULTRA_THIN, true)
}

// ===================== 四主题光感色板 =====================

/**
 * 每个主题一对（RGB, 顶部光晕透明度）。
 * 光晕色取自既有配色族（米纸暖光 C48A5B / 青笺冷光 4EA8A0，见 DesignTokens.PROJECT_COLORS），
 * 深色主题用冷光提亮，浅色主题用极淡微光——保证正文对比度不变。
 */
/** 全透明渐变：给"选中/未选中"这类三元表达式当另一分支用，避免用 if 包住整个组件 */
export const GLASS_NONE_GRADIENT: Array<[ResourceColor, number]> = [
  ['#00000000', 0.0],
  ['#00000000', 1.0]
]

const HALO_RGB: string[] = ['#8E8E93', '#C48A5B', '#4EA8A0', '#5B8DEF']
const HALO_ALPHA: number[] = [0.06, 0.11, 0.10, 0.14]

const SPEC_CACHE: Array<Array<WeaverGlassSpec | null>> = [
  [null, null, null, null, null],
  [null, null, null, null, null],
  [null, null, null, null, null],
  [null, null, null, null, null]
]
const PAGE_GLOW_CACHE: Array<Array<[ResourceColor, number]> | null> = [null, null, null, null]
const HALO_CACHE: Array<Array<[ResourceColor, number]> | null> = [null, null, null, null]

function makeSpec(themeId: string, kind: WeaverGlassKind): WeaverGlassSpec {
  const colors: WeaverColorSet = tokensFor(themeId)
  const dark: boolean = themeById(themeId).dark
  const spec: WeaverGlassSpec = new WeaverGlassSpec()
  spec.colorMode = dark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT

  // 各面的基调色 + 不透明度（浅色主题透明度略高，深色主题略低以免整块发灰）
  let tintTop: string = colors.bgCard
  let tintBottom: string = colors.bgSurface
  let opacity: number = dark ? 0.84 : 0.90
  if (kind === WeaverGlassKind.CARD) {
    opacity = dark ? 0.90 : 0.88
  } else if (kind === WeaverGlassKind.PANEL) {
    opacity = dark ? 0.94 : 0.96
  } else if (kind === WeaverGlassKind.VEIL) {
    tintTop = colors.bgSurface
    tintBottom = colors.bgCard
    opacity = dark ? 0.62 : 0.72
  } else if (kind === WeaverGlassKind.SHEEN) {
    // 选中态：品牌色薄纱（深浅主题各自取品牌色，ink 是近黑、dark 是近白，观感都成立）
    tintTop = colors.brand
    tintBottom = colors.brand
    opacity = dark ? 0.16 : 0.09
  }
  spec.opacity = opacity

  // 实时模糊档：只有 chrome / panel 允许；card / veil / sheen 一律零模糊
  if (kind === WeaverGlassKind.CHROME) {
    spec.blurEnabled = true
    spec.blur = dark ? BlurStyle.COMPONENT_THICK : BlurStyle.COMPONENT_REGULAR
    spec.style = uiMaterial.ImmersiveStyle.THIN
  } else if (kind === WeaverGlassKind.PANEL) {
    spec.blurEnabled = true
    spec.blur = BlurStyle.COMPONENT_THICK
    spec.style = uiMaterial.ImmersiveStyle.THICK
  } else if (kind === WeaverGlassKind.CARD) {
    spec.style = uiMaterial.ImmersiveStyle.REGULAR
  } else {
    spec.style = uiMaterial.ImmersiveStyle.ULTRA_THIN
  }

  // 渐变：FULL 用半透明 stop（叠模糊）；降级用不透明 stop（无模糊也够厚）
  const midAlpha: number = Math.max(0, opacity - 0.05)
  spec.gradient = [
    [glassAlpha(tintTop, opacity), 0.0],
    [glassAlpha(tintBottom, midAlpha), 0.55],
    [glassAlpha(tintBottom, opacity), 1.0]
  ]
  // chrome / card / panel 是"承托正文的表面"，降级时必须完全不透明以保证对比度；
  // veil / sheen 是"叠加在内容上的薄层"，降级时保持原透明度。
  const opaqueFallback: boolean = kind === WeaverGlassKind.CHROME || kind === WeaverGlassKind.CARD ||
    kind === WeaverGlassKind.PANEL
  const solidAlpha: number = opaqueFallback ? 1 : opacity
  spec.gradientSolid = [
    [glassAlpha(tintTop, solidAlpha), 0.0],
    [glassAlpha(tintBottom, solidAlpha), 1.0]
  ]

  // 1px 高光描边 / 分隔线：浅色用既有 divider（浅灰），深色同样是浅灰 → 形成玻璃边缘高光
  spec.borderColor = kind === WeaverGlassKind.SHEEN
    ? glassAlpha(colors.brand, dark ? 0.34 : 0.18)
    : colors.divider

  // 阴影：只有 chrome / panel 有（卡片与行靠描边区分，避免列表里出现大片灰影）
  if (kind === WeaverGlassKind.CHROME) {
    spec.shadowColor = dark ? '#4D000000' : '#0F000000'
    spec.shadowRadius = dark ? 10 : 8
    spec.shadowOffsetY = 2
  } else if (kind === WeaverGlassKind.PANEL) {
    spec.shadowColor = dark ? '#66000000' : '#1A000000'
    spec.shadowRadius = dark ? 24 : 20
    spec.shadowOffsetY = 8
  } else if (kind === WeaverGlassKind.CARD) {
    spec.shadowColor = dark ? '#33000000' : '#0A000000'
    spec.shadowRadius = 6
    spec.shadowOffsetY = 2
  }
  return spec
}

/** 按主题 + 种类取玻璃描述（模块内缓存，避免每帧构造） */
export function glassSpec(themeId: string, kind: WeaverGlassKind): WeaverGlassSpec {
  const slot: number = themeSlot(themeId)
  const row: Array<WeaverGlassSpec | null> = SPEC_CACHE[slot]
  const cached: WeaverGlassSpec | null = row[kind]
  if (cached !== null) {
    return cached
  }
  const built: WeaverGlassSpec = makeSpec(themeId, kind)
  row[kind] = built
  return built
}

/** chrome 玻璃条（顶栏 / 底栏）：实时模糊 + 渐变 + 1px 描边 + 轻阴影 */
export function chromeGlass(themeId: string): WeaverGlassSpec {
  return glassSpec(themeId, WeaverGlassKind.CHROME)
}

/** 卡片玻璃：零实时模糊，渐变 + 1px 描边 + 极轻阴影 */
export function cardGlass(themeId: string): WeaverGlassSpec {
  return glassSpec(themeId, WeaverGlassKind.CARD)
}

/** 浮层玻璃（自绘弹窗/面板）：实时模糊 + 更厚渐变 + 大圆角阴影 */
export function panelGlass(themeId: string): WeaverGlassSpec {
  return glassSpec(themeId, WeaverGlassKind.PANEL)
}

/** 薄纱（侧栏 / 分段页签等次级面）：零模糊，只做淡淡的一层渐变 */
export function veilGlass(themeId: string): WeaverGlassSpec {
  return glassSpec(themeId, WeaverGlassKind.VEIL)
}

/** 选中态薄纱：品牌色微光，替代原来的纯色 activeBg */
export function sheenGlass(themeId: string): WeaverGlassSpec {
  return glassSpec(themeId, WeaverGlassKind.SHEEN)
}

/** 页面底色渐变（顶层一层，铺满页面；不吃点击） */
export function pageGlow(themeId: string): Array<[ResourceColor, number]> {
  const slot: number = themeSlot(themeId)
  const cached: Array<[ResourceColor, number]> | null = PAGE_GLOW_CACHE[slot]
  if (cached !== null) {
    return cached
  }
  const colors: WeaverColorSet = tokensFor(themeId)
  const dark: boolean = themeById(themeId).dark
  let built: Array<[ResourceColor, number]> = []
  if (dark) {
    // 深色：顶部略亮（受光），向下回到页底
    built = [
      [glassAlpha(colors.bgSurface, 1), 0.0],
      [glassAlpha(colors.bgPrimary, 1), 1.0]
    ]
  } else {
    // 浅色：顶部纸白，向下过渡到次级面（8%~10% 的明度差，够看出"光从上面来"）
    built = [
      [glassAlpha(colors.bgPrimary, 1), 0.0],
      [glassAlpha(colors.bgSurface, 1), 1.0]
    ]
  }
  PAGE_GLOW_CACHE[slot] = built
  return built
}

/** 顶部光晕（径向，渐隐到全透明；每主题一条光色） */
export function glowHalo(themeId: string): Array<[ResourceColor, number]> {
  const slot: number = themeSlot(themeId)
  const cached: Array<[ResourceColor, number]> | null = HALO_CACHE[slot]
  if (cached !== null) {
    return cached
  }
  const rgb: string = HALO_RGB[slot]
  const alpha: number = HALO_ALPHA[slot]
  const built: Array<[ResourceColor, number]> = [
    [glassAlpha(rgb, alpha), 0.0],
    [glassAlpha(rgb, 0), 1.0]
  ]
  HALO_CACHE[slot] = built
  return built
}

/** 顶部光晕半径（vp）；固定值避免百分比在 radialGradient 上的兼容差异 */
export const GLOW_HALO_RADIUS: number = 420
/** 顶部光晕层占页面高度的比例 */
export const GLOW_HALO_HEIGHT: string = '46%'
