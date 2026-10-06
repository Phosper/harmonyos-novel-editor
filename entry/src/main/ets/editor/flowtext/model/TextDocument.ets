/**
 * FlowText 文档模型（单一事实源）
 *
 * 持有全文、光标偏移、选区范围与变更版本号。
 * 索引语义为 UTF-16 code unit（与系统输入法 insertText 回调一致），
 * 但**对外的编辑操作以字符（字素簇）为最小单位**：见 GraphemeUtil。
 * 内部仍存码元索引，IME 传什么就存什么，不需要在边界转换。
 */
import { GraphemeUtil } from './GraphemeUtil';
import { FormatRun, StyleKind } from './EditorTypes';

export class TextDocument {
  private textValue: string = '';
  private caretOffsetValue: number = 0;
  private selectionStartValue: number = 0;
  private selectionEndValue: number = 0;
  private versionValue: number = 0;
  /** 行内/段落格式标注（仅存非默认项；按偏移升序、非重叠）（T020） */
  private runsValue: FormatRun[] = [];
  private formatVersionValue: number = 0;

  get text(): string {
    return this.textValue;
  }

  get caretOffset(): number {
    return this.caretOffsetValue;
  }

  get selectionStart(): number {
    return this.selectionStartValue;
  }

  get selectionEnd(): number {
    return this.selectionEndValue;
  }

  get version(): number {
    return this.versionValue;
  }

  /** 当前格式标注（只读视图） */
  get runs(): FormatRun[] {
    return this.runsValue;
  }

  /** 格式版本号：格式变化时自增，供布局缓存失效（T020） */
  get formatVersion(): number {
    return this.formatVersionValue;
  }

  get length(): number {
    return this.textValue.length;
  }

  /** 整体载入文本，光标置于末尾 */
  setText(text: string): void {
    this.textValue = text;
    this.caretOffsetValue = this.textValue.length;
    this.selectionStartValue = this.caretOffsetValue;
    this.selectionEndValue = this.caretOffsetValue;
    this.runsValue = [];
    this.formatVersionValue += 1;
    this.versionValue += 1;
  }

  /**
   * 整体载入文本并把光标恢复到指定位置（打开文稿时恢复上次光标用）。
   * 历史偏移可能落在代理对内部（如旧版本按码元保存过），需吸附到边界。
   */
  setTextWithCaret(text: string, caret: number): void {
    this.setText(text);
    this.moveCaret(caret);
  }

