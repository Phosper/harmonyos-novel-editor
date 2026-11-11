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
  readContract('OutlineExtras.ets'),
  read('editor/OutlineExtract.ets')
]) {
  vm.runInContext(strip(source), context);
}
const api = vm.runInContext('({ FormatRun, FormatCodec, buildOutline, buildOutlineFromParagraphs, layoutOutline, outlineParents,' +
  ' OUTLINE_NODE_W, OUTLINE_NODE_H, OUTLINE_COL_GAP, OUTLINE_PAD, extractHeadings, buildOutlineSnapshot,'+
  ' outlineConnectors, outlineWires, OUTLINE_WIRE_PAD, OUTLINE_WIRE_STEPS,'+
  ' OUTLINE_WIRE_CURVE, OUTLINE_WIRE_ELBOW,'+
  ' OutlineSummary, OutlineRelation, outlineSummaryBoxes, outlineRelationWires, summaryRangeOf,'+
  ' OUTLINE_SUMMARY_GAP, OutlineNodeStyle, isBlankNodeStyle, findNodeStyle, toggleMarker, nodeLabelY,'+
  ' OUTLINE_LAYOUT_RIGHT, OUTLINE_LAYOUT_BALANCED, OUTLINE_LAYOUT_DOWN, OUTLINE_LAYOUT_TABLE,'+
  ' OUTLINE_AXIS_X, OUTLINE_AXIS_Y, OUTLINE_SIB_GAP, OUTLINE_LEVEL_GAP,'+
  ' OUTLINE_TABLE_COL_W, OUTLINE_TABLE_ROW_STEP })', context);

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

check('段落模型建树：节点 id 用 paraId，父下标与节范围可算', () => {
  const nodes = api.buildOutlineFromParagraphs('书名', [
    { id: 'p1', kind: 1, title: '第一章', startOffset: 0, endOffset: 3 },
    { id: 'p3', kind: 2, title: '第一节', startOffset: 10, endOffset: 13 },
    { id: 'p5', kind: 1, title: '第二章', startOffset: 20, endOffset: 23 }
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(nodes.map(n => [n.id, n.paraId, n.parentIndex, n.depth]))),
    [['root', '', -1, 0], ['p1', 'p1', 0, 1], ['p3', 'p3', 1, 2], ['p5', 'p5', 0, 1]]);
  // 第一节的节范围到第二章开头；第一章到第二章开头
  assert.equal(nodes[2].sectionEnd, 20);
  assert.equal(nodes[1].sectionEnd, 20);
});

check('折叠：子树不参与布局，画布随之变矮', () => {
  const nodes = api.buildOutlineFromParagraphs('书名', [
    { id: 'p1', kind: 1, title: '第一章', startOffset: 0, endOffset: 3 },
    { id: 'p3', kind: 2, title: '第一节', startOffset: 10, endOffset: 13 },
    { id: 'p5', kind: 1, title: '第二章', startOffset: 20, endOffset: 23 }
  ]);
  const open = api.layoutOutline(nodes, null);
  const folded = api.layoutOutline(nodes, new Set(['p1']));
  assert.equal(open.nodes.length, 4);
  assert.equal(folded.nodes.length, 3, '被折叠节点的子节点不再出现');
  assert.ok(folded.height <= open.height, '画布高度不会因折叠变大');
  const first = folded.nodes.find(n => n.id === 'p1');
  assert.equal(first.hasChildren, true, '折叠态仍要知道自己有子节点（画徽标）');
  assert.equal(first.collapsed, true);
});

