/**
 * FlowText 字形级排版引擎
 *
 * 封装 @ohos.graphics.text：构建段落 → 行排版器（LineTypeset）→ 按宽度断行 →
 * 提取字形数据（getGlyphs / getFont / getAdvances），输出可绘制/可插值的布局结构。
 *
 * 单位约定（2026-08-23 决策：内部全量 vp）：
 *   - 对外接口（构造参数与输出 LayoutLine/GlyphRun 坐标）全部为 vp；
 *   - text 模块是 px 原生接口（TextStyle.fontSize、getAdvances、getLineBreak 宽度均为 px），
 *     在本类适配层内统一 vp↔px 换算，px 被隔离在本类内部。
 *   - 字体对象（drawing.Font）保持引擎返回的 px 尺寸：字形物理大小 = fontSizeVp*density px，
 *     在 vp 坐标系中恰好等于期望的 vp 字号，视觉一致。
 */
import { text, drawing, common2D } from '@kit.ArkGraphics2D';
import { FormatRun } from '../model/EditorTypes';
import { TextIndexMap } from '../model/TextIndexMap';

/** 字形段：同一字体样式的连续字形（坐标为 vp） */
export class GlyphRunData {
  glyphs: number[] = [];
  font: drawing.Font | null = null;
  /** 逐字形宽高（vp） */
  advances: common2D.Point[] = [];
  /** 逐字形绘制坐标（相对 run 起点，vp） */
  positions: common2D.Point[] = [];
  /** run 首个字形对应的文本偏移（UTF-16 code unit） */
  textStart: number = 0;
  /**
   * 逐字形对应的**码元起始偏移**（相对 textStart，UTF-16 code unit）。
   *
   * 为什么必须逐字形记录而不能用 `textStart + 字形下标` 推算：
   * 一个字形不一定对应一个码元。emoji / 增补平面字符占 2 个码元但只渲染 1 个字形，
   * 于是 `textStart + g` 会从emoji 起整体错位——后面所有字形的索引都偏小，
   * 表现为「点击定位偏左、选区边界画错、动画错位」。
   * 由排版结果反推真实偏移是唯一可靠来源。
   */
  glyphOffsets: number[] = [];
  /** 对应文本区间（UTF-16 code unit索引） */
  textEnd: number = 0;
  /** run 在行内的起始 x（vp） */
  runOffsetX: number = 0;

  width(): number {
    if (this.advances.length === 0) {
      return 0;
    }
    const last = this.advances[this.advances.length - 1];
    return this.positions[this.positions.length - 1].x + last.x;
  }

  /**
   * 码元偏移 → run 内字形下标；该偏移落在当前字形范围内则返回其下标，
   * 否则返回 -1。命中测试与光标定位据此把码元位置映射到具体字形。
   */
  glyphIndexAt(offset: number): number {
    for (let g: number = 0; g < this.glyphOffsets.length; g++) {
      const start: number = this.textStart + this.glyphOffsets[g];
      const nextStart: number = g + 1 < this.glyphOffsets.length
        ? this.textStart + this.glyphOffsets[g + 1]
        : this.textEnd;
      if (offset >= start && offset < nextStart) {
        return g;
      }
    }
    return -1;
  }

  /** 字形下标 → 该字形之后的码元偏移（光标停在字形之后的位置） */
  offsetAfterGlyph(g: number): number {
    if (g < 0 || g >= this.glyphOffsets.length) {
      return this.textEnd;
    }
    const isLast: boolean = g === this.glyphOffsets.length - 1;
    return this.textStart + (isLast ? (this.textEnd - this.textStart) : this.glyphOffsets[g + 1]);
  }
}

/** 排版行（坐标为 vp） */
export class LayoutLine {
  startIndex: number = 0;
  endIndex: number = 0;
  /** 行顶 y（vp，相对编辑区内容顶部） */
  yOffset: number = 0;
  /** 行高（vp，不含行距） */
  height: number = 0;
  /** 行步进（vp，= 行高 + 行距，用于命中测试覆盖行间距区域） */
  step: number = 0;
  /** 行内容宽度（vp） */
  width: number = 0;
  /** 行内字形基线（vp，内容坐标 = yOffset + 基线偏移），绘制与命中统一使用 */
  baseline: number = 0;
  runs: GlyphRunData[] = [];
  consumedEnd: number = 0;
  nativeLine: text.TextLine | null = null;
  indexMap: TextIndexMap = new TextIndexMap();
  nativeStartIndex: number = 0;
  pxPerVp: number = 1;
  ascent: number = 0;
  descent: number = 0;
}

