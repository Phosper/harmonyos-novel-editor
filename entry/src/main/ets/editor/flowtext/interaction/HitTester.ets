/**
 * FlowText 命中测试
 *
 * 坐标 ↔ 字符偏移 / 光标位置 的换算。
 * 坐标约定：内容区从 (paddingLeftPx, paddingTopPx) 起；行 y = paddingTopPx + line.yOffset。
 */
import { LayoutLine } from '../render/TextLayoutEngine';
import { CursorState } from './CursorState';
import { GraphemeUtil } from '../model/GraphemeUtil';

export class HitTester {
  /**
   * 视口坐标 → 字符偏移（UTF-16 code unit）。
   *
   * @param source 全文。传入后可把命中结果吸附到字符边界 —— 字形是按"字符"排布的，
   *   而 run.glyphs 的下标与码元索引在 emoji（代理对）上并非一一对应，
   *   不吸附就可能把光标放进半个字符里。传空串则跳过吸附（仅内部调试用）。
   */
  static hitTest(x: number, y: number, lines: LayoutLine[], paddingLeftPx: number, paddingTopPx: number,
    source: string = ''): number {
    if (lines.length === 0) {
      return 0;
    }
    const raw: number = HitTester.hitTestRaw(x, y, lines, paddingLeftPx, paddingTopPx);
    if (source === '') {
      return raw;
    }
    return HitTester.snapToNearestBoundary(source, raw);
  }

  /**
   * 把偏移吸附到**就近**的字符边界。
   *
   * 逐字形累加得到的 raw 可能是字符内部的码元位置（如emoji 的第2 个码元）。
   * 此时比较它到"前一边界"与"后一边界"的距离，取更近者：
   *   - 点在字形左半 → 落到字符之前
   *   - 点在字形右半 → 落到字符之后
   * 这样无论点哪儿，光标都停在合法边界上，且符合用户直觉。
   */
  private static snapToNearestBoundary(source: string, raw: number): number {
    if (raw <= 0 || raw >= source.length) {
      return raw < 0 ? 0 : source.length;
    }
    if (GraphemeUtil.isBoundary(source, raw)) {
      return raw;
    }
    const prev: number = GraphemeUtil.snapToBoundary(source, raw);
    const next: number = GraphemeUtil.moveRight(source, prev);
    return (raw - prev) <= (next - raw) ? prev : next;
  }

