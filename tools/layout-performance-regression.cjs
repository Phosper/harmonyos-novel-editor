// Node 24+. Runs the real layout sources with counted native/engine doubles.
// These assertions bound work and state sharing; they do not claim device latency.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets/editor/flowtext');
let clock = 0;

class ParagraphBuilder {
  constructor() { this.parts = []; }
  addText(value) { this.parts.push(value); }
  pushStyle() {}
  popStyle() {}
  buildLineTypeset() {
    const scalars = Array.from(this.parts.join(''));
    return {
      getLineBreak(start) { assert.ok(start >= 0); return Math.min(5, scalars.length - start); },
      createLine(start, count) {
        const glyphs = scalars.slice(start, start + count).map(value => value.codePointAt(0));
        return {
          getTextRange() { return { start: 0, end: count }; },
          getTypographicBounds() { return { ascent: 14, descent: 4, leading: 0, width: count * 10 }; },
          getGlyphRuns() { return [{
            getStringRange() { return { start: 0, end: count }; },
            getStringIndices() { return glyphs.map((_, i) => i); },
            getGlyphs() { return glyphs; }, getFont() { return {}; },
            getAdvances() { return glyphs.map(() => ({ x: 10, y: 0 })); },
            getPositions() { return glyphs.map((_, i) => ({ x: i * 10, y: 0 })); }
          }]; },
          getOffsetForStringIndex(index) { return index * 10; }
        };
      }
    };
  }
}
const context = vm.createContext({ Date: { now: () => clock },
  text: { FontCollection: { getGlobalInstance() { return {}; } }, ParagraphBuilder,
    FontWeight: { W700: 700 }, FontStyle: { ITALIC: 1 } }
});
for (const file of ['model/EditorTypes', 'model/TextIndexMap', 'model/UnicodeGraphemeData',
  'model/GraphemeUtil', 'render/TextLayoutEngine', 'render/LayoutCache']) {
  const source = fs.readFileSync(path.join(root, file + '.ets'), 'utf8');
  const executable = stripTypeScriptTypes(source
    .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+/g, ''), { mode: 'transform' });
  vm.runInContext(executable, context, { filename: file + '.ets' });
}
const api = vm.runInContext('({ LayoutCache, TextLayoutEngine, FormatRun, GraphemeUtil })', context);
let nextEngineId = 0;
class CountingEngine {
  constructor(metrics = { lines: 0, windows: 0, chars: 0, tick: 0 }) {
    this.metrics = metrics; this.id = ++nextEngineId; this.runs = []; this.base = -1;
  }
  cloneConfiguration() { return new CountingEngine(this.metrics); }
  setRuns(runs) { this.runs = runs; }
  availableWidthPx() { return 100; }
  buildTypesetWindow(content, base, end) {
    this.base = base;
    this.metrics.windows++; this.metrics.chars += end - base;
    return { engine: this.id, base, value: content.substring(base, end) };
  }
  lineBreak(typeset, start) {
    assert.equal(typeset.engine, this.id, 'typeset belongs to its own engine');
    assert.equal(typeset.base, this.base, 'engine origin still matches its typeset');
    return Math.min(5, typeset.value.length - (start - this.base));
  }
  createLayoutLine(typeset, start, count, y) {
    assert.equal(typeset.engine, this.id);
    return this.makeLine(start, count, y, typeset.value.substring(start - this.base, start - this.base + count));
  }
  emptyLine(start, y) { return this.makeLine(start, 0, y, ''); }
  makeLine(start, count, y, value) {
    this.metrics.lines++; clock += this.metrics.tick;
    return { startIndex: start, endIndex: start + count, consumedEnd: start + count,
      yOffset: y, step: 20, height: 20, value,
      styles: this.runs.filter(run => run.startOffset < start + count && run.endOffset > start)
        .map(run => [run.startOffset, run.endOffset, run.bold, run.heading]) };
  }
}
const shape = lines => Array.from(lines, line => [line.startIndex, line.endIndex, line.consumedEnd, line.yOffset]);
let checks = 0;
function check(name, run) { clock = 0; run(); checks++; console.log('PASS ' + name); }

