// 思路板 · 视觉与共享视图类型（B 工作流私有，不属于数据层）
//
// 设计约束（docs/design/canvas-contract.md §5）：
// - 只用 DesignTokens 的 tokensFor(themeId) 取色；本文件是唯一取色点，禁止在组件里写 hex。
// - 尺寸只用 constants/CanvasSpec + 本文件的 CanvasLayout（卡片内边距/脊线宽度等排版常量）。
// - 共享视图类型统一放这里，避免 TopicCard 与 CanvasPane 循环导入。
//   契约里 CanvasPane/TopicCard/CanvasEdges/EvidenceDrawer 四个组件名由契约冻结，
//   其余新增类型一律 Canvas 前缀。
import { tokensFor, blendHexColor, WeaverColorSet, TypeScale } from '../constants/DesignTokens'
import { CanvasSpec } from '../constants/CanvasSpec'
import {
  CanvasLinkKind, CanvasEvidenceKind, CanvasCardKind, CanvasCardData, CanvasPlacementData
} from '../model/CanvasTypes'

/** 画布语义色：全部由当前主题色派生，不出现裸 hex */
export interface CanvasPalette {
  /** 画布纸色 */
  paper: string
  /** 卡片底 */
  cardBg: string
  /** 卡片描边（常态 / 悬停选中） */
  cardBorder: string
  cardBorderActive: string
  /** C 型脊线 */
  ridge: string
  /** 正文三级 */
  textPrimary: string
  textSecondary: string
  textTertiary: string
  divider: string
  hoverBg: string
  activeBg: string
  /** 张嘴 / 编号强调色（主题 warning） */
  accent: string
  accentSoft: string
  accentLine: string
  /** 危险动作 */
  danger: string
  /** 品牌色上的文字 */
  onBrand: string
  /** 点阵背景点色 */
  dot: string
  /** 次级按钮底 */
  chipBg: string
  /** 素材三类 chip */
  quoteText: string
  quoteBg: string
  quoteLine: string
  judgeText: string
  judgeBg: string
  judgeLine: string
  noteText: string
  noteBg: string
  noteLine: string
}

/**
 * 主题 id → 画布语义色。
 * 混合比例：*Bg 用 0.88（基本是卡片色，只带一点色相），*Line 用 0.45~0.55（可辨认的描边）。
 */
export function canvasPalette(themeId: string): CanvasPalette {
  const t: WeaverColorSet = tokensFor(themeId)
  const palette: CanvasPalette = {
    paper: t.bgPrimary,
    cardBg: t.bgCard,
    cardBorder: t.divider,
    cardBorderActive: t.brand,
    ridge: t.brand,
    textPrimary: t.textPrimary,
    textSecondary: t.textSecondary,
    textTertiary: t.textTertiary,
    divider: t.divider,
    hoverBg: t.hoverBg,
    activeBg: t.activeBg,
    accent: t.warning,
    accentSoft: blendHexColor(t.warning, t.bgCard, 0.88),
    accentLine: blendHexColor(t.warning, t.bgCard, 0.45),
    danger: t.danger,
    onBrand: t.onBrand,
    dot: blendHexColor(t.textTertiary, t.bgPrimary, 0.55),
    chipBg: t.bgSurface,
    quoteText: t.success,
    quoteBg: blendHexColor(t.success, t.bgCard, 0.9),
    quoteLine: blendHexColor(t.success, t.bgCard, 0.55),
    judgeText: t.warning,
    judgeBg: blendHexColor(t.warning, t.bgCard, 0.9),
    judgeLine: blendHexColor(t.warning, t.bgCard, 0.55),
    noteText: t.textSecondary,
    noteBg: blendHexColor(t.brand, t.bgCard, 0.92),
    noteLine: blendHexColor(t.brand, t.bgCard, 0.72)
  }
  return palette
}

/**
 * 卡片内部排版常量（与 TopicCard 的 build 一一对应）。
 * 这些是"卡片内部"的 vp，在 zoom 之后才参与屏幕布局；
 * CanvasPane 用它把测量到的 bodyTop 换算成世界坐标行矩形。
 */
export class CanvasLayout {
  /** 卡片内容内边距 */
  static readonly CARD_PAD: number = 12
  /** C 型脊线宽度（3vp 实线） */
  static readonly RIDGE_WIDTH: number = 3
  /** 子卡区自身左内边距（脊线之后到行内容） */
  static readonly BODY_LEFT: number = 15
  /** 行内容相对卡片左缘的总缩进 = 卡片内边距 + 脊线 + 子卡区左内边距（深度 1 时） */
  static readonly BODY_CONTENT_LEFT: number = 30
  /** 子卡区顶部内边距（与 TopicCard 的 ridgeBody padding.top 对应） */
  static readonly ROW_GAP_TOP: number = 2
  /** 行内左右内边距 */
  static readonly ROW_PAD_X: number = 8
  /** 编号列宽 */
  static readonly NUM_W: number = 30
  /** 圆角（随 zoom 缩放，基准值） */
  static readonly CARD_RADIUS: number = 12
  /** 拖动手势的启动距离（vp） */
  static readonly DRAG_DISTANCE: number = 5
  /** 行尾动作按钮尺寸 */
  static readonly ROW_ACTION_W: number = 18
  /** 未测量到卡片高度时的兜底高度（世界坐标），只影响首帧命中 */
  static readonly FALLBACK_CARD_H: number = 96
  /** 抽屉内边距 */
  static readonly DRAWER_PAD: number = 16
  /** 连线每段控制点的弯曲量上限 */
  static readonly EDGE_BOW_MAX: number = 54
}

