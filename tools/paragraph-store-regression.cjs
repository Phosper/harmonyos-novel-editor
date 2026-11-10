// Node 24+. P5 第一步：段落侧车表 + 迁移映射。
// 用 node:sqlite 重放 DatabaseHelper 的建表语句，并直接执行 DocumentModel 的行映射；
// 证明“旧正文能拆成段落、写进去、按 ordinal 读回、投影不丢文本/样式”。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const { DatabaseSync } = require('node:sqlite');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const strip = text => stripTypeScriptTypes(text
  .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+default\s+/g, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });

const context = vm.createContext({ console: { log() {}, warn() {}, error() {} } });
for (const file of ['editor/flowtext/model/EditorTypes.ets', 'editor/flowtext/model/FormatCodec.ets',
  'editor/model/DocumentModel.ets']) {
  vm.runInContext(strip(read(file)), context, { filename: file });
}
const api = vm.runInContext('({ FormatRun, FormatCodec, createDocument, project, documentRows })', context);

const dbSource = fs.readFileSync(path.join(root, 'database/DatabaseHelper.ets'), 'utf8');
function extractSqls() {
  const start = dbSource.indexOf('const sqls: string[] = [');
  assert.ok(start >= 0, 'DatabaseHelper 里找不到 sqls 数组');
  const bodyStart = dbSource.indexOf('[', start);
  const bodyEnd = dbSource.indexOf('\n    ]', bodyStart);
  assert.ok(bodyEnd > bodyStart, '无法定位 sqls 数组结束位置');
  const sqls = new Function('return ' + dbSource.slice(bodyStart, bodyEnd + 6))();
  assert.ok(Array.isArray(sqls) && sqls.length > 0, 'sqls 不是非空数组');
  return sqls;
}
const sqls = extractSqls();

let pass = 0;
function check(name, action) {
  try {
    action();
    pass++;
    console.log('PASS ' + name);
  } catch (error) {
    console.error('FAIL ' + name + ' :: ' + error.message);
    process.exitCode = 1;
  }
}

function newDb() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  return db;
}

function insertChapter(db, id, title = '书名') {
  db.prepare('INSERT INTO chapters (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)')
    .run(id, title, 1, 1);
}

function insertRows(db, model) {
  const rows = api.documentRows(model);
  const p = db.prepare('INSERT INTO doc_paragraphs ' +
    '(doc_id, para_id, ordinal, kind, indent, text) VALUES (?, ?, ?, ?, ?, ?)');
  for (let i = 0; i < rows.paragraphs.length; i++) {
    const row = rows.paragraphs[i];
    p.run(row.docId, row.paraId, row.ordinal, row.kind, row.indent, row.text);
  }
  const r = db.prepare('INSERT INTO doc_runs ' +
    '(doc_id, para_id, start_off, end_off, bold, italic) VALUES (?, ?, ?, ?, ?, ?)');
  for (let i = 0; i < rows.runs.length; i++) {
    const row = rows.runs[i];
    r.run(row.docId, row.paraId, row.start, row.end, row.bold ? 1 : 0, row.italic ? 1 : 0);
  }
  return rows;
}

const json = value => JSON.parse(JSON.stringify(value));

function sample(id = 'doc-1') {
  const text = '第一章 引言\n这是正文。\n子项内容\n第一节\n结尾';
  const runs = [
    new api.FormatRun(0, 6, false, false, 1, 0),
    new api.FormatRun(13, 17, false, false, 4, 1),
    new api.FormatRun(7, 11, true, false, 0, 0),
    new api.FormatRun(18, 21, false, false, 2, 0)
  ];
  return api.createDocument(id, '书名', text, api.FormatCodec.encode(runs));
}

check('行映射：段落序号、种类、层级与段内偏移', () => {
  const rows = json(api.documentRows(sample()));
  assert.deepEqual(rows.paragraphs.map(p => [p.paraId, p.ordinal, p.kind, p.indent, p.text]), [
    ['p1', 0, 1, 0, '第一章 引言'],
    ['p2', 1, 0, 0, '这是正文。'],
    ['p3', 2, 4, 1, '子项内容'],
    ['p4', 3, 2, 0, '第一节'],
    ['p5', 4, 0, 0, '结尾']
  ]);
  assert.deepEqual(rows.runs.map(r => [r.paraId, r.start, r.end, r.bold, r.italic]),
    [['p2', 0, 4, true, false]]);
});

check('写库后按 ordinal 读回段落，行内样式是段内偏移', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  insertRows(db, sample());
  const paragraphs = db.prepare('SELECT para_id, ordinal, kind, indent, text FROM doc_paragraphs ' +
    'WHERE doc_id = ? ORDER BY ordinal').all('doc-1');
  assert.equal(paragraphs.length, 5);
  assert.deepEqual(paragraphs.map(p => p.para_id), ['p1', 'p2', 'p3', 'p4', 'p5']);
  assert.deepEqual(paragraphs.map(p => p.kind), [1, 0, 4, 2, 0]);
  assert.equal(paragraphs[2].indent, 1);
  assert.equal(paragraphs[1].text, '这是正文。');
  const runs = db.prepare('SELECT para_id, start_off, end_off, bold, italic FROM doc_runs ' +
    'WHERE doc_id = ? ORDER BY start_off').all('doc-1');
  assert.deepEqual(runs.map(r => [r.para_id, r.start_off, r.end_off, r.bold, r.italic]),
    [['p2', 0, 4, 1, 0]]);
  db.close();
});

