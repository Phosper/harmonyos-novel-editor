// Node 24+. 只读导图的纯逻辑：从正文抽标题 → 建树 → 布局。
//
// 这三步都不依赖 UI 与设备，所以必须在本地被证明：
//   - 抽标题：格式边车被行内加粗切碎时仍能认出标题（与导出/编辑器同一套取值规则）
//   - 建树：层级栈决定父子（H1 > H2 > H3，回到更小层级就换父）
//   - 布局：x 由深度决定，叶子按文档顺序排 y，父节点取首末子节点中点
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const repo = path.resolve(__dirname, '..');

const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const readContract = file => fs.readFileSync(path.join(repo, 'feature_contracts/src/main/ets/contracts', file), 'utf8');
const strip = source => stripTypeScriptTypes(source
  .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+default\s+/g, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });

const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
for (const source of [
  read('editor/flowtext/model/EditorTypes.ets'),
  read('editor/flowtext/model/FormatCodec.ets'),
  readContract('OutlineLayout.ets'),
  read('editor/OutlineExtract.ets')
]) {
  vm.runInContext(strip(source), context);
}
const api = vm.runInContext('({ FormatRun, FormatCodec, buildOutline, layoutOutline, outlineParents,' +
  ' OUTLINE_NODE_W, OUTLINE_NODE_H, OUTLINE_COL_GAP, OUTLINE_PAD, extractHeadings, buildOutlineSnapshot })', context);

let pass = 0;
function check(name, action) {
  action();
  pass++;
  console.log('PASS ' + name);
}
const heading = (title, level, start, end) => ({ title, level, startOffset: start, endOffset: end });

check('层级栈决定父子：H1 > H2 > H3，回到 H1 换父', () => {
  const nodes = api.buildOutline('论文', [
    heading('一', 1, 0, 1), heading('一之一', 2, 2, 3), heading('一之一之一', 3, 4, 5), heading('二', 1, 6, 7)
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(nodes.map(n => n.depth))), [0, 1, 2, 3, 1]);
  assert.deepEqual(JSON.parse(JSON.stringify(api.outlineParents(nodes))), [-1, 0, 1, 2, 0]);
  assert.equal(nodes.length, 5, 'root + 4 headings');
});

check('布局：x 跟深度走，叶子按顺序排，父节点取中点', () => {
  const nodes = api.buildOutline('论文', [
    heading('一', 1, 0, 1), heading('一之一', 2, 2, 3), heading('一之二', 2, 4, 5)
  ]);
  const layout = api.layoutOutline(nodes);
  const at = id => layout.nodes.find(n => n.id === id);
  assert.equal(layout.nodes.length, 4);
  const rootNode = layout.nodes[0];
  const h1 = layout.nodes[1];
  const c1 = layout.nodes[2];
  const c2 = layout.nodes[3];
  assert.equal(rootNode.x, api.OUTLINE_PAD);
  assert.equal(h1.x, api.OUTLINE_PAD + api.OUTLINE_COL_GAP);
  assert.equal(c1.x, api.OUTLINE_PAD + 2 * api.OUTLINE_COL_GAP);
  assert.ok(c1.y < c2.y, 'leaves keep document order');
  assert.equal(h1.y, (c1.y + c2.y) / 2, 'parent sits between its children');
  assert.equal(rootNode.y, h1.y, 'single child does not offset the parent');
  assert.ok(layout.width > c1.x + api.OUTLINE_NODE_W, 'canvas covers the deepest column');
  assert.ok(layout.height >= c2.y + api.OUTLINE_NODE_H, 'canvas covers the last row');
});

check('抽标题：只认 1–3 级，正文与四级标题不进大纲', () => {
  const text = '标题一\n正文\n标题二\n四级标题';
  const runs = [new api.FormatRun(0, 3, false, false, 1), new api.FormatRun(13, 16, false, false, 4)];
  const headings = api.extractHeadings(text, api.FormatCodec.encode(runs));
  assert.deepEqual(JSON.parse(JSON.stringify(headings.map(h => [h.title, h.level, h.startOffset]))),
    [['标题一', 1, 0]]);
});

check('抽标题：行内加粗把段落标注切碎时仍能认出标题', () => {
  const text = '重点标题\n正文';
  // 同一段被切成三段 run，只有最后一段带 heading=2
  const runs = [
    new api.FormatRun(0, 2, true, false, 0),
    new api.FormatRun(2, 4, false, false, 0),
    new api.FormatRun(0, 4, false, false, 2)
  ];
  const headings = api.extractHeadings(text, api.FormatCodec.encode(runs));
  assert.deepEqual(JSON.parse(JSON.stringify(headings.map(h => [h.title, h.level]))), [['重点标题', 2]]);
});

check('没有标题或没有格式边车时返回空大纲（只剩根）', () => {
  assert.equal(api.extractHeadings('只有正文\n还是正文', '').length, 0);
  const snapshot = api.buildOutlineSnapshot('d1', '', '只有正文', '', 3);
  assert.equal(snapshot.nodes.length, 1);
  assert.equal(snapshot.nodes[0].title, '未命名文稿');
  assert.equal(snapshot.docId, 'd1');
  assert.equal(snapshot.version, 3);
});

check('快照带根节点，标题按文档顺序挂上去', () => {
  const text = '第一章\n内容\n第二章';
  const runs = [new api.FormatRun(0, 3, false, false, 1), new api.FormatRun(7, 10, false, false, 1)];
  const snapshot = api.buildOutlineSnapshot('d2', '书名', text, api.FormatCodec.encode(runs), 9);
  assert.equal(snapshot.docTitle, '书名');
  assert.deepEqual(JSON.parse(JSON.stringify(snapshot.nodes.map(n => [n.title, n.depth]))),
    [['书名', 0], ['第一章', 1], ['第二章', 1]]);
});

console.log('Outline regression: ' + pass + ' checks passed');
