/**
 * FlowText 动画编排器
 *
 * 基于 UIContext.createAnimator（@ohos.animator）驱动帧回调插值（目标状态驱动）：
 * 调用方传入 duration/easing 与 onFrame(progress) 回调，逐帧更新字形/光标插值状态并触发重绘。
 *
 * 曲线采用字符串形式的 interpolating-spring（物理弹簧曲线），达终点速度为 0。
 */
import { UIContext, AnimatorResult } from '@kit.ArkUI';

export class EditorAnimator {
  private uiContext: UIContext;
  private animator: AnimatorResult | null = null;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }

  /** 启动一个弹簧插值动画；onFrame 每帧回调 progress(0~1，已按曲线映射) */
  animate(duration: number, easing: string, onFrame: (progress: number) => void, onFinish: () => void): void {
    this.stop();
    const result: AnimatorResult = this.uiContext.createAnimator({
      duration: duration,
      easing: easing,
      delay: 0,
      iterations: 1,
      fill: 'forwards',
      direction: 'normal',
      begin: 0,
      end: 1
    });
    result.onFrame = (progress: number) => {
      onFrame(progress);
    };
    result.onFinish = () => {
      this.animator = null;
      onFinish();
    };
    this.animator = result;
    result.play();
  }

  /** 停止当前动画 */
  stop(): void {
    if (this.animator !== null) {
      this.animator.cancel();
      this.animator = null;
    }
  }

  /** 线性插值辅助 */
  static lerp(from: number, to: number, t: number): number {
    return from + (to - from) * t;
  }
}
