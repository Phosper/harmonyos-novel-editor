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
const context = vm.createContext({console, setTimeout() {return 1;}, clearTimeout() {},
  text: { FontCollection: { getGlobalInstance() { return {}; } }, ParagraphBuilder,
    FontWeight:{W700:700}, FontStyle:{ITALIC:1} },
  drawing: {Font, Brush, TextBlob: {makeFromRunBuffer(buffer, font) {return {buffer,font};}}},
  KeyCode: { KEYCODE_DPAD_LEFT:2012 }, KeyType:{Down:0}, ChapterFormat:{TXT:0},
  Logger:{info(){}}, inputMethod:{getController(){return controller;}}
});
const read = file => fs.readFileSync(path.join(root,file),'utf8');
function compile(source) {
  return stripTypeScriptTypes(source.replace(/^import\s+[\s\S]*?from\s+['"][^'"]+['"];?\s*$/gm,'')
    .replace(/\bexport\s+/g,'').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,''), {mode:'transform'});
}
function load(file) {vm.runInContext(compile(read(file)),context,{filename:file});}
for (const file of ['model/EditorTypes','model/TextIndexMap','model/UnicodeGraphemeData','model/GraphemeUtil','model/TextDocument',
  'interaction/SelectionManager','interaction/CursorState','interaction/HitTester','render/TextLayoutEngine',
  'render/LayoutCache','render/GlyphRenderer','animation/GlyphAnimator','ime/PreviewTextManager','ime/KeyboardHandler','ime/ImeBridge']) {
  load('editor/flowtext/'+file+'.ets');
}
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
  'handleKeyPreIme','isNavigationAction','readModifiers','registerImeCallbacks','refreshPreview','displayText','displayCaret','deletePreview','deleteExternalLeft',
  'pasteAtCaret','insertAtCaret','aboutToDisappear'].map(name=>method(canvas,name)).join('\n')+'\n  loadText(text: string): void { this.loadDocument(text, [], text.length); }\n  currentCaret(): number { return this.doc.caretOffset; }\n}'),context);
vm.runInContext(compile('class HostProbe {\n'+method(read('editor/TextEditorHost.ets'),'onContentRevChanged')+'\n}'),context);
const api = vm.runInContext('({TextIndexMap,GraphemeUtil,TextDocument,SelectionManager,FormatRun,StyleKind,LayoutLine,GlyphRunData,'+
  'CursorState,HitTester,TextLayoutEngine,LayoutCache,GlyphRenderer,RenderTheme,ViewportInfo,GlyphAnimator,GlyphDiffOptions,'+
  'PreviewTextManager,KeyAction,KeyboardEvent,KeyboardHandler,ImeBridge,CanvasTextEditorController,EditorProbe,HostProbe,EditorStore,OpenDoc})',context);
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
    lastText:value,preferredX:-1,anims:{clear(){}},lines:[],caret:new api.CursorState(),theme:{fontSize:16},
    cache:null,renderer:null,onEdit:null,onCaretChange:null,onTextChange:null,onFormatChange:null,onSelectionChange:null,
    documentGeneration:0,controller:null,ime:new api.ImeBridge(),caretAnimator:null,glyphAnimator:null,
    padLeftVp(){return 0;},padTopVp(){return 0;},ensureCaretLayout(){},ensureCaretVisible(){},effectivePolicy(){return 0;},
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
  console.log(`FlowText regression: ${count} checks passed`);
})().catch(error=>{console.error(error);process.exitCode=1;});
