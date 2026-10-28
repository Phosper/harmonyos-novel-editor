/**
 * 全局动效令牌：按 HarmonyOS 官方动效设计原则统一时长与曲线。
 *
 * 官方依据（2026-10-21 阅读）：
 * - 设计原则：自然流畅、简洁高效、快速响应、运动一致、隐藏等待、凸显品牌。
 * - 时长：颜色等简单动画 100ms；小范围 150ms；局部范围 200ms；长距离不超过 350ms。
 * - 曲线：视线内、起止都静止的物体用**标准曲线**
 *   cubic-bezier(0.40, 0.00, 0.20, 1.00)；新出现物体用减速曲线；
 *   离场用加速曲线；可打断的物理运动用 spring。
 *
 * 本项目的映射：
 * - 颜色/透明度小状态：fast 120ms；
 * - 面板、列表局部变化：normal 200ms；
 * - 侧栏这类局部结构变化：sidebar 240ms（起止静止，用标准曲线，避免 EaseOut 的“突然启动”生硬感）；
 * - 页面级结构：slow 300ms。
 */
export class Motion {
  static readonly fast: number = 120
  static readonly normal: number = 200
  static readonly sidebar: number = 240
  static readonly slow: number = 300
  /** 官方标准曲线：两端静止、速度峰值在中段，适合视线内物体的收放 */
  static readonly standardCurve: string = 'cubic-bezier(0.40, 0.00, 0.20, 1.00)'
}
