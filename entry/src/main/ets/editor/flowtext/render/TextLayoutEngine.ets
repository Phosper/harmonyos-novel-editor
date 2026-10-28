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
import { FormatRun, MAX_LIST_LEVEL, ParagraphKind, isListParagraph } from '../model/EditorTypes';
import { TextIndexMap } from '../model/TextIndexMap';

/** 列表每层缩进步长（vp） */
const LIST_INDENT_STEP_VP: number = 24;
/** 项目符号槽宽 = 字号 × 该比例（保证 • / ○ / ✓ 不压到正文） */
const MARKER_WIDTH_RATIO: number = 1.2;

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
  /**
   * 整段字形的 **TextBlob 缓存**（绘制器惰性填充）。
   *
   * 缓存放在数据上而不是绘制器里，是因为它的生命周期正好等于这一份排版结果：
   * 布局重建 → 新 GlyphRunData → 缓存自然失效。Draw 热路径（光标弹簧动画、
   * 闪烁、惯性滚动都以 60fps 调 draw）因此不必每帧重建 TextBlob。
   * 含动画字形的 run 需要剔除后重绘，那条路径不读这个缓存。
   */
  blob: drawing.TextBlob | null = null;

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
  /** 本行的 UTF-16 偏移与 Unicode scalar 下标转换，不保留窗口或全文映射。 */
  indexMap: TextIndexMap = new TextIndexMap();
  /** 原生 TextLine 自己的 scalar 原点（createLine 通常为 0），不是文档/窗口偏移。 */
  nativeStartIndex: number = 0;
  pxPerVp: number = 1;
  ascent: number = 0;
  descent: number = 0;
  /** 段落种类（ParagraphKind）：4=列表 5=待办 6=已完成待办 */
  paraKind: number = 0;
  /** 列表层级 0–2 */
  paraIndent: number = 0;
  /**
   * 文本列相对行左边缘的偏移（vp）：列表层级缩进 + 项目符号槽宽。
   * **首行与续行取同一个值**（悬挂缩进）：换行后的文字与首行文字左边界对齐，
   * 项目符号只占首行左侧的槽位，不参与正文折行。
   */
  inset: number = 0;
  /** 本行是否为所在段落的第一条视觉行（只有首行画项目符号） */
  markerOn: boolean = false;
  /** 项目符号槽位左边界（vp，相对行左边缘） */
  markerX: number = 0;
  /** 项目符号槽位宽度（vp） */
  markerW: number = 0;
  /** 已完成待办：文字画删除线 */
  strike: boolean = false;
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
  /**
   * 当前 typeset / indexMap 对应的**窗口起点**（文档 UTF-16 码元偏移）。
   *
   * 对外接口一律收发文档绝对偏移，窗口化的换算全部收敛在本类内部：
   * native 的 LineTypeset / Run 只认窗口内这一小段文本的下标。
   * 窗口起点由 LayoutCache 保证落在码元边界（段落起点）。
   * createLine 返回的 Run 和光标接口使用该原生行自己的下标，
   * 不能继续套用窗口的 indexMap；逐行转换在 buildLayoutLine 内完成。
   */
  private typesetBase: number = 0;
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

  /** Each preview cache needs an independent typeset window and index map. */
  cloneConfiguration(): TextLayoutEngine {
    const copy: TextLayoutEngine = new TextLayoutEngine(this.maxWidthPx / this.pxPerVp,
      this.fontSizePx / this.pxPerVp, this.lineHeightPx / this.pxPerVp,
      this.lineSpacingPx / this.pxPerVp, this.pxPerVp);
    copy.textColor = { alpha: this.textColor.alpha, red: this.textColor.red,
      green: this.textColor.green, blue: this.textColor.blue };
    const runs: FormatRun[] = [];
    for (const run of this.runsValue) { runs.push(run.clone()); }
    copy.setRuns(runs);
    return copy;
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

  /**
   * 构建**整篇**行排版器。保留给"文档很短/需要一次排完"的场景；
   * 长文请走 buildTypesetWindow，否则每次编辑都要为整篇文本重建 typeset。
   */
  buildTypeset(content: string): text.LineTypeset {
    return this.buildTypesetWindow(content, 0, content.length);
  }

  /**
   * 构建 [base, end) 窗口的行排版器（成本低，~2ms）；供 LayoutCache 增量断行复用。
   *
   * 旧实现每次编辑都用**整篇**文本调用 buildTypeset：行级缓存只省下了"行对象"，
   * 没省下"整篇排版"——JS 侧要建整篇 TextIndexMap，原生侧还要为整篇文本构建字型 run。
   * 这与项目自定规范 R9「避免整篇 typeset」直接冲突，长文下每次按键都是一次 O(文档) 开销。
   *
   * 窗口由 LayoutCache 保证**覆盖完整的段落**（起止都取段落边界），
   * 因此窗口内的断行结果与整篇排版一致：一行永远不会跨窗口边界。
   */
  buildTypesetWindow(content: string, base: number, end: number): text.LineTypeset {
    const lo: number = Math.max(0, Math.min(base, content.length));
    const hi: number = Math.max(lo, Math.min(end, content.length));
    const windowText: string = content.substring(lo, hi);
    this.typesetBase = lo;
    this.indexMap = new TextIndexMap(windowText);
    const baseStyle: text.TextStyle = {
      fontSize: this.fontSizePx,
      color: this.textColor
    };
    const paragraphStyle: text.ParagraphStyle = {
      textStyle: baseStyle
    };
    const builder = new text.ParagraphBuilder(paragraphStyle, this.fontCollection);
    if (this.runsValue.length === 0) {
      builder.addText(windowText);
      return builder.buildLineTypeset();
    }
    // 分段添加：格式区间 pushStyle，其余用基准样式；保证字形 run 在格式边界处断开。
    // 标注本身是文档坐标，这里逐段裁剪到窗口并重定基（减 lo）。
    let cursor: number = 0;
    for (let i = 0; i < this.runsValue.length; i++) {
      const r: FormatRun = this.runsValue[i];
      const clippedStart: number = Math.max(lo, r.startOffset);
      const clippedEnd: number = Math.min(hi, r.endOffset);
      // 窗口外的标注不能触发 addText，否则会反复追加尚未消费的窗口尾部。
      if (clippedEnd <= clippedStart) {
        continue;
      }
      const s: number = Math.max(cursor, clippedStart - lo);
      const e: number = Math.max(s, clippedEnd - lo);
      if (s > cursor) {
        builder.addText(windowText.substring(cursor, s));
      }
      if (e > s) {
        builder.pushStyle(this.styleFor(r));
        builder.addText(windowText.substring(s, e));
        builder.popStyle();
        cursor = e;
      }
    }
    if (cursor < windowText.length) {
      builder.addText(windowText.substring(cursor));
    }
    return builder.buildLineTypeset();
  }

  /** 排版宽度（px，供 LayoutCache 调 getLineBreak） */
  contentMaxWidthPx(): number {
    return this.maxWidthPx;
  }

  /**
   * Native LineTypeset/Run indices count scalars; document/IME offsets count UTF-16.
   * start 为**文档**偏移，这里换算成窗口内偏移再查表。
   */
  lineBreak(typeset: text.LineTypeset, start: number, availableWidthPx: number = -1): number {
    const local: number = start - this.typesetBase;
    const nativeStart: number = this.indexMap.toScalar(local);
    // 列表段落要把项目符号槽位与层级缩进从可用宽度里扣掉，
    // 否则文字按整列宽折行、再整体右移 → 右侧溢出并被裁剪。
    const width: number = availableWidthPx > 0 ? Math.min(availableWidthPx, this.maxWidthPx) : this.maxWidthPx;
    const count: number = typeset.getLineBreak(nativeStart, width);
    return this.indexMap.fromScalar(nativeStart + count) - local;
  }

  /** 段落种类/层级 → 文本列左偏移（vp）；非列表段落为 0 */
  static insetVpFor(kind: number, indent: number, fontSizeVp: number): number {
    if (!isListParagraph(kind)) {
      return 0;
    }
    const level: number = Math.max(0, Math.min(MAX_LIST_LEVEL, indent));
    return level * LIST_INDENT_STEP_VP + fontSizeVp * MARKER_WIDTH_RATIO;
  }

  /**
   * 指定段落的可用折行宽度（px）：列宽减去该段的文本列左偏移。
   * 下限取 1vp（而不是一个字号）：原生 getLineBreak 要求宽度 > 0，
   * 但在"极窄列 + 2 级缩进"这种退化场景下，用字号当下限会让结果超过真实可用宽度，
   * 反而把文字顶出右边界。
   */
  availableWidthPx(kind: number, indent: number): number {
    const insetVp: number = TextLayoutEngine.insetVpFor(kind, indent, this.fontSizePx / this.pxPerVp);
    return Math.max(this.pxPerVp, this.maxWidthPx - insetVp * this.pxPerVp);
  }

  createLayoutLine(typeset: text.LineTypeset, start: number, count: number, y: number,
    paraKind: number = ParagraphKind.BODY, paraIndent: number = 0, markerOn: boolean = true): LayoutLine {
    const local: number = start - this.typesetBase;
    const nativeStart: number = this.indexMap.toScalar(local);
    const nativeCount: number = this.indexMap.toScalar(local + count) - nativeStart;
    return this.buildLayoutLine(typeset.createLine(nativeStart, nativeCount), start, count, y,
      paraKind, paraIndent, markerOn);
  }

  /** 行步进（行高+行距，vp） */
  lineStepVp(): number {
    return (this.lineHeightPx + this.lineSpacingPx) / this.pxPerVp;
  }

  /** 从指定排版区间构建一行（输出 vp；公开供 LayoutCache 增量调用） */
  buildLayoutLineFrom(line: text.TextLine, textStart: number, count: number, yOffsetVp: number,
    paraKind: number = ParagraphKind.BODY, paraIndent: number = 0, markerOn: boolean = true): LayoutLine {
    return this.buildLayoutLine(line, textStart, count, yOffsetVp, paraKind, paraIndent, markerOn);
  }

  /** Empty paragraphs also have a caret and occupy one line. */
  emptyLine(offset: number, y: number, paraKind: number = ParagraphKind.BODY,
    paraIndent: number = 0): LayoutLine {
    const line: LayoutLine = new LayoutLine();
    line.startIndex = offset;
    line.endIndex = offset;
    line.consumedEnd = offset;
    line.yOffset = y;
    this.applyParagraphGeometry(line, paraKind, paraIndent, true);
    line.height = this.lineHeightPx / this.pxPerVp;
    line.step = this.lineStepVp();
    line.ascent = this.fontSizePx * 0.8 / this.pxPerVp;
    line.descent = this.fontSizePx * 0.2 / this.pxPerVp;
    line.baseline = y + (line.height - line.ascent - line.descent) / 2 + line.ascent;
    return line;
  }

  /**
   * 写入段落几何：种类、层级、文本列左偏移与项目符号槽位。
   * 首行与续行使用同一个 inset（悬挂缩进），差别只在 markerOn：
   * 续行不画符号，但文字继续与首行文字左边界对齐。
   */
  private applyParagraphGeometry(line: LayoutLine, kind: number, indent: number, markerOn: boolean): void {
    const level: number = isListParagraph(kind) ? Math.max(0, Math.min(MAX_LIST_LEVEL, indent)) : 0;
    line.paraKind = kind;
    line.paraIndent = level;
    line.strike = kind === ParagraphKind.TODO_DONE;
    if (!isListParagraph(kind)) {
      line.inset = 0;
      line.markerOn = false;
      line.markerX = 0;
      line.markerW = 0;
      return;
    }
    const fontSizeVp: number = this.fontSizePx / this.pxPerVp;
    const markerW: number = fontSizeVp * MARKER_WIDTH_RATIO;
    line.markerW = markerW;
    line.markerX = level * LIST_INDENT_STEP_VP;
    line.inset = line.markerX + markerW;
    line.markerOn = markerOn;
  }

  private buildLayoutLine(line: text.TextLine, textStart: number, count: number, yOffsetVp: number,
    paraKind: number = ParagraphKind.BODY, paraIndent: number = 0, markerOn: boolean = true): LayoutLine {
    // textStart/count 是文档偏移；窗口内偏移 = 减去 typesetBase
    const localStart: number = textStart - this.typesetBase;
    const layoutLine: LayoutLine = new LayoutLine();
    this.applyParagraphGeometry(layoutLine, paraKind, paraIndent, markerOn);
    const bounds: text.TypographicBounds = line.getTypographicBounds();
    layoutLine.startIndex = textStart;
    layoutLine.endIndex = textStart + count;
    layoutLine.consumedEnd = layoutLine.endIndex;
    layoutLine.nativeLine = line;
    // createLine 的原生 Run/光标下标从本行开始，getTextRange 给出原生行的起点。
    // 使用逐行索引表，避免第二条软折行被错误映射回 typeset 窗口开头。
    layoutLine.indexMap = this.indexMap.slice(localStart, localStart + count);
    layoutLine.nativeStartIndex = line.getTextRange().start;
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
      // 原生下标先减去本行原点，再经本行 UTF-16 映射加回文档起点。
      const localRunStart: number = layoutLine.indexMap.fromScalar(range.start - layoutLine.nativeStartIndex);
      data.textStart = textStart + localRunStart;
      // Run APIs use end as LENGTH, unlike the document's end-exclusive ranges.
      data.textEnd = textStart + layoutLine.indexMap.fromScalar(range.start + range.end - layoutLine.nativeStartIndex);
      data.glyphOffsets = indices.map((index: number): number =>
        layoutLine.indexMap.fromScalar(index - layoutLine.nativeStartIndex) - localRunStart);
      // Preserve native line-relative positions, including bidi order and shaping bearings.
      // Only runs actually rebased to zero need their line origin added back.
      data.runOffsetX = this.localRunOriginVp(line, range, positions);
      const advances: common2D.Point[] = run.getAdvances({ start: 0, end: data.glyphs.length });
      for (let g: number = 0; g < data.glyphs.length; g++) {
        const adv: common2D.Point | null = g < advances.length ? advances[g] : null;
        const pos: common2D.Point | null = g < positions.length ? positions[g] : null;
        data.advances.push({
          x: adv !== null ? adv.x / this.pxPerVp : 0,
          y: adv !== null ? adv.y / this.pxPerVp : 0
        });
        data.positions.push({
          x: pos !== null ? pos.x / this.pxPerVp : 0,
          y: pos !== null ? pos.y / this.pxPerVp : 0
        });
      }
      layoutLine.runs.push(data);
    }
    return layoutLine;
  }

  /** API 26 devices can return either line-positioned runs or runs rebased to x=0. */
  private localRunOriginVp(line: text.TextLine, range: text.Range, positions: common2D.Point[]): number {
    if (positions.length === 0) { return 0; }
    let minX: number = positions[0].x;
    for (const point of positions) { minX = Math.min(minX, point.x); }
    if (Math.abs(minX) > 0.01) { return 0; }
    try {
      const start: number = line.getOffsetForStringIndex(range.start);
      const end: number = line.getOffsetForStringIndex(range.start + range.end);
      const origin: number = Math.min(start, end);
      return Number.isFinite(origin) && origin > 0.01 ? origin / this.pxPerVp : 0;
    } catch (error) {
      return 0;
    }
  }
}
