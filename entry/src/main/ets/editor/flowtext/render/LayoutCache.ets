/** Versioned, lazy paragraph layout. Coordinates are vp. */
import { text } from '@kit.ArkGraphics2D';
import { TextLayoutEngine, LayoutLine } from './TextLayoutEngine';
import { FormatRun } from '../model/EditorTypes';
import { GraphemeUtil } from '../model/GraphemeUtil';

export class LayoutCache {
  private engine: TextLayoutEngine;
  private textValue: string = '';
  private versionValue: number = -1;
  private formatVersionValue: number = -1;
  private typeset: text.LineTypeset | null = null;
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
    this.typeset = null;
    this.complete = false;
  }

  invalidate(): void {
    this.typeset = null;
    this.lines = [];
    this.nextStart = 0;
    this.nextY = 0;
    this.complete = false;
  }

  private synchronize(content: string, version: number, formatVersion: number): void {
    if (content !== this.textValue || version !== this.versionValue || formatVersion !== this.formatVersionValue) {
      this.invalidate();
      this.textValue = content;
      this.versionValue = version;
      this.formatVersionValue = formatVersion;
    }
  }

  private appendLine(): void {
    const start: number = this.nextStart;
    let line: LayoutLine;
    if (start >= this.textValue.length) {
      line = this.engine.emptyLine(start, this.nextY);
      this.complete = true;
    } else {
      if (this.typeset === null) { this.typeset = this.engine.buildTypeset(this.textValue); }
      const newline: number = this.textValue.indexOf('\n', start);
      const paragraphEnd: number = newline < 0 ? this.textValue.length :
        (newline > start && this.textValue.charAt(newline - 1) === '\r' ? newline - 1 : newline);
      let count: number = Math.min(this.engine.lineBreak(this.typeset, start), paragraphEnd - start);
      count = GraphemeUtil.snapToBoundary(this.textValue, start + count) - start;
      if (count <= 0 && paragraphEnd > start) { count = GraphemeUtil.moveRight(this.textValue, start) - start; }
      const end: number = start + count;
      line = count === 0 ? this.engine.emptyLine(start, this.nextY) :
        this.engine.createLayoutLine(this.typeset, start, count, this.nextY);
      line.consumedEnd = end === paragraphEnd && newline >= 0 ? newline + 1 : end;
      this.nextStart = line.consumedEnd;
      this.complete = this.nextStart >= this.textValue.length && newline < 0;
    }
    this.lines.push(line);
    this.nextY += line.step;
  }
}
