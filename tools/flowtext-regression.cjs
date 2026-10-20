// Node 24+. Executes project model/interaction code; graphics and IME are controlled doubles.
// Native shaping is tested separately by entry/src/ohosTest/ets/test/FlowText.test.ets.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { stripTypeScriptTypes } = require('node:module');
const root = path.resolve(__dirname, '../entry/src/main/ets');
let nativeAttachCount = 0, nativeDetachCount = 0, resolveAttach, nativeAttached=false;
const listeners = new Map();
const controller = {
  on(event, fn) { if (!['setPreviewText','finishTextPreview'].includes(event)) assert.ok(nativeAttached,'regular listeners require an attached native client'); if (!listeners.has(event)) listeners.set(event, new Set()); listeners.get(event).add(fn); },
  off(event, fn) { assert.ok(fn, 'must remove only owned callbacks'); listeners.get(event)?.delete(fn); },
  attach() { nativeAttachCount++; return new Promise(resolve => { resolveAttach = () => {nativeAttached=true;resolve();}; }); },
  detach() { nativeDetachCount++; nativeAttached=false; return Promise.resolve(); },
  updateCursor() { return Promise.resolve(); }, changeSelection() { return Promise.resolve(); }
};
class Font { setSize(size) { this.size = size; } }
class Brush { setColor(color) { this.color = color; } setAntiAlias(enabled) { this.antiAlias = enabled; } }
// Capture native builder input exactly; scalar indices model the LineTypeset contract.
class ParagraphBuilder {
  constructor(style) { this.spans = []; this.styles = [style.textStyle]; }
  addText(value) { this.spans.push({text:value,style:this.styles.at(-1)}); }
  pushStyle(style) { this.styles.push(style); }
  popStyle() { this.styles.pop(); }
  buildLineTypeset() {
    const value = this.spans.map(span=>span.text).join('');
    const scalars = Array.from(value);
    return {value,spans:this.spans,
      getLineBreak(start) { return Math.min(5,scalars.length-start); },
      createLine(start,count) {
        const glyphs=scalars.slice(start,start+count).map(s=>s.codePointAt(0));
        const font=new Font();
        return {
          getTextRange() { return {start:0,end:count}; },
          getTypographicBounds() { return {ascent:14,descent:4,leading:0,width:count*10}; },
          getGlyphRuns() { return [{
            getStringRange() { return {start:0,end:count}; },
            getStringIndices() { return glyphs.map((_,i)=>i); },
            getGlyphs() { return glyphs; }, getFont() { return font; },
            getAdvances() { return glyphs.map(()=>({x:10,y:0})); },
            getPositions() { return glyphs.map((_,i)=>({x:i*10,y:0})); }
          }]; },
          getOffsetForStringIndex(index) { return index*10; },
          getStringIndexForPosition(point) { return Math.max(0,Math.min(count,Math.round(point.x/10))); }
        };
      }
    };
  }
}
const draws = [];
// KeyCode 受控替身：官方 js-apis-keycode（API 26）数值，仅用于在 Node 里驱动 .ets 源码。
const keyCodes = {
  KEYCODE_0:2000, KEYCODE_1:2001, KEYCODE_2:2002, KEYCODE_3:2003, KEYCODE_4:2004,
  KEYCODE_5:2005, KEYCODE_6:2006, KEYCODE_7:2007, KEYCODE_8:2008, KEYCODE_9:2009,
  KEYCODE_DPAD_UP:2012, KEYCODE_DPAD_DOWN:2013, KEYCODE_DPAD_LEFT:2014, KEYCODE_DPAD_RIGHT:2015,
  KEYCODE_COMMA:2043, KEYCODE_PERIOD:2044, KEYCODE_TAB:2049, KEYCODE_SPACE:2050, KEYCODE_ENTER:2054, KEYCODE_DEL:2055,
  KEYCODE_GRAVE:2056, KEYCODE_MINUS:2057, KEYCODE_EQUALS:2058, KEYCODE_LEFT_BRACKET:2059,
  KEYCODE_RIGHT_BRACKET:2060, KEYCODE_BACKSLASH:2061, KEYCODE_SEMICOLON:2062, KEYCODE_APOSTROPHE:2063,
  KEYCODE_SLASH:2064, KEYCODE_AT:2065, KEYCODE_PLUS:2066, KEYCODE_PAGE_UP:2068, KEYCODE_PAGE_DOWN:2069,
  KEYCODE_ESCAPE:2070, KEYCODE_FORWARD_DEL:2071, KEYCODE_MOVE_HOME:2081, KEYCODE_MOVE_END:2082, KEYCODE_F11:2100,
  KEYCODE_NUMPAD_ENTER:2119, KEYCODE_NUMPAD_ADD:2116, KEYCODE_NUMPAD_SUBTRACT:2115,
  KEYCODE_NUMPAD_MULTIPLY:2114, KEYCODE_NUMPAD_DIVIDE:2113, KEYCODE_NUMPAD_DOT:2117,
  KEYCODE_NUMPAD_COMMA:2118, KEYCODE_NUMPAD_EQUALS:2120, KEYCODE_NUMPAD_LEFT_PAREN:2121, KEYCODE_NUMPAD_RIGHT_PAREN:2122
};
for (let i = 0; i < 26; i++) { keyCodes['KEYCODE_' + String.fromCharCode(65 + i)] = 2017 + i; }
// 官方 js-apis-keycode：KEYCODE_NUMPAD_0=2103 … NUMPAD_9=2112（2100 是 F11，不能复用）
for (let i = 0; i < 10; i++) { keyCodes['KEYCODE_NUMPAD_' + i] = 2103 + i; }
const context = vm.createContext({console, setTimeout() {return 1;}, clearTimeout() {},
  text: { FontCollection: { getGlobalInstance() { return {}; } }, ParagraphBuilder,
    FontWeight:{W700:700}, FontStyle:{ITALIC:1} },
  drawing: {Font, Brush, TextBlob: {makeFromRunBuffer(buffer, font) {return {buffer,font};}}},
  KeyCode: keyCodes, KeyType:{Down:0}, ChapterFormat:{TXT:0},
  TouchType:{Down:0,Up:1,Move:2,Cancel:3},
  SourceTool: { UNKNOWN: 0, FINGER: 1, STYLUS: 2, MOUSE: 3, TOUCHPAD: 4, JOYSTICK: 5 },
  Logger:{info(){}}, inputMethod:{getController(){return controller;}}
});
const read = file => fs.readFileSync(path.join(root,file),'utf8');
function compile(source) {
  return stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm,'')
    .replace(/\bexport\s+/g,'').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,''), {mode:'transform'});
}
function load(file) {vm.runInContext(compile(read(file)),context,{filename:file});}
for (const file of ['model/EditorTypes','model/TextIndexMap','model/UnicodeGraphemeData','model/GraphemeUtil','model/TextDocument','theme/TypewriterScale',
  'interaction/SelectionManager','interaction/CursorState','interaction/HitTester','render/TextLayoutEngine',
  'render/LayoutCache','render/GlyphRenderer','animation/GlyphAnimator','ime/PreviewTextManager','ime/KeyboardHandler','ime/ImeBridge']) {
  load('editor/flowtext/'+file+'.ets');
}
for (const file of ['editor/interaction/EditCommand','editor/interaction/ShortcutMap',
  'editor/interaction/EditorCommandRouter','editor/interaction/InputArbiter']) load(file+'.ets');
// 真实适配器（struct 内实现）从源码末尾抽出：验证 router -> host 的接线本身，而不是替身。
const adapterSource = read('editor/flowtext/CanvasTextEditor.ets').match(/^class CanvasEditCommandHost[\s\S]*?^\}/m);
assert.ok(adapterSource, 'CanvasEditCommandHost adapter class');
vm.runInContext(compile(adapterSource[0].replace(/ implements EditCommandHost/, '')), context);
load('store/StoreModels.ets'); load('store/EditorStore.ets');
function method(source,name) {
  const match = source.match(new RegExp('^  (?:private )?'+name+'\\([\\s\\S]*?^  }','m'));
  assert.ok(match,'source method '+name); return match[0];
}
function uiCallback(file,name,indent) {
  const padding=' '.repeat(indent);
  const match=read(file).match(new RegExp('^'+padding+name+': (\\([^\\n]*\\) => \\{[\\s\\S]*?^'+padding+'\\})','m'));
  assert.ok(match,'source callback '+file+' '+name);
  return vm.runInContext(compile('(function '+match[1].replace(' => ',' ')+')'),context);
}
vm.runInContext(compile(read('editor/flowtext/CanvasTextEditor.ets').split('@Component')[0]),context);
const canvas = read('editor/flowtext/CanvasTextEditor.ets').split('export struct CanvasTextEditor {')[1];
vm.runInContext(compile('class EditorProbe {\n'+['loadDocument','currentText','getRuns','moveCaretTo','moveCaretAnimated','insertExternalText','extendSelection',
  'selectTo','applyKeyCommand','afterCaretMove','afterEdit','emitSelection','setRuns','afterFormatChange',
  'handleKeyPreIme','handleKeyEvent','isNavigationAction','readModifiers','registerImeCallbacks','refreshPreview','displayText','displayCaret','deletePreview','deleteExternalLeft',
  'readEditorModifiers','adoptKeyFocus','dispatchCommand','editHost','insertFromKeyboard','hostInsertText','hostDismiss','handleMenuKey',
  'pasteAtCaret','insertAtCaret','aboutToDisappear','hasCaretLayout','cancelCaretLayout','deferCaretLayout','continueCaretLayout','clearPreviewLayout','settleCaret','drawNow','reportCursor',
  'affinityAt','inlineStyleMask','styleMaskAt','visualCaret','reportSelection','handleTouch','stopCaretAnimation','stopScrollAnimation','stopGlyphAnimation','syncSelectionToCaret','handlePositions','selectAllText',
  'captureViewAnchor','refreshDensity','ensureLayoutThroughY','engineSignature','extendWordSelection','clampScroll','tailPadVp','laidOutHeightVp',
  'effectivePolicy','leadPadVp','paragraphStartAt','paragraphEndAt','refreshTypewriterFocus','typewriterScrollTarget','ensureCaretVisible','followTypewriter','placeCaretImmediately','isPointerInput','retargetTypewriterScale','snapTypewriterScale','stopTypewriterScaleAnimation'].map(name=>method(canvas,name)).join('\n')+'\n  loadText(text: string): void { this.loadDocument(text, [], text.length); }\n  currentCaret(): number { return this.doc.caretOffset; }\n}'),context);
vm.runInContext(compile('class HostProbe {\n'+method(read('editor/TextEditorHost.ets'),'onContentRevChanged')+'\n}'),context);
const api = vm.runInContext('({TextIndexMap,GraphemeUtil,TextDocument,SelectionManager,FormatRun,StyleKind,LayoutLine,GlyphRunData,'+
  'CursorState,HitTester,TextLayoutEngine,LayoutCache,GlyphRenderer,RenderTheme,ViewportInfo,GlyphAnimator,GlyphDiffOptions,'+
  'PreviewTextManager,KeyAction,KeyboardEvent,KeyboardHandler,ImeBridge,CanvasTextEditorController,EditorProbe,HostProbe,EditorStore,OpenDoc,CaretAffinity,LineBox,PreviewInfo,'+
  'EditCommand,EditCommandKind,EditorInputSource,EditorModifiers,EditorCommandRouter,ImeEchoGuard,shouldConsumePreIme,isCaretCommand,isEditingCommand,resolveShortcut,KeyCode,'+
  'TypewriterScaleOptions,typewriterLineDistance,typewriterScaleForDistance,typewriterDimWeight})',context);
