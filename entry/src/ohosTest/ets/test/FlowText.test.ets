import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import { KeyCode } from '@kit.InputKit';
import { GraphemeUtil } from '../../../main/ets/editor/flowtext/model/GraphemeUtil';
import { TextDocument } from '../../../main/ets/editor/flowtext/model/TextDocument';
import { FormatRun, StyleKind, CaretAffinity } from '../../../main/ets/editor/flowtext/model/EditorTypes';
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

async function pressAndRelease(driver: Driver, first: KeyCode, second?: KeyCode): Promise<void> {
  const firstBefore: number = FlowTextFixture.keyReleaseCount(first);
  const secondBefore: number = second === undefined ? 0 : FlowTextFixture.keyReleaseCount(second);
  if (second === undefined) { await driver.triggerKey(first); }
  else { await driver.triggerCombineKeys(first, second); }
  // UI 空闲不代表注入的按键序列已处理完；收到本轮 Up 后才开始下一组输入。
  const deadline: number = Date.now() + 5000;
  while (FlowTextFixture.keyReleaseCount(first) <= firstBefore ||
    (second !== undefined && FlowTextFixture.keyReleaseCount(second) <= secondBefore)) {
    if (Date.now() >= deadline) { throw new Error('Injected keys did not finish releasing'); }
    await driver.delayMs(20);
  }
  expect(await driver.waitForIdle(200, 5000)).assertTrue();
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
    it('nativeMixedRunOriginsKeepGlyphsSeparated', 0, () => {
      const value: string = 'abc中文ABC😀 mixed';
      const lines: LayoutLine[] = layout(value, 400, 2, [new FormatRun(3, 5, true)]);
      let checked: number = 0;
      for (const line of lines) {
        if (line.nativeLine === null) { continue; }
        const nativeRuns = line.nativeLine.getGlyphRuns();
        for (let i: number = 0; i < line.runs.length; i++) {
          const run = line.runs[i];
          const raw = nativeRuns[i].getPositions();
          if (raw.length === 0) { continue; }
          const range = nativeRuns[i].getStringRange();
          let rawMin: number = raw[0].x;
          let drawnMin: number = run.positions[0].x;
          for (let g: number = 1; g < raw.length; g++) {
            rawMin = Math.min(rawMin, raw[g].x);
            drawnMin = Math.min(drawnMin, run.positions[g].x);
          }
          drawnMin += run.runOffsetX;
          const start: number = line.nativeLine.getOffsetForStringIndex(range.start);
          const end: number = line.nativeLine.getOffsetForStringIndex(range.start + range.end);
          const origin: number = Math.min(start, end) / line.pxPerVp;
          console.info('FlowText native run ' + range.start + '+' + range.end +
            ' rawMin=' + rawMin + ' caretStart=' + start + ' caretEnd=' + end +
            ' offset=' + run.runOffsetX + ' drawnMin=' + drawnMin);
          if (Math.abs(rawMin) < 0.01 && origin > 0.01) {
            expect(Math.abs(drawnMin - origin) < 0.01).assertTrue();
          } else {
            expect(run.runOffsetX).assertEqual(0);
            expect(Math.abs(drawnMin - rawMin / line.pxPerVp) < 0.01).assertTrue();
          }
          checked++;
        }
      }
      expect(checked > 1).assertTrue();
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
    it('canvasHeadingAtParagraphStartUpdatesNativeLayoutAndFormats', 0, () => {
      const controller = FlowTextFixture.controller;
      controller.setDocument('abc\ndef', [], 4);controller.toggleParagraphStyle(1);
      const runs: FormatRun[] = controller.getRuns();
      expect(runs.length).assertEqual(1);expect(runs[0].startOffset).assertEqual(4);
      expect(runs[0].endOffset).assertEqual(7);expect(runs[0].heading).assertEqual(1);
      expect(FlowTextFixture.savedText).assertEqual('abc\ndef');expect(FlowTextFixture.savedCaret).assertEqual(4);
      expect(FlowTextFixture.savedRuns[0].heading).assertEqual(1);
      controller.toggleParagraphStyle(1);expect(controller.getRuns().length).assertEqual(0);
    });
    it('canvasPhysicalKeyboardSelectionAndEmojiBackspace', 0, async () => {
      const driver: Driver = Driver.create();
      const controller = FlowTextFixture.controller;
      controller.setText('ABCDE'); controller.setCaretPosition(4); controller.focus();
      const editor = await driver.waitForComponent(ON.id('canvasTextEditor'), 5000);
      expect(await editor.isFocused()).assertTrue();
      // 焦点确认不等于异步 IME attach 和编辑器帧已落定；先等待输入准备结束。
      expect(await driver.waitForIdle(200, 5000)).assertTrue();
      expect(FlowTextFixture.savedCaret).assertEqual(4);
      await pressAndRelease(driver, KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_DPAD_LEFT);
      expect(FlowTextFixture.selectionStart).assertEqual(3);
      expect(FlowTextFixture.selectionEnd).assertEqual(4);
      controller.insertTextAtCaret('');
      expect(controller.getText()).assertEqual('ABCDE');
      expect(FlowTextFixture.selectionStart).assertEqual(3);
      expect(FlowTextFixture.selectionEnd).assertEqual(4);
      await pressAndRelease(driver, KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_DPAD_LEFT);
      expect(FlowTextFixture.selectionStart).assertEqual(2);
      expect(FlowTextFixture.selectionEnd).assertEqual(4);
      await pressAndRelease(driver, KeyCode.KEYCODE_DPAD_LEFT);
      expect(FlowTextFixture.savedCaret).assertEqual(2);
      controller.setText('A😀'); controller.setCaretPosition(3);
      expect(await driver.waitForIdle(200, 5000)).assertTrue();
      expect(FlowTextFixture.savedCaret).assertEqual(3);
      await pressAndRelease(driver, KeyCode.KEYCODE_DEL);
      expect(controller.getText()).assertEqual('A');
    });
    it('multiRunLinesKeepLineRelativeOrigins', 0, () => {
      // Preserve Jouko's mixed-format probe while checking final drawn coordinates.
      const lines: LayoutLine[] = layout('abc中文ABC', 240, 1, [new FormatRun(3, 7, true)]);
      let checked: number = 0;
      for (const line of lines) {
        if (line.nativeLine === null) { continue; }
        let previousX: number = -1;
        for (const run of line.runs) {
          if (run.positions.length === 0) { continue; }
          let drawnX: number = run.positions[0].x + run.runOffsetX;
          for (const position of run.positions) { drawnX = Math.min(drawnX, position.x + run.runOffsetX); }
          const scalar: number = line.nativeStartIndex + line.indexMap.toScalar(run.textStart - line.startIndex);
          const expectedX: number = line.nativeLine.getOffsetForStringIndex(scalar) / line.pxPerVp;
          expect(Math.abs(drawnX - expectedX) < 0.5).assertTrue();
          expect(drawnX >= previousX).assertTrue();
          previousX = drawnX;
          checked++;
        }
      }
      expect(checked > 1).assertTrue();
    });
    it('caretAffinityAtSoftWrapKeepsHighlightAndCaretOnSameLine', 0, () => {
      const value: string = 'abcdefghij';
      const lines: LayoutLine[] = layout(value, 25, 1);
      expect(lines.length > 1).assertTrue();
      const boundary: number = lines[0].endIndex;
      expect(lines[1].startIndex).assertEqual(boundary);
      const down = HitTester.caretPositionFor(boundary, lines, 0, 0, 16, CaretAffinity.DOWNSTREAM);
      const up = HitTester.caretPositionFor(boundary, lines, 0, 0, 16, CaretAffinity.UPSTREAM);
      // 新版 DOWNSTREAM 贴上一行行尾；UPSTREAM 贴下一行行首。
      expect(down.y < up.y).assertTrue();
      expect(down.x > up.x).assertTrue();
      expect(Math.abs(down.x - lines[0].width) < 0.5).assertTrue();
    });
    it('caretAndSelectionShareTheSameLineBox', 0, () => {
      const value: string = '标题行与正文\nsecond line with 中文';
      const lines: LayoutLine[] = layout(value, 240, 1, [new FormatRun(0, 5, false, false, 1)]);
      for (let i: number = 0; i < lines.length; i++) {
        const box = HitTester.lineBox(lines[i]);
        expect(box.height > 0).assertTrue();
      }
      const first: LayoutLine = lines[0];
      const box0 = HitTester.lineBox(first);
      const caret = HitTester.caretPositionFor(first.startIndex, lines, 12, 8, 16,
        CaretAffinity.DOWNSTREAM);
      expect(Math.abs(caret.y - box0.top) < 0.01).assertTrue();
      expect(Math.abs(caret.height - box0.height) < 0.01).assertTrue();
    });
    it('handleDragKeepsAnchorHeadIdentityWhenCrossing', 0, () => {
      const m: SelectionManager = new SelectionManager();
      m.setSource('ABCDE'); m.setSelection(1, 4);
      expect(m.anchor).assertEqual(1); expect(m.head).assertEqual(4);
      m.beginHandleDrag(1); m.updateHandleDrag(0);
      expect(m.anchor).assertEqual(0); expect(m.head).assertEqual(4);
      expect(m.startOffset).assertEqual(0); expect(m.endOffset).assertEqual(4);
      m.updateHandleDrag(5);
      expect(m.anchor).assertEqual(5); expect(m.head).assertEqual(4);
      expect(m.startOffset).assertEqual(4); expect(m.endOffset).assertEqual(5);
      expect(m.headAffinity).assertEqual(CaretAffinity.UPSTREAM);
      m.endHandleDrag();
      m.setSelection(4, 1);
      expect(m.startOffset).assertEqual(1); expect(m.endOffset).assertEqual(4);
    });
    it('nativePreviewForkRetainsCommittedParagraphsWithoutSharingTypesetState', 0, () => {
      const value: string = '中英 A😀B\n'.repeat(12) + 'tail';
      const cache: LayoutCache = new LayoutCache(new TextLayoutEngine(240, 16, 24, 4, 1));
      const committed: LayoutLine[] = cache.ensureOffset(value, 1, 1, value.length);
      const first: LayoutLine = committed[0];
      const count: number = committed.length;
      const preview: LayoutCache = cache.forkForEdit(value + '候选', 2, 2, [], value.length);
      expect(preview.ensureOffset(value + '候选', 2, 2, value.length + 2)[0] === first).assertTrue();
      preview.applyEdit(value + '中文预览', 3, 3, [], value.length);
      const changed: LayoutLine[] = preview.ensureOffset(value + '中文预览', 3, 3, value.length + 4);
      expect(changed[0] === first).assertTrue();
      expect(cache.lineCount()).assertEqual(count);
      expect(committed[committed.length - 1].endIndex).assertEqual(value.length);
      expect(changed[changed.length - 1].endIndex).assertEqual(value.length + 4);
    });
    it('nativeLayoutSlicesKeepTheSameFinalOffsetsAndGlyphBoundaries', 0, () => {
      const value: string = 'A😀中文 e\u0301\n'.repeat(12);
      const cache: LayoutCache = new LayoutCache(new TextLayoutEngine(100, 16, 24, 4, 1));
      let slices: number = 0;
      let reached: boolean = false;
      let lines: LayoutLine[] = [];
      while (!reached && slices < 200) {
        const progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 2, 0);
        expect(progress.appendedLines <= 1).assertTrue();
        lines = progress.lines;
        reached = progress.reached;
        slices++;
      }
      expect(reached).assertTrue();
      expect(slices > 1).assertTrue();
      expect(lines[lines.length - 1].endIndex).assertEqual(value.length);
      for (const line of lines) {
        expect(GraphemeUtil.isBoundary(value, line.startIndex)).assertTrue();
        expect(GraphemeUtil.isBoundary(value, line.endIndex)).assertTrue();
      }
    });
    it('canvasFarNavigationCannotRevealAnOlderDocumentAfterReload', 0, async () => {
      const driver: Driver = Driver.create();
      const value: string = '段落 A😀B\n'.repeat(80);
      FlowTextFixture.controller.setDocument(value, [], 0);
      FlowTextFixture.controller.setCaretPosition(value.length);
      expect(FlowTextFixture.savedCaret).assertEqual(value.length);
      FlowTextFixture.controller.setDocument('replacement😀', [], 2);
      FlowTextFixture.controller.setCaretPosition(2);
      await driver.delayMs(150);
      expect(FlowTextFixture.controller.getText()).assertEqual('replacement😀');
      expect(FlowTextFixture.savedCaret).assertEqual(2);
    });
    it('canvasSelectAllReplacesTheCompleteDocumentWithoutRequiringItsTailGeometry', 0, async () => {
      const driver: Driver = Driver.create();
      const value: string = '长文 A😀B\n'.repeat(80);
      FlowTextFixture.controller.setDocument(value, [], 0);
      FlowTextFixture.controller.focus();
      expect(await driver.waitForIdle(200, 5000)).assertTrue();
      await pressAndRelease(driver, KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_A);
      expect(FlowTextFixture.selectionStart).assertEqual(0);
      expect(FlowTextFixture.selectionEnd).assertEqual(value.length);
      expect(FlowTextFixture.savedCaret).assertEqual(value.length);
      FlowTextFixture.controller.insertTextAtCaret('完整替换😀');
      expect(FlowTextFixture.controller.getText()).assertEqual('完整替换😀');
    });
  });
  // This group has its own timeout; yielding keeps the real UI watchdog active.
  describe('FlowTextLongLayoutRegression', () => {
    it('nativeLayoutCrossesMultipleParagraphWindows', 0, async () => {
      const paragraph: string = '中文 A😀B '.repeat(40) + '\n';
      const value: string = paragraph.repeat(15) + '尾段😀';
      const cache: LayoutCache = new LayoutCache(new TextLayoutEngine(240, 16, 24, 4, 1));
      cache.setRuns([new FormatRun(value.length - 4, value.length, true)]);
      let lines: LayoutLine[] = [];
      while (!cache.isComplete()) {
        const progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 8, 4);
        lines = progress.lines;
        if (!progress.reached) { await new Promise<void>((resolve) => { setTimeout(resolve, 1); }); }
      }
      expect(lines[lines.length - 1].endIndex).assertEqual(value.length);
      const nextWindowStart: number = value.indexOf('\n', 4000) + 1;
      let sampledWrap: boolean = false;
      let sampledNextWindow: boolean = false;
      let checkedGlyphs: number = 0;
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
            // The detailed guard above checks every glyph; avoid thousands of duplicate Hypium assertions.
            checkedGlyphs++;
          }
        }
      }
      expect(sampledWrap).assertTrue();
      expect(sampledNextWindow).assertTrue();
      expect(checkedGlyphs > 0).assertTrue();
    });
  });
}