check('从表行重建模型并投影，正文与格式边车往返一致', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  const original = sample();
  insertRows(db, original);
  const paragraphs = db.prepare('SELECT para_id, kind, indent, text FROM doc_paragraphs ' +
    'WHERE doc_id = ? ORDER BY ordinal').all('doc-1')
    .map(row => ({ id: row.para_id, kind: row.kind, indent: row.indent, text: row.text }));
  const runs = db.prepare('SELECT para_id, start_off, end_off, bold, italic FROM doc_runs ' +
    'WHERE doc_id = ? ORDER BY start_off').all('doc-1')
    .map(row => ({ paraId: row.para_id, start: row.start_off, end: row.end_off,
      bold: row.bold === 1, italic: row.italic === 1 }));
  const restored = { id: 'doc-1', title: '书名', paragraphs, runs, version: 1 };
  const projection = api.project(restored);
  const expected = api.project(original);
  assert.equal(projection.text, expected.text);
  assert.deepEqual(json(api.FormatCodec.decode(projection.runsJson).map(r =>
    [r.startOffset, r.endOffset, r.heading, r.indent, r.bold, r.italic])),
  json(api.FormatCodec.decode(expected.runsJson).map(r =>
    [r.startOffset, r.endOffset, r.heading, r.indent, r.bold, r.italic])));
  db.close();
});

check('空文档也保留一行空段', () => {
  const db = newDb();
  insertChapter(db, 'doc-empty');
  const rows = insertRows(db, api.createDocument('doc-empty', '', '', ''));
  assert.equal(rows.paragraphs.length, 1);
  assert.equal(rows.paragraphs[0].text, '');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM doc_paragraphs WHERE doc_id = ?')
    .get('doc-empty').n, 1);
  db.close();
});

check('替换式迁移幂等：重复 delete + insert 不增行', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  const model = sample();
  insertRows(db, model);
  const before = db.prepare('SELECT COUNT(*) AS n FROM doc_paragraphs WHERE doc_id = ?').get('doc-1').n;
  db.exec("DELETE FROM doc_runs WHERE doc_id = 'doc-1'");
  db.exec("DELETE FROM doc_paragraphs WHERE doc_id = 'doc-1'");
  insertRows(db, model);
  const after = db.prepare('SELECT COUNT(*) AS n FROM doc_paragraphs WHERE doc_id = ?').get('doc-1').n;
  assert.equal(after, before);
  assert.deepEqual(db.prepare('SELECT para_id FROM doc_paragraphs WHERE doc_id = ? ORDER BY ordinal')
    .all('doc-1').map(row => row.para_id), ['p1', 'p2', 'p3', 'p4', 'p5']);
  db.close();
});

check('段落主键拒绝同文档重复 para_id', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  const p = db.prepare('INSERT INTO doc_paragraphs ' +
    '(doc_id, para_id, ordinal, kind, indent, text) VALUES (?, ?, ?, ?, ?, ?)');
  p.run('doc-1', 'p1', 0, 0, 0, 'a');
  assert.throws(() => p.run('doc-1', 'p1', 1, 0, 0, 'b'), /UNIQUE|constraint/i);
  db.close();
});

check('行内样式外键拒绝悬空 para_id', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  assert.throws(() => {
    db.prepare('INSERT INTO doc_runs ' +
      '(doc_id, para_id, start_off, end_off, bold, italic) VALUES (?, ?, ?, ?, ?, ?)')
      .run('doc-1', 'missing', 0, 1, 1, 0);
  }, /FOREIGN KEY|constraint/i);
  db.close();
});

check('删除文稿级联清理段落与行内样式', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  insertRows(db, sample());
  db.exec("DELETE FROM chapters WHERE id = 'doc-1'");
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM doc_paragraphs').get().n, 0);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM doc_runs').get().n, 0);
  db.close();
});

check('schema_meta 可记录并覆盖一次性迁移标记', () => {
  const db = newDb();
  db.prepare('INSERT INTO schema_meta (meta_key, meta_value, updated_at) VALUES (?, ?, ?)')
    .run('paragraph_v1', 'done', 1);
  assert.equal(db.prepare('SELECT meta_value FROM schema_meta WHERE meta_key = ?')
    .get('paragraph_v1').meta_value, 'done');
  db.exec("DELETE FROM schema_meta WHERE meta_key = 'paragraph_v1'");
  db.prepare('INSERT INTO schema_meta (meta_key, meta_value, updated_at) VALUES (?, ?, ?)')
    .run('paragraph_v1', 'done', 2);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM schema_meta').get().n, 1);
  db.close();
});

check('ordinal 决定读回顺序，不受插入顺序影响', () => {
  const db = newDb();
  insertChapter(db, 'doc-1');
  const p = db.prepare('INSERT INTO doc_paragraphs ' +
    '(doc_id, para_id, ordinal, kind, indent, text) VALUES (?, ?, ?, ?, ?, ?)');
  p.run('doc-1', 'p2', 1, 0, 0, '第二段');
  p.run('doc-1', 'p1', 0, 0, 0, '第一段');
  assert.deepEqual(db.prepare('SELECT para_id FROM doc_paragraphs WHERE doc_id = ? ORDER BY ordinal')
    .all('doc-1').map(row => row.para_id), ['p1', 'p2']);
  db.close();
});

console.log('Paragraph store regression: ' + pass + ' checks passed');
