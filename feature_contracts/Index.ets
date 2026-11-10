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
  buildOutline,
  buildOutlineFromParagraphs,
  layoutOutline,
  outlineParents
} from './src/main/ets/contracts/OutlineLayout'
export type { OutlineHeading, OutlineParagraph } from './src/main/ets/contracts/OutlineLayout'