let count=0;
function check(name, fn) {fn(); count++; console.log('PASS '+name);}
check('native scalar offsets convert to UTF-16',()=>{const map=new api.TextIndexMap('A😀中B');assert.equal(map.fromScalar(2),3);assert.equal(map.toScalar(3),2);assert.equal(map.toScalar(2),1);assert.equal(map.fromScalar(4),5);});
const json=value=>JSON.parse(JSON.stringify(value));
const doc=value=>{const d=new api.TextDocument();d.setText(value);return d;};
check('Unicode 17 official grapheme fixture, both directions and every UTF-16 boundary',()=>{
  let cases=0;
  for(const line of fs.readFileSync(path.join(__dirname,'unicode/GraphemeBreakTest.txt'),'utf8').split('\n')) {
    const content=line.split('#')[0].trim();if(!content)continue;
    let value='', expected=[];
    for(const token of content.split(/\s+/)) {
      if(token==='÷')expected.push(value.length);
      else if(token!=='×')value+=String.fromCodePoint(parseInt(token,16));
    }
    let forward=[0],at=0;
    while(at<value.length){at=api.GraphemeUtil.moveRight(value,at);forward.push(at);}
    assert.deepEqual(forward,expected,content);
    let backward=[value.length];at=value.length;
    while(at>0){at=api.GraphemeUtil.moveLeft(value,at);backward.unshift(at);}
    assert.deepEqual(backward,expected,content);
    for(let i=0;i<=value.length;i++)assert.equal(api.GraphemeUtil.isBoundary(value,i),expected.includes(i),content+' @'+i);
    cases++;
  }
  console.log('  Unicode cases: '+cases);
});
for(const value of ['A😀','甲𠮷','a👨‍👩‍👧','A👍🏽','A🇨🇳','Ae\u0301']) {
  check('backspace preserves prefix '+value,()=>{const d=doc(value);d.deleteLeft(1);assert.equal(d.text,value[0]);});
}
check('delete arbitrary range cannot split emoji',()=>{const d=doc('A😀B');d.delete(2,3);assert.equal(d.text,'AB');});
check('caret and selection do not invalidate content version',()=>{const d=doc('abc');const v=d.version;d.moveCaret(1);d.setSelection(2,0);assert.equal(d.version,v);assert.equal(d.caretOffset,0);});
check('bold toggling fills default gaps',()=>{const d=doc('abcd');d.setRuns([new api.FormatRun(0,1,true)]);d.toggleInline(api.StyleKind.BOLD,0,4);assert.deepEqual(json(d.runs.map(r=>[r.startOffset,r.endOffset,r.bold])),[[0,4,true]]);});
function editor(value) {
  const e = new api.EditorProbe();
  Object.assign(e,{doc:doc(value),selMgr:new api.SelectionManager(),previewMgr:new api.PreviewTextManager(),
    lastText:value,preferredX:-1,anims:{clear(){}},lines:[],caret:new api.CursorState(),
    theme:{fontSize:16,typewriterScaleAnimated:false,typewriterScaleDurationMs:180},
    twAnimFirst:-1,twAnimLast:-1,twTargetFirst:-1,twTargetLast:-1,twScaleInitialized:false,twScaleAnimator:null,
    cache:null,engineRef:null,renderer:null,onEdit:null,onCaretChange:null,onTextChange:null,onFormatChange:null,onSelectionChange:null,
    documentGeneration:0,controller:null,ime:new api.ImeBridge(),caretAnimator:null,glyphAnimator:null,scrollAnimator:null,
    caretAnimating:false,viewHeightVp:600,scrollY:0,
    commandRouter:new api.EditorCommandRouter(),hostAdapter:null,echoGuard:new api.ImeEchoGuard(),
    imeUsable:false,focused:false,focusConfirmed:false,menuVisible:false,menuIndex:0,previewDoc:null,previewCache:null,
    caretLayoutTimer:-1,caretLayoutRevision:0,caretLayoutPending:false,caretLayoutHidden:false,caretLayoutRestoreVisible:true,
    previewBaseVersion:-1,previewBaseFormatVersion:-1,previewLayoutStart:-1,
    startBlink(){},
    padLeftVp(){return 0;},padTopVp(){return 0;},ensureCaretLayout(){},ensureVisibleLayout(){},ensureCaretVisible(){},effectivePolicy(){return 0;},
    relayout(){},drawNow(){},reportSelection(){},reportCursor(){},hideSelectionMenu(){},diag(){},
    cancelLongPress(){},stopBlink(){},stopFling(){},
    animateCaretMove(from,to){this.caret=to;}});
  e.selMgr.setSource(value);e.selMgr.collapse(e.doc.caretOffset);return e;
}
check('switch document clears stale selection before inserting',()=>{const e=editor('ABCDE');e.selMgr.setSelection(1,3);e.loadText('uvwxyz');e.moveCaretAnimated(6);e.insertExternalText('!');assert.equal(e.doc.text,'uvwxyz!');});
check('paste replaces a selection in either direction in one edit',()=>{
  for(const [anchor,head] of [[1,4],[4,1]]) {
    const e=editor('ABCDE');e.doc.setRuns([new api.FormatRun(0,5,true)]);
    e.selMgr.setSelection(anchor,head);e.emitSelection();let edits=0;e.onEdit=()=>edits++;
    e.insertAtCaret('X');assert.equal(e.doc.text,'AXE');assert.equal(e.doc.caretOffset,2);
    assert.ok(e.selMgr.selection.isEmpty());assert.equal(edits,1);
    assert.deepEqual(json(e.doc.runs),[json(new api.FormatRun(0,3,true))]);
  }
});
check('paste replaces the provisional composition range in one edit',()=>{
  const e=editor('ABCDE');e.selMgr.setSelection(1,3);e.emitSelection();e.engineRef=null;e.registerImeCallbacks();
  e.ime.onPreviewText('ni',-1,-1);let edits=0;e.onEdit=()=>edits++;e.insertAtCaret('X');
  assert.equal(e.doc.text,'AXDE');assert.equal(e.previewMgr.isComposing,false);assert.equal(edits,1);
});
check('continuous Shift Left preserves anchor and direction',()=>{const e=editor('ABCDE');e.moveCaretAnimated(4);e.extendSelection(-1);e.extendSelection(-1);assert.deepEqual(json(e.selMgr.selection),{startOffset:2,endOffset:4});assert.equal(e.doc.caretOffset,2);assert.equal(e.doc.selectionEnd,4);e.extendSelection(1);assert.equal(e.doc.caretOffset,3);});
check('empty IME commit preserves selected text, anchor, formats and history',()=>{
  const e=editor('ABCDE');e.doc.setRuns([new api.FormatRun(0,5,true)]);e.moveCaretAnimated(4);e.extendSelection(-1);
  e.ime=new api.ImeBridge();e.registerImeCallbacks();let edits=0;e.onEdit=()=>edits++;
  const version=e.doc.version,formats=json(e.doc.runs);e.ime.onInsertText('');
  assert.equal(e.doc.text,'ABCDE');assert.equal(e.doc.caretOffset,3);assert.equal(e.doc.version,version);
  assert.deepEqual(json(e.doc.runs),formats);assert.deepEqual(json(e.selMgr.selection),{startOffset:3,endOffset:4});
  assert.equal(e.selMgr.anchor,4);assert.equal(e.selMgr.head,3);assert.equal(edits,0);e.extendSelection(-1);
  assert.deepEqual(json(e.selMgr.selection),{startOffset:2,endOffset:4});
});
check('finishing an empty composition still replaces its original range',()=>{
  const e=editor('ABCDE');e.selMgr.setSelection(1,3);e.emitSelection();e.ime=new api.ImeBridge();e.engineRef=null;
  e.registerImeCallbacks();let edits=0;e.onEdit=()=>edits++;e.ime.onPreviewText('',-1,-1);e.ime.onPreviewFinish();
  assert.equal(e.doc.text,'ADE');assert.equal(e.doc.caretOffset,1);assert.equal(e.previewMgr.isComposing,false);
  assert.equal(edits,1);
});
check('Left collapses selection at its start',()=>{const e=editor('ABCDE');e.selMgr.setSelection(1,3);e.emitSelection();const cmd=new api.KeyboardEvent();cmd.action=api.KeyAction.MOVE_LEFT;e.applyKeyCommand(cmd);assert.equal(e.doc.caretOffset,1);assert.ok(e.selMgr.selection.isEmpty());});
check('composition does not intercept candidate navigation',()=>{const e=editor('abc');e.focused=true;e.previewMgr.update('ni',-1,-1,3,3);assert.equal(e.handleKeyPreIme({keyCode:2012,type:0,keyText:''}),false);});
check('Ctrl Home and Shift Home have correct scope',()=>{assert.equal(api.KeyboardHandler.translate(2081,'',true,true,false,false).action,api.KeyAction.MOVE_DOC_START);assert.equal(api.KeyboardHandler.translate(2081,'',true,false,true,false).action,api.KeyAction.MOVE_LINE_START);});
check('preview replacement, insertion, commit snapshot and invalid range',()=>{const p=new api.PreviewTextManager();p.update('aaa',-1,-1,5,7);p.update('b',6,7);assert.equal(p.previewInfo.text,'aba');p.update('X',6,6);assert.equal(p.previewInfo.text,'aXba');assert.equal(p.update('?',-3,99),false);const result=p.commit();assert.equal(result.text,'aXba');assert.equal(result.startOffset,5);assert.equal(result.endOffset,7);assert.equal(p.isComposing,false);});
check('IME preview replaces selected text and commits exactly once',()=>{const e=editor('abcXYZ');e.selMgr.setSelection(1,3);e.emitSelection();e.ime=new api.ImeBridge();e.engineRef=null;e.registerImeCallbacks();let events=0;e.onEdit=()=>events++;e.ime.onPreviewText('ni',-1,-1);assert.equal(e.displayText(),'aniXYZ');assert.equal(e.doc.text,'abcXYZ');assert.equal(events,0);e.ime.onPreviewText('你',-1,-1);e.ime.onPreviewFinish();assert.equal(e.doc.text,'a你XYZ');assert.equal(events,1);e.ime.onPreviewFinish();assert.equal(events,1);});
check('backspace during composition edits provisional text only',()=>{const e=editor('正文');e.ime=new api.ImeBridge();e.engineRef=null;e.registerImeCallbacks();e.ime.onPreviewText('ni',-1,-1);e.ime.onDeleteLeft(1);assert.equal(e.doc.text,'正文');assert.equal(e.displayText(),'正文n');e.ime.onPreviewFinish();assert.equal(e.doc.text,'正文n');});
check('typing persists text, moved formats and caret in one transaction',()=>{const e=editor('abc');e.doc.setRuns([new api.FormatRun(0,3,true)]);e.moveCaretAnimated(0);let events=[];e.onEdit=(text,runs,caret)=>events.push([text,json(runs),caret]);e.insertExternalText('X');assert.equal(events.length,1);assert.equal(events[0][0],'Xabc');assert.equal(events[0][1][0].endOffset,4);assert.equal(events[0][2],1);assert.ok(e.selMgr.selection.isEmpty());});
check('loading format does not report a user edit',()=>{const e=editor('abc');let events=0;e.onEdit=()=>events++;e.onFormatChange=()=>events++;e.setRuns([new api.FormatRun(0,3,true)]);assert.equal(events,0);});
check('controller load preserves formats and saved caret before binding',()=>{const controller=new api.CanvasTextEditorController();controller.setDocument('abc',[new api.FormatRun(0,3,true)],1);const e=editor('');controller.bind(e);assert.equal(e.doc.text,'abc');assert.equal(e.doc.caretOffset,1);assert.equal(e.doc.runs[0].bold,true);});
check('undo restores content before format',()=>{const e=editor('abcX');const host=new api.HostProbe();Object.assign(host,{docId:'a',contentRev:2,appliedRev:1,loadText(){return 'abc';},loadCaret(){return 2;},loadFormat(){return [new api.FormatRun(0,3,true)];},flowController:{getText(){return e.doc.text;},setDocument(value,runs,caret){e.loadDocument(value,runs,caret);},setText(v){e.loadText(v);},setRuns(r){e.setRuns(r);},setCaretPosition(n){e.moveCaretAnimated(n);}}});host.onContentRevChanged();assert.equal(e.doc.text,'abc');assert.equal(e.doc.runs[0].endOffset,3);});
check('undo/redo availability follows the active document',()=>{const store=new api.EditorStore();store.scheduleFlush=()=>{};const a=new api.OpenDoc('a','A',0,'','a',0);const b=new api.OpenDoc('b','B',0,'','b',0);store.openDocs=[a,b];store.activeId='a';store.setEditorState('a1','',1);assert.equal(store.canUndo,true,'A has history');store.activeId='b';assert.equal(store.canUndo,false,'B has no history');assert.equal(store.canRedo,false);store.activeId='a';assert.equal(store.canUndo,true);store.undo();assert.equal(store.canUndo,false);assert.equal(store.canRedo,true);store.activeId='b';assert.equal(store.canRedo,false,'redo state must not leak into another document');});
check('history preserves other documents and clears redo after new edits',()=>{const store=new api.EditorStore();store.scheduleFlush=()=>{};const a=new api.OpenDoc('a','A',0,'','a',0);const b=new api.OpenDoc('b','B',0,'','b',0);store.openDocs=[a,b];store.activeId='a';store.setEditorState('a1','0,1,1,0,0',2);store.activeId='b';store.setEditorState('b1','',2);store.activeId='a';store.undo();assert.equal(a.draft,'a');store.activeId='b';store.undo();assert.equal(b.draft,'b');store.activeId='a';store.setEditorState('a2','',2);store.redo();assert.equal(a.draft,'a2');});
check('heading at a collapsed paragraph start affects the current paragraph',()=>{
  const d=doc('abc\ndef');d.toggleHeading(1,4,4);
  assert.equal(d.headingAt(4),1);assert.equal(d.headingAt(0),0);
  d.toggleHeading(1,4,4);assert.equal(d.runs.length,0);
  d.toggleHeading(1,0,4);assert.equal(d.headingAt(0),1);assert.equal(d.headingAt(4),0);
});
check('new input after undo or redo starts a separate history entry',()=>{
  const originalDate=vm.runInContext('Date',context);let now=1000;context.Date={now:()=>now};
  try {
    const store=new api.EditorStore();store.scheduleFlush=()=>{};
    const d=new api.OpenDoc('a','A',0,'','A',1);store.openDocs=[d];store.activeId='a';
    store.setEditorState('AB','',2);now=2000;store.setEditorState('ABC','',3);store.undo();
    assert.equal(d.draft,'AB');now=2100;store.setEditorState('ABX','',3);store.undo();
    assert.equal(d.draft,'AB');assert.equal(d.caret,2);
    store.redo();assert.equal(d.draft,'ABX');now=2200;store.setEditorState('ABXY','',4);
    now=2250;store.setEditorState('ABXYZ','',5);store.undo();
    assert.equal(d.draft,'ABX');assert.equal(d.caret,3);
  } finally { context.Date=originalDate; }
});
check('caret updates reject an editor belonging to another document',()=>{
  const store=new api.EditorStore();const a=new api.OpenDoc('a','A',0,'','AAAA',1);
  const b=new api.OpenDoc('b','B',0,'','BBBB',4);store.openDocs=[a,b];store.activeId='b';
  store.setCaret(2,'a');assert.equal(b.caret,4);assert.equal(a.caret,1);
  store.setCaret(3,'b');assert.equal(b.caret,3);
  store.setCaret(1);assert.equal(b.caret,1);
});
check('host undo and redo callbacks retain their loaded document owner',()=>{
  const store=new api.EditorStore();store.scheduleFlush=()=>{};
  const a=new api.OpenDoc('a','A',0,'','A',1),b=new api.OpenDoc('b','B',0,'','B',1);
  store.openDocs=[a,b];store.activeId='b';store.setEditorState('B edited','',8);
  const pane={app:{editor:store}};
  const undo=uiCallback('shell/EditorPane.ets','onUndo',12),redo=uiCallback('shell/EditorPane.ets','onRedo',12);
  const host={loadedDocId:'a',onUndo:undo.bind(pane),onRedo:redo.bind(pane)};
  const hostUndo=uiCallback('editor/TextEditorHost.ets','onUndo',8),hostRedo=uiCallback('editor/TextEditorHost.ets','onRedo',8);
  hostUndo.call(host);assert.equal(b.draft,'B edited');assert.equal(store.undoStack.length,1);
  host.loadedDocId='b';hostUndo.call(host);assert.equal(b.draft,'B');
  host.loadedDocId='a';hostRedo.call(host);assert.equal(b.draft,'B');assert.equal(store.redoStack.length,1);
  host.loadedDocId='b';hostRedo.call(host);assert.equal(b.draft,'B edited');assert.equal(a.draft,'A');
});
function line(start,value,y=0) {
  const l=new api.LayoutLine();Object.assign(l,{startIndex:start,endIndex:start+value.length,consumedEnd:start+value.length,yOffset:y,height:24,step:28,baseline:y+18,ascent:14,descent:4,width:value.length*10});
  const r=new api.GlyphRunData();Object.assign(r,{textStart:start,textEnd:l.endIndex,font:new Font(),glyphs:Array.from(value).map(c=>c.charCodeAt(0)),glyphOffsets:Array.from(value).map((_,i)=>i),positions:Array.from(value).map((_,i)=>({x:i*10,y:0})),advances:Array.from(value).map(()=>({x:10,y:16}))});l.runs=[r];return l;
}
check('soft wrap picks following line and column zero stays zero',()=>{const lines=[line(0,'ABC'),line(3,'DEF',28)];assert.equal(api.HitTester.lineIndexOf(3,lines),1);assert.equal(api.HitTester.columnOf(0,lines),0);});
check('native mapping and positions are kept verbatim',()=>{const engine=new api.TextLayoutEngine(400,16,24,4,2);engine.indexMap=new api.TextIndexMap('A😀B');const native={getTextRange(){return {start:0,end:3};},getGlyphRuns(){return [{getStringRange(){return {start:0,end:3};},getStringIndices(){return [0,1,2];},getGlyphs(){return [65,999,66];},getFont(){return new Font();},getAdvances(){return [{x:20,y:0},{x:40,y:0},{x:20,y:0}];},getPositions(){return [{x:0,y:0},{x:20,y:0},{x:60,y:0}];}}];},getTypographicBounds(){return {ascent:40,descent:10,leading:0,width:80};},getOffsetForStringIndex(n){return [0,20,60,80][n];}};const l=engine.buildLayoutLineFrom(native,0,4,0);assert.deepEqual(json(l.runs[0].glyphOffsets),[0,1,3]);assert.equal(l.height,25);assert.equal(api.HitTester.offsetToX(l,1,0),10);});
check('typeset window excludes earlier, later and boundary-only format runs',()=>{
  const engine=new api.TextLayoutEngine(400,16,24,4,1);
  engine.setRuns([new api.FormatRun(0,4,true),new api.FormatRun(8,9,false,true),new api.FormatRun(9,11,true)]);
  const typeset=engine.buildTypesetWindow('ABC\nDEF\nGHI\n',4,8);
  assert.equal(typeset.value,'DEF\n');
  assert.equal(typeset.spans.length,1);
  assert.equal(typeset.spans[0].style.fontWeight,undefined);
  assert.equal(typeset.spans[0].style.fontStyle,undefined);
});
check('typeset window clips crossing formats without repeating default gaps',()=>{
  const engine=new api.TextLayoutEngine(400,16,24,4,1);
  engine.setRuns([new api.FormatRun(2,6,true),new api.FormatRun(7,11,false,true)]);
  const typeset=engine.buildTypesetWindow('AAA\nBBCC\nDDD',4,9);
  assert.equal(typeset.value,'BBCC\n');
  assert.deepEqual(typeset.spans.map(span=>[span.text,span.style.fontWeight===700,span.style.fontStyle===1]),
    [['BB',true,false],['C',false,false],['C\n',false,true]]);
  engine.setRuns([new api.FormatRun(2,11,true,true)]);
  const across=engine.buildTypesetWindow('AAA\nBBCC\nDDD',4,9);
  assert.equal(across.value,'BBCC\n');
  assert.equal(across.spans.length,1);
  assert.equal(across.spans[0].style.fontWeight,700);
  assert.equal(across.spans[0].style.fontStyle,1);
});
check('astral offsets and saved line mappings survive typeset window changes',()=>{
  const engine=new api.TextLayoutEngine(400,16,24,4,1);
  const value='😀\nA😀B\nZZ';
  const firstTypeset=engine.buildTypesetWindow(value,0,3);
  const first=engine.createLayoutLine(firstTypeset,0,2,0);
  const secondTypeset=engine.buildTypesetWindow(value,3,8);
  assert.equal(engine.lineBreak(secondTypeset,3),5);
  assert.equal(engine.lineBreak(secondTypeset,6),2);
  const second=engine.createLayoutLine(secondTypeset,3,4,28);
  const within=engine.createLayoutLine(secondTypeset,6,1,56);
  assert.equal(second.startIndex,3);assert.equal(second.endIndex,7);
  assert.equal(second.runs[0].textStart,3);assert.equal(second.runs[0].textEnd,7);
  assert.deepEqual(json(second.runs[0].glyphOffsets),[0,1,3]);
  assert.equal(within.nativeStartIndex,0);assert.equal(within.runs[0].textStart,6);
  assert.deepEqual(json(within.runs[0].glyphOffsets),[0]);
  const thirdTypeset=engine.buildTypesetWindow(value,8,value.length);
  const third=engine.createLayoutLine(thirdTypeset,8,2,84);
  assert.equal(third.runs[0].textStart,8);assert.equal(third.runs[0].textEnd,10);
  assert.equal(api.HitTester.offsetToX(first,2,0),10);
  assert.equal(api.HitTester.offsetToX(second,6,0),20);
  assert.equal(api.HitTester.hitTest(20,29,[second],0,0,value),6);
});
check('soft-wrapped native lines map their own glyphs and caret back into the document',()=>{
  const engine=new api.TextLayoutEngine(50,16,24,4,1);
  const value='XX😀A😀B中文';
  const typeset=engine.buildTypeset(value);
  const first=engine.createLayoutLine(typeset,0,4,0);
  const second=engine.createLayoutLine(typeset,4,4,28);
  assert.equal(second.runs[0].textStart,4);assert.equal(second.runs[0].textEnd,8);
  assert.deepEqual(json(second.runs[0].glyphOffsets),[0,1,3]);
  assert.equal(api.HitTester.offsetToX(second,4,0),0);
  assert.equal(api.HitTester.offsetToX(second,5,0),10);
  assert.equal(api.HitTester.offsetToX(second,7,0),20);
  assert.equal(api.HitTester.hitTest(0,29,[first,second],0,0,value),4);
  assert.equal(api.HitTester.hitTest(20,29,[first,second],0,0,value),7);
});
function cacheEngine() {let builds=0;return {get builds(){return builds;},setRuns(){},lineStepVp(){return 28;},contentMaxWidthPx(){return 50;},lineBreak(typeset,start){return typeset.getLineBreak(start-typeset.base);},createLayoutLine(typeset,start,count,y){return this.buildLayoutLineFrom(typeset.createLine(start-typeset.base,count),start,count,y);},emptyLine(offset,y){return line(offset,'',y);},buildTypesetWindow(content,base,end){builds++;const value=content.substring(base,end);return {base,getLineBreak(start){return Math.min(5,value.length-start);},createLine(start,n){return {value:value.substring(start,start+n)};}};},buildLayoutLineFrom(native,start,count,y){return line(start,native.value,y);}};}
check('empty document and trailing newline create real caret lines',()=>{for(const value of ['','A\n','\n\n']){const c=new api.LayoutCache(cacheEngine());const lines=c.ensureLayout(value,1,1,999);assert.ok(c.isComplete());assert.equal(lines.length,value==='\n\n'?3:value===''?1:2);assert.equal(lines.at(-1).startIndex,value.length);}});
check('lazy layout can reach an offscreen caret',()=>{const c=new api.LayoutCache(cacheEngine());c.ensureLayout('x'.repeat(200),1,1,28);const lines=c.ensureOffset('x'.repeat(200),1,1,200);assert.equal(lines.at(-1).endIndex,200);});
check('editing retains preceding paragraphs',()=>{const engine=cacheEngine();const c=new api.LayoutCache(engine);const lines=c.ensureLayout('aaa\nbbb',1,1,999);const first=lines[0];c.applyEdit('aaa\nbXbb',2,2,[],5);const updated=c.ensureLayout('aaa\nbXbb',2,2,999);assert.equal(updated[0],first);assert.equal(updated.at(-1).endIndex,8);});
function animationOptions(oldText,newText,hintOffset=0) {const options=new api.GlyphDiffOptions();Object.assign(options,{oldText,newText,hintOffset});return options;}
check('insert animation belongs to inserted glyph',()=>{const a=api.GlyphAnimator.createEditAnimations([line(0,'AB')],[line(0,'XAB')],animationOptions('AB','XAB'));assert.deepEqual(Array.from(a.map.keys()),[0]);assert.equal(a.map.get(0).glyph,88);});
check('removed glyph has independent exit animation',()=>{const a=api.GlyphAnimator.createEditAnimations([line(0,'AB')],[line(0,'B')],animationOptions('AB','B'));assert.equal(a.exits.length,1);assert.equal(a.exits[0].glyph,65);assert.equal(a.map.size,0);});
check('scrolled caret and handles stay visible',()=>{const theme=new api.RenderTheme();const renderer=new api.GlyphRenderer(theme);const canvas={attachBrush(){},detachBrush(){},drawRect(r){draws.push(r);},drawCircle(...v){draws.push(v);}};const caret=new api.CursorState();Object.assign(caret,{x:12,y:1000,height:16});renderer.drawCaret(canvas,caret,new api.ViewportInfo(1000,200));renderer.drawHandles(canvas,[caret],new api.ViewportInfo(1000,200));assert.equal(draws.length,3);});
check('native mixed-direction runs preserve positioned glyph bearings',()=>{
  const engine=new api.TextLayoutEngine(400,16,24,4,2);
  engine.indexMap=new api.TextIndexMap('ABCD');
  const positions=[{x:72,y:2},{x:48,y:-1}];
  const run={getStringRange(){return {start:2,end:2};},getStringIndices(){return [3,2];},
    getGlyphs(){return [68,67];},getFont(){return new Font();},
    getAdvances(){return [{x:20,y:0},{x:20,y:0}];},getPositions(){return positions;}};
  const native={getTextRange(){return {start:0,end:4};},getGlyphRuns(){return [run];},
    getTypographicBounds(){return {ascent:28,descent:8,leading:0,width:80};},
    getOffsetForStringIndex(n){return [0,20,80,60,40][n];}};
  const l=engine.buildLayoutLineFrom(native,0,4,0);
  assert.equal(l.runs[0].runOffsetX,0);
  assert.deepEqual(json(l.runs[0].positions),[{x:36,y:1},{x:24,y:-0.5}]);
  assert.deepEqual(json(l.runs[0].glyphOffsets),[1,0]);
});
check('undo/redo reload preserves scroll; document switch resets it',()=>{
  const e=editor('old');e.scrollY=120;
  e.loadDocument('abc',[],0,true);assert.equal(e.scrollY,120);
  e.loadDocument('xyz',[],0,false);assert.equal(e.scrollY,0);
});
check('selection stores anchor/head; handle crossing never swaps identity',()=>{
  const m=new api.SelectionManager();m.setSource('ABCDE');m.setSelection(1,4);
  assert.equal(m.anchor,1);assert.equal(m.head,4);assert.equal(m.startOffset,1);assert.equal(m.endOffset,4);
  m.beginHandleDrag(1);m.updateHandleDrag(0);
  assert.equal(m.anchor,0);assert.equal(m.head,4);assert.equal(m.startOffset,0);
  m.updateHandleDrag(5);
  assert.equal(m.anchor,5);assert.equal(m.head,4);assert.equal(m.startOffset,4);assert.equal(m.endOffset,5);
  assert.equal(m.headAffinity,api.CaretAffinity.DOWNSTREAM);
  m.endHandleDrag();
  m.setSelection(4,1);assert.equal(m.startOffset,1);assert.equal(m.endOffset,4);assert.equal(m.headAffinity,api.CaretAffinity.DOWNSTREAM);
});
check('caret affinity picks the same visual side as the selection highlight',()=>{
  const lines=[line(0,'ABC'),line(3,'DEF',28)];
  const down=api.HitTester.caretPositionFor(3,lines,0,0,16,api.CaretAffinity.UPSTREAM);
  const up=api.HitTester.caretPositionFor(3,lines,0,0,16,api.CaretAffinity.DOWNSTREAM);
  assert.equal(down.y,lines[0].baseline-lines[0].ascent);
  assert.equal(up.y,lines[1].baseline-lines[1].ascent);
  assert.equal(down.x,30);assert.equal(up.x,0);
  const box=api.HitTester.lineBox(lines[0]);
  assert.equal(box.top,lines[0].baseline-lines[0].ascent);assert.equal(box.height,18);
});
check('dragging a selection keeps the drawn caret at head',()=>{
  const e=editor('ABCDE');e.lines=[line(0,'ABCDE')];
  e.selMgr.beginDrag(1);e.selMgr.updateDrag(4);e.syncSelectionToCaret();
  assert.equal(e.doc.caretOffset,4);assert.equal(e.caret.x,40);
  e.selMgr.updateDrag(2);e.syncSelectionToCaret();
  assert.equal(e.doc.caretOffset,2);assert.equal(e.caret.x,20);
});
check('Ctrl+A updates caret, callbacks and IME once',()=>{
  const e=editor('ABCDE');let reported=0;e.reportSelection=(force)=>{reported++;};
  let changed=null;e.onSelectionChange=(s,en)=>{changed=[s,en];};
  const cmd=new api.KeyboardEvent();cmd.action=api.KeyAction.SELECT_ALL;e.applyKeyCommand(cmd);
  assert.equal(e.doc.caretOffset,5);assert.deepEqual(json(changed),[0,5]);assert.ok(reported>0);
  assert.equal(e.selMgr.anchor,0);assert.equal(e.selMgr.head,5);
});
check('long-document Ctrl+A selects immediately without laying out its offscreen tail',()=>{
  const value='甲乙丙\n'.repeat(5000)+'尾';const e=editor(value);
  const cache=new api.LayoutCache(cacheEngine());
  e.lines=cache.ensureLayout(value,e.doc.version,e.doc.formatVersion,56);e.cache=cache;
  const countBefore=cache.lineCount();e.ensureCaretLayout=()=>{throw new Error('full selection must not force the tail');};
  let selected;e.onSelectionChange=(start,end)=>selected=[start,end];e.selectAllText();
  assert.deepEqual(selected,[0,value.length]);assert.equal(e.doc.caretOffset,value.length);
  assert.equal(cache.lineCount(),countBefore);assert.equal(cache.isComplete(),false);
  assert.equal(e.caret.visible,false);assert.deepEqual(Array.from(e.handlePositions()),[]);
});
function withLayoutTimers(action) {
  const oldSet=context.setTimeout,oldClear=context.clearTimeout;let next=0;const pending=new Map(),all=[];
  context.setTimeout=(fn)=>{const id=++next;pending.set(id,fn);all.push(fn);return id;};
  context.clearTimeout=id=>pending.delete(id);
  const timers={pending,all,drain(){let turns=0;while(pending.size){assert.ok(turns++<1000);const [id,fn]=pending.entries().next().value;pending.delete(id);fn();}}};
  try {action(timers);} finally {context.setTimeout=oldSet;context.clearTimeout=oldClear;}
}
function longNavigationEditor() {
  const value='甲乙丙\n'.repeat(5000)+'尾';const e=editor(value);
  e.cache=new api.LayoutCache(cacheEngine());e.lines=e.cache.ensureLayout(value,e.doc.version,e.doc.formatVersion,56);
  e.doc.moveCaret(0);e.selMgr.collapse(0);e.focused=true;return e;
}
check('far caret navigation yields in bounded slices while logical offsets update immediately',()=>withLayoutTimers(timers=>{
  const e=longNavigationEditor();const before=e.cache.lineCount();e.moveCaretAnimated(e.doc.length);
  assert.equal(e.doc.caretOffset,e.doc.length);assert.equal(e.selMgr.head,e.doc.length);
  assert.ok(e.cache.lineCount()-before<=32);assert.equal(e.caretLayoutPending,true);assert.equal(e.caret.visible,false);
  timers.drain();assert.equal(e.cache.isComplete(),true);assert.equal(e.caretLayoutPending,false);
  assert.equal(e.caret.visible,true);assert.ok(e.caret.y>0);
}));
check('a newer caret request invalidates already queued layout callbacks',()=>withLayoutTimers(timers=>{
  const e=longNavigationEditor();e.moveCaretAnimated(e.doc.length);const stale=timers.all[0];
  e.moveCaretAnimated(0);const lines=e.cache.lineCount();stale();
  assert.equal(e.doc.caretOffset,0);assert.equal(e.cache.lineCount(),lines);assert.equal(timers.pending.size,0);
}));
check('document reload and typing cancel pending navigation without moving or editing the replacement',()=>withLayoutTimers(timers=>{
  for(const replace of [false,true]) {
    const e=longNavigationEditor();e.moveCaretAnimated(e.doc.length);const stale=timers.all.at(-1);
    if(replace){e.loadDocument('B',[],1);}else{e.insertExternalText('X');}
    const text=e.doc.text,caret=e.doc.caretOffset,lines=e.cache.lineCount();stale();
    assert.equal(e.doc.text,text);assert.equal(e.doc.caretOffset,caret);assert.equal(e.cache.lineCount(),lines);
    assert.equal(e.caretLayoutPending,false);assert.equal(timers.pending.size,0);
  }
}));
check('Shift far navigation keeps its selection direction while the visual reveal is pending',()=>withLayoutTimers(timers=>{
  const e=longNavigationEditor();e.selectTo(e.doc.length);
  assert.equal(e.selMgr.anchor,0);assert.equal(e.selMgr.head,e.doc.length);assert.equal(e.caretLayoutPending,true);
  timers.drain();assert.equal(e.selMgr.anchor,0);assert.equal(e.selMgr.head,e.doc.length);
}));
check('cancelling at an unfinished soft-wrap boundary keeps stale caret and handles hidden',()=>withLayoutTimers(timers=>{
  const e=editor('A'.repeat(2000));e.doc.moveCaret(0);e.selMgr.collapse(0);e.focused=true;
  e.cache=new api.LayoutCache(cacheEngine());e.moveCaretAnimated(160);
  assert.equal(e.lines.at(-1).endIndex,160);assert.equal(e.caretLayoutPending,true);
  e.cancelCaretLayout();assert.equal(e.caret.visible,false);
  assert.equal(e.hasCaretLayout(160,api.CaretAffinity.DOWNSTREAM),false);
  assert.equal(e.hasCaretLayout(160,api.CaretAffinity.UPSTREAM),true);
  e.selMgr.setSelection(170,160);assert.deepEqual(Array.from(e.handlePositions()),[]);
  e.ime.isAttached=true;let reports=0;e.ime.updateCursor=()=>reports++;
  api.EditorProbe.prototype.reportCursor.call(e);assert.equal(reports,0);
  e.renderer={draw(){}};api.EditorProbe.prototype.drawNow.call(e);assert.equal(e.caret.visible,false);
  e.lines=e.cache.ensureOffset(e.doc.text,e.doc.version,e.doc.formatVersion,160);
  api.EditorProbe.prototype.drawNow.call(e);assert.equal(e.caret.visible,true);
  assert.equal(e.caretLayoutHidden,false);assert.ok(e.caret.y>0);assert.equal(timers.pending.size,0);
}));
check('drawing a covered caret respects keyboard-hide visibility',()=>{
  const e=editor('ABC');e.lines=[line(0,'ABC')];e.focused=true;e.caret.visible=false;
  e.renderer={draw(){}};api.EditorProbe.prototype.drawNow.call(e);
  assert.equal(e.caret.visible,false);assert.equal(e.caretLayoutHidden,false);
});
check('keyboard hiding during a pending far jump remains hidden after layout completes',()=>withLayoutTimers(timers=>{
  context.inputMethod.KeyboardStatus={SHOW:1,HIDE:2};
  const e=longNavigationEditor();e.registerImeCallbacks();e.moveCaretAnimated(e.doc.length);
  e.ime.onSendKeyboardStatus(context.inputMethod.KeyboardStatus.HIDE);
  timers.drain();assert.equal(e.caretLayoutPending,false);assert.equal(e.caret.visible,false);
  e.moveCaretAnimated(0);assert.equal(e.caretLayoutHidden,false);assert.equal(e.caretLayoutRestoreVisible,true);
}));
check('visual navigation immediately after a far jump uses the destination line',()=>withLayoutTimers(timers=>{
  for(const action of [api.KeyAction.MOVE_UP,api.KeyAction.MOVE_DOWN,api.KeyAction.MOVE_LINE_START,api.KeyAction.MOVE_LINE_END]) {
    for(const shift of [false,true]) {
      const actual=longNavigationEditor(),reference=longNavigationEditor();
      for(const e of [actual,reference]) e.ensureCaretLayout=()=>{
        e.lines=e.cache.ensureOffset(e.doc.text,e.doc.version,e.doc.formatVersion,e.doc.caretOffset);
      };
      reference.doc.moveCaret(reference.doc.length);reference.selMgr.collapse(reference.doc.length);
      reference.ensureCaretLayout();
      actual.moveCaretAnimated(actual.doc.length);assert.equal(actual.caretLayoutPending,true);
      const command=new api.KeyboardEvent();command.action=action;command.shift=shift;
      actual.applyKeyCommand(command);reference.applyKeyCommand(command);
      assert.equal(actual.doc.caretOffset,reference.doc.caretOffset,action+' shift='+shift);
      assert.equal(actual.selMgr.anchor,reference.selMgr.anchor);assert.equal(actual.selMgr.head,reference.selMgr.head);
      assert.equal(actual.caretLayoutPending,false);assert.equal(timers.pending.size,0);
    }
  }
}));
check('deleting a collapsed composition to empty preserves its original caret',()=>{
  const e=editor('ABCDE');e.doc.moveCaret(1);e.selMgr.collapse(1);
  e.previewMgr.update('ni',-1,-1,1,1);e.refreshPreview();assert.equal(e.displayCaret(),3);
  e.previewMgr.update('',-1,-1);e.refreshPreview();
  assert.equal(e.displayText(),'ABCDE');assert.equal(e.displayCaret(),1);assert.equal(e.doc.caretOffset,1);
});
check('composition updates reuse an isolated preview cache and retain committed prefix lines',()=>{
  const value='甲乙丙\n'.repeat(300)+'尾';const e=editor(value);
  e.engineRef=new api.TextLayoutEngine(50,16,24,4,1);e.cache=new api.LayoutCache(e.engineRef);
  e.lines=e.cache.ensureOffset(value,e.doc.version,e.doc.formatVersion,value.length);
  const prefix=e.lines[0],committedCount=e.cache.lineCount();
  e.previewMgr.update('ni',-1,-1,value.length,value.length);e.refreshPreview();
  const preview=e.previewCache;assert.notEqual(preview,e.cache);
  let lines=preview.ensureOffset(e.previewDoc.text,e.previewDoc.version,e.previewDoc.formatVersion,e.previewDoc.caretOffset);
  assert.equal(lines[0],prefix);
  for(const text of ['nin','你好','ni\nhao','n']) {
    e.previewMgr.update(text,-1,-1);e.refreshPreview();assert.equal(e.previewCache,preview);
    lines=preview.ensureOffset(e.previewDoc.text,e.previewDoc.version,e.previewDoc.formatVersion,e.previewDoc.caretOffset);
    assert.equal(lines[0],prefix);assert.equal(e.doc.text,value);assert.equal(e.cache.lineCount(),committedCount);
  }
  e.insertExternalText('你好');assert.equal(e.doc.text,value+'你好');assert.equal(e.previewCache,null);
  assert.equal(e.previewDoc,null);assert.equal(e.previewMgr.isComposing,false);
});
check('clampScroll never resets to top while the layout cache is still empty',()=>{
  const e=editor('x'.repeat(1000));e.viewHeightVp=50;e.scrollY=100;
  e.cache={height:0,setRuns(){},ensureLayout(text,version,fmt,untilY){this.height=Math.max(this.height,untilY);return [];},ensureOffset(){return [];}};
  e.lines=[];
  e.clampScroll();
  assert.equal(e.scrollY,100);
});
check('preview text is drawn once, in the same run origin and baseline',()=>{
  const theme=new api.RenderTheme();const renderer=new api.GlyphRenderer(theme);
  const l=line(0,'ABC');const preview=new api.PreviewInfo();preview.text='B';preview.startOffset=1;preview.endOffset=3;
  const blobs=[];const ctx={canvas:{clear(){},attachBrush(){},detachBrush(){},drawTextBlob(b,x,y){blobs.push({n:b.buffer.length,x,y});},
    drawRect(){},drawCircle(){},save(){},restore(){},translate(){},scale(){}},invalidate(){}};
  renderer.draw(ctx,[l],null,null,preview,new api.ViewportInfo(0,100),null,[]);
  const glyphTotal=blobs.reduce((sum,b)=>sum+b.n,0);
  assert.equal(glyphTotal,3);
  assert.deepEqual(blobs.map(b=>b.n).sort(),[1,2]);
});
// ===================== T1 交互归一：快捷键表 / 输入仲裁 / IME 回声 =====================
const KIND = api.EditCommandKind;
const K = name => api.KeyCode[name];
const modsOf = (ctrl = false, shift = false, alt = false, meta = false) => {
  const m = new api.EditorModifiers();
  m.ctrl = ctrl; m.shift = shift; m.alt = alt; m.meta = meta;
  return m;
};
const shortcut = (code, keyText = '', mods = modsOf(), down = true, composing = false) =>
  api.resolveShortcut(code, keyText, down, mods, composing);
