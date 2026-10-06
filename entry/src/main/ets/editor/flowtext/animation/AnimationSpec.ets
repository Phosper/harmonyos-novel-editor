/**
 * FlowText 动画规格（弹簧曲线参数）
 *
 * 使用 interpolating-spring(velocity, mass, stiffness, damping) 字符串曲线。
 * 参数经真机体验调优：响应时间控制在 0.3s 以内，避免动画拖沓。
 */
export class AnimationSpec {
  /**
   * 光标移动曲线：按距离分段的 interpolating-spring（弹簧=灵动；分段=远慢近快 + 近处跟手）。
   *   - 弹簧让光标"起步即响应、末端轻微过冲回稳"，比固定贝塞尔(ease-ish)更自然/灵动；
   *   - 太远的路程用更低刚度(稍慢) + 稍松阻尼(多一点点余摆)，反之近程快且几乎不过冲。
   *  interpolating-spring 会忽略 duration（由参数决定时长），因此"远慢近快"靠分段参数实现。
   */
  /**
   * 光标移动曲线：按距离分段的 interpolating-spring。
   *
   * 重要：interpolating-spring **不受 duration 控制**（动画时长由弹簧参数决定），
   * 因此"快慢"只能靠刚度/阻尼/初速度调。
   *
   * 参数尺度参考官方示例 `curves.springCurve(10, 1, 228, 30)`：
   *   - stiffness 越大 → 复位越快（官方量级在数百）；此前误用 3~5 导致复位长达数秒 → "光标移动过慢"。
   *   - damping 取近临界值（≈ 2·√stiffness）→ 快速落定且几乎不过冲。
   *   - velocity（归一化初速度）取较大值 → 起步即响应、更跟手。
   * 分段保留"远稍慢、近极快"的层次，但整体显著提速。
   */
  static caretCurveForDistance(distVp: number): string {
    if (distVp < 70) {
      // 近程：极高刚度 + 近临界阻尼 → 瞬间到位、几乎无过冲
      return 'interpolating-spring(20, 1, 340, 36)';
    }
    if (distVp < 180) {
      // 中程：稍降刚度，仍很快
      return 'interpolating-spring(18, 1, 300, 34)';
    }
    // 远程：再降一点刚度，跨度大也保持轻快
    return 'interpolating-spring(16, 1, 260, 32)';
  }

  /** 字形入场/退场弹簧曲线（提速：原刚度 1.8 过慢，改为近临界快落定） */
  static glyphEnter(): string {
    return 'interpolating-spring(2, 1, 150, 16)';
  }

  /** 占位时长（interpolating-spring 会忽略 duration；此值作 createAnimator 必填兜底） */
  static readonly caretNominalMs: number = 300;

  /** 字形动画时长（ms） */
  static readonly glyphAnimDurationMs: number = 240;
}
