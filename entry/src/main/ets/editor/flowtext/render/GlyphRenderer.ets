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
import { SelectionInfo, PreviewInfo, ViewportInfo, ParagraphKind } from '../model/EditorTypes';
import { HitTester } from '../interaction/HitTester';
import {
  TypewriterScaleOptions,
  typewriterLineDistance,
  typewriterScaleForDistance,
  typewriterDimWeight
} from '../theme/TypewriterScale';

/** 渲染主题（vp 化，内部坐标全量 vp；px 换算仅在需要 px 的 API 处进行） */
export class RenderTheme {
  paddingLeftVp: number = 12;
  paddingTopVp: number = 8;
  fontSizeVp: number = 16;
  lineHeightVp: number = 24;
  textColor: common2D.Color = { alpha: 255, red: 31, green: 35, blue: 41 };
  /** 非当前段落的淡化字色（打字机模式）；由宿主按主题计算 */
  dimTextColor: common2D.Color = { alpha: 255, red: 154, green: 160, blue: 166 };
  /** 打字机段落缩放参数（当前段 1.08× / 相邻 0.98× / 下限 0.90×） */
  typewriterScale: TypewriterScaleOptions = new TypewriterScaleOptions();
  /** 文本列宽（vp） */
  textColumnWidthVp: number = 0;
  /** 右侧内边距（vp）：文字裁剪边界 */
  paddingRightVp: number = 12;
  /** 编辑区可视尺寸（vp）：文字绘制裁剪到该矩形内，杜绝越界 */
  viewWidthVp: number = 0;
  viewHeightVp: number = 0;
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
  private dimBrush: drawing.Brush = new drawing.Brush();
  /** 光标所在行的打字机缩放与基线（draw 里预计算，drawCaret 保持原签名） */
  private caretScalePending: number = 1;
  /**
   * 项目符号画笔（圆环 + 对勾都用几何绘制）。
   *
   * 为什么不用字体字形：• ○ ✓ 命中率依赖设备默认字体是否覆盖这些码点，
   * 缺字形时整块空白（表现为"勾选后符号消失"）。几何绘制与字体无关，
   * 也与 HarmonyOS Symbol 的"圆环 + 对勾"观感更接近。
   */
  private markerPen: drawing.Pen = new drawing.Pen();
  private caretPivotYPending: number = 0;

  constructor(opts: RenderTheme) {
    this.opts = opts;
    this.textBrush.setAntiAlias(true);
    this.animBrush.setAntiAlias(true);
    this.selectionBrush.setAntiAlias(true);
    this.handleBrush.setAntiAlias(true);
    this.caretBrush.setAntiAlias(true);
    this.previewBrush.setAntiAlias(true);
    this.dimBrush.setAntiAlias(true);
    // 圆环/对勾是细线：必须显式开抗锯齿（Pen 默认关闭），转角与线帽取圆头
    this.markerPen.setAntiAlias(true);
    this.markerPen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.markerPen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }

  /** vp → px（绘制模块按物理 px 解释坐标；布局/触摸为 vp，绘制需换算） */
  private pv(v: number): number {
    return v * this.opts.pxPerVp;
  }

  /** Match pointer/IME/handle geometry to the transform used to draw each line. */
  visualCaret(caret: CursorState, lines: LayoutLine[], scaleEnabled: boolean,
    first: number, last: number): CursorState {
    const visual: CursorState = caret.clone();
    if (!scaleEnabled || lines.length === 0) { return visual; }
    let index: number = 0;
    let distance: number = Number.MAX_VALUE;
    for (let i: number = 0; i < lines.length; i++) {
      const delta: number = Math.abs(HitTester.lineBox(lines[i]).top - caret.y);
      if (delta < distance) { index = i; distance = delta; }
    }
    const line: LayoutLine = lines[index];
    const scale: number = this.fittedScale(index, line, true, first, last);
    visual.x = this.opts.paddingLeftVp + (caret.x - this.opts.paddingLeftVp) * scale;
    visual.y = line.baseline + (caret.y - line.baseline) * scale;
    visual.height = caret.height * scale;
    return visual;
  }

