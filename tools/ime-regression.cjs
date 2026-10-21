// Node 24+. Executes the real ImeBridge with controlled native IPC and timers.
// No device, keyboard injection, or simulator is used.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const source = fs.readFileSync(path.resolve(__dirname,
  '../entry/src/main/ets/editor/flowtext/ime/ImeBridge.ets'), 'utf8');
const compiled = stripTypeScriptTypes(source
  .replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm, '')
  .replace(/\bexport\s+/g, ''), { mode: 'transform' });
const settle = () => new Promise(resolve => setImmediate(resolve));

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function harness() {
  const attachments = [];
  const selections = [];
  const listeners = new Map();
  const timers = new Map();
  const timerHistory = new Map();
  const warnings = [];
  const calls = [];
  let nextTimer = 0;
  const controller = {
    throwSelection: false,
    on(name, callback) {
      if (!listeners.has(name)) { listeners.set(name, new Set()); }
      listeners.get(name).add(callback);
    },
    off(name, callback) { listeners.get(name)?.delete(callback); },
    attach() {
      const result = deferred();
      attachments.push(result);
      return result.promise;
    },
    detach() { calls.push('detach'); return Promise.resolve(); },
    changeSelection(value, start, end) {
      if (this.throwSelection) { throw new Error('native selection sync failed synchronously'); }
      const result = deferred();
      selections.push({ value, start, end, ...result });
      return result.promise;
    },
    updateCursor() { return Promise.resolve(); },
    hideTextInput() { calls.push('hide'); return Promise.resolve(); },
    showTextInput() { calls.push('show'); return Promise.resolve(); }
  };
  const context = vm.createContext({
    inputMethod: { getController() { return controller; } },
    console: { error() {}, warn(message) { warnings.push(message); } },
    setTimeout(callback, delay) {
      const id = ++nextTimer;
      const timer = { callback, delay };
      timers.set(id, timer);
      timerHistory.set(id, timer);
      return id;
    },
    clearTimeout(id) { timers.delete(id); }
  });
  vm.runInContext(compiled, context);
  const Bridge = vm.runInContext('ImeBridge', context);
  const bridge = new Bridge();
  return {
    bridge, controller, selections, warnings, timers, timerHistory, calls,
    async attach() {
      const result = bridge.attach(false, 0, 0);
      attachments.at(-1).resolve();
      await result;
      assert.equal(bridge.attached, true);
    },
    async succeed(index = selections.length - 1) {
      selections[index].resolve();
      await settle();
    },
    async fail(index = selections.length - 1) {
      selections[index].reject(new Error('native IPC temporarily unavailable'));
      await settle();
    },
    async runTimer() {
      assert.equal(timers.size, 1, 'only one retry may be scheduled');
      const [id, timer] = timers.entries().next().value;
      timers.delete(id);
      timer.callback();
      await settle();
      return timer.delay;
    },
    values() { return selections.map(({ value, start, end }) => [value, start, end]); }
  };
}

let count = 0;
async function check(name, run) {
  await run();
  count++;
  console.log('PASS ' + name);
}

