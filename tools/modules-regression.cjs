// Node 24+. 分包骨架的静态守卫（P4）
//
// 不跑构建（构建由 tools/verify.sh 负责），只锁三件事：
//   1) 三个模块在工程里被正确声明（HAR / HSP / 入口依赖）；
//   2) 依赖方向不倒（可选包与契约包不许反向依赖 entry）；
//   3) 入口真的引用了核心运行时（否则 HSP 会被当成"没用到"而不打包）。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

let pass = 0;
function check(name, action) {
  action();
  pass++;
  console.log('PASS ' + name);
}

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    const rel = dir + '/' + entry.name;
    if (entry.isDirectory()) {
      if (entry.name === 'build' || entry.name === 'oh_modules') {
        continue;
      }
      out.push(...walk(rel));
    } else if (entry.name.endsWith('.ets') || entry.name.endsWith('.ts')) {
      out.push(rel);
    }
  }
  return out;
}

check('every module is registered with the default product', () => {
  const profile = read('build-profile.json5');
  for (const name of ['entry', 'feature_contracts', 'core_runtime', 'structure_feature']) {
    assert.match(profile, new RegExp('"name": "' + name + '"'), name + ' must be listed in modules');
  }
  // 没有 applyToProducts 的模块不会被放进 app 包（第一次就是这样漏掉 HSP 的）
  assert.equal((profile.match(/applyToProducts/g) || []).length >= 4, true,
    'every module needs applyToProducts so the app bundle contains it');
});

check('module types match their packaging role', () => {
  assert.match(read('feature_contracts/src/main/module.json5'), /"type": "har"/,
    'contracts must stay a static HAR');
  assert.match(read('feature_contracts/hvigorfile.ts'), /harTasks/);
  for (const hsp of ['core_runtime', 'structure_feature']) {
    const source = read(hsp + '/src/main/module.json5');
    assert.match(source, /"type": "shared"/, hsp + ' must be an HSP');
    assert.match(source, /"deliveryWithInstall": true/, hsp + ' must ship with the app');
    assert.match(read(hsp + '/hvigorfile.ts'), /hspTasks/);
  }
});

check('entry consumes the runtime, the contracts and the structure package', () => {
  const pkg = read('entry/oh-package.json5');
  assert.match(pkg, /"core_runtime": "file:\.\.\/core_runtime"/);
  assert.match(pkg, /"feature_contracts": "file:\.\.\/feature_contracts"/);
  assert.match(pkg, /"structure_feature": "file:\.\.\/structure_feature"/);
  assert.match(read('entry/src/main/ets/shell/AppShell.ets'), /from 'core_runtime'/,
    'a runtime nobody imports is not packaged into the app');
  assert.match(read('entry/src/main/ets/shell/AppShell.ets'), /from 'structure_feature'/,
    'the structure page must be imported by the host or it is never packaged');
  assert.match(read('core_runtime/Index.ets'), /featureCatalog/);
  assert.match(read('structure_feature/Index.ets'), /StructurePage/);
});

check('contracts stay stateless and nothing depends back on entry', () => {
  const contractFiles = walk('feature_contracts/src');
  for (const file of contractFiles) {
    const source = read(file);
    assert.ok(!/from 'entry'|from '\.\.\/entry'/.test(source), file + ' must not import entry');
    assert.ok(!/export (const|let) .*new /.test(source), file + ' must not export shared mutable state');
  }
  const featureFiles = walk('core_runtime/src').concat(walk('structure_feature/src')).concat(walk('feature_contracts/src'));
  for (const file of featureFiles) {
    const source = read(file);
    assert.ok(!/from ['"]entry/.test(source), file + ' must not depend on the host HAP');
    assert.ok(!/from '(board_feature|novel_feature|research_feature)'/.test(source),
      file + ' must not depend on a sibling feature package');
  }
  // 方向：core_runtime / structure_feature -> feature_contracts（单向）
  assert.match(read('core_runtime/oh-package.json5'), /"feature_contracts": "file:\.\.\/feature_contracts"/);
  assert.match(read('structure_feature/oh-package.json5'), /"feature_contracts": "file:\.\.\/feature_contracts"/);
  assert.match(read('structure_feature/oh-package.json5'), /"core_runtime": "file:\.\.\/core_runtime"/);
  assert.ok(!fs.readFileSync(path.join(root, 'feature_contracts/oh-package.json5'), 'utf8').includes('core_runtime'),
    'contracts must not depend on the runtime');
});

check('the structure package only talks to the host through core_runtime', () => {
  const page = read('structure_feature/src/main/ets/pages/StructurePage.ets');
  assert.match(page, /outlineService\(\)\.current\(\)/, 'reads the snapshot published by the host');
  assert.match(page, /requestReveal\(/, 'asks the host to move the caret instead of touching the editor');
  assert.ok(!/editorController|CanvasTextEditor|EditorStore/.test(page),
    'the feature package must not reach into the editor internals');
  // 连线/节点不抢命中，否则点节点会点到线上
  assert.match(page, /hitTestBehavior\(HitTestMode\.None\)/);
});

check('the host publishes the outline before opening the map', () => {
  const pane = read('entry/src/main/ets/shell/EditorPane.ets');
  assert.match(pane, /buildOutlineSnapshotFromModel\(/);
  assert.match(pane, /reconcileDocument\(/, 'snapshot ids must come from the reconciled paragraph model');
  assert.match(pane, /outlineService\(\)\.publish\(/);
  assert.match(pane, /enterStructure\(\)/);
  const shell = read('entry/src/main/ets/shell/AppShell.ets');
  assert.match(shell, /app\.ui\.structureOpen/, 'the shell renders the map as a full-window branch');
  assert.match(shell, /takeReveal\(\)/, 'closing the map applies the requested jump');
});

check('right-side surfaces keep clear of the native caption buttons', () => {
  // 桌面自由窗口下三键由系统画在右上角、压在页面之上：所有贴右的全高面板都得让位
  const map = read('structure_feature/src/main/ets/pages/StructurePage.ets');
  assert.match(map, /@Param captionInset: number = 0/);
  assert.match(map, /right: 16 \+ this\.captionInset/);
  const library = read('entry/src/main/ets/shell/CardLibrary.ets');
  assert.match(library, /@Param captionInset: number = 0/);
  assert.match(library, /WeaverSpacing\.LG \+ this\.captionInset/);
  const outline = read('entry/src/main/ets/shell/OutlinePanel.ets');
  assert.match(outline, /8 \+ this\.captionInset/);
});

check('feature catalog surfaces the package state', () => {
  assert.match(read('core_runtime/Index.ets'), /featureStatuses/);
  const settings = read('entry/src/main/ets/shell/SettingsPanel.ets');
  assert.match(settings, /from 'core_runtime'/);
  assert.match(settings, /featureStatuses\(\)/);
  assert.match(settings, /扩展功能/);
});

check('the map edits through commands, never through the host store', () => {
  const page = read('structure_feature/src/main/ets/pages/StructurePage.ets');
  assert.match(page, /outlineService\(\)\.dispatch\(/, 'structure package sends commands');
  assert.match(page, /new OutlineCommand\(/, 'commands are plain data from the contract package');
  assert.ok(!/applyGeneratedContent|EditorStore|documentSession/.test(page),
    'the feature package must not touch the editor or the repository');
  const pane = read('entry/src/main/ets/shell/EditorPane.ets');
  assert.match(pane, /outlineService\(\)\.setCommandHandler\(applyOutlineCommand\)/,
    'the host registers the command handler before opening the map');
});

console.log('Modules regression: ' + pass + ' checks passed');