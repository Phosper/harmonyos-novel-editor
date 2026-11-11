// 契约包唯一出口：只导出类型与纯规则。
// 任何"能改状态"的东西都不许从这里出去（ADR-003 §2.2）。
export {
  FeatureId,
  SurfaceKind,
  FeatureError,
  FeatureDescriptor,
  OpenIntent,
  SubscriptionLease,
  isIntentStale,
  surfaceAllowed
} from './src/main/ets/contracts/FeatureContracts'
export type { SubscriptionLease as SubscriptionLeaseType } from './src/main/ets/contracts/FeatureContracts'
// 只读大纲/导图：节点、快照、纯布局
export {
  OutlineNode,
  OutlineSnapshot,
  PlacedNode,
  MindMapLayout,
  OUTLINE_NODE_W,
  OUTLINE_NODE_H,
  OUTLINE_COL_GAP,
  OUTLINE_ROW_GAP,
  OUTLINE_PAD,
  OUTLINE_LAYOUT_RIGHT,
  OUTLINE_LAYOUT_BALANCED,
  OUTLINE_LAYOUT_DOWN,
  OUTLINE_LAYOUT_TABLE,
  OUTLINE_AXIS_X,
  OUTLINE_AXIS_Y,
  OUTLINE_SIB_GAP,
  OUTLINE_LEVEL_GAP,
  OUTLINE_TABLE_COL_W,
  OUTLINE_TABLE_ROW_STEP,
  buildOutline,
  buildOutlineFromParagraphs,
  layoutOutline,
  outlineParents,
  OutlineConnector,
  outlineConnectors,
  OutlineWire,
  OUTLINE_WIRE_PAD,
  OUTLINE_WIRE_STEPS,
  OUTLINE_WIRE_CURVE,
  OUTLINE_WIRE_ELBOW,
  outlineWires
} from './src/main/ets/contracts/OutlineLayout'
export type { OutlineHeading, OutlineParagraph } from './src/main/ets/contracts/OutlineLayout'
// 导图 → 正文的结构命令
export { OutlineCommand, OutlineCommandKind } from './src/main/ets/contracts/OutlineCommands'
// 导图的附加信息（M5）：概要 / 关系线（独立侧车，不进正文）
export {
  OutlineSummary,
  OutlineRelation,
  OutlineBoundary,
  OutlineBoundaryBox,
  OUTLINE_BOUNDARY_PAD,
  outlineBoundaryBoxes,
  OutlineExtras,
  OutlineExtraCommand,
  OutlineNodeStyle,
  OUTLINE_EXTRA_ADD_SUMMARY,
  OUTLINE_EXTRA_REMOVE_SUMMARY,
  OUTLINE_EXTRA_ADD_RELATION,
  OUTLINE_EXTRA_REMOVE_RELATION,
  OUTLINE_EXTRA_ADD_BOUNDARY,
  OUTLINE_EXTRA_REMOVE_BOUNDARY,
  OUTLINE_EXTRA_SET_NODE_STYLE,
  OUTLINE_SHAPE_CARD,
  OUTLINE_SHAPE_PILL,
  OUTLINE_SHAPE_PLAIN,
  isBlankNodeStyle,
  findNodeStyle,
  toggleMarker,
  nodeLabelY,
  OUTLINE_SUMMARY_GAP,
  OUTLINE_SUMMARY_TEXT_W,
  OUTLINE_EXTRA_PAD,
  OutlineSummaryBox,
  OutlineRelationWire,
  outlineSummaryBoxes,
  outlineRelationWires,
  summaryRangeOf
} from './src/main/ets/contracts/OutlineExtras'

// 导图 → 文本互通（Markdown / OPML / FreeMind）
export {
  outlineMarkdown,
  outlineOpml,
  outlineFreemind,
  outlineExportExtension,
  OUTLINE_EXPORT_MD,
  OUTLINE_EXPORT_OPML,
  OUTLINE_EXPORT_FREEMIND,
  OUTLINE_EXPORT_PNG
} from './src/main/ets/contracts/OutlineExport'
