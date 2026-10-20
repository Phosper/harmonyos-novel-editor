/**
 * Versioned, lazy paragraph layout. Coordinates are vp.
 *
 * typeset 以**段落对齐的窗口**构建，而不是整篇：
 * 旧实现每次 invalidateFrom 之后都用整篇文本重建 LineTypeset，等于每敲一个字
 * 都做一次 O(文档) 的 JS + 原生排版（TextIndexMap 整篇重建 + 原生为整篇建字型 run），
 * 与项目自定规范 R9「避免整篇 typeset」直接冲突。
 * 窗口化的正确性前提：窗口起止都取段落边界，因此一行永远不会跨窗口边界，
 * 窗口内的断行结果与整篇排版完全一致。
 */
import { text } from '@kit.ArkGraphics2D';
import { TextLayoutEngine, LayoutLine } from './TextLayoutEngine';
import { FormatRun } from '../model/EditorTypes';
import { GraphemeUtil } from '../model/GraphemeUtil';

/**
 * typeset 窗口的最小跨度（码元），并向外取整到段落边界。
 * 越大 → 重建次数越少但单次越贵。4000 码元约十几个段落、两三千字形，
 * 相对 5 万字文稿把单次重建成本压到约 1/12。
 */
const WINDOW_MIN_CHARS: number = 4000;

/** One bounded layout slice. A native line/window remains an indivisible unit. */
export class LayoutProgress {
  lines: LayoutLine[];
  reached: boolean;
  complete: boolean;
  appendedLines: number;

  constructor(lines: LayoutLine[], reached: boolean, complete: boolean, appendedLines: number) {
    this.lines = lines;
    this.reached = reached;
    this.complete = complete;
    this.appendedLines = appendedLines;
  }
}

export class LayoutCache {
  private engine: TextLayoutEngine;
  private textValue: string = '';
  private versionValue: number = -1;
  private formatVersionValue: number = -1;
  private typeset: text.LineTypeset | null = null;
  /** 当前 typeset 覆盖的文档区间 [windowBase, windowEnd)，两端都在段落边界上 */
  private windowBase: number = -1;
  private windowEnd: number = -1;
  private lines: LayoutLine[] = [];
  private nextStart: number = 0;
  private nextY: number = 0;
  private complete: boolean = false;

  constructor(engine: TextLayoutEngine) { this.engine = engine; }
  get version(): number { return this.versionValue; }
  get height(): number { return this.nextY; }
  lineCount(): number { return this.lines.length; }
  isComplete(): boolean { return this.complete; }
  setRuns(runs: FormatRun[]): void { this.engine.setRuns(runs); }

  /** At a soft-wrap boundary the following line is needed for the downstream caret. */
  coversOffset(offset: number): boolean {
    const at: number = Math.max(0, Math.min(offset, this.textValue.length));
    return this.lines.length > 0 && (this.complete || this.nextStart > at);
  }

  coversY(y: number): boolean {
    return this.lines.length > 0 && (this.complete || this.nextY >= y);
  }

  ensureLayout(content: string, version: number, formatVersion: number, untilYVp: number): LayoutLine[] {
    this.synchronize(content, version, formatVersion);
    while (!this.complete && (this.lines.length === 0 || this.nextY < untilYVp)) { this.appendLine(); }
    return this.lines;
  }

  ensureOffset(content: string, version: number, formatVersion: number, offset: number): LayoutLine[] {
    this.synchronize(content, version, formatVersion);
    while (!this.complete && (this.lines.length === 0 || this.nextStart <= offset)) { this.appendLine(); }
    return this.lines;
  }

  ensureLayoutIncremental(content: string, version: number, formatVersion: number,
    untilYVp: number, maxLines: number = 64, budgetMs: number = 6): LayoutProgress {
    this.synchronize(content, version, formatVersion);
    return this.appendWithinBudget(untilYVp, 0, false, maxLines, budgetMs);
  }

  ensureOffsetIncremental(content: string, version: number, formatVersion: number,
    offset: number, maxLines: number = 64, budgetMs: number = 6): LayoutProgress {
    this.synchronize(content, version, formatVersion);
    return this.appendWithinBudget(0, offset, true, maxLines, budgetMs);
  }

  /**
   * Fork for an edit without rebuilding unchanged paragraphs. The caller supplies
   * the earliest possibly changed text/format offset; preceding paragraphs must
   * be identical. Line objects retain identity, while the array and all mutable
   * engine/window state belong to the fork. Repeated previews can call applyEdit
   * on their existing fork rather than copying the committed cache again.
   */
  forkForEdit(content: string, version: number, formatVersion: number,
    runs: FormatRun[], offset: number): LayoutCache {
    const fork: LayoutCache = new LayoutCache(this.engine.cloneConfiguration());
    fork.textValue = this.textValue;
    fork.versionValue = this.versionValue;
    fork.formatVersionValue = this.formatVersionValue;
    fork.lines = this.lines.slice();
    fork.nextStart = this.nextStart;
    fork.nextY = this.nextY;
    fork.complete = this.complete;
    fork.applyEdit(content, version, formatVersion, runs, offset);
    return fork;
  }

