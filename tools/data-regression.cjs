// Node 24+. Runs the actual ArkTS data/store classes with controlled ArkData and timer doubles.
// This verifies asynchronous persistence behavior; a HarmonyOS SDK build/device run remains separate.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return {promise, resolve}; };
const copy = value => JSON.parse(JSON.stringify(value));

class Predicates {
  constructor(table) { this.table = table; this.conditions = []; }
  equalTo(key, value) { this.conditions.push(row => row[key] === value); return this; }
  lessThan(key, value) { this.conditions.push(row => row[key] < value); return this; }
  orderByAsc(key) { this.order = [key, 1]; return this; }
  orderByDesc(key) { this.order = [key, -1]; return this; }
  matches(row) { return this.conditions.every(test => test(row)); }
}
class ResultSet {
  constructor(rows) { this.rows = rows; this.index = -1; this.columns = Object.keys(rows[0] || {}); this.closed = false; }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { return ++this.index < this.rows.length; }
  getColumnIndex(key) { return this.columns.indexOf(key); }
  getString(index) { return this.rows[this.index][this.columns[index]] ?? ''; }
  getLong(index) { return Number(this.rows[this.index][this.columns[index]] ?? 0); }
  getDouble(index) { return Number(this.rows[this.index][this.columns[index]] ?? 0); }
  close() { this.closed = true; }
}
class StoreDouble {
  constructor() {
    this.tables = new Map(['books', 'chapters', 'characters', 'world_settings', 'inspirations', 'relationships',
      'topics', 'topic_evidence', 'canvases', 'canvas_placements', 'canvas_links']
      .map(name => [name, new Map()]));
    this.routes = []; this.activeTx = null;
  }
  seed(table, row) { this.tables.get(table).set(row.id, {...row}); }
  get(table, id) { return this.tables.get(table).get(id); }
  checkWrite() { if (this.activeTx) throw new Error('14800024: database locked'); }
  async insert(table, value) {
    this.routes.push('store.insert:' + table); this.checkWrite();
    if (this.onInsert) await this.onInsert(table, value);
    this.validate(table, value); this.seed(table, value); return 1;
  }
  validate(table, value) {
    if (table === 'characters' && typeof value.name !== 'string') throw new Error('invalid character name');
  }
  async update(value, predicates) {
    this.routes.push('store.update:' + predicates.table); this.checkWrite();
    if (this.onUpdate) await this.onUpdate(value, predicates);
    let count = 0;
    for (const row of this.tables.get(predicates.table).values()) {
      if (predicates.matches(row)) { Object.assign(row, value); count++; }
    }
    return count;
  }
  async delete(predicates) {
    this.routes.push('store.delete:' + predicates.table); this.checkWrite();
    let count = 0;
    for (const [id, row] of this.tables.get(predicates.table)) {
      if (predicates.matches(row)) { this.tables.get(predicates.table).delete(id); count++; }
    }
    return count;
  }
  async query(predicates) {
    const rows = [...this.tables.get(predicates.table).values()].filter(row => predicates.matches(row)).map(row => ({...row}));
    if (predicates.order) rows.sort((a, b) => (a[predicates.order[0]] > b[predicates.order[0]] ? 1 : -1) * predicates.order[1]);
    if (this.onQuery) await this.onQuery(predicates);
    return new ResultSet(rows);
  }
  async querySql(sql, args = []) {
    const canvasTable = ['topic_evidence', 'canvas_placements', 'canvas_links', 'topics', 'canvases']
      .find(name => sql.includes('FROM ' + name));
    if (canvasTable) {
      let rows = [...this.tables.get(canvasTable).values()];
      if (/topic_id IN \(/.test(sql)) rows = rows.filter(row => args.includes(row.topic_id));
      if (/canvas_id IN \(/.test(sql)) rows = rows.filter(row => args.includes(row.canvas_id));
      rows = rows.map(row => ({...row}));
      if (this.onQuerySql) await this.onQuerySql(sql, args);
      return new ResultSet(rows);
    }
    const all = [...this.tables.get('chapters').values()];
    let rows;
    if (sql.startsWith('SELECT id, book_id')) {
      rows = all.filter(ch => ch.is_trash === args[0] && (args.length < 2 || ch.book_id === args[1]) &&
        (!sql.includes('is_fav = 1') || ch.is_fav === 1) && (!sql.includes('is_inspiration = 1') || ch.is_inspiration === 1));
    } else if (sql.includes('c_all')) {
      // args 为空 = 跨项目全局计数（侧栏「文库」段）；有 args 时按书过滤
      const scoped = args.length === 0 ? all : all.filter(ch => ch.book_id === args[0]);
      rows = [{c_all: scoped.filter(ch => !ch.is_trash).length, c_fav: scoped.filter(ch => !ch.is_trash && ch.is_fav).length,
        c_insp: scoped.filter(ch => !ch.is_trash && ch.is_inspiration).length, c_trash: scoped.filter(ch => ch.is_trash).length}];
    } else if (sql.includes('GROUP BY book_id')) {
      const counts = new Map();
      for (const ch of all.filter(ch => !ch.is_trash)) counts.set(ch.book_id, (counts.get(ch.book_id) || 0) + 1);
      rows = [...counts].map(([book_id, c]) => ({book_id, c}));
    } else {
      throw new Error('Unsupported SQL in data regression double: ' + sql);
    }
    rows = rows.map(row => ({...row}));
    if (this.onQuerySql) await this.onQuerySql(sql, args);
    return new ResultSet(rows);
  }
  async beginTransaction() {
    this.checkWrite();
    const shadow = new StoreDouble();
    for (const [table, rows] of this.tables) for (const row of rows.values()) shadow.seed(table, row);
    const source = this;
    const tx = {
      async insert(table, value) {
        source.routes.push('tx.insert:' + table);
        const result = await shadow.insert(table, value);
        if (source.onTxInsert) await source.onTxInsert(table, value);
        return result;
      },
      async update(value, predicates) { source.routes.push('tx.update:' + predicates.table); return shadow.update(value, predicates); },
      async delete(predicates) { source.routes.push('tx.delete:' + predicates.table); return shadow.delete(predicates); },
      async commit() { source.tables = shadow.tables; source.activeTx = null; },
      async rollback() { source.activeTx = null; }
    };
    this.activeTx = tx; return tx;
  }
}

let store = new StoreDouble(), timerId = 0;
const timers = new Map();
const context = vm.createContext({
  console, Logger: {info() {}, warn() {}, error() {}},
  relationalStore: {RdbPredicates: Predicates},
  dbHelper: {getStore() { return store; }, beginTransaction() { return store.beginTransaction(); }},
  UiStore: class { constructor() { this.mode = 'professional'; this.view = 0; } },
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; }, clearTimeout(id) { timers.delete(id); },
  setInterval(fn) { timers.set(++timerId, fn); return timerId; }, clearInterval(id) { timers.delete(id); }
});
function load(file) {
  const source = fs.readFileSync(path.join(root, file), 'utf8')
    .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+/g, '').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
  vm.runInContext(stripTypeScriptTypes(source, {mode: 'transform'}), context, {filename: file});
}
for (const file of [
  'model/Book', 'model/Chapter', 'model/Character', 'model/WorldSetting', 'model/Inspiration', 'model/Relationship',
  'model/CanvasTypes', 'model/CanvasStoreModels',
  'constants/DesignTokens', 'utils/TextLimit', 'utils/IdGenerator', 'utils/TimeUtil',
  'database/BaseDao', 'database/BookDao', 'database/ChapterDao', 'database/CharacterDao',
  'database/WorldSettingDao', 'database/InspirationDao', 'database/RelationshipDao',
  'database/CanvasBoardDao', 'database/CanvasCardDao', 'database/CanvasEvidenceDao',
  'database/CanvasPlacementDao', 'database/CanvasLinkDao',
  'repository/BookRepository', 'repository/ChapterRepository', 'repository/MaterialRepository', 'repository/RelationshipRepository',
  'repository/CanvasRepository',
  'store/Repos', 'store/StoreModels', 'store/EditorStore', 'store/ProjectStore', 'store/MaterialStore', 'store/RelationStore',
  'store/CanvasStore', 'store/AppStores'
]) load(file + '.ets');
const api = vm.runInContext('({AppStores, EditorStore, OpenDoc, SaveState, ChapterFormat, BookMode, LibId, MAX_CONTENT_BYTES,' +
  ' runInTransaction, chapterRepo, canvasRepo, CanvasCardKind, CanvasBoardScope, CanvasEvidenceKind, CanvasLinkKind,' +
  ' canvasFindPlacement})', context);
