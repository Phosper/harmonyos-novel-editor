// Node 24+. 直接执行思路板初稿生成器（CanvasTypes + EditorTypes + FormatCodec + CanvasDraftWriter），
// 不需要 SDK / 设备 / ArkUI。验证的是"落稿形状"：标题级别只走 format_runs、素材顺序、
// 【待展开】占位、空大纲、正文永不出现 '#'。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
// 只剥 import/export：这些文件没有任何 @kit.* 依赖，可在 Node 里按依赖顺序拼成一个模块执行。
function compile(files) {
  return stripTypeScriptTypes(files
    .map((file) => read(file)
      .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
      .replace(/\bexport\s+default\s+/g, '')
      .replace(/\bexport\s+/g, ''))
    .join('\n'), { mode: 'transform' });
}
const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
vm.runInContext(compile([
  'model/CanvasTypes.ets',
  'editor/flowtext/model/EditorTypes.ets',
  'editor/flowtext/model/FormatCodec.ets',
  'editor/CanvasDraftWriter.ets',
  'editor/CanvasCapture.ets'
]), context);
const api = vm.runInContext('({ CanvasDraftWriter, FormatCodec, FormatRun, canvasFingerprint, canvasParagraphIndex, canvasCapturePayload })', context);

let pass = 0;
function check(name, action) {
  try { action(); pass++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name + ' :: ' + error.message); process.exitCode = 1; }
}

function card(id, title) {
  return { id, bookId: 'b1', kind: 'writing', title, aliases: '', tags: '', summary: '', docId: '',
    createdAt: 0, updatedAt: 0 };
}
function row(cardId, depth, index) {
  return { cardId, placementId: 'p_' + cardId, depth, index, numbering: '' };
}
function ev(id, cardId, kind, quoteText, userText, sourceLabel) {
  return { id, cardId, kind, docId: 'd1', paraIndex: 0, startOff: 0, endOff: 0, fingerprint: '',
    quoteText, userText, sourceLabel, createdAt: 0 };
}
// 卡片表：W 是写作卡（不进 rows），A/B/C 是 章/节/目
const CARDS = new Map([['W', card('W', '国际关系理论课程期末论文')], ['A', card('A', '导论')],
  ['B', card('B', '理论框架')], ['C', card('C', '案例：跨期合作')]]);
const cardOf = (cardId) => CARDS.get(cardId);
const ROWS = [row('A', 1, 0), row('B', 2, 0), row('C', 3, 0)];
function build(rows, evidence, rootEvidence) {
  return api.CanvasDraftWriter.build({ rows, evidence, cardOf, rootEvidence });
}

check('标题级别只写进 runs：三级 heading 1/2/3 且区间含段末换行', () => {
  const out = build(ROWS, []);
  assert.equal(out.runs.length, 3);
  assert.deepEqual(Array.from(out.runs.map((r) => r.heading)), [1, 2, 3]);
  assert.deepEqual(Array.from(out.runs.map((r) => r.startOffset)), [0, 9, 20]);
  for (const r of out.runs) {
    // 行区间 = 标题文字 + '\n'（与 TextDocument.paragraphAttrsBounds 同语义）
    assert.ok(out.content.substring(r.startOffset, r.endOffset).endsWith('\n'), 'run 必须含段末换行');
    assert.equal(r.bold, false);
    assert.equal(r.italic, false);
  }
  assert.equal(out.content.substring(0, 3), '导论\n');
  assert.equal(out.content.substring(9, 14), '理论框架\n');
});

check('素材顺序：按传入数组顺序落到各自节点下', () => {
  const out = build(ROWS, [
    ev('e1', 'A', 'quote', '跨期合作的困境来自信息不对称', '', '《国际关系史》3 章 2 段'),
    ev('e2', 'B', 'judgement', '', '这条判断只在双边的静态博弈里成立'),
    ev('e3', 'A', 'note', '', '回头查 1994 年那篇'),
    ev('e4', 'C', 'note', '', '案例段先放一放')
  ]);
  const body = out.content;
  const iQuote = body.indexOf('跨期合作的困境来自信息不对称');
  const iNoteA = body.indexOf('回头查 1994 年那篇');
  const iJudge = body.indexOf('这条判断只在双边的静态博弈里成立');
  assert.ok(iQuote > 0 && iNoteA > iQuote, 'A 的两条素材顺序应为 quote → note');
  assert.ok(iJudge > iNoteA, 'B 的素材应排在 A 的素材之后（深度优先）');
  assert.ok(body.indexOf('案例段先放一放') > iJudge);
});

check('引文格式：原文（引自《…》N 章 M 段）', () => {
  const out = build(ROWS, [ev('e1', 'A', 'quote', '跨期合作的困境', '', '《国际关系史》3 章 2 段')]);
  assert.ok(out.content.includes('跨期合作的困境（引自《国际关系史》3 章 2 段）\n'), out.content);
});