/** 一行子卡（扁平化后的渲染单元；顺序与自动编号由 CanvasTypes.canvasFlatten 给出） */
export interface CanvasRowView {
  cardId: string
  placementId: string
  /** 1 = 章，2 = 节，3 = 目 */
  depth: number
  /** 同级序号（0 起） */
  index: number
  /** 自动编号文本，如「一、」「（一）」「1.」 */
  numbering: string
  title: string
  isWriting: boolean
  /** 素材条数 */
  materialCount: number
  /** 是否还有下一层子卡 */
  hasChildren: boolean
}

/** 顶层卡的渲染视图（卡存在才生成；避免把 undefined 传给 @Require @Param） */
export interface CanvasCardView {
  card: CanvasCardData
  placement: CanvasPlacementData
  rows: CanvasRowView[]
  materialCount: number
}

/** 拖拽种类：整张卡（顶层卡）/ 子卡行 */
export enum CanvasDragKind {
  CARD = 0,
  ROW = 1
}

/**
 * 命中结果：把卡 / 行统一成"挂到哪张卡下"。
 * cardId 是目标卡；rowCardId 非空表示命中的是那一行（决定缺口插在哪一行之后）。
 */
export interface CanvasHitResult {
  cardId: string
  rowCardId: string
  /** 最终父卡下的兄弟位置（attachCardAt 用） */
  insertIndex: number
  /** 缺口在展开行里的位置（mouthInsert 用；与 insertIndex 可能不同） */
  previewIndex: number
  /** 缺口缩进层级（1..3） */
  depth: number
  isRow: boolean
}

/** 一条连线的绘制数据（屏幕坐标，vp） */
export interface CanvasEdgeLine {
  linkId: string
  /** Path.commands 字符串（屏幕坐标） */
  commands: string
  label: string
  labelX: number
  labelY: number
  labelWidth: number
  /** 弱连接用虚线（当前 kind 全部实线，保留字段给后续） */
  dashed: boolean
}

/** 矩形（世界坐标；命中与连线都在世界坐标里算，最后再乘 zoom + pan） */
export interface CanvasRect {
  x: number
  y: number
  w: number
  h: number
}

/** 卡片测量结果（世界坐标）：高度 + 子卡区起点，用于行矩形与连线端点 */
export interface CanvasCardGeometry {
  cardId: string
  worldHeight: number
  bodyTop: number
}

/** 连线类型 → 中文标签（label 为空时的兜底） */
export function canvasLinkLabel(kind: CanvasLinkKind): string {
  if (kind === CanvasLinkKind.PREMISE) {
    return '前提'
  }
  if (kind === CanvasLinkKind.CAUSE) {
    return '因果'
  }
  if (kind === CanvasLinkKind.CONTRAST) {
    return '对比'
  }
  if (kind === CanvasLinkKind.EXAMPLE) {
    return '例证'
  }
  if (kind === CanvasLinkKind.SEQUENCE) {
    return '递进'
  }
  return '相关'
}

/** 素材类型 → 中文标签 */
export function canvasEvidenceLabel(kind: CanvasEvidenceKind): string {
  if (kind === CanvasEvidenceKind.QUOTE) {
    return '引文'
  }
  if (kind === CanvasEvidenceKind.JUDGEMENT) {
    return '判断'
  }
  return '笔记'
}

/** 层级文案（抽屉顶部与无障碍播报共用） */
export function canvasDepthLabel(depth: number): string {
  if (depth <= 0) {
    return '顶层卡片'
  }
  if (depth === 1) {
    return '第 1 层（章）'
  }
  if (depth === 2) {
    return '第 2 层（节）'
  }
  return '第 3 层（目）'
}

/** 卡片标题字号（随 zoom 缩放；写作卡略大，与原型一致） */
export function canvasTitleSize(kind: CanvasCardKind, zoom: number): number {
  const base: number = kind === CanvasCardKind.WRITING ? 16 : 15.5
  return base * zoom
}

/** 卡片元信息字号 */
export function canvasMetaSize(zoom: number): number {
  return TypeScale.MICRO * zoom
}

/** 卡片宽度（世界坐标，不含 zoom） */
export function canvasCardWidth(kind: CanvasCardKind): number {
  return kind === CanvasCardKind.WRITING ? CanvasSpec.WRITING_WIDTH : CanvasSpec.CARD_WIDTH
}