  hitTest(x: number, y: number, lines: LayoutLine[], source: string,
    scaleEnabled: boolean, first: number, last: number): number {
    if (!scaleEnabled || lines.length === 0) {
      return HitTester.hitTest(x, y, lines, this.opts.paddingLeftVp, this.opts.paddingTopVp, source);
    }
    let index: number = 0;
    let distance: number = Number.MAX_VALUE;
    for (let i: number = 0; i < lines.length; i++) {
      const line: LayoutLine = lines[i];
      const box = HitTester.lineBox(line);
      const scale: number = this.fittedScale(i, line, true, first, last);
      const top: number = this.opts.paddingTopVp + line.baseline + (box.top - line.baseline) * scale;
      const bottom: number = top + box.height * scale;
      const delta: number = y < top ? top - y : y > bottom ? y - bottom : 0;
      if (delta < distance) { index = i; distance = delta; }
    }
    const line: LayoutLine = lines[index];
    const scale: number = this.fittedScale(index, line, true, first, last);
    const logicalX: number = this.opts.paddingLeftVp + (x - this.opts.paddingLeftVp) / scale;
    return HitTester.hitTest(logicalX, this.opts.paddingTopVp + line.yOffset + line.height / 2,
      [line], this.opts.paddingLeftVp, this.opts.paddingTopVp, source);
  }

