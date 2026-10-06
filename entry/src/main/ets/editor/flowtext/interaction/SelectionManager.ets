/**
 * FlowText 选区管理
 *
 * 选区索引语义与 TextDocument 一致（UTF-16 码元），但两端都必须落在**字符边界**：
 * IME 的 selectByRange 可能给出任意偏移，直接使用会切碎代理对，
 * 导致后续删除该选区时产生乱码。
 */
import { SelectionInfo } from '../model/EditorTypes';
import { GraphemeUtil } from '../model/GraphemeUtil';

export class SelectionManager {
  private sel: SelectionInfo = new SelectionInfo();
  /** 拖动锚点（-1 表示未在拖动） */
  private anchorOffset: number = -1;
  /** 全文，用于把选区两端吸附到字符边界（未设置时退化为仅钳制范围） */
  private source: string = '';
  private anchorValue: number = 0;
  private headValue: number = 0;

  get anchor(): number { return this.anchorValue; }
  get head(): number { return this.headValue; }

  extendTo(offset: number): void {
    this.setSelection(this.anchorValue, offset);
  }

  get selection(): SelectionInfo {
    return this.sel;
  }

  /** 设定参照全文，使后续选区操作能按字符边界收敛 */
  setSource(text: string): void {
    this.source = text;
  }

  /**
   * 设置选区（顺序无关）。越界会被钳制到 [0, length]，
   * 落在字符内部的偏移会吸附到就近边界。
   */
  setSelection(start: number, end: number): void {
    this.anchorValue = this.normalize(start);
    this.headValue = this.normalize(end);
    const lo: number = this.normalize(Math.min(start, end));
    const hi: number = this.normalize(Math.max(start, end));
    this.sel.startOffset = Math.min(lo, hi);
    this.sel.endOffset = Math.max(lo, hi);
  }

  /** 光标位置即选区（收起选区） */
  collapse(offset: number): void {
    const at: number = this.normalize(offset);
    this.sel.startOffset = at;
    this.sel.endOffset = at;
    this.anchorValue = at;
    this.headValue = at;
  }

  /** 开始拖动（锚点 = 起始偏移） */
  beginDrag(offset: number): void {
    const at: number = this.normalize(offset);
    this.anchorOffset = at;
    this.collapse(at);
  }

  /** 拖动中更新选区 */
  updateDrag(offset: number): void {
    if (this.anchorOffset < 0) {
      return;
    }
    const at: number = this.normalize(offset);
    this.setSelection(this.anchorOffset, at);
  }

  /** 结束拖动 */
  endDrag(): void {
    this.anchorOffset = -1;
  }

  /** 当前拖动中的手柄：0 无 / 1 起点 / 2 终点 */
  private handleDragging: number = 0;

  get draggingHandle(): number {
    return this.handleDragging;
  }

  /** 开始拖动指定手柄（1 起点 / 2 终点） */
  beginHandleDrag(which: number): void {
    this.handleDragging = which;
  }

  /** 拖动手柄更新选区（保持 start<=end，越过对端时自动切换手柄） */
  updateHandleDrag(offset: number): void {
    if (this.handleDragging === 0) {
      return;
    }
    const at: number = this.normalize(offset);
    if (this.handleDragging === 1) {
      if (at <= this.sel.endOffset) {
        this.sel.startOffset = at;
      } else {
        this.sel.startOffset = this.sel.endOffset;
        this.sel.endOffset = at;
        this.handleDragging = 2;
      }
    } else {
      if (at >= this.sel.startOffset) {
        this.sel.endOffset = at;
      } else {
        this.sel.endOffset = this.sel.startOffset;
        this.sel.startOffset = at;
        this.handleDragging = 1;
      }
    }
    this.anchorValue = this.handleDragging === 1 ? this.sel.endOffset : this.sel.startOffset;
    this.headValue = this.handleDragging === 1 ? this.sel.startOffset : this.sel.endOffset;
  }

  /** 结束手柄拖动 */
  endHandleDrag(): void {
    if (this.handleDragging !== 0) {
      this.anchorValue = this.handleDragging === 1 ? this.sel.endOffset : this.sel.startOffset;
      this.headValue = this.handleDragging === 1 ? this.sel.startOffset : this.sel.endOffset;
    }
    this.handleDragging = 0;
  }

  clear(): void {
    this.collapse(0);
    this.anchorOffset = -1;
    this.handleDragging = 0;
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
