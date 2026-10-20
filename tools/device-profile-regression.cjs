// Node 24+. Executes the device-profile service (T2) in a vm with controlled window/ability doubles.
// The window object is a double: no DevEco/SDK/hdc is required, and nothing here talks to a device.
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
const statuses = { FLOATING: 0, MAXIMIZE: 1, FULL_SCREEN: 2, SPLIT_SCREEN: 3 };
const avoidTypes = { TYPE_SYSTEM: 0, TYPE_NAVIGATION_INDICATOR: 4 };
const breakpoints = { WIDTH_XS: 0, WIDTH_SM: 1, WIDTH_MD: 2, WIDTH_LG: 3, WIDTH_XL: 4 };
const storage = new Map();
const warnings = [];
const errors = [];
const deviceInfo = { deviceType: 'phone' };
const context = vm.createContext({
  window: { WindowStatusType: statuses, AvoidAreaType: avoidTypes },
  WidthBreakpoint: breakpoints,
  deviceInfo,
  AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  Logger: { info() {}, warn: message => warnings.push(message), error: message => errors.push(message) },
  px2vp: value => value,
  UIContext: class {},
  console: { log() {}, warn() {}, error() {} }
});
vm.runInContext(compile(read('utils/BreakPoint.ets')), context);
vm.runInContext(compile(read('utils/DesktopWindowChrome.ets')), context);
vm.runInContext(compile(read('utils/SafeArea.ets')), context);
vm.runInContext(compile(read('utils/DeviceProfile.ets')), context);
const api = vm.runInContext('({BreakPoint,DeviceClass,InputModality,LayoutTier,DeviceSnapshot,DeviceProfileService,' +
  'detectDeviceClass,modalityFor,DESKTOP_CHROME_HEIGHT_VP})', context);
const settle = () => new Promise(resolve => setImmediate(resolve));

function nativeWindow(options = {}) {
  const record = { on: [], off: [], calls: [] };
  const win = {
    free: options.free === true,
    status: options.status === undefined ? statuses.FLOATING : options.status,
    rectWidth: options.rectWidth === undefined ? 0 : options.rectWidth,
    safeTopPx: options.safeTopPx === undefined ? 0 : options.safeTopPx,
    safeBottomPx: options.safeBottomPx === undefined ? 0 : options.safeBottomPx,
    density: options.density === undefined ? 1 : options.density,
    getUIContext() { return { px2vp: value => value / this.density }; },
    freeThrows: options.freeThrows === true,
    statusThrows: options.statusThrows === true,
    rectThrows: options.rectThrows === true,
    isInFreeWindowMode() {
      record.calls.push(['isInFreeWindowMode']);
      if (this.freeThrows) { throw new Error('1300002 free window unavailable'); }
      return this.free;
    },
    getWindowStatus() {
      record.calls.push(['getWindowStatus']);
      if (this.statusThrows) { throw new Error('getWindowStatus failed'); }
      return this.status;
    },
    getTitleButtonRect() {
      record.calls.push(['getTitleButtonRect']);
      if (this.rectThrows) { throw new Error('getTitleButtonRect failed'); }
      return { width: this.rectWidth };
    },
    getWindowAvoidArea(type) {
      record.calls.push(['getWindowAvoidArea', type]);
      if (type === avoidTypes.TYPE_SYSTEM) {
        return { topRect: { height: this.safeTopPx }, bottomRect: { height: 0 } };
      }
      return { topRect: { height: 0 }, bottomRect: { height: this.safeBottomPx } };
    },
    on(name, callback) { record.on.push([name, callback]); },
    off(name, callback) { record.off.push([name, callback]); }
  };
  return { win, record };
}
function uiContext(breakpoint, throws) {
  return {
    bp: breakpoint === undefined ? breakpoints.WIDTH_SM : breakpoint,
    boom: throws === true,
    getWindowWidthBreakpoint() {
      if (this.boom) { throw new Error('breakpoint unavailable'); }
      return this.bp;
    }
  };
}
function service() { return new api.DeviceProfileService(); }
function attach(options = {}) {
  const binding = nativeWindow(options);
  const ui = uiContext(options.breakpoint, options.breakpointThrows);
  const profile = options.profile === undefined ? service() : options.profile;
  profile.attach(ui, binding.win);
  return { profile, binding, ui };
}
let count = 0;
function check(name, fn) {
  warnings.length = 0;
  errors.length = 0;
  fn();
  count++;
  console.log('PASS ' + name);
}
function withDeviceType(type, run) {
  const original = deviceInfo.deviceType;
  deviceInfo.deviceType = type;
  try { run(); } finally { deviceInfo.deviceType = original; }
}

