/**
 * FlowText 自绘编辑器组件（完全方案 C）
 *
 * Canvas(DrawingRenderingContext, PX) + @ohos.graphics.text 字形级排版 +
 * TextBlob 字形级绘制 + IME Kit 自绘编辑框输入 + 弹簧动画。
 *
 * 动画体系（目标状态驱动）：
 *   - 光标移动：caretAnimator 逐帧插值光标坐标（interpolating-spring）
 *   - 字形变化：glyphAnimator 逐帧插值字形位置/透明度/缩放
 *     （让位/回流/换行 → 位置插值；插入 → 缩放+淡入；删除 → 收缩+淡出）
 *
 * 对外：CanvasTextEditorController（setText/getText/setCaretPosition/focus/blur/insertTextAtCaret/deleteLeftAtCaret）
 */
import { inputMethod } from '@kit.IMEKit';
import { deviceInfo, pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { common2D } from '@kit.ArkGraphics2D';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { TextDocument } from './model/TextDocument';
import { GraphemeUtil } from './model/GraphemeUtil';
import { SelectionInfo, PreviewInfo, ViewportInfo, ScrollPolicy, StyleKind, FormatRun } from './model/EditorTypes';
import { EditorTheme } from './theme/EditorTheme';
import { TextLayoutEngine, LayoutLine } from './render/TextLayoutEngine';
import { LayoutCache } from './render/LayoutCache';
import { GlyphRenderer, RenderTheme, GlyphAnimRegistry, GlyphAnimState } from './render/GlyphRenderer';
import { GlyphAnimator, GlyphDiffOptions } from './animation/GlyphAnimator';
import { HitTester } from './interaction/HitTester';
import { CursorState } from './interaction/CursorState';
import { SelectionManager } from './interaction/SelectionManager';
import { EditorGesture } from './interaction/EditorGesture';
import { ImeBridge } from './ime/ImeBridge';
import { KeyboardHandler, KeyAction, KeyboardEvent } from './ime/KeyboardHandler';
import { PreviewTextManager } from './ime/PreviewTextManager';
import { EditorAnimator } from './animation/EditorAnimator';
import { AnimationSpec } from './animation/AnimationSpec';

/** 运行时诊断开关：真机排查"动画/交互错乱"时置 true，便于比对 触摸坐标/命中/caret/scrollY/progress。 */
const DIAG_ENABLED: boolean = false;
/** 本特性预留的量化诊断标签（经 diag() 输出，供 Phase 5 真机核验）：
 *  scroll=滚动偏移、center=居中偏差、anim=字符动画、fmt=格式变更。 */
/** 诊断日志 tag（console.info，JSAPP 通道；hilog 缓冲不可靠） */
const DIAG_TAG: string = 'FlowTextDiag';
/** 容器 id：.id() 与 requestFocus 必须一致，单独提出常量防止两处漂移。
 *  注意：该 id 挂在包裹 Canvas 的 Stack 上（Canvas 无获焦能力，不能作为焦点目标）。 */
const CANVAS_EDITOR_ID: string = 'canvasTextEditor';

/** 应用内剪贴板回退缓冲：部分环境下系统剪贴板不可读，保证编辑器内复制/粘贴可用 */
let appClipboard: string = '';

/** 颜色解析：#RRGGBB / #AARRGGBB → common2D.Color（AARRGGBB：alpha 在前） */
function parseColor(hex: string): common2D.Color {
  let str = hex;
  if (str.startsWith('#')) {
    str = str.substring(1);
  }
  let r = 0;
  let g = 0;
  let b = 0;
  let a = 255;
  if (str.length >= 8) {
    // #AARRGGBB：alpha 在前
    a = parseInt(str.substring(0, 2), 16);
    r = parseInt(str.substring(2, 4), 16);
    g = parseInt(str.substring(4, 6), 16);
    b = parseInt(str.substring(6, 8), 16);
  } else if (str.length >= 6) {
    // #RRGGBB
    r = parseInt(str.substring(0, 2), 16);
    g = parseInt(str.substring(2, 4), 16);
    b = parseInt(str.substring(4, 6), 16);
  }
  return { alpha: a, red: r, green: g, blue: b };
}

export class CanvasTextEditorController {
  private editor: CanvasTextEditor | null = null;
  /** 待处理文本：宿主页面在编辑器绑定前调用 setText 时暂存，绑定后立即应用，避免文本丢失。 */
  private pendingText: string | null = null;
  /** 待处理光标位置：绑定前暂存，绑定 + 排版后应用 */
  private pendingCaret: number = -1;
  /** 待处理焦点请求：绑定前暂存 */
  private pendingFocus: boolean = false;
  private pendingRuns: FormatRun[] = [];

  unbind(editor: CanvasTextEditor): void {
    if (this.editor === editor) {
      this.pendingText = editor.currentText();
      this.pendingRuns = editor.getRuns().map((run: FormatRun): FormatRun => run.clone());
      this.pendingCaret = editor.currentCaret();
      this.editor = null;
    }
  }

  bind(editor: CanvasTextEditor): void {
    this.editor = editor;
    // 若在绑定前已有 setText 调用（如宿主页面 aboutToAppear 先于子 editor 绑定），此刻补载入
    if (this.pendingText !== null) {
      const t: string = this.pendingText;
      this.pendingText = null;
      this.editor.loadDocument(t, this.pendingRuns, this.pendingCaret >= 0 ? this.pendingCaret : t.length);
      this.pendingCaret = -1;
    } else { this.editor.setRuns(this.pendingRuns); }
    // 处理暂存的光标
    if (this.pendingCaret >= 0) {
      const caret: number = this.pendingCaret;
      this.pendingCaret = -1;
      this.editor.moveCaretTo(caret);
    }
    // 处理暂存的焦点
    if (this.pendingFocus) {
      this.pendingFocus = false;
      this.editor.requestEditorFocus();
    }
  }

  setText(text: string): void {
    if (this.editor !== null) {
      this.editor.loadText(text);
    } else {
      this.pendingText = text;
    }
  }

  setDocument(value: string, runs: FormatRun[], caret: number): void {
    this.pendingRuns = runs.map((run: FormatRun): FormatRun => run.clone());
    if (this.editor !== null) { this.editor.loadDocument(value, this.pendingRuns, caret); }
    else { this.pendingText = value; this.pendingCaret = caret; }
  }

  getText(): string {
    if (this.editor === null) {
      return '';
    }
    return this.editor.currentText();
  }

  setCaretPosition(offset: number): void {
    if (this.editor !== null) {
      this.editor.moveCaretTo(offset);
    } else {
      this.pendingCaret = offset;
    }
  }

  focus(): void {
    if (this.editor !== null) {
      this.editor.requestEditorFocus();
    } else {
      this.pendingFocus = true;
    }
  }

  blur(): void {
    if (this.editor !== null) {
      this.editor.releaseEditorFocus();
    }
    this.pendingFocus = false;
  }

  /** 模拟输入（供演示/预览器无 IME 场景测试） */
  insertTextAtCaret(text: string): void {
    if (this.editor !== null) {
      this.editor.insertExternalText(text);
    }
  }

  /** 模拟删除（供演示/预览器无 IME 场景测试） */
  deleteLeftAtCaret(length: number): void {
    if (this.editor !== null) {
      this.editor.deleteExternalLeft(length);
    }
  }

  /** 切换行内样式（粗/斜）于当前选区（T023） */
  toggleInlineStyle(kind: StyleKind): void {
    if (this.editor !== null) {
      this.editor.toggleInlineStyle(kind);
    }
  }

  /** 切换段落标题级别于当前选区（T023） */
  toggleParagraphStyle(level: number): void {
    if (this.editor !== null) {
      this.editor.toggleParagraphStyle(level);
    }
  }

  /** 载入格式标注（回灌，T024/T025） */
  setRuns(runs: FormatRun[]): void {
    this.pendingRuns = runs.map((run: FormatRun): FormatRun => run.clone());
    if (this.editor !== null) {
      this.editor.setRuns(runs);
    }
  }

  /** 取当前格式标注 */
  getRuns(): FormatRun[] {
    return this.editor !== null ? this.editor.getRuns() : [];
  }
}

@Component
export struct CanvasTextEditor {
  @Prop @Watch('onThemeChanged') fontSize: number = 16;
  @Prop @Watch('onThemeChanged') lineHeight: number = 24;
  @Prop @Watch('onThemeChanged') lineSpacing: number = 4;
  @Prop @Watch('onThemeChanged') textColor: string = '#1F2329';
  @Prop @Watch('onThemeChanged') bgColor: string = '#FFFFFF';
  @Prop @Watch('onThemeChanged') caretColor: string = '#0A59F7';
  @Prop placeholder: string = '';
  /** 打字机模式：为 true 时按 scrollPolicy=CENTER 使当前段居中（默认关） */
  @Prop typewriter: boolean = false;
  /** 滚动策略：NORMAL（仅保证光标可见）/ CENTER（当前段居中跟随） */
  @Prop scrollPolicy: ScrollPolicy = ScrollPolicy.NORMAL;

  /** 外部注入控制器（非必填） */
  controller: CanvasTextEditorController | null = null;

  onTextChange: ((text: string, version: number) => void) | null = null;
  /** One history/persistence transaction for text, shifted formats and caret. */
  onEdit: ((text: string, runs: FormatRun[], caret: number) => void) | null = null;
  onCaretChange: ((offset: number) => void) | null = null;
  /** 选区变化（start/end，用于工具栏态） */
  onSelectionChange: ((start: number, end: number) => void) | null = null;
  /** 格式变化（Phase B 生效） */
  onFormatChange: ((runs: FormatRun[]) => void) | null = null;
  /** 滚动状态：1 向下 / -1 向上 / 0 停止（用于沉浸显隐） */
  onScrollState: ((state: number) => void) | null = null;
  /** 请求保存（失焦/键盘隐藏等时机，T028） */
  onRequestSave: (() => void) | null = null;
  /** 选区"查找"请求（携带选中文本，由应用层打开查找面板） */
  onRequestFind: ((text: string) => void) | null = null;
  /** 选区"分享"请求（携带选中文本） */
  onRequestShare: ((text: string) => void) | null = null;
  /** 撤销/重做交给宿主（历史栈在 EditorStore 里，不在文档模型内） */
  onUndo: (() => void) | null = null;
  onRedo: (() => void) | null = null;

  private ctx: DrawingRenderingContext = new DrawingRenderingContext(LengthMetricsUnit.PX);
  private theme: EditorTheme = new EditorTheme();
  private doc: TextDocument = new TextDocument();
  private ime: ImeBridge = new ImeBridge();
  private previewMgr: PreviewTextManager = new PreviewTextManager();
  private selMgr: SelectionManager = new SelectionManager();
  /** 载入或销毁后，旧粘贴请求不得再改写当前文稿。 */
  private documentGeneration: number = 0;
  private caretAnimator: EditorAnimator | null = null;
  private glyphAnimator: EditorAnimator | null = null;
  private caret: CursorState = new CursorState();
  private pxPerVp: number = 1;
  private viewWidthVp: number = 0;
  private viewHeightVp: number = 0;
  private scrollY: number = 0;
  private lines: LayoutLine[] = [];
  private oldLines: LayoutLine[] = [];
  private lastEditOffset: number = 0;
  private cache: LayoutCache | null = null;
  private engineWidth: number = -1;
  private previewDoc: TextDocument | null = null;
  private previewCache: LayoutCache | null = null;
  private windowX: number = 0;
  private windowY: number = 0;
  private lastText: string = '';
  private mouseSelecting: boolean = false;
  private preferredX: number = -1;
  /** 排版引擎引用（分词选词用） */
  private engineRef: TextLayoutEngine | null = null;
  private renderer: GlyphRenderer | null = null;
  private anims: GlyphAnimRegistry = new GlyphAnimRegistry();
  private blinkTimer: number = -1;
  private initialized: boolean = false;
  private focused: boolean = false;
  /** 是否已真正取得框架焦点（onFocus 确认）；未确认时会在布局就绪后补发焦点请求 */
  private focusConfirmed: boolean = false;
  /** 是否需要"打开即聚焦"：布局就绪后补发一次 requestEditorFocus（组件上树前请求会失败） */
  private wantInitFocus: boolean = false;
  /** 光标动画是否正在进行（用于在键盘/视口 relayout 时避免硬编码覆盖正在播放的光标） */
  private caretAnimating: boolean = false;
  // 触摸状态
  private pressX: number = 0;
  private pressY: number = 0;
  private dragging: boolean = false;
  private scrollMode: boolean = false;
  private pressScrollY: number = 0;
  /** 惯性滑动：速度(vp/ms)、上一帧位置/时间、定时器 */
  private scrollVel: number = 0;
  private lastScrollY: number = 0;
  private lastScrollAt: number = 0;
  private flingTimer: number = -1;
  /** 滚动时是否已收起软键盘（点击后重新拉起） */
  private keyboardSuppressed: boolean = false;
  /** 惯性参数：每帧(≈16ms)速度衰减系数（越接近 1 越顺滑、滑得越远）与初速放大 */
  private readonly FLING_FRICTION: number = 0.985;
  private readonly FLING_VEL_FACTOR: number = 16;
  /** 长按定时器（-1 未启动） */
  private longPressTimer: number = -1;
  private readonly LONG_PRESS_MS: number = 450;
  /** 双击判定窗口（ms）与上次点按时间；取 400ms 以容纳较慢的双击节奏 */
  private readonly DOUBLE_TAP_MS: number = 400;
  private lastTapAt: number = 0;
  /** 连击计数：1 单(定位) / 2 双击(选词) / 3 三击(选段) */
  private tapStreak: number = 0;
  /** 本次按住是否已触发长按选中（用于 Up 时不坍缩选区） */
  private longPressed: boolean = false;

  /** 选区操作浮层显隐、位置（vp）与箭头方向 */
  @State menuVisible: boolean = false;
  @State menuX: number = 0;
  @State menuY: number = 0;
  @State menuBelow: boolean = false;

  // ================= 选区操作浮层（补齐自绘化后丢失的系统选择菜单） =================

  @Builder
  selectionMenu() {
    Column() {
      if (!this.menuBelow) {
        Text('▼').fontSize(9).fontColor('#E61F2329')
      }
      Column() {
        Row() {
          Text('撤销').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.requestUndo())
          Text('重做').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.requestRedo())
          Text('粗').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.applyInline(StyleKind.BOLD))
          Text('斜').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.applyInline(StyleKind.ITALIC))
          Text('标题').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.applyHeading(1))
        }
        Row() {
          Text('复制').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.copySelection())
          Text('剪切').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.cutSelection())
          Text('粘贴').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.pasteAtCaret())
          Text('全选').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.selectAllText())
          Text('查找').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.findSelection())
          Text('分享').fontSize(13).fontColor('#FFFFFF').padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .onClick(() => this.shareSelection())
        }
      }
      .backgroundColor('#E61F2329')
      .borderRadius(8)
      if (this.menuBelow) {
        Text('▲').fontSize(9).fontColor('#E61F2329')
      }
    }
    .position({ x: this.menuX, y: this.menuY })
  }

  /** 在选区上方/下方弹出操作浮层（带箭头，自动避让屏幕边缘） */
  private showSelectionMenu(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    if (sel.isEmpty()) {
      this.menuVisible = false;
      return;
    }
    const h: CursorState = HitTester.caretPositionFor(sel.startOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    const menuW: number = 320; // 两行各 5/6 项，约 320vp
    const menuH: number = 88;
    const topEdgeVp: number = this.theme.paddingTop + h.y - this.scrollY;
    let x: number = h.x;
    if (x + menuW > this.viewWidthVp) {
      x = Math.max(0, this.viewWidthVp - menuW);
    }
    if (x < 0) {
      x = 0;
    }
    let below: boolean = false;
    let y: number = topEdgeVp - menuH - 6;
    if (y < 0) {
      below = true;
      y = topEdgeVp + h.height + 6;
    }
    this.menuBelow = below;
    this.menuX = x;
    this.menuY = y;
    this.menuVisible = true;
    this.diag('menu show x=' + x.toFixed(1) + ' y=' + y.toFixed(1) + ' below=' + below.toString() +
      ' sel=' + sel.startOffset.toString() + '-' + sel.endOffset.toString());
  }

  private hideSelectionMenu(): void {
    if (this.menuVisible) {
      this.menuVisible = false;
    }
  }

  private requestUndo(): void {
    this.hideSelectionMenu();
    if (this.onUndo !== null) {
      this.onUndo();
    }
  }

  private requestRedo(): void {
    this.hideSelectionMenu();
    if (this.onRedo !== null) {
      this.onRedo();
    }
  }

  private applyInline(kind: StyleKind): void {
    this.toggleInlineStyle(kind);
    this.hideSelectionMenu();
  }

  private applyHeading(level: number): void {
    this.toggleParagraphStyle(level);
    this.hideSelectionMenu();
  }

  private findSelection(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    const text: string = sel.isEmpty() ? '' : this.doc.text.substring(sel.startOffset, sel.endOffset);
    this.hideSelectionMenu();
    if (this.onRequestFind !== null) {
      this.onRequestFind(text);
    }
  }

  private shareSelection(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    const text: string = sel.isEmpty() ? '' : this.doc.text.substring(sel.startOffset, sel.endOffset);
    this.hideSelectionMenu();
    if (this.onRequestShare !== null) {
      this.onRequestShare(text);
    }
  }

  /** 三击选段（按段落边界） */
  private selectParagraphAt(x: number, y: number): void {
    const offset: number = this.offsetAt(x, y);
    const text: string = this.doc.text;
    let start: number = text.lastIndexOf('\n', offset - 1);
    start = start < 0 ? 0 : start + 1;
    let end: number = text.indexOf('\n', offset);
    end = end < 0 ? text.length : end;
    if (end <= start) {
      return;
    }
    this.selMgr.setSource(text);
    this.selMgr.setSelection(start, end);
    this.doc.setSelection(start, end);
    this.caret = HitTester.caretPositionFor(end, this.lines, this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    this.diag('paragraph sel=' + start.toString() + '-' + end.toString());
    this.emitSelection();
    this.showSelectionMenu();
    this.drawNow();
    this.reportCursor();
  }

  /** Shift+方向键扩选（按字素簇） */
  private extendSelection(dir: number): void {
    const head: number = dir < 0 ? GraphemeUtil.moveLeft(this.doc.text, this.selMgr.head) :
      GraphemeUtil.moveRight(this.doc.text, this.selMgr.head);
    this.selectTo(head);
  }

  private selectTo(head: number): void {
    this.selMgr.setSource(this.doc.text);
    this.selMgr.extendTo(head);
    this.doc.setSelection(this.selMgr.anchor, this.selMgr.head);
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines, this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    this.ensureCaretVisible(this.effectivePolicy());
    this.drawNow();
    this.reportSelection();
    this.emitSelection();
  }

  private clipboard(text: string): void {
    appClipboard = text;
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      board.setData(data).catch((e: BusinessError) => {
        this.diag('clipboard set failed: ' + e.code + ' ' + e.message);
      });
    } catch (e) {
      this.diag('clipboard set threw: ' + String(e));
    }
    this.diag('clipboard buffer len=' + text.length.toString());
  }

  private copySelection(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    if (!sel.isEmpty()) {
      this.clipboard(this.doc.text.substring(sel.startOffset, sel.endOffset));
    }
    this.hideSelectionMenu();
  }

  private cutSelection(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    if (sel.isEmpty()) {
      this.hideSelectionMenu();
      return;
    }
    this.clipboard(this.doc.text.substring(sel.startOffset, sel.endOffset));
    this.oldLines = this.lines;
    this.lastEditOffset = sel.startOffset;
    this.doc.delete(sel.startOffset, sel.endOffset);
    this.selMgr.collapse(sel.startOffset);
    this.previewMgr.cancel();
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
    this.emitSelection();
    this.hideSelectionMenu();
  }

  private pasteAtCaret(): void {
    const generation: number = this.documentGeneration;
    this.hideSelectionMenu();
    this.diag('paste action invoked buffer=' + appClipboard.length.toString());
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    board.getData().then((data: pasteboard.PasteData) => {
      if (generation !== this.documentGeneration) { return; }
      let text: string = '';
      try {
        const raw: string = data.getPrimaryText();
        if (raw !== undefined && raw !== null) {
          text = raw;
        }
      } catch (e0) {
        text = '';
      }
      // 纯文本为空时尝试 HTML（去标签），再回退到应用内缓冲
      if (text.length === 0) {
        try {
          const html: string = data.getPrimaryHtml();
          if (html !== undefined && html !== null && html.length > 0) {
            text = html.replace(new RegExp('<[^>]+>', 'g'), '');
          }
        } catch (e1) {
          text = '';
        }
      }
      if (text.length === 0) {
        text = appClipboard;
      }
      this.diag('paste resolved len=' + text.length.toString());
      if (text.length > 0) {
        this.insertAtCaret(text);
      }
    }).catch((e: BusinessError) => {
      if (generation !== this.documentGeneration) { return; }
      this.diag('paste sys failed, use buffer: ' + e.code);
      if (appClipboard.length > 0) {
        this.insertAtCaret(appClipboard);
      }
    });
  }

  /** 在光标处插入文本（粘贴用） */
  private insertAtCaret(text: string): void {
    // 与键入共用选区替换和预上屏提交，整次粘贴只产生一个编辑事务。
    this.insertExternalText(text);
  }

  private selectAllText(): void {
    this.selMgr.setSource(this.doc.text);
    this.selMgr.setSelection(0, this.doc.text.length);
    this.doc.setSelection(0, this.doc.text.length);
    this.emitSelection();
    this.drawNow();
    this.showSelectionMenu();
  }

  aboutToAppear(): void {
    this.pxPerVp = this.getUIContext().vp2px(1);
    if (this.pxPerVp <= 0) {
      this.pxPerVp = 1;
    }
    // 同步对外 @Prop 主题参数到内部 theme
    this.theme.fontSize = this.fontSize;
    this.theme.lineHeight = this.lineHeight;
    this.theme.lineSpacing = this.lineSpacing;
    this.theme.textColor = this.textColor;
    this.theme.backgroundColor = this.bgColor;
    this.theme.caretColor = this.caretColor;
    if (this.controller !== null) {
      this.controller.bind(this);
    }
    this.registerImeCallbacks();
  }

  aboutToDisappear(): void {
    this.documentGeneration++;
    this.cancelLongPress();
    if (this.controller !== null) { this.controller.unbind(this); }
    this.stopBlink();
    this.stopFling();
    this.ime.detach();
    if (this.caretAnimator !== null) {
      this.caretAnimator.stop();
    }
    if (this.glyphAnimator !== null) {
      this.glyphAnimator.stop();
    }
  }

  build() {
    Stack() {
      // Canvas 无获焦能力；tabStop 容器仍需要一个可获焦子节点。
      Text(' ').width(1).height(1).opacity(0).focusable(true)
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.initialized = true;
          this.ensureEngine();
          this.relayout();
          // 打开文稿即聚焦：组件此刻已上树，补发此前失败的焦点请求，让光标立即可见
          this.ensureInitFocus();
          this.diag('onReady viewW=' + this.viewWidthVp.toFixed(1) + ' viewH=' + this.viewHeightVp.toFixed(1) +
            ' renderer=' + (this.renderer !== null ? 'yes' : 'no') + ' lines=' + this.lines.length.toString());
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.windowX = Number(newValue.globalPosition.x);
          this.windowY = Number(newValue.globalPosition.y);
          this.viewWidthVp = Number(newValue.width);
          this.viewHeightVp = Number(newValue.height);
          if (this.initialized) {
            this.ensureEngine();
            this.clampScroll();
            this.relayout();
            this.ensureInitFocus();
          }
          this.diag('onAreaChange viewW=' + this.viewWidthVp.toFixed(1) + ' viewH=' + this.viewHeightVp.toFixed(1) +
            ' renderer=' + (this.renderer !== null ? 'yes' : 'no') + ' lines=' + this.lines.length.toString());
        })
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })
      if (this.menuVisible) {
        this.selectionMenu()
      }
    }
    // ===================== 焦点 / 按键 / IME：一律挂在容器上 =====================
    // tabStop 让焦点停在容器上，内部可获焦子节点使其进入框架焦点树。
    .id(CANVAS_EDITOR_ID)
    .focusable(true)
    .tabStop(true)
    .focusOnTouch(true)
    .onClick(() => {
      this.diag('container onClick -> requestEditorFocus');
      this.requestEditorFocus();
    })
    // 鼠标按下兜底：鼠标点击不派发 onTouch（onTouch 是触屏事件）
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Left && event.action === MouseAction.Press) {
        this.mouseSelecting = true;
        this.hideSelectionMenu();
        this.requestEditorFocus();
        const offset: number = this.offsetAt(event.x, event.y);
        this.moveCaretAnimated(offset);
        this.selMgr.beginDrag(offset);
      } else if (event.action === MouseAction.Move && this.mouseSelecting) {
        this.selMgr.updateDrag(this.offsetAt(event.x, event.y));
        this.emitSelection();
        this.drawNow();
      } else if (event.action === MouseAction.Release && this.mouseSelecting) {
        this.mouseSelecting = false;
        this.selMgr.endDrag();
        this.emitSelection();
      }
      if (event.action === MouseAction.Press) {
        // PC/2in1 右键：就近选词并弹出操作浮层（PC 一致性）
        if (event.button === MouseButton.Right) {
          const px: number = event.x;
          const py: number = event.y;
          this.requestEditorFocus();
          const sel: SelectionInfo = this.selMgr.selection;
          const off: number = this.offsetAt(px, py);
          if (sel.isEmpty() || off < sel.startOffset || off > sel.endOffset) {
            this.selectWordAt(px, py, 'rightClick');
          } else {
            this.showSelectionMenu();
          }
          this.diag('rightClick x=' + px.toFixed(1) + ',y=' + py.toFixed(1));
          return;
        }
        this.diag('container onMouse(Press) -> requestEditorFocus');
        this.requestEditorFocus();
      }
    })
    .onAxisEvent((event: AxisEvent) => {
      const delta: number = event.getVerticalAxisValue();
      if (delta !== 0) {
        this.stopFling();
        this.hideSelectionMenu();
        this.scrollY += delta;
        this.ensureVisibleLayout();
        this.clampScroll();
        this.drawNow();
        this.reportCursor();
      }
    })
    // 方向键必须走 onKeyPreIme：官方按键三次派发顺序为
    //   ① onKeyPreIme + 快捷键 → ② 输入法 → ③ 系统默认 Key（走焦）+ onKeyEvent
    // 编辑框获焦且启用输入法时，方向键会被输入法拿去"切换候选词"，
    // 故必须在 ① 阶段截下；而字母键必须放行给输入法（中文组字依赖 IME）。
    .onKeyPreIme((event: KeyEvent): boolean => {
      const handled: boolean = this.handleKeyPreIme(event);
      if (handled) {
        event.stopPropagation();
      }
      return handled;
    })
    .onKeyEvent((event: KeyEvent): boolean => {
      const handled: boolean = this.handleKeyEvent(event);
      if (handled) {
        event.stopPropagation();
      }
      return handled;
    })
    // 获焦：作为 focused / 光标可见性的权威来源，并补挂 IME（点击路径已挂，走焦路径兜底）
    .onFocus(() => {
      this.diag('container onFocus gained');
      this.focused = true;
      this.focusConfirmed = true;
      this.wantInitFocus = false;
      this.caret.visible = true;
      this.startBlink();
      this.drawNow();
      const softKeyboard: boolean = deviceInfo.deviceType !== '2in1';
      this.ime.attach(softKeyboard, inputMethod.TextInputType.TEXT,
        inputMethod.EnterKeyType.UNSPECIFIED).then(() => { this.reportSelection(); this.reportCursor(); });
    })
    // 失焦：释放状态，避免焦点已转走时物理键盘仍改写正文
    .onBlur(() => {
      this.diag('container onBlur -> releaseEditorFocus');
      this.releaseEditorFocus();
    })
    .width('100%')
    .height('100%')
  }

  /** ================= 对外方法（Controller 调用） ================= */

  loadText(text: string): void { this.loadDocument(text, [], text.length); }

  loadDocument(text: string, runs: FormatRun[], caret: number): void {
    this.documentGeneration++;
    this.preferredX = -1;
    this.doc.setTextWithCaret(text, caret);
    this.doc.setRuns(runs);
    if (this.cache !== null) { this.cache.setRuns(this.doc.runs); }
    this.lastText = text;
    // 选区管理器需同步参照全文，否则 IME/拖动给出的偏移不会被吸附到字符边界
    this.selMgr.setSource(text);
    this.selMgr.collapse(this.doc.caretOffset);
    this.previewMgr.cancel();
    this.anims.clear();
    this.scrollY = 0;
    this.relayout();
  }

  currentCaret(): number { return this.doc.caretOffset; }

  currentText(): string {
    return this.doc.text;
  }

  moveCaretTo(offset: number): void {
    this.preferredX = -1;
    this.moveCaretAnimated(offset);
  }

  /** 光标移动（连贯动画：px/vp 对齐后动画不再乱飞；不重排/不生成字形动画） */
  private moveCaretAnimated(offset: number): void {
    const from: CursorState = this.caret;
    this.doc.moveCaret(offset);
    this.selMgr.setSource(this.doc.text);
    this.selMgr.collapse(this.doc.caretOffset);
    this.ensureCaretLayout();
    const to: CursorState = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    this.diag('moveCaret offset=' + offset.toString() + ' from=(' + from.x.toFixed(1) + ',' + from.y.toFixed(1) +
      ') to=(' + to.x.toFixed(1) + ',' + to.y.toFixed(1) + ')');
    this.animateCaretMove(from, to);
    this.emitSelection();
    if (this.onCaretChange !== null) {
      this.onCaretChange(this.doc.caretOffset);
    }
  }

  insertExternalText(text: string): void {
    // 输入法切换语言会提交空文本；无组字状态时不应删除选区或产生编辑事务。
    // 空预上屏完成仍需替换原范围，保留组字流程的语义。
    if (text.length === 0 && !this.previewMgr.isComposing) { return; }
    if (this.previewMgr.isComposing) {
      const range: PreviewInfo = this.previewMgr.previewInfo;
      this.selMgr.setSelection(range.startOffset, range.endOffset);
      this.doc.setSelection(range.startOffset, range.endOffset);
    }
    this.oldLines = this.lines;
    // 有选区时先删除选区（输入即替换），避免在选区末尾追加
    const sel: SelectionInfo = this.selMgr.selection;
    if (!sel.isEmpty()) {
      this.lastEditOffset = sel.startOffset;
      this.doc.delete(sel.startOffset, sel.endOffset);
      this.selMgr.collapse(sel.startOffset);
    }
    // 插入点已在 doc.insert 内吸附到字符边界，此处取吸附后的实际位置作为失效起点
    const offset: number = GraphemeUtil.snapToBoundary(this.doc.text, this.doc.caretOffset);
    this.lastEditOffset = offset;
    this.doc.insert(offset, text);
    // 预上屏确认上屏（若有组合态）：消费组合态而非直接丢弃（T015）
    if (this.previewMgr.isComposing) {
      this.previewMgr.commit();
    } else {
      this.previewMgr.cancel();
    }
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
  }

  deleteExternalLeft(length: number): void {
    if (this.deletePreview(true, length)) { return; }
    // 有选区时删除整个选区（软键盘删除键），而不是逐个字符删
    if (this.deleteSelectionIfAny()) {
      return;
    }
    this.oldLines = this.lines;
    // 失效起点用字素簇回退，与 deleteLeft 的删除范围保持一致；
    // 若按码元算，emoji 前方的删除会导致失效位置落在字符内部，排版多算一行
    this.lastEditOffset = GraphemeUtil.moveLeft(this.doc.text, this.doc.caretOffset);
    this.doc.deleteLeft(length);
    this.previewMgr.cancel();
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
  }

  requestEditorFocus(): void {
    this.diag('requestEditorFocus ENTER focused(before)=' + this.focused.toString() +
      ' imeAttached=' + this.ime.attached.toString());
    this.focused = true;
    // 打开文稿的瞬间组件可能尚未上树，requestFocus 会失败；先记下"待聚焦"意图，
    // 待 onReady / onAreaChange（布局就绪）时由 ensureInitFocus 补发，保证"打开即见光标"。
    if (!this.focusConfirmed) {
      this.wantInitFocus = true;
    }
    // 关键：必须让组件在**框架层**真正获焦，否则 onKeyEvent 永不触发。
    // 仅置内部 focused 标志只够驱动光标闪烁与 IME，物理键盘事件收不到
    // —— 这正是"电脑上敲键盘没反应"的根因。
    this.grabFrameworkFocus();
    // PC（2in1）接物理键盘时不拉起系统软键盘：官方说明外接物理键盘会阻止
    // 软键盘弹出，此处仍显式传 false，避免某些桌面形态下多余地弹出输入栏。
    const softKeyboard: boolean = deviceInfo.deviceType !== '2in1';
    this.ime.attach(softKeyboard, inputMethod.TextInputType.TEXT, inputMethod.EnterKeyType.UNSPECIFIED).then(() => { this.reportSelection(); this.reportCursor(); });
    this.caret.visible = true;
    this.startBlink();
    this.drawNow();
  }

  /** 向框架请求焦点（按组件 id）；失败不阻断编辑，仅记日志 */
  private grabFrameworkFocus(): void {
    try {
      this.getUIContext().getFocusController().requestFocus(CANVAS_EDITOR_ID);
    } catch (e) {
      // 焦点未就绪（组件尚未上树）等情况下会抛错，属可恢复情形
      this.diag('requestFocus failed: ' + String(e));
    }
  }

  releaseEditorFocus(): void {
    this.previewMgr.cancel();
    this.previewDoc = null;
    this.previewCache = null;
    // 失焦即请求落库（T028）：切走/后台/关闭编辑面时不丢最后一次编辑
    if (this.onRequestSave !== null) {
      this.onRequestSave();
    }
    this.hideSelectionMenu();
    this.focused = false;
    this.focusConfirmed = false;
    this.wantInitFocus = false;
    this.ime.detach();
    this.stopBlink();
    this.caret.visible = false;
    this.drawNow();
  }

  /** 视觉参数变化：同步主题、重建引擎并重排（T030） */
  onThemeChanged(): void {
    if (!this.initialized) {
      return;
    }
    this.theme.fontSize = this.fontSize;
    this.theme.lineHeight = this.lineHeight;
    this.theme.lineSpacing = this.lineSpacing;
    this.theme.textColor = this.textColor;
    this.theme.backgroundColor = this.bgColor;
    this.theme.caretColor = this.caretColor;
    // 引擎按字号/行高构建，参数变化须重建（否则仍按旧字号排版）
    this.cache = null;
    this.renderer = null;
    this.ensureEngine();
    this.clampScroll();
    this.relayout();
  }

  /**
   * 布局就绪后补发一次焦点请求。
   * 打开文稿时父组件 aboutToAppear 先于画布上树，requestFocus 会失败且不再重试；
   * 这里在 onReady / onAreaChange 之后补一次，确保编辑器一打开就有焦点与可见光标。
   */
  private ensureInitFocus(): void {
    if (this.wantInitFocus && !this.focusConfirmed) {
      this.requestEditorFocus();
    }
  }

  /** ================= 内部实现 ================= */

  private registerImeCallbacks(): void {
    this.ime.onInsertText = (text: string): void => {
      this.insertExternalText(text);
    };
    this.ime.onDeleteLeft = (length: number): void => {
      this.deleteExternalLeft(length);
    };
    this.ime.onDeleteRight = (length: number): void => {
      if (this.deletePreview(false, length)) { return; }
      // 有选区时删除整个选区
      if (this.deleteSelectionIfAny()) {
        return;
      }
      this.oldLines = this.lines;
      // 删除区间从当前光标开始，起点已是合法边界
      this.lastEditOffset = this.doc.caretOffset;
      // 走文档的 deleteRight：按字素簇整簇删除，避免切碎 emoji
      this.doc.deleteRight(length);
      this.previewMgr.cancel();
      this.afterEdit();
      if (this.onTextChange !== null) {
        this.onTextChange(this.doc.text, this.doc.version);
      }
    };
    this.ime.onMoveCursor = (direction: inputMethod.Direction): void => {
      if (this.previewMgr.isComposing) { return; }
      const command: KeyboardEvent = new KeyboardEvent();
      if (direction === inputMethod.Direction.CURSOR_LEFT) { command.action = KeyAction.MOVE_LEFT; }
      else if (direction === inputMethod.Direction.CURSOR_RIGHT) { command.action = KeyAction.MOVE_RIGHT; }
      else if (direction === inputMethod.Direction.CURSOR_UP) { command.action = KeyAction.MOVE_UP; }
      else if (direction === inputMethod.Direction.CURSOR_DOWN) { command.action = KeyAction.MOVE_DOWN; }
      this.applyKeyCommand(command);
    };
    this.ime.onSelectByRange = (start: number, end: number): void => {
      this.selMgr.setSelection(start, end);
      this.emitSelection();
      this.drawNow();
    };
    // 软键盘回车：纯文本多行正文的默认语义为插入换行（此前未接线，导致无法回车换行）
    this.ime.onSendFunctionKey = (_enterKeyType: inputMethod.EnterKeyType): void => {
      if (this.previewMgr.isComposing) { this.insertExternalText(this.previewMgr.previewInfo.text); }
      this.insertExternalText('\n');
    };
    this.ime.onSendKeyboardStatus = (status: inputMethod.KeyboardStatus): void => {
      if (status === inputMethod.KeyboardStatus.SHOW) {
        this.caret.visible = true;
      } else if (status === inputMethod.KeyboardStatus.HIDE) {
        this.caret.visible = false;
      }
      this.drawNow();
    };
    this.ime.onPreviewText = (value: string, start: number, end: number): void => {
      const sel: SelectionInfo = this.selMgr.selection;
      if (this.previewMgr.update(value, start, end, sel.startOffset, sel.endOffset)) {
        this.refreshPreview();
        this.drawNow();
        this.reportSelection();
        this.reportCursor();
      }
    };
    this.ime.onPreviewFinish = (): void => {
      if (this.previewMgr.isComposing) { this.insertExternalText(this.previewMgr.previewInfo.text); }
    };
    this.ime.onGetTextLeft = (length: number): string => {
      const value: string = this.displayText();
      const at: number = this.displayCaret();
      return value.substring(Math.max(0, at - length), at);
    };
    this.ime.onGetTextRight = (length: number): string => {
      const value: string = this.displayText();
      const at: number = this.displayCaret();
      return value.substring(at, Math.min(value.length, at + length));
    };
    this.ime.onGetCursorIndex = (): number => this.displayCaret();
  }

  private displayText(): string {
    return this.previewMgr.isComposing && this.previewDoc !== null ? this.previewDoc.text : this.doc.text;
  }
  private deletePreview(backward: boolean, length: number): boolean {
    if (!this.previewMgr.isComposing) { return false; }
    const value: string = this.previewMgr.previewInfo.text;
    let at: number = value.length;
    if (backward) {
      for (let i: number = 0; i < length; i++) { at = GraphemeUtil.moveLeft(value, at); }
      this.previewMgr.update(value.substring(0, at), -1, -1);
      this.refreshPreview();
      this.drawNow();
      this.reportSelection();
      this.reportCursor();
    }
    return true;
  }
  private displayCaret(): number {
    return this.previewMgr.isComposing && this.previewDoc !== null ? this.previewDoc.caretOffset : this.doc.caretOffset;
  }
  private refreshPreview(): void {
    const info: PreviewInfo = this.previewMgr.previewInfo;
    const provisional: TextDocument = new TextDocument();
    provisional.setText(this.doc.text);
    provisional.setRuns(this.doc.runs);
    provisional.delete(info.startOffset, info.endOffset);
    provisional.insert(info.startOffset, info.text);
    this.previewDoc = provisional;
    if (this.engineRef !== null) {
      this.previewCache = new LayoutCache(this.engineRef);
      this.previewCache.setRuns(provisional.runs);
    }
  }

  // ================= 物理键盘（PC / 外接键盘） =================

  /**
   * 处理一次物理按键。
   * @return true 表示已消费该按键（调用方应停止冒泡，避免触发系统默认行为）
   */
  handleKeyEvent(event: KeyEvent): boolean {
    if (this.previewMgr.isComposing) { return false; }
    if (event === undefined || event === null) {
      return false;
    }
    this.diag('handleKeyEvent keyCode=' + event.keyCode.toString() + ' type=' + event.type.toString() +
      ' focused=' + this.focused.toString());
    const isDown: boolean = event.type === KeyType.Down;
    const mods: boolean[] = this.readModifiers(event);
    const cmd: KeyboardEvent = KeyboardHandler.translate(
      event.keyCode, event.keyText, isDown, mods[0], mods[1], mods[2]);
    if (cmd.action === KeyAction.NONE) {
      return false;
    }
    if (!this.focused) {
      // 未获焦时不抢输入（例如用户正在侧栏输入搜索词）
      return false;
    }
    this.applyKeyCommand(cmd);
    return true;
  }

  /**
   * onKeyPreIme 专用：只拦截"走位类"按键。
   *
   * 背景（官方）：按键三次派发为 ① onKeyPreIme + 快捷键 → ② 输入法 → ③ 系统默认 Key + onKeyEvent。
   * 编辑框获焦且启用输入法时，**方向键会被输入法拿去切换候选词**，所以必须在此阶段截下；
   * 但**字母键必须放行**——中文/拼音组字依赖输入法接收字母，若在此消费会直接破坏中文输入。
   *
   * @return true 表示该键已被消费（后续不再发给输入法与 onKeyEvent）
   */
  private handleKeyPreIme(event: KeyEvent): boolean {
    if (this.previewMgr.isComposing) { return false; }
    if (event === undefined || event === null) {
      return false;
    }
    const isDown: boolean = event.type === KeyType.Down;
    const mods: boolean[] = this.readModifiers(event);
    const cmd: KeyboardEvent = KeyboardHandler.translate(
      event.keyCode, event.keyText, isDown, mods[0], mods[1], mods[2]);
    if (!this.isNavigationAction(cmd.action)) {
      return false; // 非走位键（尤其是字母键）放行给输入法
    }
    if (!this.focused) {
      return false;
    }
    this.diag('preIme nav action=' + cmd.action.toString());
    this.applyKeyCommand(cmd);
    return true;
  }

  /** 走位类命令：上下左右 / 行首行尾 / 文首文尾 —— 这些被输入法占用后光标就动不了 */
  private isNavigationAction(action: KeyAction): boolean {
    return action === KeyAction.MOVE_LEFT || action === KeyAction.MOVE_RIGHT ||
      action === KeyAction.MOVE_UP || action === KeyAction.MOVE_DOWN ||
      action === KeyAction.MOVE_LINE_START || action === KeyAction.MOVE_LINE_END ||
      action === KeyAction.MOVE_DOC_START || action === KeyAction.MOVE_DOC_END;
  }

  /**
   * 读取 Ctrl / Shift / Alt 状态，返回 [ctrl, shift, alt]。
   *
   * 集中在此处而非散落三处调用，便于统一做异常兜底。
   *
   * 注意：getModifierKeyState 传入修饰键名数组、返回**单个 boolean**
   *（表示传入的键里是否有任一个按下），**不是**与入参等长的 boolean 数组 ——
   * 按数组声明会报 10505001 类型不匹配。故三个键分别查询。
   * 另做存在性判断：部分场景下该方法不可用，缺失时按"未按下"处理。
   */
  private readModifiers(event: KeyEvent): boolean[] {
    const out: boolean[] = [false, false, false];
    if (event.getModifierKeyState === undefined || event.getModifierKeyState === null) {
      return out;
    }
    const names: string[] = ['Ctrl', 'Shift', 'Alt'];
    for (let i: number = 0; i < names.length; i++) {
      try {
        const list: string[] = [names[i]];
        out[i] = event.getModifierKeyState(list) === true;
      } catch (e) {
        out[i] = false;
      }
    }
    return out;
  }

  /** 执行归一化后的编辑命令 */
  private applyKeyCommand(cmd: KeyboardEvent): void {
    if (cmd.action !== KeyAction.MOVE_UP && cmd.action !== KeyAction.MOVE_DOWN) { this.preferredX = -1; }
    const before: number = this.doc.caretOffset;
    const hadSelection: boolean = this.selMgr.selection.startOffset !== this.selMgr.selection.endOffset;

    switch (cmd.action) {
      case KeyAction.INSERT:
        this.insertExternalText(cmd.text);
        return;
      case KeyAction.DELETE_BACKWARD:
        this.deleteByKeyboard(before, hadSelection, true);
        return;
      case KeyAction.DELETE_FORWARD:
        this.deleteByKeyboard(before, hadSelection, false);
        return;
      case KeyAction.MOVE_LEFT:
        if (cmd.shift) {
          this.extendSelection(-1);
          return;
        }
        if (hadSelection) {
          // 有选区时左右键应收起选区到起点/终点，而不是再移动一格
          this.doc.moveCaret(this.selMgr.selection.startOffset);
        } else {
          this.doc.moveCaretByDirection(-1);
        }
        this.afterCaretMove();
        return;
      case KeyAction.MOVE_RIGHT:
        if (cmd.shift) {
          this.extendSelection(1);
          return;
        }
        if (hadSelection) {
          this.doc.moveCaret(this.selMgr.selection.endOffset);
        } else {
          this.doc.moveCaretByDirection(1);
        }
        this.afterCaretMove();
        return;
      case KeyAction.MOVE_UP:
      case KeyAction.MOVE_DOWN: {
        const lineIdx: number = HitTester.lineIndexOf(before, this.lines);
        if (lineIdx < 0) {
          return;
        }
        if (this.preferredX < 0) {
          this.preferredX = HitTester.offsetToX(this.lines[lineIdx], before, this.padLeftVp());
        }
        const targetLine: number = cmd.action === KeyAction.MOVE_UP ? lineIdx - 1 : lineIdx + 1;
        if (targetLine >= this.lines.length && this.cache !== null) {
          this.lines = this.cache.ensureLayout(this.doc.text, this.doc.version, this.doc.formatVersion,
            this.lines[lineIdx].yOffset + this.lines[lineIdx].step * 2);
        }
        if (targetLine < 0 || targetLine >= this.lines.length) {
          return;
        }
        const target: LayoutLine = this.lines[targetLine];
        const next: number = HitTester.hitTest(this.preferredX, this.padTopVp() + target.yOffset + target.height / 2,
          this.lines, this.padLeftVp(), this.padTopVp(), this.doc.text);
        if (cmd.shift) { this.selectTo(next); return; }
        this.doc.moveCaret(next);
        this.afterCaretMove();
        return;
      }
      case KeyAction.MOVE_LINE_START:
        if (cmd.shift) { this.selectTo(HitTester.lineStartOffset(this.lines, HitTester.lineIndexOf(before, this.lines))); return; }
        this.doc.moveCaret(HitTester.lineStartOffset(this.lines,
          HitTester.lineIndexOf(before, this.lines)));
        this.afterCaretMove();
        return;
      case KeyAction.MOVE_LINE_END:
        if (cmd.shift) { this.selectTo(HitTester.lineEndOffset(this.lines, HitTester.lineIndexOf(before, this.lines))); return; }
        this.doc.moveCaret(HitTester.lineEndOffset(this.lines,
          HitTester.lineIndexOf(before, this.lines)));
        this.afterCaretMove();
        return;
      case KeyAction.MOVE_DOC_START:
        if (cmd.shift) { this.selectTo(0); return; }
        this.doc.moveCaret(0);
        this.afterCaretMove();
        return;
      case KeyAction.MOVE_DOC_END:
        if (cmd.shift) { this.selectTo(this.doc.length); return; }
        this.doc.moveCaret(this.doc.length);
        this.afterCaretMove();
        return;
      case KeyAction.COPY:
        this.copySelection();
        return;
      case KeyAction.CUT:
        this.cutSelection();
        return;
      case KeyAction.PASTE:
        this.pasteAtCaret();
        return;
      case KeyAction.SELECT_ALL:
        this.selMgr.setSelection(0, this.doc.length);
        this.doc.setSelection(0, this.doc.length);
        this.drawNow();
        this.reportSelection();
        return;
      case KeyAction.UNDO:
        // 历史栈在 EditorStore，交给宿主处理
        if (this.onUndo !== null) {
          this.onUndo();
        }
        return;
      case KeyAction.REDO:
        if (this.onRedo !== null) {
          this.onRedo();
        }
        return;
      default:
        return;
    }
  }

  /** 键盘删除：有选区则删选区，否则按方向删一个字符 */
  private deleteByKeyboard(caret: number, hadSelection: boolean, backward: boolean): void {
    this.oldLines = this.lines;
    if (hadSelection) {
      const sel = this.selMgr.selection;
      this.lastEditOffset = sel.startOffset;
      this.doc.delete(sel.startOffset, sel.endOffset);
      this.selMgr.collapse(sel.startOffset);
    } else if (backward) {
      this.lastEditOffset = GraphemeUtil.moveLeft(this.doc.text, caret);
      this.doc.deleteLeft(1);
    } else {
      this.lastEditOffset = caret;
      this.doc.deleteRight(1);
    }
    this.previewMgr.cancel();
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
  }

  /** 光标移动后的收口：动画 + 上报 + 保证光标可见 */
  private afterCaretMove(): void {
    this.selMgr.collapse(this.doc.caretOffset);
    this.moveCaretAnimated(this.doc.caretOffset);
  }

  /** ================= 行内/段落格式命令（T023） ================= */

  /** 载入格式标注并重排 */
  setRuns(runs: FormatRun[]): void {
    this.doc.setRuns(runs);
    this.afterFormatChange(false);
  }

  /** 取当前格式标注 */
  getRuns(): FormatRun[] {
    return this.doc.runs;
  }

  /** 切换行内样式（粗/斜）于当前选区；无选区时作用于光标前一字 */
  toggleInlineStyle(kind: StyleKind): void {
    const sel: SelectionInfo = this.selMgr.selection;
    let s: number = sel.startOffset;
    let e: number = sel.endOffset;
    if (s === e) {
      s = GraphemeUtil.moveLeft(this.doc.text, this.doc.caretOffset);
      e = this.doc.caretOffset;
      if (s === e) {
        return;
      }
    }
    this.doc.toggleInline(kind, s, e);
    this.afterFormatChange();
  }

  /** 切换段落标题级别于当前选区/光标所在段 */
  toggleParagraphStyle(level: number): void {
    const sel: SelectionInfo = this.selMgr.selection;
    this.doc.toggleHeading(level, sel.startOffset, sel.endOffset);
    this.afterFormatChange();
  }

  /** 格式变化收口：整体失效重排 + 重绘 + 上抛（T023） */
  private afterFormatChange(notify: boolean = true): void {
    if (this.cache !== null) {
      // 必须把最新格式标注交给排版引擎：normalizeRuns 会替换 runsValue 数组，
      // 若不同步，引擎将一直沿用建引擎时的旧样式（标题/撤销重做都不会生效）
      this.cache.setRuns(this.doc.runs);
      this.cache.invalidate();
    }
    this.relayout();
    if (notify && this.onEdit !== null) {
      this.onEdit(this.doc.text, this.doc.runs, this.doc.caretOffset);
    }
    if (notify && this.onFormatChange !== null) {
      this.onFormatChange(this.doc.runs);
    }
  }

  private ensureEngine(): void {
    if (this.cache !== null && this.renderer !== null && this.viewWidthVp === this.engineWidth) {
      return;
    }
    if (this.viewWidthVp <= 0) {
      return;
    }
    const contentWidthVp: number = Math.max(1,
      this.viewWidthVp - this.theme.paddingLeft - this.theme.paddingRight);
    this.engineWidth = this.viewWidthVp;
    if (this.caretAnimator !== null) { this.caretAnimator.stop(); }
    if (this.glyphAnimator !== null) { this.glyphAnimator.stop(); }
    // 引擎接收 vp 尺寸 + pxPerVp，内部换算 px 排版，输出 vp
    const engine = new TextLayoutEngine(contentWidthVp,
      this.theme.fontSize,
      this.theme.lineHeight,
      this.theme.lineSpacing,
      this.pxPerVp);
    this.cache = new LayoutCache(engine);
    engine.setRuns(this.doc.runs);
    this.engineRef = engine;

    const rtp = new RenderTheme();
    rtp.paddingLeftVp = this.theme.paddingLeft;
    rtp.paddingTopVp = this.theme.paddingTop;
    rtp.fontSizeVp = this.theme.fontSize;
    rtp.lineHeightVp = this.theme.lineHeight;
    rtp.textColor = parseColor(this.theme.textColor);
    rtp.caretColor = parseColor(this.caretColor);
    rtp.selectionColor = parseColor(this.theme.selectionColor);
    rtp.backgroundColor = parseColor(this.theme.backgroundColor);
    rtp.previewColor = parseColor(this.theme.previewColor);
    rtp.caretWidthVp = this.theme.caretWidth;
    rtp.pxPerVp = this.pxPerVp;
    this.renderer = new GlyphRenderer(rtp);
    this.caretAnimator = new EditorAnimator(this.getUIContext());
    this.glyphAnimator = new EditorAnimator(this.getUIContext());
  }

  private padLeftVp(): number {
    return this.theme.paddingLeft;
  }

  private padTopVp(): number {
    return this.theme.paddingTop;
  }

  private contentHeight(): number {
    if (this.cache === null) {
      return 0;
    }
    const base: number = this.cache.height;
    if (this.cache.isComplete()) {
      return base;
    }
    const lineCount: number = this.cache.lineCount();
    const layoutedChars: number = lineCount > 0 ? this.lines[lineCount - 1].endIndex : 0;
    const avgChars: number = lineCount > 0 ? Math.max(1, layoutedChars / lineCount) : 16;
    const remaining: number = Math.max(0, this.doc.length - layoutedChars);
    const estLines: number = remaining / avgChars;
    const lineStep: number = this.theme.lineHeight + this.theme.lineSpacing;
    return base + estLines * lineStep;
  }

  /** 惰性排版至可视区底部 */
  private ensureVisibleLayout(): void {
    if (this.cache === null) {
      return;
    }
    const untilY: number = this.scrollY + this.viewHeightVp;
    if (this.previewMgr.isComposing && this.previewDoc !== null && this.previewCache !== null) {
      const provisional: TextDocument = this.previewDoc;
      this.previewCache.setRuns(provisional.runs);
      this.lines = this.previewCache.ensureLayout(provisional.text, provisional.version, provisional.formatVersion, untilY);
      this.lines = this.previewCache.ensureOffset(provisional.text, provisional.version, provisional.formatVersion, provisional.caretOffset);
      this.caret = HitTester.caretPositionFor(provisional.caretOffset, this.lines, this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
      return;
    }
    this.cache.setRuns(this.doc.runs);
    this.lines = this.cache.ensureLayout(this.doc.text, this.doc.version, this.doc.formatVersion, untilY);
  }

  private ensureCaretLayout(): void {
    if (this.cache !== null) {
      this.lines = this.cache.ensureOffset(this.doc.text, this.doc.version, this.doc.formatVersion, this.doc.caretOffset);
    }
  }

  /** 重新排版并立即绘制 */
  private relayout(): void {
    if (this.cache === null || this.renderer === null) {
      return;
    }
    const perfT0: number = Date.now();
    this.ensureVisibleLayout();
    this.ensureCaretLayout();
    let lm: string = 'pxPerVp=' + this.pxPerVp.toFixed(3) + ' lines=' + this.lines.length.toString();
    for (let i = 0; i < this.lines.length && i < 3; i++) {
      const l = this.lines[i];
      lm += (' | y=' + l.yOffset.toFixed(1) + ' h=' + l.height.toFixed(1) +
        ' step=' + l.step.toFixed(1) + ' base=' + l.baseline.toFixed(1) +
        ' w=' + l.width.toFixed(1) + ' end=' + l.endIndex.toString());
    }
    this.diag(lm);
    this.anims.clear();
    if (!this.caretAnimating) {
      // 键盘弹起/视口变化等引起的 relayout 不应硬编码打断正在播放的光标动画
      this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
        this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    }
    this.ensureCaretVisible(this.effectivePolicy());
    this.drawNow();
    this.reportCursor();
    // 性能诊断（T036）：Phase 5 真机据此核对 5 万字下重排耗时
    this.diag('perf relayout=' + (Date.now() - perfT0).toString() + 'ms lines=' +
      this.lines.length.toString() + ' len=' + this.doc.length.toString());
  }

  /** 编辑后：失效重排 + 字形动画 + 光标平滑移动动画 */
  private afterEdit(): void {
    this.preferredX = -1;
    const previousText: string = this.lastText;
    this.lastText = this.doc.text;
    this.selMgr.setSource(this.doc.text);
    this.selMgr.collapse(this.doc.caretOffset);
    if (this.onEdit !== null) { this.onEdit(this.doc.text, this.doc.runs, this.doc.caretOffset); }
    if (this.onCaretChange !== null) { this.onCaretChange(this.doc.caretOffset); }
    if (this.cache === null || this.renderer === null) {
      return;
    }
    // 编辑发生后选区语义已变，收起操作浮层
    this.hideSelectionMenu();
    // 正文已变，长度与内容都变了：同步选区管理器的参照文本，
    // 否则它会按旧长度钳制选区，产生越界或切碎字符
    this.selMgr.setSource(this.doc.text);
    this.cache.applyEdit(this.doc.text, this.doc.version, this.doc.formatVersion, this.doc.runs, this.lastEditOffset);
    this.ensureVisibleLayout();
    this.ensureCaretLayout();
    // 字符级动画：对比编辑前后字形（入场/消退/换行滑动），再驱动播放（T010/T011）
    // 差分只在 lastEditOffset 附近的窗口内进行：整篇建两份字形 Map 是"越写越卡"的主因，
    // 而真正需要过渡的字形上限只有 80 + 24 个。
    const diff: GlyphDiffOptions = new GlyphDiffOptions();
    diff.paddingLeftPx = this.padLeftVp();
    diff.paddingTopPx = this.padTopVp();
    diff.rowThresholdVp = this.theme.lineHeight * 0.5;
    diff.oldText = previousText;
    diff.newText = this.doc.text;
    diff.hintOffset = this.lastEditOffset;
    this.anims = GlyphAnimator.createEditAnimations(this.oldLines, this.lines, diff);
    this.lastText = this.doc.text;
    this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    this.ensureCaretVisible(this.effectivePolicy());
    this.runGlyphAnimation();
    this.reportCursor();
  }

  /** 光标移动弹簧动画 */
  private animateCaretMove(from: CursorState, to: CursorState): void {
    if (this.caretAnimator === null) {
      this.settleCaret(to);
      return;
    }
    // 以光标"当前实际位置"为起跳点（from 即调用方传入的 this.caret 当前值），
    // 保证连续点击/移动时路径连续无跳变；过冲交由 applyClampedCaret 钳制，防止越过目标行/字符。
    const startFrom: CursorState = from.clone();
    // 移动过程中光标保持全程可见，到位后再闪烁（blink 由 startBlink 中 !caretAnimating 守卫）
    this.caret.visible = true;
    this.caretAnimating = true;
    // 按距离选择弹簧参数档（spring 灵动 + 远慢近快；interpolating-spring 忽略 duration）
    const distVp: number = this.caretDistanceVp(startFrom, to);
    const curve: string = AnimationSpec.caretCurveForDistance(distVp);
    this.diag('caretAnim from=(' + startFrom.x.toFixed(1) + ',' + startFrom.y.toFixed(1) + ')' +
      ' to=(' + to.x.toFixed(1) + ',' + to.y.toFixed(1) + ')' + ' dist=' + distVp.toFixed(1) +
      ' curve=' + curve);
    this.caretAnimator.animate(AnimationSpec.caretNominalMs, curve,
      (p: number) => {
        this.applyClampedCaret(startFrom, to, p);
        this.drawNow();
      },
      () => {
        this.settleCaret(to);
      });
  }

  /** 光标位移（vp，欧氏距离） */
  private caretDistanceVp(from: CursorState, to: CursorState): number {
    const dx: number = to.x - from.x;
    const dy: number = to.y - from.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  /** 将光标落定到目标位置并上报 */
  private settleCaret(to: CursorState): void {
    this.caretAnimating = false;
    this.caret.x = to.x;
    this.caret.y = to.y;
    this.caret.height = to.height;
    this.ensureCaretVisible(this.effectivePolicy());
    this.drawNow();
    this.reportCursor();
  }

  /** 对光标插值结果做位置钳制（保留轻微弹性，避免越过目标行/字符） */
  private applyClampedCaret(from: CursorState, to: CursorState, p: number): void {
    if (p > 1.05) {
      this.diag('caret spring overshoot p=' + p.toFixed(3));
    }
    const rawX: number = EditorAnimator.lerp(from.x, to.x, p);
    const rawY: number = EditorAnimator.lerp(from.y, to.y, p);
    const rawH: number = EditorAnimator.lerp(from.height, to.height, p);
    // 弹性余量：纵向约 1/4 行高、横向约 0.6 字符宽（以目标行高近似字符宽），其余钳制在区间内
    const charW: number = Math.max(1, to.height * 0.6);
    const epsY: number = Math.max(1, to.height * 0.25);
    this.caret.x = this.clampNum(rawX, Math.min(from.x, to.x) - charW, Math.max(from.x, to.x) + charW);
    this.caret.y = this.clampNum(rawY, Math.min(from.y, to.y) - epsY, Math.max(from.y, to.y) + epsY);
    this.caret.height = this.clampNum(rawH, Math.min(from.height, to.height), Math.max(from.height, to.height));
    if (p > 1.05) {
      this.diag('  caret@p=' + p.toFixed(3) + ' x=' + this.caret.x.toFixed(1) + ' y=' + this.caret.y.toFixed(1) +
        ' (to x=' + to.x.toFixed(1) + ' y=' + to.y.toFixed(1) + ')');
    }
  }

  private clampNum(v: number, lo: number, hi: number): number {
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }

  /** 运行时诊断日志（仅 DIAG_ENABLED 时输出，避免生产噪音） */
  private diag(msg: string): void {
    if (DIAG_ENABLED) {
      console.info(DIAG_TAG + ' ' + msg);
    }
  }

  /** 字形动画驱动（让位/入场/退场插值） */
  private runGlyphAnimation(): void {
    if (this.anims.isEmpty()) {
      this.drawNow();
      return;
    }
    if (this.glyphAnimator === null) {
      this.anims.clear();
      this.drawNow();
      return;
    }
    this.glyphAnimator.animate(AnimationSpec.glyphAnimDurationMs, AnimationSpec.glyphEnter(),
      (p: number) => {
        this.anims.map.forEach((st: GlyphAnimState, offset: number) => {
          st.progress = p;
        });
        for (let i: number = 0; i < this.anims.exits.length; i++) { this.anims.exits[i].progress = p; }
        this.drawNow();
      },
      () => {
        this.anims.clear();
        this.drawNow();
      });
  }

  /** 全量重绘 */
  private drawNow(): void {
    if (this.renderer === null) {
      this.diag('drawNow renderer=null (skip)');
      return;
    }
    this.ensureVisibleLayout();
    if (this.lines.length === 0) {
      this.diag('drawNow lines=0 doc.len=' + this.doc.length.toString() +
        ' cache.lines=' + (this.cache !== null ? this.cache.lineCount().toString() : '-') +
        ' scrollY=' + this.scrollY.toFixed(1) + ' viewH=' + this.viewHeightVp.toFixed(1));
    }
    const viewport = new ViewportInfo(this.scrollY, this.viewHeightVp);
    const preview: PreviewInfo | null = this.previewMgr.isComposing ? this.previewMgr.previewInfo : null;
    this.renderer.draw(this.ctx, this.lines, this.caret,
      preview === null ? this.selMgr.selection : null, null, viewport, this.anims, this.handlePositions());
  }

  /** 选区两端的把手位置（内容坐标；无选区返回空） */
  private handlePositions(): CursorState[] {
    const sel: SelectionInfo = this.selMgr.selection;
    if (sel.isEmpty()) {
      return [];
    }
    const a: CursorState = HitTester.caretPositionFor(sel.startOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    const b: CursorState = HitTester.caretPositionFor(sel.endOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    return [a, b];
  }

  /** 命中检测：视口坐标是否落在某个选区手柄上（返回 1 起点 / 2 终点 / 0 无） */
  private handleAt(x: number, y: number): number {
    const positions: CursorState[] = this.handlePositions();
    if (positions.length === 0) {
      return 0;
    }
    const rVp: number = 14; // 命中半径（略大于视觉半径，便于手指操作）
    for (let i = 0; i < positions.length; i++) {
      const h: CursorState = positions[i];
      const hx: number = h.x;
      const hy: number = this.theme.paddingTop + h.y + h.height - this.scrollY + 5;
      const dx: number = x - hx;
      const dy: number = y - hy;
      if (dx * dx + dy * dy <= rVp * rVp) {
        return i === 0 ? 1 : 2;
      }
    }
    return 0;
  }

  /** 上抛选区变化（供工具栏态；无外部监听则忽略） */
  private emitSelection(): void {
    const active: SelectionInfo = this.selMgr.selection;
    if (active.isEmpty()) { this.doc.moveCaret(active.startOffset); }
    else { this.doc.setSelection(this.selMgr.anchor, this.selMgr.head); }
    if (this.onCaretChange !== null) { this.onCaretChange(this.doc.caretOffset); }
    if (this.onSelectionChange !== null) {
      const sel: SelectionInfo = this.selMgr.selection;
      this.onSelectionChange(sel.startOffset, sel.endOffset);
    }
    // 同步选区给输入法：否则软键盘删除只会按字符删，不会删整个选区
    this.reportSelection();
  }

  /** 有选区则删除整个选区（IME 删除键 / 输入覆盖共用）；返回是否已处理 */
  private deleteSelectionIfAny(): boolean {
    const sel: SelectionInfo = this.selMgr.selection;
    if (sel.isEmpty()) {
      return false;
    }
    this.oldLines = this.lines;
    this.lastEditOffset = sel.startOffset;
    this.doc.delete(sel.startOffset, sel.endOffset);
    this.selMgr.collapse(sel.startOffset);
    this.previewMgr.cancel();
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
    this.emitSelection();
    return true;
  }

  /** 光标变化后上报输入法（IME CursorInfo 单位要求 px，此处 vp→px）
   *   光标 top 采用组件内可视 y（padTop + 内容 y - scrollY，并 clamp ≥0），
   *   避免仅上报内容 y 造成键盘悬浮偏移；完整窗口绝对位置需组件在窗口中的坐标（后续扩展）。
   *   left 与绘制一致：以边界为中线居中（边界 - 半宽），保证 IME 悬浮元素与可视光标对齐。 */
  private reportCursor(): void {
    if (!this.ime.attached) {
      return;
    }
    const topVp: number = Math.max(0, this.theme.paddingTop + this.caret.y - this.scrollY);
    const caretW: number = this.theme.caretWidth * this.pxPerVp;
    this.ime.updateCursor((this.windowX + this.caret.x) * this.pxPerVp - caretW / 2,
      (this.windowY + topVp) * this.pxPerVp, caretW, this.caret.height * this.pxPerVp);
  }

  /** 选区变化后上报输入法（键盘选区、输入法联动需要） */
  private reportSelection(): void {
    if (!this.ime.attached) {
      return;
    }
    const sel = this.selMgr.selection;
    if (this.previewMgr.isComposing) {
      const at: number = this.displayCaret();
      this.ime.changeSelection(this.displayText(), at, at);
    } else { this.ime.changeSelection(this.doc.text, sel.startOffset, sel.endOffset); }
  }

  /** 触摸：点按定位光标 / 水平拖动选区 / 垂直拖动滚动 */
  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return;
    }
    // 触摸事件坐标与内部坐标统一为 vp
    const x: number = event.touches[0].x;
    const y: number = event.touches[0].y;
    if (event.type === TouchType.Down) {
      this.pressX = x;
      this.pressY = y;
      this.dragging = false;
      this.scrollMode = false;
      this.pressScrollY = this.scrollY;
      this.stopFling();
      this.scrollVel = 0;
      this.lastScrollY = this.scrollY;
      this.lastScrollAt = Date.now();
      this.hideSelectionMenu();
      this.diag('DOWN touch=(vp)' + x.toFixed(1) + ',' + y.toFixed(1) + ' scrollY=' + this.scrollY.toFixed(1));
      this.diag('onTouch(DOWN) -> requestEditorFocus');
      this.requestEditorFocus();
      // 先判定是否落在选区手柄上（T018）：是则进入手柄拖动，否则进入点按/长按
      const handle: number = this.handleAt(x, y);
      if (handle !== 0) {
        this.selMgr.beginHandleDrag(handle);
        this.dragging = true;
        this.scrollMode = false;
        this.cancelLongPress();
        this.diag('handleDrag begin which=' + handle.toString());
      } else {
        this.startLongPress(x, y);
      }
    } else if (event.type === TouchType.Move) {
      const dx: number = x - this.pressX;
      const dy: number = y - this.pressY;
      if (!this.dragging) {
        if (EditorGesture.isDrag(this.pressX, this.pressY, x, y)) {
          this.cancelLongPress();
          this.dragging = true;
          this.scrollMode = Math.abs(dy) > Math.abs(dx);
          if (this.scrollMode) {
            // 滚动即收起软键盘，腾出阅读空间（点击后重新拉起）
            if (!this.keyboardSuppressed) {
              this.keyboardSuppressed = true;
              this.ime.hideKeyboard();
            }
          } else {
            const offset: number = this.offsetAt(this.pressX, this.pressY);
            this.selMgr.beginDrag(offset);
          }
        }
      }
      if (this.dragging && this.selMgr.draggingHandle !== 0) {
        const offH: number = this.offsetAt(x, y);
        this.selMgr.updateHandleDrag(offH);
        // 手柄拖到视口上下边缘时自动滚动
        const edge: number = 40;
        if (y < edge) {
          this.scrollY -= this.theme.lineHeight;
          this.clampScroll();
          this.ensureVisibleLayout();
        } else if (y > this.viewHeightVp - edge) {
          this.scrollY += this.theme.lineHeight;
          this.clampScroll();
          this.ensureVisibleLayout();
        }
        this.emitSelection();
        this.showSelectionMenu();
        this.drawNow();
      } else if (this.dragging && this.scrollMode) {
        this.scrollY = this.pressScrollY - dy;
        this.clampScroll();
        // 记录滚动速度（vp/ms），供抬起后的惯性滑动
        const nowMs: number = Date.now();
        const dtMs: number = nowMs - this.lastScrollAt;
        if (dtMs > 0) {
          this.scrollVel = (this.scrollY - this.lastScrollY) / dtMs;
        }
        this.lastScrollY = this.scrollY;
        this.lastScrollAt = nowMs;
        // 滚动时收起浮层
        this.hideSelectionMenu();
        // 上报滚动方向（T032）：手指上滑(dy<0)=向下浏览内容 → 1；反之 -1
        if (this.onScrollState !== null) {
          this.onScrollState(dy < 0 ? 1 : -1);
        }
        this.drawNow();
      } else if (this.dragging) {
        const off: number = this.offsetAt(x, y);
        this.selMgr.updateDrag(off);
        this.emitSelection();
        this.showSelectionMenu();
        this.drawNow();
      }
    } else if (event.type === TouchType.Up) {
      const wasScroll: boolean = this.scrollMode;
      // 兜底：部分场景 Down 事件被系统消费，Up 时确保已 attach 输入法
      this.cancelLongPress();
      this.requestEditorFocus();
      if (!this.dragging && !this.longPressed) {
        // 用 Down（手指按下）坐标定位，而非 Up（抬起）坐标：真机上手指抬起位置常比按下位置偏左上，
        // 用 Up 会导致光标偏离真实点击位置（上偏/左偏）。
        const offset: number = this.offsetAt(this.pressX, this.pressY);
        const now: number = Date.now();
        const near: boolean = (now - this.lastTapAt) <= this.DOUBLE_TAP_MS;
        this.tapStreak = near ? (this.tapStreak + 1) : 1;
        this.lastTapAt = now;
        if (this.tapStreak >= 3) {
          // 三击选段
          this.tapStreak = 0;
          this.diag('tripleTap x=' + this.pressX.toFixed(1) + ',y=' + this.pressY.toFixed(1));
          this.selectParagraphAt(this.pressX, this.pressY);
          this.longPressed = true;
        } else if (this.tapStreak === 2) {
          // 双击选词（与长按一致）并弹出操作浮层
          this.diag('doubleTap x=' + this.pressX.toFixed(1) + ',y=' + this.pressY.toFixed(1));
          this.selectWordAt(this.pressX, this.pressY, 'doubleTap');
          this.longPressed = true; // 抑制随后的收起判断（结尾按"选区非空"弹层）
        } else {
          this.selMgr.collapse(offset);
          this.emitSelection();
          this.diag('UP tap(hold x=' + this.pressX.toFixed(1) + ',y=' + this.pressY.toFixed(1) + ') offset=' + offset +
            ' lines=' + this.lines.length.toString());
          this.moveCaretAnimated(offset);
        }
      }
      this.longPressed = false;
      this.selMgr.endHandleDrag();
      this.selMgr.endDrag();
      this.emitSelection();
      // 滚动结束（T032）
      if (this.onScrollState !== null) {
        this.onScrollState(0);
      }
      if (this.scrollMode) {
        this.startFling();
      }
      this.dragging = false;
      this.scrollMode = false;
      // 非滚动的一次点按：若此前因滚动收起了键盘，则重新拉起
      if (!wasScroll && this.keyboardSuppressed) {
        this.keyboardSuppressed = false;
        this.ime.showKeyboard();
      }
      // 选区仍在（长按/手柄拖动后）→ 重新弹出操作浮层；否则收起
      if (!this.selMgr.selection.isEmpty()) {
        this.showSelectionMenu();
      } else {
        this.hideSelectionMenu();
      }
    }
  }

  /** 视口坐标 → 字符偏移（考虑滚动；结果已吸附到字符边界） */
  private offsetAt(x: number, y: number): number {
    return HitTester.hitTest(x, y + this.scrollY, this.lines,
      this.padLeftVp(), this.padTopVp(), this.doc.text);
  }

  /** 长按：启动定时器（按住 450ms 未拖动 → 分词选中） */
  private startLongPress(x: number, y: number): void {
    this.cancelLongPress();
    this.longPressTimer = setTimeout(() => {
      this.longPressTimer = -1;
      this.handleLongPress(x, y);
    }, this.LONG_PRESS_MS);
  }

  private cancelLongPress(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  /** 长按分词选中：展开到词边界（CJK/字母/数字连续段） */
  private handleLongPress(x: number, y: number): void {
    this.longPressed = true;
    this.selectWordAt(x, y, 'longPress');
  }

  /** 在 (x,y) 处按词选中（长按 / 双击共用）并弹出操作浮层 */
  private selectWordAt(x: number, y: number, source: string): void {
    const offset: number = this.offsetAt(x, y);
    const text: string = this.doc.text;
    let start: number = -1;
    let end: number = -1;
    // 优先用 ICU 词边界（getWordBoundary），与 Android/iOS/Pure Writer 双击选词一致
    if (this.engineRef !== null) {
      const r: number[] = this.engineRef.wordRangeAt(text, offset);
      if (r.length === 2 && r[1] > r[0]) {
        start = r[0];
        end = r[1];
      }
    }
    if (start < 0) {
      // 回退（无分词能力时）：按 CJK/字母/数字连续段
      start = offset;
      while (start > 0 && this.isWordChar(text.charCodeAt(start - 1))) {
        start--;
      }
      end = offset;
      while (end < text.length && this.isWordChar(text.charCodeAt(end))) {
        end++;
      }
      if (start === end && offset < text.length) {
        end = offset + 1; // 未命中"词字符"（如标点），退化为选中一个字
      }
    }
    this.selMgr.setSource(text);
    this.selMgr.setSelection(start, end);
    this.doc.setSelection(start, end);
    this.caret = HitTester.caretPositionFor(end, this.lines, this.padLeftVp(), this.padTopVp(), this.theme.fontSize);
    this.diag(source + ' offset=' + offset.toString() + ' sel=' + start.toString() + '-' + end.toString());
    this.emitSelection();
    this.showSelectionMenu();
    this.drawNow();
    this.reportCursor();
  }

  /** 词字符判定（CJK 汉字 / 字母 / 数字；排除空格与标点） */
  private isWordChar(code: number): boolean {
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true; // CJK 统一汉字
    }
    if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
      return true; // A-Z a-z
    }
    if (code >= 0x30 && code <= 0x39) {
      return true; // 0-9
    }
    return false;
  }

  /** 打字机居中所需的尾部留白：允许最后一行滚动到视口中心（T008） */
  private tailPadVp(): number {
    return this.effectivePolicy() === ScrollPolicy.CENTER ? this.viewHeightVp / 2 : 0;
  }

  /** 最大滚动量：CENTER 策略下额外允许半屏尾部留白，使末行可居中 */
  private maxScrollVp(): number {
    return Math.max(0, this.contentHeight() + this.tailPadVp() - this.viewHeightVp);
  }

  private clampScroll(): void {
    const maxScroll: number = this.maxScrollVp();
    if (this.scrollY > maxScroll) {
      this.scrollY = maxScroll;
    }
    if (this.scrollY < 0) {
      this.scrollY = 0;
    }
  }

  /** 停止惯性滑动 */
  private stopFling(): void {
    if (this.flingTimer !== -1) {
      clearInterval(this.flingTimer);
      this.flingTimer = -1;
    }
  }

  /** 抬起后的惯性滑动：按速度指数衰减，逐帧推进滚动，到边界/减速即停 */
  private startFling(): void {
    this.stopFling();
    let v: number = this.scrollVel * this.FLING_VEL_FACTOR; // 每帧(≈16ms)位移（vp）
    if (Math.abs(v) < 1) {
      return;
    }
    this.flingTimer = setInterval(() => {
      v *= this.FLING_FRICTION; // 摩擦衰减（越接近 1 滑得越远、越顺）
      const before: number = this.scrollY;
      this.scrollY += v;
      this.clampScroll();
      this.drawNow();
      // 触边界（被 clamp 截住）或速度过小 → 停止
      if (Math.abs(v) < 0.3 || this.scrollY !== before + v) {
        this.stopFling();
      }
    }, 16);
  }

  /** 生效滚动策略：打字机开启即 CENTER，否则用外部传入的 scrollPolicy */
  private effectivePolicy(): ScrollPolicy {
    return this.typewriter ? ScrollPolicy.CENTER : this.scrollPolicy;
  }

  /**
   * 使光标在当前视口内可见（T007）；policy=CENTER 时使当前行居中（T008，打字机）。
   * 坐标系：scrollY 为内容顶部偏移（vp），caret.y 为内容坐标（vp）。
   */
  private ensureCaretVisible(policy: ScrollPolicy): void {
    if (this.viewHeightVp <= 0) {
      return;
    }
    const caretH: number = Math.max(1, this.caret.height);
    const caretTop: number = this.caret.y;
    const caretBottom: number = caretTop + caretH;
    let target: number = this.scrollY;
    if (policy === ScrollPolicy.CENTER) {
      // 当前行中心对齐视口中心
      target = caretTop - (this.viewHeightVp - caretH) / 2;
    } else {
      const margin: number = Math.max(1, this.theme.lineHeight);
      if (caretTop < this.scrollY + margin) {
        target = caretTop - margin;
      } else if (caretBottom > this.scrollY + this.viewHeightVp - margin) {
        target = caretBottom - this.viewHeightVp + margin;
      }
    }
    const maxScroll: number = this.maxScrollVp();
    if (target < 0) {
      target = 0;
    }
    if (target > maxScroll) {
      target = maxScroll;
    }
    if (Math.abs(target - this.scrollY) > 0.5) {
      this.scrollY = target;
      this.diag('scroll policy=' + (policy === ScrollPolicy.CENTER ? 'CENTER' : 'NORMAL') +
        ' caretY=' + caretTop.toFixed(1) + ' scrollY=' + this.scrollY.toFixed(1) +
        ' max=' + maxScroll.toFixed(1));
      this.ensureVisibleLayout();
    }
  }

  private startBlink(): void {
    this.stopBlink();
    this.blinkTimer = setInterval(() => {
      // 光标移动（动画）过程中保持全程可见，到位（caretAnimating=false）后再闪烁
      if (this.focused && !this.caretAnimating) {
        this.caret.visible = !this.caret.visible;
        this.drawNow();
      }
    }, this.theme.caretBlinkDuration);
  }

  private stopBlink(): void {
    if (this.blinkTimer >= 0) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
  }
}
