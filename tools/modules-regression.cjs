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

check('three modules are registered with the default product', () => {
  const profile = read('build-profile.json5');
  for (const name of ['entry', 'feature_contracts', 'core_runtime']) {
    assert.match(profile, new RegExp('"name": "' + name + '"'), name + ' must be listed in modules');
  }
  // 没有 applyToProducts 的模块不会被放进 app 包（第一次就是这样漏掉 HSP 的）
  assert.equal((profile.match(/applyToProducts/g) || []).length >= 3, true,
    'every module needs applyToProducts so the app bundle contains it');
});

check('module types match their packaging role', () => {
  assert.match(read('feature_contracts/src/main/module.json5'), /"type": "har"/,
    'contracts must stay a static HAR');
  const runtime = read('core_runtime/src/main/module.json5');
  assert.match(runtime, /"type": "shared"/, 'core_runtime must be an HSP');
  assert.match(runtime, /"deliveryWithInstall": true/, 'HSP must ship with the app');
  assert.match(read('core_runtime/hvigorfile.ts'), /hspTasks/);
  assert.match(read('feature_contracts/hvigorfile.ts'), /harTasks/);
});

check('entry consumes the runtime and the contracts', () => {
  const pkg = read('entry/oh-package.json5');
  assert.match(pkg, /"core_runtime": "file:\.\.\/core_runtime"/);
  assert.match(pkg, /"feature_contracts": "file:\.\.\/feature_contracts"/);
  assert.match(read('entry/src/main/ets/shell/AppShell.ets'), /from 'core_runtime'/,
    'a runtime nobody imports is not packaged into the app');
  assert.match(read('core_runtime/Index.ets'), /featureCatalog/);
});

check('contracts stay stateless and nothing depends back on entry', () => {
  const contractFiles = walk('feature_contracts/src');
  for (const file of contractFiles) {
    const source = read(file);
    assert.ok(!/from 'entry'|from '\.\.\/entry'/.test(source), file + ' must not import entry');
    assert.ok(!/export (const|let) .*new /.test(source), file + ' must not export shared mutable state');
  }
  for (const file of walk('core_runtime/src').concat(walk('feature_contracts/src'))) {
    assert.ok(!/from ['"]entry/.test(read(file)), file + ' must not depend on the host HAP');
  }
  // 方向：core_runtime -> feature_contracts（单向）
  assert.match(read('core_runtime/oh-package.json5'), /"feature_contracts": "file:\.\.\/feature_contracts"/);
  assert.ok(!fs.readFileSync(path.join(root, 'feature_contracts/oh-package.json5'), 'utf8').includes('core_runtime'),
    'contracts must not depend on the runtime');
});

console.log('Modules regression: ' + pass + ' checks passed');
