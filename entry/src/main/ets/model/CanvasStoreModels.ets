// 思路板：Store / DAO / 备份共用的模型（状态管理 V2 可观察类 + 备份载荷）
//
// 为什么用 @ObservedV2 类而不是纯 interface：
// 画布上的贴放要就地改坐标/折叠态（拖拽每帧都在改），V2 的 @Trace 让「数组里的某一个
// 元素属性变了」也能刷新对应卡片；纯 interface 只能整体替换数组，等于每帧重建整块画布。
//
// 四个 Item 类 implements 冻结文件 model/CanvasTypes.ets 里的同名 Data 接口，
// 字段逐一对应，因此可以直接传给 canvasChildren/canvasFlatten/canvasCanNest 等纯规则。
import { CanvasBoardScope, CanvasCardKind, CanvasEvidenceKind, CanvasLinkKind } from './CanvasTypes'
import type {
  CanvasBoardData, CanvasCardData, CanvasEvidenceData, CanvasLinkData, CanvasPlacementData
} from './CanvasTypes'

/** 白板（canvases 表的一行） */
@ObservedV2
export class CanvasBoardItem implements CanvasBoardData {
  @Trace id: string = ''
  @Trace scope: CanvasBoardScope = CanvasBoardScope.COURSE
  @Trace bookId: string = ''
  @Trace title: string = ''
  @Trace panX: number = 0
  @Trace panY: number = 0
  @Trace zoom: number = 1
  @Trace sortOrder: number = 0
  @Trace createdAt: number = 0
  @Trace updatedAt: number = 0
}

/** 卡片 / 主题（topics 表的一行） */
@ObservedV2
export class CanvasCardItem implements CanvasCardData {
  @Trace id: string = ''
  @Trace bookId: string = ''
  @Trace kind: CanvasCardKind = CanvasCardKind.CONCEPT
  @Trace title: string = ''
  @Trace aliases: string = ''
  @Trace tags: string = ''
  @Trace summary: string = ''
  @Trace docId: string = ''
  @Trace createdAt: number = 0
  @Trace updatedAt: number = 0
}

/** 贴放（canvas_placements 表的一行）：父子关系挂在这里，不挂卡片 */
@ObservedV2
export class CanvasPlacementItem implements CanvasPlacementData {
  @Trace id: string = ''
  @Trace canvasId: string = ''
  @Trace cardId: string = ''
  @Trace parentId: string = ''
  @Trace order: number = 0
  @Trace x: number = 0
  @Trace y: number = 0
  @Trace z: number = 0
  @Trace collapsed: boolean = false
  @Trace style: string = ''
}

/** 连线（canvas_links 表的一行） */
@ObservedV2
export class CanvasLinkItem implements CanvasLinkData {
  @Trace id: string = ''
  @Trace canvasId: string = ''
  @Trace fromCardId: string = ''
  @Trace toCardId: string = ''
  @Trace kind: CanvasLinkKind = CanvasLinkKind.RELATE
  @Trace label: string = ''
  @Trace createdAt: number = 0
}

/** 素材（topic_evidence 表的一行） */
@ObservedV2
export class CanvasEvidenceItem implements CanvasEvidenceData {
  @Trace id: string = ''
  @Trace cardId: string = ''
  @Trace kind: CanvasEvidenceKind = CanvasEvidenceKind.NOTE
  @Trace docId: string = ''
  @Trace paraIndex: number = 0
  @Trace startOff: number = 0
  @Trace endOff: number = 0
  @Trace fingerprint: string = ''
  @Trace quoteText: string = ''
  @Trace userText: string = ''
  @Trace sourceLabel: string = ''
  @Trace createdAt: number = 0
}

/** 新建素材的输入（契约 §2） */
export interface CanvasEvidenceInput {
  docId: string
  paraIndex: number
  startOff: number
  endOff: number
  fingerprint: string
  quoteText: string
  userText: string
  sourceLabel: string
}

/** 卡片元信息更新的补丁（未传的字段不动） */
export interface CanvasCardPatch {
  title?: string
  aliases?: string
  tags?: string
  summary?: string
}

/** 备份载荷里的思路板部分（导出用，字段必填） */
export interface CanvasBackupBundle {
  topics: CanvasCardData[]
  topicEvidence: CanvasEvidenceData[]
  canvases: CanvasBoardData[]
  canvasPlacements: CanvasPlacementData[]
  canvasLinks: CanvasLinkData[]
}

/** 备份载荷里的思路板部分（导入用，字段可缺：旧备份没有这 5 项） */
export interface CanvasBackupLooseBundle {
  topics?: CanvasCardData[]
  topicEvidence?: CanvasEvidenceData[]
  canvases?: CanvasBoardData[]
  canvasPlacements?: CanvasPlacementData[]
  canvasLinks?: CanvasLinkData[]
}

/**
 * 生成 count 个 SQL 绑定占位符（"?,?,?"），配合 `WHERE x IN (...)` 的参数化查询。
 * 值一律走 bindArgs，不拼字符串；count <= 0 返回空串（调用方先判空，避免拼出 IN ()）。
 */
export function canvasSqlPlaceholders(count: number): string {
  let out: string = ''
  for (let i: number = 0; i < count; i++) {
    out += i === 0 ? '?' : ',?'
  }
  return out
}
