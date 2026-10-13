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
async function check(name, action) {
  await action();
  count++;
  console.log('PASS ' + name);
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
    async write(fd, text) {
      calls.push(['write']);
      if (options.writeError) throw options.writeError;
      return (await handles.get(fd).write(text)).bytesWritten;
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
  const fileContext = vm.createContext({ fileIo: io, picker, Logger: log });
  vm.runInContext(compile(read('utils/ExportService.ets')), fileContext);
  return { service: vm.runInContext('ExportService', fileContext), calls, handles };
}
(async () => {
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
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  if (fs.existsSync(output)) fs.unlinkSync(output);
  fs.rmdirSync(tempDir);
});
