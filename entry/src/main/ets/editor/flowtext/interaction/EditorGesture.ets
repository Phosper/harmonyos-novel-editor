/**
 * FlowText 手势处理（MVP：点按定位光标；拖动选择基础支持）
 *
 * 回调由组件在 onTouch 中分发：Down/Up 位置一致 → 点击定位；
 * 按下后移动超过阈值 → 拖动选区。
 */
import { HitTester } from './HitTester';
import { LayoutLine } from '../render/TextLayoutEngine';

export class EditorGesture {
  private static readonly DRAG_THRESHOLD_PX: number = 8;

  /**
   * 点按定位：返回命中的字符偏移。
   * @param source 全文，用于把命中结果吸附到字符边界（emoji/组合字符内部需归位）
   */
  static tap(x: number, y: number, lines: LayoutLine[], paddingLeftPx: number, paddingTopPx: number,
    source: string = ''): number {
    return HitTester.hitTest(x, y, lines, paddingLeftPx, paddingTopPx, source);
  }

  static isDrag(pressX: number, pressY: number, moveX: number, moveY: number): boolean {
    const dx: number = moveX - pressX;
    const dy: number = moveY - pressY;
    return dx * dx + dy * dy > EditorGesture.DRAG_THRESHOLD_PX * EditorGesture.DRAG_THRESHOLD_PX;
  }
}
