/**
 * FlowText 文档模型（单一事实源）
 *
 * 持有全文、光标偏移、选区范围与变更版本号。
 * 索引语义为 UTF-16 code unit（与系统输入法 insertText 回调一致），
 * 但**对外的编辑操作以字符（字素簇）为最小单位**：见 GraphemeUtil。
 * 内部仍存码元索引，IME 传什么就存什么，不需要在边界转换。
 */
import { GraphemeUtil } from './GraphemeUtil';
import { FormatRun, MAX_LIST_LEVEL, ParagraphKind, StyleKind, isListParagraph } from './EditorTypes';

export class TextDocument {
  private textValue: string = '';
  private caretOffsetValue: number = 0;
  private selectionStartValue: number = 0;
  private selectionEndValue: number = 0;
  private versionValue: number = 0;
  /** 行内/段落格式标注（仅存非默认项；按偏移升序、非重叠）（T020） */
  private runsValue: FormatRun[] = [];
  private formatVersionValue: number = 0;
  /**
   * 末段为空段落时的待生效段落属性。
   *
   * 为什么需要它：段落属性存于 FormatRun，而"文档末尾的空段落"没有任何字符，
   * 区间 [len,len) 是空标注，归一化时会被丢弃 —— 于是"先点 • 列表 再打字"
   * 这种最常见的用法会静默失效。这里把属性暂存在文档上，插入第一批字符时
   * 立即落到新文本上（见 insert）。
   */
  private pendingKindValue: number = -1;
  private pendingIndentValue: number = 0;
  private pendingOffsetValue: number = -1;

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
    this.clearPending();
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
    // 待生效属性绑定在"文档末尾的空段落"上：在它之前插入内容时必须跟着平移，
    // 否则它会被落到别的段落上（实测：先设置末段待办，再在段中插入，样式错位）。
    if (this.pendingOffsetValue >= 0 && clamped < this.pendingOffsetValue) {
      this.pendingOffsetValue += insertText.length;
    }
    // 空末段的待生效段落属性：第一批字符落地时同时落成标注，
    // 必须放在 shiftRunsAtInsert 之后，否则新标注会被自己平移。
    this.resolvePendingAt(clamped, insertText.length);
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
    // 删除会把被覆盖的段落标注一起裁掉：先记下删除点所在段落的种类，
    // 段内文字被删空时再补回来 —— 否则"删光列表项文字"会顺手退出列表，
    // 与 Word/备忘录的行为相反，也会和下一轮的 Backspace 语义打架。
    const attrs: number[] = this.paragraphAttrsAt(start);
    // 待生效属性（空末段）绑在偏移上：整体位于删除区间之后时要跟着左移
    const pendingOffset: number = this.pendingOffsetValue;
    const pendingKind: number = this.pendingKindValue;
    const pendingIndent: number = this.pendingIndentValue;
    const mergesParagraphs: boolean = this.textValue.substring(start, end).indexOf('\n') >= 0;
    this.textValue = this.textValue.substring(0, start) + this.textValue.substring(end);
    this.clearPending();
    this.adjustRunsAtDelete(start, end);
    if (pendingOffset >= end) {
      this.applyPending(pendingKind, pendingIndent, pendingOffset - (end - start));
    }
    this.restoreParagraphAttrsAfterDelete(start, attrs);
    if (mergesParagraphs) {
      // 删掉换行 = 两段合并：合并段跟随**前一段**的段落属性，
      // 否则后一段残留的 run 会让整段"复活"成列表/标题（行业惯例同 Word/备忘录）。
      this.applyParagraphAttrsAt(start, attrs);
    }
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
    this.clearPending();
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

  /**
   * 段落属性区间 [start, end)：**含段末换行符**。
   *
   * 为什么含换行：空段落只有一个 '\n'，不含它就无从记录"这一段是列表/待办"。
   * 换行符本身不产生字形，覆盖它没有视觉副作用；反而让"光标停在段尾"
   * 也能正确读到本段属性。
   */
  paragraphAttrsBounds(offset: number): number[] {
    const b: number[] = this.paragraphBounds(offset);
    const end: number = b[1] < this.textValue.length ? b[1] + 1 : b[1];
    return [b[0], end];
  }

