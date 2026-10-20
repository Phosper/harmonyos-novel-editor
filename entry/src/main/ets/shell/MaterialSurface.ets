// 沉浸光感材质面（Glass Surface）—— 可复用的 @Builder 与 AttributeModifier
//
// 为什么主要用 AttributeModifier，而不是 @Styles：
//   @Styles 只能写"与主题无关"的常量样式，拿不到 themeId，也无法在不支持的设备上降级；
//   AttributeModifier 能在同一处声明「实时模糊 + 渐变 + 1px 描边 + 阴影」，
//   并且实例按主题缓存，不会每帧 new（见下方 MODIFIER_CACHE）。
//
// 官方限制（见 constants/LightTokens.ets 文件头）：
//   自绘 chrome 不是系统标题栏，`.systemMaterial()` 在这些位置**不生效**，
//   因此这里统一用 backgroundBlurStyle + linearGradient + 1px 描边复刻沉浸光感；
//   真正的系统标题栏 / 半模态 options 请传 LightTokens.sheetMaterial() / chromeMaterial()。
import { uiMaterial } from '@kit.ArkUI'
import {
  WeaverGlassSpec,
  chromeGlass,
  cardGlass,
  panelGlass,
  veilGlass,
  sheenGlass,
  pageGlow,
  glowHalo,
  blurEnabled,
  chromeMaterial,
  themeSlot,
  GLOW_HALO_RADIUS,
  GLOW_HALO_HEIGHT
} from '../constants/LightTokens'

/** 1px 描边的位置（顶部 chrome 在下沿、底部页签在上沿、卡片四面） */
enum WeaverHairline {
  NONE = 0,
  BOTTOM = 1,
  TOP = 2,
  ALL = 3
}

/** 六种玻璃面形状（同时是缓存槽位下标） */
const SHAPE_BAR: number = 0
const SHAPE_TAB_BAR: number = 1
const SHAPE_CARD: number = 2
const SHAPE_PANEL: number = 3
const SHAPE_VEIL: number = 4
const SHAPE_SHEEN: number = 5

/**
 * 玻璃面属性修改器：模糊 / 渐变 / 描边 / 阴影 一次性写入。
 * 降级路径：`blurEnabled() === false`（不支持沉浸材质或低算力 SMOOTH）时**完全不调用**
 * backgroundBlurStyle，只画不透明渐变 + 1px 描边 —— 零实时模糊开销，对比度不变。
 */
export class WeaverGlassModifier implements AttributeModifier<CommonAttribute> {
  private spec: WeaverGlassSpec
  private hairline: WeaverHairline
  private radius: number

  constructor(spec: WeaverGlassSpec, hairline: WeaverHairline, radius: number) {
    this.spec = spec
    this.hairline = hairline
    this.radius = radius
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (this.spec.blurEnabled && blurEnabled()) {
      instance.backgroundBlurStyle(this.spec.blur, { colorMode: this.spec.colorMode })
      instance.linearGradient({ angle: 180, colors: this.spec.gradient })
    } else {
      // 降级：无实时模糊，用不透明渐变模拟同样的"上亮下暗"玻璃光感
      instance.linearGradient({ angle: 180, colors: this.spec.gradientSolid })
    }
    if (this.hairline === WeaverHairline.BOTTOM) {
      instance.border({ width: { bottom: 1 }, color: this.spec.borderColor })
    } else if (this.hairline === WeaverHairline.TOP) {
      instance.border({ width: { top: 1 }, color: this.spec.borderColor })
    } else if (this.hairline === WeaverHairline.ALL) {
      instance.border({ width: 1, color: this.spec.borderColor })
    }
    if (this.radius > 0) {
      instance.borderRadius(this.radius)
    }
    if (this.spec.shadowRadius > 0) {
      instance.shadow({
        radius: this.spec.shadowRadius,
        color: this.spec.shadowColor,
        offsetY: this.spec.shadowOffsetY
      })
    }
  }
}