check('连线图元跟着节点矩形走：缩放后端点仍对齐', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '第一章', startOffset: 0, endOffset: 3 },
    { id: 'p2', kind: 2, title: '第一节', startOffset: 6, endOffset: 9 }
  ]);
  const layout = api.layoutOutline(nodes, null, 0.76);
  const links = api.outlineConnectors(layout.nodes);
  assert.equal(links.length, 2, 'root→第一章、第一章→第一节');
  const root = layout.nodes[0];
  const first = layout.nodes[1];
  assert.ok(Math.abs(links[0].fromX - (root.x + api.OUTLINE_NODE_W * root.scale)) < 0.001, '起点在父节点右缘');
  assert.ok(Math.abs(links[0].fromY - (root.y + api.OUTLINE_NODE_H * root.scale / 2)) < 0.001, '起点在父节点垂直中点');
  assert.ok(Math.abs(links[0].toX - first.x) < 0.001, '终点在子节点左缘');
  assert.ok(Math.abs(links[0].toY - (first.y + api.OUTLINE_NODE_H * first.scale / 2)) < 0.001);
  assert.ok(Math.abs(links[0].controlX - (links[0].fromX + links[0].toX) / 2) < 0.001);
  // 换一档缩放，端点必须跟着变（否则就是"节点动了、线没动"）
  const zoomed = api.outlineConnectors(api.layoutOutline(nodes, null, 1.4).nodes);
  assert.ok(Math.abs(zoomed[0].fromX - links[0].fromX) > 1, '缩放后端点跟着重算');
  // 折叠时子节点不参与布局，连线数量随之减少
  const folded = api.outlineConnectors(api.layoutOutline(nodes, new Set(['p1'])).nodes);
  assert.equal(folded.length, 1);
});

check('连线图元 → Polyline 采样点：不越界、端点贴合、包围盒跟着缩放', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '第一章', startOffset: 0, endOffset: 3 },
    { id: 'p2', kind: 2, title: '第一节', startOffset: 6, endOffset: 9 },
    { id: 'p3', kind: 2, title: '第二节', startOffset: 10, endOffset: 13 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const links = api.outlineConnectors(layout.nodes);
  const wires = api.outlineWires(links);
  assert.equal(wires.length, links.length, '每条连线一个 Polyline');
  assert.equal(wires[0].points.length, api.OUTLINE_WIRE_STEPS + 1, '采样段数 + 1 个点');
  for (let i = 0; i < wires.length; i++) {
    const w = wires[i];
    const c = links[i];
    for (const p of w.points) {
      // 组件只会画在自己包围盒里：点越界就会被裁掉（"线只剩一小段"的老毛病）
      assert.ok(p[0] >= 0 && p[0] <= w.width, 'x 落在包围盒内');
      assert.ok(p[1] >= 0 && p[1] <= w.height, 'y 落在包围盒内');
    }
    assert.ok(Math.abs(w.points[0][0] - (c.fromX - w.originX)) < 0.001, '首点在父节点右缘');
    assert.ok(Math.abs(w.points[0][1] - (c.fromY - w.originY)) < 0.001);
    const last = w.points[w.points.length - 1];
    assert.ok(Math.abs(last[0] - (c.toX - w.originX)) < 0.001, '末点在子节点左缘');
    assert.ok(Math.abs(last[1] - (c.toY - w.originY)) < 0.001);
    assert.ok(w.originX <= c.fromX && w.originY <= Math.min(c.fromY, c.toY), '包围盒包住整条曲线（含描边余量）');
  }
  // 缩放：包围盒随节点一起收窄，而不是停在旧尺寸
  const small = api.outlineWires(api.outlineConnectors(api.layoutOutline(nodes, null, 0.76).nodes));
  assert.ok(small[0].width < wires[0].width - 1, '缩放后连线包围盒跟着收窄');
  // 采样段数可调（回归里给个下限：2 段也要能画）
  assert.equal(api.outlineWires(links, 4)[0].points.length, 5);
});

check('同一水平线的父子连线不会被压成 0 高（高度 0 的 Polyline 不渲染）', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '唯一一章', startOffset: 0, endOffset: 3 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const links = api.outlineConnectors(layout.nodes);
  assert.equal(links.length, 1);
  assert.ok(Math.abs(links[0].fromY - links[0].toY) < 0.001, '这里两端的 y 相同');
  const wire = api.outlineWires(links)[0];
  assert.ok(wire.height >= 1, '高度不得为 0');
  assert.ok(wire.width > api.OUTLINE_WIRE_PAD * 2, '宽度含两端描边余量');
  for (const p of wire.points) {
    assert.ok(Math.abs(p[1] - api.OUTLINE_WIRE_PAD) < 0.001, '水平线均分在包围盒中线');
  }
});