  /** Always make progress, then yield at either bound; callers schedule the next slice. */
  private appendWithinBudget(untilYVp: number, offset: number, forOffset: boolean,
    maxLines: number, budgetMs: number): LayoutProgress {
    const limit: number = Number.isFinite(maxLines) ? Math.max(1, Math.floor(maxLines)) : 64;
    const duration: number = Number.isFinite(budgetMs) ? Math.max(0, budgetMs) : 6;
    const started: number = Date.now();
    let appended: number = 0;
    let reached: boolean = forOffset ? this.coversOffset(offset) : this.coversY(untilYVp);
    while (!reached && appended < limit) {
      this.appendLine();
      appended++;
      reached = forOffset ? this.coversOffset(offset) : this.coversY(untilYVp);
      if (Date.now() - started >= duration) { break; }
    }
    return new LayoutProgress(this.lines, reached, this.complete, appended);
  }

  /** Accept content and shifted format runs atomically; retain unaffected paragraphs. */
  applyEdit(content: string, version: number, formatVersion: number, runs: FormatRun[], offset: number): void {
    const at: number = Math.max(0, offset);
    const paragraphStart: number = at === 0 ? 0 : this.textValue.lastIndexOf('\n', at - 1) + 1;
    this.invalidateFrom(paragraphStart);
    this.textValue = content;
    this.versionValue = version;
    this.formatVersionValue = formatVersion;
    this.engine.setRuns(runs);
  }

  invalidateFrom(offset: number): void {
    let cut: number = 0;
    while (cut < this.lines.length && this.lines[cut].consumedEnd <= offset && this.lines[cut].startIndex < offset) { cut++; }
    this.lines = this.lines.slice(0, cut);
    const last: LayoutLine | null = cut > 0 ? this.lines[cut - 1] : null;
    this.nextStart = last === null ? 0 : last.consumedEnd;
    this.nextY = last === null ? 0 : last.yOffset + last.step;
    this.dropWindow();
    this.complete = false;
  }

  invalidate(): void {
    this.dropWindow();
    this.lines = [];
    this.nextStart = 0;
    this.nextY = 0;
    this.complete = false;
  }

  private dropWindow(): void {
    this.typeset = null;
    this.windowBase = -1;
    this.windowEnd = -1;
  }

  private synchronize(content: string, version: number, formatVersion: number): void {
    if (content !== this.textValue || version !== this.versionValue || formatVersion !== this.formatVersionValue) {
      this.invalidate();
      this.textValue = content;
      this.versionValue = version;
      this.formatVersionValue = formatVersion;
    }
  }

  /**
   * 确保当前 typeset 覆盖 nextStart 所在的段落。
   * 起点取 nextStart 所在段落的开头（一定是码元边界：'\n' 是 ASCII），
   * 终点取 nextStart + WINDOW_MIN_CHARS 之后的第一个段落边界 —— 于是窗口
   * 永远是若干**完整段落**，窗口内断行与整篇排版等价。
   */
  private ensureWindow(): void {
    if (this.typeset !== null && this.nextStart >= this.windowBase && this.nextStart < this.windowEnd) {
      return;
    }
    const len: number = this.textValue.length;
    const base: number = LayoutCache.paragraphStartOf(this.textValue, this.nextStart);
    let end: number = Math.min(len, this.nextStart + WINDOW_MIN_CHARS);
    if (end < len) {
      const nl: number = this.textValue.indexOf('\n', end);
      end = nl < 0 ? len : nl + 1;
    }
    if (end <= base) {
      end = len;
    }
    this.typeset = this.engine.buildTypesetWindow(this.textValue, base, end);
    this.windowBase = base;
    this.windowEnd = end;
  }

  /** offset 所在段落的起点（段落以 '\n' 分隔） */
  private static paragraphStartOf(value: string, offset: number): number {
    if (offset <= 0) {
      return 0;
    }
    const nl: number = value.lastIndexOf('\n', offset - 1);
    return nl < 0 ? 0 : nl + 1;
  }

  private appendLine(): void {
    const start: number = this.nextStart;
    let line: LayoutLine;
    if (start >= this.textValue.length) {
      line = this.engine.emptyLine(start, this.nextY);
      this.complete = true;
    } else {
      this.ensureWindow();
      const typeset: text.LineTypeset | null = this.typeset;
      if (typeset === null) {
        // 理论上不可达：ensureWindow 必然建出 typeset。留此分支只为避免死循环。
        line = this.engine.emptyLine(start, this.nextY);
        this.complete = true;
      } else {
        const newline: number = this.textValue.indexOf('\n', start);
        const paragraphEnd: number = newline < 0 ? this.textValue.length :
          (newline > start && this.textValue.charAt(newline - 1) === '\r' ? newline - 1 : newline);
        let count: number = Math.min(this.engine.lineBreak(typeset, start), paragraphEnd - start);
        count = GraphemeUtil.snapToBoundary(this.textValue, start + count) - start;
        if (count <= 0 && paragraphEnd > start) { count = GraphemeUtil.moveRight(this.textValue, start) - start; }
        const end: number = start + count;
        line = count === 0 ? this.engine.emptyLine(start, this.nextY) :
          this.engine.createLayoutLine(typeset, start, count, this.nextY);
        line.consumedEnd = end === paragraphEnd && newline >= 0 ? newline + 1 : end;
        this.nextStart = line.consumedEnd;
        this.complete = this.nextStart >= this.textValue.length && newline < 0;
      }
    }
    this.lines.push(line);
    this.nextY += line.step;
  }
}
