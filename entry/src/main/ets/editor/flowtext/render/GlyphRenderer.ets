/**
 * FlowText 字形级绘制器
 *
 * 使用 DrawingRenderingContext.canvas（DrawingCanvas）完成：
 *   清空画布 → 选区高亮 → 字形批量绘制（TextBlob）→ 预上屏 → 光标。
 * 所有坐标单位为 px（内容坐标，视口裁剪由外部传入 scrollY 换算）。
 *
 * 动画支持：GlyphAnimRegistry 记录每字符（offset）的插值状态，
 * 处于动画中的字形从批量 TextBlob 中剔除、单独绘制（位置/透明度/缩放插值）。
 */
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { LayoutLine, GlyphRunData } from './TextLayoutEngine';
import { CursorState } from '../interaction/CursorState';
import { SelectionInfo, PreviewInfo, ViewportInfo } from '../model/EditorTypes';
import { HitTester } from '../interaction/HitTester';

/** 渲染主题（vp 化，内部坐标全量 vp；px 换算仅在需要 px 的 API 处进行） */
export class RenderTheme {
  paddingLeftVp: number = 12;
  paddingTopVp: number = 8;
  fontSizeVp: number = 16;
  lineHeightVp: number = 24;
  textColor: common2D.Color = { alpha: 255, red: 31, green: 35, blue: 41 };
  caretColor: common2D.Color = { alpha: 255, red: 10, green: 89, blue: 247 };
  selectionColor: common2D.Color = { alpha: 77, red: 10, green: 89, blue: 247 };
  backgroundColor: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  previewColor: common2D.Color = { alpha: 255, red: 92, green: 100, blue: 112 };
  caretWidthVp: number = 2;
  /** vp → px 换算系数（uiContext.vp2px(1)），用于底层 px 语义 API（如 Font.setSize、drawTextBlob 间距） */
  pxPerVp: number = 1;
}

/** 单字形动画状态（key = 字符 offset） */
export class GlyphAnimState {
  fromX: number = 0;
  fromY: number = 0;
  toX: number = 0;
  toY: number = 0;
  fromAlpha: number = 1;
  toAlpha: number = 1;
  fromScale: number = 1;
  toScale: number = 1;
  progress: number = 0;
  /** 退场字形需要独立绘制数据 */
  exiting: boolean = false;
  glyph: number = 0;
  font: drawing.Font | null = null;
  glyphWidth: number = 0;
  glyphHeight: number = 0;
  /**
   * 单字形 TextBlob 缓存：动画生命周期内 glyph/font 都不变，
   * 每帧重建是纯浪费（一次编辑最多 80 个 slide + 24 个 exit，即约 1.2 万次分配/秒）。
   */
  blob: drawing.TextBlob | null = null;
}

export class GlyphAnimRegistry {
  map: Map<number, GlyphAnimState> = new Map<number, GlyphAnimState>();
  exits: GlyphAnimState[] = [];

  has(offset: number): boolean {
    return this.map.has(offset);
  }

  get(offset: number): GlyphAnimState | undefined {
    return this.map.get(offset);
  }

  clear(): void {
    this.map.clear();
    this.exits = [];
  }

  isEmpty(): boolean {
    return this.map.size === 0 && this.exits.length === 0;
  }

  static lerp(from: number, to: number, t: number): number {
    return from + (to - from) * t;
  }
}

export class GlyphRenderer {
  private opts: RenderTheme;

