// 核心运行时的对外骨架（ADR-003）
//
// P4 只做"能被 entry 引用、能编译、能打包"的最小面：
//   - 版本号：宿主与功能包各自校验；
//   - 功能目录：基础包里要能显示"有哪些扩展、装没装"；
//   - 宿主服务入口：P5 接 DocumentSession 时在这里扩展，不新增第二个单例。
//
// 明确不做：P4 阶段不搬仓储、不搬 Store、不改正文。搬动在 P5 按 ADR-002 执行。
import { FeatureDescriptor, FeatureId, SurfaceKind } from 'feature_contracts'

/** 宿主接口版本：功能包激活前必须与它比对 */
export const HOST_API_VERSION: number = 1

/**
 * 内置功能目录。即使某个包没装，也要能显示名字与"未安装"状态，
 * 所以这份清单必须在基础包里（不能从可选包读）。
 */
export function featureCatalog(): FeatureDescriptor[] {
  const list: FeatureDescriptor[] = []
  const structure: FeatureDescriptor = new FeatureDescriptor(
    FeatureId.STRUCTURE, 'structure_feature',
    [SurfaceKind.FULL_PAGE, SurfaceKind.WORKSPACE_VIEW], '大纲 · 导图 · 演讲')
  structure.routeName = 'structure'
  structure.contractVersion = HOST_API_VERSION
  list.push(structure)
  const board: FeatureDescriptor = new FeatureDescriptor(
    FeatureId.BOARD, 'board_feature', [SurfaceKind.FULL_PAGE], '思路板')
  board.routeName = 'board'
  board.contractVersion = HOST_API_VERSION
  list.push(board)
  const novel: FeatureDescriptor = new FeatureDescriptor(
    FeatureId.NOVEL, 'novel_feature', [SurfaceKind.INSPECTOR, SurfaceKind.FULL_PAGE], '小说工具')
  novel.contractVersion = HOST_API_VERSION
  list.push(novel)
  const research: FeatureDescriptor = new FeatureDescriptor(
    FeatureId.RESEARCH, 'research_feature', [SurfaceKind.FULL_PAGE, SurfaceKind.INSPECTOR], '文献与引用')
  research.routeName = 'research'
  research.contractVersion = HOST_API_VERSION
  list.push(research)
  return list
}

/** 按 id 取功能自述；找不到返回 undefined（调用方按"未安装/未知"处理） */
export function findFeature(id: FeatureId): FeatureDescriptor | undefined {
  const all: FeatureDescriptor[] = featureCatalog()
  for (let i: number = 0; i < all.length; i++) {
    if (all[i].id === id) {
      return all[i]
    }
  }
  return undefined
}
