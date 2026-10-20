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
// DeviceProfile 的受控替身：标题栏只订阅/通知它，DeviceProfile 本身由 device-profile-regression.cjs 覆盖。
const profile = {
  changes: 0, pointerCalls: 0, listeners: [],
  onChange(cb) {
    this.listeners.push(cb);
    return () => { const index = this.listeners.indexOf(cb); if (index >= 0) this.listeners.splice(index, 1); };
  },
  refresh() { this.changes++; },
  notePointerActivity() { this.pointerCalls++; },
  emit(snapshot) { this.listeners.slice().forEach(cb => cb(snapshot)); },
  detach() {},
  reset() { this.changes = 0; this.pointerCalls = 0; this.listeners.length = 0; }
};
const context = vm.createContext({
  window: { WindowStatusType: statuses, WindowStageEventType: { ACTIVE: 1 } }, MouseAction: mouseActions, MouseButton: mouseButtons, TouchType: touchTypes,
  AppStorage: { delete: key => storage.delete(key), get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Logger: { info() {}, warn: message => warnings.push(message), error: message => errors.push(message) },
  deviceInfo, deviceProfile: profile, UIAbility: class {},
  ConfigurationConstant: { ColorMode: { COLOR_MODE_LIGHT: 0, COLOR_MODE_DARK: 1, COLOR_MODE_NOT_SET: -1 } },
  prefs: { async init() {}, async isDarkExplicit() { return true; }, async isFirstLaunch() { return false; } },
  app: { ui: { syncSystemBars() {}, async applySystemDarkMode() {} }, async flushAll() {}, destroy() {} },
  setAppContext() {},
  DEFAULT_THEME_ID: 'paper',
  tokensFor: () => ({ brand: '#0A59F7', textPrimary: '#1C1C1E', textSecondary: '#6E6E73',
    textTertiary: '#A6A6AB', danger: '#E84026', divider: '#ECECEE', activeBg: '#0F1C1C1E' })
});
vm.runInContext(compile(read('utils/DesktopWindowChrome.ets')), context);
const barSource = read('shell/PcWindowBar.ets');
vm.runInContext(compile('class WindowBarProbe {\n' + ['win', 'startMove', 'minimize', 'toggleMaximize', 'close',
  'onTitleTouch', 'onTitleMouse'].map(name => method(barSource, name)).join('\n') + '\n}'), context);
const titleBarSource = read('shell/DesktopTitleBar.ets');
vm.runInContext(compile("const TITLE_FALLBACK: string = 'Weaver';\nclass TitleBarProbe {\n" + ['aboutToAppear', 'aboutToDisappear', 'win', 'applyChrome',
  'readStatus', 'refreshTitleButtonRect', 'bindWindowListeners', 'unbindWindowListeners', 'startMove', 'minimize',
  'toggleMaximize', 'close', 'showCloseBlockedDialog', 'exportDraftsBeforeClose', 'hostContext', 'terminate', 'onTitleTouch', 'onTitleMouse', 'barTitle', 'barHeight',
  'maximized', 'maxGlyph', 'maxLabel', 'themeId', 'colors'].map(name => method(titleBarSource, name)).join('\n') + '\n}'), context);
vm.runInContext(compile(read('entryability/EntryAbility.ets')), context);
const editorPaneSource = read('shell/EditorPane.ets');
vm.runInContext(compile('class EditorPaneProbe {\n' + ['beginRename', 'commitRename', 'onActiveDocChanged', 'aboutToDisappear']
  .map(name => method(editorPaneSource, name)).join('\n') + '\n}'), context);
const api = vm.runInContext('({configureDesktopChrome, WindowBarProbe, TitleBarProbe, EntryAbility, EditorPaneProbe})', context);
const settle = () => new Promise(resolve => setImmediate(resolve));
function nativeWindow(failures = {}) {
  const calls = [];
  const native = { calls, status: statuses.FLOATING, free: deviceInfo.deviceType === '2in1' };
  native.isInFreeWindowMode = () => native.free;
  function invoke(name, args, asynchronous = true) {
    calls.push([name, ...args]);
    if (failures[name] === 'throw') throw new Error(name + ' sync failure');
    if (failures[name] === 'reject') return Promise.reject(new Error(name + ' async failure'));
    return asynchronous ? Promise.resolve() : undefined;
  }
  native.setWindowDecorVisible = (...args) => invoke('setWindowDecorVisible', args, false);
  native.setWindowTitleButtonVisible = (...args) => invoke('setWindowTitleButtonVisible', args, false);
  native.setWindowDecorHeight = (...args) => invoke('setWindowDecorHeight', args, false);
  native.setDecorButtonStyle = (...args) => invoke('setDecorButtonStyle', args, false);
  native.setTitleAndDockHoverShown = (...args) => invoke('setTitleAndDockHoverShown', args);
  native.setWindowLayoutFullScreen = (...args) => invoke('setWindowLayoutFullScreen', args);
  native.getWindowStatus = () => { invoke('getWindowStatus', [], false); return native.status; };
  native.titleButtonRect = { width: 0 };
  native.getTitleButtonRect = () => { invoke('getTitleButtonRect', [], false); return native.titleButtonRect; };
  const handlers = new Map();
  native.handlers = handlers;
  native.on = (name, callback) => { if (!handlers.has(name)) handlers.set(name, []); handlers.get(name).push(callback); };
  native.off = (name, callback) => {
    const list = handlers.get(name) || [];
    const index = list.indexOf(callback);
    if (index >= 0) list.splice(index, 1);
  };
  native.onCount = name => (handlers.get(name) || []).length;
  native.emit = (name, argument) => (handlers.get(name) || []).slice().forEach(callback => callback(argument));
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
function titleBar(native, overrides = {}) {
  if (native === undefined) storage.delete('mainWindow');
  else storage.set('mainWindow', native);
  profile.reset();
  const probe = new api.TitleBarProbe();
  Object.assign(probe, { windowStatus: 0, titleButtonWidth: 0, statusListener: null, rectListener: null,
    profileDisposer: null, safeTop: 0, chromeHeight: 0, app: null }, overrides);
  return probe;
}
function chromeCalls(native) {
  return native.calls.filter(call => ['setWindowDecorVisible', 'setWindowTitleButtonVisible', 'setWindowDecorHeight', 'setTitleAndDockHoverShown'].includes(call[0]));
}
function stage(native) {
  return { loaded: [], callbacks: [], handlers: new Map(),
    on(name, callback) { this.handlers.set(name, callback); },
    off(name, callback) { if (this.handlers.get(name) === callback) this.handlers.delete(name); },
    getMainWindowSync() { return native; },
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
  await check('custom chrome hides native title and buttons while keeping dock', async () => {
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

  // ===================== DesktopTitleBar（T2 沉浸标题栏） =====================
  await check('desktop title bar applies immersive decor metrics before hiding native chrome', async () => {
    const native = nativeWindow();
    titleBar(native).aboutToAppear();
    assert.deepEqual(native.calls.map(call => call[0]), ['setWindowDecorHeight', 'setDecorButtonStyle',
      'setWindowDecorVisible', 'setWindowTitleButtonVisible', 'setTitleAndDockHoverShown',
      'getWindowStatus', 'getTitleButtonRect']);
    assert.deepEqual(native.calls[0], ['setWindowDecorHeight', 48], '48vp is inside the official [37,112] range');
    assert.equal(native.calls[1][0], 'setDecorButtonStyle');
    assert.equal(native.calls[1][1].buttonIconSize, 18);
    assert.deepEqual(native.calls[2], ['setWindowDecorVisible', false]);
    assert.deepEqual(native.calls[3], ['setWindowTitleButtonVisible', false, false, false]);
    assert.deepEqual(native.calls[4], ['setTitleAndDockHoverShown', false, true]);
  });
  await check('desktop title bar dragging starts only from touch down or a left mouse press', () => {
    const native = nativeWindow();
    const probe = titleBar(native);
    for (const type of [touchTypes.Move, touchTypes.Up, touchTypes.Cancel, touchTypes.Down]) {
      probe.onTitleTouch({ type });
    }
    for (const event of [{ action: mouseActions.Press, button: mouseButtons.Right },
      { action: mouseActions.Press, button: mouseButtons.Middle },
      { action: mouseActions.Release, button: mouseButtons.Left },
      { action: mouseActions.Move, button: mouseButtons.Left },
      { action: mouseActions.Press, button: mouseButtons.Left }]) {
      probe.onTitleMouse(event);
    }
    // 只有 TouchType.Down 与左键 Press 各触发一次；右键/中键/释放/移动都不拖动窗口
    assert.deepEqual(native.calls.map(call => call[0]), ['startMoving', 'startMoving']);
    assert.equal(profile.pointerCalls, 1, 'only a real pointer press upgrades the input modality');
  });
  await check('desktop title bar maximizes, recovers and treats full screen as maximized', async () => {
    for (const [status, operation] of [[statuses.MAXIMIZE, 'recover'], [statuses.FULL_SCREEN, 'recover'],
      [statuses.FLOATING, 'maximize'], [statuses.SPLIT_SCREEN, 'maximize']]) {
      const native = nativeWindow();
      native.status = status;
      titleBar(native).toggleMaximize();
      await settle();
      assert.deepEqual(native.calls.map(call => call[0]), ['getWindowStatus', operation, 'setWindowDecorHeight',
        'setDecorButtonStyle', 'setWindowDecorVisible', 'setWindowTitleButtonVisible', 'setTitleAndDockHoverShown'],
        'status ' + status);
    }
  });
  await check('desktop title bar status glyphs follow the maximized state', () => {
    const probe = titleBar(nativeWindow());
    assert.equal(probe.maximized(), false);
    assert.equal(probe.maxGlyph(), '□');
    assert.equal(probe.maxLabel(), '最大化');
    probe.windowStatus = statuses.MAXIMIZE;
    assert.equal(probe.maximized(), true);
    assert.equal(probe.maxGlyph(), '❐');
    assert.equal(probe.maxLabel(), '还原');
    probe.windowStatus = statuses.FULL_SCREEN;
    assert.equal(probe.maxGlyph(), '❐');
  });
  await check('desktop title bar bar height absorbs the safe area exactly once', () => {
    const probe = titleBar(nativeWindow(), { safeTop: 28 });
    assert.equal(probe.barHeight(), 76, '48vp chrome + 28vp status bar');
    probe.chromeHeight = 90;
    assert.equal(probe.barHeight(), 90, 'a snapshot chrome height wins over the constant fallback');
  });
  await check('desktop title bar falls back to the Weaver title for an empty book name', () => {
    const probe = titleBar(nativeWindow(), { app: { project: { bookName: '   ' }, ui: { themeId: 'paper' } } });
    assert.equal(probe.barTitle(), 'Weaver');
    probe.app = { project: { bookName: '长夜' }, ui: { themeId: 'paper' } };
    assert.equal(probe.barTitle(), '长夜');
    probe.app = null;
    assert.equal(probe.barTitle(), 'Weaver');
  });
  await check('desktop title bar start and minimize failures are contained', async () => {
    for (const [operation, methodName] of [['startMoving', 'startMove'], ['minimize', 'minimize']]) {
      for (const failure of ['reject', 'throw']) {
        const before = warnings.length;
        const native = nativeWindow({ [operation]: failure });
        titleBar(native)[methodName]();
        await settle();
        assert.equal(warnings.length, before + 1, operation + ' ' + failure);
        assert.equal(native.calls.length, 1, operation + ' failure must not reapply chrome');
      }
    }
  });
  await check('desktop title bar maximize and recover failures are contained', async () => {
    for (const [operation, status] of [['maximize', statuses.FLOATING], ['recover', statuses.MAXIMIZE]]) {
      for (const failure of ['reject', 'throw']) {
        const before = warnings.length;
        const native = nativeWindow({ [operation]: failure });
        native.status = status;
        titleBar(native).toggleMaximize();
        await settle();
        assert.equal(warnings.length, before + 1, operation + ' ' + failure);
        assert.equal(chromeCalls(native).length, 0, 'a failed maximize/recover must not apply success chrome');
      }
    }
  });
  await check('desktop title bar flushes drafts before terminating the ability', async () => {
    const log = [];
    const host = { terminateSelf() { log.push('terminate'); return Promise.resolve(); } };
    const probe = titleBar(nativeWindow(), {
      app: { flushAllStrict() { log.push('flush'); return Promise.resolve(); } },
      getUIContext: () => ({ getHostContext: () => host })
    });
    probe.close();
    assert.deepEqual(log, ['flush'], 'termination must wait for the flush to settle');
    await settle();
    assert.deepEqual(log, ['flush', 'terminate']);
  });
  await check('desktop title bar keeps the window open when the strict flush fails', async () => {
    const log = [];
    const host = { terminateSelf() { log.push('terminate'); return Promise.resolve(); } };
    let dialog = null;
    const probe = titleBar(nativeWindow(), {
      app: { ui: { themeId: 'paper' }, flushAllStrict() { log.push('flush'); return Promise.reject(new Error('disk full')); } },
      getUIContext: () => ({
        getHostContext: () => host,
        getPromptAction: () => ({
          showDialog(options) { dialog = options; return new Promise(() => {}); },
          showToast() {}
        })
      })
    });
    probe.close();
    await settle();
    assert.deepEqual(log, ['flush'], 'a failed save must NOT terminate the ability');
    assert.ok(dialog !== null, 'the user must get retry/export/discard choices');
    assert.equal(dialog.buttons.map(b => b.text).join(','), '重试保存,导出草稿,放弃并退出');
    assert.match(warnings.at(-1), /flushAllStrict failed before close/);
  });
  await check('desktop title bar closes safely without a store or a host context', async () => {
    const log = [];
    const host = { terminateSelf() { log.push('terminate'); return Promise.resolve(); } };
    titleBar(nativeWindow(), { app: null, getUIContext: () => ({ getHostContext: () => host }) }).close();
    await settle();
    assert.deepEqual(log, ['terminate'], 'no store means nothing to flush, but the ability still ends');
    const before = warnings.length;
    const missingHost = titleBar(nativeWindow(), {
      app: { flushAllStrict() { return Promise.resolve(); } },
      getUIContext: () => ({ getHostContext: () => { throw new Error('no host context'); } })
    });
    missingHost.close();
    await settle();
    assert.equal(warnings.length, before + 1);
    assert.equal(log.length, 1);
  });
  await check('desktop title bar owns exactly its own window listeners and disposes them', () => {
    const native = nativeWindow();
    const probe = titleBar(native);
    probe.aboutToAppear();
    assert.equal(native.onCount('windowStatusChange'), 1);
    assert.equal(native.onCount('windowTitleButtonRectChange'), 1);
    assert.equal(profile.listeners.length, 1, 'the title bar subscribes to the single DeviceProfile broadcast');
    probe.aboutToDisappear();
    assert.equal(native.onCount('windowStatusChange'), 0);
    assert.equal(native.onCount('windowTitleButtonRectChange'), 0);
    assert.equal(profile.listeners.length, 0);
    assert.equal(probe.statusListener, null);
    assert.equal(probe.rectListener, null);
    probe.aboutToDisappear();
    assert.equal(native.onCount('windowStatusChange'), 0, 'a second teardown must be a no-op');
  });
  await check('desktop title bar reacts to status and title-button rect changes', () => {
    const native = nativeWindow();
    const probe = titleBar(native);
    probe.aboutToAppear();
    const chromeBefore = native.calls.filter(call => call[0] === 'setWindowDecorVisible').length;
    native.emit('windowStatusChange', statuses.MAXIMIZE);
    assert.equal(probe.windowStatus, statuses.MAXIMIZE);
    assert.equal(native.calls.filter(call => call[0] === 'setWindowDecorVisible').length, chromeBefore + 1,
      'a status change must reapply the immersive chrome');
    assert.equal(profile.changes, 1, 'a status change asks DeviceProfile to re-read the safe area');
    native.titleButtonRect = { width: 120 };
    native.emit('windowTitleButtonRectChange', { width: 120 });
    assert.equal(probe.titleButtonWidth, 120);
    native.titleButtonRect = { width: 120 };
    native.emit('windowTitleButtonRectChange', { width: 120 });
    assert.equal(probe.titleButtonWidth, 120, 'an unchanged rect must not reassign the bound value');
    profile.emit({ windowStatus: statuses.FLOATING });
    assert.equal(probe.windowStatus, statuses.FLOATING, 'the AppShell-side snapshot also updates the glyph state');
  });
  await check('desktop title bar controls are safe without a main window', async () => {
    const probe = titleBar(undefined, { getUIContext: () => ({ getHostContext: () => undefined }) });
    probe.aboutToAppear();
    for (const name of ['startMove', 'minimize', 'toggleMaximize', 'close']) {
      probe[name]();
    }
    await settle();
    assert.equal(warnings.length, 0);
    probe.aboutToDisappear();
  });
  await check('PcWindowBar stays a thin compatibility shell over DesktopTitleBar', () => {
    const source = read('shell/PcWindowBar.ets');
    assert.match(source, /import \{ DesktopTitleBar \} from '\.\/DesktopTitleBar'/);
    assert.match(source, /DesktopTitleBar\(\{ app: this\.app \}\)/);
    for (const name of ['win', 'startMove', 'minimize', 'toggleMaximize', 'close', 'onTitleTouch', 'onTitleMouse']) {
      method(source, name);
    }
  });
  await check('title bar disposes listeners on its original window even after AppStorage changes', () => {
    const original = nativeWindow();
    const probe = titleBar(original);
    probe.aboutToAppear();
    storage.set('mainWindow', nativeWindow());
    probe.aboutToDisappear();
    assert.equal(original.onCount('windowStatusChange'), 0);
    assert.equal(original.onCount('windowTitleButtonRectChange'), 0);
  });
  await check('tablet free-window transitions configure and restore chrome after content is ready', async () => {
    deviceInfo.deviceType = 'tablet';
    const native = nativeWindow();
    const windowStage = stage(native);
    const entry = ability();
    entry.onWindowStageCreate(windowStage);
    await settle();
    windowStage.callbacks[0]({ code: 0 });
    assert.equal(entry.isDesktop, false);
    native.free = true;
    native.emit('freeWindowModeChange', true);
    assert.equal(entry.isDesktop, true);
    assert.deepEqual(chromeCalls(native).slice(-3), [['setWindowDecorVisible', false],
      ['setWindowTitleButtonVisible', false, false, false], ['setTitleAndDockHoverShown', false, true]]);
    native.free = false;
    native.emit('freeWindowModeChange', false);
    assert.equal(entry.isDesktop, false);
    assert.deepEqual(chromeCalls(native).slice(-3), [['setWindowDecorVisible', true],
      ['setWindowTitleButtonVisible', true, true, true], ['setTitleAndDockHoverShown', true, true]]);
    entry.onWindowStageDestroy();
    assert.equal(windowStage.handlers.size, 0);
    assert.equal(native.onCount('freeWindowModeChange'), 0);
    assert.equal(storage.has('mainWindow'), false);
  });
  await check('destroying a window before async initialization finishes does not load stale content', async () => {
    const entry = ability();
    const windowStage = stage(nativeWindow());
    entry.onWindowStageCreate(windowStage);
    entry.onWindowStageDestroy();
    await settle();
    assert.equal(windowStage.loaded.length, 0);
    assert.equal(windowStage.handlers.size, 0);
  });
  await check('renaming is cancelled when the active document changes before submission', async () => {
    const changes = [];
    const probe = new api.EditorPaneProbe();
    probe.app = { editor: { activeId: 'A', title: 'Title A' },
      renameChapter: async (id, title) => changes.push([id, title]) };
    probe.beginRename();
    probe.draftTitle = 'New A';
    probe.app.editor.activeId = 'B';
    probe.app.editor.title = 'Title B';
    probe.commitRename();
    await settle();
    assert.deepEqual(changes, []);
    probe.beginRename();
    probe.onActiveDocChanged();
    assert.equal(probe.renaming, false);
    assert.equal(probe.renameDocId, '');
  });
  await check('a rename saves its captured owner and does not refocus another document', async () => {
    const changes = [];
    let finish;
    let focused = 0;
    const probe = new api.EditorPaneProbe();
    probe.app = { editor: { activeId: 'A', title: 'Title A' },
      renameChapter(id, title) { changes.push([id, title]); return new Promise(resolve => { finish = resolve; }); } };
    probe.editorController = { focus() { focused++; } };
    probe.beginRename();
    probe.draftTitle = 'New A';
    probe.commitRename();
    probe.commitRename();
    assert.deepEqual(changes, [['A', 'New A']]);
    probe.app.editor.activeId = 'B';
    finish();
    await settle();
    assert.equal(focused, 0);
  });
  await check('unmounting an old editor cannot erase the current editor controller', () => {
    const old = {};
    const current = {};
    const probe = new api.EditorPaneProbe();
    probe.editorController = old;
    probe.app = { ui: { editorController: current } };
    probe.aboutToDisappear();
    assert.equal(probe.app.ui.editorController, current);
    assert.equal(probe.editorController, null);
  });
  console.log(`Window regression: ${count} checks passed`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  process.removeListener('unhandledRejection', onUnhandled);
});