  /**
   * 复用的画刷。draw 是 60fps 热路径（光标弹簧动画、字形动画、闪烁、惯性滚动
   * 都会调 drawNow），每帧 new 一个是纯浪费。
   *
   * 另外必须显式 setAntiAlias(true)：官方 Brush 文档写明「未调用此接口设置时，
   * 系统默认关闭抗锯齿」，而本渲染器走 DrawingRenderingContext（这是正确的高性能
   * 选择），无法用 RenderingContextSettings(true) 开抗锯齿 —— 不设置的话
   * 字形边缘、光标竖条、选区手柄全是硬边。
   */
  private textBrush: drawing.Brush = new drawing.Brush();
  private animBrush: drawing.Brush = new drawing.Brush();
  private selectionBrush: drawing.Brush = new drawing.Brush();
  private handleBrush: drawing.Brush = new drawing.Brush();
  private caretBrush: drawing.Brush = new drawing.Brush();
  private previewBrush: drawing.Brush = new drawing.Brush();
  /** 预上屏字体与 TextBlob 缓存（字号变化 / 文本变化时才重建） */
  private previewFont: drawing.Font | null = null;
  private previewFontSizePx: number = -1;
  private previewBlob: drawing.TextBlob | null = null;
  private previewBlobText: string = '';

  constructor(opts: RenderTheme) {
    this.opts = opts;
    this.textBrush.setAntiAlias(true);
    this.animBrush.setAntiAlias(true);
    this.selectionBrush.setAntiAlias(true);
    this.handleBrush.setAntiAlias(true);
    this.caretBrush.setAntiAlias(true);
    this.previewBrush.setAntiAlias(true);
  }

  /** vp → px（绘制模块按物理 px 解释坐标；布局/触摸为 vp，绘制需换算） */
  private pv(v: number): number {
    return v * this.opts.pxPerVp;
  }

  /** 完整重绘（先清空再绘制） */
  draw(ctx: DrawingRenderingContext,
    lines: LayoutLine[],
    caret: CursorState | null,
    selection: SelectionInfo | null,
    preview: PreviewInfo | null,
    viewport: ViewportInfo,
    anims: GlyphAnimRegistry | null,
    handles: CursorState[]): void {
    const canvas = ctx.canvas;
    canvas.clear(this.opts.backgroundColor);

    if (selection !== null && !selection.isEmpty()) {
      this.drawSelection(canvas, lines, selection, viewport);
      this.drawHandles(canvas, handles, viewport);
    }
    this.drawText(canvas, lines, viewport, anims);
    if (preview !== null && !preview.isEmpty()) {
      this.drawPreview(canvas, preview, caret, viewport);
    }
    if (caret !== null && caret.visible) {
      this.drawCaret(canvas, caret, viewport);
    }
    ctx.invalidate();
  }