check('折叠徽标：子节点数量不受折叠影响，折叠后子树不参与布局', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '第一章', startOffset: 0, endOffset: 3 },
    { id: 'p2', kind: 2, title: '一节', startOffset: 6, endOffset: 9 },
    { id: 'p3', kind: 2, title: '二节', startOffset: 10, endOffset: 13 },
    { id: 'p4', kind: 1, title: '第二章', startOffset: 14, endOffset: 17 }
  ]);
  const open = api.layoutOutline(nodes, null, 1);
  const first = open.nodes.find(n => n.id === 'p1');
  assert.equal(first.childCount, 2, '直接子节点数');
  assert.equal(first.hasChildren, true, '有子节点（画徽标）');
  const folded = api.layoutOutline(nodes, new Set(['p1']), 1);
  const f = folded.nodes.find(n => n.id === 'p1');
  assert.equal(f.childCount, 2, '折叠后数量不变——徽标要显示「2 项」');
  assert.equal(f.collapsed, true);
  assert.equal(folded.nodes.length, open.nodes.length - 2, '两个子节点不参与布局');
});

check('左右均衡：根在中间，一级主题分两侧，左侧连线镜像，最左不越界', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 1, title: '二', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 1, title: '三', startOffset: 6, endOffset: 7 },
    { id: 'p5', kind: 1, title: '四', startOffset: 8, endOffset: 9 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_BALANCED);
  const root = layout.nodes[0];
  const right = layout.nodes.filter(n => n.side > 0);
  const left = layout.nodes.filter(n => n.side < 0);
  assert.ok(right.length >= 1 && left.length >= 1, '两侧都要有主题');
  for (const n of right) {
    assert.ok(n.x > root.x, '右侧节点在根右边');
  }
  for (const n of left) {
    assert.ok(n.x < root.x, '左侧节点在根左边');
  }
  const minX = Math.min(...layout.nodes.map(n => n.x));
  assert.ok(minX >= api.OUTLINE_PAD - 0.001, '最左节点不能被画到负坐标（否则滚不到）');
  assert.ok(layout.width >= root.x + api.OUTLINE_NODE_W, '宽度要包住右侧');
  // 左侧连线端点镜像：父左缘 → 子右缘
  const links = api.outlineConnectors(layout.nodes);
  let mirrored = 0;
  for (let i = 0; i < links.length; i++) {
    const to = layout.nodes[i + 1];
    const from = layout.nodes[to.parentIndex];
    if (to.side < 0) {
      assert.ok(Math.abs(links[i].fromX - from.x) < 0.001, '起点在父节点左缘');
      assert.ok(Math.abs(links[i].toX - (to.x + api.OUTLINE_NODE_W * to.scale)) < 0.001, '终点在子节点右缘');
      mirrored++;
    } else {
      assert.ok(Math.abs(links[i].fromX - (from.x + api.OUTLINE_NODE_W * from.scale)) < 0.001, '右侧仍是父右缘');
    }
  }
  assert.ok(mirrored > 0, '至少有一条左侧连线');
});

check('左右均衡：只有一个一级主题时退回全向右（不把整棵树甩到左边）', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '唯一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '其一', startOffset: 2, endOffset: 3 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_BALANCED);
  assert.ok(layout.nodes.slice(1).every(n => n.side === 1), '全部朝右');
  assert.equal(layout.nodes[0].side, 0, '根不带方向');
});

check('向右布局的几何与旧版一致（根贴内边距、列距不变）', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_RIGHT);
  assert.equal(layout.nodes[0].x, api.OUTLINE_PAD);
  assert.equal(layout.nodes[1].x, api.OUTLINE_PAD + api.OUTLINE_COL_GAP);
  assert.equal(layout.width, api.OUTLINE_PAD * 2 + 2 * api.OUTLINE_COL_GAP + api.OUTLINE_NODE_W);
});

check('分支色号与编号：同一分支同色，编号按文档顺序且不受折叠影响', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 3, title: '一一一', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 1, title: '二', startOffset: 6, endOffset: 7 },
    { id: 'p5', kind: 2, title: '二一', startOffset: 8, endOffset: 9 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const byId = id => layout.nodes.find(n => n.id === id);
  assert.equal(layout.nodes[0].branchIndex, -1, '根没有分支');
  assert.equal(byId('p3').branchIndex, 0, '孙节点继承一级主题的色号');
  assert.equal(byId('p5').branchIndex, 1, '第二个一级主题换色号');
  assert.deepEqual(JSON.parse(JSON.stringify(layout.nodes.map(n => n.orderLabel))),
    ['', '1', '1.1', '1.1.1', '2', '2.1']);
  // 折叠不改变编号：编号按真实文档顺序算，不是按可见顺序
  const folded = api.layoutOutline(nodes, new Set(['p1']), 1);
  assert.equal(folded.nodes.find(n => n.id === 'p4').orderLabel, '2');
  // 连线与图元都带着"要画哪种颜色"
  const links = api.outlineConnectors(layout.nodes);
  for (let i = 0; i < links.length; i++) {
    assert.equal(links[i].branchIndex, layout.nodes[i + 1].branchIndex, '连线取子节点的分支色号');
  }
  const wires = api.outlineWires(links);
  assert.equal(wires[0].branchIndex, links[0].branchIndex, '图元保留色号');
});

