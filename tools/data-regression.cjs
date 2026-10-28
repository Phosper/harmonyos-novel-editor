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
  close() { this.closed = true; }
}
class StoreDouble {
  constructor() {
    this.tables = new Map(['books', 'chapters', 'characters', 'world_settings', 'inspirations', 'relationships']
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
    const all = [...this.tables.get('chapters').values()];
    let rows;
    if (sql.startsWith('SELECT title FROM chapters WHERE is_trash = 0 AND book_id = ?')) {
      rows = all.filter(ch => !ch.is_trash && ch.book_id === args[0]).map(ch => ({title: ch.title}));
    } else if (sql.startsWith('SELECT id, book_id')) {
      rows = all.filter(ch => ch.is_trash === args[0] && (args.length < 2 || ch.book_id === args[1]) &&
        (!sql.includes('is_fav = 1') || ch.is_fav === 1) && (!sql.includes('is_inspiration = 1') || ch.is_inspiration === 1));
    } else if (sql.includes('c_all')) {
      const scoped = all.filter(ch => ch.book_id === args[0]);
      rows = [{c_all: scoped.filter(ch => !ch.is_trash).length, c_fav: scoped.filter(ch => !ch.is_trash && ch.is_fav).length,
        c_insp: scoped.filter(ch => !ch.is_trash && ch.is_inspiration).length, c_trash: scoped.filter(ch => ch.is_trash).length}];
    } else if (sql.includes('GROUP BY book_id')) {
      const counts = new Map();
      for (const ch of all.filter(ch => !ch.is_trash)) counts.set(ch.book_id, (counts.get(ch.book_id) || 0) + 1);
      rows = [...counts].map(([book_id, c]) => ({book_id, c}));
    } else if (sql.startsWith('SELECT COUNT(*) AS c, COALESCE(MAX(sort_order), -1) AS m')) {
      const scoped = all.filter(ch => !ch.is_trash && ch.book_id === args[0]);
      rows = [{c: scoped.length, m: scoped.length > 0 ? Math.max(...scoped.map(ch => ch.sort_order)) : -1}];
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

let store = new StoreDouble(), timerId = 0, clockOffset = 0;
const timers = new Map();
const context = vm.createContext({
  console, Logger: {info() {}, warn() {}, error() {}},
  Date: class extends Date { static now() { return Date.now() + clockOffset; } },
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
  'constants/DesignTokens', 'editor/flowtext/model/EditorTypes', 'editor/flowtext/model/FormatCodec',
  'utils/TextLimit', 'utils/IdGenerator', 'utils/TimeUtil', 'utils/ImportService',
  'database/BaseDao', 'database/BookDao', 'database/ChapterDao', 'database/CharacterDao',
  'database/WorldSettingDao', 'database/InspirationDao', 'database/RelationshipDao',
  'repository/BookRepository', 'repository/ChapterRepository', 'repository/MaterialRepository', 'repository/RelationshipRepository',
  'store/Repos', 'store/StoreModels', 'store/EditorStore', 'store/ProjectStore', 'store/MaterialStore', 'store/RelationStore', 'store/AppStores'
]) load(file + '.ets');
const api = vm.runInContext('({AppStores, EditorStore, OpenDoc, HistoryEntry, SaveState, ChapterFormat, BookMode, LibId, MAX_CONTENT_BYTES, MAX_HISTORY_BYTES, MAX_HISTORY, runInTransaction, chapterRepo, ImportService, ImportKind, FormatCodec, ParagraphKind})', context);
function chapter(id = 'a', bookId = 'book-a', content = 'previous saved text') {
  return {id, book_id: bookId, title: 'Chapter ' + id, content, format: 'txt', format_runs: '', sort_order: 0,
    word_count: content.length, caret_offset: 0, is_fav: 0, is_inspiration: 0, is_trash: 0, created_at: 1, updated_at: 1};
}
function fixture() {
  store = new StoreDouble(); timers.clear(); clockOffset = 0;
  api.ImportService.pickAndRead = async () => [];
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
function importedFile(fileName, text, kind = api.ImportKind.TEXT) {
  return {fileName, text, kind, uri: 'file:///' + fileName,
    format: kind === api.ImportKind.MD ? api.ChapterFormat.MD : api.ChapterFormat.TXT};
}
function rejectImportedContent(content) {
  // Fail either an atomic insert or the old create-empty-then-update path.
  store.onInsert = async (table, value) => {
    if (table === 'chapters' && value.content === content) throw new Error('disk full');
  };
  store.onUpdate = async value => {
    if (value.content === content) throw new Error('disk full');
  };
}
let checks = 0;
async function check(name, run) { await run(); checks++; console.log('PASS ' + name); }
function editStep(editor, text, runs = '', caret = text.length) {
  clockOffset += 700; // Separate user transactions, beyond the store's 600 ms typing merge window.
  editor.setEditorState(text, runs, caret);
}
function historyEntries(editor) { return [...editor.undoStack, ...editor.redoStack]; }
function assertHistoryBudget(editor) {
  const entries = historyEntries(editor);
  const bytes = entries.reduce((sum, entry) => sum + entry.estimatedBytes, 0);
  assert.equal(editor.historyBytes, bytes, 'incremental accounting matches every retained snapshot');
  assert.ok(entries.length <= api.MAX_HISTORY, 'undo and redo share the count ceiling');
  assert.ok(bytes <= api.MAX_HISTORY_BYTES || entries.length === 1,
    'only one oversized recovery point may exceed the shared byte budget');
}

(async () => {
  await check('rename keeps the captured document target when another tab is active', async () => {
    const {app, doc} = fixture(); const other = new api.OpenDoc('b', 'Other', api.ChapterFormat.TXT, '', 'B', 0);
    app.editor.openDocs.push(other); app.editor.activeId = 'b'; let reloads = 0, syncs = 0;
    app.project.reloadChapters = async () => { reloads++; }; app.syncSelection = () => syncs++;
    await app.renameChapter('a', '  Renamed A  ');
    assert.equal(store.get('chapters', 'a').title, 'Renamed A'); assert.equal(doc.title, 'Renamed A');
    assert.equal(other.title, 'Other'); assert.equal(reloads, 1); assert.equal(syncs, 1);
  });
  await check('late rename persistence and refresh cannot update the replacement project', async () => {
    for (const stage of ['persist', 'refresh']) {
      const {app} = fixture(); const entered = deferred(), resume = deferred(); let reloads = 0, syncs = 0;
      if (stage === 'persist') store.onUpdate = async () => { entered.resolve(); await resume.promise; };
      app.project.reloadChapters = async () => { reloads++; if (stage === 'refresh') { entered.resolve(); await resume.promise; } };
      app.syncSelection = () => syncs++;
      const pending = app.renameChapter('a', 'Renamed A'); await entered.promise;
      app.project.currentBookId = 'book-b'; const other = new api.OpenDoc('b', 'Other project', api.ChapterFormat.TXT, '', 'B', 0);
      app.editor.openDocs = [other]; app.editor.activeId = 'b'; resume.resolve(); await pending;
      assert.equal(store.get('chapters', 'a').title, 'Renamed A'); assert.equal(other.title, 'Other project');
      assert.equal(reloads, stage === 'persist' ? 0 : 1); assert.equal(syncs, 0);
    }
  });
  await check('history estimates UTF-16 text and formatting without encoding or copying snapshots', () => {
    const entry = new api.HistoryEntry('doc', '中😀a', '中😀a'.length, '[{"bold":true}]');
    assert.equal(entry.estimatedBytes, ('doc'.length + '中😀a'.length + '[{"bold":true}]'.length) * 2 + 128);
  });
  await check('history version notifies real edits, undo, redo and forks while empty operations stay silent', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    assert.equal(editor.historyVersion, 0);
    editor.undo(); editor.redo(); editor.discard('missing');
    editor.setEditorState(doc.draft, doc.runsJson, doc.caret);
    assert.equal(editor.historyVersion, 0);
    editStep(editor, 'A1'); let version = editor.historyVersion;
    assert.ok(version > 0); assert.equal(editor.canUndo, true);
    editor.setEditorState('A1 merged typing', '', 3);
    assert.equal(editor.historyVersion, version, 'typing merged into one recovery point does not change history');
    editStep(editor, 'A2'); assert.ok(editor.historyVersion > version); version = editor.historyVersion;
    editor.undo(); assert.ok(editor.historyVersion > version); version = editor.historyVersion;
    assert.equal(doc.draft, 'A1 merged typing'); assert.equal(editor.canRedo, true);
    editor.redo(); assert.ok(editor.historyVersion > version); version = editor.historyVersion;
    assert.equal(doc.draft, 'A2'); assert.equal(editor.canRedo, false);
    editor.redo(); assert.equal(editor.historyVersion, version);
    editor.undo(); version = editor.historyVersion;
    editor.setEditorState('A branch', '', 2);
    assert.ok(editor.historyVersion > version); assert.equal(editor.canRedo, false);
    assertHistoryBudget(editor);
  });
  await check('history version covers pruning and document drops without changing close or cross-document history', async () => {
    const {app} = fixture(); const editor = app.editor;
    const other = new api.OpenDoc('b', 'B', api.ChapterFormat.TXT, '', 'B original', 0);
    editor.openDocs.push(other); store.seed('chapters', chapter('b'));
    for (let i = 0; i <= api.MAX_HISTORY; i++) {
      const version = editor.historyVersion;
      editStep(editor, 'A' + i);
      assert.ok(editor.historyVersion > version, 'an append must notify even when capacity pruning keeps the count equal');
      assertHistoryBudget(editor);
    }
    let version = editor.historyVersion;
    await editor.activate('b'); assert.equal(editor.historyVersion, version);
    editStep(editor, 'B1'); editor.undo(); version = editor.historyVersion;
    const bHistory = historyEntries(editor).filter(entry => entry.docId === 'b');
    await editor.close('a');
    assert.equal(editor.historyVersion, version, 'closing a tab retains its recovery points');
    editor.discard('a'); assert.ok(editor.historyVersion > version); version = editor.historyVersion;
    assert.deepEqual(historyEntries(editor).filter(entry => entry.docId === 'b'), bHistory);
    assert.ok(historyEntries(editor).every(entry => entry.docId === 'b')); assertHistoryBudget(editor);
    editor.discard('a'); assert.equal(editor.historyVersion, version);
    editor.reset(); assert.ok(editor.historyVersion > version); version = editor.historyVersion;
    assert.equal(editor.canUndo, false); assert.equal(editor.canRedo, false); assertHistoryBudget(editor);
    editor.reset(); editor.undo(); editor.redo(); editor.discard('b');
    assert.equal(editor.historyVersion, version);
  });
  await check('long formatted documents keep bounded history and the latest transaction remains reversible', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    const body = '文'.repeat(350000), formatting = '格式'.repeat(140000);
    let beforeText, beforeRuns, beforeCaret;
    for (let i = 0; i < 40; i++) {
      beforeText = doc.draft; beforeRuns = doc.runsJson; beforeCaret = doc.caret;
      editStep(editor, body + i, formatting + i, i);
      assertHistoryBudget(editor);
    }
    assert.ok(editor.undoStack.length < 20, 'byte budget trims before the snapshot count limit');
    const latestText = doc.draft, latestRuns = doc.runsJson, latestCaret = doc.caret;
    editor.undo(); assertHistoryBudget(editor);
    assert.equal(doc.draft, beforeText); assert.equal(doc.runsJson, beforeRuns); assert.equal(doc.caret, beforeCaret);
    editor.redo(); assertHistoryBudget(editor);
    assert.equal(doc.draft, latestText); assert.equal(doc.runsJson, latestRuns); assert.equal(doc.caret, latestCaret);
    assert.equal(doc.dirty, true);
  });
  await check('undo and redo share one budget while preserving cross-document isolation and redo order', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    const other = new api.OpenDoc('b', 'B', api.ChapterFormat.TXT, '', 'B original', 0);
    editor.openDocs.push(other);
    const body = '文'.repeat(300000);
    for (let i = 0; i < 18; i++) editStep(editor, body + 'A' + i);
    for (let i = 0; i < 5; i++) { editor.undo(); assertHistoryBudget(editor); }
    const aText = doc.draft;
    editor.activeId = 'b';
    for (let i = 0; i < 15; i++) { editStep(editor, body + 'B' + i); assertHistoryBudget(editor); }
    assert.equal(doc.draft, aText);
    for (let i = 14; i > 5; i--) {
      editor.undo(); assert.equal(other.draft, body + 'B' + (i - 1)); assertHistoryBudget(editor);
    }
    editor.activeId = 'a';
    const redo = editor.redoStack.filter(entry => entry.docId === 'a').map(entry => entry.text).reverse();
    assert.equal(redo.length, 5, 'recent A redo steps survive while the older A undo steps are pruned');
    for (const expected of redo) { editor.redo(); assert.equal(doc.draft, expected); assertHistoryBudget(editor); }
    assert.equal(other.draft, body + 'B5');
  });
  await check('the shared count limit applies during undo and retains the nearest available user steps', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    for (let i = 1; i <= 160; i++) editStep(editor, 'step ' + i);
    assert.equal(editor.undoStack.length, api.MAX_HISTORY); assertHistoryBudget(editor);
    for (let i = 159; i >= 100; i--) {
      editor.undo(); assert.equal(doc.draft, 'step ' + i); assertHistoryBudget(editor);
    }
    assert.equal(historyEntries(editor).length, api.MAX_HISTORY);
    for (let i = 101; i <= 160; i++) {
      editor.redo(); assert.equal(doc.draft, 'step ' + i); assertHistoryBudget(editor);
    }
  });
  await check('a single oversized recovery point is retained and a later small edit releases it', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    const huge = 'x'.repeat(api.MAX_HISTORY_BYTES / 2 + 1);
    doc.draft = huge;
    editStep(editor, 'small'); assertHistoryBudget(editor);
    assert.equal(historyEntries(editor).length, 1); assert.ok(editor.historyBytes > api.MAX_HISTORY_BYTES);
    editor.undo(); assert.equal(doc.draft, huge); assertHistoryBudget(editor);
    editor.redo(); assert.equal(doc.draft, 'small'); assertHistoryBudget(editor);
    editStep(editor, 'new small'); assertHistoryBudget(editor);
    assert.equal(historyEntries(editor).length, 1); assert.ok(editor.historyBytes < 1024);
    editor.undo(); assert.equal(doc.draft, 'small');
  });
  await check('new edit branches release only the active document redo and keep undo recovery boundaries', () => {
    const {app, doc} = fixture(); const editor = app.editor;
    const other = new api.OpenDoc('b', 'B', api.ChapterFormat.TXT, '', 'B original', 0);
    editor.openDocs.push(other);
    editStep(editor, 'A1'); editStep(editor, 'A2'); editor.undo();
    editor.activeId = 'b'; editStep(editor, 'B1'); editor.undo();
    editor.activeId = 'a';
    // No clock advance: the first edit after undo must still establish its own recovery point.
    editor.setEditorState('A branch', 'format branch', 2); assertHistoryBudget(editor);
    assert.equal(editor.redoStack.filter(entry => entry.docId === 'a').length, 0);
    assert.equal(editor.redoStack.filter(entry => entry.docId === 'b').length, 1);
    editor.undo(); assert.equal(doc.draft, 'A1'); assertHistoryBudget(editor);
    editor.redo(); assert.equal(doc.draft, 'A branch'); assert.equal(doc.runsJson, 'format branch');
    editor.setEditorState('after redo branch', '', 1); editor.undo();
    assert.equal(doc.draft, 'A branch'); assertHistoryBudget(editor);
    editor.activeId = 'b'; editor.redo(); assert.equal(other.draft, 'B1'); assertHistoryBudget(editor);
  });
  await check('switching, discarding and resetting documents keep history accounting exact', async () => {
    const {app} = fixture(); const editor = app.editor;
    const other = new api.OpenDoc('b', 'B', api.ChapterFormat.TXT, '', 'B original', 0);
    editor.openDocs.push(other); store.seed('chapters', chapter('b'));
    editStep(editor, 'A1'); editStep(editor, 'A2'); editor.undo();
    const beforeSwitch = editor.historyBytes;
    await editor.activate('b'); assert.equal(editor.historyBytes, beforeSwitch);
    editStep(editor, 'B1'); editStep(editor, 'B2'); editor.undo(); assertHistoryBudget(editor);
    editor.discard('a'); assert.ok(historyEntries(editor).every(entry => entry.docId === 'b')); assertHistoryBudget(editor);
    editor.discard('a'); assertHistoryBudget(editor);
    editor.reset(); assert.equal(editor.historyBytes, 0); assert.equal(historyEntries(editor).length, 0);
    assert.equal(editor.canUndo, false); assert.equal(editor.canRedo, false);
    await editor.openChapter({id: 'c', title: 'C', format: api.ChapterFormat.TXT, content: 'C original', caretOffset: 0});
    editStep(editor, 'C1'); editor.undo(); assert.equal(editor.content, 'C original'); assertHistoryBudget(editor);
  });
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
  await check('a delayed chapter creation cannot open its original project chapter inside the replacement project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('chapters', chapter('b', 'book-b', 'Book B content'));
    const entered = deferred(), resume = deferred();
    store.onInsert = async (table, value) => {
      if (table === 'chapters' && value.title === 'Created in A') { entered.resolve(); await resume.promise; }
    };
    const creating = app.createChapter('Created in A'); await entered.promise;
    await app.selectBook('book-b'); await app.project.reloadChapters(); await app.openChapter('b');
    resume.resolve(); const created = await creating;
    assert.equal(store.get('chapters', created.id).book_id, 'book-a');
    assert.equal(app.project.currentBookId, 'book-b'); assert.equal(app.editor.activeId, 'b');
    assert.deepEqual(copy(app.editor.openDocs.map(ch => ch.id)), ['b']);
    assert.equal(app.project.docItems.find(item => item.id === 'b').selected, true);
  });
  await check('a late entry point cannot open a foreign project chapter in the current project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('chapters', chapter('b', 'book-b', 'Book B content'));
    await app.selectBook('book-b'); await app.project.reloadChapters(); await app.openChapter('b');
    await app.openChapter('a');
    assert.equal(app.project.currentBookId, 'book-b'); assert.equal(app.editor.activeId, 'b');
    assert.deepEqual(copy(app.editor.openDocs.map(ch => ch.id)), ['b']);
    assert.equal(app.project.docItems.find(item => item.id === 'b').selected, true);
  });
  await check('a delayed new chapter cannot steal focus from a newer document open in the same project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('chapters', chapter('other', 'book-a', 'Other content'));
    await app.project.reloadChapters();
    const entered = deferred(), resume = deferred();
    store.onInsert = async (table, value) => {
      if (table === 'chapters' && value.title === 'Created slowly') { entered.resolve(); await resume.promise; }
    };
    const creating = app.createChapter('Created slowly'); await entered.promise;
    await app.openChapter('other'); resume.resolve(); const created = await creating;
    assert.ok(store.get('chapters', created.id)); assert.equal(app.editor.activeId, 'other');
    assert.ok(!app.editor.openDocs.some(ch => ch.id === created.id));
    assert.ok(app.project.docItems.some(item => item.id === created.id), 'the newly persisted chapter must still appear in the current project list');
    assert.equal(app.project.docItems.find(item => item.id === 'other').selected, true);
  });
  await check('mixed text and backup imports keep every ordinary file in the initial project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    api.ImportService.pickAndRead = async () => [
      importedFile('Before.txt', 'First import'),
      importedFile('Restored.json', JSON.stringify({app: 'Weaver', book: {name: 'Restored', mode: 'professional'}}), api.ImportKind.BACKUP),
      importedFile('After.md', 'Second import', api.ImportKind.MD)
    ];
    const result = await app.importFiles();
    const rows = [...store.tables.get('chapters').values()].filter(ch => ['Before', 'After'].includes(ch.title));
    assert.equal(rows.length, 2);
    assert.deepEqual(rows.map(ch => ch.book_id), ['book-a', 'book-a']);
    assert.equal(rows.find(ch => ch.title === 'After').format, api.ChapterFormat.MD);
    const restored = [...store.tables.get('books').values()].find(book => book.name === 'Restored（导入）');
    assert.ok(restored); assert.ok(rows.every(ch => ch.book_id !== restored.id));
    assert.match(result, /导入\s*2\s*篇文稿/); assert.match(result, /恢复\s*1\s*个备份项目/);
  });
  await check('an import captures its target before the picker returns and a project switch occurs', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    const entered = deferred(), resume = deferred();
    api.ImportService.pickAndRead = async () => { entered.resolve(); await resume.promise; return [importedFile('Picked.txt', 'Picked content')]; };
    const importing = app.importFiles(); await entered.promise;
    await app.selectBook('book-b'); resume.resolve();
    const result = await importing;
    const imported = [...store.tables.get('chapters').values()].find(ch => ch.title === 'Picked');
    assert.equal(app.project.currentBookId, 'book-b'); assert.equal(imported.book_id, 'book-a');
    assert.equal(imported.content, 'Picked content'); assert.equal(imported.word_count, 'Picked content'.length);
    assert.match(result, /导入\s*1\s*篇文稿/);
  });
  await check('a failed ordinary import cannot leave an empty chapter behind', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    api.ImportService.pickAndRead = async () => [importedFile('Rejected.txt', 'Rejected content')];
    rejectImportedContent('Rejected content');
    let result = '';
    try { result = await app.importFiles(); } catch {}
    assert.ok(![...store.tables.get('chapters').values()].some(ch => ch.title === 'Rejected'), 'failed import must not persist an empty shell');
    assert.equal(store.tables.get('chapters').size, 1);
    assert.match(result, /(?:失败\s*1\s*个|1\s*个[^，]*失败)/);
  });
  await check('ordinary import failures are isolated and later files still commit with an accurate summary', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    api.ImportService.pickAndRead = async () => [
      importedFile('First.txt', 'First committed'), importedFile('Rejected.txt', 'Rejected content'),
      importedFile('Last.txt', 'Last committed')
    ];
    rejectImportedContent('Rejected content');
    let result = '';
    try { result = await app.importFiles(); } catch {}
    const rows = [...store.tables.get('chapters').values()];
    assert.equal(rows.find(ch => ch.title === 'First').content, 'First committed');
    assert.equal(rows.find(ch => ch.title === 'Last')?.content, 'Last committed', 'a failed middle file must not abort later imports');
    assert.ok(!rows.some(ch => ch.title === 'Rejected'));
    assert.match(result, /导入\s*2\s*篇文稿/); assert.match(result, /(?:失败\s*1\s*个|1\s*个[^，]*失败)/);
  });
  await check('a refresh failure after importing still reports already committed files as successful', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    api.ImportService.pickAndRead = async () => [importedFile('Committed.txt', 'Committed before refresh')];
    app.project.reloadChapters = async () => { throw new Error('list refresh unavailable'); };
    let result = '', failure;
    try { result = await app.importFiles(); } catch (error) { failure = error; }
    assert.equal([...store.tables.get('chapters').values()].find(ch => ch.title === 'Committed').content, 'Committed before refresh');
    assert.equal(failure, undefined, 'a later list failure must not report persisted content as an import failure');
    assert.match(result, /导入\s*1\s*篇文稿/);
  });
  await check('draft previews update stable visible rows without rewriting list projections or saved chapters', async () => {
    const {app} = fixture(); await app.project.reloadChapters();
    const items = app.project.docItems, item = items[0], model = app.project.chapters[0];
    const beforeModel = copy(model), beforeSaved = copy(store.get('chapters', 'a')), beforeRoutes = store.routes.length;
    app.editor.setEditorState('  实时\n\t预览正文  ', '', 3, 'a');
    app.project.updateDocPreview('a', '新标题', app.editor.content, 7);
    assert.equal(app.project.docItems, items); assert.equal(app.project.docItems[0], item);
    assert.equal(item.title, '新标题'); assert.equal(item.subTitle, '实时 预览正文');
    assert.equal(item.wordCount, 7); assert.equal(item.badge, '7 字');
    assert.equal(app.project.chapters[0], model); assert.deepEqual(copy(model), beforeModel);
    assert.deepEqual(copy(store.get('chapters', 'a')), beforeSaved); assert.equal(store.routes.length, beforeRoutes);
    assert.equal(app.editor.activeDoc.dirty, true);
  });
  await check('draft previews accept the current snapshots after real undo and redo operations', async () => {
    const {app} = fixture(); await app.project.reloadChapters();
    const item = app.project.docItems[0], initialText = app.editor.content;
    const publish = () => app.project.updateDocPreview(app.editor.activeId, app.editor.title, app.editor.content, app.editor.wordCount);
    editStep(app.editor, '新的草稿'); publish(); assert.equal(item.subTitle, '新的草稿');
    const initialRev = app.editor.contentRev;
    app.editor.undo(); publish();
    assert.ok(app.editor.contentRev > initialRev); assert.equal(item.subTitle, initialText);
    app.editor.redo(); publish();
    assert.equal(item.subTitle, '新的草稿'); assert.equal(item.wordCount, app.editor.wordCount);
    assert.equal(app.project.docItems[0], item); assert.equal(store.get('chapters', 'a').content, 'previous saved text');
  });
  await check('metadata reloads retain every open unsaved draft preview without writing its body', async () => {
    for (const action of ['favourite', 'inspiration', 'format']) {
      const {app, doc} = fixture();
      store.seed('chapters', chapter('second', 'book-a', 'Second saved body'));
      const other = new api.OpenDoc('second', 'Second draft title', api.ChapterFormat.TXT, '', '另一个草稿😀', 0);
      other.dirty = true; app.editor.openDocs.push(other);
      await app.project.reloadChapters();
      editStep(app.editor, '  未保存\n草稿😀  ');
      app.project.updateDocPreview('a', doc.title, doc.draft, app.editor.wordCount);
      const item = app.project.docItems.find(row => row.id === 'a');
      if (action === 'favourite') await app.toggleFav('a');
      if (action === 'inspiration') await app.toggleInspiration('a');
      if (action === 'format') await app.setChapterFormat(api.ChapterFormat.MD);
      assert.equal(item.subTitle, '未保存 草稿😀', action + ' must keep the visible draft');
      assert.equal(item.wordCount, app.editor.wordCount, action + ' must keep the draft count');
      assert.equal(item.badge, app.editor.wordCount + ' 字');
      assert.equal(app.project.docItems.find(row => row.id === 'a'), item);
      const second = app.project.docItems.find(row => row.id === 'second');
      assert.equal(second.title, other.title); assert.equal(second.subTitle, other.draft);
      assert.equal(second.wordCount, 6);
      assert.equal(store.get('chapters', 'a').content, 'previous saved text');
      assert.equal(store.get('chapters', 'second').content, 'Second saved body');
      assert.equal(doc.dirty, true); assert.equal(other.dirty, true);
      assert.equal(app.project.chapters.find(row => row.id === 'a').content, 'previous saved text');
    }
  });
  await check('opening a clean document preserves the list modification time', async () => {
    const {app} = fixture(); app.editor.reset();
    await app.project.reloadChapters();
    const item = app.project.docItems[0], modified = item.modified;
    await app.openChapter('a');
    assert.equal(app.editor.activeDoc.dirty, false);
    assert.equal(item.modified, modified, 'opening a saved chapter is not a new edit');
    assert.equal(item.subTitle, 'previous saved text');
    assert.equal(item.selected, true);
  });
  await check('a late format write never refreshes or overlays the replacement project', async () => {
    const {app, doc} = fixture();
    await app.project.reloadChapters();
    const entered = deferred(), resume = deferred();
    store.onUpdate = async values => { if (values.format === 'md') { entered.resolve(); await resume.promise; } };
    const pending = app.setChapterFormat(api.ChapterFormat.MD); await entered.promise;
    store.seed('chapters', chapter('b', 'book-b', 'B saved body'));
    app.project.setCurrentBook('book-b'); app.editor.reset();
    await app.project.reloadChapters(); await app.openChapter('b');
    editStep(app.editor, 'B 的新草稿');
    app.project.updateDocPreview('b', app.editor.title, app.editor.content, app.editor.wordCount);
    const item = app.project.docItems[0], before = copy(item);
    let reloads = 0; const reload = app.project.reloadChapters.bind(app.project);
    app.project.reloadChapters = async () => { reloads++; await reload(); };
    resume.resolve(); await pending;
    assert.equal(store.get('chapters', 'a').format, 'md', 'the captured write still belongs to its original chapter');
    assert.equal(app.editor.activeId, 'b'); assert.equal(app.editor.format, api.ChapterFormat.TXT);
    assert.equal(doc.format, api.ChapterFormat.TXT, 'detached old editor state is not republished');
    assert.equal(reloads, 0); assert.deepEqual(copy(item), before);
    assert.equal(store.get('chapters', 'b').content, 'B saved body');
  });
  await check('draft previews reject unknown ids and visible rows whose project ownership does not match', async () => {
    const {app} = fixture(); await app.project.reloadChapters();
    const item = app.project.docItems[0], before = copy(item);
    app.project.updateDocPreview('unknown', '错误标题', '错误正文', 99);
    assert.deepEqual(copy(item), before);
    app.project.chapters[0].bookId = 'book-b';
    app.project.updateDocPreview('a', '错误项目', '错误正文', 99);
    assert.deepEqual(copy(item), before);
  });
  await check('late preview callbacks cannot update another project after the user switches', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('chapters', chapter('b', 'book-b', 'B original'));
    await app.selectBook('book-b'); await app.project.reloadChapters();
    const item = app.project.docItems[0], before = copy(item);
    app.project.updateDocPreview('a', '旧项目迟到标题', '旧项目迟到正文', 999);
    assert.equal(app.project.currentBookId, 'book-b'); assert.equal(app.project.docItems.length, 1);
    assert.equal(app.project.docItems[0], item); assert.deepEqual(copy(item), before);
    assert.equal(store.get('chapters', 'a').content, 'previous saved text');
  });
  await check('empty draft previews clear old counts and show the existing empty-document prompt', async () => {
    const {app} = fixture(); await app.project.reloadChapters();
    const item = app.project.docItems[0];
    app.project.updateDocPreview('a', '空文稿', '', 0);
    assert.equal(item.title, '空文稿'); assert.equal(item.subTitle, '空白文稿，点击开始写作…');
    assert.equal(item.wordCount, 0); assert.equal(item.badge, '');
    app.project.updateDocPreview('a', '空文稿', '\n\t\r  ', 0);
    assert.equal(item.subTitle, '空白文稿，点击开始写作…');
  });
  await check('draft summaries retain leading-whitespace content and cap long previews without changing normalization', async () => {
    const {app} = fixture(); await app.project.reloadChapters();
    const item = app.project.docItems[0];
    app.project.updateDocPreview('a', '长前导空白', ' '.repeat(400) + '真正正文', 4);
    assert.equal(item.subTitle, '真正正文');
    app.project.updateDocPreview('a', '长文', '前缀'.repeat(100000), 200000);
    assert.equal(item.subTitle, '前缀'.repeat(36) + '…');
    app.project.updateDocPreview('a', '末尾空白', 'a'.repeat(72) + '\t\n ', 72);
    assert.equal(item.subTitle, 'a'.repeat(72));
    app.project.updateDocPreview('a', '空白归一化', '  A\r\n\tB\u00a0C  ', 3);
    assert.equal(item.subTitle, 'A B C');
  });
  await check('six-field list and todo indentation survives history, autosave and backup snapshots', async () => {
    const {app, doc} = fixture();
    const original = '0,6,0,0,4,2;6,12,0,0,5,1';
    const changed = '0,6,1,0,4,1;6,12,0,0,6,2';
    const originalRuns = api.FormatCodec.decode(original);
    assert.equal(originalRuns[0].heading, api.ParagraphKind.BULLET); assert.equal(originalRuns[0].indent, 2);
    assert.equal(originalRuns[1].heading, api.ParagraphKind.TODO); assert.equal(originalRuns[1].indent, 1);
    assert.equal(api.FormatCodec.encode(originalRuns), original);
    doc.draft = '嵌套列表项\n待办事项内容'; doc.runsJson = original;
    editStep(app.editor, doc.draft, changed, 8);
    app.editor.undo(); assert.equal(doc.runsJson, original);
    assert.equal(doc.draft, '嵌套列表项\n待办事项内容');
    app.editor.redo(); assert.equal(doc.runsJson, changed);
    await app.editor.flushActive();
    assert.equal(store.get('chapters', 'a').format_runs, changed);
    assert.equal(doc.dirty, false);
    const backup = await app.exportBackupData();
    assert.equal(backup.chapters.find(ch => ch.id === 'a').formatRuns, changed);
    assertHistoryBudget(app.editor);
  });
  await check('a delayed restore cannot refresh or select the replacement project', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    store.seed('chapters', {...chapter('trashed'), is_trash: 1});
    const entered = deferred(), resume = deferred();
    store.onUpdate = async (values, predicate) => {
      if (predicate.matches(store.get('chapters', 'trashed'))) { entered.resolve(); await resume.promise; }
    };
    const pending = app.restoreChapter('trashed'); await entered.promise;
    store.seed('chapters', chapter('b', 'book-b', 'B body'));
    app.project.setCurrentBook('book-b'); app.editor.reset();
    await app.project.reloadChapters(); await app.openChapter('b');
    let reloads = 0; const reload = app.project.reloadChapters.bind(app.project);
    app.project.reloadChapters = async () => { reloads++; await reload(); };
    resume.resolve(); await pending;
    assert.equal(store.get('chapters', 'trashed').is_trash, 0);
    assert.equal(reloads, 0); assert.equal(app.editor.activeId, 'b');
    assert.deepEqual(copy(app.project.docItems.map(row => row.id)), ['b']);
    assert.equal(app.project.docItems[0].selected, true);
  });
  await check('a format update cannot republish an editor session closed and reopened during the write', async () => {
    const {app, doc} = fixture(); doc.dirty = false;
    const entered = deferred(), resume = deferred();
    store.onUpdate = async values => { if (values.format === 'md') { entered.resolve(); await resume.promise; } };
    const pending = app.setChapterFormat(api.ChapterFormat.MD); await entered.promise;
    await app.closeTab('a'); await app.openChapter('a');
    const replacement = app.editor.activeDoc;
    assert.notEqual(replacement, doc);
    let reloads = 0; app.project.reloadChapters = async () => { reloads++; };
    resume.resolve(); await pending;
    assert.equal(store.get('chapters', 'a').format, 'md');
    assert.equal(doc.format, api.ChapterFormat.TXT);
    assert.equal(replacement.format, api.ChapterFormat.TXT);
    assert.equal(reloads, 0);
  });
  console.log('Data regression: ' + checks + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