const keyEvent = (keyCode, keyText = '') => ({ keyCode, keyText, type: 0, getModifierKeyState: () => false });

check('Ctrl chord table covers select/copy/cut/paste/undo/redo/save/find/bold/italic', () => {
  const table = [[K('KEYCODE_A'), KIND.SELECT_ALL], [K('KEYCODE_C'), KIND.COPY], [K('KEYCODE_X'), KIND.CUT],
    [K('KEYCODE_V'), KIND.PASTE], [K('KEYCODE_Z'), KIND.UNDO], [K('KEYCODE_Y'), KIND.REDO],
    [K('KEYCODE_S'), KIND.SAVE], [K('KEYCODE_F'), KIND.FIND], [K('KEYCODE_B'), KIND.TOGGLE_BOLD],
    [K('KEYCODE_I'), KIND.TOGGLE_ITALIC]];
  for (const [code, kind] of table) {
    const cmd = shortcut(code, '', modsOf(true));
    assert.equal(cmd.kind, kind, 'ctrl + keycode ' + code);
    assert.equal(cmd.mods.ctrl, true);
    assert.equal(cmd.source, api.EditorInputSource.KEYBOARD);
  }
});
check('Ctrl+Shift+Z redoes, Ctrl+Z undoes and a Meta chord counts as primary', () => {
  assert.equal(shortcut(K('KEYCODE_Z'), '', modsOf(true, true)).kind, KIND.REDO);
  assert.equal(shortcut(K('KEYCODE_Z'), '', modsOf(true, false)).kind, KIND.UNDO);
  assert.equal(shortcut(K('KEYCODE_Y'), '', modsOf(true, false)).kind, KIND.REDO);
  assert.equal(shortcut(K('KEYCODE_A'), '', modsOf(false, false, false, true)).kind, KIND.SELECT_ALL);
});
check('Home/End stay on the line while Ctrl+Home/End reach the document bounds', () => {
  assert.equal(shortcut(K('KEYCODE_MOVE_HOME')).kind, KIND.MOVE_LINE_START);
  assert.equal(shortcut(K('KEYCODE_MOVE_END')).kind, KIND.MOVE_LINE_END);
  assert.equal(shortcut(K('KEYCODE_MOVE_HOME'), '', modsOf(true)).kind, KIND.MOVE_DOC_START);
  assert.equal(shortcut(K('KEYCODE_MOVE_END'), '', modsOf(true)).kind, KIND.MOVE_DOC_END);
});
check('plain arrows move by caret while Ctrl+arrows move by word', () => {
  assert.equal(shortcut(K('KEYCODE_DPAD_LEFT')).kind, KIND.MOVE_LEFT);
  assert.equal(shortcut(K('KEYCODE_DPAD_RIGHT')).kind, KIND.MOVE_RIGHT);
  assert.equal(shortcut(K('KEYCODE_DPAD_UP')).kind, KIND.MOVE_UP);
  assert.equal(shortcut(K('KEYCODE_DPAD_DOWN')).kind, KIND.MOVE_DOWN);
  assert.equal(shortcut(K('KEYCODE_DPAD_LEFT'), '', modsOf(true)).kind, KIND.MOVE_WORD_LEFT);
  assert.equal(shortcut(K('KEYCODE_DPAD_RIGHT'), '', modsOf(true)).kind, KIND.MOVE_WORD_RIGHT);
});
check('Backspace, Delete and Ctrl+Backspace keep their own deletion semantics', () => {
  assert.equal(shortcut(K('KEYCODE_DEL')).kind, KIND.DELETE_BACKWARD);
  assert.equal(shortcut(K('KEYCODE_FORWARD_DEL')).kind, KIND.DELETE_FORWARD);
  assert.equal(shortcut(K('KEYCODE_DEL'), '', modsOf(true)).kind, KIND.DELETE_WORD_BACKWARD);
});
check('PageUp/PageDown, Enter and Esc map to paging, newline and dismiss', () => {
  assert.equal(shortcut(K('KEYCODE_PAGE_UP')).kind, KIND.PAGE_UP);
  assert.equal(shortcut(K('KEYCODE_PAGE_DOWN')).kind, KIND.PAGE_DOWN);
  const enter = shortcut(K('KEYCODE_ENTER'));
  assert.equal(enter.kind, KIND.INSERT_TEXT);
  assert.equal(enter.text, '\n');
  assert.equal(shortcut(K('KEYCODE_NUMPAD_ENTER')).kind, KIND.INSERT_TEXT);
  assert.equal(shortcut(K('KEYCODE_ESCAPE')).kind, KIND.DISMISS);
});
check('Tab never produces a command in any modifier combination', () => {
  for (const mods of [modsOf(), modsOf(true), modsOf(false, true), modsOf(true, true), modsOf(false, false, true)]) {
    const cmd = shortcut(K('KEYCODE_TAB'), '', mods);
    assert.equal(cmd.kind, KIND.NONE);
    assert.equal(cmd.text, '');
  }
});
check('printable keys become INSERT_TEXT with Shift casing, composing releases every key', () => {
  const plain = shortcut(K('KEYCODE_X'), 'x');
  assert.equal(plain.kind, KIND.INSERT_TEXT);
  assert.equal(plain.text, 'x');
  assert.equal(shortcut(K('KEYCODE_X'), 'x', modsOf(false, true)).text, 'X', 'Shift must uppercase a-z');
  assert.equal(shortcut(K('KEYCODE_SPACE'), ' ').text, ' ');
  assert.equal(shortcut(K('KEYCODE_1'), '1').text, '1');
  for (const mods of [modsOf(), modsOf(true), modsOf(false, true)]) {
    assert.equal(shortcut(K('KEYCODE_X'), 'x', mods, true, true).kind, KIND.NONE, 'composing must pass keys to the IME');
  }
});
check('unrecognised Ctrl/Alt chords and key-up events are handed back to the system', () => {
  assert.equal(shortcut(K('KEYCODE_Q'), 'q', modsOf(true)).kind, KIND.NONE, 'an unknown Ctrl chord must not be swallowed');
  assert.equal(shortcut(K('KEYCODE_A'), 'a', modsOf(false, false, true)).kind, KIND.NONE, 'Alt is left to the system');
  // AltGr may be reported as Ctrl+Alt: never trigger destructive shortcuts.
  for (const key of ['A','C','X','V','S','F','B','I']) {
    assert.equal(shortcut(K('KEYCODE_'+key), key.toLowerCase(), modsOf(true,false,true)).kind, KIND.NONE, 'AltGr '+key);
  }
  assert.equal(shortcut(K('KEYCODE_X'), 'x', modsOf(), false).kind, KIND.NONE, 'key-up must not repeat an edit');
});
check('pre-Ime consumption intercepts caret, chord and Esc commands in both IME states', () => {
  const caret = [KIND.MOVE_LEFT, KIND.MOVE_RIGHT, KIND.MOVE_UP, KIND.MOVE_DOWN, KIND.MOVE_WORD_LEFT,
    KIND.MOVE_WORD_RIGHT, KIND.MOVE_LINE_START, KIND.MOVE_LINE_END, KIND.MOVE_DOC_START, KIND.MOVE_DOC_END,
    KIND.PAGE_UP, KIND.PAGE_DOWN];
  for (const kind of caret) {
    for (const ime of [true, false]) {
      assert.equal(api.shouldConsumePreIme(new api.EditCommand(kind, ''), ime), true, 'kind ' + kind + ' ime ' + ime);
    }
  }
  const chord = new api.EditCommand(KIND.SELECT_ALL, '');
  chord.mods.ctrl = true;
  assert.equal(api.shouldConsumePreIme(chord, true), true);
  assert.equal(api.shouldConsumePreIme(new api.EditCommand(KIND.DISMISS, ''), true), true);
});
check('character and editing keys are consumed in pre-Ime only when the IME is unusable', () => {
  const character = new api.EditCommand(KIND.INSERT_TEXT, 'x');
  assert.equal(api.shouldConsumePreIme(character, true), false, 'a usable IME must receive letters for composition');
  assert.equal(api.shouldConsumePreIme(character, false), true, 'an unusable IME leaves the keyboard fallback to us');
  for (const kind of [KIND.DELETE_BACKWARD, KIND.DELETE_FORWARD, KIND.DELETE_WORD_BACKWARD, KIND.PASTE,
    KIND.UNDO, KIND.REDO, KIND.TOGGLE_ITALIC]) {
    assert.equal(api.shouldConsumePreIme(new api.EditCommand(kind, ''), true), false, 'kind ' + kind);
    assert.equal(api.shouldConsumePreIme(new api.EditCommand(kind, ''), false), true, 'kind ' + kind);
  }
});
check('digit keys insert 0-9 even when keyText is empty and never steal IME candidate selection', () => {
  // 回归：曾经"字母能打、数字打不出来"——数字行 keyText 为空时没有兜底。
  // 但数字键在组字态是"选择候选词"，因此 ①preIme 必须放行给输入法，
  // 键盘兜底放在 ③onKeyEvent（输入法没用掉该键时才到达）。
  for (let i = 0; i <= 9; i++) {
    const cmd = shortcut(K('KEYCODE_' + i), '');
    assert.equal(cmd.kind, KIND.INSERT_TEXT, 'digit ' + i + ' must insert');
    assert.equal(cmd.text, String(i), 'digit ' + i + ' text');
    assert.equal(api.shouldConsumePreIme(cmd, true), false,
      'digit ' + i + ' must reach the IME so it can select a candidate while composing');
    assert.equal(api.shouldConsumePreIme(cmd, false), true,
      'digit ' + i + ' falls back to the keyboard when the IME is unusable');
    assert.equal(shortcut(K('KEYCODE_' + i), '', modsOf(), true, true).kind, KIND.NONE,
      'composing passes digit ' + i + ' to the IME');
  }
  for (let i = 0; i <= 9; i++) {
    assert.equal(shortcut(K('KEYCODE_NUMPAD_' + i), '').text, String(i), 'numpad ' + i);
  }
  // 有 keyText 时仍以 keyText 为准；Shift+数字得到符号
  assert.equal(shortcut(K('KEYCODE_1'), '1').text, '1');
  assert.equal(shortcut(K('KEYCODE_1'), '1', modsOf(false, true)).text, '!');
  assert.equal(shortcut(K('KEYCODE_0'), '0', modsOf(false, true)).text, ')');
  // 其它字符不受影响：Ctrl+数字仍是系统组合，字母仍按原规则（IME 可用时放行）
  assert.equal(shortcut(K('KEYCODE_5'), '', modsOf(true)).kind, KIND.NONE, 'Ctrl+digit stays a system chord');
  const letter = shortcut(K('KEYCODE_X'), 'x');
  assert.equal(letter.text, 'x');
  assert.equal(api.shouldConsumePreIme(letter, true), false, 'letters still go to the IME for composition');
});
check('typewriter is a two-state toggle wired from the toolbar down to the V1 editor', () => {
  const canvasSource = read('editor/flowtext/CanvasTextEditor.ets');
  const hostSource = read('editor/TextEditorHost.ets');
  const paneSource = read('shell/EditorPane.ets');
  const toolsSource = read('shell/EditorTools.ets');
  assert.match(canvasSource, /@Prop @Watch\('onTypewriterPropChanged'\) typewriter/, 'prop watch so toggling takes effect immediately');
  assert.match(canvasSource, /private typewriterOverride: number = -1;/, 'controller override wins over a stale prop');
  assert.match(canvasSource, /applyTypewriter\(on: boolean\): void/, 'editor applies the toggle and re-centers');
  assert.match(canvasSource, /setTypewriter\(on: boolean\): void/, 'controller exposes setTypewriter');
  assert.match(hostSource, /typewriter: this\.typewriter/, 'host forwards the prop');
  assert.match(toolsSource, /editorController\.setTypewriter\(/, 'toolbar pushes the state to the controller');
  assert.match(toolsSource, /ui\.setTypewriter\(/, 'store stays the single source of truth');
  assert.match(paneSource, /typewriter: this\.app\.ui\.typewriter/, 'pane forwards the state');
});
check('NONE commands are never consumed in pre-Ime', () => {
  assert.equal(api.shouldConsumePreIme(new api.EditCommand(KIND.NONE, ''), false), false);
  assert.equal(api.shouldConsumePreIme(new api.EditCommand(KIND.NONE, ''), true), false);
});
check('an IME echo is dropped only for the same text inside the 40ms window', () => {
  const guard = new api.ImeEchoGuard();
  guard.recordKeyboardFallback('x', 1000);
  assert.equal(guard.claim('y', 1000), false, 'different text is genuine input');
  assert.equal(guard.claim('x', 1000), true);
  assert.equal(guard.armed, false, 'a hit disarms the guard');
  guard.recordKeyboardFallback('x', 2000);
  assert.equal(guard.claim('x', 2040), true, '40ms is still inside the window');
  guard.recordKeyboardFallback('x', 3000);
  assert.equal(guard.claim('x', 3041), false, 'beyond 40ms is a real user input');
  guard.recordKeyboardFallback('x', 5000);
  assert.equal(guard.claim('x', 4999), false, 'a backwards clock is not an echo');
});
check('one keyboard fallback swallows at most one echo and reset clears the window', () => {
  const guard = new api.ImeEchoGuard();
  guard.recordKeyboardFallback('中', 100);
  assert.equal(guard.claim('中', 110), true);
  assert.equal(guard.claim('中', 120), false, 'only one echo per fallback');
  guard.recordKeyboardFallback('文', 200);
  assert.equal(guard.armed, true);
  guard.reset();
  assert.equal(guard.armed, false);
  assert.equal(guard.claim('文', 210), false);
  guard.recordKeyboardFallback('', 300);
  assert.equal(guard.armed, false, 'empty commits never arm the guard');
});
check('editing and caret classifications match the arbiter contract', () => {
  for (const kind of [KIND.INSERT_TEXT, KIND.DELETE_BACKWARD, KIND.DELETE_WORD_BACKWARD, KIND.CUT, KIND.PASTE,
    KIND.UNDO, KIND.REDO, KIND.TOGGLE_BOLD]) {
    assert.equal(api.isEditingCommand(kind), true, 'editing ' + kind);
  }
  for (const kind of [KIND.NONE, KIND.SELECT_ALL, KIND.COPY, KIND.MOVE_LEFT, KIND.PAGE_UP, KIND.DISMISS]) {
    assert.equal(api.isEditingCommand(kind), false, 'not editing ' + kind);
  }
  for (const kind of [KIND.MOVE_LEFT, KIND.MOVE_WORD_LEFT, KIND.MOVE_LINE_END, KIND.MOVE_DOC_START, KIND.PAGE_DOWN]) {
    assert.equal(api.isCaretCommand(kind), true, 'caret ' + kind);
  }
  assert.equal(api.isCaretCommand(KIND.INSERT_TEXT), false);
});
check('pre-Ime keyboard fallback inserts once, corrects focus and arms the echo guard', () => {
  const e = editor(''); e.imeUsable = false;
  assert.equal(e.handleKeyPreIme(keyEvent(K('KEYCODE_X'), 'x')), true);
  assert.equal(e.doc.text, 'x');
  assert.equal(e.focused, true, 'a delivered key proves framework focus');
  assert.equal(e.focusConfirmed, true);
  assert.equal(e.echoGuard.armed, true);
});
check('a usable IME releases character keys in pre-Ime without editing', () => {
  const e = editor('abc'); e.imeUsable = true;
  assert.equal(e.handleKeyPreIme(keyEvent(K('KEYCODE_X'), 'x')), false);
  assert.equal(e.doc.text, 'abc');
  assert.equal(e.echoGuard.armed, false);
});
check('a digit reaches the editor through the late key path when the IME does not consume it', () => {
  // 数字不再在 preIme 抢键（组字态要让输入法选词）；输入法没用掉时由 ③ onKeyEvent 上屏。
  const e = editor('a');
  e.imeUsable = true;
  e.moveCaretAnimated(1);
  assert.equal(e.handleKeyEvent(keyEvent(K('KEYCODE_5'), '')), true);
  assert.equal(e.doc.text, 'a5');
  const withText = editor('a');
  withText.imeUsable = true;
  withText.moveCaretAnimated(1);
  assert.equal(withText.handleKeyEvent(keyEvent(K('KEYCODE_7'), '7')), true);
  assert.equal(withText.doc.text, 'a7');
});
check('Tab is released from both key paths and never inserts indentation', () => {
  for (const name of ['handleKeyPreIme', 'handleKeyEvent']) {
    const e = editor('abc'); e.moveCaretAnimated(3);
    assert.equal(e[name](keyEvent(K('KEYCODE_TAB'))), false, name);
    assert.equal(e.doc.text, 'abc', name + ' must not insert spaces');
    assert.equal(e.focused, false, name + ' must not steal focus from traversal');
  }
});
check('a key delivered to a stale unfocused editor corrects focus instead of being dropped', () => {
  const e = editor(''); e.focused = false; e.imeUsable = false;
  assert.equal(e.handleKeyEvent(keyEvent(K('KEYCODE_Y'), 'y')), true);
  assert.equal(e.doc.text, 'y');
  assert.equal(e.focused, true);
});
check('Esc without an open overlay is not swallowed, but closes a visible menu', () => {
  const closed = editor('abc');
  assert.equal(closed.handleKeyPreIme(keyEvent(K('KEYCODE_ESCAPE'))), false);
  const open = editor('abc'); open.menuVisible = true;
  assert.equal(open.handleKeyEvent(keyEvent(K('KEYCODE_ESCAPE'))), true);
  assert.equal(open.doc.text, 'abc');
});
check('paragraph boundaries resolve for first, empty, middle and last paragraphs', () => {
  const e = editor('a\n\nbc\nd');
  const t = e.doc.text;
  assert.deepEqual([e.paragraphStartAt(t, 0), e.paragraphEndAt(t, 0)], [0, 1]);
  assert.deepEqual([e.paragraphStartAt(t, 1), e.paragraphEndAt(t, 1)], [0, 1]);
  // 空段落：offset 落在两个换行之间
  assert.deepEqual([e.paragraphStartAt(t, 2), e.paragraphEndAt(t, 2)], [2, 2]);
  assert.deepEqual([e.paragraphStartAt(t, 3), e.paragraphEndAt(t, 3)], [3, 5]);
  assert.deepEqual([e.paragraphStartAt(t, 5), e.paragraphEndAt(t, 5)], [3, 5]);
  assert.deepEqual([e.paragraphStartAt(t, 6), e.paragraphEndAt(t, 6)], [6, 7]);
  assert.deepEqual([e.paragraphStartAt(t, 7), e.paragraphEndAt(t, 7)], [6, 7]);
  const empty = editor('');
  assert.deepEqual([empty.paragraphStartAt('', 0), empty.paragraphEndAt('', 0)], [0, 0]);
});
check('typewriter centres the caret line and moves one line per line change', () => {
  const make = (text, caret, lines, viewH) => {
    const e = editor(text);
    e.typewriterOverride = 1;
    e.viewHeightVp = viewH;
    e.theme.paddingTop = 8;
    e.lines = lines;
    e.doc.moveCaret(caret);
    // editor() 里的替身会覆盖真实实现；这里按本用例需要装回"打字机开启 + 顶距 8vp"
    e.effectivePolicy = () => 1;
    e.padTopVp = () => 8;
    return e;
  };
  const short = [line(0, 'a', 0), line(2, '', 28), line(3, 'bc', 56), line(6, 'd', 84)];
  // 光标行居中：caretTop + 半行高 - 视口半高
  const mid = make('a\n\nbc\nd', 3, short, 200);
  assert.equal(Math.round(mid.typewriterScrollTarget(8 + 56 + 18, 20)), -8);
  // 首行允许负滚动（顶部留白）
  const first = make('a\n\nbc\nd', 0, short, 200);
  assert.equal(Math.round(first.typewriterScrollTarget(8 + 18, 20)), -64);
  // 末行：110+10-100 = 20
  const last = make('a\n\nbc\nd', 6, short, 200);
  assert.equal(Math.round(last.typewriterScrollTarget(8 + 84 + 18, 20)), 20);
  // 同一段落内换行：目标逐行移动（差一行 = 28vp），而不是整段不动
  assert.equal(Math.round(mid.typewriterScrollTarget(8 + 84 + 18, 20) -
    mid.typewriterScrollTarget(8 + 56 + 18, 20)), 28);
  // 超长段落（7 行 168vp > 160vp）：退化为光标行居中，光标不会被甩出视口
  const many = [];
  for (let i = 0; i < 7; i++) { many.push(line(i * 3, 'xxx', i * 28)); }
  // 单段 20 字跨 7 行：块高 192 > 160 → 退化为光标行居中（第 4 行 92..116）
  const long = make('x'.repeat(20), 10, many, 200);
  assert.equal(Math.round(long.typewriterScrollTarget(8 + 84 + 18, 20)), 20);
});
check('typewriter keeps negative scroll for the first paragraph and restores zero when off', () => {
  const e = editor('a\n\nb');
  e.viewHeightVp = 200;
  e.theme.paddingTop = 8;
  e.lines = [line(0, 'a', 0), line(2, 'b', 28)];
  e.cache = { height: 400, setRuns() {}, ensureLayout() { return []; }, ensureOffset() { return []; }, lineCount() { return 2; } };
  e.typewriterOverride = 1;
  e.leadPadVp = () => (e.typewriterOverride === 1 ? 100 : 0);
  e.scrollY = -50;
  e.clampScroll();
  assert.equal(e.scrollY, -50, 'negative scroll is the top breathing room');
  e.typewriterOverride = 0;
  e.clampScroll();
  assert.equal(e.scrollY, 0, 'turning typewriter off removes the negative range');
});
check('renderer dims every line outside the current paragraph and keeps it normal', () => {
  const theme = new api.RenderTheme();
  theme.textColor = { alpha: 255, red: 17, green: 17, blue: 17 };
  theme.dimTextColor = { alpha: 255, red: 150, green: 150, blue: 150 };
  theme.backgroundColor = { alpha: 255, red: 255, green: 255, blue: 255 };
  const renderer = new api.GlyphRenderer(theme);
  const colors = [];
  const ctx = { canvas: {
    clear() {}, attachBrush(b) { colors.push(b.color); }, detachBrush() {}, drawTextBlob() {},
    drawRect() {}, drawCircle() {}, save() {}, restore() {}, translate() {}, scale() {}
  }, invalidate() {} };
  const lines = [line(0, 'AB', 0), line(3, 'CD', 28)];
  renderer.draw(ctx, lines, null, null, null, new api.ViewportInfo(0, 200), null, [], true, 1, 1);
  assert.deepEqual(colors[0], theme.dimTextColor, 'the paragraph before the caret is dimmed');
  assert.deepEqual(colors[1], theme.textColor, 'the current paragraph keeps the normal colour');
  colors.length = 0;
  renderer.draw(ctx, lines, null, null, null, new api.ViewportInfo(0, 200), null, [], false, -1, -1);
  assert.deepEqual(colors[0], theme.textColor);
  assert.deepEqual(colors[1], theme.textColor);
});
check('F11 toggles immersive editing through the command chain', () => {
  const cmd = shortcut(K('KEYCODE_F11'), '');
  assert.equal(cmd.kind, KIND.TOGGLE_IMMERSIVE);
  assert.equal(api.shouldConsumePreIme(cmd, true), true, 'F11 must be consumed before the IME');
  const calls = [];
  const router = new api.EditorCommandRouter();
  const host = { toggleImmersive() { calls.push('immersive'); } };
  assert.equal(router.dispatch(cmd, host), true);
  assert.deepEqual(calls, ['immersive']);
});
check('pointer clicks place the caret immediately while finger taps keep the spring animation', () => {
  const pointer = editor('abcd');
  pointer.lines = [line(0, 'abcd', 0)];
  pointer.ensureCaretLayout = () => {};
  pointer.emitSelection = () => {};
  pointer.followTypewriter = () => {};
  pointer.reportCursor = () => {};
  pointer.drawNow = () => {};
  pointer.placeCaretImmediately(2);
  assert.equal(pointer.doc.caretOffset, 2);
  assert.equal(pointer.caretAnimating, false, 'pointer placement must not start the caret spring');
  assert.equal(pointer.caret.alpha, 1, 'placement keeps the caret solid; breathing resumes afterwards');
  // 指针判定：最近 800ms 内收到过 onMouse = 指针点击；纯触摸设备永不触发 onMouse
  pointer.lastPointerAtMs = Date.now();
  assert.equal(pointer.isPointerInput({}), true, 'mouse/touchpad click');
  pointer.lastPointerAtMs = Date.now() - 2000;
  assert.equal(pointer.isPointerInput({}), false, 'finger tap after the pointer window');
});
check('caret breathing uses alpha instead of a hard visible/hidden blink', () => {
  const theme = new api.RenderTheme();
  theme.caretColor = { alpha: 255, red: 0, green: 0, blue: 255 };
  const renderer = new api.GlyphRenderer(theme);
  const colors = [];
  const ctx = { canvas: {
    clear() {}, attachBrush(b) { colors.push(b.color); }, detachBrush() {}, drawTextBlob() {},
    drawRect() {}, drawCircle() {}, save() {}, restore() {}, translate() {}, scale() {}
  }, invalidate() {} };
  const caret = new api.CursorState();
  caret.x = 10; caret.y = 5; caret.height = 20; caret.visible = true; caret.alpha = 0.5;
  renderer.draw(ctx, [line(0, 'A', 0)], caret, null, null, new api.ViewportInfo(0, 200), null, []);
  assert.equal(colors[colors.length - 1].alpha, 128, 'half-phase caret is drawn at half opacity');
  colors.length = 0;
  caret.alpha = 0.01;
  renderer.draw(ctx, [line(0, 'A', 0)], caret, null, null, new api.ViewportInfo(0, 200), null, []);
  assert.equal(colors.length, 1, 'the caret disappears only near zero alpha (never a hard blink)');
});
check('typewriter scale hierarchy defaults and progressive falloff', () => {
  const o = new api.TypewriterScaleOptions();
  assert.equal(o.focusScale, 1.08, 'current paragraph is slightly enlarged');
  assert.equal(o.adjacentScale, 0.98, 'neighbouring lines are slightly reduced');
  assert.equal(o.scaleStep, 0.02);
  assert.equal(o.minScale, 0.90, 'focus mode never shrinks below 90%');
  const scale = (d) => api.typewriterScaleForDistance(d, o);
  assert.equal(scale(0), 1.08);
  assert.ok(scale(0.5) > 0.98 && scale(0.5) < 1.08, 'boundary values interpolate continuously');
  assert.equal(scale(1), 0.98);
  assert.equal(scale(2), 0.96);
  assert.equal(scale(5), 0.90);
  assert.equal(scale(20), 0.90);
  assert.equal(api.typewriterLineDistance(3, 3, 5), 0);
  assert.equal(api.typewriterLineDistance(2, 3, 5), 1);
  assert.equal(api.typewriterLineDistance(6, 3, 5), 1);
  assert.equal(api.typewriterDimWeight(0), 0);
  assert.equal(api.typewriterDimWeight(0.5), 0.5);
  assert.equal(api.typewriterDimWeight(2), 1);
});
check('typewriter per-line scaling is a draw-time transform with a clamped floor', () => {
  const theme = new api.RenderTheme();
  theme.textColumnWidthVp = 400;
  const scales = [];
  const ctx = { canvas: {
    clear() {}, attachBrush() {}, detachBrush() {}, drawTextBlob() {}, drawRect() {}, drawCircle() {},
    save() {}, restore() {}, translate() {}, scale(x, y) { scales.push(x); }
  }, invalidate() {} };
  const renderer = new api.GlyphRenderer(theme);
  const lines = [line(0, 'aa', 0), line(2, 'bb', 28), line(4, 'cc', 56), line(6, 'dd', 84)];
  renderer.draw(ctx, lines, null, null, null, new api.ViewportInfo(0, 300), null, [], true, 2, 2, true);
  assert.deepEqual(scales.map(v => Math.round(v * 100) / 100), [0.96, 0.98, 1.08, 0.98]);
});
check('typewriter focus retargets on paragraph switch without stacking animations', () => {
  const e = editor('a\n\nbc\nd');
  e.typewriterOverride = 1;
  e.effectivePolicy = () => 1;
  e.viewHeightVp = 200;
  e.theme.paddingTop = 8;
  e.lines = [line(0, 'a', 0), line(2, '', 28), line(3, 'bc', 56), line(6, 'd', 84)];
  e.doc.moveCaret(3);
  e.twDirty = true;
  e.refreshTypewriterFocus();
  assert.equal(e.twAnimFirst, 2);
  assert.equal(e.twAnimLast, 2);
  e.doc.moveCaret(6);
  e.twDirty = true;
  e.refreshTypewriterFocus();
  assert.equal(e.twAnimFirst, 3, 'switching paragraphs retargets the focus block');
  assert.equal(e.twAnimLast, 3);
  e.doc.moveCaret(3);
  e.twDirty = true;
  e.refreshTypewriterFocus();
  assert.equal(e.twAnimFirst, 2, 'rapid switching starts from the latest state instead of stacking');
});
check('caret uses the exact caret line scale instead of an overlapping y-range guess', () => {
  const theme = new api.RenderTheme();
  theme.textColumnWidthVp = 200;
  const renderer = new api.GlyphRenderer(theme);
  const rects = [];
  const ctx = { canvas: {
    clear() {}, attachBrush() {}, detachBrush() {}, drawTextBlob() {}, drawCircle() {},
    save() {}, restore() {}, translate() {}, scale() {}, clipRect() {},
    drawRect(r) { rects.push(r); }
  }, invalidate() {} };
  const lines = [line(0, 'A', 0), line(1, 'B', 28)];
  const caretA = new api.CursorState();
  caretA.x = 100; caretA.y = 30; caretA.height = 24; caretA.visible = true;
  const caretB = new api.CursorState();
  caretB.x = 100; caretB.y = 30; caretB.height = 24; caretB.visible = true;
  // 焦点在第二行：显式行号 1 → 1.08×；错误地退化成行号 0 → 0.98×，两者横向位置必须不同
  renderer.draw(ctx, lines, caretA, null, null, new api.ViewportInfo(0, 200), null, [], true, 1, 1, true, 1);
  const leftExact = rects[rects.length - 1].left;
  rects.length = 0;
  renderer.draw(ctx, lines, caretB, null, null, new api.ViewportInfo(0, 200), null, [], true, 1, 1, true, 0);
  const leftWrong = rects[rects.length - 1].left;
  assert.ok(leftExact > leftWrong + 1, 'explicit caret line must apply the 1.08 scale (left ' + leftExact + ' vs ' + leftWrong + ')');
});
check('typewriter spotlight scale is capped by the measured line width (never overflows)', () => {
  const theme = new api.RenderTheme();
  theme.viewWidthVp = 200;
  theme.paddingLeftVp = 12;
  theme.paddingRightVp = 12;
  theme.textColumnWidthVp = 176;
  const scales = [];
  const ctx = { canvas: {
    clear() {}, attachBrush() {}, detachBrush() {}, drawTextBlob() {}, drawRect() {}, drawCircle() {},
    save() {}, restore() {}, translate() {}, scale(x, y) { scales.push(x); }, clipRect() {}
  }, invalidate() {} };
  const renderer = new api.GlyphRenderer(theme);
  // 176 可用宽：170 宽的行只能放大到 176/170 ≈ 1.035；100 宽的行可到 1.08
  const wide = line(0, 'x'.repeat(17), 0);
  const narrow = line(18, 'x'.repeat(10), 28);
  renderer.draw(ctx, [wide, narrow], null, null, null, new api.ViewportInfo(0, 300), null, [], true, 0, 1, true, -1);
  assert.equal(scales.length, 2);
  assert.ok(Math.abs(scales[0] - 176 / 170) < 0.001, 'wide line clamped to fit: ' + scales[0]);
  assert.ok(Math.abs(scales[1] - 1.08) < 0.001, 'short line keeps the full spotlight: ' + scales[1]);
});
check('scaled text, caret and selection share the left-edge pivot', () => {
  const theme = new api.RenderTheme();
  theme.viewWidthVp = 200;
  theme.paddingLeftVp = 12;
  theme.paddingRightVp = 12;
  theme.textColumnWidthVp = 176;
  const blobX = [];
  const rects = [];
  const ctx = { canvas: {
    clear() {}, attachBrush() {}, detachBrush() {},
    drawTextBlob(b, x) { blobX.push(x); },
    drawRect(r) { rects.push(r); }, drawCircle() {},
    save() {}, restore() {}, translate() {}, scale() {}, clipRect() {}
  }, invalidate() {} };
  const renderer = new api.GlyphRenderer(theme);
  const l = line(0, 'x'.repeat(10), 0);
  const caret = new api.CursorState();
  caret.x = 100; caret.y = 5; caret.height = 24; caret.visible = true;
  renderer.draw(ctx, [l], caret, null, null, new api.ViewportInfo(0, 300), null, [], true, 0, 0, true, 0);
  // 左轴心：缩放不会把文本左边界推离 paddingLeft
  assert.equal(blobX[0], 12, 'text must keep the left padding (got ' + blobX[0] + ')');
  // 光标同样围绕左轴心：12 + (100-12)*1.08 - halfW(1) ≈ 106
  const left = rects[rects.length - 1].left;
  assert.ok(Math.abs(left - 106.04) < 0.2, 'caret must share the same pivot (got ' + left + ')');
});
check('Shift digit fallback preserves the active keyboard layout symbols',()=>{
  assert.equal(shortcut(K('KEYCODE_2'), '"', modsOf(false,true)).text, '"');
  assert.equal(shortcut(K('KEYCODE_3'), '£', modsOf(false,true)).text, '£');
  assert.equal(shortcut(K('KEYCODE_2'), '', modsOf(false,true)).text, '@');
});
check('Meta uses the supported KeyEvent field without querying an unsupported modifier',()=>{
  const queried=[];const e=editor('');
  const mods=e.readEditorModifiers({metaKey:1,getModifierKeyState(names){
    assert.ok(['Ctrl','Shift','Alt'].includes(names[0]));queried.push(names[0]);return names[0]==='Shift';
  }});
  assert.equal(mods.meta,true);assert.equal(mods.shift,true);assert.equal(mods.ctrl,false);
  assert.deepEqual(queried,['Ctrl','Shift','Alt']);
});
check('rapid keyboard fallbacks retain each pending IME echo once',()=>{
  const guard=new api.ImeEchoGuard();
  guard.recordKeyboardFallback('a',100);guard.recordKeyboardFallback('b',110);
  assert.equal(guard.claim('a',120),true);assert.equal(guard.claim('b',120),true);
  guard.recordKeyboardFallback('x',200);guard.recordKeyboardFallback('x',205);
  assert.equal(guard.claim('x',210),true);assert.equal(guard.claim('x',211),true);
  assert.equal(guard.claim('x',212),false);
  guard.recordKeyboardFallback('old',300);guard.recordKeyboardFallback('new',345);
  assert.equal(guard.claim('old',346),false);assert.equal(guard.claim('new',346),true);
  guard.recordKeyboardFallback('z',400);guard.reset();assert.equal(guard.claim('z',401),false);
});
check('document replacement cancels pending IME echoes and obsolete drag identity',()=>{
  const e=editor('A');e.echoGuard.recordKeyboardFallback('x',Date.now());
  e.selMgr.beginDrag(0);e.selMgr.beginHandleDrag(1);e.mouseSelecting=true;e.dragging=true;
  e.loadDocument('B',[],1);assert.equal(e.echoGuard.armed,false);
  assert.equal(e.selMgr.draggingHandle,0);assert.equal(e.dragging,false);assert.equal(e.mouseSelecting,false);
});
check('IME reports every changed preview including same-length replacements',()=>{
  const e=editor('A');const reports=[];
  e.ime={attached:true,changeSelection(...args){reports.push(args);}};e.engineRef=null;
  e.reportSelection=api.EditorProbe.prototype.reportSelection;e.registerImeCallbacks();
  e.ime.onPreviewText('ni',-1,-1);e.ime.onPreviewText('ha',-1,-1);e.ime.onPreviewText('hao',-1,-1);
  assert.deepEqual(reports.map(v=>v[0]),['Ani','Aha','Ahao']);
  e.reportSelection();assert.equal(reports.length,3);
  e.previewMgr.cancel();e.selMgr.collapse(0);e.reportSelection();
  e.selMgr.collapse(1);e.reportSelection();assert.deepEqual(reports.at(-1),['A',1,1]);
});
check('format state requires the entire selection and matches the character before a caret',()=>{
  const e=editor('abc');e.doc.setRuns([new api.FormatRun(0,1,true),new api.FormatRun(2,3,true)]);
  e.selMgr.setSelection(0,3);assert.equal(e.inlineStyleMask(),0);
  e.selMgr.collapse(1);e.doc.moveCaret(1);assert.equal(e.inlineStyleMask(),1);
  e.selMgr.collapse(2);e.doc.moveCaret(2);assert.equal(e.inlineStyleMask(),0);
});
check('Home and End retain their visual line at a soft-wrap boundary',()=>{
  const e=editor('ABCDEF');e.lines=[line(0,'ABC'),line(3,'DEF',28)];e.moveCaretAnimated(1);
  const end=new api.KeyboardEvent();end.action=api.KeyAction.MOVE_LINE_END;
  e.applyKeyCommand(end);assert.equal(e.doc.caretOffset,3);assert.equal(e.caret.x,30);assert.equal(e.caret.y,4);
  e.applyKeyCommand(end);assert.equal(e.doc.caretOffset,3);assert.equal(e.caret.x,30);
  const home=new api.KeyboardEvent();home.action=api.KeyAction.MOVE_LINE_START;e.applyKeyCommand(home);
  assert.equal(e.doc.caretOffset,0);e.moveCaretAnimated(3);assert.equal(e.caret.x,0);assert.equal(e.caret.y,32);
});
check('scaled pointer hits, handles and IME caret use the rendered text coordinates',()=>{
  const theme=new api.RenderTheme();theme.paddingLeftVp=12;theme.paddingTopVp=8;
  theme.viewWidthVp=1000;theme.textColumnWidthVp=500;theme.typewriterScale.focusScale=1.2;
  const renderer=new api.GlyphRenderer(theme);const lines=[line(0,'ABCDEFGHIJ')];
  const caret=api.HitTester.caretPositionFor(9,lines,12,8,16);
  const visual=renderer.visualCaret(caret,lines,true,0,0);
  assert.equal(visual.x,120);assert.equal(visual.height,caret.height*1.2);
  assert.equal(renderer.hitTest(visual.x,8+visual.y+visual.height/2,lines,'ABCDEFGHIJ',true,0,0),9);
  const e=editor('ABCDEFGHIJ');e.lines=lines;e.renderer=renderer;e.effectivePolicy=()=>1;e.padLeftVp=()=>12;
  e.twAnimFirst=0;e.twAnimLast=0;e.refreshTypewriterFocus=()=>{};e.selMgr.setSelection(1,9);
  assert.equal(e.handlePositions()[1].x,120);
});
check('coordinate-free touch cancellation clears drag and handle state',()=>{
  const e=editor('ABCDE');e.selMgr.setSelection(1,4);e.selMgr.beginHandleDrag(1);
  e.dragging=true;e.scrollMode=true;e.onScrollState=null;
  e.handleTouch({type:3,touches:[],changedTouches:[]});
  assert.equal(e.dragging,false);assert.equal(e.scrollMode,false);assert.equal(e.selMgr.draggingHandle,0);
});
check('comma, period and numeric keypad punctuation reach the fallback input path',()=>{
  for (const [name,text] of [['COMMA',','],['PERIOD','.'],['NUMPAD_ADD','+'],['NUMPAD_DIVIDE','/'],
    ['NUMPAD_MULTIPLY','*'],['NUMPAD_SUBTRACT','-'],['NUMPAD_DOT','.'],['NUMPAD_COMMA',','],
    ['NUMPAD_EQUALS','='],['NUMPAD_LEFT_PAREN','('],['NUMPAD_RIGHT_PAREN',')']]) {
    const e=editor('');assert.equal(e.handleKeyPreIme(keyEvent(K('KEYCODE_'+name),text)),true,name);
    assert.equal(e.doc.text,text,name);
  }
  assert.equal(shortcut(2119).text,'\n');assert.equal(shortcut(2116,'+').text,'+');
});
check('pointer clicks retain either visual side of a shared soft-wrap offset',()=>{
  const e=editor('ABCDEF');e.lines=[line(0,'ABC'),line(3,'DEF',28)];
  const upper=e.affinityAt(10,3),lower=e.affinityAt(40,3);
  assert.equal(upper,api.CaretAffinity.UPSTREAM);assert.equal(lower,api.CaretAffinity.DOWNSTREAM);
  e.placeCaretImmediately(3,upper);assert.equal(e.caret.x,30);assert.equal(e.caret.y,4);
  e.placeCaretImmediately(3,lower);assert.equal(e.caret.x,0);assert.equal(e.caret.y,32);
});
check('run-local and line-absolute native glyphs render at the same distinct positions',()=>{
  for (const local of [true,false]) {
    const engine=new api.TextLayoutEngine(400,16,24,4,2);engine.indexMap=new api.TextIndexMap('AB中文');
    const makeRun=(start,glyphs,positions)=>({getStringRange(){return {start,end:2};},getStringIndices(){return [start,start+1];},
      getGlyphs(){return glyphs;},getFont(){return new Font();},getAdvances(){return [{x:20,y:0},{x:20,y:0}];},
      getPositions(){return positions.map(x=>({x,y:0}));}});
    const native={getTextRange(){return {start:0,end:4};},getGlyphRuns(){return [makeRun(0,[65,66],[0,20]),
      makeRun(2,[20013,25991],local?[0,20]:[40,60])];},
      getTypographicBounds(){return {ascent:28,descent:8,leading:0,width:80};},
      getOffsetForStringIndex(n){return n*20;}};
    const layout=engine.buildLayoutLineFrom(native,0,4,0);
    assert.equal(layout.runs[1].runOffsetX,local?20:0);
    assert.deepEqual(json(layout.runs[1].positions),local?[{x:0,y:0},{x:10,y:0}]:[{x:20,y:0},{x:30,y:0}]);
    const theme=new api.RenderTheme();theme.pxPerVp=2;theme.paddingLeftVp=0;theme.paddingTopVp=0;
    const renderer=new api.GlyphRenderer(theme);const painted=[];
    const canvas={clear(){},save(){},restore(){},clipRect(){},attachBrush(){},detachBrush(){},
      drawTextBlob(blob,x,y){for(const glyph of blob.buffer)painted.push([glyph.glyph,x+glyph.positionX]);}};
    renderer.draw({canvas,invalidate(){}},[layout],null,null,null,new api.ViewportInfo(0,100),null,[]);
    assert.deepEqual(painted,[[65,0],[66,20],[20013,40],[25991,60]],'cached '+local);
    const preview=new api.PreviewInfo();preview.startOffset=2;preview.text='中';preview.endOffset=3;painted.length=0;
    renderer.draw({canvas,invalidate(){}},[layout],null,null,preview,new api.ViewportInfo(0,100),null,[]);
    assert.deepEqual(painted.sort((a,b)=>a[1]-b[1]),[[65,0],[66,20],[20013,40],[25991,60]],'preview '+local);
  }
});
(async()=>{
  for(const failed of [false,true]) {
    let completePaste;context.pasteboard={getSystemPasteboard(){return {getData(){return new Promise((resolve,reject)=>{
      completePaste=()=>failed?reject({code:1}):resolve({getPrimaryText(){return 'X';}});
    });}};}};
    vm.runInContext("appClipboard='FALLBACK'",context);
    const e=editor('ABCDE');e.selMgr.setSelection(1,4);e.emitSelection();let edits=0;e.onEdit=()=>edits++;
    e.pasteAtCaret();completePaste();await Promise.resolve();await Promise.resolve();
    assert.equal(e.doc.text,failed?'AFALLBACKE':'AXE');assert.equal(edits,1);
    count++;console.log('PASS current-document paste '+(failed?'fallback':'success')+' replaces its selection');
  }
  for(const failed of [false,true]) {
    let completePaste;context.pasteboard={getSystemPasteboard(){return {getData(){return new Promise((resolve,reject)=>{
      completePaste=()=>failed?reject({code:1}):resolve({getPrimaryText(){return 'PASTE';}});
    });}};}};
    vm.runInContext("appClipboard='FALLBACK'",context);
    const e=editor('Document A');let edits=0;e.onEdit=()=>edits++;e.pasteAtCaret();
    e.loadDocument('Document B',[],10);completePaste();await Promise.resolve();await Promise.resolve();
    assert.equal(e.doc.text,'Document B');assert.equal(edits,0);
    count++;console.log('PASS delayed paste '+(failed?'fallback':'success')+' cannot edit a replacement document');
  }
  for(const failed of [false,true]) {
    let completePaste;context.pasteboard={getSystemPasteboard(){return {getData(){return new Promise((resolve,reject)=>{
      completePaste=()=>failed?reject({code:1}):resolve({getPrimaryText(){return 'PASTE';}});
    });}};}};
    const store=new api.EditorStore();store.scheduleFlush=()=>{};
    const a=new api.OpenDoc('a','A',0,'','Document A',10),b=new api.OpenDoc('b','B',0,'','Document B',10);
    store.openDocs=[a,b];store.activeId='a';const e=editor(a.draft);
    e.onEdit=(text,runs,caret)=>store.setEditorState(text,'',caret,'a');e.pasteAtCaret();
    // activeId changes before the host's next UI update has loaded B into the canvas.
    store.activeId='b';completePaste();await Promise.resolve();await Promise.resolve();
    assert.equal(b.draft,'Document B');assert.equal(b.caret,10);assert.equal(b.dirty,false);
    assert.equal(a.draft,'Document A');assert.equal(store.undoStack.length,0);
    count++;console.log('PASS paste '+(failed?'fallback':'success')+' cannot edit a new active document before host reload');
  }
  {
    let resolvePaste;context.pasteboard={getSystemPasteboard(){return {getData(){return new Promise(resolve=>{resolvePaste=resolve;});}};}};
    const e=editor('closed document');let edits=0;e.onEdit=()=>edits++;e.pasteAtCaret();e.aboutToDisappear();
    resolvePaste({getPrimaryText(){return 'PASTE';}});await Promise.resolve();await Promise.resolve();
    assert.equal(e.doc.text,'closed document');assert.equal(edits,0);
    count++;console.log('PASS delayed paste cannot edit an unmounted editor');
  }
  const bridge=new api.ImeBridge();const other=()=>{};listeners.set('insertText',new Set([other]));
  const one=bridge.attach(false,0,0), two=bridge.attach(false,0,0);
  assert.equal(nativeAttachCount,1);assert.equal(one,two);bridge.detach();resolveAttach();await one;
  assert.equal(bridge.attached,false);assert.equal(nativeDetachCount,1);assert.equal(listeners.get('insertText').size,1);
  const attached=bridge.attach(false,0,0);resolveAttach();await attached;assert.equal(bridge.attached,true);assert.equal(listeners.get('insertText').size,2);bridge.detach();assert.equal(listeners.get('insertText').size,1);
  count++;console.log('PASS pending IME attach, cancellation and owned listener cleanup');
  {
    const frozenDate = context.Date;
    let now = 5000;
    context.Date = { now: () => now };
    try {
      const e = editor('');
      e.imeUsable = false;
      e.ime.setEchoGuard(e.echoGuard);
      e.registerImeCallbacks();
      const attached = e.ime.attach(false, 0, 0);
      resolveAttach();
      await attached;
      assert.equal(e.handleKeyPreIme(keyEvent(K('KEYCODE_X'), 'x')), true);
      assert.equal(e.doc.text, 'x');
      assert.equal(e.echoGuard.armed, true);
      const deliver = value => { for (const callback of listeners.get('insertText')) callback(value); };
      now = 5010;
      deliver('x');
      assert.equal(e.doc.text, 'x', 'the IME echo inside 40ms must be dropped');
      now = 5100;
      deliver('x');
      assert.equal(e.doc.text, 'xx', 'a later identical IME commit is genuine input');
      e.ime.detach();
      count++;
      console.log('PASS keyboard fallback and IME echo suppression are wired through the real listeners');
    } finally {
      if (frozenDate === undefined) delete context.Date;
      else context.Date = frozenDate;
    }
  }
  console.log(`FlowText regression: ${count} checks passed`);
})().catch(error=>{console.error(error);process.exitCode=1;});