check('折线画法：四点折线，首尾贴合端点，全部落在包围盒内', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const links = api.outlineConnectors(layout.nodes);
  // 第 2 条（p1 → p2）两端 y 不同，才会出现竖段；第 1 条是根→p1，天然水平
  const elbow = api.outlineWires(links, api.OUTLINE_WIRE_STEPS, api.OUTLINE_WIRE_ELBOW)[1];
  assert.equal(elbow.points.length, 4, '父缘 → 中缝 → 中缝 → 子缘');
  assert.ok(Math.abs(elbow.points[0][0] - (links[1].fromX - elbow.originX)) < 0.001, '首点在父节点右缘');
  assert.ok(Math.abs(elbow.points[1][0] - (links[1].controlX - elbow.originX)) < 0.001, '竖段落在两点中间');
  assert.ok(Math.abs(elbow.points[3][0] - (links[1].toX - elbow.originX)) < 0.001, '末点在子节点左缘');
  assert.ok(Math.abs(elbow.points[1][1] - elbow.points[2][1]) > 0.001, '两段水平线高度不同才需要竖段');
  for (const p of elbow.points) {
    assert.ok(p[0] >= 0 && p[0] <= elbow.width, 'x 不越界');
    assert.ok(p[1] >= 0 && p[1] <= elbow.height, 'y 不越界');
  }
  // 切回曲线：点数回到采样数 + 1
  assert.equal(api.outlineWires(links, api.OUTLINE_WIRE_STEPS, api.OUTLINE_WIRE_CURVE)[0].points.length,
    api.OUTLINE_WIRE_STEPS + 1);
});

check('概要：括号落在成员外侧、覆盖首末成员、端点缺失就整条不画', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 2, title: '一三', startOffset: 6, endOffset: 7 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const at = id => layout.nodes.find(n => n.id === id);
  const box = api.outlineSummaryBoxes(layout.nodes,
    [new api.OutlineSummary('s1', 'p2', 'p3', '这两节在讲同一件事')]);
  assert.equal(box.length, 1, '端点都能找到就画一条');
  const b = box[0];
  const first = at('p2');
  const last = at('p3');
  // 括号要盖住两个成员，且比节点更靠外
  assert.ok(b.originY <= first.y + 0.001, '上端不低于第一节的顶');
  assert.ok(b.originY + b.height >= last.y + api.OUTLINE_NODE_H - 0.001, '下端不低于最后一节的底');
  const bracketLeft = b.originX + b.points[1][0];
  assert.ok(bracketLeft > at('p4').x - api.OUTLINE_SUMMARY_GAP, '括号在成员外侧（朝右时在右边）');
  for (const p of b.points) {
    assert.ok(p[0] >= 0 && p[0] <= b.width, 'x 落在包围盒内');
    assert.ok(p[1] >= 0 && p[1] <= b.height, 'y 落在包围盒内');
  }
  assert.ok(b.textX > bracketLeft, '文字在括号更外侧');
  assert.equal(b.alignEnd, false, '朝右的分支文字靠左排');

  // 端点被折叠/删除 → 不画（绝不能画到别的分支上）
  assert.equal(api.outlineSummaryBoxes(layout.nodes,
    [new api.OutlineSummary('s2', 'p2', 'gone', '')]).length, 0);
  // 跨分支（父不同）→ 不画
  assert.equal(api.outlineSummaryBoxes(layout.nodes,
    [new api.OutlineSummary('s3', 'p1', 'p2', '')]).length, 0);
});

