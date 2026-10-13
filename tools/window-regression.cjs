// Node 24+. Execute desktop window configuration, controls and ability lifecycle source.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function compile(source) {
  return stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
    .replace(/\bexport\s+default\s+/g, '').replace(/\bexport\s+/g, ''), { mode: 'transform' });
}
function method(source, name) {
  const match = source.match(new RegExp('^  (?:private )?' + name + '\\([\\s\\S]*?^  }', 'm'));
  assert.ok(match, 'production method ' + name);
  return match[0];
}
const statuses = { FLOATING: 0, MAXIMIZE: 1, FULL_SCREEN: 2, SPLIT_SCREEN: 3 };
const mouseActions = { Press: 1, Release: 2, Move: 3 };
const mouseButtons = { Left: 0, Right: 1, Middle: 2 };
const touchTypes = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
const storage = new Map();
const warnings = [];
const errors = [];
const rejected = [];
const onUnhandled = error => rejected.push(error);
process.on('unhandledRejection', onUnhandled);
const deviceInfo = { deviceType: '2in1' };
const context = vm.createContext({
  window: { WindowStatusType: statuses }, MouseAction: mouseActions, MouseButton: mouseButtons, TouchType: touchTypes,
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Logger: { info() {}, warn: message => warnings.push(message), error: message => errors.push(message) },
  deviceInfo, UIAbility: class {},
  ConfigurationConstant: { ColorMode: { COLOR_MODE_LIGHT: 0, COLOR_MODE_DARK: 1, COLOR_MODE_NOT_SET: -1 } },
  prefs: { async init() {}, async isDarkExplicit() { return true; }, async isFirstLaunch() { return false; } },
  app: { ui: { syncSystemBars() {}, async applySystemDarkMode() {} }, async flushAll() {}, destroy() {} },
  setAppContext() {}
});
vm.runInContext(compile(read('utils/DesktopWindowChrome.ets')), context);
const barSource = read('shell/PcWindowBar.ets');
vm.runInContext(compile('class WindowBarProbe {\n' + ['win', 'startMove', 'minimize', 'toggleMaximize', 'close',
  'onTitleTouch', 'onTitleMouse'].map(name => method(barSource, name)).join('\n') + '\n}'), context);