  /** 完整重绘（先清空再绘制） */
  draw(ctx: DrawingRenderingContext,
    lines: LayoutLine[],
    caret: CursorState | null,
    selection: SelectionInfo | null,
    preview: PreviewInfo | null,
    viewport: ViewportInfo,
    anims: GlyphAnimRegistry | null,
    handles: CursorState[],
    dimEnabled: boolean = false,
    focusLineStart: number = -1,
    focusLineEnd: number = -1,
    scaleEnabled: boolean = false,
    caretLineIndex: number = -1,
    placeholder: string = '',
    placeholderColor: common2D.Color = { alpha: 255, red: 154, green: 160, blue: 166 }): void {
    const canvas = ctx.canvas;
    canvas.clear(this.opts.backgroundColor);

    if (selection !== null && !selection.isEmpty()) {
      this.drawSelection(canvas, lines, selection, viewport, scaleEnabled, focusLineStart, focusLineEnd);
      this.drawHandles(canvas, handles, viewport);
    }
    // 预上屏文字已经进入真实排版（previewCache 的 lines），由 drawText 分段着色，
    // 不能再叠加一层 drawPreview —— 旧实现会在同一位置画两遍且基线偏移约 4-6vp。
    this.drawText(canvas, lines, viewport, anims, preview, dimEnabled, focusLineStart, focusLineEnd, scaleEnabled);
    // 空文稿占位文字：走 Canvas 绘制，与光标共用同一条排版行/基线/左内边距，
    // 不再用 EditorPane 的 Text 叠加层（两套排版参数导致首次聚焦时光标与占位错位）。
    if (placeholder !== '' && lines.length > 0) {
      this.drawPlaceholder(canvas, lines[0], placeholder, placeholderColor, viewport,
        scaleEnabled, focusLineStart, focusLineEnd);
    }
    if (caret !== null && caret.visible) {
      // 光标必须与所在行的文字使用**同一缩放与轴心**，否则放大段里光标会水平偏移。
      // 行号由编辑器按 caretOffset 精确给出；y 区间只作兜底（不能用 line.step，会与下一行重叠）。
      this.caretScalePending = 1;
      this.caretPivotYPending = 0;
      if (scaleEnabled) {
        let caretLine: number = caretLineIndex;
        if (caretLine < 0 || caretLine >= lines.length) {
          caretLine = -1;
          for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (caret.y >= l.yOffset && caret.y < l.yOffset + l.height) {
              caretLine = i;
              break;
            }
          }
        }
        if (caretLine >= 0) {
          const l = lines[caretLine];
          this.caretScalePending = this.fittedScale(caretLine, l, true, focusLineStart, focusLineEnd);
          this.caretPivotYPending = this.pv(this.opts.paddingTopVp + l.baseline - viewport.scrollY);
        }
      }
      this.drawCaret(canvas, caret, viewport);
    }
    ctx.invalidate();
  }

  /** 字形绘制：批量 TextBlob（**按 run 缓存**）+ 预上屏分段着色 + 动画字形单独插值（仅可视区行） */
  private drawText(canvas: DrawingCanvas, lines: LayoutLine[], viewport: ViewportInfo,
    anims: GlyphAnimRegistry | null, preview: PreviewInfo | null,
    dimEnabled: boolean, focusLineStart: number, focusLineEnd: number, scaleEnabled: boolean): void {
    // 画刷颜色必须每帧显式下发：缓存 TextBlob 路径不会自己带颜色（旧实现只在慢路径 setColor，
    // 首次绘制命中缓存时会沿用画刷旧色）。
    this.textBrush.setColor(this.opts.textColor);
    const hasPreview: boolean = preview !== null && !preview.isEmpty();
    // 预览在正文中的实际占位是 [startOffset, startOffset + text.length)；
    // PreviewInfo.endOffset 是"被替换区间"的终点（提交时用），不能直接当显示终点。
    const previewStart: number = preview !== null ? preview.startOffset : -1;
    const previewEnd: number = preview !== null ? preview.startOffset + preview.text.length : -1;
    // 硬裁剪：文字（含缩放/字形动画）不得越过编辑区可视边界。
    // 正常排版下当前段放大后右边界正好是 viewWidth - paddingRight，不会被裁掉；
    // 只有异常超长 run / 动画过冲才由这里兜住。
    const clipLeft: number = this.pv(this.opts.paddingLeftVp) - 0.5;
    const clipRight: number = this.opts.viewWidthVp > 0
      ? this.pv(this.opts.viewWidthVp - this.opts.paddingRightVp)
      : this.pv(this.opts.paddingLeftVp + this.opts.textColumnWidthVp);
    const clipBottom: number = this.opts.viewHeightVp > 0 ? this.pv(this.opts.viewHeightVp) : Number.MAX_SAFE_INTEGER;
    // 裁剪是"兜底"而非排版手段：不支持 clipRect 的实现（或单测画布）直接跳过，不影响正常绘制
    let clipped: boolean = false;
    try {
      canvas.save();
      canvas.clipRect({ left: clipLeft, top: 0, right: clipRight, bottom: clipBottom });
      clipped = true;
    } catch (e) {
      try {
        canvas.restore();
      } catch (e2) {
        // 忽略：画布实现不支持裁剪
      }
    }
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.yOffset + line.height < viewport.top || line.yOffset > viewport.bottom) {
        continue;
      }
      const baselineY: number = this.pv(this.opts.paddingTopVp + line.baseline - viewport.scrollY);
      // columnX = 文本列左边缘；lineX = 本行文字起点（列左边缘 + 列表缩进/符号槽）。
      // 悬挂缩进下续行与首行共用同一个 inset，因此这里不需要区分首行/续行。
      const columnX: number = this.pv(this.opts.paddingLeftVp);
      const lineX: number = columnX + this.pv(line.inset);

      // 打字机视觉层级（纯绘制层，不改排版）：
      //   距离 → 淡化权重（0/1 之间在 1 行内连续过渡）；距离 → 缩放（当前段 1.08×，逐行递减到 0.90×）。
      const distance: number = dimEnabled ? typewriterLineDistance(i, focusLineStart, focusLineEnd) : 0;
      const dimWeight: number = dimEnabled ? typewriterDimWeight(distance) : 0;
      const lineColor: common2D.Color = this.colorForWeight(dimWeight);
      const lineScale: number = (dimEnabled && scaleEnabled)
        ? this.fittedScale(i, line, true, focusLineStart, focusLineEnd) : 1;
      const scaled: boolean = Math.abs(lineScale - 1) > 0.001;
      // 缩放轴心必须与光标/选区一致：文本列**左边缘**（不是列中心）。
      // 列已按 1/focusScale 收窄，若这里用列中心，当前段左边缘会被推到列外（左侧裁字），
      // 非当前行则会向中间内缩（看起来整段都溢出/不对齐）。
      const pivotX: number = this.textPivotPx();
      if (scaled) {
        canvas.save();
        canvas.translate(pivotX, baselineY);
        canvas.scale(lineScale, lineScale);
        canvas.translate(-pivotX, -baselineY);
      }
      this.textBrush.setColor(lineColor);
      // 项目符号画在符号槽内（只有段落首行有 markerOn），删除线盖住整行文字
      if (line.markerOn && line.markerW > 0) {
        this.drawMarker(canvas, line, columnX, baselineY, lineColor);
      }
      for (let r = 0; r < line.runs.length; r++) {
        const run = line.runs[r];
        if (run.glyphs.length === 0 || run.font === null) {
          continue;
        }
        const runHasPreview: boolean = hasPreview && previewStart < run.textEnd && previewEnd > run.textStart;
        // 常规路径（绝大多数帧）：本 run 无动画字形、也无预上屏 →
        // 直接画缓存好的整 run TextBlob，不逐字形建对象。
        if (!this.hasAnimatedGlyph(run, anims) && !runHasPreview) {
          const cached: drawing.TextBlob | null = this.runBlob(run);
          if (cached !== null) {
            canvas.attachBrush(this.textBrush);
            canvas.drawTextBlob(cached, lineX + this.pv(run.runOffsetX), baselineY);
            canvas.detachBrush();
          }
          continue;
        }
        // 慢路径：run 内有动画字形，或本 run 与预上屏区间相交。
        // 预上屏字形与普通字形分别成段绘制，但共用同一个 run 原点与基线。
        const normalBuffer: drawing.TextBlobRunBuffer[] = [];
        const previewBuffer: drawing.TextBlobRunBuffer[] = [];
        for (let g = 0; g < run.glyphs.length; g++) {
          const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          if (this.animStateAt(anims, offset) !== undefined) {
            continue;
          }
          const item: drawing.TextBlobRunBuffer = {
            glyph: run.glyphs[g],
            positionX: this.pv(run.positions[g].x),
            positionY: this.pv(run.positions[g].y)
          };
          if (hasPreview && offset >= previewStart && offset < previewEnd) {
            previewBuffer.push(item);
          } else {
            normalBuffer.push(item);
          }
        }
        const originX: number = lineX + this.pv(run.runOffsetX);
        if (normalBuffer.length > 0) {
          const blob: drawing.TextBlob = drawing.TextBlob.makeFromRunBuffer(normalBuffer, run.font, null);
          canvas.attachBrush(this.textBrush);
          canvas.drawTextBlob(blob, originX, baselineY);
          canvas.detachBrush();
        }
        if (previewBuffer.length > 0) {
          const previewBlob: drawing.TextBlob = drawing.TextBlob.makeFromRunBuffer(previewBuffer, run.font, null);
          this.previewBrush.setColor(this.opts.previewColor);
          canvas.attachBrush(this.previewBrush);
          canvas.drawTextBlob(previewBlob, originX, baselineY);
          canvas.detachBrush();
        }
        for (let g = 0; g < run.glyphs.length; g++) {
          const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          const st: GlyphAnimState | undefined = this.animStateAt(anims, offset);
          if (st !== undefined) {
            this.drawAnimatedGlyph(canvas, st, viewport, lineColor);
          }
        }
      }
      if (line.strike && line.width > 0.5) {
        this.drawStrikethrough(canvas, line, lineX, baselineY, lineColor);
      }
      if (scaled) {
        canvas.restore();
      }
    }
    if (clipped) {
      canvas.restore();
    }
    if (anims !== null) {
      for (let i: number = 0; i < anims.exits.length; i++) {
        this.drawAnimatedGlyph(canvas, anims.exits[i], viewport, this.opts.textColor);
      }
    }
  }

  /**
   * 段落项目符号，全部用几何绘制（槽位由排版算好）：
   *   • 列表   → 实心圆点（层级越深越小）
   *   ○ 待办   → 空心圆环
   *   ✓ 已完成 → 空心圆环 + 对勾路径
   *
   * 不用字体字形的原因见 markerPen 的注释：缺字形会整块消失。
   */
  private drawMarker(canvas: DrawingCanvas, line: LayoutLine, columnX: number, baselineY: number,
    color: common2D.Color): void {
    const fontSizePx: number = this.pv(this.opts.fontSizeVp);
    const slotW: number = this.pv(line.markerW);
    const cx: number = columnX + this.pv(line.markerX) + slotW / 2;
    // 基线 - 0.32em ≈ 一行文字的视觉中心（x-height 中段），与文字重心对齐
    const cy: number = baselineY - fontSizePx * 0.32;
    if (line.paraKind === ParagraphKind.BULLET) {
      // 层级越深点越小：• → ·（与常见排版软件的 3 级圆点层次一致）
      let r: number = fontSizePx * 0.20;
      if (line.paraIndent === 1) {
        r = fontSizePx * 0.15;
      } else if (line.paraIndent >= 2) {
        r = fontSizePx * 0.10;
      }
      this.textBrush.setColor(color);
      canvas.attachBrush(this.textBrush);
      canvas.drawCircle(cx, cy, Math.max(1, r));
      canvas.detachBrush();
      return;
    }
    // 圆环直径约 0.8em，控制在符号槽内；对勾按半径比例缩放，字号变化自动跟随
    const radius: number = Math.max(1, Math.min(slotW * 0.34, fontSizePx * 0.42));
    // 画笔属性改动后必须重新 attachPen 才生效（官方文档明确要求）
    this.markerPen.setColor(color);
    this.markerPen.setStrokeWidth(Math.max(1, fontSizePx * 0.085));
    canvas.attachPen(this.markerPen);
    canvas.drawCircle(cx, cy, radius);
    if (line.paraKind === ParagraphKind.TODO_DONE) {
      // 对勾：两段折线，圆头线帽/转角由 markerPen 统一设置
      const path: drawing.Path = new drawing.Path();
      path.moveTo(cx - radius * 0.52, cy + radius * 0.02);
      path.lineTo(cx - radius * 0.12, cy + radius * 0.42);
      path.lineTo(cx + radius * 0.56, cy - radius * 0.44);
      canvas.drawPath(path);
    }
    canvas.detachPen();
  }

  /** 已完成待办的删除线：横跨本行文字（line.width 为实测行宽） */
  private drawStrikethrough(canvas: DrawingCanvas, line: LayoutLine, lineX: number,
    baselineY: number, color: common2D.Color): void {
    const thickness: number = Math.max(1, this.pv(this.opts.fontSizeVp) * 0.06);
    const y: number = baselineY - this.pv(this.opts.fontSizeVp) * 0.32;
    this.textBrush.setColor(color);
    canvas.attachBrush(this.textBrush);
    canvas.drawRect({
      left: lineX,
      top: y,
      right: lineX + this.pv(line.width),
      bottom: y + thickness
    });
    canvas.detachBrush();
  }

  /**
   * 缩放轴心（px）= 文本列左边缘（paddingLeft）。
   *
   * 为什么不用"列中心"：打字机模式下列宽已按 1/focusScale 收窄，
   * 若再围绕列中心缩放，非当前行（<1.0×）会左右同时内缩，出现额外缩进；
   * 以左边缘为轴心可保证**所有行的左边界对齐**，当前段落放大后右边界正好回到原列宽，
   * 既不裁剪，也不会让正文左右"跳来跳去"。
   */
  private textPivotPx(): number {
    return this.pv(this.opts.paddingLeftVp);
  }

  /** 指定行的打字机缩放（未开启/未启用缩放时为 1） */
  private lineScaleAt(index: number, enabled: boolean, first: number, last: number): number {
    if (!enabled) {
      return 1;
    }
    const d: number = typewriterLineDistance(index, first, last);
    return typewriterScaleForDistance(d, this.opts.typewriterScale);
  }

  /**
   * 按**该行实测宽度**夹取的缩放：保证 `line.width * scale <= 可用文本宽度`。
   *
   * 为什么要多这一层：列宽收窄是"预留空间"，一旦出现
   *   - 设备上排版宽度与视口宽度不一致（密度/内边距取整）、
   *   - 超长不可断 run（长数字/URL）、
   *   - 主题/字号切换后的旧排版缓存，
   * 仅靠预留仍可能让高亮段越界。这里用实测行宽做硬上限，
   * 正常排版下 fit ≥ focusScale，不影响 1.08× 效果；异常时自动收敛到可容纳的比例。
   */
  private fittedScale(index: number, line: LayoutLine, enabled: boolean,
    first: number, last: number): number {
    const wanted: number = this.lineScaleAt(index, enabled, first, last);
    if (!enabled || line.width <= 0.5) {
      return wanted;
    }
    // 缩放轴心是文本列左边缘，所以 inset 本身也会被一起放大：
    // 放大后的右边界 = 列宽 × s 里的 (inset + line.width) 部分。
    // 上界取 columnWidth / (inset + width)，只减 inset 会算出偏大的比例（右移 1–2vp）。
    const available: number = this.opts.viewWidthVp > 0
      ? this.opts.viewWidthVp - this.opts.paddingLeftVp - this.opts.paddingRightVp
      : this.opts.textColumnWidthVp;
    const span: number = line.inset + line.width;
    if (available <= 0.5 || span <= 0.5) {
      return Math.min(wanted, 1);
    }
    const fit: number = available / span;
    return Math.min(wanted, Math.max(0.5, fit));
  }

  /** 空文稿占位：与正文第一行同字号、同基线、同左内边距 */
  private drawPlaceholder(canvas: DrawingCanvas, line: LayoutLine, text: string,
    color: common2D.Color, viewport: ViewportInfo,
    scaleEnabled: boolean, focusFirst: number, focusLast: number): void {
    const font: drawing.Font = new drawing.Font();
    font.setSize(this.pv(this.opts.fontSizeVp));
    const blob: drawing.TextBlob = drawing.TextBlob.makeFromString(
      text, font, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    // 空文稿若已被设为列表/待办，占位文字要让开项目符号槽，不能压在 • 上
    const x: number = this.pv(this.opts.paddingLeftVp + line.inset);
    const y: number = this.pv(this.opts.paddingTopVp + line.baseline - viewport.scrollY);
    // 打字机模式下光标按当前行缩放，占位必须用同一变换，避免空文稿时错位
    const s: number = this.lineScaleAt(0, scaleEnabled, focusFirst, focusLast);
    const scaled: boolean = Math.abs(s - 1) > 0.001;
    if (scaled) {
      const px: number = this.textPivotPx();
      canvas.save();
      canvas.translate(px, y);
      canvas.scale(s, s);
      canvas.translate(-px, -y);
    }
    this.textBrush.setColor(color);
    canvas.attachBrush(this.textBrush);
    canvas.drawTextBlob(blob, x, y);
    canvas.detachBrush();
    if (scaled) {
      canvas.restore();
    }
  }

  /** 淡化权重 → 字色（0=正文色，1=淡化色，中间线性插值，切换时平滑过渡） */
  private colorForWeight(weight: number): common2D.Color {
    if (weight <= 0.001) {
      return this.opts.textColor;
    }
    if (weight >= 0.999) {
      return this.opts.dimTextColor;
    }
    const from: common2D.Color = this.opts.textColor;
    const to: common2D.Color = this.opts.dimTextColor;
    return {
      alpha: 255,
      red: Math.round(from.red + (to.red - from.red) * weight),
      green: Math.round(from.green + (to.green - from.green) * weight),
      blue: Math.round(from.blue + (to.blue - from.blue) * weight)
    };
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
  private drawAnimatedGlyph(canvas: DrawingCanvas, st: GlyphAnimState, viewport: ViewportInfo,
    color: common2D.Color): void {
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
      red: color.red,
      green: color.green,
      blue: color.blue
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

  /**
   * 选区高亮：命中 [start,end) 区间的字形绘制半透明背景矩形。
   *
   * 几何与光标/手柄统一取 HitTester.lineBox（基线 - ascent 到 + descent）：
   * - 相邻已选行的矩形首尾相接（top = 上一行 bottom），跨行/跨段无缝；
   * - 空行在选区内补一段最小宽度，避免"选不中空行"；
   * - 软换行边界处的零宽矩形跳过，避免在下一行行首多画一条竖线。
   */
  private drawSelection(canvas: DrawingCanvas, lines: LayoutLine[], selection: SelectionInfo,
    viewport: ViewportInfo, scaleEnabled: boolean, focusFirst: number, focusLast: number): void {
    const brush: drawing.Brush = this.selectionBrush;
    brush.setColor(this.opts.selectionColor);
    canvas.attachBrush(brush);
    const blankWidth: number = Math.max(8, this.opts.fontSizeVp * 0.5);
    let prevBottom: number = -1;
    let prevIndex: number = -2;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const isEmptyLine: boolean = line.startIndex === line.endIndex;
      const selected: boolean = isEmptyLine
        ? line.startIndex >= selection.startOffset && line.startIndex < selection.endOffset
        : line.startIndex < selection.endOffset && line.endIndex > selection.startOffset;
      if (!selected) {
        prevBottom = -1;
        continue;
      }
      if (line.yOffset + line.height < viewport.top || line.yOffset > viewport.bottom) {
        prevBottom = -1;
        continue;
      }
      const box = HitTester.lineBox(line);
      // 相邻已选行：顶边接到上一行底边，形成连续高亮（参考 OH text_base 的 rect 合并）
      const topVp: number = (i === prevIndex + 1 && prevBottom > 0) ? prevBottom : box.top;
      const bottomVp: number = box.bottom;
      prevBottom = bottomVp;
      prevIndex = i;
      if (bottomVp <= topVp) {
        continue;
      }
      let x0: number;
      let x1: number;
      if (isEmptyLine) {
        // 空行也要从本行的文字列起点开始高亮（列表段落右侧有符号槽）
        x0 = this.opts.paddingLeftVp + line.inset;
        x1 = x0 + blankWidth;
      } else {
        const selStart: number = Math.max(line.startIndex, selection.startOffset);
        const selEnd: number = Math.min(line.endIndex, selection.endOffset);
        x0 = this.offsetToX(line, selStart);
        x1 = this.offsetToX(line, selEnd);
        // 软换行边界：下一行的 0 宽矩形不画
        if (x1 - x0 < 0.5) {
          continue;
        }
      }
      const screenTop: number = this.pv(this.opts.paddingTopVp + topVp - viewport.scrollY);
      const screenBottom: number = this.pv(this.opts.paddingTopVp + bottomVp - viewport.scrollY);
      let leftPx: number = this.pv(x0);
      let rightPx: number = this.pv(x1);
      let topPx: number = screenTop;
      let bottomPx: number = screenBottom;
      // 选区跟随当前文字缩放：同一轴心/基线变换，避免高亮框与放大文字错位
      const s: number = this.fittedScale(i, line, scaleEnabled, focusFirst, focusLast);
      if (Math.abs(s - 1) > 0.001) {
        const px: number = this.textPivotPx();
        const py: number = this.pv(this.opts.paddingTopVp + line.baseline - viewport.scrollY);
        leftPx = px + (leftPx - px) * s;
        rightPx = px + (rightPx - px) * s;
        topPx = py + (topPx - py) * s;
        bottomPx = py + (bottomPx - py) * s;
      }
      canvas.drawRect({ left: leftPx, top: topPx, right: rightPx, bottom: bottomPx });
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
    // 呼吸光标：按 alpha 渐隐渐显（不做硬闪烁）
    const alpha: number = Math.max(0, Math.min(1, caret.alpha));
    if (alpha <= 0.02) {
      return;
    }
    const brush: drawing.Brush = this.caretBrush;
    brush.setColor({
      alpha: Math.round(alpha * 255),
      red: this.opts.caretColor.red,
      green: this.opts.caretColor.green,
      blue: this.opts.caretColor.blue
    });
    canvas.attachBrush(brush);
    // 光标条以字符边界为中线居中绘制（左右各半宽）：
    // 左端锚定会让整条压在右侧字符墨迹上（CJK 满格字形尤为明显），
    // 居中后光标横跨两侧字形的边缘缝隙，视觉上"停在文字两边之间"而非"停在文字上"。
    const halfW: number = this.pv(this.opts.caretWidthVp) / 2;
    let centerX: number = this.pv(caret.x);
    let topPx: number = screenY;
    let bottomPx: number = screenY + this.pv(caret.height);
    // 光标与所在行文字使用同一缩放（draw 预计算），围绕列中心/基线变换
    const s: number = this.caretScalePending;
    if (Math.abs(s - 1) > 0.001) {
      const px: number = this.textPivotPx();
      const py: number = this.caretPivotYPending;
      centerX = px + (centerX - px) * s;
      topPx = py + (topPx - py) * s;
      bottomPx = py + (bottomPx - py) * s;
    }
    canvas.drawRect({
      left: centerX - halfW,
      top: topPx,
      right: centerX + halfW,
      bottom: bottomPx
    });
    canvas.detachBrush();
  }

  /** 行内字符偏移 → x（px）；越界钳制到行首/行尾 */
  private offsetToX(line: LayoutLine, offset: number): number {
    return HitTester.offsetToX(line, offset, this.opts.paddingLeftVp);
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
