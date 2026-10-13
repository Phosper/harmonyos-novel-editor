import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import { KeyCode } from '@kit.InputKit';
import { GraphemeUtil } from '../../../main/ets/editor/flowtext/model/GraphemeUtil';
import { TextDocument } from '../../../main/ets/editor/flowtext/model/TextDocument';
import { FormatRun, StyleKind } from '../../../main/ets/editor/flowtext/model/EditorTypes';
import { SelectionManager } from '../../../main/ets/editor/flowtext/interaction/SelectionManager';
import { HitTester } from '../../../main/ets/editor/flowtext/interaction/HitTester';
import { TextLayoutEngine, LayoutLine } from '../../../main/ets/editor/flowtext/render/TextLayoutEngine';
import { LayoutCache } from '../../../main/ets/editor/flowtext/render/LayoutCache';
import { PreviewTextManager } from '../../../main/ets/editor/flowtext/ime/PreviewTextManager';
import { FlowTextFixture } from './FlowTextFixture';

function layout(value: string, width: number = 240, density: number = 1, runs: FormatRun[] = []): LayoutLine[] {
  const engine: TextLayoutEngine = new TextLayoutEngine(width, 16, 24, 4, density);
  engine.setRuns(runs);
  const cache: LayoutCache = new LayoutCache(engine);
  return cache.ensureLayout(value, 1, 1, 1000000);
}

