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
    if (sql.startsWith('SELECT id, book_id')) {
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
  'constants/DesignTokens', 'utils/TextLimit', 'utils/IdGenerator', 'utils/TimeUtil',
  'database/BaseDao', 'database/BookDao', 'database/ChapterDao', 'database/CharacterDao',
  'database/WorldSettingDao', 'database/InspirationDao', 'database/RelationshipDao',
  'repository/BookRepository', 'repository/ChapterRepository', 'repository/MaterialRepository', 'repository/RelationshipRepository',
  'store/Repos', 'store/StoreModels', 'store/EditorStore', 'store/ProjectStore', 'store/MaterialStore', 'store/RelationStore', 'store/AppStores'
]) load(file + '.ets');
const api = vm.runInContext('({AppStores, EditorStore, OpenDoc, SaveState, ChapterFormat, BookMode, LibId, MAX_CONTENT_BYTES, runInTransaction, chapterRepo})', context);
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
  console.log('Data regression: ' + checks + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
