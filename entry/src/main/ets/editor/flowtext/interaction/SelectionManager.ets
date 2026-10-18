/**
 * FlowText 选区管理
 *
 * 索引语义与 TextDocument 一致（UTF-16 码元），两端必须落在**字符边界**：
 * IME 的 selectByRange 可能给出任意偏移，直接使用会切碎代理对，导致删除出乱码。
 *
 * 单一事实源是 **anchor / head**（参考 OpenHarmony ace_engine TextSelection 的
 * base/extent 模型）：
 *   - startOffset/endOffset 永远由 min/max 派生，不单独存储，避免两端漂移；
 *   - 反向选择（head < anchor）时 head 就是光标所在端；
 *   - 手柄身份固定（1=anchor、2=head），越过对端时**不交换身份**，只由 min/max
 *     重新归一——交换身份正是"多选越界即乱"的高发根因。
 *   - 软换行边界处的落点亲和性由 headAffinity 给出，交给 HitTester 选边。
 */
import { CaretAffinity, SelectionInfo } from '../model/EditorTypes';
import { GraphemeUtil } from '../model/GraphemeUtil';

export class SelectionManager {
  /** 选区锚点（拖选起点；反向选择时位于文档序更靠后的一端） */
  private anchorValue: number = 0;
  /** 选区活动端（光标所在端） */
  private headValue: number = 0;
  /** 全文，用于把选区两端吸附到字符边界（未设置时退化为仅钳制范围） */
  private source: string = '';
  /** 拖选是否进行中 */
  private dragActive: boolean = false;
  /** 当前拖动中的手柄：0 无 / 1 anchor / 2 head */
  private handleDragging: number = 0;
  /** 派生视图缓存：避免每帧分配，但每次读取都会按 anchor/head 重算 */
  private readonly selValue: SelectionInfo = new SelectionInfo();

  get anchor(): number { return this.anchorValue; }
  get head(): number { return this.headValue; }
  get startOffset(): number { return Math.min(this.anchorValue, this.headValue); }
  get endOffset(): number { return Math.max(this.anchorValue, this.headValue); }

  /**
   * 光标落点亲和性：
   * - 正向选择（anchor <= head）：head 在文档序右端，落在软换行处应贴上一行行尾；
   * - 反向选择（anchor > head）：head 在左端，落在软换行处应贴下一行行首；
   * - 折叠光标默认 DOWNSTREAM（与"行尾接续输入"一致）。
   */
  get headAffinity(): CaretAffinity {
    return this.anchorValue <= this.headValue ? CaretAffinity.DOWNSTREAM : CaretAffinity.UPSTREAM;
  }

  /** 当前选区（start<=end，派生自 anchor/head） */
  get selection(): SelectionInfo {
    this.syncView();
    return this.selValue;
  }

  /** 设定参照全文，使后续选区操作能按字符边界收敛 */
  setSource(text: string): void {
    this.source = text;
  }

  /** 设置选区（方向保留：start 为 anchor，end 为 head） */
  setSelection(start: number, end: number): void {
    this.anchorValue = this.normalize(start);
    this.headValue = this.normalize(end);
    this.syncView();
  }

  /** 光标位置即选区（收起选区） */
  collapse(offset: number): void {
    const at: number = this.normalize(offset);
    this.anchorValue = at;
    this.headValue = at;
    this.syncView();
  }

  /** Shift+方向键：锚点不动，只移动 head */
  extendTo(offset: number): void {
    this.headValue = this.normalize(offset);
    this.syncView();
  }

  /** 开始拖选（anchor = 按下点） */
  beginDrag(offset: number): void {
    const at: number = this.normalize(offset);
    this.dragActive = true;
    this.anchorValue = at;
    this.headValue = at;
    this.syncView();
  }

  /** 拖选移动：anchor 固定，head 跟随手指/鼠标 */
  updateDrag(offset: number): void {
    if (!this.dragActive) {
      return;
    }
    this.headValue = this.normalize(offset);
    this.syncView();
  }

  /** 结束拖选 */
  endDrag(): void {
    this.dragActive = false;
  }

  get draggingHandle(): number {
    return this.handleDragging;
  }

  /** 开始拖动指定手柄（1=anchor / 2=head） */
  beginHandleDrag(which: number): void {
    this.handleDragging = which;
  }

  /**
   * 拖动手柄更新选区。
   * 身份固定：handle 1 只改 anchor，handle 2 只改 head；越过对端时由 min/max
   * 自然翻转视觉方向（参考 OH TextSelectController 的 first/second handle 模型）。
   */
  updateHandleDrag(offset: number): void {
    if (this.handleDragging === 0) {
      return;
    }
    const at: number = this.normalize(offset);
    if (this.handleDragging === 1) {
      this.anchorValue = at;
    } else {
      this.headValue = at;
    }
    this.syncView();
  }

  /** 结束手柄拖动 */
  endHandleDrag(): void {
    this.handleDragging = 0;
  }

  clear(): void {
    this.anchorValue = 0;
    this.headValue = 0;
    this.dragActive = false;
    this.handleDragging = 0;
    this.syncView();
  }

  private syncView(): void {
    this.selValue.startOffset = Math.min(this.anchorValue, this.headValue);
    this.selValue.endOffset = Math.max(this.anchorValue, this.headValue);
  }

  /** 钳制到范围并吸附到字符边界 */
  private normalize(offset: number): number {
    const len: number = this.source.length;
    if (Number.isNaN(offset) || offset < 0) {
      return 0;
    }
    if (offset > len) {
      return len;
    }
    if (this.source === '') {
      return offset;
    }
    if (GraphemeUtil.isBoundary(this.source, offset)) {
      return offset;
    }
    const prev: number = GraphemeUtil.snapToBoundary(this.source, offset);
    const next: number = GraphemeUtil.moveRight(this.source, prev);
    return (offset - prev) <= (next - offset) ? prev : next;
  }
}