(async () => {
  await check('unattached reports are ignored and an attached report sends without a timer', async () => {
    const h = harness();
    h.bridge.changeSelection('old', 1, 1);
    assert.equal(h.selections.length, 0);
    await h.attach();
    h.bridge.changeSelection('中文', 1, 2);
    assert.deepEqual(h.values(), [['中文', 1, 2]]);
    assert.equal(h.timers.size, 0, 'normal composition must not be throttled');
    await h.succeed();
    assert.equal(h.timers.size, 0);
  });

  await check('rapid reports retain only the latest state behind one in-flight request', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('first', 0, 0);
    for (let index = 0; index < 2000; index++) {
      h.bridge.changeSelection('预览' + index, index, index);
    }
    assert.equal(h.selections.length, 1);
    await h.succeed(0);
    assert.deepEqual(h.values(), [['first', 0, 0], ['预览1999', 1999, 1999]]);
    await h.succeed(1);
    assert.equal(h.selections.length, 2);
    assert.equal(h.timers.size, 0);
  });

  await check('latest selection offsets are retained even when the text is unchanged', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('same', 0, 0);
    h.bridge.changeSelection('same', 1, 1);
    h.bridge.changeSelection('same', 1, 3);
    await h.succeed(0);
    assert.deepEqual(h.values(), [['same', 0, 0], ['same', 1, 3]]);
    await h.succeed(1);
  });

  await check('returning to an in-flight state cancels an obsolete pending state', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('A', 0, 0);
    h.bridge.changeSelection('B', 1, 1);
    h.bridge.changeSelection('A', 0, 0);
    await h.succeed(0);
    assert.deepEqual(h.values(), [['A', 0, 0]]);
  });

  await check('a newer state follows a failed request immediately without retrying obsolete text', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('obsolete', 0, 0);
    h.bridge.changeSelection('current', 2, 2);
    await h.fail(0);
    assert.deepEqual(h.values(), [['obsolete', 0, 0], ['current', 2, 2]]);
    assert.equal(h.timers.size, 0);
    await h.succeed(1);
  });

  await check('a transient failure retries unchanged text even without a new editor report', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('未变化', 1, 1);
    await h.fail(0);
    assert.equal(await h.runTimer(), 32);
    assert.deepEqual(h.values(), [['未变化', 1, 1], ['未变化', 1, 1]]);
    await h.succeed(1);
    assert.equal(h.timers.size, 0);
    assert.equal(h.warnings.length, 0);
  });

  await check('a report stops after three failed attempts and keyboard activation can recover it', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('recover', 3, 3);
    await h.fail(0);
    assert.equal(await h.runTimer(), 32);
    await h.fail(1);
    assert.equal(await h.runTimer(), 128);
    await h.fail(2);
    assert.equal(h.selections.length, 3);
    assert.equal(h.timers.size, 0, 'persistent failure must not keep a background timer alive');
    assert.equal(h.warnings.length, 1);
    assert.match(h.warnings[0], /3 attempts/);
    h.bridge.showKeyboard();
    assert.equal(h.selections.length, 4);
    assert.ok(h.calls.includes('show'));
    await h.succeed(3);
    assert.equal(h.timers.size, 0);
  });

  await check('same-state reports and already-attached focus requests can recover a parked report', async () => {
    for (const resume of ['report', 'attach']) {
      const h = harness();
      await h.attach();
      h.bridge.changeSelection('retry', 1, 1);
      await h.fail(0);
      await h.runTimer();
      await h.fail(1);
      await h.runTimer();
      await h.fail(2);
      if (resume === 'report') {
        h.bridge.changeSelection('retry', 1, 1);
      } else {
        await h.bridge.attach(false, 0, 0);
      }
      assert.equal(h.selections.length, 4, resume + ' starts a fresh bounded attempt');
      await h.succeed(3);
    }
  });

  await check('new composition bypasses an old retry delay and its cancelled callback is harmless', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('old', 0, 0);
    await h.fail(0);
    const oldTimer = h.timers.values().next().value;
    h.bridge.changeSelection('新候选', 1, 2);
    assert.deepEqual(h.values(), [['old', 0, 0], ['新候选', 1, 2]]);
    assert.equal(h.timers.size, 0);
    oldTimer.callback();
    await settle();
    assert.equal(h.selections.length, 2);
    await h.succeed(1);
  });

  await check('a cancelled timer cannot clear a newer retry in the same session', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('old', 0, 0);
    await h.fail(0);
    const oldTimer = h.timers.values().next().value;
    h.bridge.changeSelection('latest', 2, 2);
    await h.fail(1);
    oldTimer.callback();
    await settle();
    assert.equal(h.timers.size, 1);
    assert.equal(h.selections.length, 2);
    await h.runTimer();
    assert.equal(h.selections.length, 3);
    assert.equal(h.selections[2].value, 'latest');
    await h.succeed(2);
  });

  await check('detach cancels retries and reattachment never sends the previous document state', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('private old document', 3, 3);
    await h.fail(0);
    const oldTimer = h.timers.values().next().value;
    h.bridge.detach();
    assert.equal(h.bridge.attached, false);
    assert.equal(h.timers.size, 0);
    await h.attach();
    assert.equal(h.selections.length, 1, 'reattachment must not replay a detached document');
    h.bridge.changeSelection('new document', 1, 1);
    oldTimer.callback();
    await settle();
    assert.equal(h.selections.length, 2);
    await h.succeed(1);
  });

  await check('old success and failure completions cannot disturb a new session or its pending selection', async () => {
    for (const oldResult of ['success', 'failure']) {
      const h = harness();
      await h.attach();
      h.bridge.changeSelection('old session', 0, 0);
      h.bridge.changeSelection('old pending', 0, 0);
      h.bridge.detach();
      await h.attach();
      h.bridge.changeSelection('new session', 1, 1);
      h.bridge.changeSelection('new latest', 2, 2);
      if (oldResult === 'success') { await h.succeed(0); } else { await h.fail(0); }
      assert.equal(h.selections.length, 2);
      assert.equal(h.timers.size, 0);
      await h.succeed(1);
      assert.deepEqual(h.values(), [
        ['old session', 0, 0], ['new session', 1, 1], ['new latest', 2, 2]
      ]);
      await h.succeed(2);
      assert.equal(h.warnings.length, 0);
    }
  });

  await check('a failing in-flight report is still retried after A to B to A convergence', async () => {
    const h = harness();
    await h.attach();
    h.bridge.changeSelection('A', 0, 0);
    h.bridge.changeSelection('B', 1, 1);
    h.bridge.changeSelection('A', 0, 0);
    await h.fail(0);
    await h.runTimer();
    assert.deepEqual(h.values(), [['A', 0, 0], ['A', 0, 0]]);
    await h.succeed(1);
  });

  await check('synchronous native exceptions follow the same bounded recovery path', async () => {
    const h = harness();
    await h.attach();
    h.controller.throwSelection = true;
    assert.doesNotThrow(() => h.bridge.changeSelection('sync error', 0, 0));
    assert.equal(h.timers.size, 1);
    h.controller.throwSelection = false;
    await h.runTimer();
    assert.deepEqual(h.values(), [['sync error', 0, 0]]);
    await h.succeed(0);
    assert.equal(h.timers.size, 0);
  });

  console.log('IME: ' + count + ' checks passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