  /** 在指定偏移插入文本，光标移动到插入点之后（偏移自动吸附到字符边界） */
  insert(offset: number, insertText: string): void {
    if (insertText.length === 0) {
      return;
    }
    const clamped: number = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(offset));
    this.textValue =
      this.textValue.substring(0, clamped) + insertText + this.textValue.substring(clamped);
    this.shiftRunsAtInsert(clamped, insertText.length);
    this.caretOffsetValue = clamped + insertText.length;
    this.selectionStartValue = this.caretOffsetValue;
    this.selectionEndValue = this.caretOffsetValue;
    this.versionValue += 1;
  }

  /** 删除 [rangeStart, rangeEnd) 区间内容（顺序无关），光标回到区间起点 */
  delete(rangeStart: number, rangeEnd: number): void {
    const start: number = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(Math.min(rangeStart, rangeEnd)));
    const rawEnd: number = this.clamp(Math.max(rangeStart, rangeEnd));
    const end: number = GraphemeUtil.isBoundary(this.textValue, rawEnd) ? rawEnd :
      GraphemeUtil.moveRight(this.textValue, rawEnd);
    if (start === end) {
      return;
    }
    this.textValue = this.textValue.substring(0, start) + this.textValue.substring(end);
    this.adjustRunsAtDelete(start, end);
    this.caretOffsetValue = start;
    this.selectionStartValue = start;
    this.selectionEndValue = start;
    this.versionValue += 1;
  }

  /**
   * 向左删除 length 个字符（基于当前光标）。
   * length 表示"字符数"而非码元数：删除时按字素簇整簇移除，
   * 避免把 emoji / 组合字符删成半个乱码。
   */
  deleteLeft(length: number): void {
    let at: number = this.caretOffsetValue;
    for (let n: number = 0; n < length; n++) {
      const prev: number = GraphemeUtil.moveLeft(this.textValue, at);
      if (prev >= at) {
        break;
      }
      at = prev;
    }
    this.delete(at, this.caretOffsetValue);
  }

  /**
   * 向右删除 length 个字符（基于当前光标），按字素簇整簇移除。
   */
  deleteRight(length: number): void {
    let at: number = this.caretOffsetValue;
    for (let n: number = 0; n < length; n++) {
      const next: number = GraphemeUtil.moveRight(this.textValue, at);
      if (next <= at) {
        break;
      }
      at = next;
    }
    this.delete(this.caretOffsetValue, at);
  }

  /**
   * 移动光标（收起选区）。
   * 传入的偏移会被吸附到最近的字符边界：调用方（命中测试 / IME / 外部状态）
   * 可能给出落在代理对或组合字符内部的索引，直接使用会导致插入产生乱码。
   */
  moveCaret(offset: number): void {
    this.caretOffsetValue = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(offset));
    this.selectionStartValue = this.caretOffsetValue;
    this.selectionEndValue = this.caretOffsetValue;
  }

  /**
   * 设置选区（start/end 顺序无关，光标取 end）。
   * 两端都吸附到字符边界，避免选区切碎代理对导致删除时产生乱码。
   */
  setSelection(start: number, end: number): void {
    const lo: number = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(Math.min(start, end)));
    const hi: number = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(Math.max(start, end)));
    // 吸附后可能出现 lo > hi（两端各自向外吸附），交换回来
    this.selectionStartValue = Math.min(lo, hi);
    this.selectionEndValue = Math.max(lo, hi);
    this.caretOffsetValue = GraphemeUtil.snapToBoundary(this.textValue, this.clamp(end));
  }

  /**
   * 按方向移动光标（direction: -1 左移 / 1 右移；上下移动由外部按行换算后调用 moveCaret）。
   * 以**字符**为单位移动，落在 emoji / 组合字符中间时会自动跳到相邻边界。
   */
  moveCaretByDirection(direction: number): void {
    if (direction < 0) {
      this.moveCaret(GraphemeUtil.moveLeft(this.textValue, this.caretOffsetValue));
      return;
    }
    if (direction > 0) {
      this.moveCaret(GraphemeUtil.moveRight(this.textValue, this.caretOffsetValue));
      return;
    }
    this.moveCaret(this.caretOffsetValue);
  }

  // ================= 行内/段落格式（T020） =================

  /** 整体设置格式标注（载入时用），自动归一化 */
  setRuns(runs: FormatRun[]): void {
    this.runsValue = [];
    for (let i = 0; i < runs.length; i++) {
      this.runsValue.push(runs[i].clone());
    }
    this.normalizeRuns();
  }

  /** 取某偏移处的标题级别（0=正文） */
  headingAt(offset: number): number {
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (offset >= r.startOffset && offset < r.endOffset) {
        return r.heading;
      }
    }
    return 0;
  }

  /** 切换行内样式（粗/斜）于 [start,end)；已全具备则取消，否则施加 */
  toggleInline(kind: StyleKind, start: number, end: number): void {
    const s: number = Math.max(0, Math.min(start, end));
    const e: number = Math.min(this.textValue.length, Math.max(start, end));
    if (e <= s) {
      return;
    }
    this.splitAt(s);
    this.splitAt(e);
    let allOn: boolean = true;
    let covered: number = s;
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (r.startOffset >= s && r.endOffset <= e) {
        if (r.startOffset !== covered) {
          allOn = false;
        }
        covered = r.endOffset;
        const on: boolean = kind === StyleKind.BOLD ? r.bold : r.italic;
        if (!on) {
          allOn = false;
        }
      }
    }
    const turnOn: boolean = !(covered === e && allOn);
    this.applyInlineOverRange(kind, s, e, turnOn);
    this.normalizeRuns();
  }

  /** 切换段落标题级别于 [start,end) 覆盖的段落；已全部为该级别则恢复正文 */
  toggleHeading(level: number, start: number, end: number): void {
    if (this.textValue.length === 0) {
      return;
    }
    const lo: number = Math.max(0, Math.min(start, end));
    const hi: number = Math.max(start, end);
    const first: number[] = this.paragraphBounds(lo);
    const last: number[] = this.paragraphBounds(hi > 0 ? hi - 1 : 0);
    const ps: number = first[0];
    const pe: number = last[1];
    if (pe <= ps) {
      return;
    }
    let allOn: boolean = true;
    let cursor: number = ps;
    while (cursor < pe) {
      const pb: number[] = this.paragraphBounds(cursor);
      const pEnd: number = Math.min(pb[1], pe);
      if (this.headingAt(cursor) !== level) {
        allOn = false;
      }
      cursor = pEnd < pe ? (pEnd + 1) : pe;
    }
    const target: number = allOn ? 0 : level;
    cursor = ps;
    while (cursor < pe) {
      const pb: number[] = this.paragraphBounds(cursor);
      const pEnd: number = Math.min(pb[1], pe);
      this.splitAt(cursor);
      this.splitAt(pEnd);
      this.applyHeadingOverRange(cursor, pEnd, target);
      cursor = pEnd < pe ? (pEnd + 1) : pe;
    }
    this.normalizeRuns();
  }

  /** 段落边界 [start,end]（不含换行符） */
  private paragraphBounds(offset: number): number[] {
    const c: number = Math.max(0, Math.min(offset, this.textValue.length));
    let start: number = this.textValue.lastIndexOf('\n', c - 1);
    start = start < 0 ? 0 : start + 1;
    let end: number = this.textValue.indexOf('\n', c);
    end = end < 0 ? this.textValue.length : end;
    return [start, end];
  }

  /** 在 offset 处切分跨越它的 run，保证该点成为边界 */
  private splitAt(offset: number): void {
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (offset > r.startOffset && offset < r.endOffset) {
        const right: FormatRun = r.clone();
        right.startOffset = offset;
        r.endOffset = offset;
        this.runsValue.splice(i + 1, 0, right);
        return;
      }
    }
  }

  /** 把 [s,e) 内所有分段统一设为/取消某行内样式（缺失分段在开启时补建） */
  private applyInlineOverRange(kind: StyleKind, s: number, e: number, on: boolean): void {
    const bounds: number[] = this.collectBounds(s, e);
    for (let i = 0; i + 1 < bounds.length; i++) {
      const a: number = bounds[i];
      const b: number = bounds[i + 1];
      if (b <= a) {
        continue;
      }
      const r: FormatRun | null = this.findRunExact(a, b);
      if (r === null) {
        if (!on) {
          continue;
        }
        const nr: FormatRun = new FormatRun(a, b, kind === StyleKind.BOLD, kind === StyleKind.ITALIC, 0);
        this.runsValue.push(nr);
      } else if (kind === StyleKind.BOLD) {
        r.bold = on;
      } else {
        r.italic = on;
      }
    }
  }

  /** 把 [a,b) 内所有分段统一设为某标题级别 */
  private applyHeadingOverRange(a: number, b: number, level: number): void {
    const bounds: number[] = this.collectBounds(a, b);
    for (let i = 0; i + 1 < bounds.length; i++) {
      const s: number = bounds[i];
      const e: number = bounds[i + 1];
      if (e <= s) {
        continue;
      }
      const r: FormatRun | null = this.findRunExact(s, e);
      if (r === null) {
        if (level === 0) {
          continue;
        }
        this.runsValue.push(new FormatRun(s, e, false, false, level));
      } else {
        r.heading = level;
      }
    }
  }

  /** 收集 [s,e) 内的分段边界（含 s、e 与区间内所有 run 边界），升序去重 */
  private collectBounds(s: number, e: number): number[] {
    const raw: number[] = [s, e];
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (r.startOffset > s && r.startOffset < e) {
        raw.push(r.startOffset);
      }
      if (r.endOffset > s && r.endOffset < e) {
        raw.push(r.endOffset);
      }
    }
    raw.sort((a: number, b: number) => a - b);
    const uniq: number[] = [];
    for (let i = 0; i < raw.length; i++) {
      if (i === 0 || raw[i] !== raw[i - 1]) {
        uniq.push(raw[i]);
      }
    }
    return uniq;
  }

  /** 查找恰好覆盖 [a,b) 的 run */
  private findRunExact(a: number, b: number): FormatRun | null {
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (r.startOffset === a && r.endOffset === b) {
        return r;
      }
    }
    return null;
  }

  /** 归一化：裁剪到文本范围、丢弃空/默认、按起点排序、合并相邻同式、裁剪重叠 */
  private normalizeRuns(): void {
    const list: FormatRun[] = [];
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      const s: number = Math.max(0, Math.min(r.startOffset, r.endOffset));
      const e: number = Math.min(this.textValue.length, Math.max(r.startOffset, r.endOffset));
      if (e <= s || r.isDefault()) {
        continue;
      }
      list.push(new FormatRun(s, e, r.bold, r.italic, r.heading));
    }
    list.sort((a: FormatRun, b: FormatRun) => a.startOffset - b.startOffset);
    const merged: FormatRun[] = [];
    for (let i = 0; i < list.length; i++) {
      const cur: FormatRun = list[i];
      if (merged.length > 0) {
        const last: FormatRun = merged[merged.length - 1];
        if (cur.startOffset < last.endOffset) {
          cur.startOffset = last.endOffset;
          if (cur.endOffset <= cur.startOffset) {
            continue;
          }
        }
        if (cur.startOffset === last.endOffset && last.sameAs(cur)) {
          last.endOffset = cur.endOffset;
          continue;
        }
      }
      merged.push(cur);
    }
    this.runsValue = merged;
    this.formatVersionValue += 1;
  }

  /** 插入时平移/扩展格式标注 */
  private shiftRunsAtInsert(offset: number, len: number): void {
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (r.startOffset >= offset) {
        r.startOffset += len;
        r.endOffset += len;
      } else if (r.endOffset > offset) {
        r.endOffset += len;
      }
    }
    this.formatVersionValue += 1;
  }

  /** 删除时收缩/平移格式标注 */
  private adjustRunsAtDelete(start: number, end: number): void {
    const delta: number = end - start;
    const out: FormatRun[] = [];
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      let s: number = r.startOffset;
      let e: number = r.endOffset;
      if (e <= start) {
        // 完全在删除区间之前，保持不变
      } else if (s >= end) {
        s -= delta;
        e -= delta;
      } else {
        // 与删除区间交叠
        s = Math.min(s, start);
        e = e > end ? (e - delta) : start;
      }
      if (e > s) {
        out.push(new FormatRun(s, e, r.bold, r.italic, r.heading));
      }
    }
    this.runsValue = out;
    this.normalizeRuns();
  }

  private clamp(offset: number): number {
    if (offset < 0) {
      return 0;
    }
    if (offset > this.textValue.length) {
      return this.textValue.length;
    }
    return offset;
  }
}