check('preview fork and repeated updates only lay out the changed tail', () => {
  const prefix = 'abcd\n'.repeat(5000), value = prefix + 'tail';
  const engine = new CountingEngine(), main = new api.LayoutCache(engine);
  const mainLines = main.ensureOffset(value, 1, 1, value.length);
  const before = engine.metrics.lines, windows = engine.metrics.windows, chars = engine.metrics.chars;
  const preview = main.forkForEdit(prefix + '候选', 2, 2, [], prefix.length);
  const first = preview.ensureOffset(prefix + '候选', 2, 2, prefix.length + 2);
  assert.equal(first[0], mainLines[0], 'unchanged native line identity retained');
  assert.notEqual(first, mainLines, 'arrays are independently owned');
  for (let i = 0; i < 20; i++) {
    const candidate = prefix + (i % 2 ? '预编辑' : '候选词');
    preview.applyEdit(candidate, i + 3, i + 3, [], prefix.length);
    const lines = preview.ensureOffset(candidate, i + 3, i + 3, candidate.length);
    assert.equal(lines[4999], mainLines[4999]);
  }
  assert.equal(engine.metrics.lines - before, 21, 'one short tail line per preview update');
  assert.equal(engine.metrics.windows - windows, 21);
  assert.ok(engine.metrics.chars - chars <= 21 * 3, 'no unchanged prefix enters native typesetting');
  assert.equal(main.ensureOffset(value, 1, 1, value.length), mainLines);
  assert.equal(mainLines.at(-1).value, 'tail', 'cancelled preview leaves committed lines unchanged');
});

check('fork invalidates the entire changed paragraph and atomically applies its format', () => {
  const value = 'safe\nabcdefghij\nlast';
  const main = new api.LayoutCache(new CountingEngine());
  const original = main.ensureOffset(value, 1, 1, value.length);
  const runs = [new api.FormatRun(5, 16, true)];
  const preview = main.forkForEdit('safe\nabcXdefghij\nlast', 2, 2, runs, 8);
  const lines = preview.ensureOffset('safe\nabcXdefghij\nlast', 2, 2, 21);
  assert.equal(lines[0], original[0]);
  assert.notEqual(lines[1], original[1], 'no soft-wrapped line within changed paragraph retained');
  assert.equal(lines[1].styles[0][2], true);
  assert.equal(original[1].styles.length, 0);
  assert.equal(original.at(-1).startIndex, 16);
});

check('real engine clone isolates maps, typeset origins, runs and word caches', () => {
  const engine = new api.TextLayoutEngine(51, 17, 25, 3, 2);
  const run = new api.FormatRun(0, 8, true);
  engine.setRuns([run]);
  const mainTypeset = engine.buildTypesetWindow('A😀中XYZ', 0, 7);
  const map = engine.indexMap;
  engine.wordParagraph = { old: true }; engine.wordParagraphText = 'old';
  const clone = engine.cloneConfiguration();
  assert.equal(clone.contentMaxWidthPx(), 102); assert.equal(clone.lineStepVp(), 28);
  assert.notEqual(clone.indexMap, map); assert.notEqual(clone.runsValue, engine.runsValue);
  assert.notEqual(clone.runsValue[0], run); assert.equal(clone.wordParagraph, null);
  clone.runsValue[0].bold = false;
  clone.buildTypesetWindow('prefix\n𠮷𠮷tail', 7, 15);
  assert.equal(engine.typesetBase, 0); assert.equal(engine.indexMap, map); assert.equal(run.bold, true);
  const line = engine.createLayoutLine(mainTypeset, 1, 3, 0);
  assert.equal(line.runs[0].textStart, 1); assert.equal(line.runs[0].textEnd, 4);
  assert.deepEqual(Array.from(line.runs[0].glyphOffsets), [0, 2]);
});

check('real committed cache resumes an active window after a far preview was cancelled', () => {
  const value = 'A😀'.repeat(1000) + '\n' + '中B'.repeat(1000) + '\n' + 'tail';
  const engine = new api.TextLayoutEngine(50, 16, 24, 4, 1), main = new api.LayoutCache(engine);
  const early = main.ensureLayout(value, 1, 1, 60), map = engine.indexMap, base = engine.typesetBase;
  const preview = main.forkForEdit(value + '候选', 2, 2, [], value.length);
  preview.ensureOffset(value + '候选', 2, 2, value.length + 2);
  assert.equal(engine.indexMap, map); assert.equal(engine.typesetBase, base);
  const resumed = main.ensureOffset(value, 1, 1, value.length);
  const clean = new api.LayoutCache(new api.TextLayoutEngine(50, 16, 24, 4, 1));
  const expected = clean.ensureOffset(value, 1, 1, value.length);
  assert.deepEqual(shape(resumed), shape(expected)); assert.equal(resumed[0], early[0]);
  for (let i = 0; i < resumed.length; i++) {
    assert.deepEqual(Array.from(resumed[i].runs.flatMap(run => run.glyphs)),
      Array.from(expected[i].runs.flatMap(run => run.glyphs)));
  }
});