check('概要：左侧分支的括号镜像，文字靠右对齐', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 1, title: '二', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '二一', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 2, title: '二二', startOffset: 6, endOffset: 7 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_BALANCED);
  const byId = id => layout.nodes.find(n => n.id === id);
  assert.equal(byId('p1').side, 1, '第一节在右');
  assert.equal(byId('p2').side, -1, '第二节在左');
  const box = api.outlineSummaryBoxes(layout.nodes, [new api.OutlineSummary('s1', 'p3', 'p4', '左组')]);
  assert.equal(box.length, 1);
  assert.equal(box[0].alignEnd, true, '左侧括号的文字靠右对齐');
  const bracketX = box[0].originX + box[0].points[1][0];
  assert.ok(bracketX < byId('p3').x, '括号在左侧成员的外面（更靠左）');
  assert.ok(box[0].textX + api.OUTLINE_NODE_W > bracketX, '文字在括号外侧');
});

check('关系线：两端落在朝向对方的那条边上，标签在中点附近', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 1, title: '二', startOffset: 4, endOffset: 5 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const byId = id => layout.nodes.find(n => n.id === id);
  const wires = api.outlineRelationWires(layout.nodes, [new api.OutlineRelation('r1', 'p1', 'p2', 'A 论证 B')]);
  assert.equal(wires.length, 1);
  const w = wires[0];
  const a = byId('p1');
  const b = byId('p2');
  const first = w.points[0];
  const last = w.points[w.points.length - 1];
  assert.ok(Math.abs((first[0] + w.originX) - (a.x + api.OUTLINE_NODE_W)) < 0.001, '起点在 a 的右缘');
  assert.ok(Math.abs((first[1] + w.originY) - (a.y + api.OUTLINE_NODE_H / 2)) < 0.001, '起点在 a 的垂直中点');
  assert.ok(Math.abs((last[0] + w.originX) - b.x) < 0.001, '终点在 b 的左缘');
  assert.equal(w.arrow.length, 3, '箭头三点');
  for (const p of w.points) {
    assert.ok(p[0] >= 0 && p[0] <= w.width, 'x 落在包围盒内');
    assert.ok(p[1] >= 0 && p[1] <= w.height, 'y 落在包围盒内');
  }
  assert.ok(w.labelX > first[0] + w.originX - 1 && w.labelX < last[0] + w.originX + 1, '标签在中段');
  // 同一列的两个人：走上下边，不能出现 0 长的水平线
  const vertical = api.outlineRelationWires(layout.nodes, [new api.OutlineRelation('r4', 'p1', 'p3', '')]);
  assert.equal(vertical.length, 1);
  const v = vertical[0];
  const va = byId('p1');
  const vy = v.points[0][1] + v.originY;
  assert.ok(Math.abs(vy - (va.y + api.OUTLINE_NODE_H)) < 0.001 || Math.abs(vy - va.y) < 0.001,
    '同一列时从 a 的上/下边出发');
  // 端点缺失或两端相同 → 不画
  assert.equal(api.outlineRelationWires(layout.nodes, [new api.OutlineRelation('r2', 'p1', 'gone', '')]).length, 0);
  assert.equal(api.outlineRelationWires(layout.nodes, [new api.OutlineRelation('r3', 'p1', 'p1', '')]).length, 0);
});

check('多选 → 概要端点：同父才算数，顺序取文档先后', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 1, title: '二', startOffset: 6, endOffset: 7 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  // 顺序反着选也要按文档顺序给端点
  assert.deepEqual(JSON.parse(JSON.stringify(api.summaryRangeOf(layout.nodes, ['p3', 'p2']))), ['p2', 'p3']);
  assert.deepEqual(JSON.parse(JSON.stringify(api.summaryRangeOf(layout.nodes, ['p1', 'p2']))), [],
    '不同父不能做概要');
  assert.deepEqual(JSON.parse(JSON.stringify(api.summaryRangeOf(layout.nodes, ['p2']))), [],
    '只选一个不够');
  assert.deepEqual(JSON.parse(JSON.stringify(api.summaryRangeOf(layout.nodes, ['p2', 'gone']))), [],
    '未知端点不算');
});