// ===================== device class =====================
check('device class maps 2in1 and pc to PC, tablet to TABLET, phone to PHONE', () => {
  withDeviceType('2in1', () => assert.equal(api.detectDeviceClass(), api.DeviceClass.PC));
  withDeviceType('pc', () => assert.equal(api.detectDeviceClass(), api.DeviceClass.PC));
  withDeviceType('tablet', () => assert.equal(api.detectDeviceClass(), api.DeviceClass.TABLET));
  withDeviceType('phone', () => assert.equal(api.detectDeviceClass(), api.DeviceClass.PHONE));
});
check('unknown or empty device type falls back to the conservative PHONE class', () => {
  for (const type of ['', 'wearable', 'tv', 'default']) {
    withDeviceType(type, () => assert.equal(api.detectDeviceClass(), api.DeviceClass.PHONE));
  }
});
check('an unreadable device type is classified as PHONE and only warns', () => {
  const descriptor = Object.getOwnPropertyDescriptor(deviceInfo, 'deviceType');
  Object.defineProperty(deviceInfo, 'deviceType', { configurable: true, get() { throw new Error('deviceInfo denied'); } });
  try {
    assert.equal(api.detectDeviceClass(), api.DeviceClass.PHONE);
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /deviceType/);
  } finally {
    Object.defineProperty(deviceInfo, 'deviceType', descriptor);
  }
});

// ===================== modality =====================
check('a desktop class is pointer-first even without observed pointer input', () => {
  assert.equal(api.modalityFor(api.DeviceClass.PC, false, false), api.InputModality.POINTER);
  assert.equal(api.modalityFor(api.DeviceClass.PC, true, false), api.InputModality.POINTER);
});
check('a tablet and a free-window tablet stay touch-first until a pointer is seen', () => {
  // 平板电脑模式（MatePad Edge）仍可能纯触摸使用，因此自由窗口本身不等于键鼠优先。
  assert.equal(api.modalityFor(api.DeviceClass.TABLET, false, false), api.InputModality.TOUCH);
  assert.equal(api.modalityFor(api.DeviceClass.TABLET, true, false), api.InputModality.TOUCH);
  assert.equal(api.modalityFor(api.DeviceClass.PHONE, true, false), api.InputModality.TOUCH);
});
check('a plain phone stays touch-first', () => {
  assert.equal(api.modalityFor(api.DeviceClass.PHONE, false, false), api.InputModality.TOUCH);
});
check('observed pointer input upgrades every class to pointer-first', () => {
  for (const cls of [api.DeviceClass.PHONE, api.DeviceClass.TABLET, api.DeviceClass.PC]) {
    assert.equal(api.modalityFor(cls, false, true), api.InputModality.POINTER, 'class ' + cls);
    assert.equal(api.modalityFor(cls, true, true), api.InputModality.POINTER, 'free ' + cls);
  }
});

// ===================== snapshot =====================
check('layout tier is derived from width breakpoint only', () => {
  const snapshot = new api.DeviceSnapshot();
  const table = [[api.BreakPoint.SM, api.LayoutTier.SINGLE], [api.BreakPoint.MD, api.LayoutTier.DOUBLE],
    [api.BreakPoint.LG, api.LayoutTier.TRIPLE]];
  for (const [breakPoint, tier] of table) {
    snapshot.breakPoint = breakPoint;
    assert.equal(snapshot.tier, tier, 'breakpoint ' + breakPoint);
  }
});
check('desktop chrome is exactly free-window mode, never the device class', () => {
  const snapshot = new api.DeviceSnapshot();
  snapshot.deviceClass = api.DeviceClass.PC;
  snapshot.freeWindow = false;
  assert.equal(snapshot.isDesktopChrome, false);
  snapshot.deviceClass = api.DeviceClass.TABLET;
  snapshot.freeWindow = true;
  assert.equal(snapshot.isDesktopChrome, true);
});
check('pointerPrimary follows the modality: only a real pointer enables pointer-only chrome', () => {
  const snapshot = new api.DeviceSnapshot();
  snapshot.modality = api.InputModality.TOUCH;
  assert.equal(snapshot.pointerPrimary, false);
  // 注意：契约 §1 写的是 modality !== TOUCH，当前实现是 modality === POINTER；
  // modalityFor 目前不会产出 MIXED，两者行为等价，已作为源码偏差上报给 Lead。
  snapshot.modality = api.InputModality.MIXED;
  assert.equal(snapshot.pointerPrimary, false);
  snapshot.modality = api.InputModality.POINTER;
  assert.equal(snapshot.pointerPrimary, true);
});

