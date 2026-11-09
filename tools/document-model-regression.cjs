// Node 24+. P5 语义层：段落身份与结构性编辑（ADR-002 §2.5）。
// 这里证明的是"拖动/分裂/合并时 id 与正文怎么走"，不碰数据库与 UI。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const strip = text => stripTypeScriptTypes(text
  .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+default\s+/g, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });

const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
for (const file of ['editor/flowtext/model/EditorTypes.ets', 'editor/flowtext/model/FormatCodec.ets',
  'editor/model/DocumentModel.ets']) {
  vm.runInContext(strip(read(file)), context);
}
const api = vm.runInContext('({ FormatRun, FormatCodec, createDocument, project, paragraphSpans,' +
  ' paragraphIdAt, splitParagraph, mergeParagraphs, setParagraphKind, sectionRange, moveSection, changeIndent })', context);

let pass = 0;
function check(name, action) {
  action();
  pass++;
  console.log('PASS ' + name);
}
const json = value => JSON.parse(JSON.stringify(value));
const kinds = model => json(model.paragraphs.map(p => p.kind));
const ids = model => json(model.paragraphs.map(p => p.id));
const texts = model => json(model.paragraphs.map(p => p.text));
const runTuples = projection => json(api.FormatCodec.decode(projection.runsJson)
  .map(r => [r.startOffset, r.endOffset, r.heading, r.indent, r.bold, r.italic]));

function sample() {
  // 标题 + 正文 + 列表（第 2 级）+ 二级标题 + 正文
  const text = '第一章 引言\n这是正文。\n子项内容\n第一节\n结尾';
  // 偏移：p1 [0,6) · p2 [7,12) · p3 [13,17) · p4 [18,21) · p5 [22,24)
  const runs = [
    new api.FormatRun(0, 6, false, false, 1, 0),
    new api.FormatRun(13, 17, false, false, 4, 1),
    new api.FormatRun(7, 11, true, false, 0, 0),
    new api.FormatRun(18, 21, false, false, 2, 0)
  ];
  return api.createDocument('d1', '书名', text, api.FormatCodec.encode(runs));
}

check('解析：段落按换行切开，种类/层级/行内样式各归各位', () => {
  const model = sample();
  assert.deepEqual(ids(model), ['p1', 'p2', 'p3', 'p4', 'p5']);
  assert.deepEqual(kinds(model), [1, 0, 4, 2, 0]);
  assert.equal(model.paragraphs[2].indent, 1);
  assert.deepEqual(texts(model), ['第一章 引言', '这是正文。', '子项内容', '第一节', '结尾']);
  // 行内粗体被裁到第 2 段并转成段内偏移
  assert.deepEqual(json(model.runs.map(r => [r.paraId, r.start, r.end, r.bold])),
    [['p2', 0, 4, true]]);
});

check('投影：文本与 run 能还原成编辑器认识的样子', () => {
  const model = sample();
  const projection = api.project(model);
  assert.equal(projection.text, '第一章 引言\n这是正文。\n子项内容\n第一节\n结尾');
  assert.deepEqual(runTuples(projection), [
    [0, 6, 1, 0, false, false],
    [7, 11, 0, 0, true, false],
    [13, 17, 4, 1, false, false],
    [18, 21, 2, 0, false, false]
  ]);
  // 段落跨度首尾相接（ing 一个换行）
  const spans = json(projection.spans);
  for (let i = 1; i < spans.length; i++) {
    assert.equal(spans[i].start, spans[i - 1].end + 1);
  }
});

check('分裂段落：左段保留 id，右段新建，跨界样式一分为二', () => {
  const model = sample();
  const rightId = api.splitParagraph(model, 1, 2); // 「这是|正文。」
  assert.equal(rightId, 'p6');
  assert.deepEqual(ids(model), ['p1', 'p2', 'p6', 'p3', 'p4', 'p5']);
  assert.deepEqual(texts(model), ['第一章 引言', '这是', '正文。', '子项内容', '第一节', '结尾']);
  // 粗体 [0,3) 跨过切点 2 → 左 [0,2)、右 [0,1)
  assert.deepEqual(json(model.runs.map(r => [r.paraId, r.start, r.end])),
    [['p2', 0, 2], ['p6', 0, 2]]);
  const projection = api.project(model);
  assert.equal(projection.text, '第一章 引言\n这是\n正文。\n子项内容\n第一节\n结尾');
});

check('合并段落：保留左段 id，右段样式平移到左段', () => {
  const model = sample();
  api.splitParagraph(model, 1, 2);
  assert.equal(api.mergeParagraphs(model, 1), true);
  assert.deepEqual(ids(model), ['p1', 'p2', 'p3', 'p4', 'p5']);
  assert.equal(model.paragraphs[1].text, '这是正文。');
  assert.deepEqual(json(model.runs.map(r => [r.paraId, r.start, r.end])), [['p2', 0, 4]]);
});

check('段首分裂只插入空段，不改原段 id', () => {
  const model = sample();
  const newId = api.splitParagraph(model, 0, 0);
  assert.notEqual(newId, 'p1');
  assert.deepEqual(ids(model).slice(0, 2), [newId, 'p1']);
  assert.equal(model.paragraphs[0].text, '');
});

check('改段落种类：切回正文时缩进归零', () => {
  const model = sample();
  assert.equal(api.setParagraphKind(model, 2, 0), true);
  assert.equal(model.paragraphs[2].kind, 0);
  assert.equal(model.paragraphs[2].indent, 0);
  assert.equal(api.setParagraphKind(model, 0, 3), true);
  assert.equal(runTuples(api.project(model))[0][2], 3);
});

check('列表缩进只在列表段生效，且钳制在 0–2', () => {
  const model = sample();
  assert.equal(api.changeIndent(model, 1, 1), false, 'body paragraph is not a list');
  assert.equal(api.changeIndent(model, 2, 1), true);
  assert.equal(model.paragraphs[2].indent, 2);
  assert.equal(api.changeIndent(model, 2, 1), false, 'already at MAX_LIST_LEVEL');
});

check('一节的范围：到下一个同级或更高级标题为止', () => {
  const model = sample();
  assert.deepEqual(json(api.sectionRange(model, 0)), [0, 5], 'H1 covers everything until the end');
  assert.deepEqual(json(api.sectionRange(model, 3)), [3, 5], 'H2 covers until the last body');
  assert.deepEqual(json(api.sectionRange(model, 1)), [1, 2], 'body paragraph is its own section');
});

check('移动整节：顺序变化，id 一个都不变', () => {
  const model = sample();
  const before = ids(model);
  // 把「第一节」（H2 + 尾段）整节移到第一段正文之前
  assert.equal(api.moveSection(model, 3, 1), true);
  assert.deepEqual(ids(model), ['p1', 'p4', 'p5', 'p2', 'p3'], 'stable identity: no id rewrite');
  assert.deepEqual(texts(model), ['第一章 引言', '第一节', '结尾', '这是正文。', '子项内容']);
  assert.equal(model.version, 2, 'structural change bumps version');
});

check('偏移定位：段尾归本段，越界归最后一段', () => {
  const model = sample();
  assert.equal(api.paragraphIdAt(model, 0), 'p1');
  assert.equal(api.paragraphIdAt(model, 6), 'p1', 'end of paragraph belongs to itself');
  assert.equal(api.paragraphIdAt(model, 7), 'p2');
  assert.equal(api.paragraphIdAt(model, 999), 'p5');
});

console.log('Document model regression: ' + pass + ' checks passed');