  /** 字形绘制：批量 TextBlob（**按 run 缓存**）+ 动画字形单独插值绘制（仅可视区行） */
  private drawText(canvas: DrawingCanvas, lines: LayoutLine[], viewport: ViewportInfo,
    anims: GlyphAnimRegistry | null): void {
    const brush: drawing.Brush = this.textBrush;
    brush.setColor(this.opts.textColor);
    canvas.attachBrush(brush);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.yOffset + line.height < viewport.top || line.yOffset > viewport.bottom) {
        continue;
      }
      const baselineY: number = this.pv(this.opts.paddingTopVp + line.baseline - viewport.scrollY);
      const lineX: number = this.pv(this.opts.paddingLeftVp);
      for (let r = 0; r < line.runs.length; r++) {
        const run = line.runs[r];
        if (run.glyphs.length === 0 || run.font === null) {
          continue;
        }
        // 常规路径（绝大多数帧）：本 run 没有处于动画中的字形，
        // 直接画缓存好的整 run TextBlob —— 不再逐字形建对象、不再重建 blob。
        if (!this.hasAnimatedGlyph(run, anims)) {
          const cached: drawing.TextBlob | null = this.runBlob(run);
          if (cached !== null) {
            canvas.drawTextBlob(cached, lineX + this.pv(run.runOffsetX), baselineY);
          }
          continue;
        }
        // 慢路径：仅出现在编辑后几百毫秒内、且该 run 内有正在插值的字形
        const runBuffer: drawing.TextBlobRunBuffer[] = [];
        for (let g = 0; g < run.glyphs.length; g++) {
          const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          if (this.animStateAt(anims, offset) === undefined) {
            runBuffer.push({ glyph: run.glyphs[g], positionX: this.pv(run.positions[g].x), positionY: this.pv(run.positions[g].y) });
          }
        }
        if (runBuffer.length > 0) {
          const blob: drawing.TextBlob = drawing.TextBlob.makeFromRunBuffer(runBuffer, run.font, null);
          canvas.drawTextBlob(blob, lineX + this.pv(run.runOffsetX), baselineY);
        }
        for (let g = 0; g < run.glyphs.length; g++) {
          const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          const st: GlyphAnimState | undefined = this.animStateAt(anims, offset);
          if (st !== undefined) {
            this.drawAnimatedGlyph(canvas, st, viewport);
          }
        }
      }
    }
    if (anims !== null) {
      for (let i: number = 0; i < anims.exits.length; i++) { this.drawAnimatedGlyph(canvas, anims.exits[i], viewport); }
    }
    canvas.detachBrush();
  }

  private animStateAt(anims: GlyphAnimRegistry | null, offset: number): GlyphAnimState | undefined {
    return anims === null ? undefined : anims.get(offset);
  }

  /** 本 run 是否有字形处于动画中（只读一遍，无分配，供热路径早退用） */
  private hasAnimatedGlyph(run: GlyphRunData, anims: GlyphAnimRegistry | null): boolean {
    if (anims === null || anims.map.size === 0) {
      return false;
    }
    for (let g: number = 0; g < run.glyphs.length; g++) {
      const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
      if (anims.has(offset)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 整 run 的 TextBlob：首次绘制时构建并缓存在 run 数据上。
   * 缓存随布局重建自动失效（新 GlyphRunData 的 blob 为 null），
   * 而光标动画/闪烁/滚动这些不改变布局的帧全部命中缓存。
   */
  private runBlob(run: GlyphRunData): drawing.TextBlob | null {
    const cached: drawing.TextBlob | null = run.blob;
    if (cached !== null) {
      return cached;
    }
    const font: drawing.Font | null = run.font;
    if (font === null) {
      return null;
    }
    const runBuffer: drawing.TextBlobRunBuffer[] = [];
    for (let g: number = 0; g < run.glyphs.length; g++) {
      runBuffer.push({
        glyph: run.glyphs[g],
        positionX: this.pv(run.positions[g].x),
        positionY: this.pv(run.positions[g].y)
      });
    }
    const blob: drawing.TextBlob = drawing.TextBlob.makeFromRunBuffer(runBuffer, font, null);
    run.blob = blob;
    return blob;
  }

  /** 动画字形：位置/透明度/缩放插值绘制（绕字形中心缩放） */
  private drawAnimatedGlyph(canvas: DrawingCanvas, st: GlyphAnimState, viewport: ViewportInfo): void {
    const t: number = st.progress;
    // 位置插值结果钳制在 from→to 扫过的区间（含轻微弹性余量），防止弹簧过冲导致字形越位乱飞
    const epsX: number = st.glyphWidth > 0 ? st.glyphWidth * 0.6 : 1;
    const epsY: number = st.glyphHeight > 0 ? st.glyphHeight * 0.25 : 1;
    const x: number = this.clampNum(GlyphAnimRegistry.lerp(st.fromX, st.toX, t),
      Math.min(st.fromX, st.toX) - epsX, Math.max(st.fromX, st.toX) + epsX);
    const y: number = this.clampNum(GlyphAnimRegistry.lerp(st.fromY, st.toY, t),
      Math.min(st.fromY, st.toY) - epsY, Math.max(st.fromY, st.toY) + epsY);
    // 弹簧曲线 progress 会过冲（>1），透明度/缩放必须钳制到合法范围
    const alphaRaw: number = GlyphAnimRegistry.lerp(st.fromAlpha, st.toAlpha, t);
    const alpha: number = Math.min(1, Math.max(0, alphaRaw));
    const scaleRaw: number = GlyphAnimRegistry.lerp(st.fromScale, st.toScale, t);
    const scale: number = Math.min(1.5, Math.max(0, scaleRaw));
    if (alpha <= 0.01 || scale <= 0.01 || st.font === null) {
      return;
    }
    const screenY: number = y - viewport.scrollY;
    const baseline: number = this.pv(this.opts.paddingTopVp + screenY);
    const xPx: number = this.pv(x);
    const glyphW: number = this.pv(st.glyphWidth);
    const glyphH: number = this.pv(st.glyphHeight);

    const brush: drawing.Brush = this.animBrush;
    brush.setColor({
      alpha: Math.round(alpha * 255),
      red: this.opts.textColor.red,
      green: this.opts.textColor.green,
      blue: this.opts.textColor.blue
    });
    canvas.attachBrush(brush);

    // 单字形 TextBlob 在动画生命周期内不变（glyph/font 已固定），构建一次即可
    let blob: drawing.TextBlob | null = st.blob;
    if (blob === null) {
      blob = drawing.TextBlob.makeFromRunBuffer(
        [{ glyph: st.glyph, positionX: 0, positionY: 0 }], st.font, null);
      st.blob = blob;
    }
    if (Math.abs(scale - 1) > 0.01) {
      const cx: number = xPx + glyphW / 2;
      const cy: number = baseline + glyphH / 2;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(scale, scale);
      canvas.translate(-cx, -cy);
      canvas.drawTextBlob(blob, xPx, baseline);
      canvas.restore();
    } else {
      canvas.drawTextBlob(blob, xPx, baseline);
    }
    canvas.detachBrush();
  }

  /** 选区高亮：命中 [start,end) 区间的字形绘制半透明背景矩形 */
  private drawSelection(canvas: DrawingCanvas, lines: LayoutLine[], selection: SelectionInfo, viewport: ViewportInfo): void {
    const brush: drawing.Brush = this.selectionBrush;
    brush.setColor(this.opts.selectionColor);
    canvas.attachBrush(brush);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startIndex >= selection.endOffset || line.endIndex <= selection.startOffset) {
        continue;
      }
      if (line.yOffset + line.height < viewport.top || line.yOffset > viewport.bottom) {
        continue;
      }
      const screenY: number = this.pv(this.opts.paddingTopVp + line.yOffset - viewport.scrollY);
      const selStart: number = Math.max(line.startIndex, selection.startOffset);
      const selEnd: number = Math.min(line.endIndex, selection.endOffset);
      const x0: number = this.pv(this.offsetToX(line, selStart));
      const x1: number = this.pv(this.offsetToX(line, selEnd));
      canvas.drawRect({ left: x0, top: screenY, right: x1, bottom: screenY + this.pv(line.height) });
    }
    canvas.detachBrush();
  }

  /** 选区手柄：在选区两端下方绘制圆形把手 */
  private drawHandles(canvas: DrawingCanvas, handles: CursorState[], viewport: ViewportInfo): void {
    if (handles.length === 0) {
      return;
    }
    const brush: drawing.Brush = this.handleBrush;
    brush.setColor(this.opts.caretColor);
    canvas.attachBrush(brush);
    const rVp: number = 5;
    for (let i = 0; i < handles.length; i++) {
      const h: CursorState = handles[i];
      const screenYVp: number = this.opts.paddingTopVp + h.y + h.height - viewport.scrollY;
      if (screenYVp + rVp < 0 || screenYVp > viewport.bottom - viewport.top) {
        continue;
      }
      const cx: number = this.pv(h.x);
      const cy: number = this.pv(screenYVp + rVp);
      // 水滴形手柄：圆头 + 连接选区端的细柄
      canvas.drawCircle(cx, cy, this.pv(rVp));
      const stemW: number = this.pv(1.5);
      const stemTop: number = this.pv(screenYVp - 4);
      canvas.drawRect({ left: cx - stemW, top: stemTop, right: cx + stemW, bottom: cy });
    }
    canvas.detachBrush();
  }

  /** 光标绘制 */
  private drawCaret(canvas: DrawingCanvas, caret: CursorState, viewport: ViewportInfo): void {
    // 视口裁剪用 vp；绘制坐标换算 px
    const screenYVp: number = this.opts.paddingTopVp + caret.y - viewport.scrollY;
    if (screenYVp + caret.height < 0 || screenYVp > viewport.bottom - viewport.top) {
      return;
    }
    const screenY: number = this.pv(screenYVp);
    const brush: drawing.Brush = this.caretBrush;
    brush.setColor(this.opts.caretColor);
    canvas.attachBrush(brush);
    // 光标条以字符边界为中线居中绘制（左右各半宽）：
    // 左端锚定会让整条压在右侧字符墨迹上（CJK 满格字形尤为明显），
    // 居中后光标横跨两侧字形的边缘缝隙，视觉上"停在文字两边之间"而非"停在文字上"。
    const halfW: number = this.pv(this.opts.caretWidthVp) / 2;
    const centerX: number = this.pv(caret.x);
    canvas.drawRect({
      left: centerX - halfW,
      top: screenY,
      right: centerX + halfW,
      bottom: screenY + this.pv(caret.height)
    });
    canvas.detachBrush();
  }

  /** 预上屏文本：以灰色绘制在光标之后（MVP：不参与断行） */
  private drawPreview(canvas: DrawingCanvas, preview: PreviewInfo, caret: CursorState | null,
    viewport: ViewportInfo): void {
    // 画布为 VP 单位，Font.setSize 为物理 px 语义：字号 = fontSizeVp * pxPerVp，
    // 使预上屏尺寸与正文一致。Font 只在字号变化时重建（合成期间这个函数每帧都会调用）。
    const sizePx: number = this.opts.fontSizeVp * this.opts.pxPerVp;
    if (this.previewFont === null || this.previewFontSizePx !== sizePx) {
      const built = new drawing.Font();
      built.setSize(sizePx);
      this.previewFont = built;
      this.previewFontSizePx = sizePx;
      this.previewBlob = null;
      this.previewBlobText = '';
    }
    const font: drawing.Font | null = this.previewFont;
    if (font === null) {
      return;
    }
    // TextBlob 按预上屏文本缓存：拼音合成期文本变化远低于帧率
    let blob: drawing.TextBlob | null = this.previewBlob;
    if (blob === null || this.previewBlobText !== preview.text) {
      blob = drawing.TextBlob.makeFromString(preview.text, font,
        drawing.TextEncoding.TEXT_ENCODING_UTF16);
      this.previewBlob = blob;
      this.previewBlobText = preview.text;
    }
    const brush: drawing.Brush = this.previewBrush;
    brush.setColor(this.opts.previewColor);
    canvas.attachBrush(brush);
    let px: number = this.pv(this.opts.paddingLeftVp);
    let py: number = this.pv(this.opts.paddingTopVp + viewport.top - viewport.scrollY);
    if (caret !== null) {
      px = this.pv(caret.x);
      py = this.pv(this.opts.paddingTopVp + caret.y - viewport.scrollY);
    }
    // 基线偏移 = 行高 * 0.8（与正文字形一致；0.8 基线已在 TextLayoutEngine 集中计算，此处保持行内基线偏移）
    canvas.drawTextBlob(blob, px, py + this.pv(this.opts.lineHeightVp * 0.8));
    canvas.detachBrush();
  }

  /** 行内字符偏移 → x（px）；越界钳制到行首/行尾 */
  private offsetToX(line: LayoutLine, offset: number): number {
    return HitTester.offsetToX(line, offset, this.opts.paddingLeftVp);
  }

  private legacyOffsetToX(line: LayoutLine, offset: number): number {
    if (offset <= line.startIndex) {
      return this.opts.paddingLeftVp;
    }
    if (offset >= line.endIndex) {
      return this.opts.paddingLeftVp + line.width;
    }
    let x = this.opts.paddingLeftVp;
    for (let r = 0; r < line.runs.length; r++) {
      const run = line.runs[r];
      if (offset <= run.textStart) {
        return x;
      }
      if (offset >= run.textEnd) {
        x += run.width();
        continue;
      }
      // 用码元偏移查所属字形，避免 emoji 让下标越界
      const gi: number = run.glyphIndexAt(offset);
      if (gi < 0) {
        return x;
      }
      return x + run.positions[gi].x;
    }
    return x;
  }

  private clampNum(v: number, lo: number, hi: number): number {
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }
}