  /** 该偏移所在段落的段落种类（ParagraphKind；0=正文） */
  paragraphKindAt(offset: number): number {
    return this.paragraphAttrsAt(offset)[0];
  }

  /** 该偏移所在段落的列表层级（0–2；非列表恒为 0） */
  paragraphIndentAt(offset: number): number {
    return this.paragraphAttrsAt(offset)[1];
  }

  /**
   * 设置段落种类（作用于 start..end 覆盖的所有段落）。
   * 进入列表时保留原层级；回到正文/标题时层级归零（层级只对列表有意义）。
   */
  setParagraphKind(kind: number, start: number, end: number): void {
    this.applyParagraphKind(kind, -1, start, end);
  }

  /**
   * 设置段落种类并**显式指定**列表层级（回车续列表用）。
   * 与 setParagraphKind 的区别只在层级来源：这里不读目标段落的旧层级，
   * 直接用调用方给的值（新段还没有任何标注，读旧值恒为 0，会把层级丢掉）。
   */
  setParagraphKindAndIndent(kind: number, indent: number, start: number, end: number): void {
    this.applyParagraphKind(kind, Math.max(0, Math.min(MAX_LIST_LEVEL, indent)), start, end);
  }

  /** 段落种类设置的统一实现；indentOverride < 0 表示沿用原层级 */
  private applyParagraphKind(kind: number, indentOverride: number, start: number, end: number): void {
    const target: number = Math.max(ParagraphKind.BODY, Math.min(ParagraphKind.TODO_DONE, Math.round(kind)));
    const lo: number = Math.max(0, Math.min(start, end));
    const hi: number = Math.max(start, end);
    if (this.textValue.length === 0) {
      this.applyPending(target, indentOverride >= 0 ? indentOverride : 0, 0);
      return;
    }
    const first: number[] = this.paragraphAttrsBounds(lo);
    const last: number[] = this.paragraphAttrsBounds(hi > lo ? hi - 1 : lo);
    const ps: number = first[0];
    const pe: number = last[1];
    if (pe <= ps) {
      // 文档末尾的空段落：没有字符可以承载标注，转成待生效属性
      this.applyPending(target, indentOverride >= 0 ? indentOverride : this.paragraphIndentAt(ps), ps);
      return;
    }
    let cursor: number = ps;
    while (cursor < pe) {
      const pb: number[] = this.paragraphAttrsBounds(cursor);
      const pEnd: number = Math.min(pb[1], pe);
      if (pEnd <= cursor) {
        break;
      }
      const indent: number = isListParagraph(target)
        ? (indentOverride >= 0 ? indentOverride : this.paragraphIndentAt(cursor))
        : 0;
      this.splitAt(cursor);
      this.splitAt(pEnd);
      this.applyParagraphOverRange(cursor, pEnd, target, indent);
      cursor = pEnd;
    }
    this.clearPending();
    this.normalizeRuns();
    // 选区右端到达文末、且末段是空段落时，"最后一段"没有字符可承载属性，
    // 走待生效路径 —— 否则"全选 + 点列表"之后在末尾继续输入得到的是正文，
    // 与"光标停在末尾再点列表"的行为不一致。
    if (hi >= this.textValue.length) {
      const tail: number[] = this.paragraphAttrsBounds(this.textValue.length);
      if (tail[1] <= tail[0]) {
        this.applyPending(target, indentOverride >= 0 ? indentOverride : this.paragraphIndentAt(tail[0]), tail[0]);
      }
    }
  }

  /** 调整该偏移所在列表段落的层级（delta = ±1，钳制 0..MAX_LIST_LEVEL）；非列表段无操作 */
  setIndent(offset: number, delta: number): void {
    if (delta === 0) {
      return;
    }
    const attrs: number[] = this.paragraphAttrsAt(offset);
    if (!isListParagraph(attrs[0])) {
      return;
    }
    const next: number = Math.max(0, Math.min(MAX_LIST_LEVEL, attrs[1] + delta));
    if (next === attrs[1]) {
      return;
    }
    const b: number[] = this.paragraphAttrsBounds(offset);
    if (b[1] <= b[0]) {
      this.applyPending(attrs[0], next, b[0]);
      return;
    }
    this.splitAt(b[0]);
    this.splitAt(b[1]);
    this.applyParagraphOverRange(b[0], b[1], attrs[0], next);
    this.normalizeRuns();
  }

