// Node 24+. P5 迁移链路：直接执行 ArkTS 的 ChapterDao / ParagraphRepository /
// ParagraphMigration，用受控 Store/Transaction 替身验证“逐篇迁移、幂等、失败回滚”。
// 不连真机数据库；schema 的 SQL 由 paragraph-store-regression 用 node:sqlite 单独验证。
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

class Predicates {
  constructor(table) { this.table = table; this.conditions = []; this.order = null; }
  equalTo(key, value) { this.conditions.push(row => row[key] === value); return this; }
  lessThan(key, value) { this.conditions.push(row => row[key] < value); return this; }
  orderByAsc(key) { this.order = [key, 1]; return this; }
  orderByDesc(key) { this.order = [key, -1]; return this; }
  matches(row) { return this.conditions.every(test => test(row)); }
}

class ResultSet {
  constructor(rows) {
    this.rows = rows;
    this.index = -1;
    this.columns = Object.keys(rows[0] || {});
    this.closed = false;
  }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { return ++this.index < this.rows.length; }
  getColumnIndex(key) { return this.columns.indexOf(key); }
  getString(index) { return this.rows[this.index][this.columns[index]] ?? ''; }
  getLong(index) { return Number(this.rows[this.index][this.columns[index]] ?? 0); }
  getDouble(index) { return Number(this.rows[this.index][this.columns[index]] ?? 0); }
  close() { this.closed = true; }
}

const TABLE_NAMES = ['chapters', 'doc_paragraphs', 'doc_runs', 'schema_meta'];

class StoreDouble {
  constructor(failState = { docId: '', updateTable: '' }) {
    this.tables = new Map(TABLE_NAMES.map(name => [name, []]));
    this.nextRunId = 1;
    this.failState = failState;
    this.activeTx = null;
    this.paragraphQueries = 0;
  }
  rows(table) { return this.tables.get(table); }
  insert(table, value) {
    if (table === 'doc_paragraphs') {
      if (this.failState.docId !== '' && value.doc_id === this.failState.docId) {
        throw new Error('simulated paragraph insert failure');
      }
      const rows = this.tables.get(table);
      if (rows.some(row => row.doc_id === value.doc_id && row.para_id === value.para_id)) {
        throw new Error('UNIQUE constraint failed: doc_paragraphs');
      }
      rows.push({...value});
      return 1;
    }
    if (table === 'doc_runs') {
      this.tables.get(table).push({id: this.nextRunId++, ...value});
      return 1;
    }
    if (table === 'schema_meta') {
      const rows = this.tables.get(table);
      if (rows.some(row => row.meta_key === value.meta_key)) {
        throw new Error('UNIQUE constraint failed: schema_meta');
      }
      rows.push({...value});
      return 1;
    }
    if (table === 'chapters') {
      const rows = this.tables.get(table);
      if (rows.some(row => row.id === value.id)) {
        throw new Error('UNIQUE constraint failed: chapters');
      }
      rows.push({...value});
      return 1;
    }
    throw new Error('Unsupported insert table: ' + table);
  }
  update(value, predicates) {
    if (this.failState.updateTable !== '' && predicates.table === this.failState.updateTable) {
      throw new Error('simulated ' + predicates.table + ' update failure');
    }
    let count = 0;
    for (const row of this.tables.get(predicates.table)) {
      if (predicates.matches(row)) { Object.assign(row, value); count++; }
    }
    return count;
  }
  delete(predicates) {
    const rows = this.tables.get(predicates.table);
    const kept = rows.filter(row => !predicates.matches(row));
    const count = rows.length - kept.length;
    this.tables.set(predicates.table, kept);
    return count;
  }
  query(predicates) {
    if (predicates.table === 'doc_paragraphs') {
      this.paragraphQueries++;
    }
    let rows = this.tables.get(predicates.table).filter(row => predicates.matches(row));
    if (predicates.order !== null) {
      const key = predicates.order[0];
      const dir = predicates.order[1];
      rows = rows.slice().sort((a, b) => (a[key] > b[key] ? 1 : a[key] < b[key] ? -1 : 0) * dir);
    }
    return new ResultSet(rows.map(row => ({...row})));
  }
  querySql(sql) {
    if (/SELECT c\.id FROM chapters c LEFT JOIN doc_paragraphs/.test(sql)) {
      const withParagraphs = new Set(this.tables.get('doc_paragraphs').map(row => row.doc_id));
      const rows = this.tables.get('chapters')
        .filter(row => !withParagraphs.has(row.id))
        .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
        .map(row => ({id: row.id}));
      return new ResultSet(rows);
    }
    throw new Error('Unsupported SQL in paragraph migration double: ' + sql);
  }
  beginTransaction() {
    const shadow = new StoreDouble(this.failState);
    for (const name of TABLE_NAMES) {
      shadow.tables.set(name, this.tables.get(name).map(row => ({...row})));
    }
    shadow.nextRunId = this.nextRunId;
    const source = this;
    const tx = {
      insert(table, value) { return shadow.insert(table, value); },
      update(value, predicates) { return shadow.update(value, predicates); },
      delete(predicates) { return shadow.delete(predicates); },
      commit() {
        source.tables = shadow.tables;
        source.nextRunId = shadow.nextRunId;
        source.activeTx = null;
      },
      rollback() { source.activeTx = null; }
    };
    this.activeTx = tx;
    return tx;
  }
}

