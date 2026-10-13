/**
 * FlowText 字形动画生成器
 *
 * 编辑前后对比字形位置映射，为每个受影响字符生成插值动画：
 *   前后均存在 → 让位/回流/换行（位置插值）
 *   仅新出现   → 入场（缩放 0.6→1 + 淡入）
 *   仅旧存在   → 退场（收缩 + 淡出，绘制于旧位置）
 *
 * **只对编辑点附近的窗口做差分**：
 * 旧实现每次按键都对"整篇已排版字形"建两份 Map（5 万字 ≈ 2×5 万个 GlyphPoint），
 * 再把两张表的键合并成数组 + Set 去重，而最终真正需要动画的字形上限只有
 * MAX_SLIDES + MAX_EXITS = 104 个 —— 相当于为了 104 个字形处理了 10 万个。
 * 窗口外的字形本来就不需要过渡（它们直接以新位置绘制），排除后每键成本与
 * 文稿长度解耦。
 */
import { drawing } from '@kit.ArkGraphics2D';
import { LayoutLine } from '../render/TextLayoutEngine';
import { GlyphAnimRegistry, GlyphAnimState } from '../render/GlyphRenderer';
import { GraphemeUtil } from '../model/GraphemeUtil';

/** 字形位置 + 绘制数据 */
export class GlyphPoint {
  x: number = 0;
  y: number = 0;
  glyph: number = 0;
  font: drawing.Font | null = null;
  width: number = 0;
  height: number = 0;
}

/** 字形差分参数（字段多，用类承载以便调用点可读） */
export class GlyphDiffOptions {
  paddingLeftPx: number = 0;
  paddingTopPx: number = 0;
  /** 视为"跨行动（换行/回行）"的最小纵向位移（vp） */
  rowThresholdVp: number = 0;
  oldText: string = '';
  newText: string = '';
  /** 本次编辑的起点（文档 UTF-16 偏移），差分窗口以它为中心 */
  hintOffset: number = 0;
  /**
   * 窗口半径（码元）。视口约 30 行 × 20 字形 ≈ 600 码元，
   * 1024 ≈ 前后各一个多半视口，足够覆盖会"让位"的字形。
   */
  windowRadius: number = 1024;
}

