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
const context = vm.createContext({ app, nav, Routes: { WORKSPACE: 'workspace' }, ExportService: exportDouble, Logger: log,
  fireAndLog: promise => promise.catch(error => { throw error; }) });
vm.runInContext(compile(shellSource.split('@ComponentV2')[0]), context);
vm.runInContext(compile(read('store/UiStore.ets').split('@ObservedV2')[0]), context);
vm.runInContext(compile(read('utils/ExportService.ets').split('export interface ExportableChapter')[0]), context);
vm.runInContext(compile('class ShellProbe {\n' + ['doExport', 'openDoc', 'handleDialogConfirm']
  .map(name => method(shellSource, name)).join('\n') + '\n}'), context);
vm.runInContext(compile('class WorkspaceProbe {\n' + ['onListOpenChange', 'syncOverlayDim', 'showWorkspace',
  'releaseDrawer', 'aboutToDisappear', 'closeDrawerForBack'].map(name => method(workspaceSource, name)).join('\n') + '\n}'), context);
const docListSource = read('shell/DocListPane.ets');
vm.runInContext(compile('class DocListProbe {\n' + ['rowMenuItems', 'onRowMenuAction', 'onMoreAction']
  .map(name => method(docListSource, name)).join('\n') + '\n}'), context);
const api = vm.runInContext('({ShellProbe, WorkspaceProbe, ShellDialog, DocListProbe})', context);
function docMenu(isTrash = false) {
  const calls = [], probe = new api.DocListProbe();
  const row = {id: 'doc-a', bookId: 'book-a', title: 'Current title', isTrash, isFav: false, isInspiration: false};
  let current = row;
  probe.app = {project: {currentBookId: 'book-a', findChapter: id => current?.id === id ? current : undefined},
    async restoreChapter(id) { calls.push(['restore', id]); },
    async hardDeleteChapter(id) { calls.push(['purge', id]); },
    async toggleFav(id) { calls.push(['fav', id]); }, async toggleInspiration(id) { calls.push(['inspiration', id]); }};
  probe.onRenameDoc = (id, title) => calls.push(['rename', id, title]);
  probe.onDeleteDoc = (id, title) => calls.push(['confirmDelete', id, title]);
  probe.moveDocToTrash = id => calls.push(['trash', id]);
  probe.onExport = () => calls.push(['export']); probe.onImport = () => calls.push(['import']);
  return {probe, row, calls, replaceRow: value => current = value};
}

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
  await check('native document menu maps rename, favourite, inspiration and trash to the current document', () => {
    const {probe, row, calls} = docMenu();
    const items = probe.rowMenuItems(row);
    assert.deepEqual(Array.from(items, item => item.value), ['重命名', '收藏', '移入灵感池', '移入废纸篓']);
    items.forEach(item => item.action());
    assert.deepEqual(calls, [['rename','doc-a','Current title'],['fav','doc-a'],['inspiration','doc-a'],['trash','doc-a']]);
    row.isFav = true; row.isInspiration = true;
    assert.deepEqual(Array.from(probe.rowMenuItems(row), item => item.value), ['重命名','取消收藏','移出灵感池','移入废纸篓']);
  });
  await check('trash context menu restores a document but requests confirmation before permanent deletion', () => {
    const {probe, row, calls} = docMenu(true), items = probe.rowMenuItems(row);
    assert.deepEqual(Array.from(items, item => item.value), ['恢复','彻底删除']);
    items.forEach(item => item.action());
    assert.deepEqual(calls, [['restore','doc-a'],['confirmDelete','doc-a','Current title']]);
  });
  await check('a menu opened before switching project or removing its document cannot act on the replacement', () => {
    for (const change of ['project','removed','foreignRow']) {
      const {probe, row, calls, replaceRow} = docMenu(), items = probe.rowMenuItems(row);
      if (change === 'project') probe.app.project.currentBookId = 'book-b';
      else if (change === 'removed') replaceRow(undefined);
      else replaceRow({...row, bookId: 'book-b'});
      items.forEach(item => item.action()); assert.deepEqual(calls, []);
    }
  });
  await check('an old menu cannot delete a restored document or reinterpret actions after its trash state changes', () => {
    for (const wasTrash of [false, true]) {
      const {probe, row, calls, replaceRow} = docMenu(wasTrash), items = probe.rowMenuItems(row);
      replaceRow({...row, isTrash: !wasTrash}); row.isTrash = !wasTrash;
      items.forEach(item => item.action()); assert.deepEqual(calls, []);
    }
  });
  await check('the document header dispatches only valid export and import entries', () => {
    const {probe, calls} = docMenu();
    for (const index of [0,1,-1,2]) probe.onMoreAction(index);
    assert.deepEqual(calls, [['export'],['import']]);
  });
  await check('formatted TXT HTML preserves literal Markdown, HTML characters and whitespace', () => {
    const harness = exportHarness();
    const content = '加粗\n# 原样标题\n*星号* _下划线_ `代码` ~~删除线~~\n> 引用 <script>&"\n  尾部\t  \n\n';
    const chapter = { title: '<片段>&"', content, format: harness.format.TXT, runsJson: '0,2,1,0,0' };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.ok(html.includes('<strong>加粗</strong>'));
    assert.ok(html.includes('# 原样标题'));
    assert.ok(html.includes('*星号* _下划线_ `代码` ~~删除线~~'));
    assert.ok(html.includes('&gt; 引用 &lt;script&gt;&amp;&quot;'));
    assert.ok(html.includes('  尾部\t  '));
    assert.match(html, /white-space:\s*pre-wrap/);
    assert.match(html, /<title>&lt;片段&gt;&amp;&quot;<\/title>/);
    assert.doesNotMatch(html, /<h1\b|<em>星号|<code>代码|<del>删除线|<blockquote>|<script>/);
    assert.equal((html.match(/<br>/g) ?? []).length, 2, 'both trailing empty paragraphs remain visible');
  });
  await check('whole-book HTML keeps formatted TXT literal and still parses Markdown chapters', () => {
    const harness = exportHarness();
    const chapters = [
      { title: '<纯文本>', content: '重点 *字面* & <原文>', format: harness.format.TXT, runsJson: '0,2,1,0,0' },
      { title: 'Markdown', content: '# 标题\n**重点**与 _斜体_', format: harness.format.MD }
    ];
    const html = harness.service.renderBook('书<&', chapters, 'html');
    assert.ok(html.includes('<h1>书&lt;&amp;</h1>'));
    assert.ok(html.includes('<h2>&lt;纯文本&gt;</h2>'));
    assert.ok(html.includes('<strong>重点</strong> *字面* &amp; &lt;原文&gt;'));
    assert.ok(html.includes('<h1>标题</h1>'));
    assert.ok(html.includes('<strong>重点</strong>与 <em>斜体</em>'));
    assert.doesNotMatch(html, /<em>字面<\/em>/);
  });
  await check('formatted TXT HTML retains all supported heading and inline styles', () => {
    const harness = exportHarness();
    const chapter = { title: '格式', content: '一标题\n二标题\n三标题\n双重样式', format: harness.format.TXT,
      runsJson: '0,3,1,0,1;4,7,0,1,2;8,11,0,0,3;12,16,1,1,0' };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.match(html, /<h1\b[^>]*><strong>一标题<\/strong><\/h1>/);
    assert.match(html, /<h2\b[^>]*><em>二标题<\/em><\/h2>/);
    assert.match(html, /<h3\b[^>]*>三标题<\/h3>/);
    assert.match(html, /<p\b[^>]*><em><strong>双重样式<\/strong><\/em><\/p>/);
  });
  await check('formatted TXT HTML keeps UTF-16 styles aligned across CRLF and newline boundaries', () => {
    const harness = exportHarness();
    const chapter = { title: '边界', content: '😀甲\r\n乙🚀\n尾', format: harness.format.TXT,
      runsJson: '0,5,1,0,2;5,8,0,1,3' };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.match(html, /<h2\b[^>]*><strong>😀甲<\/strong><\/h2>/);
    assert.match(html, /<h3\b[^>]*><em>乙🚀<\/em><\/h3>/);
    assert.match(html, /<p\b[^>]*>尾<\/p>/);
    assert.doesNotMatch(html, /\r|\uFFFD/);
  });
  await check('formatted TXT HTML never splits a surrogate pair at an imported run boundary', () => {
    const harness = exportHarness();
    const chapter = { title: '边界', content: 'A😀B\nC', format: harness.format.TXT, runsJson: '1,2,1,0,0' };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.ok(html.includes('A<strong>😀</strong>B'));
    assert.doesNotMatch(html, /\uD83D<\/strong>\uDE00|\uFFFD/);
  });
  await check('formatted TXT HTML exports list levels and todo completion without interpreting the literal body', () => {
    const harness = exportHarness();
    const lines = ['*字面* <条目>&', '待办 _原文_', '完成 `代码` ~~原样~~', '# 正文'];
    let offset = 0;
    const runsJson = lines.map((line, index) => {
      const start = offset; offset += line.length + 1;
      return `${start},${offset},${index === 0 ? 1 : 0},${index === 1 ? 1 : 0},${[4,5,6,0][index]},${[0,1,2,0][index]}`;
    }).join(';');
    const chapter = { title: '列表', content: lines.join('\n'), format: harness.format.TXT, runsJson };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.match(html, /<ul\b[^>]*margin-left:\s*0em/);
    assert.match(html, /<ul\b[^>]*margin-left:\s*2em/);
    assert.match(html, /<ul\b[^>]*margin-left:\s*4em/);
    assert.match(html, /<li\b[^>]*><strong>\*字面\* &lt;条目&gt;&amp;<\/strong><\/li>/);
    assert.match(html, /<input\b[^>]*type="checkbox"[^>]*disabled[^>]*> <em>待办 _原文_<\/em>/);
    assert.match(html, /<input\b[^>]*type="checkbox"[^>]*checked[^>]*> <del>完成 `代码` ~~原样~~<\/del>/);
    assert.match(html, /<p\b[^>]*># 正文<\/p>/);
    assert.doesNotMatch(html, /<h[4-6]\b|<em>字面|<code>|<del>原样/);
    assert.equal((html.match(/<ul\b/g) ?? []).length, (html.match(/<\/ul>/g) ?? []).length);
  });
  await check('whole-book TXT list HTML preserves CRLF offsets, escaped titles and surrogate boundaries', () => {
    const harness = exportHarness();
    const chapter = { title: '<清单>&', content: 'A😀\r\n乙🚀\n尾', format: harness.format.TXT,
      runsJson: '0,5,0,0,4,1;1,2,1,0,4,1;5,8,0,1,6,2' };
    const markdown = { title: 'Markdown', content: '- *Markdown*', format: harness.format.MD };
    const html = harness.service.renderBook('书<&', [chapter, markdown], 'html');
    assert.ok(html.includes('<h1>书&lt;&amp;</h1>'));
    assert.ok(html.includes('<h2>&lt;清单&gt;&amp;</h2>'));
    assert.match(html, /A<strong>😀<\/strong><\/li>/);
    assert.match(html, /<del><em>乙🚀<\/em><\/del>/);
    assert.match(html, /<p\b[^>]*>尾<\/p>\n<hr>/);
    assert.ok(html.includes('<li><em>Markdown</em></li>'));
    assert.doesNotMatch(html, /\r|\uFFFD|\uD83D<\/strong>\uDE00|<h[4-6]\b/);
    assert.equal((html.match(/<ul\b/g) ?? []).length, (html.match(/<\/ul>/g) ?? []).length);
  });
  await check('HTML paragraph lookup retains shifted list attributes beside inline marks and closes before body', () => {
    const harness = exportHarness();
    const chapter = { title: '段落', content: 'Xitem\nnext\n- 字面列表\n标题', format: harness.format.TXT,
      runsJson: '0,1,1,0,0,0;1,6,0,0,5,1;6,10,0,0,5,1;18,20,0,0,2,0' };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.match(html, /<input\b[^>]*> <strong>X<\/strong>item<\/li>/);
    assert.equal((html.match(/type="checkbox"/g) ?? []).length, 2);
    assert.match(html, /<\/li>\n<\/ul>\n<p\b[^>]*>- 字面列表<\/p>/);
    assert.match(html, /<h2\b[^>]*>标题<\/h2>/);
  });
  await check('TXT HTML keeps blank paragraphs and indentation even without format annotations', () => {
    const harness = exportHarness();
    const chapter = { title: '无标注', content: '  *原文*\t \r\n\n', format: harness.format.TXT };
    const html = harness.service.renderChapter(chapter, 'html', chapter.title);
    assert.match(html, /<p\b[^>]*white-space:\s*pre-wrap[^>]*>  \*原文\*\t <\/p>/);
    assert.equal((html.match(/<br>/g) ?? []).length, 2);
    assert.doesNotMatch(html, /<em>原文|\r/);
  });

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
  await check('list and todo paragraphs export as Markdown list items, never as fake headings', () => {
    const harness = exportHarness();
    const content = '正文\n第一项\n待办\n已办';
    // 段落属性区间含段末换行：列表 [3,7)、待办 [7,10)、已完成待办 [10,12)
    const runsJson = '3,7,0,0,4,0;7,10,0,0,5,0;10,12,0,0,6,1';
    const chapter = { title: '片段', content, format: harness.format.TXT, runsJson };
    assert.equal(harness.service.renderChapter(chapter, 'md', chapter.title),
      '正文\n- 第一项\n- [ ] 待办\n  - [x] 已办');
    const heading = { title: '片段', content: '标题', format: harness.format.TXT, runsJson: '0,2,0,0,2' };
    assert.equal(harness.service.renderChapter(heading, 'md', heading.title), '## 标题');
    // 在段首插入过文字后段落标注可能从段中开始，导出要按整段判定，不能时有时无
    const shifted = { title: '片段', content: 'Xitem', format: harness.format.TXT,
      runsJson: '1,5,0,0,4,0' };
    assert.equal(harness.service.renderChapter(shifted, 'md', shifted.title), '- Xitem');
    // 行内标注（heading=0）不能把列表读成正文
    const inline = { title: '片段', content: 'item', format: harness.format.TXT,
      runsJson: '0,1,1,0,0,0;1,4,0,0,5,0' };
    // 行内加粗仍按 ** 导出，段落种类按列表前缀导出：两者共存
    assert.equal(harness.service.renderChapter(inline, 'md', inline.title), '- [ ] **i**tem');
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
  await check('project sidebar pins its list to the top (no centred block on project changes)', async () => {
    const sidebar = read('shell/ProjectSidebar.ets');
    assert.match(sidebar, /constraintSize\(\{ minHeight: '100%' \}\)/, 'content must fill the viewport height');
    assert.match(sidebar, /justifyContent\(FlexAlign\.Start\)/, 'content must start at the top');
    assert.match(sidebar, /\.align\(Alignment\.TopStart\)/, 'Scroll must align its content to the top');
    assert.ok(!sidebar.includes('.translate('), 'no bottom-up slide-in transform');
    assert.match(sidebar, /sys\.symbol\.folder/, 'project rows use a Symbol icon');
  });
  await check('window chrome is transparent and pane headers own the Symbol actions', async () => {
    const bar = read('shell/DesktopTitleBar.ets');
    assert.ok(!bar.includes("Text('☰')"), 'hamburger text glyph must be gone');
    assert.match(bar, /backgroundColor\(Color\.Transparent\)/, 'window strip must not paint a bar');
    const list = read('shell/DocListPane.ets');
    assert.match(list, /sys\.symbol\.close_sidebar/);
    assert.match(list, /sys\.symbol\.open_sidebar/);
    // 更多图标统一为鸿蒙四点 dot_grid_2x2；设置入口已并入左下角账号行
    assert.match(list, /headerMoreIcon/);
    assert.match(list, /items: \['导出', '导入'\]/);
    assert.doesNotMatch(list, /\$r\('sys\.symbol\.more'\)/, 'more glyph is an app grid, not four dots');
    const sidebar = read('shell/ProjectSidebar.ets');
    assert.match(sidebar, /app\.media\.startIcon/);
  });
  await check('tool group uses Symbol icons and unified motion tokens', async () => {
    const tools = read('shell/EditorTools.ets');
    for (const name of ['undo', 'redo', 'bold', 'italic', 'magnifyingglass', 'fullscreen', 'textformat']) {
      assert.ok(tools.includes('sys.symbol.' + name), 'missing symbol ' + name);
    }
    assert.match(tools, /Motion\.fast/);
    assert.match(tools, /Motion\.standardCurve/);
  });
  await check('user-visible application name is 语流 across resources and headers', async () => {
    const appStrings = fs.readFileSync(path.resolve(__dirname, '../AppScope/resources/base/element/string.json'), 'utf8');
    const entryStrings = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/resources/base/element/string.json'), 'utf8');
    assert.match(appStrings, /"value": "语流"/);
    assert.ok(!appStrings.includes('"value": "Weaver"'));
    assert.match(entryStrings, /语流小说编辑器/);
    assert.ok(!entryStrings.includes('Weaver 小说编辑器'));
    assert.ok(read('pages/GuideSwiperPage.ets').includes('开始使用 语流'));
    assert.ok(read('shell/ProjectSidebar.ets').includes("Text('语流')"));
  });
  await check('main app no longer mounts a layout-occupying title bar', async () => {
    const shell = read('shell/AppShell.ets');
    assert.ok(!shell.includes('DesktopTitleBar({'), 'title bar must not be rendered in the main layout');
    assert.match(read('shell/ProjectSidebar.ets'), /startWindowMove/);
    assert.match(read('shell/DocListPane.ets'), /startWindowMove/);
    assert.match(read('shell/EditorPane.ets'), /startWindowMove/);
  });
  await check('wide sidebar animates width, opacity and offset instead of snapping', async () => {
    const shell = read('shell/AppShell.ets');
    assert.match(shell, /\.width\(app\.ui\.showSidebar \? this\.sideBarWidthVp\(\) : 0\)/);
    assert.match(shell, /\.opacity\(app\.ui\.showSidebar \? 1 : 0\)/);
    assert.match(shell, /\.translate\(\{ x: app\.ui\.showSidebar \? 0 : -16 \}\)/);
    assert.match(shell, /duration: Motion\.sidebar/);
    assert.match(shell, /curves\.springMotion\(0\.4, 1\.0, 0\)/);
    assert.ok(!shell.includes('SideBarContainer(SideBarContainerType.AUTO)'), 'wide layout must not rely on instant showSideBar');
  });
  await check('placeholder is painted on the text canvas with body metrics', async () => {
    const renderer = read('editor/flowtext/render/GlyphRenderer.ets');
    assert.match(renderer, /drawPlaceholder/);
    assert.match(renderer, /TextBlob\.makeFromString/);
    const editor = read('editor/flowtext/CanvasTextEditor.ets');
    assert.match(editor, /placeholderColor/);
    const pane = read('shell/EditorPane.ets');
    assert.ok(!pane.includes("Text('开始写作…')"), 'placeholder overlay must be removed');
  });
  await check('middle column receives live text preview updates and undo sync', async () => {
    assert.match(read('store/ProjectStore.ets'), /updateDocPreview\(/);
    const pane = read('shell/EditorPane.ets');
    assert.match(method(pane, 'syncActivePreview'), /updateDocPreview\(doc\.id, stores\.editor\.title, stores\.editor\.content,\s*stores\.editor\.wordCount, doc\.dirty\)/);
    assert.match(method(pane, 'applyEditorChange'), /stores\.editor\.activeId !== ownerId/);
    assert.match(method(pane, 'applyEditorChange'), /setEditorState\(text, FormatCodec\.encode\(runs\), caret, ownerId\)/);
    assert.match(method(pane, 'applyEditorChange'), /this\.syncActivePreview\(\)/);
    assert.match(pane, /@Monitor\('editor\.contentRev'\)/);
  });
  await check('focus mode has a designed header, exit path and visible fallback animation', async () => {
    const focus = read('shell/FocusWorkspace.ets');
    assert.match(focus, /专注写作/);
    assert.match(focus, /exitFocus\(/);
    assert.match(focus, /sys\.symbol\.exit_full_screen/);
    // 不再用 scale/translate 入场（与 geometryTransition 叠加会出现白边与标题跳变）
    assert.doesNotMatch(focus, /\.scale\(\{ x: this\.entered/);
    assert.match(focus, /\.backgroundColor\(this\.colors\(\)\.bgPrimary\)/);
    assert.doesNotMatch(focus, /\.translate\(\{ y: this\.entered/);
    // 入场不再用透明度/位移兜底：geometryTransition 负责形变，页面本身始终不透明
    assert.doesNotMatch(focus, /\.opacity\(this\.entered/);
    assert.match(focus, /aboutToAppear/);
    assert.match(focus, /Motion\.fast/);
  });
  await check('top actions are flat Email-style icons without glass material', async () => {
    const tokens = read('constants/LightTokens.ets');
    assert.match(tokens, /TOP_ICON_SIZE: number = 40/);
    assert.match(tokens, /TOP_ICON_HIT_POINTER: number = 44/);
    assert.match(tokens, /TOP_ICON_HIT_TOUCH: number = 48/);
    assert.match(tokens, /TOP_ICON_FONT: number = 20/);
    assert.doesNotMatch(tokens, /WeaverGlassKind\.ICON/);
    assert.doesNotMatch(tokens, /iconGlass/);
    const surface = read('shell/MaterialSurface.ets');
    assert.doesNotMatch(surface, /glassIconStyle/);
    const button = read('shell/TopActionButton.ets');
    // 关键字面：没有材质修改器、没有模糊/渐变、没有描边阴影，只有 hover/按下时的纯色底
    assert.doesNotMatch(button, /glassIconStyle|attributeModifier|backgroundBlurStyle|linearGradient|border\s*\(|shadow/);
    assert.match(button, /Color\.Transparent/);
    assert.match(button, /this\.pressed/);
    assert.match(button, /HitTestMode\.None/);
    for (const file of ['shell/EditorTools.ets', 'shell/DocListPane.ets', 'shell/ProjectSidebar.ets']) {
      assert.match(read(file), /TopActionButton/, file + ' must reuse the shared button');
    }
    const focus = read('shell/FocusWorkspace.ets');
    assert.doesNotMatch(focus, /glassIconStyle/, 'focus exit pill must stay flat too');
  });
  await check('native caption buttons follow the app theme instead of the system theme', async () => {
    const chrome = read('utils/DesktopWindowChrome.ets');
    assert.match(chrome, /export function syncDesktopDecorButtons\(dark: boolean\): void/);
    assert.match(chrome, /setDecorButtonStyle/);
    assert.match(chrome, /COLOR_MODE_DARK/);
    assert.match(chrome, /COLOR_MODE_LIGHT/);
    // 只对桌面窗口下发，手机/平板不刷 801 告警
    assert.match(chrome, /AppStorage\.get<boolean>\('isPcDevice'\)/);
    assert.match(chrome, /AppStorage\.get<boolean>\('freeWindowMode'\)/);
    const ui = read('store/UiStore.ets');
    assert.match(ui, /syncDesktopDecorButtons\(t\.dark\)/, 'theme sync must drive the caption button colour');
  });
  await check('top-right tools reserve the measured native caption area', async () => {
    const ui = read('store/UiStore.ets');
    assert.match(ui, /titleButtonWidthVp: number = 0/);
    assert.match(ui, /this\.titleButtonWidthVp = snapshot\.titleButtonWidthVp/);
    assert.match(ui, /get captionInset\(\): number/);
    assert.match(ui, /Math\.max\(measured \+ 24, 168\)/);
    const pane = read('shell/EditorPane.ets');
    assert.match(pane, /return this\.app\.ui\.captionInset/);
    assert.doesNotMatch(pane, /\? 148 : 12/, 'caption inset must not stay hard-coded');
    const focus = read('shell/FocusWorkspace.ets');
    assert.match(focus, /return this\.app\.ui\.captionInset/);
  });
  await check('editor tool group collapses by measured width and keeps an overflow menu', async () => {
    const tools = read('shell/EditorTools.ets');
    assert.match(tools, /@Param space: number = 0/);
    assert.match(tools, /private rowWidth\(level: number\): number/);
    assert.match(tools, /private level\(\): number/);
    assert.match(tools, /if \(this\.level\(\) === 0\)/);
    for (const item of ['加粗', '斜体', '标题 1', '标题 2', '打字机', '专注写作']) {
      assert.ok(tools.includes("'" + item + "'"), 'overflow menu must keep ' + item);
    }
    // 兜底裁剪 + 不再按窗口断点拍脑袋
    assert.doesNotMatch(tools, /@Param compact: boolean/, 'compact must come from measured space');
    const pane = read('shell/EditorPane.ets');
    assert.match(pane, /EditorTools\(\{ app: this\.app, space: this\.toolSpace\(\)/);
    const shell = read('shell/AppShell.ets');
    assert.match(shell, /EditorTools\(\{ app: app, space: 260/);
    assert.doesNotMatch(shell, /EditorTools\(\{[^}]*compact:/, 'appBar must not pass the removed compact param');
    assert.match(pane, /this\.headerWidth = width/);
    const button = read('shell/TopActionButton.ets');
    assert.match(button, /@Param gapOverride: number = -1/);
    assert.match(button, /\.margin\(\{ left: this\.gap\(\), right: this\.gap\(\) \}\)/);
  });
  await check('system chrome follows the app theme instead of the OS dark mode', async () => {
    const chrome = read('utils/AppChromeMode.ets');
    assert.match(chrome, /export function rememberAppContext/);
    assert.match(chrome, /export function applyAppColorMode/);
    assert.match(chrome, /setColorMode\(/);
    assert.match(chrome, /COLOR_MODE_DARK/);
    assert.match(chrome, /COLOR_MODE_LIGHT/);
    const ui = read('store/UiStore.ets');
    assert.match(ui, /applyAppColorMode\(this\.darkMode\)/);
    assert.match(ui, /refreshDecorColorScheme\(this\.darkMode\)/);
    const ability = read('entryability/EntryAbility.ets');
    assert.match(ability, /rememberAppContext\(this\.context\.getApplicationContext\(\)\)/);
    const tools = read('shell/EditorTools.ets');
    assert.match(tools, /MenuButton\(/);
    // 列表/待办也进 ⋯ 菜单：段落下拉在 L2/L3 档会被整档收起，这两项必须另有入口
    const overflow = method(tools, 'overflowMenu');
    for (const label of ['撤销', '重做', '加粗', '斜体', '正文', '标题 1', '标题 2', '标题 3', '• 列表', '○ 待办', '打字机', '查找', '专注写作']) {
      assert.ok(overflow.includes("'" + label + "'"), 'overflow must retain ' + label);
    }
    assert.doesNotMatch(tools, /\$r\('sys\.symbol\.more'\)/, 'overflow must not use the app-grid glyph');
    const button = read('shell/TopActionButton.ets');
    assert.match(button, /@Param glyphText: string = ''/);
    assert.match(button, /Text\(this\.glyphText\)/);
  });
  await check('top action state background is a desktop rounded square, not a circle', async () => {
    const tokens = read('constants/LightTokens.ets');
    assert.match(tokens, /TOP_ICON_RADIUS: number = 8/);
    const button = read('shell/TopActionButton.ets');
    // 电脑：方形（8vp 圆角）；平板：圆形（visualSize/2）——形态必须分流
    assert.match(button, /TOP_ICON_RADIUS/);
    assert.match(button, /metrics\.circular \? metrics\.visualSize \/ 2 : TOP_ICON_RADIUS/);
    assert.match(read('constants/LightTokens.ets'), /export function topIconMetrics\(pointerPrimary: boolean, tabletMode: boolean,/);
  });
  await check('native caption buttons stay native and follow the app colour mode', async () => {
    assert.equal(fs.existsSync(path.resolve(__dirname, '../entry/src/main/ets/shell/WindowControls.ets')), false,
      'self-drawn window controls must not come back');
    const chrome = read('utils/DesktopWindowChrome.ets');
    assert.match(chrome, /setWindowTitleButtonVisible\(true, true, true\)/);
    assert.match(chrome, /export function refreshDecorColorScheme/);
    const ability = read('entryability/EntryAbility.ets');
    assert.match(ability, /refreshDecorColorScheme\(true\)/);
    assert.match(ability, /on\('windowStatusChange'/);
    assert.match(ability, /off\('windowStatusChange'/);
    const ui = read('store/UiStore.ets');
    assert.match(ui, /applyAppColorMode\(this\.darkMode\)/);
  });
  await check('tablet chrome scales up and uses circular state backgrounds', async () => {
    const ui = read('store/UiStore.ets');
    assert.match(ui, /get tabletMode\(\): boolean/);
    assert.match(ui, /const tabletLike: boolean = this\.deviceClass === DeviceClass\.TABLET \|\| this\.foldExpanded/);
    const light = read('constants/LightTokens.ets');
    assert.match(light, /TOP_ICON_SIZE_TOUCH: number = 44/);
    assert.match(light, /TOP_ICON_HIT_TABLET: number = 56/);
    assert.match(light, /TOP_ICON_FONT_TOUCH: number = 24/);
    assert.match(light, /metrics\.circular = true/);
    const button = read('shell/TopActionButton.ets');
    assert.match(button, /focusOnTouch\(this\.pointerPrimary\)/);
    const list = read('shell/DocListPane.ets');
    assert.match(list, /this\.tablet\(\) \? 28 : 20/);
    assert.match(list, /this\.tablet\(\) \? 44 : 36/);
    assert.match(list, /minHeight: this\.tabletMode \? 64 : 56/);
    const pane = read('shell/EditorPane.ets');
    assert.match(pane, /if \(this\.app\.ui\.tabletMode\) \{\n      return 56/);
    assert.match(pane, /maxWidth: 760/);
    const shell = read('shell/AppShell.ets');
    assert.match(shell, /if \(app\.ui\.tabletMode\) \{\n      return 380/);
    assert.match(shell, /breakPoint !== BreakPoint\.LG \|\| app\.ui\.tabletMode/);
    const bars = read('utils/SystemBars.ets');
    assert.match(bars, /setBars\(w, argbOf\(bgHex\), contentFor\(dark\)\)/);
  });
  await check('window chrome colour is fixed before the window exists', async () => {
    const ability = read('entryability/EntryAbility.ets');
    // 窗口创建前先按浅色建窗，避免系统深色把三键锁成白色
    assert.match(ability, /applyAppColorMode\(false\)/);
    // 深色主题才重建三键（浅色不闪原生标题栏）
    assert.match(ability, /if \(app\.ui\.darkMode\) \{\n\s+refreshDecorColorScheme\(true\)/);
    const chrome = read('utils/DesktopWindowChrome.ets');
    // style 只在"带窗口标题"时生效：显示 → 下发 → 隐藏
    const refresh = chrome.slice(chrome.indexOf('export function refreshDecorColorScheme'));
    const show = refresh.indexOf('setWindowDecorVisible(true)');
    const style = refresh.indexOf('applyDesktopDecorMetrics(w, dark)');
    const hide = refresh.indexOf('setWindowDecorVisible(false)');
    assert.ok(show >= 0 && show < style && style < hide, 'style must be applied while the decor is visible');
    // 系统栏区域必须由页面背景覆盖，而不是只给透明容器加 expandSafeArea
    assert.match(read('pages/Index.ets'), /expandSafeArea\(\[SafeAreaType\.SYSTEM\]/);
    assert.match(read('shell/AppShell.ets'), /expandSafeArea\(\[SafeAreaType\.SYSTEM\]/);
  });
  await check('menus use the native menu components instead of custom popups', async () => {
    const menu = read('shell/MenuButton.ets');
    // 系统菜单：位置 / 材质 / 动画 / 点击关闭都由系统负责（与电子邮件一致）
    assert.match(menu, /bindMenu\(this\.menuView, \{ placement: Placement\.BottomRight \}\)/);
    // 右对齐：菜单右边缘贴按钮，向左展开，不越过中栏
    assert.match(menu, /Placement\.BottomRight/);
    assert.match(menu, /Menu\(\) \{/);
    assert.match(menu, /MenuItem\(\{ content: item \}\)/);
    assert.match(menu, /this\.tabletMode \? 16 : 14/);
    // 触发器必须是普通 Stack：包在自定义组件里时点击会被内部 onClick 吃掉，菜单不弹
    assert.doesNotMatch(menu, /TopActionButton\(\{/, 'menu trigger must not wrap a custom component');
    assert.match(menu, /\.bindMenu\(this\.menuView/);
    assert.match(menu, /topIconMetrics\(this\.pointerPrimary, this\.tabletMode, this\.desktopMode\)/);
    assert.match(read('shell/DocListPane.ets'), /desktopMode: this\.app !== null && this\.app\.ui\.usesDesktopChrome/);
    assert.doesNotMatch(menu, /bindPopup\(/, 'no custom popup');
    assert.doesNotMatch(menu, /showActionMenu\(/, 'no modal action sheet');
    assert.match(read('shell/DocListPane.ets'), /MenuButton\(/);
    assert.match(read('shell/EditorTools.ets'), /MenuButton\(/);
  });
  await check('swipe actions are touch-only and follow the Notes circular layout', async () => {
    const list = read('shell/DocListPane.ets');
    // 电脑端（PC / Edge 电脑模式）没有横滑，动作只走菜单
    assert.match(list, /private canSwipe\(\): boolean \{\n    return this\.app !== null && !this\.app\.ui\.usesDesktopChrome/);
    assert.match(list, /if \(this\.canSwipe\(\)\) \{\n\s+ListItem\(\) \{\n\s+this\.docRow\(item\)/);
    // 触摸端：备忘录式圆形动作（收藏 / 灵感 / 重命名 / 删除）
    for (const name of ['star', 'lightbulb', 'square_and_pencil', 'trash']) {
      assert.ok(list.includes('sys.symbol.' + name), 'missing swipe glyph ' + name);
    }
    assert.match(list, /borderRadius\(this\.swipeCircleSize\(\) \/ 2\)/);
    // closeAllSwipeActions 在 ListScroller 上（Scroller 没有这个方法）
    assert.match(list, /private listScroller: ListScroller = new ListScroller\(\)/);
    assert.match(list, /closeAllSwipeActions\(\)/);
    assert.doesNotMatch(list, /swipeDelete\(/, 'the old full-width delete strip must be gone');
    // 右键 / 长按都是原生菜单（非模态），不再是半模态动作面板
    assert.match(list, /bindContextMenuWithResponse\(this\.rowMenuItems\(item\)\)/);
    assert.match(list, /private rowMenuItems\(item: DocItem\): MenuElement\[\]/);
    assert.doesNotMatch(list, /showRowMenu\(/, 'row menu must not be a half-modal sheet');
    assert.doesNotMatch(list, /showActionMenu\(/, 'row menu must not be a half-modal sheet');
  });
  await check('settings open as a centered half-modal sheet, not a right-side page', async () => {
    const shell = read('shell/AppShell.ets');
    assert.match(shell, /@Local showSettings: boolean = false/);
    assert.match(shell, /bindSheet\(this\.showSettings, this\.settingsSheet\(\)/);
    assert.match(shell, /preferType: SheetType\.CENTER/);
    assert.match(shell, /showClose: true/);
    assert.match(shell, /title: \{ title: '设置' \}/);
    assert.match(shell, /onWillDismiss: \(action: DismissSheetAction\)/);
    // 入口不再 push 路由
    assert.doesNotMatch(shell, /onSettings: \(\) => \{ nav\.pushPath\(\{ name: Routes\.SETTINGS \}\) \}/);
    // 设置内容统一在 shell/SettingsPanel（分组卡片版式，对齐电子邮件），两个宿主共用
    const panel = read('shell/SettingsPanel.ets');
    assert.match(panel, /export struct SettingsPanel/);
    assert.match(panel, /this\.themeTitle\(\)/);
    assert.match(panel, /this\.sectionTitle\('写作'\)/);
    assert.match(panel, /this\.themeRow\(theme\)/);
    assert.match(panel, /this\.switchRow\('打字机模式'/);
    assert.match(panel, /this\.actionRow\('恢复默认设置'/);
    assert.match(panel, /borderRadius\(this\.cardRadius\(\)\)/);
    const page = read('pages/dest/SettingsDest.ets');
    assert.match(page, /import \{ SettingsPanel \} from '\.\.\/\.\.\/shell\/SettingsPanel'/);
    assert.match(page, /SettingsPanel\(\)/);
  });
  await check('long-take transition is wired through Navigation on both shells', async () => {
    // 三方库以源码形式随仓库分发：不依赖 ohpm 安装，构建可离线复现
    const lib = read('thirdparty/ezcustomtransition/Index.ets');
    assert.match(lib, /export \{ ezCustomTransition \}/);
    assert.match(lib, /export \{ LongTakeSession \}/);
    assert.match(lib, /export \{ LongTakeTransitionDelegate \}/);
    // AbilityStage：配置变更转发
    const stage = read('entryability/MyAbilityStage.ets');
    assert.match(stage, /ezCustomTransition\.onConfigurationChanged\(\)/);
    const moduleJson = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/module.json5'), 'utf8');
    assert.match(moduleJson, /"srcEntry": "\.\/ets\/entryability\/MyAbilityStage\.ets"/);
    // EntryAbility：初始化
    assert.match(read('entryability/EntryAbility.ets'), /ezCustomTransition\.init\(windowStage\)/);
    // 两个外壳都挂 customNavContentTransition + 转场期间禁用交互
    const shell = read('shell/AppShell.ets');
    const mobile = read('shell/MobileShell.ets');
    for (const source of [shell, mobile]) {
      assert.match(source, /customNavContentTransition\(\(from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation\)/);
      assert.match(source, /onTransitionStart: \(\) => \{\s*this\.navInteractive = false/);
      assert.match(source, /\.enabled\(this\.navInteractive\)/);
      assert.match(source, /longTakeTransitionParam/);
    }
    // 目标页：delegate + session + onReady/onSizeChange
    const workspace = read('shell/WorkspaceDest.ets');
    assert.match(workspace, /LongTakeTransitionDelegate\(\{/);
    assert.match(workspace, /this\.longTakeSession\.init\(navDestContext, this\.longTakeParam/);
    // 1.0.0 由库内 WindowUtils 监听 windowSizeChange，目标页不再手动 setNewSize
    assert.match(workspace, /this\.longTakeSession\.init\(navDestContext, this\.longTakeParam/);
    assert.match(read('thirdparty/ezcustomtransition/src/main/ets/utils/WindowUtils.ets'), /on\('windowSizeChange'/);
    assert.match(workspace, /navDestinationBgColor/);
    // 触发侧：只在"真的会 push"的宿主里抓参数，宽屏三栏不抓
    const list = read('shell/DocListPane.ets');
    assert.match(list, /@Param enableLongTake: boolean = false/);
    assert.match(list, /if \(this\.enableLongTake && this\.app !== null && !this\.app\.ui\.isWide\)/);
    assert.match(list, /generateLongTakeParam\(\s*this\.getUIContext\(\), 'doc_row_' \+ item\.id/);
    assert.match(list, /\.id\('doc_row_' \+ item\.id\)/);
  });
  await check('soft keyboard avoidance is wired from avoid area to layout and caret', async () => {
    const safe = read('utils/SafeArea.ets');
    assert.match(safe, /AvoidAreaType\.TYPE_KEYBOARD/);
    assert.match(safe, /export function keyboardHeightVp\(\): number/);
    assert.match(safe, /data\.type === window\.AvoidAreaType\.TYPE_KEYBOARD/);
    assert.match(read('utils/DeviceProfile.ets'), /keyboardHeightVp: number = 0/);
    assert.match(read('utils/DeviceProfile.ets'), /next\.keyboardHeightVp = keyboardHeightVp\(\)/);
    assert.match(read('store/UiStore.ets'), /@Trace keyboardHeight: number = 0/);
    const shell = read('shell/AppShell.ets');
    // 页面让位：取 max(导航条, 键盘)，避免双重留白
    assert.match(shell, /Math\.max\(this\.safeBottom, this\.keyboardHeight\)/);
    // 关掉框架默认 OFFSET，避免与手动 padding 叠加
    assert.match(shell, /setKeyboardAvoidMode\(KeyboardAvoidMode\.NONE\)/);
    // 编辑器：高度变化（键盘开合）后把光标滚进可视区
    const editor = read('editor/flowtext/CanvasTextEditor.ets');
    assert.match(editor, /if \(heightChanged\) \{\n\s+this\.ensureCaretVisible\(this\.effectivePolicy\(\)\);/);
  });
  await check('foldable devices adopt tablet chrome when expanded', async () => {
    const profile = read('utils/DeviceProfile.ets');
    assert.match(profile, /foldable: boolean = false/);
    assert.match(profile, /foldExpanded: boolean = false/);
    assert.match(profile, /display\.isFoldable\(\)/);
    assert.match(profile, /display\.FoldStatus\.FOLD_STATUS_EXPANDED/);
    assert.match(profile, /display\.FoldStatus\.FOLD_STATUS_HALF_FOLDED/);
    assert.match(profile, /next\.foldExpanded = fold\.expanded/);
    // 半折叠不改变窗口尺寸，必须有独立的 foldStatusChange 监听并在 detach 释放
    assert.match(profile, /display\.on\('foldStatusChange'/);
    assert.match(profile, /display\.off\('foldStatusChange'/);
    const ui = read('store/UiStore.ets');
    assert.match(ui, /@Trace foldExpanded: boolean = false/);
    assert.match(ui, /this\.deviceClass === DeviceClass\.TABLET \|\| this\.foldExpanded/);
    // 折叠屏不能只靠 deviceType 判断：deviceClass 仍为 PHONE，但 tabletMode 由 foldExpanded 兜住
    assert.match(ui, /const tabletLike: boolean = this\.deviceClass === DeviceClass\.TABLET \|\| this\.foldExpanded/);
  });
  await check('Pura X View style short screens get compact chrome metrics', async () => {
    const profile = read('utils/DeviceProfile.ets');
    assert.match(profile, /shortScreen: boolean = false/);
    assert.match(profile, /cornerRadiusVp: number = 0/);
    assert.match(profile, /d\.getRoundedCorner\(\)/);
    assert.match(profile, /metrics\.heightVp < 800/);
    const ui = read('store/UiStore.ets');
    assert.match(ui, /@Trace shortScreen: boolean = false/);
    assert.match(ui, /@Trace cornerRadius: number = 0/);
    // 短屏上半模态用 MEDIUM，避免 744vp 高度下被截断
    assert.match(read('shell/AppShell.ets'), /height: this\.appShortScreen\(\) \? SheetSize\.MEDIUM : SheetSize\.LARGE/);
    // 方向策略显式声明（跟随系统自动旋转，布局只按宽度断点响应）
    const moduleJson = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/module.json5'), 'utf8');
    assert.match(moduleJson, /"orientation": "auto_rotation"/);
    // 阔直板（Pura X View）：横竖屏识别 + 紧凑 chrome + 圆角让位
    assert.match(profile, /wideBar: boolean = false/);
    assert.match(profile, /shortSide >= 400 && shortSide < 520/);
    assert.match(profile, /longSide \/ shortSide < 1\.9/);
    assert.match(ui, /@Trace wideBar: boolean = false/);
    assert.match(ui, /get cornerInset\(\): number/);
    assert.match(read('shell/MobileShell.ets'), /app\.ui\.wideBar \? 40 : WeaverMobile\.TITLEBAR_H/);
    assert.match(read('shell/EditorPane.ets'), /if \(this\.app\.ui\.wideBar\) \{\n      return 44/);
    assert.match(read('shell/WorkspaceDest.ets'), /app\.ui\.wideBar \? 48 : 52/);
  });
  await check('P0 motion: characters are instant, only the caret animates', async () => {
    const editor = read('editor/flowtext/CanvasTextEditor.ets');
    // 编辑链路不再生成逐字动画
    assert.doesNotMatch(editor, /createEditAnimations\(/);
    assert.match(editor, /this\.anims\.clear\(\)/);
    // 光标：临界阻尼弹簧 + 速度保留 + 快打档位
    assert.match(editor, /private caretl?VelX|private caretVelX/);
    assert.match(editor, /private startCaretSpring\(target: CursorState, durationMs: number, keepVelocity: boolean\)/);
    assert.match(editor, /const stiffness: number = 2400/);
    assert.match(editor, /const damping: number = 98/);
    // 连续输入：循环在跑时只改目标、不重建动画（否则每键进度归零 → 追不上字符）
    assert.match(editor, /private caretSpringLoop: boolean = false/);
    assert.match(editor, /if \(this\.caretSpringLoop\) \{[\s\S]{0,200}?return;/);
    // 快速重复输入/大跨度编辑：光标同帧到位（任何插值都会落后一格）
    assert.match(editor, /const fastRepeat: boolean = this\.lastInputTs > 0 && \(nowTs - this\.lastInputTs\) < 90/);
    assert.match(editor, /if \(canAnimate && !fastRepeat\)/);
    assert.match(editor, /gapVp > charGap \* 2\.5 \? 220 : 140/);
    // 代际守卫：stop/重建后丢弃旧动画残余帧（修"光标乱飞"）
    assert.match(editor, /private caretSpringEpoch: number = 0/);
    assert.match(editor, /if \(epoch !== this\.caretSpringEpoch\)/);
    assert.match(editor, /this\.stopCaretAnimation\(caretTarget\);/);
    // 方向键连按同样同帧到位
    assert.match(editor, /const navRepeat: boolean = this\.lastNavTs > 0 && \(nowTs - this\.lastNavTs\) < 80/);
    // 拖手柄必须 1:1：拖动前停掉光标弹簧
    const stops = editor.match(/this\.stopCaretAnimation\(\);\s*\n\s*this\.selMgr\.beginHandleDrag\(handle\);/g) || [];
    assert.ok(stops.length >= 2, 'both mouse and touch handle drag must stop caret animation');
  });
  await check('focus mode uses a shared-element long-take transition', async () => {
    const helper = read('shell/FocusTransition.ets');
    assert.match(helper, /export const FOCUS_EDITOR_ID: string = 'we-focus-editor'/);
    assert.match(helper, /ctx\.animateTo\(\{ duration: FOCUS_DURATION, curve: curves\.springMotion\(0\.6, 0\.85\) \}/);
    // 两个状态的编辑区共用同一 id，切换时系统把旧位置平滑放大到新位置
    assert.match(read('shell/WorkspaceDest.ets'), /\.geometryTransition\(FOCUS_EDITOR_ID\)/);
    assert.match(read('shell/FocusWorkspace.ets'), /\.geometryTransition\(FOCUS_EDITOR_ID\)/);
    // 所有入口都走动画版切换，不再直接改状态
    for (const file of ['shell/EditorPane.ets', 'shell/EditorTools.ets', 'shell/WorkspaceDest.ets']) {
      assert.match(read(file), /toggleFocusAnimated\(this\.getUIContext\(\)\)/);
    }
    assert.match(read('shell/FocusWorkspace.ets'), /exitFocusAnimated\(this\.getUIContext\(\)\)/);
  });
  await check('toolbar exposes paragraph style as a value dropdown', async () => {
    const tools = read('shell/EditorTools.ets');
    assert.match(tools, /paragraphStyleMenu\(\)/);
    assert.match(tools, /Text\(this\.paragraphLabel\(\)\)/);
    assert.match(tools, /MenuItem\(\{ content: '正文' \}\)/);
    assert.match(tools, /MenuItem\(\{ content: '标题 2' \}\)/);
    assert.match(tools, /bindMenu\(this\.paragraphMenuView, \{ placement: Placement\.BottomLeft/);
    // 当前段落样式回读（下拉显示要跟光标所在段一致）
    assert.match(read('editor/flowtext/CanvasTextEditor.ets'), /paragraphLevel\(\): number \{\n    return this\.doc\.headingAt/);
    // 悬停提示
    assert.match(read('shell/TopActionButton.ets'), /bindPopup\(this\.showTip, \{/);
    assert.match(read('shell/TopActionButton.ets'), /this\.showTip = isHover && this\.isEnabled && this\.pointerPrimary/);
  });
  await check('document title block shows big title, project chip and meta', async () => {
    const pane = read('shell/EditorPane.ets');
    assert.match(pane, /\.fontSize\(28\)\.fontWeight\(FontWeight\.Medium\)/);
    assert.match(pane, /private projectName\(\): string/);
    assert.match(pane, /this\.app\.project\.currentBook/);
    assert.match(pane, /accessibilityText\('所属项目：' \+ this\.projectName\(\)\)/);
    // 标题区在 Canvas 之上固定，正文滚动时不动（吸顶）
    assert.match(pane, /this\.editorHeader\(\)\n\s*\/\/ 轻量文稿标题/);
    assert.match(pane, /this\.docStatus\(\)/);
  });
  await check('toolbar fades out when idle and wakes on activity', async () => {
    const tools = read('shell/EditorTools.ets');
    assert.match(tools, /@Local idle: boolean = false/);
    assert.match(tools, /@Monitor\('app\.ui\.selectionTick'\)/);
    assert.match(tools, /this\.idle = true/);
    assert.match(tools, /setTimeout\(\(\) => \{[\s\S]{0,120}?\}, 3000\)/);
    assert.match(tools, /\.opacity\(this\.idle \? 0\.3 : 1\)/);
    assert.match(tools, /clearTimeout\(this\.idleTimer\)/);
  });
  await check('focus mode centers a 720vp column and offers an exit pill plus Esc', async () => {
    const focus = read('shell/FocusWorkspace.ets');
    assert.match(focus, /\.constraintSize\(\{ maxWidth: 720 \}\)/);
    assert.match(focus, /constraintSize\(\{ maxWidth: 760 \}\)/);
    assert.match(focus, /Text\('退出专注'\)/);
    assert.match(focus, /opacity\(this\.exitHovered \? 1 : 0\.72\)/);
    assert.match(focus, /KeyCode\.KEYCODE_ESCAPE/);
    assert.match(focus, /Stack\(\{ alignContent: Alignment\.BottomEnd \}\)/);
  });
  await check('inline styles apply to the whole paragraph when the caret is collapsed', async () => {
    const editor = read('editor/flowtext/CanvasTextEditor.ets');
    assert.match(editor, /const bounds: number\[\] = this\.doc\.paragraphBounds\(this\.doc\.caretOffset\)/);
    // 撤销/重做走控制器（与 Ctrl+Z 同链路）
    const tools = read('shell/EditorTools.ets');
    assert.match(tools, /this\.app\.ui\.editorController\.undo\(\)/);
    assert.match(tools, /this\.app\.ui\.editorController\.redo\(\)/);
  });
  await check('settings show about, service terms and privacy entries', async () => {
    const panel = read('shell/SettingsPanel.ets');
    assert.match(panel, /this\.sectionTitle\('关于'\)/);
    assert.match(panel, /this\.valueRow\('版本', '1\.0\.0'\)/);
    assert.match(panel, /this\.actionRow\('服务协议'/);
    assert.match(panel, /this\.actionRow\('隐私政策'/);
    assert.match(panel, /promptAction\.showDialog\(\{ title: title, message: body/);
  });
  await check('settings merge into the sidebar account row', async () => {
    const sidebar = read('shell/ProjectSidebar.ets');
    // 左下角只有账号行：账号 + 设置已合并到设置页，不再单列「设置」行或账号半模态
    assert.match(sidebar, /\.edgeEffect\(EdgeEffect\.Spring\)[\s\S]{0,1600}?Text\('请登录'\)/);
    assert.doesNotMatch(sidebar, /Text\('设置'\)/);
    assert.doesNotMatch(sidebar, /bindSheet\(this\.showAccount/);
    assert.match(sidebar, /\.onClick\(\(\) => \{\s*this\.onSettings\(\)/);
    // 头像由共享组件渲染：有自定义图片显示图片，否则系统占位人像
    assert.match(sidebar, /UserAvatar\(\{ avatarSize: this\.tablet\(\) \? 28 : 26 \}\)/);
    assert.match(read('shell/UserAvatar.ets'), /sys\.symbol\.person_crop_circle_dashed/);
    assert.match(read('shell/UserAvatar.ets'), /sys\.symbol\.person_crop_circle_fill_1/);
    assert.match(read('shell/UserAvatar.ets'), /AvatarService\.toImageSrc/);
    assert.match(sidebar, /Text\(this\.nickname\(\)\)/);

    // 设置页顶部即账号分组：登录 / 退出都在这里；明确不提供上传头像
    const panel = read('shell/SettingsPanel.ets');
    assert.match(panel, /this\.sectionTitle\('账号'\)/);
    assert.match(panel, /this\.accountSection\(\)/);
    assert.match(panel, /await app\.ui\.signIn\(this\.loginName\)/);
    assert.match(panel, /await app\.ui\.signOut\(\)/);
    // 头像只用系统占位图标：没有选图/上传入口
    // 头像可上传：图库选择 → 复制进沙箱 → 记路径
    assert.match(panel, /AvatarService\.pickAndCopy\(context\.filesDir\)/);
    assert.match(panel, /await app\.ui\.setAvatar\(path\)/);
    assert.match(panel, /this\.avatarActions\(\)/);
    assert.match(panel, /Text\('更换头像'\)/);
    // 外观分组用调色板图标
    assert.match(panel, /sys\.symbol\.paintpalette/);

    // 昵称落首选项：登录后重启仍显示
    assert.match(read('store/UiStore.ets'), /this\.nickname = await prefs\.getNickname\(\)/);
    assert.match(read('store/UiStore.ets'), /await prefs\.setNickname\(trimmed\)/);

    // 中栏（文稿列表）不再有独立设置入口；窗口头应用菜单也只剩导出/导入
    assert.match(read('shell/DocListPane.ets'), /items: \['导出', '导入'\]/);
    assert.doesNotMatch(read('shell/DocListPane.ets'), /@Event onSettings/);
    assert.doesNotMatch(read('shell/DesktopTitleBar.ets'), /text: '设置'/);

    // 宽屏/手机两种壳都把账号行接上设置
    assert.match(read('shell/AppShell.ets'), /onSettings: \(\) => \{ this\.showSettings = true \}/);
    assert.match(read('shell/MobileShell.ets'), /onSettings: \(\) => nav\.pushPath\(\{ name: Routes\.SETTINGS \}\)/);
  });
  await check('avatar upload copies the picked photo into the sandbox', async () => {
    const service = read('utils/AvatarService.ets');
    // 系统图库单选，且必须复制：媒体库 URI 的读权限只在本次会话有效
    assert.match(service, /import \{ photoAccessHelper \} from '@kit\.MediaLibraryKit'/);
    assert.match(service, /options\.MIMEType = photoAccessHelper\.PhotoViewMIMETypes\.IMAGE_TYPE/);
    assert.match(service, /options\.maxSelectNumber = 1/);
    assert.match(service, /filesDir \+ AVATAR_PREFIX \+ Date\.now\(\)/);
    assert.match(service, /fs\.copyFileSync\(src\.fd, out\.fd\)/);
    // 只接受图片后缀，未知/超长后缀回落到 jpg
    assert.match(service, /ext === '\.jpg'/);
    assert.match(service, /return DEFAULT_EXT/);
    // 换/移除时清理旧文件
    assert.match(service, /static removeFile\(path: string\): void/);
    // 路径落首选项；启动时校验文件仍存在（防死路径）
    assert.match(read('store/UiStore.ets'), /this\.avatarPath = await prefs\.getAvatarPath\(\)/);
    assert.match(read('store/UiStore.ets'), /AvatarService\.exists\(this\.avatarPath\)/);
    assert.match(read('utils/PreferenceHelper.ets'), /KEY_AVATAR: string = 'weaver_avatar'/);
    // 上传入口不依赖登录态：本机即可换头像，昵称再单独设置
    assert.match(read('shell/SettingsPanel.ets'), /this\.rowDivider\(\)\s*this\.avatarActions\(\)/);
    assert.match(read('shell/UserAvatar.ets'), /return app\.ui\.avatarPath !== ''/);
    // 官方沙箱 URI 转换（Image 不认文件系统绝对路径）
    assert.match(service, /fileUri\.getUriFromPath\(path\)/);
  });
  await check('more buttons use the four-dot HarmonyOS symbol', async () => {
    // 全项目不再用西文三点「⋯」，统一为鸿蒙四点 dot_grid_2x2
    for (const file of ['MenuButton.ets', 'EditorPane.ets', 'WorkspaceDest.ets', 'DocListPane.ets']) {
      assert.doesNotMatch(read('shell/' + file), /'⋯'/, file + ' still renders a three-dot glyph');
    }
    for (const file of ['MenuButton.ets', 'EditorPane.ets', 'WorkspaceDest.ets']) {
      assert.doesNotMatch(read('shell/' + file), /sys\.symbol\.more\b/);
    }
    assert.match(read('shell/MenuButton.ets'), /sys\.symbol\.dot_grid_2x2/);
    assert.match(read('shell/EditorPane.ets'), /sys\.symbol\.dot_grid_2x2/);
    assert.match(read('shell/WorkspaceDest.ets'), /sys\.symbol\.dot_grid_2x2/);
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