let store = new StoreDouble();
let failState = store.failState;
const context = vm.createContext({
  console: { log() {}, warn() {}, error() {} },
  Logger: { info() {}, warn() {}, error() {} },
  relationalStore: { RdbPredicates: Predicates },
  IdGenerator: { generate() { return 'generated-id'; } },
  LibId: { ALL: 0, FAV: 1, INSP: 2, TRASH: 3 },
  dbHelper: {
    getStore() { return store; },
    beginTransaction() { return store.beginTransaction(); }
  }
});

function load(file) {
  vm.runInContext(strip(read(file)), context, { filename: file });
}
for (const file of [
  'model/Chapter', 'utils/TextLimit',
  'editor/flowtext/model/EditorTypes', 'editor/flowtext/model/FormatCodec', 'editor/model/DocumentModel',
  'database/BaseDao', 'database/ChapterDao', 'database/MetaDao', 'database/ParagraphDao',
  'repository/ParagraphRepository', 'repository/DocumentSession', 'repository/ChapterRepository',
  'repository/ParagraphMigration'
]) load(file + '.ets');

const api = vm.runInContext('({ ParagraphMigration, ParagraphRepository, ChapterRepository, ' +
  'ChapterDao, MetaDao, documentSession, FormatCodec, FormatRun, project })', context);

let pass = 0;
async function check(name, action) {
  try {
    await action();
    pass++;
    console.log('PASS ' + name);
  } catch (error) {
    console.error('FAIL ' + name + ' :: ' + error.message);
    process.exitCode = 1;
  }
}

function reset() {
  store = new StoreDouble();
  failState = store.failState;
  context.dbHelper = {
    getStore() { return store; },
    beginTransaction() { return store.beginTransaction(); }
  };
}

function seedChapter(id, title, content, runsJson = '') {
  store.insert('chapters', {
    id, title, content, format: 'txt', format_runs: runsJson,
    sort_order: 0, word_count: 0, caret_offset: 0,
    is_fav: 0, is_inspiration: 0, is_trash: 0, created_at: 1, updated_at: 1
  });
}

function headingRuns(text) {
  // 第一段设为 H1，并在第二段前四个字加粗；用于验证“段落种类进表、行内样式进 runs”。
  const first = text.indexOf('\n');
  const runs = [new api.FormatRun(0, first, false, false, 1, 0)];
  if (text.length > first + 1) {
    const start = first + 1;
    runs.push(new api.FormatRun(start, Math.min(start + 2, text.length), true, false, 0, 0));
  }
  return api.FormatCodec.encode(runs);
}

