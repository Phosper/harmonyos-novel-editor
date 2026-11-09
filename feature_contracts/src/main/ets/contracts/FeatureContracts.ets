// 可选功能的**无状态契约**（对应 ADR-003 §2.1/§2.3–§2.6）
//
// 这个文件只能放：枚举、值类型、纯函数。
// 禁止放：单例、注册表、缓存、任何可变全局状态 —— 它会被编译进多个包，
// 每个包各拿一份代码，放状态就会出现"两份运行状态"。

/** 可独立获取的能力（与 ADR-003 的四个按需包一一对应） */
export enum FeatureId {
  STRUCTURE = 'structure',
  BOARD = 'board',
  NOVEL = 'novel',
  RESEARCH = 'research'
}

/**
 * 功能要挂到哪里。
 * 决定"该不该给它整页路由""能不能塞进旁栏"，与 ADR-003 §2.7 的五类位置对齐。
 */
export enum SurfaceKind {
  /** 全窗口目的地：思路板、文献库 */
  FULL_PAGE = 0,
  /** 工作区主视图：大纲、导图（不新开草稿） */
  WORKSPACE_VIEW = 1,
  /** 正文旁栏：人物、证据、引文 */
  INSPECTOR = 2,
  /** 短时选择浮层：选卡、选文献 */
  DIALOG = 3,
  /** 观众窗口：演讲播放（只读快照） */
  AUDIENCE = 4
}

/** 一次打开请求被拒绝/失败的原因；UI 据此给不同提示，不用字符串判断 */
export enum FeatureError {
  OK = 0,
  NOT_INSTALLED = 1,
  VERSION_MISMATCH = 2,
  INTENT_STALE = 3,
  TARGET_MISSING = 4,
  ACTIVATION_FAILED = 5
}

/** 功能自述：宿主据此决定"能不能装、装完挂哪、用什么名字" */
export class FeatureDescriptor {
  id: FeatureId = FeatureId.STRUCTURE
  /** 应用内模块名（HSP name），安装与加载都按它查 */
  moduleName: string = ''
  /** 契约接口版本：宿主与功能包各自校验，不一致就拒绝激活 */
  contractVersion: number = 1
  /** 允许挂载的位置（可多选） */
  surfaces: SurfaceKind[] = []
  /** 整页功能用的命名路由（空串 = 没有整页入口） */
  routeName: string = ''
  /** 功能目录里显示的名字；缺失功能也必须能显示它 */
  label: string = ''

  constructor(id: FeatureId = FeatureId.STRUCTURE, moduleName: string = '',
    surfaces: SurfaceKind[] = [], label: string = '') {
    this.id = id
    this.moduleName = moduleName
    this.surfaces = surfaces
    this.label = label
  }

  supports(surface: SurfaceKind): boolean {
    return this.surfaces.indexOf(surface) >= 0
  }
}

/**
 * 一次打开意图。
 * 只带"身份 + 代次 + 返回令牌"，绝不带可变对象或整篇正文（ADR-003 §2.5）。
 */
export class OpenIntent {
  intentId: string = ''
  windowId: string = ''
  projectId: string = ''
  /** 目标文稿；与 entityId 二选一（捕获类操作用 entityId） */
  docId: string = ''
  entityId: string = ''
  feature: FeatureId = FeatureId.STRUCTURE
  surface: SurfaceKind = SurfaceKind.FULL_PAGE
  /** 请求代次：窗口/项目/文稿一变就递增，用来丢弃迟到的异步结果 */
  generation: number = 0
  /** 返回时恢复上下文用的令牌（不是编辑器指针） */
  returnToken: string = ''

  constructor(intentId: string = '', feature: FeatureId = FeatureId.STRUCTURE,
    surface: SurfaceKind = SurfaceKind.FULL_PAGE) {
    this.intentId = intentId
    this.feature = feature
    this.surface = surface
  }
}

/** 范围化订阅：dispose 只清本次会话的监听，不注销别人的 */
export interface SubscriptionLease {
  dispose(): void
}

/**
 * 迟到的结果是否已经失效。
 * 纯函数，宿主与功能包都用它，避免各自写一遍比较逻辑。
 */
export function isIntentStale(intentGeneration: number, currentGeneration: number): boolean {
  return intentGeneration !== currentGeneration
}

/** 某位置是否允许挂这个功能（缺失 = 不允许，不猜） */
export function surfaceAllowed(descriptor: FeatureDescriptor, surface: SurfaceKind): boolean {
  return descriptor.supports(surface)
}