export class GlyphAnimator {
  /**
   * 构建"字符偏移 → 字形位置+绘制数据"映射（输入为排版行数组）。
   * 只保留与 [fromOffset, toOffset] 相交的行。
   */
  static buildGlyphMapFromLines(lines: LayoutLine[], paddingLeftPx: number, paddingTopPx: number,
    fromOffset: number, toOffset: number): Map<number, GlyphPoint> {
    const map = new Map<number, GlyphPoint>();
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 与窗口不相交的行直接跳过 —— 整篇建 Map 正是"每键 O(文档)"的主因
      if (line.endIndex < fromOffset || line.startIndex > toOffset) {
        continue;
      }
      for (let r = 0; r < line.runs.length; r++) {
        const run = line.runs[r];
        for (let g = 0; g < run.glyphs.length; g++) {
          const offset: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          if (offset < fromOffset || offset > toOffset) {
            continue;
          }
          const pt = new GlyphPoint();
          pt.x = paddingLeftPx + run.runOffsetX + run.positions[g].x;
          pt.y = line.baseline + run.positions[g].y;
          pt.glyph = run.glyphs[g];
          pt.font = run.font;
          pt.width = run.advances[g].x;
          pt.height = line.ascent + line.descent;
          // 注册键用真实码元偏移，与 GlyphRenderer 查找键保持一致
          map.set(offset, pt);
        }
      }
    }
    return map;
  }

  /** 编辑前后对比生成字形动画集合（输入为排版行数组） */
  static createEditAnimations(oldLines: LayoutLine[], newLines: LayoutLine[],
    opts: GlyphDiffOptions): GlyphAnimRegistry {
    const anims = new GlyphAnimRegistry();
    const from: number = Math.max(0, opts.hintOffset - opts.windowRadius);
    const to: number = opts.hintOffset + opts.windowRadius;

    const originalMap: Map<number, GlyphPoint> =
      GlyphAnimator.buildGlyphMapFromLines(oldLines, opts.paddingLeftPx, opts.paddingTopPx, from, to);
    const oldMap: Map<number, GlyphPoint> = new Map<number, GlyphPoint>();

    // 前后缀扫描只在**窗口内**求精确，边界处理如下：
    //   前缀：从 from 开始扫（窗口之前的差异不影响窗口内的配对）；
    //   后缀：下探到 max(prefix, from) 为止。两侧同步递减，故
    //        newEnd - oldEnd（= 位移量 delta）始终正确；被判为"变更区"的字形
    //        一定 < from，本就在窗口外、不参与动画。
    // 旧实现从 0 扫到全文，而"在文末继续写"时前缀恰好等于全文长度 ——
    // 每次按键都是一次 O(文档) 的字符比较。
    let prefix: number = Math.min(from, Math.min(opts.oldText.length, opts.newText.length));
    while (prefix < opts.oldText.length && prefix < opts.newText.length &&
      opts.oldText.charCodeAt(prefix) === opts.newText.charCodeAt(prefix)) {
      prefix++;
    }
    prefix = Math.min(GraphemeUtil.snapToBoundary(opts.oldText, prefix),
      GraphemeUtil.snapToBoundary(opts.newText, prefix));
    let oldEnd: number = opts.oldText.length;
    let newEnd: number = opts.newText.length;
    const suffixFloor: number = Math.max(prefix, from);
    while (oldEnd > suffixFloor && newEnd > prefix &&
      opts.oldText.charCodeAt(oldEnd - 1) === opts.newText.charCodeAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    originalMap.forEach((point: GlyphPoint, offset: number) => {
      const key: number = offset < prefix ? offset : offset >= oldEnd ? offset + newEnd - oldEnd : -offset - 1;
      oldMap.set(key, point);
    });
    const newMap: Map<number, GlyphPoint> =
      GlyphAnimator.buildGlyphMapFromLines(newLines, opts.paddingLeftPx, opts.paddingTopPx, from, to);

    // 单次编辑最多做滑动过渡的字形数（防止长文本折行时整段让位导致乱飞/性能）
    const MAX_SLIDES: number = 80;
    let slideCount: number = 0;
    // 退场动画上限：大段删除若逐字形退场，会既慢又乱（深色背景尤明显），超过即瞬间消失
    const MAX_EXITS: number = 24;
    let exitCount: number = 0;

    // 两趟代替「old+new 合并成数组再 Set 去重」：
    // oldMap 的负键（-offset-1，表示落在变更区内）永远不会出现在 newMap 里
    // （newMap 的键都是非负偏移），故两趟遍历与去重后的并集**完全等价**，
    // 但省掉一个 2N 长度的数组和一次 N 项 Set 插入。
    oldMap.forEach((oldP: GlyphPoint, key: number): void => {
      const newP: GlyphPoint | undefined = newMap.get(key);
      if (newP === undefined) {
        // 仅旧存在 → 删除退场：收缩 + 淡出（绘制于旧位置）
        if (exitCount >= MAX_EXITS) {
          return;
        }
        exitCount++;
        const st = new GlyphAnimState();
        st.fromX = oldP.x;
        st.fromY = oldP.y;
        st.toX = oldP.x;
        st.toY = oldP.y;
        st.fromAlpha = 1;
        st.toAlpha = 0;
        st.fromScale = 1;
        st.toScale = 0.6;
        st.glyph = oldP.glyph;
        st.font = oldP.font;
        st.glyphWidth = oldP.width;
        st.glyphHeight = oldP.height;
        st.exiting = true;
        anims.exits.push(st);
        return;
      }
      // 前后均存在：默认位置由重排直接更新，不做让位动画（避免连续输入乱飞）。
      // 仅当发生跨行动（换行/回行）且数量受控时，做一次短时纵向滑动过渡，
      // 缓解"换行动画乱跳"。
      const dy: number = Math.abs(newP.y - oldP.y);
      if (opts.rowThresholdVp > 0 && dy > opts.rowThresholdVp && slideCount < MAX_SLIDES) {
        const st = new GlyphAnimState();
        st.fromX = oldP.x;
        st.fromY = oldP.y;
        st.toX = newP.x;
        st.toY = newP.y;
        st.fromAlpha = 1;
        st.toAlpha = 1;
        st.fromScale = 1;
        st.toScale = 1;
        st.glyph = newP.glyph;
        st.font = newP.font;
        st.glyphWidth = newP.width;
        st.glyphHeight = newP.height;
        st.exiting = false;
        anims.map.set(key, st);
        slideCount++;
      }
    });
    newMap.forEach((newP: GlyphPoint, key: number): void => {
      if (oldMap.has(key)) {
        return; // 已在上一趟处理（滑动或不动）
      }
      // 仅新存在 → 插入入场：缩放 + 淡入
      const st = new GlyphAnimState();
      st.fromX = newP.x;
      st.fromY = newP.y;
      st.toX = newP.x;
      st.toY = newP.y;
      st.fromAlpha = 0;
      st.toAlpha = 1;
      st.fromScale = 0.6;
      st.toScale = 1;
      st.glyph = newP.glyph;
      st.font = newP.font;
      st.glyphWidth = newP.width;
      st.glyphHeight = newP.height;
      st.exiting = false;
      anims.map.set(key, st);
    });
    return anims;
  }
}
