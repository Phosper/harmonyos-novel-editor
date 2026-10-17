// Node 24+. Runs the production import service against real files with forced short reads.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/ImportService.ets'), 'utf8');
const compiled = stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'weaver-import-regression-'));
const input = path.join(tempDir, 'input.txt');
function harness(text, options = {}) {
  fs.writeFileSync(input, text);
  const handles = new Map(), calls = [], errors = [];
  let reads = 0;
  const fileIo = {
    OpenMode: { READ_ONLY: 0 },
    async open(uri) {
      const handle = await fs.promises.open(uri, 'r');
      handles.set(handle.fd, handle);
      return { fd: handle.fd };
    },
    async stat(fd) {
      if (options.statError) throw options.statError;
      return { size: options.reportedSize ?? (await handles.get(fd).stat()).size };
    },
    async read(fd, buffer, readOptions = {}) {
      calls.push({ ...readOptions });
      if (options.readError && reads++ >= (options.failAfterReads ?? 0)) throw options.readError;
      const length = Math.min(readOptions.length ?? buffer.byteLength, options.chunkSize ?? Infinity);
      // fileIo offset is a file position, never a destination-buffer offset.
      const result = await handles.get(fd).read(new Uint8Array(buffer), 0, length, readOptions.offset ?? null);
      return result.bytesRead;
    },
    async close(file) {
      const handle = handles.get(file.fd);
      handles.delete(file.fd);
      await handle.close();
    }
  };
  const picker = {
    DocumentSelectOptions: class {},
    DocumentViewPicker: class { async select() { return options.cancel ? [] : [input]; } }
  };
  const context = vm.createContext({ fileIo, picker, ChapterFormat: { TXT: 'txt', MD: 'md' },
    Logger: { error(message) { errors.push(message); } },
    util: { TextDecoder: { create() { return { decodeToString(bytes) { return new TextDecoder().decode(bytes); } }; } } }
  });
  vm.runInContext(compiled, context);
  return { service: vm.runInContext('ImportService', context), handles, calls, errors };
}
let count = 0;
async function check(name, action) { await action(); count++; console.log('PASS ' + name); }
(async () => {
  await check('short reads preserve the complete UTF-8 document including split emoji', async () => {
    const text = '开头A😀中文\n第二段𠮷野家，结尾';
    const h = harness(text, { chunkSize: 3 });
    const files = await h.service.pickAndRead();
    assert.equal(files.length, 1);
    assert.equal(files[0].text, text);
    assert.ok(h.calls.length > 1);
    assert.equal(h.handles.size, 0);
    assert.equal(h.errors.length, 0);
  });
  await check('EOF before the advertised size rejects a truncated document', async () => {
    const h = harness('partial', { chunkSize: 2, reportedSize: 40 });
    const files = await h.service.pickAndRead();
    assert.equal(files.length, 0);
    assert.equal(h.errors.length, 1);
    assert.equal(h.handles.size, 0);
  });
  await check('a read error cannot import the prefix or leak the file handle', async () => {
    const h = harness('完整的文稿不能只剩开头', { chunkSize: 3, failAfterReads: 1, readError: new Error('read failed') });
    const files = await h.service.pickAndRead();
    assert.equal(files.length, 0);
    assert.equal(h.errors.length, 1);
    assert.equal(h.handles.size, 0);
  });
  await check('the byte limit is checked before allocating or reading content', async () => {
    const h = harness('small', { reportedSize: 16 * 1024 * 1024 + 1 });
    assert.equal((await h.service.pickAndRead()).length, 0);
    assert.equal(h.calls.length, 0);
    assert.equal(h.handles.size, 0);
  });
  await check('empty files and picker cancellation keep their original semantics', async () => {
    const empty = harness('');
    assert.equal((await empty.service.pickAndRead())[0].text, '');
    assert.equal(empty.handles.size, 0);
    const canceled = harness('ignored', { cancel: true });
    assert.equal((await canceled.service.pickAndRead()).length, 0);
    assert.equal(canceled.calls.length, 0);
  });
  console.log('Import regression: ' + count + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  fs.unlinkSync(input);
  fs.rmdirSync(tempDir);
});