export class TextLayoutEngine {
  private fontCollection: text.FontCollection;
  private maxWidthPx: number;
  private fontSizePx: number;
  private lineHeightPx: number;
  private lineSpacingPx: number;
  private pxPerVp: number;
  private textColor: common2D.Color;
  /** 当前格式标注（T021）：布局按此分段套用差异化样式 */
  private runsValue: FormatRun[] = [];
  private indexMap: TextIndexMap = new TextIndexMap();
  /** 分词用段落对象（懒建、按文本缓存），用于双击/长按选词 */
  private wordParagraph: text.Paragraph | null = null;
  private wordParagraphText: string = '';

  /** 构造参数（maxWidthVp 等）与行度量均为 vp；pxPerVp = uiContext.vp2px(1) */
  constructor(maxWidthVp: number, fontSizeVp: number, lineHeightVp: number, lineSpacingVp: number, pxPerVp: number) {
    this.pxPerVp = pxPerVp > 0 ? pxPerVp : 1;
    this.maxWidthPx = maxWidthVp * this.pxPerVp;
    this.fontSizePx = fontSizeVp * this.pxPerVp;
    this.lineHeightPx = lineHeightVp * this.pxPerVp;
    this.lineSpacingPx = lineSpacingVp * this.pxPerVp;
    this.fontCollection = text.FontCollection.getGlobalInstance();
    this.textColor = { alpha: 255, red: 31, green: 35, blue: 41 };
  }

  /** 更新格式标注（T021）；通常在重建引擎或格式变化后调用 */
  setRuns(runs: FormatRun[]): void {
    this.runsValue = runs;
  }

  /**
   * 取 offset 处单词的 [start,end]（ICU 词边界，与 Android/iOS 双击选词同源）。
   * 段落对象懒建并按文本缓存；失败/无能力时返回空数组，由调用方回退启发式。
   */
  wordRangeAt(content: string, offset: number): number[] {
    try {
      if (this.wordParagraph === null || this.wordParagraphText !== content) {
        const style: text.TextStyle = { fontSize: this.fontSizePx, color: this.textColor };
        const paragraphStyle: text.ParagraphStyle = { textStyle: style };
        const builder = new text.ParagraphBuilder(paragraphStyle, this.fontCollection);
        builder.addText(content);
        this.wordParagraph = builder.build();
        this.wordParagraphText = content;
      }
      const r: text.Range = this.wordParagraph.getWordBoundary(offset);
      return [r.start, r.end];
    } catch (e) {
      return [];
    }
  }

