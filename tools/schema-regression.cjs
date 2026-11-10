// Node 22.5+. 用内置 node:sqlite 重放 DatabaseHelper 的建表/索引语句。
// 目的：建表 SQL 是纯字符串拼接，拼错（少逗号、两句粘一起）不会被 ArkTS 编译器发现，
// 只会在真机首次启动时炸成「数据库初始化失败」。这里把同一批 SQL 原样跑一遍。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');

const file = path.resolve(__dirname, '../entry/src/main/ets/database/DatabaseHelper.ets');
const source = fs.readFileSync(file, 'utf8');

function extractSqls() {
  const start = source.indexOf('const sqls: string[] = [');
  assert.ok(start >= 0, 'DatabaseHelper 里找不到 const sqls 数组');
  const bodyStart = source.indexOf('[', start);
  const bodyEnd = source.indexOf('\n    ]', bodyStart);
  assert.ok(bodyEnd > bodyStart, '无法定位 sqls 数组结束位置');
  const literal = source.slice(bodyStart, bodyEnd + 6);
  const sqls = new Function('return ' + literal)();
  assert.ok(Array.isArray(sqls) && sqls.length > 0, 'sqls 不是非空数组');
  return sqls;
}

let pass = 0;
function check(name, action) {
  try { action(); pass++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name + ' :: ' + error.message); process.exitCode = 1; }
}

const sqls = extractSqls();

check('每条语句只包含一个 CREATE（防止两句被拼成一句）', () => {
  for (let i = 0; i < sqls.length; i++) {
    const s = sqls[i];
    assert.ok(/^\s*CREATE\s+(TABLE|INDEX)\s+IF\s+NOT\s+EXISTS\s+/i.test(s), '第 ' + i + ' 句不是 CREATE: ' + s.slice(0, 60));
    assert.equal((s.match(/CREATE\s+(TABLE|INDEX)/gi) || []).length, 1,
      '第 ' + i + ' 句里出现了多个 CREATE: ' + s.slice(0, 80));
  }
});

check('空库可完整建表（含外键）且可重复执行', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  // 幂等：再跑一遍不能报错
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    .all().map((row) => row.name);
  const expected = ['books', 'canvas_links', 'canvas_placements', 'canvases', 'chapters',
    'characters', 'doc_paragraphs', 'doc_runs', 'inspirations', 'relationships', 'schema_meta',
    'topic_evidence', 'topics', 'world_settings'];
  for (let i = 0; i < expected.length; i++) {
    assert.ok(tables.indexOf(expected[i]) >= 0, '缺表 ' + expected[i] + '，实际: ' + tables.join(','));
  }
  const indexes = db.prepare("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'")
    .all().map((row) => row.name);
  ['idx_canvas_book', 'idx_topics_book', 'idx_evidence_topic', 'idx_placement_canvas',
    'idx_placement_parent', 'idx_link_canvas', 'idx_doc_paragraphs_order',
    'idx_doc_runs_para'].forEach((name) => {
    assert.ok(indexes.indexOf(name) >= 0, '缺索引 ' + name);
  });
  db.close();
});

check('旧库（仅 books/chapters）升级后 14 张业务表齐全', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('CREATE TABLE books (id TEXT PRIMARY KEY, name TEXT NOT NULL, mode TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
  db.exec('CREATE TABLE chapters (id TEXT PRIMARY KEY, book_id TEXT NOT NULL, title TEXT NOT NULL)');
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  const count = db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get().n;
  assert.ok(count >= 14, '升级后表数量不足: ' + count);
  db.close();
});

check('段落与行内样式随文稿删除级联清理', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  db.exec("INSERT INTO chapters (id, title, created_at, updated_at) VALUES ('ch1', 't', 1, 1)");
  db.exec("INSERT INTO doc_paragraphs (doc_id, para_id, ordinal, kind, indent, text) " +
    "VALUES ('ch1', 'p1', 0, 1, 0, '标题')");
  db.exec("INSERT INTO doc_runs (doc_id, para_id, start_off, end_off, bold, italic) " +
    "VALUES ('ch1', 'p1', 0, 1, 1, 0)");
  // 删段落应先带走它的行内样式
  db.exec("DELETE FROM doc_paragraphs WHERE doc_id = 'ch1' AND para_id = 'p1'");
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM doc_runs").get().n, 0,
    '删除段落应级联删除 doc_runs');
  // 删文稿应带走段落与行内样式
  db.exec("INSERT INTO doc_paragraphs (doc_id, para_id, ordinal, kind, indent, text) " +
    "VALUES ('ch1', 'p1', 0, 1, 0, '标题')");
  db.exec("INSERT INTO doc_runs (doc_id, para_id, start_off, end_off, bold, italic) " +
    "VALUES ('ch1', 'p1', 0, 1, 1, 0)");
  db.exec("DELETE FROM chapters WHERE id = 'ch1'");
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM doc_paragraphs").get().n, 0,
    '删除文稿应级联删除 doc_paragraphs');
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM doc_runs").get().n, 0,
    '删除文稿应级联删除 doc_runs');
  db.close();
});

check('画布外键可拦截悬空贴放', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (let i = 0; i < sqls.length; i++) {
    db.exec(sqls[i]);
  }
  db.exec("INSERT INTO topics (id, title, created_at, updated_at) VALUES ('t1', '均势', 1, 1)");
  db.exec("INSERT INTO canvases (id, scope, created_at, updated_at) VALUES ('c1', 'free', 1, 1)");
  assert.throws(() => {
    db.exec("INSERT INTO canvas_placements (id, canvas_id, topic_id) VALUES ('p1', 'c1', 'missing')");
  }, /FOREIGN KEY|constraint/i, '悬空 topic_id 应被外键拦截');
  db.exec("INSERT INTO canvas_placements (id, canvas_id, topic_id) VALUES ('p2', 'c1', 't1')");
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM canvas_placements").get().n, 1, '合法贴放应能写入');
  db.close();
});

check('同板同卡唯一索引只在无重复时创建（有重复则跳过等下次）', () => {
  const src = fs.readFileSync(file, 'utf8');
  assert.ok(src.includes('ux_placement_card'), '缺唯一索引 SQL');
  assert.ok(src.includes('HAVING COUNT(*) > 1'), '缺重复预检');
});

console.log('Schema regression: ' + pass + ' checks passed');