function chapter(id = 'a', bookId = 'book-a', content = 'previous saved text') {
  return {id, book_id: bookId, title: 'Chapter ' + id, content, format: 'txt', format_runs: '', sort_order: 0,
    word_count: content.length, caret_offset: 0, is_fav: 0, is_inspiration: 0, is_trash: 0, created_at: 1, updated_at: 1};
}
function fixture() {
  store = new StoreDouble(); timers.clear();
  const app = new api.AppStores();
  app.project.currentBookId = 'book-a';
  app.project.books = [{id: 'book-a', name: 'Book A', mode: api.BookMode.PROFESSIONAL}, {id: 'book-b', name: 'Book B', mode: api.BookMode.PROFESSIONAL}];
  store.seed('books', {id: 'book-a', name: 'Book A', mode: 'professional', created_at: 1, updated_at: 1});
  store.seed('books', {id: 'book-b', name: 'Book B', mode: 'professional', created_at: 1, updated_at: 1});
  store.seed('chapters', chapter());
  // Loading visible panes is unrelated to persistence boundaries under test.
  app.reloadAll = async () => {};
  const doc = new api.OpenDoc('a', 'Chapter a', api.ChapterFormat.TXT, '', 'latest user text', 3, '[]');
  doc.dirty = true; doc.rev = 1; doc.active = true;
  app.editor.openDocs = [doc]; app.editor.activeId = doc.id;
  return {app, doc};
}

// ===== 思路板（画布）夹具 =====
function boardRow(id, bookId, scope, title, sortOrder = 0) {
  return {id, scope, book_id: bookId, title, pan_x: 12.5, pan_y: -8.25, zoom: 0.75,
    sort_order: sortOrder, created_at: 1, updated_at: 1};
}
function topicRow(id, bookId, title, kind = 'concept', docId = '', createdAt = 1) {
  return {id, book_id: bookId, kind, title, aliases: '别名', tags: 'tag',
    my_summary: '一句话', doc_id: docId, created_at: createdAt, updated_at: createdAt};
}
function placementRow(id, canvasId, topicId, parentId = '', ord = 0, x = 0, y = 0, z = 0) {
  return {id, canvas_id: canvasId, topic_id: topicId, parent_id: parentId, ord, x, y, z,
    collapsed: 0, style: ''};
}
function evidenceRow(id, topicId, kind, docId, createdAt, startOff = 0, endOff = 0) {
  return {id, topic_id: topicId, kind, doc_id: docId, para_index: 0, start_off: startOff,
    end_off: endOff, fingerprint: 'fp', quote_text: '原文', user_text: '', source_label: '出处',
    created_at: createdAt};
}
function canvasFixture() {
  const {app, doc} = fixture();
  app.canvas.setBookScope(app.project.currentBookId);
  store.seed('canvases', boardRow('cv1', 'book-a', 'course', 'Course board', 0));
  store.seed('canvases', boardRow('cv2', '', 'free', 'Free board', 1));
  store.seed('topics', topicRow('t1', 'book-a', '均势', 'concept', '', 1));
  store.seed('topics', topicRow('t2', 'book-a', '写作卡', 'writing', '', 2));
  store.seed('topics', topicRow('t3', '', '跨书卡', 'concept', '', 3));
  store.seed('canvas_placements', placementRow('pc1', 'cv1', 't1', '', 0, 12, 0));
  store.seed('canvas_placements', placementRow('pc2', 'cv1', 't2', 'pc1', 0, 40, 60));
  store.seed('canvas_placements', placementRow('pc3', 'cv2', 't2', '', 0, 0, 0));
  store.seed('canvas_links', {id: 'lk1', canvas_id: 'cv1', from_topic_id: 't1',
    to_topic_id: 't2', kind: 'premise', label: '', created_at: 1});
  store.seed('topic_evidence', evidenceRow('ev1', 't1', 'quote', 'ch-a', 1, 0, 4));
  store.seed('topic_evidence', evidenceRow('ev2', 't1', 'note', '', 2));
  return {app, doc};
}
function evidenceOfTopic(topicId) {
  return [...store.tables.get('topic_evidence').values()].filter(row => row.topic_id === topicId);
}

let checks = 0;
async function check(name, run) { await run(); checks++; console.log('PASS ' + name); }