// 4 主题 × 6 形状，首次使用时构造并缓存
const MODIFIER_CACHE: Array<Array<WeaverGlassModifier | null>> = [
  [null, null, null, null, null, null],
  [null, null, null, null, null, null],
  [null, null, null, null, null, null],
  [null, null, null, null, null, null]
]

function getModifier(themeId: string, shape: number): WeaverGlassModifier {
  const slot: number = themeSlot(themeId)
  const row: Array<WeaverGlassModifier | null> = MODIFIER_CACHE[slot]
  const cached: WeaverGlassModifier | null = row[shape]
  if (cached !== null) {
    return cached
  }
  let spec: WeaverGlassSpec = chromeGlass(themeId)
  let hairline: WeaverHairline = WeaverHairline.BOTTOM
  let radius: number = 0
  if (shape === SHAPE_TAB_BAR) {
    hairline = WeaverHairline.TOP
  } else if (shape === SHAPE_CARD) {
    spec = cardGlass(themeId)
    hairline = WeaverHairline.ALL
    // 与 WeaverRadii.LG 对齐（卡片圆角 16vp）
    radius = 16
  } else if (shape === SHAPE_PANEL) {
    spec = panelGlass(themeId)
    hairline = WeaverHairline.ALL
    // 与 WeaverRadii.XL 对齐（浮层圆角 20vp）
    radius = 20
  } else if (shape === SHAPE_VEIL) {
    spec = veilGlass(themeId)
  } else if (shape === SHAPE_SHEEN) {
    spec = sheenGlass(themeId)
    hairline = WeaverHairline.NONE
  }
  const built: WeaverGlassModifier = new WeaverGlassModifier(spec, hairline, radius)
  row[shape] = built
  return built
}

/** 顶部 chrome 玻璃条（下沿 1px 高光）：实时模糊层 ① */
export function glassBarStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_BAR)
}

/** 底部页签玻璃条（上沿 1px 高光）：实时模糊层 ② */
export function glassTabBarStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_TAB_BAR)
}

/** 卡片玻璃：零模糊（渐变 + 1px 描边 + 极轻阴影），用于列表容器/设置分组 */
export function glassCardStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_CARD)
}

/** 浮层玻璃（自绘弹窗 / 底部面板）：实时模糊 + 大圆角 + 深阴影 */
export function glassPanelStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_PANEL)
}

/** 薄纱（侧栏 / 分段页签）：零模糊，只叠一层淡淡渐变 + 下沿描边 */
export function glassVeilStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_VEIL)
}

/** 选中态薄纱（列表行）：零模糊、无描边，品牌色微光 */
export function glassSheenStyle(themeId: string): WeaverGlassModifier {
  return getModifier(themeId, SHAPE_SHEEN)
}

// ===================== 页面光感背景（供 AppShell / MobileShell / 引导页直接接线） =====================

/**
 * 页面光感背景：底层线性渐变（纸白 → 次级面）+ 顶部径向光晕。
 * 只有一个装饰层，`hitTestBehavior(None)` 不吃点击，`accessibilityLevel('no')` 不参与读屏。
 * 用法：放在页面根 Stack 的第一个子节点，其余内容容器背景置为透明。
 */
@Builder
export function GlowPageBackground(themeId: string) {
  Stack() {
    Column()
      .width('100%').height('100%')
      .linearGradient({ angle: 180, colors: pageGlow(themeId) })
    Column()
      .width('100%').height(GLOW_HALO_HEIGHT)
      .radialGradient({
        center: ['50%', 0],
        radius: GLOW_HALO_RADIUS,
        colors: glowHalo(themeId)
      })
  }
  .width('100%').height('100%')
  .alignContent(Alignment.Top)
  .hitTestBehavior(HitTestMode.None)
  .accessibilityLevel('no')
}

/**
 * 真·系统标题栏 / 半模态 options 的材质片段（唯一合法使用 systemMaterial 的地方）。
 * 直接把返回值塞进 options.systemMaterial 即可；不支持时返回 undefined，属性会回落。
 */
export function systemMaterialFor(themeId: string): uiMaterial.ImmersiveMaterial | undefined {
  return chromeMaterial(themeId)
}