// ===================== attach / refresh =====================
check('attach reads device class, free window, status, breakpoint and safe area', () => {
  deviceInfo.deviceType = '2in1';
  const { profile, binding } = attach({ free: true, status: statuses.MAXIMIZE, rectWidth: 96,
    breakpoint: breakpoints.WIDTH_LG, safeTopPx: 32, safeBottomPx: 16 });
  try {
    const snapshot = profile.snapshot;
    assert.equal(snapshot.deviceClass, api.DeviceClass.PC);
    assert.equal(snapshot.freeWindow, true);
    assert.equal(snapshot.windowStatus, statuses.MAXIMIZE);
    assert.equal(snapshot.breakPoint, api.BreakPoint.LG);
    assert.equal(snapshot.tier, api.LayoutTier.TRIPLE);
    assert.equal(snapshot.safeTopVp, 32);
    assert.equal(snapshot.safeBottomVp, 16);
    assert.equal(snapshot.titleButtonWidthVp, 96);
    assert.equal(snapshot.chromeHeightVp, api.DESKTOP_CHROME_HEIGHT_VP + 32);
    assert.equal(snapshot.modality, api.InputModality.POINTER);
    // attach 显式读一次（TYPE_SYSTEM + TYPE_NAVIGATION_INDICATOR），watchSafeArea 再读一次
    assert.equal(binding.record.calls.filter(call => call[0] === 'getWindowAvoidArea').length, 4);
  } finally {
    profile.detach();
  }
});
check('chrome height is zero when the window is not in free-window mode', () => {
  deviceInfo.deviceType = 'tablet';
  const { profile } = attach({ free: false, safeTopPx: 28, safeBottomPx: 12, breakpoint: breakpoints.WIDTH_MD });
  try {
    assert.equal(profile.snapshot.freeWindow, false);
    assert.equal(profile.snapshot.chromeHeightVp, 0, 'no self-drawn title bar may reserve chrome height');
    assert.equal(profile.snapshot.tier, api.LayoutTier.DOUBLE);
    assert.equal(profile.snapshot.modality, api.InputModality.TOUCH);
  } finally {
    profile.detach();
  }
});
check('a failing free-window probe falls back to AppStorage and warns only once', () => {
  storage.set('freeWindowMode', true);
  const { profile } = attach({ freeThrows: true });
  try {
    assert.equal(profile.snapshot.freeWindow, true);
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /isInFreeWindowMode/);
    storage.set('freeWindowMode', false);
    profile.refresh();
    assert.equal(profile.snapshot.freeWindow, false);
    assert.equal(warnings.length, 1, 'the unavailable probe must not warn on every refresh');
  } finally {
    storage.delete('freeWindowMode');
    profile.detach();
  }
});
check('a failing free-window probe without a stored flag stays a phone-style window', () => {
  storage.delete('freeWindowMode');
  const { profile } = attach({ freeThrows: true });
  try {
    assert.equal(profile.snapshot.freeWindow, false);
    assert.equal(profile.snapshot.chromeHeightVp, 0);
  } finally {
    profile.detach();
  }
});
check('a throwing status read keeps the previous status instead of resetting it', () => {
  const { profile } = attach({ free: true, status: statuses.MAXIMIZE, safeTopPx: 20 });
  try {
    assert.equal(profile.snapshot.windowStatus, statuses.MAXIMIZE);
    profile.detach();
    const next = attach({ free: true, statusThrows: true, safeTopPx: 20, profile });
    try {
      assert.equal(next.profile.snapshot.windowStatus, statuses.MAXIMIZE);
      assert.match(warnings.join('\n'), /getWindowStatus/);
    } finally {
      next.profile.detach();
    }
  } finally {
    profile.detach();
  }
});
check('a throwing breakpoint query keeps the previous breakpoint', () => {
  const { profile, ui } = attach({ breakpoint: breakpoints.WIDTH_MD });
  try {
    assert.equal(profile.snapshot.breakPoint, api.BreakPoint.MD);
    ui.boom = true;
    profile.refresh();
    assert.equal(profile.snapshot.breakPoint, api.BreakPoint.MD);
    assert.match(warnings.join('\n'), /getWindowWidthBreakpoint/);
  } finally {
    profile.detach();
  }
});
check('a throwing title-button rect degrades to zero avoidance width', () => {
  const { profile, binding } = attach({ free: true, rectThrows: true });
  try {
    assert.equal(profile.snapshot.titleButtonWidthVp, 0);
    binding.win.rectThrows = false;
    binding.win.rectWidth = 72;
    profile.refresh();
    assert.equal(profile.snapshot.titleButtonWidthVp, 72);
  } finally {
    profile.detach();
  }
});
check('attach binds every window listener exactly once and detach removes the same callbacks', () => {
  const { profile, binding } = attach({ free: true, safeTopPx: 10 });
  const registration = binding.record.on.map(entry => entry[0]).sort();
  try {
    assert.deepEqual(registration, ['avoidAreaChange', 'freeWindowModeChange', 'windowSizeChange', 'windowStatusChange']);
    profile.attach(uiContext(breakpoints.WIDTH_MD), binding.win);
    assert.equal(binding.record.on.filter(entry => entry[0] === 'freeWindowModeChange').length, 1,
      'attaching twice must not duplicate window listeners');
  } finally {
    profile.detach();
  }
  const removed = binding.record.off.map(entry => entry[0]).sort();
  assert.deepEqual(removed, ['avoidAreaChange', 'freeWindowModeChange', 'windowSizeChange', 'windowStatusChange']);
  for (const [name, callback] of binding.record.on) {
    const matched = binding.record.off.filter(entry => entry[0] === name && entry[1] === callback);
    assert.equal(matched.length, 1, 'off must receive the exact same callback as on for ' + name);
  }
});
check('free window mode change listener publishes AppStorage and refreshes the snapshot', () => {
  const { profile, binding } = attach({ free: false, safeTopPx: 24 });
  try {
    const listener = binding.record.on.filter(entry => entry[0] === 'freeWindowModeChange')[0][1];
    binding.win.free = true;
    listener(true);
    assert.equal(storage.get('freeWindowMode'), true);
    assert.equal(profile.snapshot.freeWindow, true);
    assert.equal(profile.snapshot.chromeHeightVp, api.DESKTOP_CHROME_HEIGHT_VP + 24);
  } finally {
    storage.delete('freeWindowMode');
    profile.detach();
  }
});
check('size and status listener callbacks recompute the current snapshot', () => {
  const { profile, binding, ui } = attach({ free: false, breakpoint: breakpoints.WIDTH_SM });
  try {
    ui.bp = breakpoints.WIDTH_LG;
    binding.record.on.filter(entry => entry[0] === 'windowSizeChange')[0][1]({ width: 1600, height: 900 });
    assert.equal(profile.snapshot.breakPoint, api.BreakPoint.LG);
    binding.win.status = statuses.FULL_SCREEN;
    binding.record.on.filter(entry => entry[0] === 'windowStatusChange')[0][1](statuses.FULL_SCREEN);
    assert.equal(profile.snapshot.windowStatus, statuses.FULL_SCREEN);
  } finally {
    profile.detach();
  }
});