  /** 标题级别对应的字号（px）；非标题返回基准字号 */
  private fontSizeForOffset(offset: number): number {
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      if (offset >= r.startOffset && offset < r.endOffset) {
        if (r.heading === 1) {
          return this.fontSizePx * 1.6;
        }
        if (r.heading === 2) {
          return this.fontSizePx * 1.35;
        }
        if (r.heading === 3) {
          return this.fontSizePx * 1.15;
        }
        return this.fontSizePx;
      }
    }
    return this.fontSizePx;
  }

  /** 把一个格式标注转为 text 样式（粗=W700 / 斜=ITALIC / 标题=放大字号） */
  private styleFor(r: FormatRun): text.TextStyle {
    const st: text.TextStyle = { fontSize: this.fontSizeForOffset(r.startOffset), color: this.textColor };
    if (r.bold) {
      st.fontWeight = text.FontWeight.W700;
    }
    if (r.italic) {
      st.fontStyle = text.FontStyle.ITALIC;
    }
    return st;
  }

  /** 构建行排版器（成本低，~2ms），供 LayoutCache 增量断行复用；按格式分段套用样式（T021） */
  buildTypeset(content: string): text.LineTypeset {
    this.indexMap = new TextIndexMap(content);
    const baseStyle: text.TextStyle = {
      fontSize: this.fontSizePx,
      color: this.textColor
    };
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: baseStyle
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, this.fontCollection);
    if (this.runsValue.length === 0) {
      builder.addText(content);
      return builder.buildLineTypeset();
    }
    // 分段添加：格式区间 pushStyle，其余用基准样式；保证字形 run 在格式边界处断开
    let cursor: number = 0;
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      const s: number = Math.max(cursor, Math.min(r.startOffset, content.length));
      const e: number = Math.min(r.endOffset, content.length);
      if (s > cursor) {
        builder.addText(content.substring(cursor, s));
      }
      if (e > s) {
        builder.pushStyle(this.styleFor(r));
        builder.addText(content.substring(s, e));
        builder.popStyle();
        cursor = e;
      }
    }
    if (cursor < content.length) {
      builder.addText(content.substring(cursor));
    }
    return builder.buildLineTypeset();
  }

  /** 排版宽度（px，供 LayoutCache 调 getLineBreak） */
  contentMaxWidthPx(): number {
    return this.maxWidthPx;
  }

  /** Native LineTypeset/Run indices count scalars; document/IME offsets count UTF-16. */
  lineBreak(typeset: text.LineTypeset, start: number): number {
    const nativeStart: number = this.indexMap.toScalar(start);
    const count: number = typeset.getLineBreak(nativeStart, this.maxWidthPx);
    return this.indexMap.fromScalar(nativeStart + count) - start;
  }
  createLayoutLine(typeset: text.LineTypeset, start: number, count: number, y: number): LayoutLine {
    const nativeStart: number = this.indexMap.toScalar(start);
    const nativeCount: number = this.indexMap.toScalar(start + count) - nativeStart;
    return this.buildLayoutLine(typeset.createLine(nativeStart, nativeCount), start, count, y);
  }

  /** 行步进（行高+行距，vp） */
  lineStepVp(): number {
    return (this.lineHeightPx + this.lineSpacingPx) / this.pxPerVp;
  }

  /** 从指定排版区间构建一行（输出 vp；公开供 LayoutCache 增量调用） */
  buildLayoutLineFrom(line: text.TextLine, textStart: number, count: number, yOffsetVp: number): LayoutLine {
    return this.buildLayoutLine(line, textStart, count, yOffsetVp);
  }

  /** Empty paragraphs also have a caret and occupy one line. */
  emptyLine(offset: number, y: number): LayoutLine {
    const line: LayoutLine = new LayoutLine();
    line.startIndex = offset;
    line.endIndex = offset;
    line.consumedEnd = offset;
    line.yOffset = y;
    line.height = this.lineHeightPx / this.pxPerVp;
    line.step = this.lineStepVp();
    line.ascent = this.fontSizePx * 0.8 / this.pxPerVp;
    line.descent = this.fontSizePx * 0.2 / this.pxPerVp;
    line.baseline = y + (line.height - line.ascent - line.descent) / 2 + line.ascent;
    return line;
  }

  private buildLayoutLine(line: text.TextLine, textStart: number, count: number, yOffsetVp: number): LayoutLine {
    const layoutLine: LayoutLine = new LayoutLine();
    const bounds: text.TypographicBounds = line.getTypographicBounds();
    layoutLine.startIndex = textStart;
    layoutLine.endIndex = textStart + count;
    layoutLine.consumedEnd = layoutLine.endIndex;
    layoutLine.nativeLine = line;
    layoutLine.indexMap = this.indexMap.slice(textStart, textStart + count);
    layoutLine.nativeStartIndex = this.indexMap.toScalar(textStart);
    layoutLine.pxPerVp = this.pxPerVp;
    layoutLine.yOffset = yOffsetVp;
    layoutLine.ascent = Math.abs(bounds.ascent) / this.pxPerVp;
    layoutLine.descent = Math.abs(bounds.descent) / this.pxPerVp;
    const naturalHeight: number = layoutLine.ascent + layoutLine.descent + Math.max(0, bounds.leading) / this.pxPerVp;
    layoutLine.height = Math.max(this.lineHeightPx / this.pxPerVp *
      this.fontSizeForOffset(textStart) / this.fontSizePx, naturalHeight);
    layoutLine.step = layoutLine.height + this.lineSpacingPx / this.pxPerVp;
    layoutLine.baseline = yOffsetVp + (layoutLine.height - layoutLine.ascent - layoutLine.descent) / 2 + layoutLine.ascent;
    layoutLine.width = bounds.width / this.pxPerVp;
    const runs: text.Run[] = line.getGlyphRuns();
    for (let i: number = 0; i < runs.length; i++) {
      const run: text.Run = runs[i];
      const range: text.Range = run.getStringRange();
      const indices: number[] = run.getStringIndices();
      const positions: common2D.Point[] = run.getPositions();
      const data: GlyphRunData = new GlyphRunData();
      data.glyphs = run.getGlyphs();
      data.font = run.getFont();
      data.textStart = this.indexMap.fromScalar(range.start);
      // Run APIs use end as LENGTH, unlike the document's end-exclusive ranges.
      data.textEnd = this.indexMap.fromScalar(range.start + range.end);
      data.glyphOffsets = indices.map((index: number): number => this.indexMap.fromScalar(index) - data.textStart);
      data.runOffsetX = 0; // Native positions are relative to the line, including bidi placement.
      const advances: common2D.Point[] = run.getAdvances({ start: 0, end: data.glyphs.length });
      for (let g: number = 0; g < data.glyphs.length; g++) {
        data.advances.push({ x: advances[g].x / this.pxPerVp, y: advances[g].y / this.pxPerVp });
        data.positions.push({ x: positions[g].x / this.pxPerVp, y: positions[g].y / this.pxPerVp });
      }
      layoutLine.runs.push(data);
    }
    return layoutLine;
  }
}
