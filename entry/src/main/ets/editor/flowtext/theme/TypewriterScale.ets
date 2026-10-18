/**
 * 打字机模式的段落缩放层级（纯函数 + 默认参数，绘制与动画共用）
 *
 * 设计约束：
 *   - 当前段落 1.08×，仅"适度放大"，不改变字号/行高/换行（缩放只发生在绘制阶段）；
 *   - 相邻行 0.98×，按行距逐步缩小 0.02/行，最低 0.90×，保证可读性；
 *   - 距离为**浮点行距**：段落切换动画期间焦点边界平滑移动，
 *     每行缩放值随之连续变化，不会出现整段瞬间跳变的断层。
 */
export class TypewriterScaleOptions {
  /** 当前段落缩放（建议 1.05–1.12） */
  focusScale: number = 1.08;
  /** 紧邻当前段落的行缩放（建议 0.96–0.99） */
  adjacentScale: number = 0.98;
  /** 每远离一行再缩小的步长（建议 0.01–0.025） */
  scaleStep: number = 0.02;
  /** 最小缩放（不低于 0.88–0.92，避免影响阅读） */
  minScale: number = 0.90;
}

/** 行到当前段落边界的距离（行）；段落内部为 0，支持浮点边界（过渡动画） */
export function typewriterLineDistance(index: number, focusFirst: number, focusLast: number): number {
  if (focusFirst < 0 || focusLast < 0) {
    return 0;
  }
  if (index < focusFirst) {
    return focusFirst - index;
  }
  if (index > focusLast) {
    return index - focusLast;
  }
  return 0;
}

/**
 * 距离 → 缩放：
 *   d = 0      → focusScale（当前段落）
 *   0 < d ≤ 1  → 从 focusScale 连续过渡到 adjacentScale（边界动画期间的插值区间）
 *   d > 1      → adjacentScale - step*(d-1)，下限 minScale
 */
export function typewriterScaleForDistance(distance: number, opts: TypewriterScaleOptions): number {
  if (distance <= 0) {
    return opts.focusScale;
  }
  if (distance <= 1) {
    return opts.focusScale - (opts.focusScale - opts.adjacentScale) * distance;
  }
  return Math.max(opts.minScale, opts.adjacentScale - opts.scaleStep * (distance - 1));
}

/**
 * 距离 → 淡化权重（0 = 正常色，1 = 完全淡化）。
 * 在 1 行内线性过渡，段落切换时淡化同步平滑淡入淡出。
 */
export function typewriterDimWeight(distance: number): number {
  return Math.max(0, Math.min(1, distance));
}