check('节点样式：空白判定、标记上限三个、标签挂在节点下方', () => {
  const blank = new api.OutlineNodeStyle('p1');
  assert.equal(api.isBlankNodeStyle(blank), true, '新样式就是"什么都没改"');
  const shaped = new api.OutlineNodeStyle('p1');
  shaped.shape = 'pill';
  assert.equal(api.isBlankNodeStyle(shaped), false);
  const labeled = new api.OutlineNodeStyle('p2');
  labeled.label = '重点';
  assert.equal(api.isBlankNodeStyle(labeled), false);

  // 标记：点一下加、再点一下删，最多三个（第四个别把标题挤没）
  let style = new api.OutlineNodeStyle('p3');
  style = api.toggleMarker(style, '⭐');
  style = api.toggleMarker(style, '✅');
  style = api.toggleMarker(style, '🔥');
  style = api.toggleMarker(style, '❗');
  assert.deepEqual(JSON.parse(JSON.stringify(style.markers)), ['⭐', '✅', '🔥'], '最多三个');
  style = api.toggleMarker(style, '✅');
  assert.deepEqual(JSON.parse(JSON.stringify(style.markers)), ['⭐', '🔥'], '再点一次就删掉');
  // 切换标记不能把别的字段弄丢
  const rich = new api.OutlineNodeStyle('p4');
  rich.shape = 'pill';
  rich.fill = '#D2543F';
  rich.bold = true;
  rich.label = '重点';
  const toggled = api.toggleMarker(rich, '⭐');
  assert.equal(toggled.shape, 'pill');
  assert.equal(toggled.fill, '#D2543F');
  assert.equal(toggled.bold, true);
  assert.equal(toggled.label, '重点');

  // 按 paraId 找样式；找不到返回 undefined（渲染层据此用全局设置）
  const list = [api.toggleMarker(new api.OutlineNodeStyle('p5'), '⭐')];
  assert.equal(api.findNodeStyle(list, 'p5') !== undefined, true);
  assert.equal(api.findNodeStyle(list, 'p6'), undefined);
  assert.equal(api.findNodeStyle(list, ''), undefined, '空身份不该命中');

  const nodes = api.buildOutlineFromParagraphs('书', [{ id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 }]);
  const layout = api.layoutOutline(nodes, null, 1);
  const node = layout.nodes[1];
  assert.equal(api.nodeLabelY(node), node.y + api.OUTLINE_NODE_H + 2, '标签贴在节点下沿');
});

check('连线终点：箭头按主轴摆正（横向朝左右、纵向朝上下）', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1);
  const links = api.outlineConnectors(layout.nodes);
  const wires = api.outlineWires(links);
  for (let i = 0; i < wires.length; i++) {
    assert.ok(Math.abs(wires[i].endX - links[i].toX) < 0.001, '终点 x 与连线端点一致');
    assert.ok(Math.abs(wires[i].endY - links[i].toY) < 0.001, '终点 y 与连线端点一致');
    assert.ok(Math.abs(Math.cos(wires[i].endAngle)) > 0.999, '横向布局的箭头朝左右');
  }
  // 折线的末段同样是水平的（父缘→中缝→中缝→子缘）
  const elbows = api.outlineWires(links, api.OUTLINE_WIRE_STEPS, api.OUTLINE_WIRE_ELBOW);
  for (const w of elbows) {
    assert.ok(Math.abs(Math.cos(w.endAngle)) > 0.999, '横向折线的末段水平，箭头要横着摆');
  }
});

check('组织架构（向下）：根在上、兄弟不重叠、父节点居中在子节点上方', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 },
    { id: 'p4', kind: 1, title: '二', startOffset: 6, endOffset: 7 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_DOWN);
  const byId = id => layout.nodes.find(n => n.id === id);
  const root = layout.nodes[0];
  const p1 = byId('p1');
  assert.equal(root.axis, api.OUTLINE_AXIS_Y, '纵向主轴');
  assert.equal(p1.y, api.OUTLINE_PAD + api.OUTLINE_LEVEL_GAP, '一层一格垂直间距');
  assert.ok(root.y < p1.y, '根在子节点上方');
  // 兄弟按文档顺序从左往右，且不重叠
  assert.ok(byId('p2').x < byId('p3').x, '兄弟从左到右按顺序');
  assert.ok(byId('p2').x + api.OUTLINE_NODE_W <= byId('p3').x, '兄弟不能重叠');
  // 父节点居中在两个子节点之间
  const c2center = byId('p2').x + api.OUTLINE_NODE_W / 2;
  const c3center = byId('p3').x + api.OUTLINE_NODE_W / 2;
  assert.ok(Math.abs((c2center + c3center) / 2 - (p1.x + api.OUTLINE_NODE_W / 2)) < 0.001, '父节点居中在子节点上方');
  // 子树不越界
  const minX = Math.min(...layout.nodes.map(n => n.x));
  assert.ok(minX >= api.OUTLINE_PAD - 0.001, '最左节点不被画到负坐标');
  assert.ok(layout.width >= byId('p2').x + api.OUTLINE_NODE_W, '宽度包住最右的节点');
});

