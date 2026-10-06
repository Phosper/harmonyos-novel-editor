/**
 * FlowText 字形动画生成器
 *
 * 编辑前后对比字形位置映射，为每个受影响字符生成插值动画：
 *   前后均存在 → 让位/回流/换行（位置插值）
 *   仅新出现   → 入场（缩放 0.6→1 + 淡入）
 *   仅旧存在   → 退场（收缩 + 淡出，绘制于旧位置）
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

export class GlyphAnimator {
  /** 构建"字符偏移 → 字形位置+绘制数据"映射（输入为排版行数组） */
  static buildGlyphMapFromLines(lines: LayoutLine[], paddingLeftPx: number, paddingTopPx: number): Map<number, GlyphPoint> {
    const map = new Map<number, GlyphPoint>();
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      for (let r = 0; r < line.runs.length; r++) {
        const run = line.runs[r];
        let x = paddingLeftPx + run.runOffsetX;
        for (let g = 0; g < run.glyphs.length; g++) {
          const pt = new GlyphPoint();
          pt.x = paddingLeftPx + run.runOffsetX + run.positions[g].x;
          pt.y = line.baseline + run.positions[g].y;
          pt.glyph = run.glyphs[g];
          pt.font = run.font;
          pt.width = run.advances[g].x;
          pt.height = line.ascent + line.descent;
          // 注册键用真实码元偏移，与 GlyphRenderer 查找键保持一致
          map.set(run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g), pt);
          x += run.advances[g].x;
        }
      }
    }
    return map;
  }

  /** 编辑前后对比生成字形动画集合（输入为排版行数组）
   *  rowThresholdVp：视为"跨行动（换行/回行）"的最小纵向位移，用于对已存在但换行的字形做短时滑动过渡。 */
  static createEditAnimations(oldLines: LayoutLine[], newLines: LayoutLine[],
    paddingLeftPx: number, paddingTopPx: number, rowThresholdVp: number = 0,
    oldText: string = '', newText: string = ''): GlyphAnimRegistry {
    const anims = new GlyphAnimRegistry();
    const originalMap: Map<number, GlyphPoint> =
      GlyphAnimator.buildGlyphMapFromLines(oldLines, paddingLeftPx, paddingTopPx);
    const oldMap: Map<number, GlyphPoint> = new Map<number, GlyphPoint>();
    let prefix: number = 0;
    while (prefix < oldText.length && prefix < newText.length && oldText.charAt(prefix) === newText.charAt(prefix)) { prefix++; }
    prefix = Math.min(GraphemeUtil.snapToBoundary(oldText, prefix), GraphemeUtil.snapToBoundary(newText, prefix));
    let oldEnd: number = oldText.length;
    let newEnd: number = newText.length;
    while (oldEnd > prefix && newEnd > prefix && oldText.charAt(oldEnd - 1) === newText.charAt(newEnd - 1)) { oldEnd--; newEnd--; }
    while (oldEnd < oldText.length && (!GraphemeUtil.isBoundary(oldText, oldEnd) || !GraphemeUtil.isBoundary(newText, newEnd))) { oldEnd++; newEnd++; }
    originalMap.forEach((point: GlyphPoint, offset: number) => {
      const key: number = offset < prefix ? offset : offset >= oldEnd ? offset + newEnd - oldEnd : -offset - 1;
      oldMap.set(key, point);
    });
    const newMap: Map<number, GlyphPoint> =
      GlyphAnimator.buildGlyphMapFromLines(newLines, paddingLeftPx, paddingTopPx);

    // 单次编辑最多做滑动过渡的字形数（防止长文本折行时整段让位导致乱飞/性能）
    const MAX_SLIDES: number = 80;
    let slideCount: number = 0;
    // 退场动画上限：大段删除若逐字形退场，会既慢又乱（深色背景尤明显），超过即瞬间消失
    const MAX_EXITS: number = 24;
    let exitCount: number = 0;

    const offsets: number[] = [];
    oldMap.forEach((value: GlyphPoint, key: number) => {
      offsets.push(key);
    });
    newMap.forEach((value: GlyphPoint, key: number) => {
      offsets.push(key);
    });
    // 去重
    const seen = new Set<number>();
    for (let i = 0; i < offsets.length; i++) {
      seen.add(offsets[i]);
    }
    seen.forEach((offset: number) => {
      const oldP: GlyphPoint | undefined = oldMap.get(offset);
      const newP: GlyphPoint | undefined = newMap.get(offset);
      const st = new GlyphAnimState();
      if (oldP !== undefined && newP !== undefined) {
        // 前后均存在：默认位置由重排直接更新，不做让位动画（避免连续输入乱飞）。
        // 仅当发生跨行动（换行/回行）且数量受控时，做一次短时纵向滑动过渡，缓解"换行动画乱跳"。
        const dy: number = Math.abs(newP.y - oldP.y);
        if (rowThresholdVp > 0 && dy > rowThresholdVp && slideCount < MAX_SLIDES) {
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
          anims.map.set(offset, st);
          slideCount += 1;
        }
        return;
      } else if (newP !== undefined) {
        // 插入入场：缩放 + 淡入
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
        anims.map.set(offset, st);
      } else if (oldP !== undefined) {
        // 删除退场：收缩 + 淡出（绘制于旧位置）
        // 大段删除时退场字形过多会既慢又乱（深色下尤其明显）：仅前 MAX_EXITS 个退场，其余瞬间消失
        if (exitCount >= MAX_EXITS) {
          return;
        }
        exitCount += 1;
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
      }
    });
    return anims;
  }
}