check('incremental offset layout enforces line budget and matches synchronous output', () => {
  const value = ('abcd😀efghij\n').repeat(200), engine = new CountingEngine();
  const cache = new api.LayoutCache(engine);
  let progress, calls = 0;
  do {
    const before = engine.metrics.lines;
    progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 7, 6);
    assert.ok(progress.appendedLines > 0 && progress.appendedLines <= 7);
    assert.equal(engine.metrics.lines - before, progress.appendedLines);
    calls++; assert.ok(calls < 1000);
  } while (!progress.reached);
  assert.ok(calls > 1); assert.equal(progress.complete, true);
  const expected = new api.LayoutCache(new CountingEngine()).ensureOffset(value, 1, 1, value.length);
  assert.deepEqual(shape(progress.lines), shape(expected));
  assert.equal(cache.ensureOffsetIncremental(value, 1, 1, value.length, 7, 6).appendedLines, 0);
});

check('incremental slices yield at the time budget while guaranteeing one-line progress', () => {
  const engine = new CountingEngine(); engine.metrics.tick = 2;
  const cache = new api.LayoutCache(engine), value = 'x'.repeat(500);
  let progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 64, 5);
  assert.equal(progress.appendedLines, 3); assert.equal(progress.reached, false);
  progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 64, 0);
  assert.equal(progress.appendedLines, 1);
  progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 0, 100);
  assert.equal(progress.appendedLines, 1, 'invalid/zero line budgets cannot stall');
});

check('incremental viewport target stops without finishing the whole document', () => {
  const engine = new CountingEngine(), cache = new api.LayoutCache(engine), value = 'abcdefghij\n'.repeat(100);
  let progress = cache.ensureLayoutIncremental(value, 1, 1, 50, 2, 6);
  assert.equal(progress.appendedLines, 2); assert.equal(progress.reached, false);
  progress = cache.ensureLayoutIncremental(value, 1, 1, 50, 2, 6);
  assert.equal(progress.appendedLines, 1); assert.equal(progress.reached, true);
  assert.equal(progress.complete, false); assert.equal(cache.coversY(50), true);
  assert.equal(cache.coversOffset(value.length), false);
});

check('soft-wrap boundary only becomes covered once its downstream line exists', () => {
  const cache = new api.LayoutCache(new CountingEngine());
  cache.ensureLayoutIncremental('abcdefghijk', 1, 1, 20, 1, 6);
  assert.equal(cache.coversOffset(4), true); assert.equal(cache.coversOffset(5), false);
  const next = cache.ensureOffsetIncremental('abcdefghijk', 1, 1, 5, 1, 6);
  assert.equal(next.reached, true); assert.equal(next.lines[1].startIndex, 5);
});

check('empty and trailing-newline caret lines survive slicing and forking', () => {
  for (const value of ['', 'A\n', '\n\n', 'abcd\n\n']) {
    const cache = new api.LayoutCache(new CountingEngine()); let progress;
    do { progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 1, 0); } while (!progress.reached);
    assert.equal(progress.lines.at(-1).endIndex, value.length);
    if (!value || value.endsWith('\n')) assert.equal(progress.lines.at(-1).startIndex, value.length);
    const preview = cache.forkForEdit(value, 2, 2, [], value.length);
    assert.deepEqual(shape(preview.ensureOffset(value, 2, 2, value.length)), shape(progress.lines));
  }
});

check('budgeted line breaks keep emoji and combining sequences intact', () => {
  const value = ('A👨‍👩‍👧B e\u0301 🇨🇳 𠮷\n').repeat(40);
  const cache = new api.LayoutCache(new CountingEngine()); let progress;
  do { progress = cache.ensureOffsetIncremental(value, 1, 1, value.length, 3, 6); } while (!progress.reached);
  for (const line of progress.lines) {
    assert.ok(api.GraphemeUtil.isBoundary(value, line.startIndex));
    assert.ok(api.GraphemeUtil.isBoundary(value, line.endIndex));
  }
});

check('content or format revision changes discard stale partial navigation', () => {
  const cache = new api.LayoutCache(new CountingEngine());
  const old = cache.ensureOffsetIncremental('old\n'.repeat(50), 1, 1, 200, 2, 6);
  const changed = cache.ensureOffsetIncremental('new', 2, 2, 3, 2, 6);
  assert.equal(changed.reached, true); assert.notEqual(changed.lines[0], old.lines[0]);
  assert.equal(changed.lines[0].value, 'new');
});

console.log('Layout performance regression: ' + checks + ' checks passed.');
