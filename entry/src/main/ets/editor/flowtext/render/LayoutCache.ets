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

/**
 * 段落属性查询：(段落起点偏移) → [种类, 层级]。
 * 由编辑器注入（数据在 TextDocument），排版层只消费结果，
 * 不自己持有文档，避免出现"两份段落状态"。
 */
export type ParagraphInfoProvider = (offset: number) => number[];

/** A bounded layout pass reports whether the requested viewport or offset is ready. */
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
  /** 段落属性来源（未注入时按正文排版） */
  private paraProvider: ParagraphInfoProvider | null = null;
  private nextStart: number = 0;
  private nextY: number = 0;
  private complete: boolean = false;

  constructor(engine: TextLayoutEngine) { this.engine = engine; }
  get version(): number { return this.versionValue; }
  get height(): number { return this.nextY; }
  lineCount(): number { return this.lines.length; }
  isComplete(): boolean { return this.complete; }
  setRuns(runs: FormatRun[]): void { this.engine.setRuns(runs); }

  coversOffset(offset: number): boolean {
    const at: number = Math.max(0, Math.min(offset, this.textValue.length));
    // Equality can still be the next visual line's start at a soft wrap.
    return this.lines.length > 0 && (this.complete || this.nextStart > at);
  }

  coversY(untilYVp: number): boolean {
    return this.lines.length > 0 && (this.complete || this.nextY >= untilYVp);
  }

  /** 注入段落属性来源；列表/待办段落的缩进与项目符号靠它生效 */
  setParagraphProvider(provider: ParagraphInfoProvider): void { this.paraProvider = provider; }

  private paragraphInfoAt(offset: number): number[] {
    if (this.paraProvider === null) {
      return [0, 0];
    }
    const info: number[] = this.paraProvider(offset);
    if (info.length < 2) {
      return [0, 0];
    }
    return info;
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

  ensureLayoutIncremental(content: string, version: number, formatVersion: number, untilYVp: number,
    maxLines: number = 64, budgetMs: number = 6): LayoutProgress {
    this.synchronize(content, version, formatVersion);
    return this.appendWithinBudget(untilYVp, -1, maxLines, budgetMs);
  }

  ensureOffsetIncremental(content: string, version: number, formatVersion: number, offset: number,
    maxLines: number = 64, budgetMs: number = 6): LayoutProgress {
    this.synchronize(content, version, formatVersion);
    return this.appendWithinBudget(-1, Math.max(0, Math.min(offset, content.length)), maxLines, budgetMs);
  }

  /** Preview owns its window map; retained prefix lines are immutable and can be shared. */
  forkForEdit(content: string, version: number, formatVersion: number, runs: FormatRun[], offset: number,
    provider: ParagraphInfoProvider | null = null): LayoutCache {
    const fork: LayoutCache = new LayoutCache(this.engine.cloneConfiguration());
    fork.textValue = this.textValue;
    fork.versionValue = this.versionValue;
    fork.formatVersionValue = this.formatVersionValue;
    fork.lines = this.lines.slice();
    fork.nextStart = this.nextStart;
    fork.nextY = this.nextY;
    fork.complete = this.complete;
    // A preview document can have different pending/list attributes from the committed one.
    fork.paraProvider = provider === null ? this.paraProvider : provider;
    fork.applyEdit(content, version, formatVersion, runs, offset);
    return fork;
  }

  private appendWithinBudget(untilYVp: number, offset: number, maxLines: number,
    budgetMs: number): LayoutProgress {
    const limit: number = Number.isFinite(maxLines) ? Math.max(1, Math.floor(maxLines)) : 64;
    const duration: number = Number.isFinite(budgetMs) ? Math.max(0, budgetMs) : 6;
    const started: number = Date.now();
    let appended: number = 0;
    let reached: boolean = offset >= 0 ? this.coversOffset(offset) : this.coversY(untilYVp);
    while (!this.complete && !reached && appended < limit) {
      this.appendLine();
      appended++;
      reached = offset >= 0 ? this.coversOffset(offset) : this.coversY(untilYVp);
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
    // 段落属性按**段落起点**取：软折行的续行与首行必须同种类同层级，
    // 否则一条长列表项的第二行会退回正文样式。
    const paragraphStart: number = LayoutCache.paragraphStartOf(this.textValue, start);
    const info: number[] = this.paragraphInfoAt(paragraphStart);
    const paraKind: number = info[0];
    const paraIndent: number = info[1];
    // 项目符号只画在段落第一条视觉行上（悬挂缩进：续行的文字列与首行对齐）
    const markerOn: boolean = start === paragraphStart;
    let line: LayoutLine;
    if (start >= this.textValue.length) {
      line = this.engine.emptyLine(start, this.nextY, paraKind, paraIndent);
      this.complete = true;
    } else {
      this.ensureWindow();
      const typeset: text.LineTypeset | null = this.typeset;
      if (typeset === null) {
        // 理论上不可达：ensureWindow 必然建出 typeset。留此分支只为避免死循环。
        line = this.engine.emptyLine(start, this.nextY, paraKind, paraIndent);
        this.complete = true;
      } else {
        const newline: number = this.textValue.indexOf('\n', start);
        const paragraphEnd: number = newline < 0 ? this.textValue.length :
          (newline > start && this.textValue.charAt(newline - 1) === '\r' ? newline - 1 : newline);
        // 列表段落要给项目符号槽位与层级缩进让出宽度，否则折行后整体右移会溢出右边界
        const availablePx: number = this.engine.availableWidthPx(paraKind, paraIndent);
        let count: number = Math.min(this.engine.lineBreak(typeset, start, availablePx), paragraphEnd - start);
        count = GraphemeUtil.snapToBoundary(this.textValue, start + count) - start;
        if (count <= 0 && paragraphEnd > start) { count = GraphemeUtil.moveRight(this.textValue, start) - start; }
        const end: number = start + count;
        line = count === 0 ? this.engine.emptyLine(start, this.nextY, paraKind, paraIndent) :
          this.engine.createLayoutLine(typeset, start, count, this.nextY, paraKind, paraIndent, markerOn);
        line.consumedEnd = end === paragraphEnd && newline >= 0 ? newline + 1 : end;
        this.nextStart = line.consumedEnd;
        this.complete = this.nextStart >= this.textValue.length && newline < 0;
      }
    }
    this.lines.push(line);
    this.nextY += line.step;
  }
}
