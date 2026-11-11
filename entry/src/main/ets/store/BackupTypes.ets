// JSON 备份载荷类型
// 分为「导出用（字段必填）」与「导入用（字段可缺，逐项校验）」两套：
// 备份文件可能来自更早的版本，用必填类型直接反序列化会在运行时踩空。
import type { BookMode } from '../model/Book'
import type { ChapterModel } from '../model/Chapter'
import type { CharacterModel } from '../model/Character'
import type { WorldSettingModel } from '../model/WorldSetting'
import type { InspirationModel } from '../model/Inspiration'
import type { RelationshipModel } from '../model/Relationship'
import type {
  CanvasBoardData, CanvasCardData, CanvasEvidenceData, CanvasLinkData, CanvasPlacementData
} from '../model/CanvasTypes'
import type { MapSummaryBackupRow, MapRelationBackupRow, MapNodeStyleBackupRow } from '../repository/MapExtraRepository'

export interface BookBackupSnapshot {
  id: string
  name: string
  mode: BookMode
}

export interface BackupPayload {
  app: string
  version: number
  exportedAt: number
  book: BookBackupSnapshot | null
  chapters: ChapterModel[]
  characters: CharacterModel[]
  worldSettings: WorldSettingModel[]
  inspirations: InspirationModel[]
  relationships: RelationshipModel[]
  /**
   * v2 新增：思路板五表（topics / topic_evidence / canvases / canvas_placements / canvas_links）。
   * 都是可选的 —— 旧版本备份没有这几项，导入时按空数组处理。
   */
  topics?: CanvasCardData[]
  topicEvidence?: CanvasEvidenceData[]
  canvases?: CanvasBoardData[]
  canvasPlacements?: CanvasPlacementData[]
  canvasLinks?: CanvasLinkData[]
  /** M5 新增：导图附加信息（概要与关系线），按章节归属，恢复时随章节重映射 */
  mapSummaries?: MapSummaryBackupRow[]
  mapRelations?: MapRelationBackupRow[]
  /** M6 新增：节点级样式（形状/填充/加粗/标记/标签） */
  mapNodeStyles?: MapNodeStyleBackupRow[]
}

/** 导入侧宽松视图：允许字段缺失，由导入逻辑逐项兜底 */
export interface BackupPayloadLoose {
  app?: string
  version?: number
  exportedAt?: number
  book?: BookBackupSnapshot | null
  chapters?: ChapterModel[]
  characters?: CharacterModel[]
  worldSettings?: WorldSettingModel[]
  inspirations?: InspirationModel[]
  relationships?: RelationshipModel[]
  topics?: CanvasCardData[]
  topicEvidence?: CanvasEvidenceData[]
  canvases?: CanvasBoardData[]
  canvasPlacements?: CanvasPlacementData[]
  canvasLinks?: CanvasLinkData[]
  mapSummaries?: MapSummaryBackupRow[]
  mapRelations?: MapRelationBackupRow[]
  mapNodeStyles?: MapNodeStyleBackupRow[]
}