vm.runInContext(compile(read('entryability/EntryAbility.ets')), context);
const api = vm.runInContext('({configureDesktopChrome, WindowBarProbe, EntryAbility})', context);
const settle = () => new Promise(resolve => setImmediate(resolve));
function nativeWindow(failures = {}) {
  const calls = [];
  const native = { calls, status: statuses.FLOATING };
  function invoke(name, args, asynchronous = true) {
    calls.push([name, ...args]);
    if (failures[name] === 'throw') throw new Error(name + ' sync failure');
    if (failures[name] === 'reject') return Promise.reject(new Error(name + ' async failure'));
    return asynchronous ? Promise.resolve() : undefined;
  }
  native.setWindowDecorVisible = (...args) => invoke('setWindowDecorVisible', args, false);
  native.setWindowTitleButtonVisible = (...args) => invoke('setWindowTitleButtonVisible', args, false);
  native.setWindowDecorHeight = (...args) => invoke('setWindowDecorHeight', args, false);
  native.setTitleAndDockHoverShown = (...args) => invoke('setTitleAndDockHoverShown', args);
  native.setWindowLayoutFullScreen = (...args) => invoke('setWindowLayoutFullScreen', args);
  native.getWindowStatus = () => { invoke('getWindowStatus', [], false); return native.status; };
  for (const name of ['startMoving', 'minimize', 'maximize', 'recover', 'restore', 'destroyWindow']) {
    native[name] = (...args) => invoke(name, args);
  }
  return native;
}
function bar(native) {
  if (native === undefined) storage.delete('mainWindow');
  else storage.set('mainWindow', native);
  return new api.WindowBarProbe();
}
function chromeCalls(native) {
  return native.calls.filter(call => ['setWindowDecorVisible', 'setWindowTitleButtonVisible', 'setWindowDecorHeight', 'setTitleAndDockHoverShown'].includes(call[0]));
}
function stage(native) {
  return { loaded: [], callbacks: [], getMainWindowSync() { return native; },
    loadContent(url, callback) { this.loaded.push(url); this.callbacks.push(callback); } };
}
function ability() {
  const result = new api.EntryAbility();
  result.context = { config: { colorMode: 0 }, getApplicationContext() { return { setColorMode() {} }; } };
  return result;
}
let count = 0;
async function check(name, action) {
  warnings.length = 0;
  errors.length = 0;
  await action();
  await settle();
  assert.equal(rejected.length, 0, 'no window operation may escape as an unhandled rejection');
  count++;
  console.log('PASS ' + name);
}
(async () => {
  await check('custom chrome disables native title and title hover while keeping dock', async () => {
    const native = nativeWindow();
    api.configureDesktopChrome(native);
    await settle();
    assert.deepEqual(native.calls, [['setWindowDecorVisible', false], ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
  });
  await check('a decor failure does not skip the separate title-hover configuration', async () => {
    const native = nativeWindow({ setWindowDecorVisible: 'throw' });
    api.configureDesktopChrome(native);
    await settle();
    assert.deepEqual(native.calls, [['setWindowDecorVisible', false], ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
    assert.equal(warnings.length, 1);
  });
  await check('a native title-button failure does not skip title-hover configuration', async () => {
    const native = nativeWindow({ setWindowTitleButtonVisible: 'throw' });
    api.configureDesktopChrome(native);
    await settle();
    assert.deepEqual(native.calls, [['setWindowDecorVisible', false], ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
    assert.equal(warnings.length, 1);
  });
  await check('both synchronous and asynchronous title-hover failures are contained', async () => {
    for (const failure of ['throw', 'reject']) {
      const before = warnings.length;
      const native = nativeWindow({ setTitleAndDockHoverShown: failure });
      api.configureDesktopChrome(native);
      await settle();
      assert.equal(warnings.length, before + 1);
      assert.equal(native.calls[0][0], 'setWindowDecorVisible');
    }
  });
  await check('window controls are safe when no main window is available', () => {
    const probe = bar(undefined);
    for (const name of ['startMove', 'minimize', 'toggleMaximize', 'close']) probe[name]();
    assert.equal(warnings.length, 0);
  });
  await check('maximize and recover complete before reapplying all three native chrome settings', async () => {
    for (const [status, expected] of [[statuses.MAXIMIZE, 'recover'], [statuses.FULL_SCREEN, 'recover'], [statuses.FLOATING, 'maximize']]) {
      const native = nativeWindow();
      native.status = status;
      bar(native).toggleMaximize();
      await settle();
      assert.deepEqual(native.calls.map(call => call[0]), ['getWindowStatus', expected,
        'setWindowDecorVisible', 'setWindowTitleButtonVisible', 'setTitleAndDockHoverShown']);
      assert.deepEqual(chromeCalls(native), [['setWindowDecorVisible', false],
        ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
    }
  });
  await check('pending maximize and recover operations do not configure native chrome prematurely', async () => {
    for (const [status, operation] of [[statuses.MAXIMIZE, 'recover'], [statuses.FLOATING, 'maximize']]) {
      const native = nativeWindow();
      native.status = status;
      let finish;
      native[operation] = () => {
        native.calls.push([operation]);
        return new Promise(resolve => { finish = resolve; });
      };
      bar(native).toggleMaximize();
      await settle();
      assert.equal(chromeCalls(native).length, 0);
      finish();
      await settle();
      assert.equal(chromeCalls(native).length, 3);
    }
  });
  await check('touch dragging starts only on pointer down', () => {
    const native = nativeWindow();
    const probe = bar(native);
    for (const type of [touchTypes.Move, touchTypes.Up, touchTypes.Cancel, touchTypes.Down]) probe.onTitleTouch({ type });
    assert.deepEqual(native.calls, [['startMoving']]);
  });
  await check('mouse dragging starts only on a left-button press', () => {
    const native = nativeWindow();
    const probe = bar(native);
    for (const event of [
      { action: mouseActions.Press, button: mouseButtons.Right },
      { action: mouseActions.Press, button: mouseButtons.Middle },
      { action: mouseActions.Release, button: mouseButtons.Left },
      { action: mouseActions.Move, button: mouseButtons.Left },
      { action: mouseActions.Press, button: mouseButtons.Left }
    ]) probe.onTitleMouse(event);
    assert.deepEqual(native.calls, [['startMoving']]);
  });
  await check('all native control promise rejections are handled', async () => {
    for (const [methodName, operation, status] of [['startMove', 'startMoving', statuses.FLOATING],
      ['minimize', 'minimize', statuses.FLOATING], ['toggleMaximize', 'maximize', statuses.FLOATING],
      ['toggleMaximize', 'recover', statuses.MAXIMIZE], ['close', 'destroyWindow', statuses.FLOATING]]) {
      const before = warnings.length;
      const native = nativeWindow({ [operation]: 'reject' });
      native.status = status;
      bar(native)[methodName]();
      await settle();
      assert.equal(warnings.length, before + 1, operation);
      assert.match(warnings.at(-1), new RegExp(operation));
      assert.equal(chromeCalls(native).length, 0, operation + ' failure must not apply success configuration');
    }
  });
  await check('all native control synchronous failures are handled', () => {
    for (const [methodName, operation, status] of [['startMove', 'startMoving', statuses.FLOATING],
      ['minimize', 'minimize', statuses.FLOATING], ['toggleMaximize', 'maximize', statuses.FLOATING],
      ['toggleMaximize', 'recover', statuses.FULL_SCREEN], ['close', 'destroyWindow', statuses.FLOATING]]) {
      const before = warnings.length;
      const native = nativeWindow({ [operation]: 'throw' });
      native.status = status;
      bar(native)[methodName]();
      assert.equal(warnings.length, before + 1, operation);
    }
  });
  await check('failed status reads do not accidentally maximize or restore', () => {
    const native = nativeWindow({ getWindowStatus: 'throw' });
    bar(native).toggleMaximize();
    assert.deepEqual(native.calls, [['getWindowStatus']]);
    assert.equal(warnings.length, 1);
  });
  await check('desktop chrome is configured only after UI content successfully loads', async () => {
    deviceInfo.deviceType = '2in1';
    const native = nativeWindow();
    const windowStage = stage(native);
    const entry = ability();
    entry.onWindowStageCreate(windowStage);
    assert.equal(chromeCalls(native).length, 0);
    entry.onForeground();
    assert.equal(chromeCalls(native).length, 0, 'early foreground is not UI readiness');
    await settle();
    assert.deepEqual(windowStage.loaded, ['pages/Index']);
    assert.equal(chromeCalls(native).length, 0, 'starting loadContent is not successful loading');
    windowStage.callbacks[0]({ code: 0 });
    assert.equal(entry.contentReady, true);
    assert.deepEqual(chromeCalls(native), [['setWindowDecorVisible', false], ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
  });
  await check('failed UI content loading leaves desktop chrome unconfigured', async () => {
    deviceInfo.deviceType = '2in1';
    const native = nativeWindow();
    const windowStage = stage(native);
    const entry = ability();
    entry.onWindowStageCreate(windowStage);
    await settle();
    windowStage.callbacks[0]({ code: 1, message: 'load failed' });
    entry.onForeground();
    assert.equal(entry.contentReady, false);
    assert.equal(chromeCalls(native).length, 0);
    assert.equal(errors.length, 1);
  });
  await check('phone and tablet lifecycle never disables native desktop chrome', async () => {
    for (const deviceType of ['phone', 'tablet']) {
      deviceInfo.deviceType = deviceType;
      const native = nativeWindow();
      const windowStage = stage(native);
      const entry = ability();
      entry.onWindowStageCreate(windowStage);
      await settle();
      windowStage.callbacks[0]({ code: 0 });
      entry.onForeground();
      assert.equal(entry.contentReady, true);
      assert.equal(entry.isDesktop, false);
      assert.equal(storage.get('isPcDevice'), false);
      assert.equal(chromeCalls(native).length, 0);
    }
  });
  await check('ready foreground reapplies desktop configuration and destruction clears readiness', async () => {
    deviceInfo.deviceType = '2in1';
    const native = nativeWindow();
    const windowStage = stage(native);
    const entry = ability();
    entry.onWindowStageCreate(windowStage);
    await settle();
    windowStage.callbacks[0]({ code: 0 });
    entry.onForeground();
    assert.equal(chromeCalls(native).length, 6);
    entry.onWindowStageDestroy();
    assert.equal(entry.contentReady, false);
    assert.equal(entry.mainWindow, null);
    entry.onForeground();
    assert.equal(chromeCalls(native).length, 6);
  });
  await check('late callbacks from destroyed or replaced windows cannot configure stale chrome', async () => {
    deviceInfo.deviceType = '2in1';
    const entry = ability();
    const oldWindow = nativeWindow();
    const oldStage = stage(oldWindow);
    entry.onWindowStageCreate(oldStage);
    await settle();
    entry.onWindowStageDestroy();
    oldStage.callbacks[0]({ code: 0 });
    assert.equal(chromeCalls(oldWindow).length, 0);
    assert.equal(entry.contentReady, false);
    const nextWindow = nativeWindow();
    const nextStage = stage(nextWindow);
    entry.onWindowStageCreate(nextStage);
    await settle();
    oldStage.callbacks[0]({ code: 0 });
    assert.equal(chromeCalls(oldWindow).length, 0);
    assert.equal(entry.contentReady, false);
    nextStage.callbacks[0]({ code: 0 });
    assert.equal(chromeCalls(nextWindow).length, 3);
  });
  console.log(`Window regression: ${count} checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  process.removeListener('unhandledRejection', onUnhandled);
});