  /** 未做边界处理的原始命中 */
  private static hitTestRaw(x: number, y: number, lines: LayoutLine[], paddingLeftPx: number,
    paddingTopPx: number): number {
    const contentY: number = y - paddingTopPx;
    let targetLine: LayoutLine | null = null;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 用行步进（含行距）匹配，点击行间距区域归入当前行
      if (contentY >= line.yOffset && contentY < line.yOffset + line.step) {
        targetLine = line;
        break;
      }
    }
    if (targetLine === null) {
      if (contentY < 0) {
        return 0;
      }
      const last = lines[lines.length - 1];
      return last.endIndex;
    }
    const contentX: number = x - paddingLeftPx;
    if (targetLine.nativeLine !== null) {
      return Math.max(targetLine.startIndex, Math.min(targetLine.endIndex,
        targetLine.startIndex + targetLine.indexMap.fromScalar(targetLine.nativeLine.getStringIndexForPosition(
          { x: contentX * targetLine.pxPerVp, y: 0 }) - targetLine.nativeStartIndex)));
    }
    if (contentX <= 0) {
      return targetLine.startIndex;
    }
    if (contentX >= targetLine.width) {
      return targetLine.endIndex;
    }
    // 行内定位：逐字形累加宽度
    let runX = 0;
    for (let r = 0; r < targetLine.runs.length; r++) {
      const run = targetLine.runs[r];
      for (let g = 0; g < run.glyphs.length; g++) {
        const left: number = runX;
        const right: number = left + run.advances[g].x;
        if (contentX < right) {
          // 取最近边界。用逐字形的真实码元偏移，而不是 textStart + g：
          // emoji 是 1 字形占 2 码元，后者会返回半个字符的位置。
          if (contentX - left < right - contentX) {
            return run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
          }
          return run.offsetAfterGlyph(g);
        }
        runX = right;
      }
    }
    return targetLine.endIndex;
  }

  /** 字符偏移 → 光标状态（x/y/height；y 为内容坐标，不含 paddingTop，绘制时统一加 padTop）
   *  光标垂直对齐"文字中线"：top = 行基线 - 0.8*字形(近似ascend)，height = 字形(≈字号)，跨行一致。 */
  static caretPositionFor(offset: number, lines: LayoutLine[], paddingLeftPx: number, paddingTopPx: number,
    fontSizeVp: number): CursorState {
    const caret = new CursorState();
    if (lines.length === 0) {
      caret.x = paddingLeftPx;
      caret.y = 0;
      caret.height = fontSizeVp;
      return caret;
    }
    let target: LayoutLine = lines[0];
    for (let i = 0; i < lines.length; i++) {
      if (offset >= lines[i].startIndex && (offset < lines[i].endIndex ||
        (offset === lines[i].endIndex && (i === lines.length - 1 || lines[i + 1].startIndex !== offset)))) {
        target = lines[i];
        break;
      }
      if (i === lines.length - 1 && offset > lines[i].endIndex) {
        target = lines[i];
      }
    }
    caret.x = HitTester.offsetToX(target, offset, paddingLeftPx);
    // 光标顶端推到文字字形顶部（近似 ascend = 0.8*fs），高度 = 字形高 → 垂直对齐文字中线
    caret.y = target.baseline - target.ascent;
    caret.height = Math.max(fontSizeVp, target.ascent + target.descent);
    return caret;
  }

  /**
   * 求某偏移所在行的下标；超出已排版范围时返回最后一行。
   * 键盘上下移动光标时需要它来定位目标行。
   */
  static lineIndexOf(offset: number, lines: LayoutLine[]): number {
    if (lines.length === 0) {
      return -1;
    }
    for (let i: number = 0; i < lines.length; i++) {
      const l: LayoutLine = lines[i];
      // 行尾（含）与下一行起点之间都算本行，便于用 endIndex 命中换行符位置
      if (offset >= l.startIndex && (offset < l.endIndex || (offset === l.endIndex &&
        (i === lines.length - 1 || lines[i + 1].startIndex !== offset)))) {
        return i;
      }
    }
    return lines.length - 1;
  }

  /**
   * 上下移动光标：在 targetLineIndex 行内按 targetColumn 放置光标。
   *
   * @param column 目标列（字符序号，非码元）—— 取自原行的光标列，
   *   换行到较短的一行时自然被截断到该行末尾，这是常规编辑器行为。
   * @return 目标偏移；无可用行时返回原偏移
   */
  static offsetAtLineColumn(lines: LayoutLine[], targetLineIndex: number, column: number,
    fallback: number): number {
    if (lines.length === 0 || targetLineIndex < 0 || targetLineIndex >= lines.length) {
      return fallback;
    }
    const line: LayoutLine = lines[targetLineIndex];
    // 逐字形累加，取第 column 个字符的起点；超出则落到行尾
    let acc: number = 0;
    for (let r: number = 0; r < line.runs.length; r++) {
      const run = line.runs[r];
      for (let g: number = 0; g < run.glyphs.length; g++) {
        if (acc === column) {
          return run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
        }
        acc++;
      }
    }
    return line.endIndex;
  }

  /** 偏移在该行内的字符列号（字形序号） */
  static columnOf(offset: number, lines: LayoutLine[]): number {
    const idx: number = HitTester.lineIndexOf(offset, lines);
    if (idx < 0) {
      return 0;
    }
    const line: LayoutLine = lines[idx];
    let acc: number = 0;
    for (let r: number = 0; r < line.runs.length; r++) {
      const run = line.runs[r];
      for (let g: number = 0; g < run.glyphs.length; g++) {
        const start: number = run.textStart + (g < run.glyphOffsets.length ? run.glyphOffsets[g] : g);
        if (offset <= start) {
          return acc;
        }
        acc++;
      }
    }
    return acc;
  }

  /** 行首偏移 */
  static lineStartOffset(lines: LayoutLine[], lineIndex: number): number {
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return 0;
    }
    return lines[lineIndex].startIndex;
  }

  /** 行尾偏移 */
  static lineEndOffset(lines: LayoutLine[], lineIndex: number): number {
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return 0;
    }
    return lines[lineIndex].endIndex;
  }

  /** 行内字符偏移 → x（px） */
  static offsetToX(line: LayoutLine, offset: number, paddingLeftPx: number): number {
    if (line.nativeLine !== null) {
      return paddingLeftPx + line.nativeLine.getOffsetForStringIndex(
        line.nativeStartIndex + line.indexMap.toScalar(Math.max(0, Math.min(line.endIndex - line.startIndex,
          offset - line.startIndex)))) / line.pxPerVp;
    }
    if (offset <= line.startIndex) {
      return paddingLeftPx;
    }
    if (offset >= line.endIndex) {
      return paddingLeftPx + line.width;
    }
    let x = paddingLeftPx;
    for (let r = 0; r < line.runs.length; r++) {
      const run = line.runs[r];
      if (offset <= run.textStart) {
        return x;
      }
      if (offset >= run.textEnd) {
        x += run.width();
        continue;
      }
      // 码元偏移落在哪个字形内，就取该字形的左边界 x。
      // 不能用 offset - textStart 当下标：emoji 占 2 码元会让下标越界或错位。
      const gi: number = run.glyphIndexAt(offset);
      if (gi < 0) {
        return x;
      }
      return x + run.positions[gi].x;
    }
    return x;
  }
}
