// Node 24+. 直接执行思路板的纯规则（model/CanvasTypes.ets），不需要 SDK / 设备。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
function compile(source) {
  return stripTypeScriptTypes(source
    .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+default\s+/g, '')
    .replace(/\bexport\s+/g, ''), { mode: 'transform' });
}
const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
vm.runInContext(compile(read('model/CanvasTypes.ets')), context);
const api = vm.runInContext('({ canvasNumbering, canvasChildren, canvasDepthOf, canvasSubtreeDepth,' +
  ' canvasIsAncestor, canvasCanNest, canvasNextOrder, canvasFlatten, canvasAttach, canvasAttachAt, canvasRemovePlacement,' +
  ' canvasReorder, canvasFindPlacement, CANVAS_MAX_DEPTH })', context);

let pass = 0;
function check(name, action) {
  try { action(); pass++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name + ' :: ' + error.message); process.exitCode = 1; }
}
function place(cardId, parentId, order) {
  return { id: 'p_' + cardId, canvasId: 'b1', cardId, parentId, order, x: 0, y: 0, z: 0, collapsed: false, style: '' };
}
// 结构：写作卡 W
//   一、A (order 0)
//   （一）B (order 0)
//   1. C (order 0)
//   二、D (order 1)
function tree() {
  return [place('W', '', 0), place('A', 'W', 0), place('B', 'A', 0), place('C', 'B', 0), place('D', 'W', 1)];
}

check('编号：三层与第十项', () => {
  assert.equal(api.canvasNumbering(1, 0), '一、');
  assert.equal(api.canvasNumbering(1, 1), '二、');
  assert.equal(api.canvasNumbering(2, 0), '（一）');
  assert.equal(api.canvasNumbering(3, 0), '1.');
  assert.equal(api.canvasNumbering(3, 9), '10.');
  assert.equal(api.canvasNumbering(1, 9), '十、');
});

check('深度：顶层 0，逐级 +1', () => {
  const list = tree();
  assert.equal(api.canvasDepthOf(list, 'W'), 0);
  assert.equal(api.canvasDepthOf(list, 'A'), 1);
  assert.equal(api.canvasDepthOf(list, 'B'), 2);
  assert.equal(api.canvasDepthOf(list, 'C'), 3);
});

check('子项按 order 排序', () => {
  const kids = api.canvasChildren(tree(), 'W');
  assert.equal(kids.map((k) => k.cardId).join(','), 'A,D');
});

check('子树深度', () => {
  const list = tree();
  assert.equal(api.canvasSubtreeDepth(list, 'C'), 0);
  assert.equal(api.canvasSubtreeDepth(list, 'B'), 1);
  assert.equal(api.canvasSubtreeDepth(list, 'A'), 2);
  assert.equal(api.canvasSubtreeDepth(list, 'W'), 3);
});

check('祖先判定', () => {
  const list = tree();
  assert.equal(api.canvasIsAncestor(list, 'W', 'C'), true);
  assert.equal(api.canvasIsAncestor(list, 'B', 'W'), false);
  assert.equal(api.canvasIsAncestor(list, 'C', 'C'), false);
});

check('嵌套：正常 / 自己 / 子孙 / 超深 / 子树超深', () => {
  const list = tree();
  assert.equal(api.canvasCanNest(list, 'D', 'A'), true);          // D 挂到 A 下（D 无子树）
  assert.equal(api.canvasCanNest(list, 'A', 'A'), false);        // 自己
  assert.equal(api.canvasCanNest(list, 'A', 'C'), false);        // 放进自己的子孙
  assert.equal(api.canvasCanNest(list, 'D', 'C'), false);        // C 已在第 3 层
  assert.equal(api.canvasCanNest(list, 'A', 'D'), false);        // A 子树深 2，D 深度 1 → 1+1+2 > 3
});

check('同级 order：追加到最后', () => {
  const list = tree();
  assert.equal(api.canvasNextOrder(list, 'W'), 2);
  api.canvasAttach(list, 'D', 'A');
  const d = api.canvasFindPlacement(list, 'D');
  assert.equal(d.parentId, 'A');
  assert.equal(d.order, 1); // A 下已有 B（order 0）
});

check('展开：深度优先 + 编号', () => {
  const rows = api.canvasFlatten(tree(), 'W', 1);
  assert.equal(rows.map((r) => r.cardId).join(','), 'A,B,C,D');
  assert.equal(rows.map((r) => r.depth).join(','), '1,2,3,1');
  assert.equal(rows.map((r) => r.numbering).join('|'), '一、|（一）|1.|二、');
});

check('移除：子项上提并接在父级末尾', () => {
  const list = tree();
  api.canvasRemovePlacement(list, 'B');
  assert.equal(api.canvasFindPlacement(list, 'B'), undefined);
  const c = api.canvasFindPlacement(list, 'C');
  assert.equal(c.parentId, 'A');
  assert.equal(c.order, 1); // B 仍在时会被算进 A 的兄弟，故 C 接 1；间隙不影响排序
});

check('重排：上移下移与边界', () => {
  const list = tree();
  assert.equal(api.canvasReorder(list, 'D', -1), true);
  assert.equal(api.canvasChildren(list, 'W').map((k) => k.cardId).join(','), 'D,A');
  assert.equal(api.canvasReorder(list, 'D', -1), false);
  assert.equal(api.canvasReorder(list, 'A', -1), true);
  assert.equal(api.canvasChildren(list, 'W').map((k) => k.cardId).join(','), 'A,D');
});

check('概念卡放进写作卡：出现在子卡行且 depth=1', () => {
  const list = tree();
  api.canvasAttach(list, 'D', 'W');
  const rows = api.canvasFlatten(list, 'W', 1);
  const hit = rows.find((r) => r.cardId === 'D');
  assert.ok(hit !== undefined, 'D 应出现在 W 的展开行里');
  assert.equal(hit.depth, 1);
  assert.equal(hit.numbering, '二、'); // W 下已有 A（一、），D 追加为第二
});

check('按位置挂载：中间插入/同父重排与预览一致', () => {
  const list = tree();
  // W 下 A、D；把 D 插到第 0 位
  api.canvasAttachAt(list, 'D', 'W', 0);
  assert.equal(api.canvasChildren(list, 'W').map((k) => k.cardId).join(','), 'D,A');
  // 同父：把 A 放到第 0 位（D 前面）
  api.canvasAttachAt(list, 'A', 'W', 0);
  assert.equal(api.canvasChildren(list, 'W').map((k) => k.cardId).join(','), 'A,D');
});

check('常量与规格一致', () => {
  assert.equal(api.CANVAS_MAX_DEPTH, 3);
});

console.log('Canvas regression: ' + pass + ' checks passed');