// ===================== subscriptions =====================
check('subscribers receive the whole fresh snapshot and disposal is idempotent', () => {
  const { profile, binding } = attach({ free: false, breakpoint: breakpoints.WIDTH_SM });
  const seen = [];
  const dispose = profile.onChange(snapshot => seen.push([snapshot.breakPoint, snapshot.freeWindow]));
  try {
    binding.win.free = true;
    profile.refresh();
    assert.deepEqual(seen, [[api.BreakPoint.SM, true]]);
    dispose();
    dispose();
    profile.refresh();
    assert.equal(seen.length, 1);
  } finally {
    profile.detach();
  }
});
check('one throwing subscriber cannot stop the remaining subscribers', () => {
  const { profile } = attach();
  const seen = [];
  profile.onChange(() => { throw new Error('title bar exploded'); });
  profile.onChange(snapshot => seen.push(snapshot.freeWindow));
  try {
    profile.refresh();
    assert.deepEqual(seen, [false]);
    assert.equal(errors.length, 1);
    assert.match(errors[0], /change listener failed/);
  } finally {
    profile.detach();
  }
});
check('window activation listeners are isolated and individually disposable', () => {
  const { profile } = attach();
  const calls = [];
  const first = profile.onWindowActivated(() => { throw new Error('editor focus failed'); });
  profile.onWindowActivated(() => calls.push('second'));
  try {
    profile.notifyWindowActivated();
    assert.deepEqual(calls, ['second']);
    assert.equal(errors.length, 1);
    first();
    profile.notifyWindowActivated();
    assert.deepEqual(calls, ['second', 'second']);
  } finally {
    profile.detach();
  }
});
check('notePointerActivity upgrades the modality once and is latched', () => {
  deviceInfo.deviceType = 'tablet';
  const { profile } = attach({ free: false, breakpoint: breakpoints.WIDTH_MD });
  try {
    assert.equal(profile.snapshot.modality, api.InputModality.TOUCH);
    profile.notePointerActivity();
    assert.equal(profile.snapshot.modality, api.InputModality.POINTER);
    const seen = [];
    profile.onChange(snapshot => seen.push(snapshot.modality));
    profile.notePointerActivity();
    assert.equal(seen.length, 0, 'a second pointer signal must not refresh again');
  } finally {
    profile.detach();
  }
});
check('detach clears subscribers so a stale page cannot react to later refreshes', () => {
  const { profile, binding } = attach();
  let seen = 0;
  profile.onChange(() => seen++);
  profile.detach();
  binding.win.status = statuses.MAXIMIZE;
  binding.record.on.filter(entry => entry[0] === 'windowStatusChange')[0][1](statuses.MAXIMIZE);
  assert.equal(seen, 0);
});

