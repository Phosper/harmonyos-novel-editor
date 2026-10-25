// 思路板的尺寸与阈值（实现用 vp；原型页用 px 近似）
// 集中放置，避免散落魔数；改这里即改全局手感。
export class CanvasSpec {
  /** 概念卡宽度 */
  static readonly CARD_WIDTH: number = 226
  /** 写作卡宽度（要容纳缩进行） */
  static readonly WRITING_WIDTH: number = 344
  /** 子卡每层缩进 */
  static readonly INDENT: number = 14
  /** 子卡行高 */
  static readonly ROW_HEIGHT: number = 30
  /** 拖动靠近卡片多远才张嘴 */
  static readonly MOUTH_INFLATE: number = 30
  /** 行命中的外扩（行优先于卡） */
  static readonly ROW_INFLATE: number = 8
  /** 张嘴缺口高度 */
  static readonly MOUTH_HEIGHT: number = 30
  /** 子卡最大层数（章/节/目） */
  static readonly MAX_DEPTH: number = 3
  /** 素材抽屉宽度 */
  static readonly DRAWER_WIDTH: number = 392
  /** 缩放范围 */
  static readonly MIN_ZOOM: number = 0.6
  static readonly MAX_ZOOM: number = 1.8
  /** 点阵背景间距 */
  static readonly DOT_GAP: number = 20
  /** 画布内容的世界尺寸上限（卡片坐标超出时提示拆分） */
  static readonly WORLD_LIMIT: number = 40000
  /** 软上限：超过提示拆分白板 */
  static readonly SOFT_CARD_LIMIT: number = 200
}
