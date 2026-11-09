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
  // Markdown 块级解析是纯模块（只依赖 EditorTypes），直接装进同一个沙箱：
  // 导入侧的剥离规则与导出侧的"已带标记"判定必须由同一份代码决定（R4）。
  const ets = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8');
  const strip = text => stripTypeScriptTypes(text
    .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+/g, ''), { mode: 'transform' });
  vm.runInContext(strip(ets('editor/flowtext/model/EditorTypes.ets')), context);
  vm.runInContext(strip(ets('utils/MarkdownBlocks.ets')), context);
  const markdown = vm.runInContext('MarkdownBlocks', context);
  return { service: vm.runInContext('ImportService', context), markdown, handles, calls, errors };
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
  await check('markdown blocks become paragraph runs and the markers leave the text', async () => {
    const h = harness('');
    const parsed = h.markdown.parse('# 标题\n正文\n- [ ] 待办\n  - 列表\n#### 四级');
    // 一~三级标题/列表/待办去掉行首标记；四级标题没有对应段落种类，保留原文（不静默改）
    assert.equal(parsed.content, '标题\n正文\n待办\n列表\n#### 四级');
    assert.deepEqual(JSON.parse(JSON.stringify(parsed.runs.map(r => [r.startOffset, r.endOffset, r.heading, r.indent]))),
      [[0, 3, 1, 0], [6, 9, 5, 0], [9, 12, 4, 1]]);
  });
  await check('a markdown round trip never stacks a second heading marker', async () => {
    const h = harness('');
    const parsed = h.markdown.parse('# 标题\n- [x] 已完成');
    assert.equal(parsed.content, '标题\n已完成');
    assert.equal(h.markdown.alreadyMarked('标题', 1), false, 'fresh text needs its prefix back');
    assert.equal(h.markdown.alreadyMarked('- 项', 4), true, 'already a list item');
    // 历史脏数据（正文里留了 #）：解析后导出只还原一层，不会变成 `# # #`
    const legacy = h.markdown.parse('# # 标题');
    assert.equal(legacy.content, '# 标题');
    assert.equal(h.markdown.alreadyMarked(legacy.content, 1), true, 'legacy marker is recognised, not doubled');
  });
  console.log('Import regression: ' + count + ' checks passed');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  fs.unlinkSync(input);
  fs.rmdirSync(tempDir);
});