(async () => {
  reset();
  const text = '第一章\n正文内容';
  seedChapter('d1', '第一篇', text, headingRuns(text));
  seedChapter('d2', '空篇', '');

  const migration = new api.ParagraphMigration();
  await check('首次迁移补齐所有缺段落侧车的文稿', async () => {
    const migrated = await migration.runIfNeeded();
    assert.equal(migrated, 2);
    const d1 = store.rows('doc_paragraphs').filter(row => row.doc_id === 'd1');
    assert.deepEqual(d1.map(row => [row.para_id, row.ordinal, row.kind, row.text]),
      [['p1', 0, 1, '第一章'], ['p2', 1, 0, '正文内容']]);
    assert.equal(store.rows('doc_runs').length, 1);
    assert.deepEqual(store.rows('doc_runs').map(row => [row.para_id, row.start_off, row.end_off, row.bold]),
      [['p2', 0, 2, 1]]);
  });

  await check('空文稿也有一行空段，且内容不被改写', async () => {
    const d2 = store.rows('doc_paragraphs').filter(row => row.doc_id === 'd2');
    assert.equal(d2.length, 1);
    assert.equal(d2[0].para_id, 'p1');
    assert.equal(d2[0].text, '');
    assert.equal(store.rows('chapters').find(row => row.id === 'd2').content, '');
  });

  await check('迁移完成后写 schema_meta 标记', async () => {
    const meta = new api.MetaDao();
    assert.equal(await meta.get('paragraph_v1'), 'done');
  });

  await check('重复运行不重复写段落', async () => {
    const before = store.rows('doc_paragraphs').length;
    assert.equal(await migration.runIfNeeded(), 0);
    assert.equal(store.rows('doc_paragraphs').length, before);
  });

  await check('迁移后新增的文稿在下次启动被补齐（自愈）', async () => {
    seedChapter('d3', '后加', '后来的一篇');
    assert.equal(await migration.runIfNeeded(), 1);
    assert.equal(store.rows('doc_paragraphs').filter(row => row.doc_id === 'd3').length, 1);
    assert.equal(await migration.runIfNeeded(), 0);
  });

  await check('Repository 读回模型后投影与原文一致', async () => {
    const repo = new api.ParagraphRepository();
    const model = await repo.loadDocument('d1', '第一篇');
    assert.ok(model !== null);
    const projection = api.project(model);
    assert.equal(projection.text, text);
    const runs = JSON.parse(JSON.stringify(api.FormatCodec.decode(projection.runsJson)
      .map(run => [run.startOffset, run.endOffset, run.heading, run.bold])));
    assert.deepEqual(runs, [[0, 3, 1, false], [4, 6, 0, true]]);
  });

  await check('单篇写入失败会回滚，不留下半截段落', async () => {
    seedChapter('d4', '会失败', '这一篇写不进去');
    failState.docId = 'd4';
    await assert.rejects(migration.runIfNeeded(), /simulated paragraph insert failure/);
    assert.equal(store.rows('doc_paragraphs').filter(row => row.doc_id === 'd4').length, 0);
    failState.docId = '';
    assert.equal(await migration.runIfNeeded(), 1);
    assert.equal(store.rows('doc_paragraphs').filter(row => row.doc_id === 'd4').length, 1);
  });

  // ===== P5 写通 + 读路径（ChapterRepository） =====
  function paragraphRows(docId) {
    return store.rows('doc_paragraphs').filter(row => row.doc_id === docId)
      .slice().sort((a, b) => a.ordinal - b.ordinal);
  }
  const h1Runs = api.FormatCodec.encode([new api.FormatRun(0, 3, false, false, 1, 0)]);
  const repo = new api.ChapterRepository();

  await check('打开文稿优先读段落侧车投影', async () => {
    paragraphRows('d1')[0].kind = 1;
    const loaded = await repo.loadOne('d1');
    assert.equal(loaded.content, text);
    assert.match(loaded.formatRuns, /0,3,0,0,1,0/);
  });

  await check('保存改一段：章节与侧车同事务更新，id 不动', async () => {
    await repo.saveDraft('d1', '第一章\n正文改了', 0, h1Runs);
    assert.equal(store.rows('chapters').find(row => row.id === 'd1').content, '第一章\n正文改了');
    assert.deepEqual(paragraphRows('d1').map(row => row.para_id), ['p1', 'p2']);
    assert.deepEqual(paragraphRows('d1').map(row => row.text), ['第一章', '正文改了']);
  });

  await check('保存插入一段：旧 id 保留，新段拿新 id', async () => {
    await repo.saveDraft('d1', '第一章\n新段\n正文改了', 0, h1Runs);
    const rows = paragraphRows('d1');
    assert.deepEqual(rows.map(row => row.text), ['第一章', '新段', '正文改了']);
    assert.equal(rows[0].para_id, 'p1');
    assert.equal(rows[2].para_id, 'p2');
    assert.ok(rows[1].para_id !== 'p1' && rows[1].para_id !== 'p2');
    assert.deepEqual(rows.map(row => row.ordinal), [0, 0.5, 1]);
  });

  await check('保存删除一段：消失段与 runs 一起清理', async () => {
    await repo.saveDraft('d1', '第一章\n正文改了', 0, h1Runs);
    assert.deepEqual(paragraphRows('d1').map(row => row.para_id), ['p1', 'p2']);
    assert.equal(store.rows('doc_paragraphs').filter(row => row.doc_id === 'd1').length, 2);
  });

  await check('保存分裂一段：左段保留 id，右段新建', async () => {
    await repo.saveDraft('d1', '第一章\n正文\n改了', 0, h1Runs);
    const rows = paragraphRows('d1');
    assert.deepEqual(rows.map(row => row.text), ['第一章', '正文', '改了']);
    assert.equal(rows[1].para_id, 'p2');
    assert.ok(rows[2].para_id !== 'p2');
  });

  await check('保存合并两段：保留左段 id', async () => {
    await repo.saveDraft('d1', '第一章\n正文改了', 0, h1Runs);
    assert.deepEqual(paragraphRows('d1').map(row => row.para_id), ['p1', 'p2']);
  });

  await check('updateContent 也维护侧车', async () => {
    await repo.updateContent('d1', '全新正文');
    assert.equal(store.rows('chapters').find(row => row.id === 'd1').content, '全新正文');
    assert.deepEqual(paragraphRows('d1').map(row => row.text), ['全新正文']);
  });

  await check('侧车写入失败时章节更新一并回滚', async () => {
    failState.updateTable = 'doc_paragraphs';
    await assert.rejects(repo.saveDraft('d1', '回滚测试', 0, ''), /simulated doc_paragraphs update failure/);
    assert.equal(store.rows('chapters').find(row => row.id === 'd1').content, '全新正文');
    assert.deepEqual(paragraphRows('d1').map(row => row.text), ['全新正文']);
    failState.updateTable = '';
    await repo.saveDraft('d1', '回滚后写入', 0, '');
    assert.equal(store.rows('chapters').find(row => row.id === 'd1').content, '回滚后写入');
  });

  await check('打开后保存复用会话模型，不再读整篇侧车', async () => {
    seedChapter('d5', '缓存', 'A\nB');
    await repo.loadOne('d5');
    assert.equal(api.documentSession.has('d5'), true);
    const before = store.paragraphQueries;
    await repo.saveDraft('d5', 'A\nB2', 0, '');
    assert.equal(store.paragraphQueries, before, 'cached open doc must not reload paragraphs');
    assert.deepEqual(paragraphRows('d5').map(row => row.text), ['A', 'B2']);
    api.documentSession.evict('d5');
    await repo.saveDraft('d5', 'A\nB3', 0, '');
    assert.ok(store.paragraphQueries > before, 'after evict the next save reloads the sidecar');
    assert.deepEqual(paragraphRows('d5').map(row => row.text), ['A', 'B3']);
  });

  console.log('Paragraph migration regression: ' + pass + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
