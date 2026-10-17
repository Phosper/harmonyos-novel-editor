// Node 24+. Run the production shell methods with controlled UI/file-service doubles.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function compile(source) {
  return stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+/g, ''), { mode: 'transform' });
}
function method(source, name) {
  const match = source.match(new RegExp('^  (?:(?:private|static|async) )*' + name + '\\([\\s\\S]*?^  }', 'm'));
  assert.ok(match, 'production method ' + name);
  return match[0];
}
const log = { info() {}, warn() {}, error() {} };
const app = {};
const nav = { paths: [], getAllPathName() { return this.paths; }, pushPath(value) { this.paths.push(value.name); } };
let exportCalls = [];
const exportDouble = {
  renderChapter(chapter, target) { exportCalls.push({ kind: 'chapter', chapter, target }); return 'chapter'; },
  renderBook(name, chapters, target) { exportCalls.push({ kind: 'book', name, chapters, target }); return 'book'; },
  async exportBackupJson(name, payload) { exportCalls.push({ kind: 'backup', name, payload }); return true; },
  async saveText(name, text) { exportCalls.push({ kind: 'save', name, text }); return true; },
  extensionOf(target) { return '.' + target; }
};
const shellSource = read('shell/AppShell.ets');
const workspaceSource = read('shell/WorkspaceDest.ets');
const context = vm.createContext({ app, nav, Routes: { WORKSPACE: 'workspace' }, ExportService: exportDouble, Logger: log });
vm.runInContext(compile(shellSource.split('@ComponentV2')[0]), context);
vm.runInContext(compile(read('store/UiStore.ets').split('@ObservedV2')[0]), context);
vm.runInContext(compile(read('utils/ExportService.ets').split('export interface ExportableChapter')[0]), context);
vm.runInContext(compile('class ShellProbe {\n' + ['doExport', 'openDoc', 'handleDialogConfirm']
  .map(name => method(shellSource, name)).join('\n') + '\n}'), context);
vm.runInContext(compile('class WorkspaceProbe {\n' + ['onListOpenChange', 'syncOverlayDim', 'showWorkspace',
  'releaseDrawer', 'aboutToDisappear', 'closeDrawerForBack'].map(name => method(workspaceSource, name)).join('\n') + '\n}'), context);
