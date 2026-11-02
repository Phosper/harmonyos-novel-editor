// Node 24+. Exercise the production chapter repository/DAO with controlled write failures and delays.
// Database calls are doubled; the API 26 build and device checks remain separate.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

class Predicates {
  constructor(table) { this.table = table; this.conditions = []; }
  equalTo(column, value) { this.conditions.push(row => row[column] === value); return this; }
  matches(row) { return this.conditions.every(test => test(row)); }
}

class WriteStore {
  constructor() { this.rows = new Map(); this.snapshots = []; this.attempts = []; }
  async update(values, predicates) {
    assert.equal(predicates.table, 'chapters');
    this.attempts.push({ ...values });
    if (this.beforeUpdate) await this.beforeUpdate(values);
    let count = 0;
    for (const row of this.rows.values()) {
      if (predicates.matches(row)) { Object.assign(row, values); count++; }
    }
    this.snapshots.push([...this.rows.values()].map(row => ({ ...row })));
    return count;
  }
}

let store;
const context = vm.createContext({
  console, Date,
  Logger: { info() {}, warn() {}, error() {} },
  relationalStore: { RdbPredicates: Predicates },
  dbHelper: { getStore() { return store; } }
});
function load(file) {
  const source = fs.readFileSync(path.join(root, file + '.ets'), 'utf8')
    .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+/g, '');
  vm.runInContext(stripTypeScriptTypes(source, { mode: 'transform' }), context, { filename: file + '.ets' });
}
for (const file of ['model/Chapter', 'database/BaseDao', 'database/ChapterDao', 'repository/ChapterRepository']) load(file);
const { ChapterRepository } = vm.runInContext('({ ChapterRepository })', context);
function row(id = 'target', fav = 0, inspiration = 0) {
  return { id, book_id: '', title: 'Original title', content: 'Saved body', format_runs: '[format]',
    caret_offset: 5, word_count: 10, sort_order: 2, updated_at: 1, is_fav: fav, is_inspiration: inspiration };
}
function fixture(fav = 0, inspiration = 0, transaction = false) {
  store = new WriteStore();
  const initial = row('target', fav, inspiration), other = row('other', 0, 1);
  store.rows.set(initial.id, { ...initial }); store.rows.set(other.id, { ...other });
  const writes = store;
  const tx = transaction ? { update: (values, predicates) => writes.update(values, predicates) } : null;
  if (transaction) store = { update() { throw new Error('transaction write escaped to ordinary store'); } };
  return { repo: new ChapterRepository(tx), writes, initial, other, current: () => writes.rows.get('target') };
}
function assertOtherFields(current, initial) {
  for (const key of ['id', 'title', 'content', 'format_runs', 'caret_offset', 'word_count', 'sort_order']) {
    assert.equal(current[key], initial[key], key + ' must remain unchanged');
  }
}
function assertExclusive(writes) {
  for (const snapshot of writes.snapshots) {
    for (const saved of snapshot) {
      assert.ok(!(saved.is_fav && saved.is_inspiration), 'a committed chapter cannot be both favourite and inspiration');
    }
  }
}
let passed = 0, failed = 0;
async function check(name, action) {
  try { await action(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name); console.error(error); }
}

(async () => {
  for (const kind of ['favourite', 'inspiration']) {
    const fav = kind === 'favourite';
    await check(kind + ' failure preserves the previous classification and modification time', async () => {
      const { repo, writes, initial, current } = fixture(fav ? 0 : 1, fav ? 1 : 0);
      writes.beforeUpdate = async values => {
        if (values[fav ? 'is_fav' : 'is_inspiration'] === 1) throw new Error('disk full');
      };
      await assert.rejects(fav ? repo.setFav('target', true) : repo.setInspiration('target', true), /disk full/);
      assert.deepEqual(current(), initial, 'failed metadata changes must not partially remove the previous category');
    });

    await check('overlapping ' + kind + ' and opposite classification never commit both flags', async () => {
      const { repo, writes, current, initial, other } = fixture();
      const entered = deferred(), resume = deferred();
      writes.beforeUpdate = async values => {
        if (values[fav ? 'is_fav' : 'is_inspiration'] === 1) { entered.resolve(); await resume.promise; }
      };
      const first = fav ? repo.setFav('target', true) : repo.setInspiration('target', true);
      await entered.promise;
      await (fav ? repo.setInspiration('target', true) : repo.setFav('target', true));
      resume.resolve(); await first;
      assertExclusive(writes);
      assert.equal(current().is_fav, fav ? 1 : 0); assert.equal(current().is_inspiration, fav ? 0 : 1);
      assertOtherFields(current(), initial); assert.deepEqual(writes.rows.get('other'), other);
    });

    await check('clearing ' + kind + ' preserves the opposite classification', async () => {
      const { repo, current } = fixture(fav ? 0 : 1, fav ? 1 : 0);
      await (fav ? repo.setFav('target', false) : repo.setInspiration('target', false));
      assert.equal(current().is_fav, fav ? 0 : 1); assert.equal(current().is_inspiration, fav ? 1 : 0);
    });
  }

  await check('failed project reassignment preserves the source project and both classification fields', async () => {
    const { repo, writes, current, initial } = fixture(1, 0);
    writes.beforeUpdate = async values => { if ('book_id' in values) throw new Error('disk full'); };
    await assert.rejects(repo.moveToBook('target', 'book-b'), /disk full/);
    assert.deepEqual(current(), initial);
  });

  await check('project reassignment exposes no partially cleared source classification', async () => {
    const { repo, writes, current, initial, other } = fixture(0, 1);
    const entered = deferred(), resume = deferred();
    writes.beforeUpdate = async values => { if ('book_id' in values) { entered.resolve(); await resume.promise; } };
    const pending = repo.moveToBook('target', 'book-b');
    await entered.promise;
    const during = { ...current() };
    resume.resolve(); await pending;
    assert.deepEqual(during, initial, 'a pending move must preserve the complete source metadata');
    assert.equal(current().book_id, 'book-b'); assert.equal(current().is_fav, 0); assert.equal(current().is_inspiration, 0);
    assertOtherFields(current(), initial); assert.deepEqual(writes.rows.get('other'), other);
  });

  await check('moving to unclassified keeps existing favourite and inspiration semantics', async () => {
    for (const flags of [[1, 0], [0, 1], [0, 0]]) {
      const { repo, current, initial } = fixture(...flags);
      current().book_id = 'book-a';
      await repo.moveToBook('target', '');
      assert.equal(current().book_id, '');
      assert.equal(current().is_fav, flags[0]); assert.equal(current().is_inspiration, flags[1]);
      assertOtherFields(current(), initial);
    }
  });

  await check('metadata writes retain the repository transaction target', async () => {
    const { repo, writes, current } = fixture(1, 0, true);
    await repo.setInspiration('target', true);
    assert.equal(current().is_inspiration, 1); assert.equal(current().is_fav, 0);
    await repo.setFav('target', true);
    assert.equal(current().is_fav, 1); assert.equal(current().is_inspiration, 0);
    await repo.moveToBook('target', 'book-b');
    assert.equal(current().book_id, 'book-b'); assert.equal(current().is_fav, 0); assert.equal(current().is_inspiration, 0);
    assertExclusive(writes);
  });

  console.log('Chapter flag regression: ' + passed + ' passed, ' + failed + ' failed');
  process.exitCode = failed > 0 ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