export default function flowTextTest(): void {
  describe('FlowTextRegression', () => {
    it('nativeApiContract', 0, () => {
      const engine: TextLayoutEngine = new TextLayoutEngine(240, 16, 24, 4, 1);
      const typeset = engine.buildTypeset('A😀B');
      expect(typeset.getLineBreak(0, 10000)).assertEqual(3);
      const native = typeset.createLine(0, 3);
      expect(native.getOffsetForStringIndex(2) > native.getOffsetForStringIndex(1)).assertTrue();
      expect(native.getGlyphRuns()[2].getStringRange().start).assertEqual(2);
    });
    it('nativeCreatedLineUsesItsOwnIndexOrigin', 0, () => {
      const engine: TextLayoutEngine = new TextLayoutEngine(240, 16, 24, 4, 1);
      const typeset = engine.buildTypeset('XX😀A😀B');
      const native = typeset.createLine(3, 3);
      const range = native.getTextRange();
      const runRange = native.getGlyphRuns()[0].getStringRange();
      const x0: number = native.getOffsetForStringIndex(0);
      const x1: number = native.getOffsetForStringIndex(1);
      const hit: number = native.getStringIndexForPosition({ x: x1 + 0.1, y: 0 });
      if (range.start !== 0 || runRange.start !== 0 || x0 !== 0 || x1 <= x0 || hit !== 1) {
        throw new Error('Created line index contract: textRange=' + range.start + '+' + range.end +
          ' runRange=' + runRange.start + '+' + runRange.end + ' x0=' + x0 + ' x1=' + x1 + ' hit=' + hit);
      }
      expect(range.start).assertEqual(0);
      expect(runRange.start).assertEqual(0);
      expect(x1 > x0).assertTrue();
      expect(hit).assertEqual(1);
    });
    it('nativeWindowExcludesLaterFormatting', 0, () => {
      const engine: TextLayoutEngine = new TextLayoutEngine(10000, 16, 24, 4, 1);
      engine.setRuns([new FormatRun(5, 7, true)]);
      const typeset = engine.buildTypesetWindow('ABCDEFGH', 0, 3);
      // A run beyond the window must not append the window text a second time.
      expect(typeset.getLineBreak(0, 10000)).assertEqual(3);
    });
    it('nativeWindowRestoresDocumentOffsetsAfterEmoji', 0, () => {
      const value: string = '😀prefix\nA😀B\nsuffix';
      const base: number = value.indexOf('A');
      const end: number = value.indexOf('\n', base);
      const engine: TextLayoutEngine = new TextLayoutEngine(10000, 16, 24, 4, 1);
      engine.setRuns([new FormatRun(0, base, true), new FormatRun(base + 1, value.length, false, true)]);
      const typeset = engine.buildTypesetWindow(value, base, end);
      expect(typeset.getLineBreak(0, 10000)).assertEqual(3);
      expect(engine.lineBreak(typeset, base)).assertEqual(4);
      const line: LayoutLine = engine.createLayoutLine(typeset, base, 4, 0);
      expect(line.startIndex).assertEqual(base);
      expect(line.endIndex).assertEqual(end);
      let offsets: number[] = [];
      for (const run of line.runs) {
        for (const offset of run.glyphOffsets) {
          offsets.push(run.textStart + offset);
        }
      }
      expect(offsets.includes(base)).assertTrue();
      expect(offsets.includes(base + 1)).assertTrue();
      expect(offsets.includes(base + 3)).assertTrue();
      expect(offsets.includes(base + 2)).assertFalse();
    });
    it('nativeLayoutCrossesMultipleParagraphWindows', 0, () => {
      const paragraph: string = '中文 A😀B '.repeat(40) + '\n';
      const value: string = paragraph.repeat(15) + '尾段😀';
      const lines: LayoutLine[] = layout(value, 240, 1,
        [new FormatRun(value.length - 4, value.length, true)]);
      expect(lines[lines.length - 1].endIndex).assertEqual(value.length);
      const nextWindowStart: number = value.indexOf('\n', 4000) + 1;
      let sampledWrap: boolean = false;
      let sampledNextWindow: boolean = false;
      for (let i: number = 0; i < lines.length; i++) {
        const line: LayoutLine = lines[i];
        expect(line.startIndex <= line.endIndex).assertTrue();
        expect(GraphemeUtil.isBoundary(value, line.startIndex)).assertTrue();
        expect(GraphemeUtil.isBoundary(value, line.endIndex)).assertTrue();
        const sampleCaret: boolean = i === 1 || (!sampledNextWindow && line.startIndex >= nextWindowStart);
        if (sampleCaret && line.nativeLine !== null && line.startIndex < line.endIndex) {
          const at: number = GraphemeUtil.moveRight(value, line.startIndex);
          const x: number = HitTester.offsetToX(line, at, 0);
          const nativeIndex: number = line.nativeStartIndex + line.indexMap.toScalar(at - line.startIndex);
          expect(Math.abs(x - line.nativeLine.getOffsetForStringIndex(nativeIndex))).assertLess(0.01);
          const hit: number = HitTester.hitTest(x, line.yOffset + line.height / 2, [line], 0, 0, value);
          if (hit !== at) {
            throw new Error('Caret round-trip: line=[' + line.startIndex + ',' + line.endIndex +
              ') at=' + at + ' x=' + x + ' nativeIndex=' + nativeIndex + ' hit=' + hit);
          }
          expect(hit).assertEqual(at);
          sampledWrap = sampledWrap || i === 1;
          sampledNextWindow = sampledNextWindow || line.startIndex >= nextWindowStart;
        }
        for (let r: number = 0; r < line.runs.length; r++) {
          const run = line.runs[r];
          for (const offset of run.glyphOffsets) {
            const absolute: number = run.textStart + offset;
            if (absolute < line.startIndex || absolute >= line.endIndex) {
              let nativeDetails: string = '';
              if (line.nativeLine !== null) {
                const nativeRun = line.nativeLine.getGlyphRuns()[r];
                const nativeRange = nativeRun.getStringRange();
                nativeDetails = ' nativeRange=' + nativeRange.start + '+' + nativeRange.end +
                  ' nativeIndices=' + nativeRun.getStringIndices().join(',') +
                  ' textRange=' + line.nativeLine.getTextRange().start + '+' + line.nativeLine.getTextRange().end +
                  ' x0=' + line.nativeLine.getOffsetForStringIndex(0) +
                  ' x1=' + line.nativeLine.getOffsetForStringIndex(1) +
                  ' hit0=' + line.nativeLine.getStringIndexForPosition({ x: 0, y: 0 });
              }
              throw new Error('Glyph outside line: absolute=' + absolute + ' line=[' + line.startIndex +
                ',' + line.endIndex + ') nativeStart=' + line.nativeStartIndex + ' run=[' + run.textStart +
                ',' + run.textEnd + ') offsets=' + run.glyphOffsets.join(',') + nativeDetails);
            }
            expect(absolute >= line.startIndex && absolute < line.endIndex).assertTrue();
          }
        }
      }
      expect(sampledWrap).assertTrue();
      expect(sampledNextWindow).assertTrue();
    });
    it('graphemeDeletionPreservesPrefix', 0, () => {
      const samples: string[] = ['A😀', '甲𠮷', 'a👨‍👩‍👧', 'A👍🏽', 'A🇨🇳', 'Ae\u0301'];
      for (let i: number = 0; i < samples.length; i++) {
        const doc: TextDocument = new TextDocument();
        doc.setText(samples[i]);
        doc.deleteLeft(1);
        expect(doc.text).assertEqual(samples[i].substring(0, 1));
      }
    });
    it('selectionAnchorSurvivesRepeatedExtension', 0, () => {
      const selection: SelectionManager = new SelectionManager();
      selection.setSource('ABCDE'); selection.collapse(4);
      selection.extendTo(3); selection.extendTo(2);
      expect(selection.selection.startOffset).assertEqual(2);
      expect(selection.anchor).assertEqual(4);
      expect(selection.head).assertEqual(2);
    });
    it('mixedBoldSelectionFillsGaps', 0, () => {
      const doc: TextDocument = new TextDocument(); doc.setText('abcd');
      doc.setRuns([new FormatRun(0, 1, true)]); doc.toggleInline(StyleKind.BOLD, 0, 4);
      expect(doc.runs.length).assertEqual(1); expect(doc.runs[0].endOffset).assertEqual(4);
      expect(doc.runs[0].bold).assertTrue();
    });
    it('previewRangeAndCommitSnapshot', 0, () => {
      const preview: PreviewTextManager = new PreviewTextManager();
      preview.update('aaa', -1, -1, 5, 7); preview.update('X', 6, 7);
      const committed = preview.commit();
      expect(committed !== null).assertTrue();
      if (committed !== null) { expect(committed.text).assertEqual('aXa'); expect(committed.endOffset).assertEqual(7); }
      expect(preview.isComposing).assertFalse();
    });
    it('nativeMixedTextIndicesAndCaret', 0, () => {
      const value: string = 'A😀B中文 office e\u0301 🇨🇳';
      const lines: LayoutLine[] = layout(value);
      expect(lines[lines.length - 1].endIndex).assertEqual(value.length);
      for (let i: number = 0; i < lines.length; i++) {
        const line: LayoutLine = lines[i];
        for (let r: number = 0; r < line.runs.length; r++) {
          const run = line.runs[r];
          for (let g: number = 0; g < run.glyphOffsets.length; g++) {
            const offset: number = run.textStart + run.glyphOffsets[g];
            expect(offset >= line.startIndex && offset < line.endIndex).assertTrue();
          }
        }
        const native = line.nativeLine;
        if (native !== null) {
          let at: number = line.startIndex;
          while (at < line.endIndex) {
            const x: number = HitTester.offsetToX(line, at, 0);
            expect(Number.isFinite(x)).assertTrue();
            expect(Math.abs(x - native.getOffsetForStringIndex(line.nativeStartIndex + line.indexMap.toScalar(at - line.startIndex)))).assertLess(0.01);
            at = GraphemeUtil.moveRight(value, at);
          }
        }
      }
    });
    it('nativeBlankAndTrailingParagraphs', 0, () => {
      const blank: LayoutLine[] = layout(''); expect(blank.length).assertEqual(1);
      expect(HitTester.caretPositionFor(0, blank, 12, 8, 16).height > 0).assertTrue();
      const lines: LayoutLine[] = layout('A\n\n'); expect(lines.length).assertEqual(3);
      expect(lines[2].startIndex).assertEqual(3);
    });
    it('nativeWidthChangeReflowsText', 0, () => {
      const value: string = '中文和 English 的宽度变化测试。'.repeat(12);
      expect(layout(value, 100).length > layout(value, 480).length).assertTrue();
    });
    it('nativeNarrowWrapKeepsEmojiClustersWhole', 0, () => {
      const value: string = 'A👨‍👩‍👧👍🏽🇨🇳B';
      const lines: LayoutLine[] = layout(value, 12);
      for (let i: number = 0; i < lines.length; i++) {
        expect(GraphemeUtil.isBoundary(value, lines[i].startIndex)).assertTrue();
        expect(GraphemeUtil.isBoundary(value, lines[i].endIndex)).assertTrue();
      }
      expect(lines[lines.length - 1].endIndex).assertEqual(value.length);
    });
    it('nativeWordBoundaryAfterEmojiUsesDocumentOffsets', 0, () => {
      const engine: TextLayoutEngine = new TextLayoutEngine(240, 16, 24, 4, 1);
      const range: number[] = engine.wordRangeAt('😀hello 世界', 4);
      expect(range[0]).assertEqual(2); expect(range[1]).assertEqual(7);
    });
    it('nativeHeadingMetricsReserveEnoughHeight', 0, () => {
      const value: string = '大标题';
      const normal: LayoutLine = layout(value)[0];
      const heading: LayoutLine = layout(value, 240, 1, [new FormatRun(0, value.length, false, false, 1)])[0];
      expect(heading.height >= heading.ascent + heading.descent).assertTrue();
      expect(heading.height > normal.height).assertTrue();
    });
    it('nativeDensityKeepsVpCoordinates', 0, () => {
      const value: string = 'A😀中文';
      const one: LayoutLine = layout(value, 240, 1)[0]; const two: LayoutLine = layout(value, 240, 2)[0];
      expect(Math.abs(one.width - two.width)).assertLess(2);
    });
    it('nativeBidiAndLigaturesHaveFiniteGeometry', 0, () => {
      const values: string[] = ['office affine ffi', 'ABC אבג DEF', 'سلام world'];
      for (let i: number = 0; i < values.length; i++) {
        const lines: LayoutLine[] = layout(values[i]);
        let at: number = 0;
        while (at <= values[i].length) {
          const caret = HitTester.caretPositionFor(at, lines, 0, 0, 16);
          expect(Number.isFinite(caret.x) && caret.height > 0).assertTrue();
          if (at === values[i].length) { break; }
          at = GraphemeUtil.moveRight(values[i], at);
        }
      }
    });
    it('nativeIncrementalLayoutRetainsEarlierParagraph', 0, () => {
      const engine: TextLayoutEngine = new TextLayoutEngine(240, 16, 24, 4, 1);
      const cache: LayoutCache = new LayoutCache(engine);
      const first: LayoutLine = cache.ensureLayout('第一段\n第二段', 1, 1, 10000)[0];
      cache.applyEdit('第一段\n第二X段', 2, 2, [], 6);
      const updated: LayoutLine[] = cache.ensureLayout('第一段\n第二X段', 2, 2, 10000);
      expect(updated[0] === first).assertTrue(); expect(updated[updated.length - 1].endIndex).assertEqual(8);
    });
    it('canvasControllerClearsSelectionAndDeletesOnlyEmoji', 0, () => {
      const controller = FlowTextFixture.controller;
      expect(FlowTextFixture.ready).assertTrue();
      controller.setText('A😀'); controller.setCaretPosition(3); controller.deleteLeftAtCaret(1);
      expect(controller.getText()).assertEqual('A');
      controller.setText('uvwxyz'); controller.setCaretPosition(6); controller.insertTextAtCaret('!');
      expect(controller.getText()).assertEqual('uvwxyz!');
    });
    it('canvasControllerRestoresAndShiftsFormat', 0, () => {
      const controller = FlowTextFixture.controller;
      controller.setText('abc'); controller.setRuns([new FormatRun(0, 3, true)]);
      controller.setCaretPosition(0); controller.insertTextAtCaret('X');
      expect(controller.getText()).assertEqual('Xabc'); expect(controller.getRuns()[0].endOffset).assertEqual(4);
      expect(FlowTextFixture.savedText).assertEqual('Xabc'); expect(FlowTextFixture.savedCaret).assertEqual(1);
      expect(FlowTextFixture.savedRuns[0].endOffset).assertEqual(4);
    });
    it('canvasPhysicalKeyboardSelectionAndEmojiBackspace', 0, async () => {
      const driver: Driver = Driver.create();
      const controller = FlowTextFixture.controller;
      controller.setText('ABCDE'); controller.setCaretPosition(4); controller.focus();
      const editor = await driver.waitForComponent(ON.id('canvasTextEditor'), 5000);
      expect(await editor.isFocused()).assertTrue();
      await driver.triggerCombineKeys(KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_DPAD_LEFT);
      await driver.triggerCombineKeys(KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_DPAD_LEFT);
      expect(FlowTextFixture.selectionStart).assertEqual(2);
      expect(FlowTextFixture.selectionEnd).assertEqual(4);
      await driver.triggerKey(KeyCode.KEYCODE_DPAD_LEFT);
      expect(FlowTextFixture.savedCaret).assertEqual(2);
      controller.setText('A😀'); controller.setCaretPosition(3);
      await driver.triggerKey(KeyCode.KEYCODE_DEL);
      expect(controller.getText()).assertEqual('A');
    });
  });
}