const api = vm.runInContext('({ShellProbe, WorkspaceProbe, ShellDialog})', context);
function shell() {
  exportCalls = [];
  nav.paths = [];
  const probe = new api.ShellProbe();
  probe.toasts = [];
  probe.toast = value => probe.toasts.push(value);
  probe.dialogPending = false;
  Object.assign(app, {
    project: { bookName: 'Book' },
    editor: { hasDoc: true, title: 'Chapter', content: 'latest draft', format: 0, runsJson: '' },
    ui: { dialog: api.ShellDialog.NONE, dialogTarget: 'id', closeCount: 0,
      closeDialog() { this.dialog = api.ShellDialog.NONE; this.closeCount++; } },
    async openChapter() {}, async createBook() {}, async renameChapter() {},
    async deleteBook() {}, async hardDeleteChapter() {},
    async exportBackupData() { return { app: 'Weaver', version: 1, chapters: ['full chapter'] }; },
    async loadFullChapters() { return [{ title: 'Full', content: 'x'.repeat(900), format: 0, isTrash: false },
      { title: 'Trash', content: 'discarded', format: 0, isTrash: true }]; }
  });
  return probe;
}
let count = 0;
let failures = 0;
async function check(name, action) {
  try {
    await action();
    count++;
    console.log('PASS ' + name);
  } catch (error) {
    failures++;
    console.error('FAIL ' + name);
    console.error(error);
  }
}
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'weaver-shell-regression-'));
const output = path.join(tempDir, 'export.txt');
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
function exportHarness(options = {}) {
  fs.writeFileSync(output, 'old content with a much longer remainder');
  const calls = [];
  const handles = new Map();
  const io = {
    OpenMode: { READ_WRITE: 2, TRUNC: 512 },
    async open(uri, flags) {
      calls.push(['open', flags]);
      if (options.openError) throw options.openError;
      const handle = await fs.promises.open(uri, flags & io.OpenMode.TRUNC ? 'w+' : 'r+');
      handles.set(handle.fd, handle);
      return { fd: handle.fd };
    },
    write(fd, data) {
      calls.push(['write']);
      if (options.writeSyncError) throw options.writeSyncError;
      if (options.writeError) return Promise.reject(options.writeError);
      const writeCount = calls.filter(call => call[0] === 'write').length;
      if (options.zeroAtWrite === writeCount) return Promise.resolve(0);
      const bytes = typeof data === 'string' ? Buffer.from(data, 'utf8') : Buffer.from(new Uint8Array(data));
      const length = Math.min(bytes.byteLength, options.maxWrite ?? bytes.byteLength);
      return handles.get(fd).write(bytes, 0, length, null).then(result => result.bytesWritten);
    },
    async fsync(fd) {
      calls.push(['fsync']);
      if (options.syncStarted) options.syncStarted.resolve();
      if (options.syncGate) await options.syncGate.promise;
      if (options.syncError) throw options.syncError;
      await handles.get(fd).sync();
    },
    async close(file) {
      calls.push(['close']);
      const handle = handles.get(file.fd);
      handles.delete(file.fd);
      await handle.close();
      if (options.closeError) throw options.closeError;
    }
  };
  const picker = {
    DocumentSaveOptions: class {},
    DocumentViewPicker: class { async save() { return options.cancel ? [] : [output]; } }
  };
  const util = { TextEncoder: class {
    encodeInto(value) {
      if (options.encoderSyncError) throw options.encoderSyncError;
      // HarmonyOS encodeInto(string) differs from the two-argument Node API.
      if (value === '') return undefined;
      const bytes = new TextEncoder().encode(value);
      if (!options.encodingViewPadding) return bytes;
      const padded = new Uint8Array(bytes.byteLength + 8);
      padded.set(bytes, 4);
      return padded.subarray(4, 4 + bytes.byteLength);
    }
  } };
  const fileContext = vm.createContext({ fileIo: io, picker, Logger: log, util });
  for (const file of ['model/Chapter.ets', 'editor/flowtext/model/EditorTypes.ets',
    'editor/flowtext/model/FormatCodec.ets', 'utils/MarkdownRenderer.ets', 'utils/ExportService.ets']) {
    vm.runInContext(compile(read(file)), fileContext);
  }
  return { service: vm.runInContext('ExportService', fileContext),
    format: vm.runInContext('ChapterFormat', fileContext), calls, handles };
}
(async () => {
  await check('formatted TXT chapter exports preserve literal Markdown symbols and whitespace', () => {
    const harness = exportHarness();
    const content = '# 标题\n字面 *星号* _下划线_ `代码` ~~删除线~~\n> 引用\n  尾部  ';
    const chapter = { title: '片段', content, format: harness.format.TXT, runsJson: '0,4,1,0,0' };
    assert.equal(harness.service.renderChapter(chapter, 'txt', chapter.title), content);
  });
  await check('formatted TXT chapters keep their literal body in whole-book TXT exports', () => {
    const harness = exportHarness();
    const content = '# 标题\n字面 *星号* _下划线_ `代码`\n  尾部  ';
    const chapter = { title: '片段', content, format: harness.format.TXT, runsJson: '0,4,1,0,0' };
    assert.equal(harness.service.renderBook('示例书', [chapter], 'txt'), '示例书\n\n片段\n==\n\n' + content);
  });
  await check('Markdown source still removes Markdown syntax for chapter and whole-book TXT exports', () => {
    const harness = exportHarness();
    const chapter = { title: '片段', content: '# 标题\n**重点**与 _斜体_ 与 `代码`', format: harness.format.MD };
    const plain = '标题\n重点与 斜体 与 代码';
    assert.equal(harness.service.renderChapter(chapter, 'txt', chapter.title), plain);
    assert.equal(harness.service.renderBook('示例书', [chapter], 'txt'), '示例书\n\n片段\n==\n\n' + plain);
  });
  await check('all six visible menu choices export their advertised format', async () => {
    const expected = [['chapter', 'txt'], ['chapter', 'md'], ['chapter', 'html'], ['book', 'txt'], ['book', 'md'], ['backup', undefined]];
    for (let index = 0; index < expected.length; index++) {
      const probe = shell();
      await probe.doExport(index);
      assert.equal(exportCalls[0].kind, expected[index][0], 'menu index ' + index);
      assert.equal(exportCalls[0].target, expected[index][1], 'menu index ' + index);
      if (index === 5) {
        assert.equal(exportCalls.length, 1, 'JSON must not pass through HTML/text rendering');
        assert.equal(exportCalls[0].payload.app, 'Weaver');
      }
      if (index === 3 || index === 4) {
        assert.equal(exportCalls[0].chapters.length, 1, 'trash is omitted');
        assert.equal(exportCalls[0].chapters[0].content.length, 900, 'whole book uses full content');
      }
    }
  });
  await check('desktop failed document read is handled and does not navigate', async () => {
    const probe = shell();
    app.openChapter = async () => { throw new Error('database unavailable'); };
    await probe.openDoc('id');
    assert.equal(nav.paths.length, 0);
    assert.deepEqual(probe.toasts, ['打开文稿失败，请重试']);
  });
  await check('dialog write failures retain input and can be retried', async () => {
    for (const [kind, operation] of [['NEW_PROJECT', 'createBook'], ['RENAME_DOC', 'renameChapter'],
      ['DELETE_PROJECT', 'deleteBook'], ['DELETE_DOC', 'hardDeleteChapter']]) {
      const probe = shell();
      app.ui.dialog = api.ShellDialog[kind];
      app[operation] = async () => { throw new Error('write refused'); };
      await probe.handleDialogConfirm(' New name ');
      assert.equal(app.ui.dialog, api.ShellDialog[kind]);
      assert.equal(app.ui.closeCount, 0);
      assert.equal(probe.dialogPending, false);
      assert.ok(probe.toasts.includes('操作失败，请重试'));
      app[operation] = async () => {};
      await probe.handleDialogConfirm('New name');
      assert.equal(app.ui.dialog, api.ShellDialog.NONE);
      assert.equal(app.ui.closeCount, 1);
    }
  });
  await check('repeated confirm clicks create one project while a write is pending', async () => {
    const probe = shell();
    const gate = deferred();
    let created = 0;
    app.ui.dialog = api.ShellDialog.NEW_PROJECT;
    app.createBook = async name => { assert.equal(name, 'New'); created++; await gate.promise; };
    const pending = probe.handleDialogConfirm(' New ');
    await probe.handleDialogConfirm('New');
    assert.equal(created, 1);
    assert.equal(probe.dialogPending, true);
    gate.resolve();
    await pending;
    assert.equal(probe.dialogPending, false);
    assert.equal(app.ui.closeCount, 1);
    assert.match(shellSource, /\.enabled\(!this\.dialogPending\)/);
  });
  await check('empty project names keep the dialog available for correction', async () => {
    const probe = shell();
    app.ui.dialog = api.ShellDialog.NEW_PROJECT;
    app.createBook = async () => assert.fail('empty project must not be written');
    await probe.handleDialogConfirm('  ');
    assert.equal(app.ui.closeCount, 0);
    assert.deepEqual(probe.toasts, ['请输入名称']);
  });
  await check('drawer dim clears on wide layout, hidden destination and disappearance', () => {
    const ui = { breakPoint: 0, overlayDim: false, get isNarrow() { return this.breakPoint === 0; },
      setOverlayDim(value) { this.overlayDim = value; } };
    const probe = new api.WorkspaceProbe();
    Object.assign(probe, { ui, listOpen: false, workspaceVisible: false });
    probe.showWorkspace();
    probe.listOpen = true;
    probe.onListOpenChange();
    assert.equal(ui.overlayDim, true);
    ui.breakPoint = 2;
    probe.onListOpenChange();
    assert.equal(ui.overlayDim, false);
    ui.breakPoint = 0;
    probe.onListOpenChange();
    assert.equal(ui.overlayDim, true);
    probe.releaseDrawer();
    assert.equal(ui.overlayDim, false);
    assert.equal(probe.listOpen, false);
    probe.listOpen = true;
    probe.onListOpenChange();
    assert.equal(ui.overlayDim, false, 'hidden destinations cannot dim later pages');
    probe.showWorkspace();
    assert.equal(ui.overlayDim, true);
    probe.aboutToDisappear();
    assert.equal(ui.overlayDim, false);
    assert.match(workspaceSource, /@Monitor\('listOpen', 'ui\.breakPoint'\)/);
    assert.match(workspaceSource, /\.onHidden\(\(\) => this\.releaseDrawer\(\)\)/);
  });
  await check('back closes an open drawer before allowing navigation', () => {
    const ui = { isNarrow: true, overlayDim: false, setOverlayDim(value) { this.overlayDim = value; } };
    const probe = new api.WorkspaceProbe();
    Object.assign(probe, { ui, listOpen: true, workspaceVisible: true });
    probe.syncOverlayDim();
    assert.equal(probe.closeDrawerForBack(), true);
    assert.equal(probe.listOpen, false);
    assert.equal(ui.overlayDim, false);
    assert.equal(probe.closeDrawerForBack(), false);
    assert.match(workspaceSource, /\.onBackPressed\(\(\) => this\.closeDrawerForBack\(\)\)/);
  });
  await check('shorter exports replace the complete existing file and close it', async () => {
    const harness = exportHarness();
    assert.equal(await harness.service.saveText('export.txt', '新'), true);
    assert.equal(fs.readFileSync(output, 'utf8'), '新');
    assert.deepEqual(harness.calls.map(call => call[0]), ['open', 'write', 'fsync', 'close']);
    assert.equal(harness.handles.size, 0);
  });
  await check('UTF-8 short writes are retried without splitting or losing encoded bytes', async () => {
    const content = '首😀尾\n组合e\u0301与\u0000零字节';
    for (const maxWrite of [1, 2, 3, 7]) {
      const harness = exportHarness({ maxWrite, encodingViewPadding: true });
      assert.equal(await harness.service.saveText('export.txt', content), true);
      assert.deepEqual(fs.readFileSync(output), Buffer.from(content, 'utf8'));
      assert.ok(harness.calls.filter(call => call[0] === 'write').length > 1);
      assert.equal(harness.calls.at(-2)[0], 'fsync');
      assert.equal(harness.calls.at(-1)[0], 'close');
      assert.equal(harness.handles.size, 0);
    }
    const longContent = '甲😀e\u0301\n'.repeat(15000);
    const harness = exportHarness({ maxWrite: 4093, encodingViewPadding: true });
    assert.equal(await harness.service.saveText('export.txt', longContent), true);
    assert.deepEqual(fs.readFileSync(output), Buffer.from(longContent, 'utf8'));
    assert.equal(harness.handles.size, 0);
  });
  await check('a write with zero progress rejects and closes without syncing truncated output', async () => {
    for (const options of [{ maxWrite: 0 }, { maxWrite: 2, zeroAtWrite: 2 }]) {
      const harness = exportHarness(options);
      await assert.rejects(harness.service.saveText('export.txt', '首😀尾'), /写入未完成/);
      assert.equal(harness.calls.some(call => call[0] === 'fsync'), false);
      assert.equal(harness.calls.filter(call => call[0] === 'close').length, 1);
      assert.equal(harness.handles.size, 0);
    }
  });
  await check('synchronous encoding and write failures close descriptors and preserve the original error', async () => {
    for (const field of ['encoderSyncError', 'writeSyncError']) {
      const error = new Error(field);
      const harness = exportHarness({ [field]: error, closeError: new Error('secondary close failure') });
      await assert.rejects(harness.service.saveText('export.txt', '首😀尾'), received => received === error);
      assert.equal(harness.calls.some(call => call[0] === 'fsync'), false);
      assert.equal(harness.calls.filter(call => call[0] === 'close').length, 1);
      assert.equal(harness.handles.size, 0);
    }
  });
  await check('an empty export truncates and syncs without encoding or requesting a zero-byte write', async () => {
    const harness = exportHarness();
    assert.equal(await harness.service.saveText('export.txt', ''), true);
    assert.equal(fs.statSync(output).size, 0);
    assert.deepEqual(harness.calls.map(call => call[0]), ['open', 'fsync', 'close']);
    assert.equal(harness.handles.size, 0);
  });
  await check('picker cancellation returns false without opening a descriptor', async () => {
    const harness = exportHarness({ cancel: true });
    assert.equal(await harness.service.saveText('export.txt', 'new'), false);
    assert.equal(harness.calls.length, 0);
  });
  await check('write and sync failures close descriptors and reach the caller', async () => {
    for (const field of ['writeError', 'syncError']) {
      const error = new Error(field);
      const harness = exportHarness({ [field]: error });
      await assert.rejects(harness.service.saveText('export.txt', 'new'), received => received === error);
      assert.equal(harness.calls.filter(call => call[0] === 'close').length, 1);
      assert.equal(harness.handles.size, 0);
    }
  });
  await check('a secondary close failure preserves the original write error', async () => {
    const error = new Error('primary write failure');
    const harness = exportHarness({ writeError: error, closeError: new Error('secondary close failure') });
    await assert.rejects(harness.service.saveText('export.txt', 'new'), received => received === error);
    assert.equal(harness.handles.size, 0);
  });
  await check('open or close failure cannot be reported as export success', async () => {
    for (const field of ['openError', 'closeError']) {
      const error = new Error(field);
      const harness = exportHarness({ [field]: error });
      await assert.rejects(harness.service.saveText('export.txt', 'new'), received => received === error);
      assert.equal(harness.handles.size, 0);
    }
  });
  await check('save waits for asynchronous fsync before closing or succeeding', async () => {
    const syncStarted = deferred();
    const syncGate = deferred();
    const harness = exportHarness({ syncStarted, syncGate });
    let finished = false;
    const save = harness.service.saveText('export.txt', 'new').then(result => { finished = true; return result; });
    await syncStarted.promise;
    assert.equal(finished, false);
    assert.equal(harness.calls.some(call => call[0] === 'close'), false);
    syncGate.resolve();
    assert.equal(await save, true);
    assert.equal(harness.handles.size, 0);
  });
  console.log(`Shell regression: ${count} checks passed`);
  if (failures > 0) {
    console.error(`Shell regression: ${failures} checks failed`);
    process.exitCode = 1;
  }
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  if (fs.existsSync(output)) fs.unlinkSync(output);
  fs.rmdirSync(tempDir);
});
