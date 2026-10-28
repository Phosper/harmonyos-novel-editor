// Node 24+. Static ArkTS red-line guard for the T1/T2/T3 deliverables.
// Not a compiler: it greps the settled sources for the contract's forbidden syntax/APIs, so that
// `node tools/*.cjs` catches the mistakes that only DevEco (hvigor + ArkTS linter) would report.
// Usage: node tools/arkts-guard.cjs  (exit code 1 on any violation)
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const moduleJson = path.resolve(__dirname, '../entry/src/main/module.json5');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

// T1 交互归一 / T2 设备与标题栏 / T3 沉浸光感：本次重构写入范围内的全部 .ets
const T1 = ['editor/interaction/EditCommand.ets', 'editor/interaction/ShortcutMap.ets',
  'editor/interaction/EditorCommandRouter.ets', 'editor/interaction/InputArbiter.ets',
  'editor/flowtext/CanvasTextEditor.ets', 'editor/flowtext/ime/ImeBridge.ets',
  'editor/flowtext/ime/KeyboardHandler.ets', 'editor/TextEditorHost.ets', 'shell/EditorPane.ets'];
const T2 = ['utils/DeviceProfile.ets', 'utils/BreakPoint.ets', 'utils/SafeArea.ets',
  'utils/DesktopWindowChrome.ets', 'utils/AppChromeMode.ets', 'utils/WindowDrag.ets',
  'utils/SystemBars.ets', 'entryability/EntryAbility.ets', 'entryability/MyAbilityStage.ets',
  'shell/AppShell.ets', 'shell/DesktopTitleBar.ets', 'shell/PcWindowBar.ets', 'store/UiStore.ets'];
const T3 = ['constants/DesignTokens.ets', 'constants/LightTokens.ets', 'constants/Motion.ets',
  'shell/MenuButton.ets', 'shell/TopActionButton.ets', 'shell/EditorTools.ets', 'shell/MaterialSurface.ets',
  'shell/FocusWorkspace.ets', 'shell/FocusTransition.ets', 'shell/LongTakeBridge.ets',
  'shell/UserAvatar.ets', 'utils/AvatarService.ets',
  'shell/MobileShell.ets', 'shell/DocListPane.ets', 'shell/ProjectSidebar.ets', 'shell/WorkspaceDest.ets',
  'shell/InputDialog.ets', 'shell/MobileTabBar.ets', 'shell/MobileSectionTabs.ets', 'shell/SettingsPanel.ets',
  'pages/Index.ets', 'pages/GuideSwiperPage.ets', 'pages/dest/SettingsDest.ets'];
const FILES = T1.concat(T2, T3);