check('树形表格：一列一层、一行一个主题，行高与列宽固定', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 1, title: '二', startOffset: 4, endOffset: 5 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_TABLE);
  const byId = id => layout.nodes.find(n => n.id === id);
  assert.equal(byId('p1').x, api.OUTLINE_PAD + api.OUTLINE_TABLE_COL_W, '第二层在第 2 列');
  assert.equal(byId('p2').x, api.OUTLINE_PAD + 2 * api.OUTLINE_TABLE_COL_W, '第三层在第 3 列');
  assert.equal(byId('p3').x, api.OUTLINE_PAD + api.OUTLINE_TABLE_COL_W, '回到第一级也回到第 2 列');
  // y 按文档顺序逐行递增（父子相邻，不会因为深度跳格）
  const ys = layout.nodes.map(n => n.y);
  for (let i = 1; i < ys.length; i++) {
    assert.ok(ys[i] > ys[i - 1], '每行一个主题，y 单调递增');
    assert.equal(ys[i] - ys[i - 1], api.OUTLINE_TABLE_ROW_STEP);
  }
  assert.equal(layout.height, api.OUTLINE_PAD * 2 + (layout.nodes.length - 1) * api.OUTLINE_TABLE_ROW_STEP
    + api.OUTLINE_NODE_H);
});

check('纵向连线：父下沿中点 → 子上沿中点，箭头竖直，采样不越界', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 },
    { id: 'p3', kind: 2, title: '一二', startOffset: 4, endOffset: 5 }
  ]);
  const layout = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_DOWN);
  const byId = id => layout.nodes.find(n => n.id === id);
  const links = api.outlineConnectors(layout.nodes);
  assert.equal(links.length, 3);
  for (let i = 0; i < links.length; i++) {
    const to = layout.nodes[i + 1];
    const from = layout.nodes[to.parentIndex];
    const c = links[i];
    assert.ok(Math.abs(c.fromX - (from.x + api.OUTLINE_NODE_W / 2)) < 0.001, '起点在父节点中线');
    assert.ok(Math.abs(c.fromY - (from.y + api.OUTLINE_NODE_H)) < 0.001, '起点在父节点下沿');
    assert.ok(Math.abs(c.toX - (to.x + api.OUTLINE_NODE_W / 2)) < 0.001, '终点在子节点中线');
    assert.ok(Math.abs(c.toY - to.y) < 0.001, '终点在子节点上沿');
    assert.ok(Math.abs(c.controlY - (c.fromY + c.toY) / 2) < 0.001, '控制点在竖直中点');
  }
  const wires = api.outlineWires(links);
  for (const w of wires) {
    for (const p of w.points) {
      assert.ok(p[0] >= 0 && p[0] <= w.width, 'x 落在包围盒内');
      assert.ok(p[1] >= 0 && p[1] <= w.height, 'y 落在包围盒内');
    }
    assert.ok(Math.abs(Math.sin(w.endAngle)) > 0.999, '纵向连线的箭头朝上下');
  }
  // 折线：先竖出去，再横着进子节点
  for (const w of api.outlineWires(links, api.OUTLINE_WIRE_STEPS, api.OUTLINE_WIRE_ELBOW)) {
    assert.equal(w.points.length, 4);
    assert.ok(Math.abs(Math.sin(w.endAngle)) > 0.999, '纵向折线的末段竖直');
  }
});

check('纵向布局同样受折叠影响', () => {
  const nodes = api.buildOutlineFromParagraphs('书', [
    { id: 'p1', kind: 1, title: '一', startOffset: 0, endOffset: 1 },
    { id: 'p2', kind: 2, title: '一一', startOffset: 2, endOffset: 3 }
  ]);
  const open = api.layoutOutline(nodes, null, 1, api.OUTLINE_LAYOUT_DOWN);
  const folded = api.layoutOutline(nodes, new Set(['p1']), 1, api.OUTLINE_LAYOUT_DOWN);
  assert.equal(folded.nodes.length, open.nodes.length - 1, '折叠后子节点不参与布局');
  assert.ok(folded.height < open.height, '折叠后画布随之变矮');
});

console.log('Outline regression: ' + pass + ' checks passed');