  /** 切换该偏移所在待办段的完成态（待办 ⇄ 已完成）；非待办段设为待办 */
  toggleTodoAt(offset: number): void {
    const kind: number = this.paragraphKindAt(offset);
    if (kind === ParagraphKind.TODO) {
      this.setParagraphKind(ParagraphKind.TODO_DONE, offset, offset);
      return;
    }
    this.setParagraphKind(ParagraphKind.TODO, offset, offset);
  }

  /**
   * 该偏移所在段落的 [种类, 层级]（含空末段的待生效属性）。
   *
   * 只认"带段落语义"的 run（heading/indent 非 0）：加粗/斜体等行内标注
   * 也可能切出 heading=0 的分段，若按"第一个相交 run"取值，段首一旦出现
   * 一段加粗就会把整段的列表种类读成正文 —— 表现为符号与缩进静默消失、
   * 工具栏显示"正文"、Tab 改层级无反应。
   */
  private paragraphAttrsAt(offset: number): number[] {
    const c: number = this.clamp(offset);
    if (this.pendingOffsetValue >= 0 && c >= this.pendingOffsetValue) {
      return [this.pendingKindValue, this.pendingIndentValue];
    }
    const b: number[] = this.paragraphAttrsBounds(c);
    let fallback: number[] = [0, 0];
    let hasFallback: boolean = false;
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (r.endOffset <= b[0] || r.startOffset >= b[1]) {
        continue;
      }
      if (r.heading === 0 && r.indent === 0) {
        continue;
      }
      // 覆盖段落起点的 run 最权威（含"空段落只有换行符"的情形）
      if (r.startOffset <= b[0] && r.endOffset >= b[0]) {
        return [r.heading, r.indent];
      }
      if (!hasFallback) {
        fallback = [r.heading, r.indent];
        hasFallback = true;
      }
    }
    return hasFallback ? fallback : [0, 0];
  }

  /** 记录末段空段落的段落属性（下一次插入时落到新字符上） */
  private applyPending(kind: number, indent: number, offset: number): void {
    const level: number = isListParagraph(kind) ? Math.max(0, Math.min(MAX_LIST_LEVEL, indent)) : 0;
    if (kind === ParagraphKind.BODY && level === 0) {
      this.clearPending();
      return;
    }
    this.pendingKindValue = kind;
    this.pendingIndentValue = level;
    this.pendingOffsetValue = Math.max(0, offset);
    this.formatVersionValue += 1;
  }

  private clearPending(): void {
    if (this.pendingOffsetValue < 0) {
      return;
    }
    this.pendingOffsetValue = -1;
    this.pendingKindValue = -1;
    this.pendingIndentValue = 0;
    this.formatVersionValue += 1;
  }

  /** 插入文本时把待生效的段落属性落成真实标注（必须晚于 shiftRunsAtInsert） */
  private resolvePendingAt(offset: number, len: number): void {
    if (this.pendingOffsetValue < 0 || len <= 0 || offset !== this.pendingOffsetValue) {
      return;
    }
    this.runsValue.push(new FormatRun(offset, offset + len, false, false,
      this.pendingKindValue, this.pendingIndentValue));
    this.pendingOffsetValue = -1;
    this.pendingKindValue = -1;
    this.pendingIndentValue = 0;
    this.formatVersionValue += 1;
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
    const target: number = Math.max(ParagraphKind.BODY, Math.min(ParagraphKind.TODO_DONE, Math.round(level)));
    if (this.textValue.length === 0) {
      this.setParagraphKind(this.paragraphKindAt(0) === target ? ParagraphKind.BODY : target, start, end);
      return;
    }
    const lo: number = Math.max(0, Math.min(start, end));
    const hi: number = Math.max(start, end);
    const first: number[] = this.paragraphAttrsBounds(lo);
    // 折叠光标属于其所在段；只有非空选区的右端点按半开区间回退一位。
    const last: number[] = this.paragraphAttrsBounds(hi > lo ? hi - 1 : lo);
    const ps: number = first[0];
    const pe: number = last[1];
    if (pe <= ps) {
      this.setParagraphKind(target, start, end);
      return;
    }
    let allOn: boolean = true;
    let cursor: number = ps;
    while (cursor < pe) {
      const pb: number[] = this.paragraphAttrsBounds(cursor);
      const pEnd: number = Math.min(pb[1], pe);
      if (pEnd <= cursor) {
        break;
      }
      if (this.paragraphAttrsAt(cursor)[0] !== target) {
        allOn = false;
      }
      cursor = pEnd;
    }
    this.setParagraphKind(allOn ? ParagraphKind.BODY : target, start, end);
  }

  /** 段落边界 [start,end]（不含换行符） */
  paragraphBounds(offset: number): number[] {
    const c: number = Math.max(0, Math.min(offset, this.textValue.length));
    // c === 0 时**不能**调 lastIndexOf('\n', -1)：JS 会把负的 fromIndex 夹到 0，
    // 于是"文档以换行开头"会命中位置 0、算出 start=1 > end=0 的非法区间
    // （首段属性读写全错、排版把空首行读成第二段的样式）。
    let start: number = 0;
    if (c > 0) {
      const prevBreak: number = this.textValue.lastIndexOf('\n', c - 1);
      start = prevBreak < 0 ? 0 : prevBreak + 1;
    }
    const nextBreak: number = this.textValue.indexOf('\n', c);
    const end: number = nextBreak < 0 ? this.textValue.length : nextBreak;
    return [Math.min(start, end), end];
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

  /** 把 [a,b) 内所有分段统一设为某段落种类与层级（缺失分段在非正文时补建） */
  private applyParagraphOverRange(a: number, b: number, kind: number, indent: number): void {
    const bounds: number[] = this.collectBounds(a, b);
    for (let i = 0; i + 1 < bounds.length; i++) {
      const s: number = bounds[i];
      const e: number = bounds[i + 1];
      if (e <= s) {
        continue;
      }
      const r: FormatRun | null = this.findRunExact(s, e);
      if (r === null) {
        if (kind === ParagraphKind.BODY && indent === 0) {
          continue;
        }
        this.runsValue.push(new FormatRun(s, e, false, false, kind, indent));
      } else {
        r.heading = kind;
        r.indent = indent;
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
      list.push(new FormatRun(s, e, r.bold, r.italic, r.heading, r.indent));
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
        out.push(new FormatRun(s, e, r.bold, r.italic, r.heading, r.indent));
      }
    }
    this.runsValue = out;
    this.normalizeRuns();
  }

  /** 把段落属性强制重铺到 offset 所在段落（合并段落时统一属性用） */
  private applyParagraphAttrsAt(offset: number, attrs: number[]): void {
    const b: number[] = this.paragraphAttrsBounds(offset);
    if (b[1] <= b[0]) {
      this.applyPending(attrs[0], attrs[1], b[0]);
      return;
    }
    this.splitAt(b[0]);
    this.splitAt(b[1]);
    this.applyParagraphOverRange(b[0], b[1], attrs[0], attrs[1]);
    this.normalizeRuns();
  }

  /**
   * 删除后补回被删空的段落属性（只针对删除点所在段落）。
   * 中间的空段落还有 '\n' 可承载，直接补 run；文档末尾的空段落没有字符，
   * 转成待生效属性，等第一批字符落下时再生效。
   */
  private restoreParagraphAttrsAfterDelete(offset: number, attrs: number[]): void {
    if (attrs[0] === 0 && attrs[1] === 0) {
      return;
    }
    const b: number[] = this.paragraphAttrsBounds(offset);
    if (this.paragraphAttrsAt(offset)[0] !== 0) {
      return;
    }
    if (b[1] > b[0]) {
      this.runsValue.push(new FormatRun(b[0], b[1], false, false, attrs[0], attrs[1]));
      this.formatVersionValue += 1;
      return;
    }
    this.applyPending(attrs[0], attrs[1], b[0]);
  }

  /** 把"空末段待生效段落属性"搬到另一份文档（IME 预上屏克隆；瞬态状态，不进历史/存储） */
  copyPendingStateTo(target: TextDocument): void {
    if (this.pendingOffsetValue < 0) {
      return;
    }
    target.applyPending(this.pendingKindValue, this.pendingIndentValue, this.pendingOffsetValue);
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