check('判断 / 笔记原样输出，不追加出处', () => {
  const out = build(ROWS, [
    ev('e2', 'A', 'judgement', '', '论断：制度可以减少欺骗空间', '《国际关系史》3 章 2 段'),
    ev('e3', 'A', 'note', '', '笔记：回头补 1994 年的材料', '')
  ]);
  assert.ok(out.content.includes('论断：制度可以减少欺骗空间\n'));
  assert.ok(!out.content.includes('论断：制度可以减少欺骗空间（引自'));
  assert.ok(out.content.includes('笔记：回头补 1994 年的材料\n'));
});

check('每个节点末尾都有【待展开】占位', () => {
  const out = build(ROWS, [ev('e1', 'A', 'quote', '一句话', '', '')]);
  const marks = out.content.split('【待展开】').length - 1;
  assert.equal(marks, ROWS.length);
  assert.ok(out.content.endsWith('【待展开】\n'));
  // 占位紧跟在该节点的素材之后，不会被下一个标题吞掉
  assert.ok(out.content.indexOf('一句话\n【待展开】\n') > 0);
});

check('空大纲 → 空稿', () => {
  const out = build([], []);
  assert.equal(out.content, '');
  assert.equal(out.runs.length, 0);
  assert.equal(out.runsJson, '');
});

check('正文不含 #：标题级别不靠 Markdown 标记', () => {
  const out = build(ROWS, [ev('e1', 'A', 'quote', '一句话', '', '《国际关系史》3 章 2 段')]);
  assert.equal(out.content.includes('#'), false);
});

check('runsJson 可被 FormatCodec 解回同一批标题', () => {
  const out = build(ROWS, []);
  const back = api.FormatCodec.decode(out.runsJson);
  assert.equal(back.length, 3);
  assert.deepEqual(Array.from(back.map((r) => r.heading)), [1, 2, 3]);
  assert.deepEqual(Array.from(back.map((r) => r.startOffset)), Array.from(out.runs.map((r) => r.startOffset)));
  assert.deepEqual(Array.from(back.map((r) => r.endOffset)), Array.from(out.runs.map((r) => r.endOffset)));
});

check('查不到的卡片不阻断生成：标题按空串写，仍是标题段', () => {
  const out = build([row('X', 2, 0)], [ev('e9', 'X', 'note', '', '孤儿素材', '')]);
  assert.equal(out.runs.length, 1);
  assert.equal(out.runs[0].heading, 2);
  assert.equal(out.content, '\n孤儿素材\n【待展开】\n');
  assert.equal(out.content.substring(out.runs[0].startOffset, out.runs[0].endOffset), '\n');
});

check('深度超限夹到 3，depth<=0 不写标题', () => {
  const deep = build([row('A', 5, 0)], []);
  assert.equal(deep.runs[0].heading, 3);
  const root = build([row('W', 0, 0)], []);
  assert.equal(root.runs.length, 0);
  assert.equal(root.content, '国际关系理论课程期末论文\n【待展开】\n');
});

check('标题内换行被压平，不破坏"一行一节点"', () => {
  const CARDS2 = new Map([['A', card('A', '上篇\n下篇')]]);
  const out = api.CanvasDraftWriter.build({ rows: [row('A', 1, 0)], evidence: [],
    cardOf: (cardId) => CARDS2.get(cardId) });
  assert.equal(out.content, '上篇 下篇\n【待展开】\n');
  assert.equal(out.runs.length, 1);
});

check('写作卡自身素材放在所有章节之前，且不带标题', () => {
  const out = build(ROWS, [], [ev('r1', 'W', 'note', '', '总纲：先立问题再拆理论', '')]);
  assert.ok(out.content.startsWith('总纲：先立问题再拆理论\n'), out.content);
  assert.ok(out.content.indexOf('总纲') < out.content.indexOf('导论'));
  assert.equal(out.runs.length, 3);
});

check('捕获：段号/出处/指纹稳定，空选区返回 undefined', () => {
  const text = '第一段\n第二段内容\n第三段';
  assert.equal(api.canvasParagraphIndex(text, 0), 0);
  assert.equal(api.canvasParagraphIndex(text, 4), 1);
  assert.equal(api.canvasParagraphIndex(text, 10), 2);
  const p = api.canvasCapturePayload('d1', '国际关系理论', text, 4, 9);
  assert.equal(p.quoteText, '第二段内容');
  assert.equal(p.startOff, 4);
  assert.equal(p.endOff, 9);
  assert.equal(p.paraIndex, 1);
  assert.equal(p.sourceLabel, '国际关系理论 · 第 2 段');
  assert.equal(p.fingerprint, api.canvasFingerprint('第二段内容'));
  assert.equal(api.canvasCapturePayload('d1', '', text, 2, 2), undefined);
  assert.equal(api.canvasCapturePayload('d1', '', text, 2, 5).sourceLabel, '第 1 段');
});

check('捕获：指纹对内容敏感、对位置不敏感', () => {
  assert.equal(api.canvasFingerprint('均势'), api.canvasFingerprint('均势'));
  assert.notEqual(api.canvasFingerprint('均势'), api.canvasFingerprint('均势。'));
});

console.log('Draft regression: ' + pass + ' checks passed');