const violations = [];
const warnings = [];
// 规则只定义一次：既用于真实文件扫描，也用于文件末尾的自检（防止正则写错导致"空转全绿"）
const RULE = {
  anyUnknown: /(:\s*(?:any|unknown)\b|<\s*(?:any|unknown)\s*>|\bas\s+(?:any|unknown)\b)/,
  destructuring: /\b(?:const|let|var)\s*[\[{]/,
  // 解构形参：function f({a}) / const g = ({a}) => ...（普通调用 foo({a:1}) 不算）
  destructureParam: /(?:function\s+[A-Za-z_$][\w$]*\s*\(\s*\{|=\s*\(\s*\{[^}]*\}\s*(?::\s*[^)]*)?\)\s*=>)/,
  objectSpread: /\{[^{}]*\.\.\.[A-Za-z_$]/,
  objectAssign: /Object\.assign\s*\(/,
  moveWindowTo: /\.moveWindowTo\s*\(/,
  sixDigitStatus: /statusBarContentColor\s*:\s*['"]#([0-9a-fA-F]{6})['"]/g,
  consoleCall: /\bconsole\.(?:info|warn|error|log|debug)\s*\(/
};
function fail(rule, file, line, detail) { violations.push(`${rule}: ${file}:${line} ${detail}`); }

/** 去掉行注释/块注释，保留行号；字符串内容原样保留（颜色规则需要）。 */
function stripComments(source) {
  let out = '';
  let i = 0;
  let mode = 'code';
  let quote = '';
  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];
    if (mode === 'code') {
      if (ch === '/' && next === '/') { mode = 'line'; out += '  '; i += 2; continue; }
      if (ch === '/' && next === '*') { mode = 'block'; out += '  '; i += 2; continue; }
      if (ch === '"' || ch === "'" || ch === '`') { mode = 'string'; quote = ch; out += ch; i += 1; continue; }
      out += ch;
      i += 1;
      continue;
    }
    if (mode === 'string') {
      out += ch;
      if (ch === '\\') { out += source[i + 1] === undefined ? '' : source[i + 1]; i += 2; continue; }
      if (ch === quote) { mode = 'code'; quote = ''; }
      i += 1;
      continue;
    }
    if (mode === 'line') {
      if (ch === '\n') { mode = 'code'; out += '\n'; } else { out += ' '; }
      i += 1;
      continue;
    }
    // block comment
    if (ch === '*' && next === '/') { mode = 'code'; out += '  '; i += 2; continue; }
    out += ch === '\n' ? '\n' : ' ';
    i += 1;
  }
  return out;
}
function lines(source) { return stripComments(source).split('\n'); }
function lineNumbered(fn) {
  for (const file of FILES) {
    const raw = read(file);
    const code = fn === 'raw' ? raw : stripComments(raw);
    code.split('\n').forEach((text, index) => fn(file, index + 1, text, raw));
  }
}
/**
 * 组件的 struct 体（成员层）出现 `.attr(` 的行号。
 * build() 内部的子组件块属于嵌套 block，链式调用合法；只要 `.attr` 直接落在 struct 体，
 * 说明 build() 提前闭合、属性链越界——hvigor 会报 10505001 Unexpected token。
 */
function topLevelChainLines(source) {
  const lines = source.split('\n');
  const hits = [];
  const stack = [];
  for (let n = 0; n < lines.length; n += 1) {
    const line = lines[n];
    if (stack.length > 0 && stack[stack.length - 1] === 'struct' && /^\s*\./.test(line)) {
      hits.push(n + 1);
    }
    let quote = '';
    for (let i = 0; i < line.length; i += 1) {
      const ch = line[i];
      if (quote) { if (ch === quote) { quote = ''; } continue; }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '{') {
        const head = line.slice(0, i);
        stack.push(/(?:^|\s)struct\s+[A-Za-z_$][\w$]*\s*$/.test(head) ? 'struct' : 'block');
      } else if (ch === '}') {
        stack.pop();
      }
    }
  }
  return hits;
}

/**
 * CustomComponent 自带 / CommonMethod 通用的属性名。
 * 组件 struct 的成员（@Param 字段或 private 方法）一旦与它们同名，
 * 该成员会被并入 CustomComponent 的类型，hvigor 直接报 10505001：
 *   - `@Param enabled` → Type 'boolean' is not assignable to '(value: boolean) => CommonAttribute'
 *   - `private background()` → Type '() => ResourceColor' is not assignable to 'background(...)'
 * 这两次都是真实踩过的坑，故固化成守卫规则。
 */
const ATTR_NAMES = new Set([
  'width', 'height', 'size', 'constraintSize', 'margin', 'padding', 'border', 'borderStyle',
  'borderWidth', 'borderColor', 'borderRadius', 'background', 'backgroundColor', 'backgroundImage',
  'backgroundBlurStyle', 'foregroundBlurStyle', 'opacity', 'scale', 'rotate', 'translate', 'transform',
  'clip', 'clipShape', 'shadow', 'blur', 'backdropBlur', 'focusable', 'enabled', 'visibility', 'zIndex',
  'position', 'offset', 'align', 'alignContent', 'animation', 'transition', 'gesture', 'id', 'key',
  'onClick', 'onTouch', 'onHover', 'onFocus', 'onBlur', 'accessibilityText', 'accessibilityLevel',
  'accessibilityGroup', 'hitTestBehavior', 'hoverEffect', 'tabIndex', 'tabStop', 'stateStyles', 'layoutWeight'
]);

/** 取一行里声明的名字（去掉装饰器/修饰符），不是声明行返回空串 */
function memberNameOf(line) {
  const m = /^\s*(?:(?:@\w+|private|public|protected|readonly|static)\s+)*([A-Za-z_$][\w$]*)\s*(?:\(|:|\?)/.exec(line);
  return m === null ? '' : m[1];
}

/** 只收集**直接位于 struct 体**的成员（方法体/interface/对象字面量里的不算） */
function structLevelMembers(source) {
  const found = [];
  const stack = [];
  const lines = source.split('\n');
  for (let n = 0; n < lines.length; n += 1) {
    const line = lines[n];
    if (stack.length > 0 && stack[stack.length - 1] === 'struct') {
      const name = memberNameOf(line);
      if (name !== '') {
        found.push({ line: n + 1, name });
      }
    }
    let quote = '';
    for (let i = 0; i < line.length; i += 1) {
      const ch = line[i];
      if (quote) { if (ch === quote) { quote = ''; } continue; }
      if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
      if (ch === '{') {
        const head = line.slice(0, i);
        stack.push(/(?:^|\s)struct\s+[A-Za-z_$][\w$]*\s*$/.test(head) ? 'struct' : 'block');
      } else if (ch === '}') {
        stack.pop();
      }
    }
  }
  return found;
}

let checks = 0;
function check(name, action) {
  const before = violations.length;
  action();
  assert.equal(violations.length, before, violations.slice(before).join('\n'));
  checks++;
  console.log('PASS ' + name);
}

// ===================== 1. any / unknown =====================
check('no any or unknown type escapes into the refactor', () => {
  lineNumbered((file, line, text) => {
    if (RULE.anyUnknown.test(text)) {
      fail('arkts-no-any-unknown', file, line, text.trim());
    }
  });
});
// ===================== 2. destructuring =====================
check('no destructuring declarations or destructured object literals', () => {
  lineNumbered((file, line, text) => {
    if (RULE.destructuring.test(text) || RULE.destructureParam.test(text)) {
      fail('arkts-no-destructuring', file, line, text.trim());
    }
  });
});
// ===================== 3. object spread =====================
check('no object spread in literals (array spread is allowed)', () => {
  lineNumbered((file, line, text) => {
    if (RULE.objectSpread.test(text)) { fail('arkts-no-spread', file, line, text.trim()); }
  });
});
// ===================== 4. Object.assign =====================
check('no Object.assign anywhere in the refactor', () => {
  lineNumbered((file, line, text) => {
    if (RULE.objectAssign.test(text)) { fail('arkts-no-object-assign', file, line, text.trim()); }
  });
});
// ===================== 5. @Builder chaining =====================
const builderNames = new Set();
(function collectBuilders() {
  const walk = directory => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) { walk(full); continue; }
      if (!entry.name.endsWith('.ets')) { continue; }
      const source = fs.readFileSync(full, 'utf8');
      for (const match of source.matchAll(/@Builder\s+(?:export\s+)?function\s+([A-Za-z_$][\w$]*)/g)) builderNames.add(match[1]);
      for (const match of source.matchAll(/@Builder\s*\n\s*([A-Za-z_$][\w$]*)\s*\(/g)) builderNames.add(match[1]);
    }
  };
  walk(root);
})();
check('no @Builder invocation is chained with attribute calls (' + builderNames.size + ' builders)', () => {
  assert.ok(builderNames.size > 0, 'at least one @Builder must be discovered');
  const names = Array.from(builderNames).map(name => name.replace(/\$/g, '\\$')).join('|');
  const chained = new RegExp('\\b(?:' + names + ')\\s*\\([^()]*\\)\\s*\\.', 'g');
  lineNumbered((file, line, text) => {
    if (chained.test(text)) { fail('arkts-no-builder-chain', file, line, text.trim()); }
    chained.lastIndex = 0;
  });
});
// ===================== 6. API baseline (official names, version <= 26) =====================
const API_BASELINE = new Map([
  ['isInFreeWindowMode', 22], ['freeWindowModeChange', 22], ['setWindowDecorVisible', 11],
  ['setWindowDecorHeight', 11], ['getWindowDecorHeight', 11], ['getTitleButtonRect', 11],
  ['windowTitleButtonRectChange', 11], ['setDecorButtonStyle', 14], ['setWindowTitleButtonVisible', 14],
  ['setTitleAndDockHoverShown', 14], ['startMoving', 14], ['moveWindowTo', 14],
  ['windowWillClose', 15],
  ['getWindowStatus', 12], ['windowStatusChange', 11], ['WindowStatusType', 11],
  ['getWindowAvoidArea', 9], ['avoidAreaChange', 9], ['AvoidAreaType', 9],
  ['setWindowLayoutFullScreen', 9], ['isImmersiveMaterialSupported', 26], ['getGlobalMaterialLevel', 26],
  ['getMaterialInfo', 26], ['ImmersiveMaterial', 26], ['ImmersiveStyle', 26], ['ImmersiveOptions', 26],
  ['MaterialLevel', 26], ['MaterialState', 26], ['systemMaterial', 26], ['backgroundBlurStyle', 11],
  ['backgroundEffect', 11], ['getWindowWidthBreakpoint', 12], ['getUIContext', 12],
  ['getHostContext', 12], ['terminateSelf', 9], ['getCursorController', 12], ['getFocusController', 12],
  ['setWindowSystemBarProperties', 9], ['statusBarContentColor', 9], ['navigationBarContentColor', 9]
]);
const API_TOKEN = /(isInFreeWindowMode|freeWindowModeChange|setWindowDecorVisible|setWindowDecorHeight|getWindowDecorHeight|getTitleButtonRect|windowTitleButtonRectChange|setDecorButtonStyle|setWindowTitleButtonVisible|setTitleAndDockHoverShown|startMoving|moveWindowTo|getWindowStatus|windowStatusChange|WindowStatusType|getWindowAvoidArea|avoidAreaChange|AvoidAreaType|setWindowLayoutFullScreen|isImmersiveMaterialSupported|getGlobalMaterialLevel|getMaterialInfo|ImmersiveMaterial|ImmersiveStyle|ImmersiveOptions|MaterialLevel|MaterialState|systemMaterial|backgroundBlurStyle|backgroundEffect|getWindowWidthBreakpoint|getUIContext|getHostContext|terminateSelf|getCursorController|getFocusController|setWindowSystemBarProperties|statusBarContentColor|navigationBarContentColor)/g;
const usedApis = new Set();
const CLOSE_API_TOKEN = /(windowWillClose)/g;
check('every used window/material API exists by API 26 and is on the official baseline', () => {
  lineNumbered((file, line, text) => {
    for (const match of [...text.matchAll(API_TOKEN), ...text.matchAll(CLOSE_API_TOKEN)]) {
      usedApis.add(match[1]);
      const version = API_BASELINE.get(match[1]);
      if (version === undefined) { fail('arkts-api-unknown', file, line, match[1]); continue; }
      if (version > 26) { fail('arkts-api-too-new', file, line, match[1] + ' needs API ' + version); }
    }
  });
  assert.ok(usedApis.size >= 10, 'expected the refactor to use the window/material APIs');
  console.log('  APIs checked: ' + Array.from(usedApis).sort().join(', '));
});
check('window dragging never uses moveWindowTo (must call startMoving on touch down)', () => {
  lineNumbered((file, line, text) => {
    if (RULE.moveWindowTo.test(text)) { fail('arkts-no-moveWindowTo', file, line, text.trim()); }
  });
});
check('startMoving is reached only from the touch-down / left-press gate', () => {
  for (const file of ['shell/DesktopTitleBar.ets', 'shell/PcWindowBar.ets']) {
    const source = read(file);
    const code = stripComments(source);
    const occurrences = (code.match(/\.startMoving\s*\(/g) || []).length;
    assert.equal(occurrences, 1, file + ' must wrap startMoving in exactly one helper');
    for (const methodName of ['onTitleTouch', 'onTitleMouse']) {
      const match = code.match(new RegExp('^  (?:private )?' + methodName + '\\([\\s\\S]*?^  }', 'm'));
      assert.ok(match, file + ' keeps ' + methodName);
      if (methodName === 'onTitleTouch') assert.match(match[0], /TouchType\.Down/, file + ' must gate on TouchType.Down');
      else assert.match(match[0], /MouseAction\.Press[^\n]*MouseButton\.Left/, file + ' must gate on left press');
      assert.match(match[0], /this\.startMove\(\)/, file + ' ' + methodName + ' calls startMove');
    }
  }
});
// ===================== 7. statusBarContentColor must be 8-digit ARGB =====================
check('statusBarContentColor never receives a 6-digit colour', () => {
  for (const file of FILES) {
    const raw = read(file);
    if (!/statusBarContentColor/.test(raw)) { continue; }
    const sixDigit = raw.match(new RegExp(RULE.sixDigitStatus.source, 'g')) || [];
    assert.deepEqual(sixDigit, [], file + ' passes a 6-digit statusBarContentColor');
    // 该文件内所有颜色字面量都必须是 8 位 ARGB（#AARRGGBB），否则系统会忽略
    for (const match of raw.matchAll(/['"]#([0-9a-fA-F]+)['"]/g)) {
      // 只拒绝 CSS 风格 3/4/6 位色值；8 位 ARGB 与 '#FF' + hex 这类通道前缀是合法写法
      assert.ok(![3, 4, 6].includes(match[1].length),
        file + ' colour literal #' + match[1] + ' is not 8-digit ARGB');
    }
  }
  assert.ok(/statusBarContentColor/.test(read('utils/SystemBars.ets')), 'SystemBars still owns the status bar colour');
});
// ===================== 8. deviceType must not drive breakpoints =====================
check('deviceType never participates in breakpoint/layout branches', () => {
  const allowed = new Set(['utils/DeviceProfile.ets', 'entryability/EntryAbility.ets']);
  const breakpointToken = /\b(?:breakPoint|BreakPoint|tier|LayoutTier|isWide|WIDTH_(?:XS|SM|MD|LG|XL)|getWindowWidthBreakpoint)\b/;
  lineNumbered((file, line, text) => {
    if (!/deviceType/.test(text)) { return; }
    if (!allowed.has(file)) { fail('one-multi-breakpoint-check', file, line, 'deviceType outside DeviceProfile/EntryAbility: ' + text.trim()); }
    if (breakpointToken.test(text)) { fail('one-multi-breakpoint-check', file, line, 'deviceType and breakpoint on one line: ' + text.trim()); }
  });
  const titleBar = stripComments(read('shell/DesktopTitleBar.ets'));
  assert.doesNotMatch(titleBar, /deviceInfo/, 'the title bar must use free-window mode, never deviceInfo');
  assert.ok(!stripComments(read('shell/AppShell.ets')).includes('DesktopTitleBar({'),
    'the main fusion layout must not mount an extra full-width title bar');
  assert.match(stripComments(read('shell/ProjectSidebar.ets')), /startWindowMove/,
    'sidebar header owns its window-drag hot zone');
  assert.match(stripComments(read('utils/DesktopWindowChrome.ets')),
    /setWindowTitleButtonVisible\(true, true, true\)/, 'system native title buttons remain visible');
});
// ===================== 9. module-level const collisions (per file only) =====================
function duplicateModuleConsts(file, source) {
  const seen = new Set();
  const duplicates = [];
  stripComments(source).split('\n').forEach((text, index) => {
    const match = text.match(/^(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*[:=]/);
    if (!match) { return; }
    if (seen.has(match[1])) duplicates.push({ name: match[1], line: index + 1 });
    seen.add(match[1]);
  });
  return duplicates;
}
check('module-level const names are unique per file (cross-file reuse is legal)', () => {
  for (const file of FILES) {
    for (const duplicate of duplicateModuleConsts(file, read(file))) {
      fail('arkts-duplicate-const', file, duplicate.line, duplicate.name);
    }
  }
  // 正例：不同文件里的同名模块级 const 合法，不得误报
  const virtual = duplicateModuleConsts('a.ets', 'const KEY_GRAVE: number = 1;\n') && [];
  assert.deepEqual(virtual, []);
  assert.deepEqual(duplicateModuleConsts('b.ets', 'const KEY_GRAVE: number = 1;\n'), [],
    'the same const in another file must not be reported');
  assert.deepEqual(duplicateModuleConsts('c.ets', 'const X: number = 1;\nconst X: number = 2;\n'), [{ name: 'X', line: 2 }]);
});
// ===================== 10. imports resolve to real files and exported symbols =====================
function resolveImport(fromFile, specifier) {
  const base = path.resolve(path.dirname(path.join(root, fromFile)), specifier);
  const candidates = [base, base + '.ets', path.join(base, 'index.ets')];
  return candidates.find(candidate => fs.existsSync(candidate) && fs.statSync(candidate).isFile());
}
function exportsSymbol(source, symbol) {
  if (new RegExp('\\bexport\\s+(?:default\\s+)?(?:declare\\s+)?(?:abstract\\s+)?(?:class|struct|function|const|let|var|enum|interface|type)\\s+' +
    symbol.replace(/\$/g, '\\$') + '\\b').test(source)) return true;
  if (new RegExp('\\bexport\\s*\\{[^}]*\\b' + symbol.replace(/\$/g, '\\$') + '\\b').test(source)) return true;
  if (/\bexport\s+default\b/.test(source)) return true;
  if (/\bexport\s+\*/.test(source)) return true;
  return false;
}
check('every relative import points to an existing file that exports the imported name', () => {
  let imports = 0;
  for (const file of FILES) {
    const raw = read(file);
    const pattern = /import\s+(?:type\s+)?(?:([A-Za-z_$][\w$]*)\s*(?:,\s*)?)?(?:\{([^}]*)\})?\s*from\s*['"]([^'"]+)['"]/g;
    for (const match of raw.matchAll(pattern)) {
      const specifier = match[3];
      if (!specifier.startsWith('.')) { continue; }
      imports++;
      const target = resolveImport(file, specifier);
      assert.ok(target, file + ' import target missing: ' + specifier);
      const source = fs.readFileSync(target, 'utf8');
      const names = (match[2] || '').split(',').map(part => part.trim()).filter(Boolean)
        .map(part => part.replace(/^type\s+/, '').split(/\s+as\s+/)[0].trim());
      if (match[1]) names.push(match[1]);
      for (const name of names) {
        assert.ok(exportsSymbol(source, name), file + ' imports ' + name + ' but ' + specifier + ' does not export it');
      }
    }
  }
  assert.ok(imports >= 40, 'expected the refactor to keep its import graph');
  console.log('  relative imports checked: ' + imports);
});
// ===================== 11. console.* is legacy-only =====================
check('console.* is confined to the two legacy editor files (reported as warnings)', () => {
  const legacy = new Set(['editor/flowtext/CanvasTextEditor.ets', 'editor/flowtext/ime/ImeBridge.ets']);
  for (const file of FILES) {
    const raw = read(file);
    const occurrences = (raw.match(new RegExp(RULE.consoleCall.source, 'g')) || []).length;
    if (occurrences === 0) { continue; }
    if (legacy.has(file)) {
      warnings.push(file + ': ' + occurrences + ' legacy console.* call(s) — historical, keep using Logger in new code');
      continue;
    }
    fail('arkts-no-console', file, 1, occurrences + ' console.* call(s) outside the legacy allowlist');
  }
  for (const entry of warnings) { console.log('WARN ' + entry); }
});
// ===================== 12. module.json5 immersive metadata =====================
check('module.json5 enables the API 26 immersive material metadata', () => {
  const json = fs.readFileSync(moduleJson, 'utf8');
  assert.match(json, /"name"\s*:\s*"ohos\.arkui\.UIMaterial\.state"/);
  assert.match(json, /"value"\s*:\s*"enable"/);
  for (const type of ['phone', 'tablet', '2in1']) {
    assert.match(json, new RegExp('"' + type + '"'), 'deviceTypes must keep ' + type);
  }
});
// ===================== 13. desktop title bar wiring =====================
check('PcWindowBar is a thin shell that renders DesktopTitleBar', () => {
  const source = stripComments(read('shell/PcWindowBar.ets'));
  assert.match(source, /import \{ DesktopTitleBar \} from '\.\/DesktopTitleBar'/);
  assert.match(source, /DesktopTitleBar\(\{ app: this\.app \}\)/);
  for (const name of ['win', 'startMove', 'minimize', 'toggleMaximize', 'close', 'onTitleTouch', 'onTitleMouse']) {
    assert.match(source, new RegExp('^  (?:private )?' + name + '\\(', 'm'), 'PcWindowBar keeps ' + name);
  }
});
// ===================== 14. immersive material degradation =====================
check('material degradation is explicit: unsupported or low-tier devices disable blur', () => {
  const light = stripComments(read('constants/LightTokens.ets'));
  assert.match(light, /isImmersiveMaterialSupported\(\)/);
  assert.match(light, /getGlobalMaterialLevel\(\)/);
  assert.match(light, /MaterialLevel\.SMOOTH/);
  assert.match(light, /WeaverGlassLevel\.OFF/);
  const surface = stripComments(read('shell/MaterialSurface.ets'));
  assert.match(surface, /if \(this\.spec\.blurEnabled && blurEnabled\(\)\)/, 'blur must be gated per surface');
  assert.match(surface, /gradientSolid/, 'a zero-blur solid gradient fallback is required');
  assert.match(light, /GLASS_MAX_BLUR_LAYERS\s*:\s*number\s*=\s*2/, 'at most two live blur layers per screen');
});

// ===================== 16. 属性链不得落到 struct 成员层 =====================
check('every chained attribute stays inside its component block', () => {
  const components = ['shell/TopActionButton.ets', 'shell/EditorTools.ets', 'shell/DocListPane.ets',
    'shell/ProjectSidebar.ets', 'shell/FocusWorkspace.ets', 'shell/MaterialSurface.ets',
    'shell/AppShell.ets', 'shell/EditorPane.ets'];
  for (const file of components) {
    for (const line of topLevelChainLines(stripComments(read(file)))) {
      fail('arkts-chain-outside-block', file, line,
        'attribute chain at struct member level — build() closed before its modifiers');
    }
  }
});

// ===================== 17. struct 成员不得与内置属性同名 =====================
check('no struct member shadows a built-in CommonAttribute name', () => {
  // 扫全部 shell 组件，而不是手工维护的白名单：UserAvatar 的 @Param size 就是这样漏掉的
  // （'size' 是 CustomComponent 自带属性，@Param 同名直接 10505001 编译失败）。
  const components = fs.readdirSync(path.join(root, 'shell'))
    .filter(name => name.endsWith('.ets'))
    .map(name => 'shell/' + name);
  for (const file of components) {
    for (const member of structLevelMembers(stripComments(read(file)))) {
      if (ATTR_NAMES.has(member.name)) {
        fail('arkts-member-shadow', file, member.line,
          'member "' + member.name + '" collides with CustomComponent attribute');
      }
    }
  }
});

// ===================== 15. guard self-test（防止规则空转成"假绿"） =====================
check('the guard rules actually flag synthetic red-line snippets', () => {
  assert.equal(RULE.anyUnknown.test('let value: any = 1'), true);
  assert.equal(RULE.anyUnknown.test('let value: unknown'), true);
  assert.equal(RULE.anyUnknown.test('let value: number = 1'), false);
  assert.equal(RULE.destructuring.test('const { a, b } = source'), true);
  assert.equal(RULE.destructuring.test('const value = { a: 1 }'), false);
  assert.equal(RULE.destructureParam.test('function pick({ name }) {}'), true);
  assert.equal(RULE.destructureParam.test('const pick = ({ name }) => name'), true);
  assert.equal(RULE.destructureParam.test('showDialog({ title: 1 })'), false);
  assert.equal(RULE.objectSpread.test('const copy = { ...source }'), true);
  assert.equal(RULE.objectSpread.test('const list = [...values]'), false);
  assert.equal(RULE.objectAssign.test('Object.assign(target, source)'), true);
  assert.equal(RULE.moveWindowTo.test('win.moveWindowTo(1, 2)'), true);
  assert.equal(RULE.sixDigitStatus.test("statusBarContentColor: '#000000'"), true);
  assert.equal(RULE.sixDigitStatus.test("statusBarContentColor: '#FF000000'"), false);
  assert.equal(RULE.consoleCall.test('console.info(msg)'), true);
  assert.equal(duplicateModuleConsts('x.ets', 'const A = 1;\nconst A = 2;\n').length, 1);
  assert.equal(duplicateModuleConsts('y.ets', 'const A = 1;\n').length, 0);
  assert.equal(exportsSymbol('export struct Foo {}', 'Foo'), true);
  assert.equal(exportsSymbol('struct Foo {}', 'Foo'), false);
  // @Param size 这类"继承自 CustomComponent 的属性名"必须能被守卫抓到
  assert.deepEqual(structLevelMembers('export struct X {\n  @Param size: number = 1;\n}').map(m => m.name), ['size']);
  // @Builder 链式调用规则对合成片段同样生效
  // 属性链越界规则：build() 提前闭合会被抓到，块内链式调用不受影响
  assert.deepEqual(topLevelChainLines('export struct X {\n  build() {\n    Stack() {\n    }\n  }\n  .width(1)\n}'), [6]);
  assert.deepEqual(topLevelChainLines('export struct X {\n  build() {\n    Stack() {\n    }\n    .width(1)\n  }\n}'), []);
  // 成员撞名规则：@Param enabled / private background() 必须被抓到，正常命名不受影响
  assert.equal(memberNameOf('  @Param enabled: boolean = true'), 'enabled');
  assert.equal(memberNameOf('  private background(): ResourceColor {'), 'background');
  assert.equal(memberNameOf('  @Param iconSize: number = 20'), 'iconSize');
  assert.equal(memberNameOf('    .width(this.hitSize)'), '');
  assert.equal(ATTR_NAMES.has('enabled') && ATTR_NAMES.has('background'), true);
  assert.equal(ATTR_NAMES.has('iconSize') || ATTR_NAMES.has('overlayColor'), false);
  // 只认 struct 体：interface 字段（LibEntry.id）不算成员撞名
  const shadowSample = 'interface Entry {\n  id: string\n}\nexport struct X {\n  @Param enabled: boolean = true\n  private background(): number {\n    return 1\n  }\n}';
  assert.deepEqual(structLevelMembers(shadowSample).map(m => m.name), ['enabled', 'background']);

  assert.ok(new RegExp('\\bGlowPageBackground\\s*\\([^()]*\\)\\s*\\.').test('GlowPageBackground(theme).width(1)'));
});

if (violations.length > 0) {
  console.error(violations.map(violation => 'FAIL ' + violation).join('\n'));
  process.exitCode = 1;
} else {
  console.log(`ArkTS guard: ${checks} checks passed (${FILES.length} files scanned, ${warnings.length} warning(s))`);
}