(async () => {
  await check('restore rollback cannot capture ordinary autosave, and the dirty draft retries afterward', async () => {
    const {app, doc} = fixture(); const entered = deferred(), resume = deferred();
    store.onTxInsert = async table => { if (table === 'books') { entered.resolve(); await resume.promise; } };
    const restoring = app.importBackupText(JSON.stringify({app: 'Weaver', characters: [{id: 'broken'}]}));
    await entered.promise;
    await app.editor.flushAll();
    assert.equal(doc.dirty, true); assert.equal(app.editor.saveState, api.SaveState.FAILED);
    assert.equal(store.get('chapters', 'a').content, 'previous saved text');
    assert.ok(!store.routes.includes('tx.update:chapters'));
    resume.resolve(); assert.equal(await restoring, '');
    assert.equal(store.tables.get('books').size, 2);
    await app.editor.flushAll(); assert.equal(store.get('chapters', 'a').content, 'latest user text'); assert.equal(doc.dirty, false);
  });
  await check('revision guard retains edits entered while a save is pending', async () => {
    const {app, doc} = fixture(); const entered = deferred(), resume = deferred();
    store.onUpdate = async () => { entered.resolve(); await resume.promise; };
    const saving = app.editor.flushActive(); await entered.promise;
    app.editor.setEditorState('newer input', '[1]', 5); resume.resolve(); await saving;
    assert.equal(doc.dirty, true); assert.equal(store.get('chapters', 'a').content, 'latest user text');
    store.onUpdate = null; await app.editor.flushAll(); assert.equal(doc.dirty, false);
    assert.equal(store.get('chapters', 'a').content, 'newer input'); assert.equal(store.get('chapters', 'a').format_runs, '[1]');
  });
  await check('closing a tab queues behind an in-flight autosave and persists its newer draft', async () => {
    const {app} = fixture(); const entered = deferred(), resume = deferred(); let writes = 0;
    store.onUpdate = async () => { if (++writes === 1) { entered.resolve(); await resume.promise; } };
    const saving = app.editor.flushActive(); await entered.promise;
    app.editor.setEditorState('text before closing', '[2]', 9);
    const closing = app.closeTab('a'); await Promise.resolve(); await Promise.resolve(); assert.equal(writes, 1);
    resume.resolve(); await Promise.all([saving, closing]);
    assert.equal(writes, 2); assert.equal(store.get('chapters', 'a').content, 'text before closing'); assert.equal(app.editor.openDocs.length, 0);
  });
  await check('closing a tab rejects and retains text entered during that close save', async () => {
    const {app, doc} = fixture(); const entered = deferred(), resume = deferred();
    store.onUpdate = async () => { entered.resolve(); await resume.promise; };
    const closing = app.closeTab('a'); await entered.promise;
    app.editor.setEditorState('edit during close', '[3]', 7); resume.resolve();
    await assert.rejects(closing, /未保存/); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.draft, 'edit during close'); assert.equal(doc.dirty, true);
  });
  await check('failed project switch and failed deletion preserve the current draft', async () => {
    const {app, doc} = fixture(); store.onUpdate = async () => { throw new Error('disk full'); };
    await assert.rejects(app.selectBook('book-b'), /disk full/);
    assert.equal(app.project.currentBookId, 'book-a'); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.dirty, true);
    await assert.rejects(app.deleteBook('book-b'), /disk full/); assert.ok(store.get('books', 'book-b'));
    await app.editor.flushAll(); assert.equal(doc.dirty, true);
  });
  await check('oversized drafts survive both closing and project switching', async () => {
    const {app, doc} = fixture(); app.editor.setContent('x'.repeat(api.MAX_CONTENT_BYTES + 1));
    await assert.rejects(app.closeTab('a'), /超过/); await assert.rejects(app.selectBook('book-b'), /超过/);
    assert.equal(app.project.currentBookId, 'book-a'); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.dirty, true);
    assert.equal(app.editor.saveState, api.SaveState.TOO_LARGE);
  });
  await check('whole-book export includes dirty text, caret and formatting without truncating closed chapters', async () => {
    const {app, doc} = fixture(); store.seed('chapters', chapter('closed', 'book-a', '中'.repeat(900)));
    doc.title = 'Draft title'; doc.runsJson = 'format-snapshot';
    const chapters = await app.loadFullChapters(); const exported = chapters.find(ch => ch.id === 'a');
    assert.equal(exported.content, doc.draft); assert.equal(exported.title, 'Draft title'); assert.equal(exported.caretOffset, 3);
    assert.equal(exported.formatRuns, 'format-snapshot'); assert.equal(chapters.find(ch => ch.id === 'closed').content.length, 900);
    assert.equal(doc.dirty, true); assert.equal(store.get('chapters', 'a').content, 'previous saved text');
  });
  await check('backup captures one project and one draft snapshot even when the user switches during the query', async () => {
    const {app, doc} = fixture(); const entered = deferred(), resume = deferred();
    app.material.characters = [{id: 'character-a', bookId: 'book-a', name: 'A'}];
    app.relation.relationships = [{id: 'relation-a', bookId: 'book-a'}];
    store.seed('characters', {id: 'character-a', book_id: 'book-a', name: 'A'});
    store.seed('relationships', {id: 'relation-a', book_id: 'book-a'});
    store.onQuery = async predicates => { if (predicates.table === 'chapters') { entered.resolve(); await resume.promise; } };
    const exporting = app.exportBackupData(); await entered.promise;
    app.editor.setEditorState('later edit', 'later-format', 8);
    app.project.currentBookId = 'book-b'; app.editor.reset();
    app.material.characters = [{id: 'character-b', bookId: 'book-b', name: 'B'}]; app.relation.relationships = [];
    resume.resolve(); const payload = await exporting;
    assert.equal(payload.book.id, 'book-a'); assert.equal(payload.chapters[0].content, 'latest user text');
    assert.equal(payload.chapters[0].formatRuns, '[]'); assert.equal(payload.characters[0].id, 'character-a'); assert.equal(payload.relationships[0].id, 'relation-a');
    assert.equal(doc.draft, 'later edit');
  });
  await check('sidebar library counts and list cover every project, project view does not', async () => {
    const {app} = fixture();
    store.seed('chapters', chapter('b1', 'book-b', 'b one'));
    store.seed('chapters', chapter('b2', 'book-b', 'b two'));
    const trashed = chapter('t1', 'book-b', 'trash'); trashed.is_trash = 1;
    store.seed('chapters', trashed);
    const fav = chapter('a2', 'book-a', 'fav one'); fav.is_fav = 1;
    store.seed('chapters', fav);
    // 侧栏数字：跨项目合计（A 两篇有效 + B 两篇有效 + B 一篇废纸篓）
    await app.project.refreshCounts();
    assert.deepEqual(copy(app.project.libCounts), {all: 4, fav: 1, insp: 0, trash: 1});
    // 点文库 = 全局库：列表与计数同一作用域
    await app.setLibFilter(api.LibId.ALL);
    assert.equal(app.project.libraryScope, true);
    assert.equal(app.project.chapters.length, 4);
    assert.equal(app.project.chapters.every(ch => ch.isTrash === false), true);
    assert.equal(app.project.docItems.every(item => item.projectName !== ''), true,
      '全局文库要标出每篇所属项目');
    // 项目行计数仍是单项目口径
    const perBook = await api.chapterRepo.countActivePerBook();
    assert.equal(perBook.get('book-a'), 2);
    assert.equal(perBook.get('book-b'), 2);
    // 选中项目 = 回到项目内视图，列表只剩本书
    // （夹具把 reloadAll 打了桩，这里显式拉一次列表，避免把"没加载"当成"没数据"）
    await app.selectBook('book-b');
    assert.equal(app.project.libraryScope, false);
    await app.project.reloadChapters();
    assert.equal(app.project.chapters.length, 2);
    assert.equal(app.project.chapters.every(ch => ch.bookId === 'book-b'), true);
    assert.equal(app.project.docItems.every(item => item.projectName === ''), true);
  });
  await check('delayed chapter opens cannot reopen the previous project', async () => {
    const {app} = fixture(); app.editor.reset(); const entered = deferred(), resume = deferred();
    store.onQuery = async predicates => { if (predicates.table === 'chapters') { entered.resolve(); await resume.promise; } };
    const opening = app.openChapter('a'); await entered.promise;
    await app.selectBook('book-b'); resume.resolve(); await opening;
    assert.equal(app.project.currentBookId, 'book-b'); assert.equal(app.editor.openDocs.length, 0); assert.equal(app.editor.activeId, '');
  });
  await check('a newer chapter open supersedes an older slow query', async () => {
    const {app} = fixture(); app.editor.reset(); store.seed('chapters', chapter('b')); const entered = deferred(), resume = deferred();
    store.onQuery = async predicates => { if (predicates.matches(store.get('chapters', 'a'))) { entered.resolve(); await resume.promise; } };
    const older = app.openChapter('a'); await entered.promise; await app.openChapter('b'); resume.resolve(); await older;
    assert.equal(app.editor.activeId, 'b'); assert.equal(app.editor.openDocs.length, 1);
  });
  await check('reset cancels a pending tab activation', async () => {
    const {app} = fixture(); const entered = deferred(), resume = deferred();
    app.editor.openDocs.push(new api.OpenDoc('b', 'B', api.ChapterFormat.TXT, '', 'b', 0));
    store.onUpdate = async () => { entered.resolve(); await resume.promise; };
    const activating = app.editor.activate('b'); await entered.promise; app.editor.reset(); resume.resolve(); await activating;
    assert.equal(app.editor.activeId, ''); assert.equal(app.editor.openDocs.length, 0);
  });
  await check('a newer click on the current tab cancels an older open waiting for autosave', async () => {
    const {app} = fixture(); store.seed('chapters', chapter('b')); const entered = deferred(), resume = deferred();
    store.onUpdate = async () => { entered.resolve(); await resume.promise; };
    const opening = app.openChapter('b'); await entered.promise;
    await app.activateChapter('a'); assert.equal(app.editor.activeId, 'a');
    resume.resolve(); await opening; assert.equal(app.editor.activeId, 'a');
  });
  await check('a failed format update preserves the open document format', async () => {
    const {app, doc} = fixture(); app.project.reloadChapters = async () => {};
    store.onUpdate = async () => { throw new Error('format update failed'); };
    await assert.rejects(app.setChapterFormat(api.ChapterFormat.MD), /format update failed/);
    assert.equal(doc.format, api.ChapterFormat.TXT); assert.equal(store.get('chapters', 'a').format, 'txt');
  });
  await check('a successful format update reaches both the open document and export snapshot', async () => {
    const {app, doc} = fixture(); app.project.reloadChapters = async () => {};
    await app.setChapterFormat(api.ChapterFormat.MD);
    assert.equal(doc.format, api.ChapterFormat.MD); assert.equal(store.get('chapters', 'a').format, 'md');
    assert.equal((await app.loadFullChapters())[0].format, api.ChapterFormat.MD);
  });
  await check('backup restore preserves formatting and publishes the imported project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    const result = await app.importBackupText(JSON.stringify({app: 'Weaver', book: {name: 'Restored', mode: 'professional'}, chapters: [{
      id: 'original', title: 'Formatted', content: 'Restored text', format: 'md', formatRuns: '[{"bold":true}]',
      wordCount: 13, caretOffset: 4, createdAt: 1, updatedAt: 2, isFav: false, isInspiration: false, isTrash: false
    }]}));
    assert.equal(result, 'Restored（导入）'); const imported = [...store.tables.get('chapters').values()].find(ch => ch.title === 'Formatted');
    assert.equal(imported.format_runs, '[{"bold":true}]'); assert.equal(imported.format, 'md'); assert.equal(imported.caret_offset, 4);
    assert.equal(app.project.currentBookId, imported.book_id); assert.ok(app.project.books.some(book => book.id === imported.book_id));
  });
  await check('committed restore still reports success when an unsaved draft prevents switching', async () => {
    const {app, doc} = fixture(); store.onUpdate = async () => { throw new Error('disk full'); };
    const result = await app.importBackupText(JSON.stringify({app: 'Weaver', book: {name: 'Committed', mode: 'professional'}}));
    assert.match(result, /已恢复/); assert.equal(app.project.currentBookId, 'book-a'); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.dirty, true);
    assert.ok([...store.tables.get('books').values()].some(book => book.name === 'Committed（导入）'));
  });
  await check('project creation fails before inserting when the initial draft cannot be saved', async () => {
    const {app, doc} = fixture(); store.onUpdate = async () => { throw new Error('initial save failed'); };
    await assert.rejects(app.createBook('New project'), /initial save failed/);
    assert.equal(store.tables.get('books').size, 2); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.dirty, true);
    assert.ok(!app.project.books.some(book => book.name === 'New project'));
  });
  await check('a created project reports success once when a later dirty draft prevents switching', async () => {
    const {app, doc} = fixture();
    store.onInsert = async table => {
      if (table === 'books') {
        app.editor.setEditorState('new edit after creation preflight', '', 2);
        store.onUpdate = async () => { throw new Error('later save failed'); };
      }
    };
    assert.equal(await app.createBook('New project'), true);
    assert.equal([...store.tables.get('books').values()].filter(book => book.name === 'New project').length, 1);
    assert.ok(app.project.books.some(book => book.name === 'New project'));
    assert.ok(app.project.projects.some(book => book.name === 'New project'));
    assert.equal(app.project.currentBookId, 'book-a'); assert.equal(app.editor.openDocs[0], doc); assert.equal(doc.dirty, true);
  });
  await check('a committed project remains visible and reports success when the list reload fails', async () => {
    const {app} = fixture();
    store.onQuery = async predicates => { if (predicates.table === 'books') throw new Error('list reload failed'); };
    assert.equal(await app.createBook('Created before reload failure'), true);
    assert.equal(store.tables.get('books').size, 3);
    assert.ok(app.project.books.some(book => book.name === 'Created before reload failure'));
    assert.ok(app.project.projects.some(book => book.name === 'Created before reload failure'));
  });
  await check('an older project list query cannot overwrite a newer project or mix its backup materials', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    app.project.books.push({id: 'book-c', name: 'Book C', mode: api.BookMode.PROFESSIONAL});
    store.seed('chapters', chapter('b', 'book-b', 'Content B')); store.seed('chapters', chapter('c', 'book-c', 'Content C'));
    store.seed('characters', {id: 'char-b', book_id: 'book-b', name: 'Character B'});
    store.seed('characters', {id: 'char-c', book_id: 'book-c', name: 'Character C'});
    const entered = deferred(), resume = deferred();
    store.onQuerySql = async (sql, args) => { if (sql.startsWith('SELECT id, book_id') && args[1] === 'book-b') { entered.resolve(); await resume.promise; } };
    app.reloadAll = api.AppStores.prototype.reloadAll.bind(app);
    const older = app.selectBook('book-b'); await entered.promise; await app.selectBook('book-c'); resume.resolve(); await older;
    const backup = await app.exportBackupData();
    assert.equal(app.project.currentBookId, 'book-c'); assert.deepEqual(copy(app.project.chapters.map(ch => ch.bookId)), ['book-c']);
    assert.deepEqual(copy(app.material.characters.map(ch => ch.bookId)), ['book-c']);
    assert.equal(backup.book.id, 'book-c'); assert.equal(backup.chapters[0].bookId, 'book-c'); assert.equal(backup.characters[0].bookId, 'book-c');
  });
  await check('an older library query cannot overwrite a newer filter', async () => {
    const {app} = fixture(); const fav = chapter('fav'); fav.is_fav = 1; store.seed('chapters', fav);
    const entered = deferred(), resume = deferred();
    store.onQuerySql = async sql => { if (sql.startsWith('SELECT id, book_id') && !sql.includes('is_fav = 1')) { entered.resolve(); await resume.promise; } };
    const older = app.project.reloadChapters(); await entered.promise; await app.project.setLibFilter(api.LibId.FAV); resume.resolve(); await older;
    assert.equal(app.project.libFilter, api.LibId.FAV); assert.deepEqual(copy(app.project.chapters.map(ch => ch.id)), ['fav']);
  });
  await check('a backup during project loading queries the selected project rather than old visible material arrays', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    app.material.characters = [{id: 'char-a', bookId: 'book-a', name: 'A'}];
    app.relation.relationships = [{id: 'rel-a', bookId: 'book-a'}];
    store.seed('characters', {id: 'char-b', book_id: 'book-b', name: 'B'});
    store.seed('relationships', {id: 'rel-b', book_id: 'book-b'});
    const entered = deferred(), resume = deferred();
    store.onQuerySql = async (sql, args) => { if (sql.startsWith('SELECT id, book_id') && args[1] === 'book-b') { entered.resolve(); await resume.promise; } };
    app.reloadAll = api.AppStores.prototype.reloadAll.bind(app);
    const switching = app.selectBook('book-b'); await entered.promise;
    const backup = await app.exportBackupData(); resume.resolve(); await switching;
    assert.equal(backup.book.id, 'book-b'); assert.equal(backup.characters[0].id, 'char-b'); assert.equal(backup.relationships[0].id, 'rel-b');
  });
  await check('an older pending material load cannot replace a newer project material scope', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('characters', {id: 'char-a', book_id: 'book-a', name: 'A'});
    store.seed('characters', {id: 'char-b', book_id: 'book-b', name: 'B'});
    const entered = deferred(), resume = deferred();
    store.onQuery = async p => { if (p.table === 'characters' && p.matches(store.get('characters', 'char-a'))) { entered.resolve(); await resume.promise; } };
    const older = app.material.load('book-a'); await entered.promise;
    app.reloadAll = api.AppStores.prototype.reloadAll.bind(app); await app.selectBook('book-b'); resume.resolve(); await older;
    assert.deepEqual(copy(app.material.characters.map(ch => ch.id)), ['char-b']);
  });
  await check('an older pending relationship load cannot replace a newer project graph', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('relationships', {id: 'rel-a', book_id: 'book-a'}); store.seed('relationships', {id: 'rel-b', book_id: 'book-b'});
    const entered = deferred(), resume = deferred();
    store.onQuery = async p => { if (p.table === 'relationships' && p.matches(store.get('relationships', 'rel-a'))) { entered.resolve(); await resume.promise; } };
    const older = app.relation.load('book-a', []); await entered.promise;
    app.reloadAll = api.AppStores.prototype.reloadAll.bind(app); await app.selectBook('book-b'); resume.resolve(); await older;
    assert.deepEqual(copy(app.relation.relationships.map(r => r.id)), ['rel-b']);
  });
  await check('a committed restore remains visible and reports success after a project-list read failure', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.onQuery = async p => { if (p.table === 'books') throw new Error('book list unavailable'); };
    const result = await app.importBackupText(JSON.stringify({app: 'Weaver', book: {name: 'Restored despite reload', mode: 'professional'}}));
    assert.notEqual(result, ''); assert.match(result, /已恢复/); assert.equal(store.tables.get('books').size, 3);
    assert.ok(app.project.projects.some(p => p.name === 'Restored despite reload（导入）'));
  });
  await check('the first default project appears in the sidebar and is selected', async () => {
    store = new StoreDouble(); const app = new api.AppStores();
    await app.project.loadBooks(); await app.project.ensureCurrentBook(api.BookMode.PROFESSIONAL);
    assert.equal(app.project.books.length, 1); assert.equal(app.project.projects.length, 1);
    assert.equal(app.project.projects[0].id, app.project.currentBookId); assert.equal(app.project.projects[0].active, true);
  });
  await check('clicking the current project cancels an older project switch still waiting for a save', async () => {
    const {app, doc} = fixture(); const entered = deferred(), resume = deferred();
    store.onUpdate = async () => { entered.resolve(); await resume.promise; };
    const older = app.selectBook('book-b'); await entered.promise;
    await app.selectBook('book-a'); resume.resolve(); await older;
    assert.equal(app.project.currentBookId, 'book-a'); assert.equal(app.editor.openDocs[0], doc);
  });
  await check('deleting the final project publishes its automatically created replacement', async () => {
    const {app, doc} = fixture(); doc.dirty = false; store.tables.get('books').delete('book-b');
    app.project.books = app.project.books.filter(book => book.id === 'book-a');
    await app.deleteBook('book-a');
    assert.equal(app.project.books.length, 1); assert.equal(app.project.projects.length, 1);
    assert.notEqual(app.project.currentBookId, 'book-a'); assert.equal(app.project.projects[0].id, app.project.currentBookId);
    assert.equal(app.project.projects[0].active, true);
  });

  await check('canvas: load publishes boards, cards, placements, links, evidence and viewport', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    assert.equal(app.canvas.boards.length, 2);
    assert.equal(app.canvas.currentBoardId, 'cv1');
    assert.equal(app.canvas.loading, false);
    assert.deepEqual(copy(app.canvas.placements.map(p => p.cardId)), ['t1', 't2']);
    assert.equal(app.canvas.allPlacements.length, 3);
    assert.equal(app.canvas.links.length, 1);
    assert.equal(app.canvas.panX, 12.5); assert.equal(app.canvas.panY, -8.25); assert.equal(app.canvas.zoom, 0.75);
    assert.equal(app.canvas.cards.length, 3);
    assert.equal(app.canvas.evidenceCountOf('t1'), 2);
    assert.deepEqual(copy(app.canvas.evidenceOf('t1').map(e => e.kind)), ['quote', 'note']);
    assert.equal(app.canvas.cardOf('t2').kind, api.CanvasCardKind.WRITING);
    assert.equal(app.canvas.depthOf('t2'), 1);
    assert.deepEqual(copy(app.canvas.childrenOf('t1').map(p => p.cardId)), ['t2']);
    assert.deepEqual(copy(app.canvas.cardsOnBoard().map(c => c.id)), ['t1', 't2']);
    assert.deepEqual(copy(app.canvas.occurrences('t2')), ['Course board', 'Free board']);
    assert.equal(app.canvas.boardCardCount('cv2'), 1);
    assert.equal(app.canvas.canNest('t1', 't2'), false);
    assert.equal(app.canvas.canNest('t3', 't2'), true);
  });

  await check('canvas: createBoard and createCard persist, and duplicate titles are rejected per board', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    assert.equal(await app.canvas.createCard(api.CanvasCardKind.CONCEPT, '均势'), undefined);
    const fresh = await app.canvas.createCard(api.CanvasCardKind.CONCEPT, '无政府状态');
    assert.ok(fresh); assert.ok(store.get('topics', fresh.id));
    assert.equal(fresh.bookId, 'book-a');
    const free = await app.canvas.createBoard(api.CanvasBoardScope.FREE, '新自由板');
    assert.ok(free);
    const freeRow = store.get('canvases', free.id);
    assert.equal(freeRow.scope, 'free'); assert.equal(freeRow.book_id, ''); assert.equal(freeRow.zoom, 1);
    assert.equal(freeRow.sort_order, 2);
    assert.equal(app.canvas.currentBoardId, free.id);
    assert.equal(app.canvas.placements.length, 0);
    const course = await app.canvas.createBoard(api.CanvasBoardScope.COURSE, '新课程板');
    assert.equal(store.get('canvases', course.id).book_id, 'book-a');
    assert.equal(await app.canvas.createBoard(api.CanvasBoardScope.FREE, '   '), undefined);
  });

  await check('canvas: addPlacement appends ord/z and movePlacement saves the drop point', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.addPlacement('t3', 100.5, -20.25);
    const row = [...store.tables.get('canvas_placements').values()]
      .find(p => p.topic_id === 't3' && p.canvas_id === 'cv1');
    assert.ok(row);
    assert.equal(row.parent_id, ''); assert.equal(row.ord, 1); assert.equal(row.z, 1);
    assert.equal(row.x, 100.5); assert.equal(row.y, -20.25);
    await app.canvas.movePlacement('t3', 5, 6);
    assert.equal(row.x, 5); assert.equal(row.y, 6);
    app.canvas.panX = 30; app.canvas.panY = 40; app.canvas.zoom = 1.25;
    await app.canvas.saveViewport();
    const board = store.get('canvases', 'cv1');
    assert.equal(board.pan_x, 30); assert.equal(board.pan_y, 40); assert.equal(board.zoom, 1.25);
  });

  await check('canvas: attachCard blocks cycles, depth overflow and the current parent, then persists legal moves', async () => {
    const {app} = canvasFixture();
    store.tables.get('canvas_placements').clear();
    store.seed('topics', topicRow('tW', 'book-a', '论文壳', 'writing'));
    store.seed('topics', topicRow('tA', 'book-a', 'A'));
    store.seed('topics', topicRow('tB', 'book-a', 'B'));
    store.seed('topics', topicRow('tC', 'book-a', 'C'));
    store.seed('topics', topicRow('tD', 'book-a', 'D'));
    store.seed('canvas_placements', placementRow('pW', 'cv1', 'tW'));
    store.seed('canvas_placements', placementRow('pA', 'cv1', 'tA', 'pW', 0));
    store.seed('canvas_placements', placementRow('pB', 'cv1', 'tB', 'pA', 0));
    store.seed('canvas_placements', placementRow('pC', 'cv1', 'tC', 'pB', 0));
    store.seed('canvas_placements', placementRow('pD', 'cv1', 'tD', '', 1, 80, 90));
    await app.canvas.load();
    assert.equal(app.canvas.depthOf('tC'), 3);
    assert.equal(await app.canvas.attachCard('tA', 'tC'), false);
    assert.equal(await app.canvas.attachCard('tD', 'tC'), false);
    assert.equal(await app.canvas.attachCard('tA', 'tA'), false);
    assert.equal(store.get('canvas_placements', 'pA').parent_id, 'pW');
    assert.equal(await app.canvas.attachCard('tD', 'tA'), true);
    const moved = store.get('canvas_placements', 'pD');
    assert.equal(moved.parent_id, 'pA'); assert.equal(moved.ord, 1);
    assert.equal(moved.x, 80); assert.equal(moved.y, 90);
    assert.equal(await app.canvas.attachCard('tD', 'tA'), false);
    assert.equal(app.canvas.depthOf('tD'), 2);
  });

  await check('canvas: detachCard promotes to top level and reorderCard rewrites sibling ord', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.detachCard('t2');
    const detached = store.get('canvas_placements', 'pc2');
    assert.equal(detached.parent_id, ''); assert.equal(detached.ord, 1);
    assert.equal(detached.x, 40); assert.equal(detached.y, 60);
    await app.canvas.reorderCard('t2', -1);
    assert.deepEqual(copy(app.canvas.childrenOf('').map(p => p.cardId)), ['t2', 't1']);
    assert.equal(store.get('canvas_placements', 'pc2').ord, 0);
    assert.equal(store.get('canvas_placements', 'pc1').ord, 1);
    await app.canvas.reorderCard('t2', -1);
    assert.equal(store.get('canvas_placements', 'pc2').ord, 0);
    assert.deepEqual(copy(app.canvas.childrenOf('').map(p => p.cardId)), ['t2', 't1']);
  });

  await check('canvas: duplicate placements collapse on load (child wins) and detach clears the row', async () => {
    const {app} = canvasFixture();
    // 模拟历史并发/连点造成的第二条贴放：同一块板、同一张卡，但它是顶层
    store.seed('canvas_placements', placementRow('pc4', 'cv1', 't2', '', 1, 200, 200));
    await app.canvas.load();
    const rows = app.canvas.placements.filter(p => p.cardId === 't2');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].parentId, 't1');
    assert.equal(store.get('canvas_placements', 'pc4'), undefined);
    await app.canvas.detachCard('t2');
    assert.equal(store.get('canvas_placements', 'pc2').parent_id, '');
    assert.equal(app.canvas.childrenOf('t1').length, 0);
    assert.deepEqual(copy(app.canvas.childrenOf('').map(p => p.cardId)), ['t1', 't2']);
  });

  await check('canvas: deleteCard undo restores the card, its evidence and the board placements', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.deleteCard('t1');
    assert.equal(app.canvas.cardOf('t1'), undefined);
    assert.equal(store.get('topics', 't1'), undefined);
    await app.canvas.performUndo();
    assert.ok(app.canvas.cardOf('t1'));
    assert.ok(store.get('topic_evidence', 'ev1'));
    assert.ok(store.get('canvas_placements', 'pc1'));
    assert.equal(app.canvas.childrenOf('t1').map(p => p.cardId).join(','), 't2');
  });

  await check('canvas: removePlacement undo restores the placement and the child parent chain', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.removePlacement('t1');
    assert.equal(store.get('canvas_placements', 'pc1'), undefined);
    await app.canvas.performUndo();
    assert.ok(store.get('canvas_placements', 'pc1'));
    assert.equal(store.get('canvas_placements', 'pc2').parent_id, 'pc1');
    assert.equal(app.canvas.childrenOf('t1').map(p => p.cardId).join(','), 't2');
  });

  await check('canvas: duplicateCard copies kind/meta but not evidence', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    const before = app.canvas.evidenceOf('t1').length;
    const copy = await app.canvas.duplicateCard('t1');
    assert.ok(copy !== undefined);
    assert.notEqual(copy.id, 't1');
    assert.equal(copy.title, '均势 副本');
    assert.equal(copy.aliases, '别名');
    assert.equal(copy.tags, 'tag');
    assert.equal(copy.summary, '一句话');
    assert.equal(app.canvas.evidenceOf(copy.id).length, 0);
    assert.equal(app.canvas.evidenceOf('t1').length, before);
  });

  await check('canvas: addChildCard creates, places and attaches a chapter in one call', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    const before = app.canvas.childrenOf('t2').length;
    assert.equal(await app.canvas.addChildCard('t2', '第 1 章', 10, 20), true);
    const kids = app.canvas.childrenOf('t2');
    assert.equal(kids.length, before + 1);
    const created = app.canvas.cardOf(kids[kids.length - 1].cardId);
    assert.equal(created.title, '第 1 章');
    assert.equal(created.kind, 'concept');
  });

  await check('canvas: updateCard saves meta, rejects empty title, and rolls back on failure', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    assert.equal(await app.canvas.updateCard('t1', {
      title: ' 新标题 ', aliases: 'A', tags: 'x,y', summary: '一句话'
    }), true);
    const row = store.get('topics', 't1');
    assert.equal(row.title, '新标题');
    assert.equal(row.aliases, 'A');
    assert.equal(row.tags, 'x,y');
    assert.equal(row.my_summary, '一句话');
    assert.equal(await app.canvas.updateCard('t1', {title: '   '}), false);
    assert.equal(app.canvas.cardOf('t1').title, '新标题');
  });

  await check('canvas: updateEvidenceText edits only the body and keeps the source', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    const before = store.get('topic_evidence', 'ev1');
    assert.equal(await app.canvas.updateEvidenceText('ev1', '新的引文', ''), true);
    const after = store.get('topic_evidence', 'ev1');
    assert.equal(after.quote_text, '新的引文');
    assert.equal(after.doc_id, before.doc_id);
    assert.equal(after.start_off, before.start_off);
    assert.equal(after.fingerprint, before.fingerprint);
  });

  await check('canvas: deleteEvidence offers a 5s undo that restores the same id', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.deleteEvidence('ev2');
    assert.equal(store.get('topic_evidence', 'ev2'), undefined);
    assert.equal(app.canvas.undoLabel, '已删除素材');
    await app.canvas.performUndo();
    assert.ok(store.get('topic_evidence', 'ev2'));
    assert.equal(app.canvas.evidenceOf('t1').filter(ev => ev.id === 'ev2').length, 1);
  });

  await check('canvas: duplicate parent placements repoint children instead of orphaning them', async () => {
    const {app} = canvasFixture();
    store.seed('topics', topicRow('t5', 'book-a', '子卡', 'concept', '', 5));
    // t2 的第二条贴放（顶层）；子卡 pc6 恰好指向这条要被删的父
    store.seed('canvas_placements', placementRow('pc5', 'cv1', 't2', '', 1, 300, 300));
    store.seed('canvas_placements', placementRow('pc6', 'cv1', 't5', 'pc5', 0, 320, 320));
    await app.canvas.load();
    assert.equal(store.get('canvas_placements', 'pc5'), undefined);
    assert.equal(store.get('canvas_placements', 'pc6').parent_id, 'pc2');
    assert.deepEqual(copy(app.canvas.childrenOf('t2').map(p => p.cardId)), ['t5']);
  });

  await check('canvas: deleteCard clears every board, promotes children with spread positions, drops evidence and links', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.deleteCard('t1');
    assert.equal(store.get('topics', 't1'), undefined);
    assert.equal(store.get('canvas_placements', 'pc1'), undefined);
    assert.equal(evidenceOfTopic('t1').length, 0);
    assert.equal([...store.tables.get('canvas_links').values()].length, 0);
    const promoted = store.get('canvas_placements', 'pc2');
    assert.equal(promoted.parent_id, '');
    assert.equal(promoted.x, 52); assert.equal(promoted.y, 60);
    assert.deepEqual(copy(app.canvas.placements.map(p => p.cardId)), ['t2']);
    assert.equal(app.canvas.cardOf('t1'), undefined);
    assert.equal(app.canvas.evidenceCountOf('t1'), 0);
    assert.equal(app.canvas.occurrences('t1').length, 0);
    assert.equal(app.canvas.boardCardCount('cv2'), 1);
  });

  await check('canvas: removePlacement takes the card off only this board and promotes its children', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    await app.canvas.removePlacement('t1');
    assert.equal(store.get('canvas_placements', 'pc1'), undefined);
    const promoted = store.get('canvas_placements', 'pc2');
    assert.equal(promoted.parent_id, '');
    assert.equal(promoted.x, 52); assert.equal(promoted.y, 60);
    assert.ok(store.get('topics', 't1'));
    assert.deepEqual(copy(app.canvas.occurrences('t1')), []);
    assert.deepEqual(copy(app.canvas.placements.map(p => p.cardId)), ['t2']);
    assert.equal(app.canvas.evidenceCountOf('t1'), 2);
    assert.equal(store.get('canvas_placements', 'pc3').canvas_id, 'cv2');
  });

  await check('canvas: writes are serialized, so a queued detach lands after the in-flight attach', async () => {
    const {app} = canvasFixture();
    store.seed('topics', topicRow('t4', 'book-a', 'D'));
    store.seed('canvas_placements', placementRow('pc4', 'cv1', 't4', '', 1, 80, 90));
    await app.canvas.load();
    const entered = deferred(), resume = deferred();
    let writes = 0;
    store.onUpdate = async () => { if (++writes === 1) { entered.resolve(); await resume.promise; } };
    const attaching = app.canvas.attachCard('t4', 't1');
    await entered.promise;
    const detaching = app.canvas.detachCard('t4');
    await Promise.resolve(); await Promise.resolve();
    assert.equal(writes, 1);
    resume.resolve();
    assert.equal(await attaching, true);
    await detaching;
    assert.equal(writes, 2);
    assert.equal(store.get('canvas_placements', 'pc4').parent_id, '');
    assert.deepEqual(copy(app.canvas.childrenOf('').map(p => p.cardId)), ['t1', 't4']);
    store.onUpdate = null;
  });

  await check('canvas: a failed load reports an error and keeps the content already on screen', async () => {
    const {app} = canvasFixture();
    await app.canvas.load();
    const boardsBefore = app.canvas.boards.length;
    store.onQuery = async p => { if (p.table === 'canvases') throw new Error('read failed'); };
    await app.canvas.load();
    assert.match(app.canvas.error, /载入思路板失败/);
    assert.equal(app.canvas.boards.length, boardsBefore);
    assert.equal(app.canvas.placements.length, 2);
    assert.equal(app.canvas.loading, false);
    store.onQuery = null;
  });

  await check('canvas: backup v2 exports the five canvas tables of the project', async () => {
    const {app, doc} = canvasFixture();
    doc.dirty = false;
    store.seed('topics', topicRow('tCross', '', '跨书卡', 'concept', '', 4));
    store.seed('canvas_placements', placementRow('pcX', 'cv1', 'tCross', '', 2, 200, 200));
    const payload = await app.exportBackupData();
    assert.equal(payload.version, 2);
    assert.deepEqual(copy(payload.canvases.map(b => b.id)), ['cv1']);
    assert.equal(payload.canvasPlacements.length, 3);
    assert.equal(payload.canvasLinks.length, 1);
    assert.deepEqual(copy(payload.topics.map(t => t.id)), ['t1', 't2', 'tCross']);
    assert.equal(payload.topicEvidence.length, 2);
    assert.equal(payload.canvasPlacements[1].parentId, 'pc1');
  });

  await check('canvas: restore remaps topic/canvas/placement ids, the parent chain and chapterIdMap', async () => {
    const {app, doc} = fixture();
    doc.dirty = false;
    const backup = {
      app: 'Weaver', version: 2, book: {name: 'Restored', mode: 'professional'},
      chapters: [{id: 'ch-old', title: '初稿', content: '正文', format: 'txt', wordCount: 2,
        caretOffset: 0, createdAt: 1, updatedAt: 2, isFav: false, isInspiration: false, isTrash: false}],
      topics: [
        {id: 't-old', bookId: 'book-x', kind: 'writing', title: '论文壳', aliases: '', tags: '',
          summary: '', docId: 'ch-old', createdAt: 1, updatedAt: 1},
        {id: 't-child', bookId: 'book-x', kind: 'concept', title: '二、均势', aliases: 'a', tags: 'b',
          summary: 's', docId: '', createdAt: 1, updatedAt: 1}
      ],
      canvases: [{id: 'cv-old', scope: 'course', bookId: 'book-x', title: '白板', panX: 1.5, panY: 2.5,
        zoom: 0.5, sortOrder: 0, createdAt: 1, updatedAt: 1}],
      canvasPlacements: [
        {id: 'p-parent', canvasId: 'cv-old', cardId: 't-old', parentId: '', order: 0, x: 1, y: 1,
          z: 0, collapsed: false, style: ''},
        {id: 'p-child', canvasId: 'cv-old', cardId: 't-child', parentId: 'p-parent', order: 0, x: 2, y: 2,
          z: 0, collapsed: true, style: 'w'}
      ],
      canvasLinks: [{id: 'l-old', canvasId: 'cv-old', fromCardId: 't-old', toCardId: 't-child',
        kind: 'cause', label: '因为', createdAt: 1}],
      topicEvidence: [{id: 'e-old', cardId: 't-child', kind: 'quote', docId: 'ch-old', paraIndex: 1,
        startOff: 2, endOff: 5, fingerprint: 'fp', quoteText: '原文', userText: '', sourceLabel: '出处',
        createdAt: 1}]
    };
    const result = await app.importBackupText(JSON.stringify(backup));
    assert.match(result, /Restored/);
    const boards = [...store.tables.get('canvases').values()];
    assert.equal(boards.length, 1);
    assert.notEqual(boards[0].id, 'cv-old');
    assert.equal(boards[0].book_id, app.project.currentBookId);
    assert.equal(boards[0].pan_x, 1.5);
    const chapters = [...store.tables.get('chapters').values()];
    const chapter = chapters.find(ch => ch.title === '初稿');
    const topics = [...store.tables.get('topics').values()];
    const writing = topics.find(t => t.title === '论文壳');
    const child = topics.find(t => t.title === '二、均势');
    assert.notEqual(writing.id, 't-old');
    assert.equal(writing.doc_id, chapter.id);
    assert.equal(child.book_id, app.project.currentBookId);
    const placements = [...store.tables.get('canvas_placements').values()];
    const parent = placements.find(p => p.topic_id === writing.id);
    const nested = placements.find(p => p.topic_id === child.id);
    assert.equal(parent.parent_id, '');
    assert.notEqual(parent.id, 'p-parent');
    assert.equal(nested.parent_id, parent.id);
    assert.equal(nested.collapsed, 1);
    const evidence = [...store.tables.get('topic_evidence').values()];
    assert.equal(evidence.length, 1);
    assert.equal(evidence[0].topic_id, child.id);
    assert.equal(evidence[0].doc_id, chapter.id);
    const links = [...store.tables.get('canvas_links').values()];
    assert.equal(links.length, 1);
    assert.equal(links[0].from_topic_id, writing.id);
    assert.equal(links[0].to_topic_id, child.id);
    assert.equal(links[0].canvas_id, boards[0].id);
    assert.equal(links[0].kind, 'cause');
  });

  console.log('Data regression: ' + checks + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