check('replacing a bound window releases the old callbacks and preserves page subscribers', () => {
  const { profile, binding } = attach({ free: false });
  const seen = [];
  profile.onChange(snapshot => seen.push(snapshot.freeWindow));
  const replacement = nativeWindow({ free: true });
  try {
    profile.attach(uiContext(breakpoints.WIDTH_LG), replacement.win);
    assert.deepEqual(binding.record.off.map(entry => entry[0]).sort(),
      ['avoidAreaChange', 'freeWindowModeChange', 'windowSizeChange', 'windowStatusChange']);
    assert.deepEqual(replacement.record.on.map(entry => entry[0]).sort(),
      ['avoidAreaChange', 'freeWindowModeChange', 'windowSizeChange', 'windowStatusChange']);
    assert.deepEqual(seen, [true]);
  } finally { profile.detach(); }
  assert.equal(replacement.record.off.length, 4);
});
check('a failed free-window capability probe is retried for a replacement window', () => {
  storage.delete('freeWindowMode');
  const { profile } = attach({ freeThrows: true });
  try {
    const replacement = nativeWindow({ free: true });
    profile.attach(uiContext(breakpoints.WIDTH_MD), replacement.win);
    assert.equal(profile.snapshot.freeWindow, true);
  } finally { profile.detach(); }
});
check('safe-area conversion follows the current window density after a display change', () => {
  const { profile, binding } = attach({ safeTopPx: 48, safeBottomPx: 24, density: 2 });
  try {
    assert.equal(profile.snapshot.safeTopVp, 24);
    assert.equal(profile.snapshot.safeBottomVp, 12);
    binding.win.density = 3;
    const callback = binding.record.on.find(entry => entry[0] === 'avoidAreaChange')[1];
    callback({ type: avoidTypes.TYPE_SYSTEM, area: { topRect: { height: 48 } } });
    callback({ type: avoidTypes.TYPE_NAVIGATION_INDICATOR, area: { bottomRect: { height: 24 } } });
    assert.equal(profile.snapshot.safeTopVp, 16);
    assert.equal(profile.snapshot.safeBottomVp, 8);
  } finally { profile.detach(); }
});
console.log(`Device profile regression: ${count} checks passed`);
