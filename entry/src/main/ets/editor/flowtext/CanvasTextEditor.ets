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
import { pointer } from '@kit.InputKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { common2D } from '@kit.ArkGraphics2D';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { TextDocument } from './model/TextDocument';
import { GraphemeUtil } from './model/GraphemeUtil';
import { SelectionInfo, PreviewInfo, ViewportInfo, ScrollPolicy, StyleKind, FormatRun, CaretAffinity } from './model/EditorTypes';
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
import { EditCommand, EditCommandKind, EditorInputSource, EditorModifiers } from '../interaction/EditCommand';
import { resolveShortcut } from '../interaction/ShortcutMap';
import { EditorCommandRouter, EditCommandHost } from '../interaction/EditorCommandRouter';
import { ImeEchoGuard, shouldConsumePreIme } from '../interaction/InputArbiter';
import { deviceProfile } from '../../utils/DeviceProfile';

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

/**
 * 重建引擎/重排前的阅读锚点：用"光标在视口中的屏幕 y"而不是 scrollY 直接继承。
 * 宽度/字号/行高变化会改变行坐标，若继续沿用旧 scrollY，用户会看到内容整体跳动。
 */
class ViewAnchor {
  caretOffset: number = 0;
  caretScreenY: number = 0;
  caretHeight: number = 0;
  valid: boolean = false;

  constructor(caretOffset: number = 0, caretScreenY: number = 0, caretHeight: number = 0,
    valid: boolean = false) {
    this.caretOffset = caretOffset;
    this.caretScreenY = caretScreenY;
    this.caretHeight = caretHeight;
    this.valid = valid;
  }
}

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
  /** 待处理的打字机开关：绑定前暂存（-1 表示未设置） */
  private pendingTypewriter: number = -1;
  private pendingRuns: FormatRun[] = [];
  /** 绑定前暂存的"保留滚动位置"意图（撤销/重做回灌时用） */
  private pendingPreserveView: boolean = false;

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
      this.editor.loadDocument(t, this.pendingRuns, this.pendingCaret >= 0 ? this.pendingCaret : t.length,
        this.pendingPreserveView);
      this.pendingPreserveView = false;
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
    // 处理暂存的打字机开关（工具栏在编辑器绑定前点击也能生效）
    if (this.pendingTypewriter >= 0) {
      this.editor.applyTypewriter(this.pendingTypewriter === 1);
    }
  }

  setText(text: string): void {
    if (this.editor !== null) {
      this.editor.loadText(text);
    } else {
      this.pendingText = text;
    }
  }

  /** 打字机开关（工具栏按钮调用；绑定前暂存，绑定后立即应用） */
  setTypewriter(on: boolean): void {
    this.pendingTypewriter = on ? 1 : 0;
    if (this.editor !== null) {
      this.editor.applyTypewriter(on);
    }
  }

  /**
   * 整体回灌正文。
   * preserveView=true 用于撤销/重做等内容替换：保留当前滚动位置，只有 caret 不在视口时才滚；
   * 切换文稿必须传 false（回到文首）。
   */
  setDocument(value: string, runs: FormatRun[], caret: number, preserveView: boolean = false): void {
    this.pendingRuns = runs.map((run: FormatRun): FormatRun => run.clone());
    if (this.editor !== null) {
      this.editor.loadDocument(value, this.pendingRuns, caret, preserveView);
    } else {
      this.pendingText = value;
      this.pendingCaret = caret;
      this.pendingPreserveView = preserveView;
    }
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
  /**
   * 非当前段落的淡化字色（打字机模式）。
   * 由宿主按当前主题（正文色 × 纸色）混合得到，编辑器不做任何硬编码取色。
   */
  @Prop @Watch('onThemeChanged') dimTextColor: string = '#9AA0A6';
  @Prop placeholder: string = '';
  /**
   * 打字机模式：为 true 时按 scrollPolicy=CENTER 使当前段居中（默认关）。
   * @Watch 是必要的：仅改这个 prop 时组件不会重排，表现为"点了按钮没有任何反应"。
   */
  /** 打字机显式覆盖：-1 未设置 / 0 关 / 1 开（控制器下发优先于 prop） */
  private typewriterOverride: number = -1;
  /** 打字机：当前段落覆盖的行区间（含端点），由 refreshTypewriterFocus 维护 */
  private twFirstLine: number = 0;
  private twLastLine: number = 0;
  private twValid: boolean = false;
  private twDirty: boolean = true;
  /** 打字机缩放：当前动画中的焦点行边界（浮点，用于连续过渡） */
  private twAnimFirst: number = -1;
  private twAnimLast: number = -1;
  /** 已下发动画的焦点行目标（用于判断"段落真的切换了"） */
  private twTargetFirst: number = -1;
  private twTargetLast: number = -1;
  private twScaleInitialized: boolean = false;
  private twScaleAnimator: EditorAnimator | null = null;
  /** 上一次绘制时的光标偏移：用于发现"非动画路径"的光标移动并刷新淡化范围 */
  private lastDrawnCaret: number = -1;
  /** 当前排版引擎构建时的打字机状态：用于发现 prop 更新但排版未重建的错配 */
  private engineTypewriter: boolean = false;
  @Prop @Watch('onTypewriterPropChanged') typewriter: boolean = false;
  /** 滚动策略：NORMAL（仅保证光标可见）/ CENTER（当前段居中跟随） */
  @Prop scrollPolicy: ScrollPolicy = ScrollPolicy.NORMAL;
  /**
   * 电脑模式（PC 自由窗口 / MatePad Edge 电脑模式）：键鼠优先交互。
   * V1 岛屿契约：只接收基本类型，不接收 V2 store 实例。
   */
  @Prop desktopMode: boolean = false;
  /** 指针为主输入（鼠标/触控板）：文本指针、右键菜单键盘操作、快捷键 */
  @Prop pointerPrimary: boolean = false;

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
  /** 沉浸编辑开关（F11）：由宿主切换界面状态，编辑器只转发 */
  onToggleImmersive: (() => void) | null = null;
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
  /** 滚动跟随动画（打字机/光标出视口时平滑滚动，替代每键瞬时跳变） */
  private scrollAnimator: EditorAnimator | null = null;
  /** 载入/首帧定位时光标揭示直接落位，不做滚动动画（避免打开文稿时"先滚一段"） */
  private instantScroll: boolean = false;
  private caret: CursorState = new CursorState();
  private pxPerVp: number = 1;
  private viewWidthVp: number = 0;
  private viewHeightVp: number = 0;
  private scrollY: number = 0;
  private lines: LayoutLine[] = [];
  private oldLines: LayoutLine[] = [];
  private lastEditOffset: number = 0;
  private cache: LayoutCache | null = null;
  /** 引擎重建键：宽度 + 密度 + 字号/行高/行距 + 内边距；任一变化都要重排 */
  private engineKey: string = '';
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
  /** 呼吸光标的相位（0–1，循环） */
  private breathPhase: number = 0;
  /** 最近一次鼠标/触控板事件时间（ms）：用于判定"指针点击"（不依赖可能缺失的枚举） */
  private lastPointerAtMs: number = 0;
  private initialized: boolean = false;
  private focused: boolean = false;
  /** 输入法 attach 是否成功：false 时字符键/删除键走键盘兜底（契约 §2.4） */
  private imeUsable: boolean = false;
  /** 键盘兜底插入后的 IME 回声抑制（40ms 内同文本去重，防双输入） */
  private echoGuard: ImeEchoGuard = new ImeEchoGuard();
  /** 唯一命令分发点：输入事件只经这里进入宿主执行 */
  private commandRouter: EditorCommandRouter = new EditorCommandRouter();
  /** EditCommandHost 适配器（struct 无法实现 interface，用薄类转调公开方法） */
  private hostAdapter: CanvasEditCommandHost | null = null;
  /** 是否已真正取得框架焦点（onFocus 确认）；未确认时会在布局就绪后补发焦点请求 */
  private focusConfirmed: boolean = false;
  /** 是否需要"打开即聚焦"：布局就绪后补发一次 requestEditorFocus（组件上树前请求会失败） */
  private wantInitFocus: boolean = false;
  /** 光标动画是否正在进行（用于在键盘/视口 relayout 时避免硬编码覆盖正在播放的光标） */
  private caretAnimating: boolean = false;
  // 触摸状态
  private pressX: number = 0;
  private pressY: number = 0;
  /** 按下点对应的文本偏移（拖选锚点用；不在 Move 时重新命中，避免手指漂移改变锚点） */
  private pressOffset: number = 0;
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
  private lastTapX: number = 0;
  private lastTapY: number = 0;
  /** 长按选中的词区间（用于"长按后继续拖动 = 词选区 ∪ 手指区间"） */
  private wordSelStart: number = -1;
  private wordSelEnd: number = -1;
  /** 连击计数：1 单(定位) / 2 双击(选词) / 3 三击(选段) */
  private tapStreak: number = 0;
  /** 本次按住是否已触发长按选中（用于 Up 时不坍缩选区） */
  private longPressed: boolean = false;

  // ===== IME 上报去抖 / 节流：选区每帧变化时不再重复过 IPC =====
  private lastReportedTextLen: number = -1;
  private lastReportedSelStart: number = -1;
  private lastReportedSelEnd: number = -1;
  private lastReportedCaretLeft: number = Number.NaN;
  private lastReportedCaretTop: number = Number.NaN;
  private lastSelectionReportAt: number = 0;

  /** 选区操作浮层显隐、位置（vp）与箭头方向 */
  @State menuVisible: boolean = false;
  @State menuX: number = 0;
  @State menuY: number = 0;
  @State menuBelow: boolean = false;
  /** 键盘操作浮层时的高亮项（0..10，顺序与 menuLabels() 一致） */
  @State menuIndex: number = 0;

  // ================= 选区操作浮层（补齐自绘化后丢失的系统选择菜单） =================

  @Builder
  selectionMenu() {
    Column() {
      if (!this.menuBelow) {
        Text('▼').fontSize(9).fontColor('#E61F2329')
      }
      Column() {
        Row() {
          ForEach(this.menuLabels().slice(0, 5), (label: string, index: number) => {
            Text(label)
              .fontSize(13).fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .backgroundColor(this.menuIndex === index ? '#33FFFFFF' : Color.Transparent)
              .borderRadius(4)
              .onClick(() => this.activateMenuItem(index))
          }, (label: string, index: number): string => 'menu0:' + label)
        }
        Row() {
          ForEach(this.menuLabels().slice(5), (label: string, index: number) => {
            Text(label)
              .fontSize(13).fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .backgroundColor(this.menuIndex === index + 5 ? '#33FFFFFF' : Color.Transparent)
              .borderRadius(4)
              .onClick(() => this.activateMenuItem(index + 5))
          }, (label: string, index: number): string => 'menu1:' + label)
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
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, CaretAffinity.UPSTREAM);
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
    // 每次弹出都把键盘高亮复位到第一项（方向键从这里开始移动）
    this.menuIndex = 0;
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
    this.stopCaretAnimation();
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
    this.caret = HitTester.caretPositionFor(end, this.lines, this.padLeftVp(), this.padTopVp(),
      this.theme.fontSize, this.selMgr.headAffinity);
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
    // 扩展选区是即时状态；不能让点击留下的弹簧动画继续覆盖 caret
    this.stopCaretAnimation();
    this.selMgr.setSource(this.doc.text);
    this.selMgr.extendTo(head);
    this.doc.setSelection(this.selMgr.anchor, this.selMgr.head);
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines, this.padLeftVp(), this.padTopVp(),
      this.theme.fontSize, this.selMgr.headAffinity);
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
    this.stopCaretAnimation();
    this.selMgr.setSource(this.doc.text);
    this.selMgr.setSelection(0, this.doc.text.length);
    this.doc.setSelection(0, this.doc.text.length);
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(this.selMgr.head, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
    this.ensureVisibleLayout();
    this.emitSelection(true);
    this.hideSelectionMenu();
    this.drawNow();
    this.reportCursor();
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
    this.theme.dimTextColor = this.dimTextColor;
    if (this.controller !== null) {
      this.controller.bind(this);
    }
    // 回声抑制在 ImeBridge 的 insertText 监听入口生效：键盘兜底插入后，
    // 40ms 内到达的同文本 IME 回调直接丢弃（契约 §2.4）
    this.ime.setEchoGuard(this.echoGuard);
    this.registerImeCallbacks();
  }

  aboutToDisappear(): void {
    this.documentGeneration++;
    this.cancelLongPress();
    if (this.controller !== null) { this.controller.unbind(this); }
    this.stopBlink();
    this.stopFling();
    this.stopScrollAnimation();
    this.stopTypewriterScaleAnimation();
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
          // 组件上树前 @Prop 可能已变化，而 onThemeChanged 因 initialized=false 提前返回；
          // 这里补一次同步，避免首帧仍按 aboutToAppear 时的旧字号排版。
          this.syncThemeFromProps();
          this.ensureEngine();
          this.instantScroll = true;
          this.relayout();
          this.instantScroll = false;
          // 打开文稿即聚焦：组件此刻已上树，补发此前失败的焦点请求，让光标立即可见
          this.ensureInitFocus();
          this.diag('onReady viewW=' + this.viewWidthVp.toFixed(1) + ' viewH=' + this.viewHeightVp.toFixed(1) +
            ' renderer=' + (this.renderer !== null ? 'yes' : 'no') + ' lines=' + this.lines.length.toString());
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          const widthChanged: boolean = Math.abs(Number(newValue.width) - Number(oldValue.width)) > 0.01;
          const heightChanged: boolean = Math.abs(Number(newValue.height) - Number(oldValue.height)) > 0.01;
          this.windowX = Number(newValue.globalPosition.x);
          this.windowY = Number(newValue.globalPosition.y);
          this.viewWidthVp = Number(newValue.width);
          this.viewHeightVp = Number(newValue.height);
          // 仅移动窗口（尺寸不变）只需更新窗口坐标，不必重排；否则 PC 拖动窗口会反复重排
          if (this.initialized && this.viewWidthVp > 0 && this.viewHeightVp > 0 &&
            (widthChanged || heightChanged)) {
            // 尺寸变化后菜单位置失效
            this.hideSelectionMenu();
            // 密度可能随窗口跨屏/系统缩放变化；先刷新再判断引擎是否需要重建
            const anchor: ViewAnchor = this.captureViewAnchor();
            this.refreshDensity();
            this.ensureEngine();
            this.relayoutPreservingAnchor(anchor);
            // 窗口尺寸变化后段落行区间会变：打字机模式下重新居中
            this.followTypewriter();
            this.ensureInitFocus();
          } else if (this.initialized) {
            // 仅位置变化：窗口坐标已更新，刷新一次 IME 光标位置
            this.reportCursor();
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
      // 输入形态校正 + 指针点击判定：真的收到鼠标事件才把当前点击视为指针操作
      deviceProfile.notePointerActivity();
      this.lastPointerAtMs = Date.now();
      if (event.button === MouseButton.Left && event.action === MouseAction.Press) {
        // 按下：锚点固定，不做弹簧动画（否则拖动时光标会先飞向旧目标）
        this.stopCaretAnimation();
        this.stopScrollAnimation();
        this.stopFling();
        this.hideSelectionMenu();
        this.requestEditorFocus();
        const offset: number = this.offsetAt(event.x, event.y);
        const handle: number = this.handleAt(event.x, event.y);
        if (handle !== 0) {
          // PC 也能拖手柄：身份固定（1=anchor / 2=head）
          this.selMgr.beginHandleDrag(handle);
          this.mouseSelecting = true;
          this.drawNow();
          return;
        }
        this.selMgr.beginDrag(offset);
        this.doc.moveCaret(offset);
        this.ensureCaretLayout();
        this.caret = HitTester.caretPositionFor(offset, this.lines, this.padLeftVp(), this.padTopVp(),
          this.theme.fontSize, CaretAffinity.DOWNSTREAM);
        this.mouseSelecting = true;
        this.caret.visible = true;
        this.caret.alpha = 1;
        this.twDirty = true;
        this.followTypewriter();
        this.drawNow();
      } else if (event.action === MouseAction.Move && this.mouseSelecting) {
        // 鼠标拖选与触摸共用同一套 anchor/head；caret 必须跟随 head
        const off: number = this.offsetAt(event.x, event.y);
        if (this.selMgr.draggingHandle !== 0) {
          this.selMgr.updateHandleDrag(off);
        } else {
          this.selMgr.updateDrag(off);
        }
        this.syncSelectionToCaret();
        this.emitSelection(false);
        this.hideSelectionMenu();
        this.drawNow();
      } else if (event.action === MouseAction.Release && this.mouseSelecting) {
        this.finishMouseSelection();
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
    // 鼠标在组件外释放时收不到 Release：用 onHover(false) 兜底收口，避免后续 Hover 继续拖选
    .onHover((isHover: boolean) => {
      if (!isHover && this.mouseSelecting) {
        this.finishMouseSelection();
      }
      // 电脑/指针优先：悬停时显示文本光标（官方 cursorController，API 12+）；
      // 触摸设备不改变光标，避免在纯触摸场景下发无意义的光标 IPC。
      this.applyPointerCursor(isHover);
    })
    // 滚轮/触控板滚动：只改滚动位置，绝不移动光标或改变选区
    .onAxisEvent((event: AxisEvent) => {
      // 滚轮/触控板 = 指针设备在场（触摸设备不会派发 axis 事件）
      deviceProfile.notePointerActivity();
      const delta: number = event.getVerticalAxisValue();
      if (delta !== 0) {
        this.stopFling();
        this.stopScrollAnimation();
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
      const softKeyboard: boolean = !this.desktopMode;
      this.attachIme(softKeyboard);
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

  loadDocument(text: string, runs: FormatRun[], caret: number, preserveView: boolean = false): void {
    this.documentGeneration++;
    this.twDirty = true;
    this.preferredX = -1;
    this.doc.setTextWithCaret(text, caret);
    this.doc.setRuns(runs);
    if (this.cache !== null) { this.cache.setRuns(this.doc.runs); }
    this.lastText = text;
    // 选区管理器需同步参照全文，否则 IME/拖动给出的偏移不会被吸附到字符边界
    this.selMgr.setSource(text);
    this.selMgr.collapse(this.doc.caretOffset);
    this.previewMgr.cancel();
    this.stopGlyphAnimation();
    if (!preserveView) {
      this.scrollY = 0;
    }
    // 换文稿：强制下一次 IME 上报，避免沿用旧稿的同坐标去重结果
    this.lastReportedCaretLeft = Number.NaN;
    this.lastReportedCaretTop = Number.NaN;
    this.lastReportedTextLen = -1;
    this.lastReportedSelStart = -1;
    this.lastReportedSelEnd = -1;
    this.instantScroll = true;
    this.relayout();
    this.instantScroll = false;
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
    this.stopScrollAnimation();
    const from: CursorState = this.caret;
    this.doc.moveCaret(offset);
    this.twDirty = true;
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
    this.followTypewriter();
  }

  insertExternalText(text: string): void {
    const wasComposing: boolean = this.previewMgr.isComposing;
    // 输入法切换语言会提交空文本；无组字状态时不应删除选区或产生编辑事务。
    // 空预上屏完成仍需替换原范围，保留组字流程的语义。
    if (text.length === 0 && !wasComposing) { return; }
    if (wasComposing) {
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
    if (wasComposing) {
      // 预览行已按最终文本排好；把 lastText 提前对齐，afterEdit 的差分即为空，
      // 提交时不会给预览字形补一次"入场动画"（那会看起来像文字跳一下）。
      this.lastText = this.doc.text;
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
    // 电脑模式（PC / MatePad Edge 电脑模式）接物理键盘时不拉起系统软键盘：
    // 判据用设备能力（desktopMode），不再用 deviceInfo.deviceType ——
    // 平板电脑模式不是 '2in1'，按 deviceType 判断会多余地弹出输入栏。
    const softKeyboard: boolean = !this.desktopMode;
    this.attachIme(softKeyboard);
    this.caret.visible = true;
    this.startBlink();
    this.drawNow();
  }

  /**
   * 挂接输入法并记录可用性（契约 §2.4）。
   *
   * ImeBridge.attach 内部已 catch 失败，因此 resolve 后必须用 ime.attached 判定真实结果：
   * - true：字符键交给 IME（中文组字），preIme 放行字符；
   * - false：imeUsable=false，字符/删除/回车走键盘兜底，并用 ImeEchoGuard 防双输入。
   */
  private attachIme(showSoftKeyboard: boolean): void {
    this.ime.attach(showSoftKeyboard, inputMethod.TextInputType.TEXT,
      inputMethod.EnterKeyType.UNSPECIFIED).then(() => {
        this.imeUsable = this.ime.attached;
        if (this.imeUsable) {
          this.reportSelection();
          this.reportCursor();
        }
        this.diag('ime attach settled usable=' + this.imeUsable.toString());
      }).catch(() => {
        this.imeUsable = false;
        this.diag('ime attach rejected -> keyboard fallback');
      });
  }

  /**
   * 指针优先形态下的光标反馈（契约 §2.5）。
   *
   * 官方给的是 cursorController（`getUIContext().getCursorController()`，API 12+），
   * 光标样式来自 `pointer.PointerStyle`：文本选择用 TEXT_CURSOR。
   * 不使用 `.pointerStyle()`：ArkUI 里 PointerStyle 只是 `type` 别名，取不到枚举值，
   * 且触摸设备不需要光标反馈。
   */
  private applyPointerCursor(inside: boolean): void {
    if (!this.desktopMode && !this.pointerPrimary) {
      return;
    }
    try {
      if (inside) {
        this.getUIContext().getCursorController().setCursor(pointer.PointerStyle.TEXT_CURSOR);
      } else {
        this.getUIContext().getCursorController().restoreDefault();
      }
    } catch (e) {
      // 非键鼠设备 / 光标能力缺失：忽略，不影响编辑
    }
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
    this.imeUsable = false;
    this.echoGuard.reset();
    // 重新 attach 输入法后必须强制上报一次 caret/selection，清掉去重缓存
    this.lastReportedCaretLeft = Number.NaN;
    this.lastReportedCaretTop = Number.NaN;
    this.lastReportedTextLen = -1;
    this.lastReportedSelStart = -1;
    this.lastReportedSelEnd = -1;
    this.stopBlink();
    this.caret.visible = false;
    this.drawNow();
  }

  /** 把 @Prop 视觉参数同步到内部 theme（onReady / onThemeChanged 共用） */
  private syncThemeFromProps(): void {
    this.theme.fontSize = this.fontSize;
    this.theme.lineHeight = this.lineHeight;
    this.theme.lineSpacing = this.lineSpacing;
    this.theme.textColor = this.textColor;
    this.theme.backgroundColor = this.bgColor;
    this.theme.caretColor = this.caretColor;
    this.theme.dimTextColor = this.dimTextColor;
  }

  /** 视觉参数变化：同步主题、重建引擎并重排（T030） */
  onThemeChanged(): void {
    if (!this.initialized) {
      return;
    }
    this.syncThemeFromProps();
    // 字号/行高变了：光标盒尺寸变化，强制下一次 IME 光标上报
    this.lastReportedCaretLeft = Number.NaN;
    this.lastReportedCaretTop = Number.NaN;
    this.hideSelectionMenu();
    // 引擎按字号/行高构建，参数变化须重建（否则仍按旧字号排版）
    const anchor: ViewAnchor = this.captureViewAnchor();
    this.cache = null;
    this.renderer = null;
    this.ensureEngine();
    // 关键：不能先 clampScroll（新 cache 高度为 0 会把 scrollY 夹回 0），
    // 重排后用锚点恢复阅读位置。
    this.relayoutPreservingAnchor(anchor);
    // 字号/行高/主题变化后行高与段落位置都变了：打字机模式下重新居中
    this.followTypewriter();
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
      let kind: EditCommandKind = EditCommandKind.NONE;
      if (direction === inputMethod.Direction.CURSOR_LEFT) { kind = EditCommandKind.MOVE_LEFT; }
      else if (direction === inputMethod.Direction.CURSOR_RIGHT) { kind = EditCommandKind.MOVE_RIGHT; }
      else if (direction === inputMethod.Direction.CURSOR_UP) { kind = EditCommandKind.MOVE_UP; }
      else if (direction === inputMethod.Direction.CURSOR_DOWN) { kind = EditCommandKind.MOVE_DOWN; }
      if (kind !== EditCommandKind.NONE) {
        this.dispatchCommand(new EditCommand(kind, '', EditorInputSource.IME));
      }
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
    this.twDirty = true;
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
   * 处理一次物理按键（③ 阶段：晚于输入法）。
   *
   * 只做"事件 → 命令"转换（契约 §2.2），不再依据内部 focused 标志丢弃按键：
   * 框架能把按键派发到这里，就说明组件在框架层已获焦，此时把 focused 校正为 true。
   * 走到 ③ 说明输入法没有消费该键（被 IME 消费的键在 ② 就停止派发），
   * 因此字符/删除命令在这里作为兜底执行；随后到达的 IME 回声由 ImeEchoGuard 丢弃。
   *
   * @return true 表示已消费该按键（调用方应停止冒泡，避免触发系统默认行为）
   */
  handleKeyEvent(event: KeyEvent): boolean {
    if (event === undefined || event === null) {
      return false;
    }
    if (this.previewMgr.isComposing) { return false; }
    const isDown: boolean = event.type === KeyType.Down;
    const mods: EditorModifiers = this.readEditorModifiers(event);
    const cmd: EditCommand = resolveShortcut(event.keyCode, event.keyText, isDown, mods, false);
    if (cmd.kind === EditCommandKind.NONE) {
      // Tab / 未识别按键：不消费，交还框架焦点遍历与系统默认行为
      return false;
    }
    this.adoptKeyFocus();
    this.diag('handleKeyEvent cmd=' + cmd.kind.toString() + ' keyCode=' + event.keyCode.toString() +
      ' imeUsable=' + this.imeUsable.toString());
    if (this.menuVisible && this.handleMenuKey(cmd)) {
      return true;
    }
    return this.dispatchCommand(cmd);
  }

  /**
   * onKeyPreIme 专用（① 阶段，先于输入法）：只做"事件 → 命令"，消费策略交给 InputArbiter。
   *
   * 背景（官方）：按键三次派发为 ① onKeyPreIme + 快捷键 → ② 输入法 → ③ 系统默认 Key + onKeyEvent。
   * - 走位键/组合键/Esc 必须在本阶段截获：方向键会被输入法拿去切候选词，Ctrl 组合会被系统吞掉；
   * - 字符键在输入法可用时**必须放行**（中文/拼音组字依赖 IME 收字母）；
   * - 输入法 attach 失败（imeUsable=false）时，字符键才允许在 preIme 直接消费走键盘兜底；
   * - Tab 不产生命令 → 返回 false，恢复焦点遍历。
   *
   * @return true 表示该键已被消费（后续不再发给输入法与 onKeyEvent）
   */
  private handleKeyPreIme(event: KeyEvent): boolean {
    if (event === undefined || event === null) {
      return false;
    }
    // 组字中所有键交还输入法（含方向键选候选词）
    if (this.previewMgr.isComposing) { return false; }
    const isDown: boolean = event.type === KeyType.Down;
    const mods: EditorModifiers = this.readEditorModifiers(event);
    const cmd: EditCommand = resolveShortcut(event.keyCode, event.keyText, isDown, mods, false);
    if (cmd.kind === EditCommandKind.NONE) {
      return false; // 字母键 / Tab 等放行
    }
    this.adoptKeyFocus();
    if (this.menuVisible && this.handleMenuKey(cmd)) {
      return true;
    }
    if (!shouldConsumePreIme(cmd, this.imeUsable)) {
      return false;
    }
    const handled: boolean = this.dispatchCommand(cmd);
    if (handled) {
      this.diag('preIme consumed cmd=' + cmd.kind.toString());
    }
    return handled;
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
    const mods: EditorModifiers = this.readEditorModifiers(event);
    return [mods.ctrl, mods.shift, mods.alt];
  }

  /** 读取 Ctrl / Shift / Alt / Meta 修饰键（键鼠归一后统一用 EditorModifiers 传参） */
  private readEditorModifiers(event: KeyEvent): EditorModifiers {
    const out: EditorModifiers = new EditorModifiers();
    if (event.getModifierKeyState === undefined || event.getModifierKeyState === null) {
      return out;
    }
    const names: string[] = ['Ctrl', 'Shift', 'Alt', 'Meta'];
    const values: boolean[] = [false, false, false, false];
    for (let i: number = 0; i < names.length; i++) {
      try {
        const list: string[] = [names[i]];
        values[i] = event.getModifierKeyState(list) === true;
      } catch (e) {
        values[i] = false;
      }
    }
    out.ctrl = values[0];
    out.shift = values[1];
    out.alt = values[2];
    out.meta = values[3];
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
        // 全选必须走统一收口：更新绘制 caret、上抛选区回调、给 IME 上报
        this.selectAllText();
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
    this.twDirty = true;
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

  /**
   * 引擎重建键：宽度/密度/字号/行高/行距/内边距任一变化都必须重排。
   * 旧实现只比较 viewWidthVp，导致跨屏/缩放（密度变化）或字号变化后仍用旧引擎，
   * 排版 px 与画布 vp 换算不一致 → 文字/光标整体漂移。
   */
  private engineSignature(): string {
    return this.viewWidthVp.toFixed(2) + '|' + this.pxPerVp.toFixed(4) + '|' +
      this.theme.fontSize.toFixed(2) + '|' + this.theme.lineHeight.toFixed(2) + '|' +
      this.theme.lineSpacing.toFixed(2) + '|' + this.theme.paddingLeft.toFixed(2) + '|' +
      this.theme.paddingRight.toFixed(2) + '|tw=' +
      (this.effectivePolicy() === ScrollPolicy.CENTER ? this.theme.typewriterScale.focusScale.toFixed(3) : '1');
  }

  private ensureEngine(): void {
    if (this.cache !== null && this.renderer !== null && this.engineSignature() === this.engineKey) {
      return;
    }
    if (this.viewWidthVp <= 0) {
      return;
    }
    const baseContentVp: number = Math.max(1,
      this.viewWidthVp - this.theme.paddingLeft - this.theme.paddingRight);
    // 打字机模式预留放大空间：文本列按 focusScale 收窄，当前段落放大后正好回到原列宽，
    // 既不会横向裁剪，也不改变行高/段距（只在进入/退出打字机时换行一次）。
    const focusScale: number = Math.max(1.0, this.theme.typewriterScale.focusScale);
    const typewriterOn: boolean = this.effectivePolicy() === ScrollPolicy.CENTER;
    // 额外留 8vp 安全边（放大后左右各 8vp），并用硬裁剪兜底：
    // 即使字体斜体/字形动画有少量过冲，也不会越过编辑区边界。
    const typewriterSafeVp: number = 16;
    const contentWidthVp: number = typewriterOn
      ? Math.max(1, (baseContentVp - typewriterSafeVp) / focusScale)
      : baseContentVp;
    this.engineKey = this.engineSignature();
    this.engineTypewriter = typewriterOn;
    this.stopCaretAnimation();
    this.stopScrollAnimation();
    this.caretAnimating = false;
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
    // 旧预上屏排版属于旧引擎，丢弃；下一次预览回调会用新引擎重建
    this.previewCache = null;
    this.lines = [];

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
    rtp.dimTextColor = parseColor(this.theme.dimTextColor);
    rtp.caretWidthVp = this.theme.caretWidth;
    rtp.pxPerVp = this.pxPerVp;
    // 打字机：段落缩放层级。布局列已按 1/focusScale 收窄，
    // 缩放轴心取文本列左边缘（见 GlyphRenderer.textPivotPx）：
    // 所有行左边界对齐，当前段放大后右边界正好回到原列宽，不裁剪、不缩进。
    rtp.typewriterScale = this.theme.typewriterScale;
    rtp.textColumnWidthVp = contentWidthVp;
    rtp.paddingRightVp = this.theme.paddingRight;
    rtp.viewWidthVp = this.viewWidthVp;
    rtp.viewHeightVp = this.viewHeightVp;
    this.renderer = new GlyphRenderer(rtp);
    this.caretAnimator = new EditorAnimator(this.getUIContext());
    this.glyphAnimator = new EditorAnimator(this.getUIContext());
    this.scrollAnimator = new EditorAnimator(this.getUIContext());
    this.twScaleAnimator = new EditorAnimator(this.getUIContext());
  }

  private padLeftVp(): number {
    return this.theme.paddingLeft;
  }

  private padTopVp(): number {
    return this.theme.paddingTop;
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

  /**
   * 确保排版覆盖到指定内容 y。
   * 滚动上限/光标揭示必须先按目标位置扩展排版，再取**已排版精确高度**；
   * 用"平均行高 × 剩余字数"估算会把 scrollY 夹回，造成长文滚动回弹。
   */
  private ensureLayoutThroughY(y: number): void {
    if (this.cache === null) {
      return;
    }
    const untilY: number = Math.max(y, this.caret.y + this.viewHeightVp);
    if (this.previewMgr.isComposing && this.previewDoc !== null && this.previewCache !== null) {
      const provisional: TextDocument = this.previewDoc;
      this.previewCache.setRuns(provisional.runs);
      this.lines = this.previewCache.ensureLayout(provisional.text, provisional.version,
        provisional.formatVersion, untilY);
      return;
    }
    this.cache.setRuns(this.doc.runs);
    this.lines = this.cache.ensureLayout(this.doc.text, this.doc.version, this.doc.formatVersion, untilY);
  }

  /** 重新排版并立即绘制 */
  private relayout(): void {
    this.twDirty = true;
    // 行索引随排版变化：缩放边界直接吸附，不做"旧行号→新行号"的假动画
    this.twScaleInitialized = false;
    if (this.cache === null || this.renderer === null) {
      return;
    }
    const perfT0: number = Date.now();
    // 重排会改变行坐标：先取消光标弹簧，避免动画目标停留在旧排版位置
    this.stopCaretAnimation();
    this.ensureLayoutThroughY(this.scrollY + this.viewHeightVp);
    if (!this.previewMgr.isComposing) {
      // 组字期间 this.lines 必须保持 previewCache 的排版；主 cache 会覆盖掉预览文字
      this.ensureCaretLayout();
    }
    let lm: string = 'pxPerVp=' + this.pxPerVp.toFixed(3) + ' lines=' + this.lines.length.toString();
    for (let i = 0; i < this.lines.length && i < 3; i++) {
      const l = this.lines[i];
      lm += (' | y=' + l.yOffset.toFixed(1) + ' h=' + l.height.toFixed(1) +
        ' step=' + l.step.toFixed(1) + ' base=' + l.baseline.toFixed(1) +
        ' w=' + l.width.toFixed(1) + ' end=' + l.endIndex.toString());
    }
    this.diag(lm);
    this.stopGlyphAnimation();
    const caretOffset: number = (this.previewMgr.isComposing && this.previewDoc !== null)
      ? this.previewDoc.caretOffset : this.doc.caretOffset;
    this.caret = HitTester.caretPositionFor(caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
    this.ensureCaretVisible(this.effectivePolicy());
    this.drawNow();
    this.reportCursor();
    // 性能诊断（T036）：Phase 5 真机据此核对 5 万字下重排耗时
    this.diag('perf relayout=' + (Date.now() - perfT0).toString() + 'ms lines=' +
      this.lines.length.toString() + ' len=' + this.doc.length.toString());
  }

  /** 记录"光标在当前视口中的屏幕 y"，供重建引擎/重排后恢复阅读位置 */
  private captureViewAnchor(): ViewAnchor {
    if (this.lines.length === 0 || this.cache === null) {
      return new ViewAnchor();
    }
    return new ViewAnchor(this.doc.caretOffset, this.caret.y - this.scrollY, this.caret.height, true);
  }

  /**
   * 重建引擎后按锚点恢复滚动位置，而不是直接沿用旧 scrollY 或先 clamp。
   * 旧实现 onAreaChange/onThemeChanged 的顺序是 ensureEngine → clampScroll → relayout，
   * 新 cache 高度为 0 时 clampScroll 会把 scrollY 夹到 0，页面直接跳回顶部。
   */
  private relayoutPreservingAnchor(anchor: ViewAnchor): void {
    if (this.cache === null || this.renderer === null) {
      return;
    }
    this.stopCaretAnimation();
    this.stopScrollAnimation();
    this.relayout();
    // relayout 内部可能启动"光标可见"滚动动画；锚点恢复要接管滚动位置，先停掉它
    this.stopScrollAnimation();
    if (this.previewMgr.isComposing) {
      // 组字期间 lines 属于 previewCache，不能用已提交文档的 caret 重算
      this.drawNow();
      return;
    }
    if (!anchor.valid || this.lines.length === 0) {
      return;
    }
    this.ensureCaretLayout();
    const to: CursorState = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
    this.caret = to;
    // 若键盘弹起导致视口变矮，把锚点屏幕 y 夹进新视口，避免光标被顶出屏幕
    const maxScreenY: number = Math.max(0, this.viewHeightVp - to.height);
    const screenY: number = Math.min(Math.max(0, anchor.caretScreenY), maxScreenY);
    this.scrollY = to.y - screenY;
    this.clampScroll();
    this.ensureVisibleLayout();
    this.drawNow();
    this.reportCursor();
  }

  /** 密度（vp→px）变化时刷新并强制重建引擎；旧实现只在 aboutToAppear 取一次 */
  private refreshDensity(): void {
    let density: number = this.pxPerVp;
    try {
      density = this.getUIContext().vp2px(1);
    } catch (e) {
      density = this.pxPerVp;
    }
    if (density > 0 && Math.abs(density - this.pxPerVp) > 0.0001) {
      this.pxPerVp = density;
      this.cache = null;
      this.renderer = null;
    }
  }

  /** 编辑后：失效重排 + 字形动画 + 光标平滑移动动画 */
  private afterEdit(): void {
    this.preferredX = -1;
    // 正文/排版已变：旧弹簧动画的目标坐标已失效，必须先停，否则光标会被拉回旧位置
    this.stopCaretAnimation();
    this.stopScrollAnimation();
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
    this.stopGlyphAnimation();
    this.anims = GlyphAnimator.createEditAnimations(this.oldLines, this.lines, diff);
    this.lastText = this.doc.text;
    this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
    this.twDirty = true;
    // 打字机 + 连续输入：居中必须**立即**生效。
    // 若每次按键都启动 160ms 滚动动画，快速输入会不断打断上一段动画，视口追不上文字，
    // 表现为"光标/画面滞后"。这里对编辑事务使用即时滚动，导航/点击仍保留平滑动画。
    if (this.effectivePolicy() === ScrollPolicy.CENTER) {
      const prevInstant: boolean = this.instantScroll;
      this.instantScroll = true;
      this.ensureCaretVisible(ScrollPolicy.CENTER);
      this.instantScroll = prevInstant;
    } else {
      this.ensureCaretVisible(this.effectivePolicy());
    }
    this.runGlyphAnimation();
    this.reportCursor();
    // 编辑后选区已收起：让输入法同步新的 caret/选区，避免候选框停留在旧位置
    this.reportSelection(true);
  }

  /**
   * 取消光标弹簧动画并复位 caretAnimating。
   * EditorAnimator.stop() 不会触发 onFinish；若不显式复位，relayout 会永远跳过光标重算、
   * 闪烁也会被守卫住（改字号/重建引擎后光标冻结的根因）。
   */
  private stopCaretAnimation(settleTo: CursorState | null = null): void {
    if (this.caretAnimator !== null) {
      this.caretAnimator.stop();
    }
    this.caretAnimating = false;
    if (settleTo !== null) {
      this.caret.x = settleTo.x;
      this.caret.y = settleTo.y;
      this.caret.height = settleTo.height;
      this.caret.visible = settleTo.visible;
    }
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
    // 移动过程中光标保持实心可见，到位后恢复呼吸（呼吸由 !caretAnimating 守卫）
    this.caret.visible = true;
    this.caret.alpha = 1;
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

  /** 停止字形动画并清空注册表，避免旧动画帧改写新一轮动画的 progress */
  private stopGlyphAnimation(): void {
    if (this.glyphAnimator !== null) {
      this.glyphAnimator.stop();
    }
    this.anims.clear();
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
    // 排版宽度与打字机状态必须一致：某些输入路径可能只更新了 prop 而未触发重建，
    // 导致"文字按 1.08 缩放、排版仍按全宽换行"→ 高亮段越界。这里在绘制前兜底校正一次。
    const typewriterMode: boolean = this.effectivePolicy() === ScrollPolicy.CENTER;
    if (this.initialized && this.renderer !== null && this.engineTypewriter !== typewriterMode &&
      this.viewWidthVp > 0) {
      const anchor: ViewAnchor = this.captureViewAnchor();
      this.cache = null;
      this.renderer = null;
      this.ensureEngine();
      if (this.renderer !== null) {
        this.relayoutPreservingAnchor(anchor);
        this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
          this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
      }
      this.twDirty = true;
      this.twScaleInitialized = false;
    }
    this.ensureVisibleLayout();
    // 上面的兜底同步会把 renderer 置空后重建；此处重新取一次并收窄类型，
    // 否则 TS 仍认为 this.renderer 可能为 null（10505001）。
    if (this.renderer === null) {
      this.diag('drawNow renderer=null after rebuild (skip)');
      return;
    }
    const renderer: GlyphRenderer = this.renderer;
    if (this.lines.length === 0) {
      this.diag('drawNow lines=0 doc.len=' + this.doc.length.toString() +
        ' cache.lines=' + (this.cache !== null ? this.cache.lineCount().toString() : '-') +
        ' scrollY=' + this.scrollY.toFixed(1) + ' viewH=' + this.viewHeightVp.toFixed(1));
    }
    // 光标任何来源的移动都可能改变"当前段落"；按偏移变化标脏，保证淡化实时更新
    if (this.lastDrawnCaret !== this.doc.caretOffset) {
      this.lastDrawnCaret = this.doc.caretOffset;
      this.twDirty = true;
    }
    const viewport = new ViewportInfo(this.scrollY, this.viewHeightVp);
    const preview: PreviewInfo | null = this.previewMgr.isComposing ? this.previewMgr.previewInfo : null;
    // 打字机：当前段落之外的行淡化；段落区间按需重算（dirty 标记，热路径无额外分配）
    const typewriterOn: boolean = this.effectivePolicy() === ScrollPolicy.CENTER;
    if (typewriterOn) {
      this.refreshTypewriterFocus();
    }
    const dimEnabled: boolean = typewriterOn && this.twValid;
    // 淡化与缩放共用同一组"动画中的焦点边界"，段落切换时两者一起平滑过渡
    const focusFirst: number = this.twAnimFirst >= 0 ? this.twAnimFirst : this.twFirstLine;
    const focusLast: number = this.twAnimLast >= 0 ? this.twAnimLast : this.twLastLine;
    const caretLine: number = this.lines.length > 0
      ? HitTester.lineIndexOf(this.doc.caretOffset, this.lines) : -1;
    renderer.draw(this.ctx, this.lines, this.caret,
      preview === null ? this.selMgr.selection : null, preview, viewport, this.anims, this.handlePositions(),
      dimEnabled, focusFirst, focusLast, typewriterOn, caretLine);
  }

  /**
   * 选区两端的把手位置（内容坐标；无选区/端点未排版时返回空）。
   * 顺序固定为 [anchor, head]，与 SelectionManager 的手柄身份一致。
   * 端点若超出已排版范围（如 Ctrl+A 后长文末尾），宁可不画也不画到错误的行。
   */
  private handlePositions(): CursorState[] {
    const sel: SelectionInfo = this.selMgr.selection;
    if (sel.isEmpty() || this.lines.length === 0) {
      return [];
    }
    const lastEnd: number = this.lines[this.lines.length - 1].endIndex;
    if (this.selMgr.anchor > lastEnd || this.selMgr.head > lastEnd) {
      return [];
    }
    const anchorAffinity: CaretAffinity = this.selMgr.headAffinity === CaretAffinity.DOWNSTREAM
      ? CaretAffinity.UPSTREAM : CaretAffinity.DOWNSTREAM;
    const a: CursorState = HitTester.caretPositionFor(this.selMgr.anchor, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, anchorAffinity);
    const b: CursorState = HitTester.caretPositionFor(this.selMgr.head, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
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
  private emitSelection(force: boolean = false): void {
    const active: SelectionInfo = this.selMgr.selection;
    if (active.isEmpty()) { this.doc.moveCaret(active.startOffset); }
    else { this.doc.setSelection(this.selMgr.anchor, this.selMgr.head); }
    if (this.onCaretChange !== null) { this.onCaretChange(this.doc.caretOffset); }
    if (this.onSelectionChange !== null) {
      const sel: SelectionInfo = this.selMgr.selection;
      this.onSelectionChange(sel.startOffset, sel.endOffset);
    }
    // 同步选区给输入法：否则软键盘删除只会按字符删，不会删整个选区
    this.reportSelection(force);
  }

  /**
   * 选区变化后统一同步"绘制用光标"到 head 端。
   * 修复：拖选/手柄拖动只更新了 doc 的 selection，this.caret 仍停在锚点，
   * 视觉上就是"高亮在动、光标不动"。
   */
  private syncSelectionToCaret(): void {
    this.stopCaretAnimation();
    const anchor: number = this.selMgr.anchor;
    const head: number = this.selMgr.head;
    if (anchor === head) {
      this.doc.moveCaret(head);
    } else {
      this.doc.setSelection(anchor, head);
    }
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(head, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, this.selMgr.headAffinity);
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
    const left: number = (this.windowX + this.caret.x) * this.pxPerVp - caretW / 2;
    const top: number = (this.windowY + topVp) * this.pxPerVp;
    // 光标未变化时不重复过 IPC（闪烁/滚动帧不必每次通知输入法）
    if (Math.abs(left - this.lastReportedCaretLeft) < 0.5 && Math.abs(top - this.lastReportedCaretTop) < 0.5) {
      return;
    }
    this.lastReportedCaretLeft = left;
    this.lastReportedCaretTop = top;
    this.ime.updateCursor(left, top, caretW, this.caret.height * this.pxPerVp);
  }

  /** 选区变化后上报输入法（键盘选区、输入法联动需要） */
  /**
   * 选区上报 IME：拖选每帧调用会重复传整篇正文（5 万字≈100KB IPC，
   * 可能触发 12800003 并导致软键盘删除/候选框错乱）。
   * 这里按 (文本长度,start,end) 去重 + 32ms 节流，Up 时 force 上报。
   */
  private reportSelection(force: boolean = false): void {
    if (!this.ime.attached) {
      return;
    }
    const sel = this.selMgr.selection;
    const now: number = Date.now();
    const textLen: number = this.doc.length;
    const sameTuple: boolean = textLen === this.lastReportedTextLen &&
      sel.startOffset === this.lastReportedSelStart && sel.endOffset === this.lastReportedSelEnd;
    if (!force) {
      if (sameTuple) {
        return;
      }
      if (now - this.lastSelectionReportAt < 32) {
        return;
      }
    }
    this.lastReportedTextLen = textLen;
    this.lastReportedSelStart = sel.startOffset;
    this.lastReportedSelEnd = sel.endOffset;
    this.lastSelectionReportAt = now;
    if (this.previewMgr.isComposing) {
      const at: number = this.displayCaret();
      this.ime.changeSelection(this.displayText(), at, at);
    } else {
      this.ime.changeSelection(this.doc.text, sel.startOffset, sel.endOffset);
    }
  }

  /**
   * 触摸状态机：点按定位 / 长按选词 / 拖选 / 手柄拖动 / 纵向滚动 / Cancel 复位。
   *
   * 关键规则（对齐 OH RichEditor/TextField）：
   * - 按下时只记录一次 pressOffset 作为拖选锚点，Move 不重新命中；
   * - 长按已选词后继续拖动 = 词区间 ∪ [手指, 词]，anchor 不重置；
   * - 拖选手柄身份固定（1=anchor / 2=head），越过对端由 min/max 归一；
   * - 拖选过程中只更新高亮/光标，不每帧弹菜单；Up 时统一弹一次；
   * - 收到 Cancel 必须把全部手势状态复位。
   */
  private handleTouch(event: TouchEvent): void {
    // 最后一根手指抬起时 touches 可能为空，此时坐标在 changedTouches；
    // 只用 touches 会让 Up/Cancel 被丢弃（拖选后手势卡住/光标不落位）。
    let x: number = 0;
    let y: number = 0;
    if (event.touches.length > 0) {
      x = event.touches[0].x;
      y = event.touches[0].y;
    } else if (event.changedTouches.length > 0) {
      x = event.changedTouches[0].x;
      y = event.changedTouches[0].y;
    } else {
      return;
    }
    if (event.type === TouchType.Down) {
      this.cancelLongPress();
      this.stopCaretAnimation();
      this.stopScrollAnimation();
      this.stopFling();
      this.pressX = x;
      this.pressY = y;
      this.pressOffset = this.offsetAt(x, y);
      this.wordSelStart = -1;
      this.wordSelEnd = -1;
      this.dragging = false;
      this.scrollMode = false;
      this.longPressed = false;
      this.pressScrollY = this.scrollY;
      this.scrollVel = 0;
      this.lastScrollY = this.scrollY;
      this.lastScrollAt = Date.now();
      this.hideSelectionMenu();
      this.diag('DOWN touch=(vp)' + x.toFixed(1) + ',' + y.toFixed(1) + ' scrollY=' + this.scrollY.toFixed(1));
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
      if (!this.dragging && EditorGesture.isDrag(this.pressX, this.pressY, x, y)) {
        this.cancelLongPress();
        this.dragging = true;
        if (this.longPressed && this.wordSelStart >= 0) {
          // 长按已选词：继续拖动 = 扩展词选区，绝不重设锚点
          this.scrollMode = false;
          this.extendWordSelection(x, y);
        } else {
          this.scrollMode = Math.abs(dy) > Math.abs(dx);
          if (this.scrollMode) {
            // 滚动即收起软键盘，腾出阅读空间（点击后重新拉起）
            if (!this.keyboardSuppressed) {
              this.keyboardSuppressed = true;
              this.ime.hideKeyboard();
            }
          } else {
            this.selMgr.beginDrag(this.pressOffset);
            this.syncSelectionToCaret();
          }
        }
      }
      if (this.dragging && this.selMgr.draggingHandle !== 0) {
        // 边缘自动滚动：先滚，再用滚动后的坐标命中，避免选区落后一帧
        this.autoScrollForHandleDrag(y);
        const offH: number = this.offsetAt(x, y);
        this.selMgr.updateHandleDrag(offH);
        this.syncSelectionToCaret();
        this.emitSelection(false);
        this.hideSelectionMenu();
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
        this.hideSelectionMenu();
        // 上报滚动方向（T032）：手指上滑(dy<0)=向下浏览内容 → 1；反之 -1
        if (this.onScrollState !== null) {
          this.onScrollState(dy < 0 ? 1 : -1);
        }
        this.drawNow();
      } else if (this.dragging) {
        if (this.longPressed && this.wordSelStart >= 0) {
          this.extendWordSelection(x, y);
        } else {
          this.selMgr.updateDrag(this.offsetAt(x, y));
        }
        this.syncSelectionToCaret();
        this.emitSelection(false);
        this.hideSelectionMenu();
        this.drawNow();
      }
    } else if (event.type === TouchType.Up) {
      const wasScroll: boolean = this.scrollMode;
      const wasDragging: boolean = this.dragging;
      // 兜底：部分场景 Down 事件被系统消费，Up 时确保已 attach 输入法
      this.cancelLongPress();
      this.requestEditorFocus();
      if (!wasDragging && !this.longPressed) {
        // 用 Down（手指按下）坐标定位，而非 Up（抬起）坐标：真机上手指抬起位置常比按下位置偏左上。
        const now: number = Date.now();
        const tapDx: number = this.pressX - this.lastTapX;
        const tapDy: number = this.pressY - this.lastTapY;
        // 连击判定 = 时间窗 + 位移阈值（OH MultipleClickRecognizer：300ms/15vp 量级），
        // 只看时间会把"拖一下再点"误判成双击，进而产生错误选词。
        const near: boolean = (now - this.lastTapAt) <= this.DOUBLE_TAP_MS &&
          (tapDx * tapDx + tapDy * tapDy) <= 15 * 15;
        this.tapStreak = near ? (this.tapStreak + 1) : 1;
        this.lastTapAt = now;
        this.lastTapX = this.pressX;
        this.lastTapY = this.pressY;
        if (this.tapStreak >= 3) {
          this.tapStreak = 0;
          this.stopCaretAnimation();
          this.diag('tripleTap x=' + this.pressX.toFixed(1) + ',y=' + this.pressY.toFixed(1));
          this.selectParagraphAt(this.pressX, this.pressY);
          this.longPressed = true;
        } else if (this.tapStreak === 2) {
          this.stopCaretAnimation();
          this.diag('doubleTap x=' + this.pressX.toFixed(1) + ',y=' + this.pressY.toFixed(1));
          this.selectWordAt(this.pressX, this.pressY, 'doubleTap');
          this.longPressed = true;
        } else {
          this.selMgr.collapse(this.pressOffset);
          this.emitSelection(false);
          this.diag('UP tap offset=' + this.pressOffset.toString() + ' lines=' + this.lines.length.toString() +
            ' pointer=' + this.isPointerInput(event).toString());
          if (this.isPointerInput(event)) {
            // 鼠标/触控板点击：立即落位，不播放光标移动动画
            this.placeCaretImmediately(this.pressOffset);
          } else {
            // 手指点按：保留平滑移动动画
            this.moveCaretAnimated(this.pressOffset);
          }
        }
      }
      this.longPressed = false;
      if (wasDragging) {
        // 拖过/滚过之后不应把下一次点按算进连击（时间窗内会误判双击选词）
        this.tapStreak = 0;
        this.lastTapAt = 0;
      }
      this.selMgr.endHandleDrag();
      this.selMgr.endDrag();
      this.wordSelStart = -1;
      this.wordSelEnd = -1;
      if (!this.selMgr.selection.isEmpty() && !wasScroll) {
        this.syncSelectionToCaret();
        this.emitSelection(true);
        // 只在 Up 时弹一次菜单；拖动过程中不再跟随手指逐帧移动
        this.showSelectionMenu();
      } else {
        this.emitSelection(true);
        this.hideSelectionMenu();
      }
      if (this.onScrollState !== null) {
        this.onScrollState(0);
      }
      if (wasScroll) {
        this.startFling();
      }
      this.dragging = false;
      this.scrollMode = false;
      if (!wasScroll && this.keyboardSuppressed) {
        this.keyboardSuppressed = false;
        this.ime.showKeyboard();
      }
    } else if (event.type === TouchType.Cancel) {
      // 系统抢走手势（来电/返回手势/多指）时必须复位，否则后续 Move 会继续拖一个已不存在的手势
      this.cancelLongPress();
      this.stopFling();
      this.stopScrollAnimation();
      this.selMgr.endHandleDrag();
      this.selMgr.endDrag();
      this.wordSelStart = -1;
      this.wordSelEnd = -1;
      this.dragging = false;
      this.scrollMode = false;
      this.longPressed = false;
      this.tapStreak = 0;
      this.lastTapAt = 0;
      this.hideSelectionMenu();
      if (this.onScrollState !== null) {
        this.onScrollState(0);
      }
      this.drawNow();
    }
  }

  /**
   * 是否为指针设备（鼠标/触控板）产生的触摸事件。
   * 指针点击光标应"立即落位"，不播放弹簧移动动画；手指点按保留动画。
   */
  private isPointerInput(event: TouchEvent): boolean {
    // 鼠标/触控板在 ArkUI 里可能同时合成 onTouch 与 onMouse；
    // 用"最近 800ms 内收到过鼠标事件"判定指针点击，避免依赖各版本不一定导出的 sourceTool 枚举。
    // 纯触摸设备不会触发 onMouse，因此电话/平板上的点按仍保留动画。
    return this.lastPointerAtMs > 0 && (Date.now() - this.lastPointerAtMs) < 800;
  }

  /** 无动画落光标（鼠标点击/触控板点击）：直接定位 + 上报 + 滚动跟随，不启动弹簧 */
  private placeCaretImmediately(offset: number): void {
    this.stopCaretAnimation();
    this.selMgr.collapse(offset);
    this.doc.moveCaret(offset);
    this.twDirty = true;
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(this.doc.caretOffset, this.lines,
      this.padLeftVp(), this.padTopVp(), this.theme.fontSize, CaretAffinity.DOWNSTREAM);
    this.caret.visible = true;
    this.caret.alpha = 1;
    this.emitSelection(false);
    this.followTypewriter();
    this.drawNow();
    this.reportCursor();
  }

  /** 长按选词后继续拖动：选区 = 词区间 ∪ [手指, 词]，方向自然翻转，anchor 不重置 */
  private extendWordSelection(x: number, y: number): void {
    if (this.wordSelStart < 0 || this.wordSelEnd < 0) {
      return;
    }
    const off: number = this.offsetAt(x, y);
    if (off < this.wordSelStart) {
      this.selMgr.setSelection(this.wordSelEnd, off);
    } else if (off > this.wordSelEnd) {
      this.selMgr.setSelection(this.wordSelStart, off);
    } else {
      this.selMgr.setSelection(this.wordSelStart, this.wordSelEnd);
    }
  }

  /** 手柄拖到视口上下边缘时按比例自动滚动；滚动后再由调用方重新命中 */
  private autoScrollForHandleDrag(y: number): void {
    const edge: number = 40;
    const step: number = Math.max(12, this.theme.lineHeight * 0.75);
    let moved: boolean = false;
    if (y < edge) {
      this.scrollY -= step;
      moved = true;
    } else if (y > this.viewHeightVp - edge) {
      this.scrollY += step;
      moved = true;
    }
    if (moved) {
      this.ensureLayoutThroughY(this.scrollY + this.viewHeightVp);
      this.clampScroll();
      this.ensureVisibleLayout();
    }
  }

  /** 鼠标拖选收口（组件内 Release 与拖出组件后的 onHover(false) 共用） */
  private finishMouseSelection(): void {
    if (!this.mouseSelecting) {
      return;
    }
    this.mouseSelecting = false;
    this.selMgr.endHandleDrag();
    this.selMgr.endDrag();
    this.syncSelectionToCaret();
    this.emitSelection(true);
    if (!this.selMgr.selection.isEmpty()) {
      this.showSelectionMenu();
    } else {
      this.hideSelectionMenu();
    }
    this.drawNow();
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
    this.stopCaretAnimation();
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
    // 记录词区间：长按/双击后继续拖动时按"词 ∪ 手指区间"扩展，而不是从按压点重选
    this.wordSelStart = start;
    this.wordSelEnd = end;
    this.ensureCaretLayout();
    this.caret = HitTester.caretPositionFor(end, this.lines, this.padLeftVp(), this.padTopVp(),
      this.theme.fontSize, this.selMgr.headAffinity);
    this.diag(source + ' offset=' + offset.toString() + ' sel=' + start.toString() + '-' + end.toString());
    this.emitSelection(true);
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

  private clampScroll(): void {
    if (this.cache === null) {
      return;
    }
    // 先补齐到当前视口底部，保证 cache.height 覆盖 scrollY + viewH；
    // 否则"空 cache → height=0 → scrollY 归零"会在改字号/改宽度时把页面打回顶部。
    this.ensureLayoutThroughY(this.scrollY + this.viewHeightVp);
    const maxScroll: number = Math.max(0, this.laidOutHeightVp() + this.tailPadVp() - this.viewHeightVp);
    if (this.scrollY > maxScroll) {
      this.scrollY = maxScroll;
    }
    const lead: number = this.leadPadVp();
    const minScroll: number = lead > 0 ? -lead : 0;
    if (this.scrollY < minScroll) {
      this.scrollY = minScroll;
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
    this.stopScrollAnimation();
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

  /** 已排版内容高度（组字期间用预览排版的精确高度，避免预览换行后滚动上限偏小） */
  private laidOutHeightVp(): number {
    if (this.previewMgr.isComposing && this.previewCache !== null) {
      return this.previewCache.height;
    }
    return this.cache !== null ? this.cache.height : 0;
  }

  /**
   * 生效滚动策略：打字机开启即 CENTER，否则用外部传入的 scrollPolicy。
   * 控制器可直接下发（applyTypewriter），因此优先读显式值，避免"prop 未及时刷新"。
   */
  // ===================== 打字机：段落识别 / 居中 / 淡化范围 =====================

  /** 段落起点：offset 之前最近的换行之后（不含 offset 处的换行） */
  private paragraphStartAt(text: string, offset: number): number {
    const at: number = Math.max(0, Math.min(offset, text.length));
    if (at === 0) {
      return 0;
    }
    const idx: number = text.lastIndexOf('\n', at - 1);
    return idx < 0 ? 0 : idx + 1;
  }

  /** 段落终点：offset 之后最近的换行（不含换行本身） */
  private paragraphEndAt(text: string, offset: number): number {
    const at: number = Math.max(0, Math.min(offset, text.length));
    const idx: number = text.indexOf('\n', at);
    return idx < 0 ? text.length : idx;
  }

  /**
   * 重新计算"当前段落"覆盖的行区间（打字机模式使用）。
   * 只在 dirty 时重算：text 扫描 + lineIndexOf 都是 O(段落长度/行数)，
   * 而 drawNow 在光标闪烁/动画时是 60fps 热路径。
   */
  private refreshTypewriterFocus(): void {
    if (this.effectivePolicy() !== ScrollPolicy.CENTER) {
      this.twValid = false;
      this.twDirty = false;
      return;
    }
    if (this.lines.length === 0) {
      this.twValid = false;
      return;
    }
    if (!this.twDirty && this.twValid &&
      this.twFirstLine < this.lines.length && this.twLastLine < this.lines.length) {
      return;
    }
    const text: string = this.doc.text;
    const caret: number = Math.max(0, Math.min(this.doc.caretOffset, text.length));
    const start: number = this.paragraphStartAt(text, caret);
    const end: number = this.paragraphEndAt(text, caret);
    const probe: number = end > start ? end - 1 : start;
    let first: number = HitTester.lineIndexOf(start, this.lines);
    let last: number = HitTester.lineIndexOf(probe, this.lines);
    if (first < 0) {
      // 理论上 lineIndexOf 会回退到最后一行；这里防御性处理"文档末尾空段"
      first = start >= text.length ? this.lines.length - 1 : 0;
    }
    if (last < 0) {
      last = first;
    }
    if (last < first) {
      last = first;
    }
    this.twFirstLine = Math.min(first, this.lines.length - 1);
    this.twLastLine = Math.min(last, this.lines.length - 1);
    this.twValid = true;
    this.twDirty = false;
    this.retargetTypewriterScale();
  }

  /**
   * 计算缩放/淡化用的焦点行边界（浮点）。
   * - 段落切换：从当前动画值平滑过渡到新段落；
   * - 快速连续切换：先取当前插值值作为新起点，避免动画堆积/回跳；
   * - 重新排版/切换文稿：直接吸附到新边界（行索引已变，做动画没有意义）。
   */
  private retargetTypewriterScale(): void {
    if (!this.twValid || this.effectivePolicy() !== ScrollPolicy.CENTER) {
      this.stopTypewriterScaleAnimation();
      this.twAnimFirst = -1;
      this.twAnimLast = -1;
      this.twTargetFirst = -1;
      this.twTargetLast = -1;
      this.twScaleInitialized = false;
      return;
    }
    const targetFirst: number = this.twFirstLine;
    const targetLast: number = this.twLastLine;
    if (this.twScaleInitialized && this.twTargetFirst === targetFirst && this.twTargetLast === targetLast) {
      return;
    }
    this.twTargetFirst = targetFirst;
    this.twTargetLast = targetLast;
    if (!this.twScaleInitialized || !this.theme.typewriterScaleAnimated || this.twScaleAnimator === null) {
      this.twAnimFirst = targetFirst;
      this.twAnimLast = targetLast;
      this.twScaleInitialized = true;
      this.stopTypewriterScaleAnimation();
      return;
    }
    const fromFirst: number = this.twAnimFirst;
    const fromLast: number = this.twAnimLast;
    this.stopTypewriterScaleAnimation();
    this.twScaleAnimator.animate(this.theme.typewriterScaleDurationMs, 'ease-out',
      (p: number) => {
        this.twAnimFirst = fromFirst + (targetFirst - fromFirst) * p;
        this.twAnimLast = fromLast + (targetLast - fromLast) * p;
        this.drawNow();
      },
      () => {
        this.twAnimFirst = targetFirst;
        this.twAnimLast = targetLast;
        this.drawNow();
      });
  }

  /** 立即吸附到当前段落边界（重新排版/关闭打字机时用，避免用旧行索引做动画） */
  private snapTypewriterScale(): void {
    this.stopTypewriterScaleAnimation();
    this.twTargetFirst = this.twFirstLine;
    this.twTargetLast = this.twLastLine;
    this.twAnimFirst = this.twFirstLine;
    this.twAnimLast = this.twLastLine;
    this.twScaleInitialized = this.twValid;
  }

  private stopTypewriterScaleAnimation(): void {
    if (this.twScaleAnimator !== null) {
      this.twScaleAnimator.stop();
    }
  }

  /**
   * 打字机模式的目标滚动位置（内容坐标）：
   * - 段落整体能放进视口 80% → 整段垂直居中（这正是"当前段落居中"的语义）；
   * - 段落超长 → 以光标所在行居中，保证正在书写的那一行始终在中间，不会把光标甩出视口。
   * 顶部预留 leadPadVp()，因此首段也能居中（scrollY 允许为负）。
   */
  private typewriterScrollTarget(caretTop: number, caretH: number): number {
    this.refreshTypewriterFocus();
    // 光标行垂直居中：每换一行（含同一段落内的软换行）画面就平滑跟随一行，
    // 不再以"整段中心"为目标（段落只决定缩放/淡化层级，不决定滚动单位）。
    return caretTop + caretH / 2 - this.viewHeightVp / 2;
  }

  /**
   * 光标落到新位置后（点击 / 键盘 / 控制器），打字机模式下让"新的当前段落"立即居中。
   * 普通模式不主动滚动，保持原有"仅在越界时可见"的行为。
   */
  private followTypewriter(): void {
    if (this.effectivePolicy() === ScrollPolicy.CENTER) {
      this.ensureCaretVisible(ScrollPolicy.CENTER);
    }
  }

  /** 打字机顶部预留空间：让首段/少段落也能滚到视口中央（关闭时为 0） */
  private leadPadVp(): number {
    return this.effectivePolicy() === ScrollPolicy.CENTER ? this.viewHeightVp / 2 : 0;
  }

  private effectivePolicy(): ScrollPolicy {
    // 显式覆盖（控制器下发）优先，且 OFF 时强制 NORMAL：
    // 避免 store→prop 传播的一帧延迟里，override=0 但 scrollPolicy 仍是 CENTER。
    if (this.typewriterOverride === 1) {
      return ScrollPolicy.CENTER;
    }
    if (this.typewriterOverride === 0) {
      return ScrollPolicy.NORMAL;
    }
    return this.typewriter ? ScrollPolicy.CENTER : this.scrollPolicy;
  }

  /** 当前是否打字机模式（按钮状态/诊断共用） */
  isTypewriterOn(): boolean {
    return this.effectivePolicy() === ScrollPolicy.CENTER;
  }

  /**
   * 应用打字机开关：立即重排 + 把光标带到中间带，给出即时视觉反馈。
   * 由控制器（工具栏按钮）调用；prop 变化也走同一入口。
   */
  applyTypewriter(on: boolean): void {
    this.typewriterOverride = on ? 1 : 0;
    this.twDirty = true;
    this.twScaleInitialized = false;
    this.stopTypewriterScaleAnimation();
    if (!this.initialized) {
      return;
    }
    // 进入/退出打字机时文本列宽变化（为放大预留空间）：重建排版并保留阅读位置
    // 只在模式切换时重排一次；段落切换只走绘制层缩放，不会触发布局抖动。
    const anchor: ViewAnchor = this.captureViewAnchor();
    this.preferredX = -1;
    this.cache = null;
    this.renderer = null;
    this.ensureEngine();
    if (this.renderer !== null) {
      this.relayoutPreservingAnchor(anchor);
    }
    this.ensureCaretLayout();
    if (!on) {
      // 关闭：取消顶部预留（负滚动会失去意义），再按普通策略把光标带回视口。
      // 不重置到文首 —— 保留用户当前阅读位置。
      if (this.scrollY < 0) {
        this.scrollY = 0;
      }
      this.ensureCaretVisible(ScrollPolicy.NORMAL);
    } else {
      // 开启：立即重算段落区间并居中（不等下一次输入）
      this.ensureCaretVisible(ScrollPolicy.CENTER);
    }
    this.drawNow();
    this.reportCursor();
  }

  /** @Prop typewriter 变化：同步覆盖值并立即生效 */
  private onTypewriterPropChanged(): void {
    this.applyTypewriter(this.typewriter);
  }

  /**
   * 使光标在当前视口内可见（T007）；CENTER 为打字机模式的"中间带"跟随。
   *
   * 参考 OpenHarmony rich_editor_scroll_controller：只在越界时滚、并留固定边距；
   * 打字机场景额外要求"当前行在中间带内"：光标离开 [0.35H, 0.65H] 才把行滚到中心，
   * 避免每敲一个字都整屏跳半行（旧实现每键严格居中 = 明显的文字漂移源）。
   */
  private ensureCaretVisible(policy: ScrollPolicy): void {
    if (this.viewHeightVp <= 0 || this.cache === null) {
      return;
    }
    const caretH: number = Math.max(1, this.caret.height);
    const caretTop: number = this.caret.y;
    const caretBottom: number = caretTop + caretH;
    let target: number = this.scrollY;
    if (policy === ScrollPolicy.CENTER) {
      // 打字机：以"当前段落"为居中单位（超长段落退化为光标行居中）
      target = this.typewriterScrollTarget(caretTop, caretH);
    } else {
      const margin: number = Math.max(this.theme.lineHeight, 8);
      if (caretTop < this.scrollY + margin) {
        target = caretTop - margin;
      } else if (caretBottom > this.scrollY + this.viewHeightVp - margin) {
        target = caretBottom - this.viewHeightVp + margin;
      }
    }
    // 先按目标位置扩展排版，再取精确上限；不能用估算高度
    this.ensureLayoutThroughY(Math.max(target, this.scrollY) + this.viewHeightVp);
    const maxScroll: number = Math.max(0, this.laidOutHeightVp() + this.tailPadVp() - this.viewHeightVp);
    // 打字机模式允许负 scrollY（顶部留白），使首段也能居中；关闭时 minScroll=0
    const lead: number = this.leadPadVp();
    const minScroll: number = lead > 0 ? -lead : 0;
    if (target < minScroll) {
      target = minScroll;
    }
    if (target > maxScroll) {
      target = maxScroll;
    }
    if (Math.abs(target - this.scrollY) > 0.5) {
      this.diag('scroll policy=' + (policy === ScrollPolicy.CENTER ? 'CENTER' : 'NORMAL') +
        ' caretY=' + caretTop.toFixed(1) + ' scrollY=' + this.scrollY.toFixed(1) +
        ' target=' + target.toFixed(1) + ' max=' + maxScroll.toFixed(1));
      // 打字机逐行移动：目标只差一行左右时直接对齐（不播放动画），
      // 既避免快速输入时滚动动画排队/滞后，也让"每移动一行画面变化一次"干净利落。
      const oneLineStep: number = this.theme.lineStep();
      const nearLineStep: boolean = policy === ScrollPolicy.CENTER &&
        Math.abs(target - this.scrollY) <= oneLineStep * 1.5;
      if (this.instantScroll || nearLineStep) {
        this.scrollY = target;
        this.ensureVisibleLayout();
      } else {
        this.scrollToAnimated(target);
      }
    }
  }

  /** 停止滚动跟随动画 */
  private stopScrollAnimation(): void {
    if (this.scrollAnimator !== null) {
      this.scrollAnimator.stop();
    }
  }

  /**
   * 平滑滚动到 target（160ms ease-out）。
   * 与惯性滑动互斥；逐帧重排可视区以保证新出现的行可见。
   */
  private scrollToAnimated(target: number): void {
    if (this.scrollAnimator === null) {
      this.scrollY = target;
      this.clampScroll();
      this.ensureVisibleLayout();
      this.drawNow();
      return;
    }
    this.stopFling();
    this.stopScrollAnimation();
    const from: number = this.scrollY;
    this.scrollAnimator.animate(160, 'ease-out', (p: number) => {
      const t: number = Math.min(1, Math.max(0, p));
      const eased: number = 1 - Math.pow(1 - t, 3);
      this.scrollY = from + (target - from) * eased;
      this.ensureVisibleLayout();
      this.drawNow();
    }, () => {
        this.scrollY = target;
      this.clampScroll();
      this.ensureVisibleLayout();
      this.drawNow();
      this.reportCursor();
    });
  }

  /**
   * 呼吸光标：用余弦缓变 alpha（0.5 → 1 → 0.5），周期 2.4s、约 16fps 刷新。
   * 相比旧的 600ms 硬闪烁：没有全灭帧、明暗过渡连续，长时间注视更柔和。
   * 光标移动动画期间保持实心（alpha=1），到位后继续呼吸，避免移动时"忽明忽暗"。
   */
  private startBlink(): void {
    this.stopBlink();
    this.caret.visible = true;
    this.caret.alpha = 1;
    this.breathPhase = 0;
    this.blinkTimer = setInterval(() => {
      if (!this.focused || this.caretAnimating) {
        return;
      }
      this.breathPhase += this.theme.caretBreathStepMs / this.theme.caretBreathPeriodMs;
      if (this.breathPhase >= 1) {
        this.breathPhase -= 1;
      }
      // 余弦：0 → 1 → 0 的平滑波形，映射到 [0.5, 1]
      const wave: number = 0.5 - 0.5 * Math.cos(this.breathPhase * Math.PI * 2);
      this.caret.alpha = 0.5 + 0.5 * wave;
      this.drawNow();
    }, this.theme.caretBreathStepMs);
  }

  private stopBlink(): void {
    if (this.blinkTimer >= 0) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
    this.caret.alpha = 1;
  }

  // ================= EditCommandHost 落点（命令层唯一执行入口） =================

  /** 键盘兜底插入：先登记 40ms 回声窗口，再写入正文（IME 若随后回调同文本会被丢弃） */
  private insertFromKeyboard(text: string): void {
    if (text.length === 0) {
      return;
    }
    this.echoGuard.recordKeyboardFallback(text, Date.now());
    this.insertExternalText(text);
  }

  /**
   * 旧指令执行器：命令层把 EditCommand 映射为既有 KeyAction 后复用同一段执行逻辑，
   * 避免"命令表一套、执行路径另一套"的双实现漂移。
   */
  private dispatchLegacy(action: KeyAction, shift: boolean): void {
    const cmd: KeyboardEvent = new KeyboardEvent();
    cmd.action = action;
    cmd.shift = shift;
    this.applyKeyCommand(cmd);
  }

  /** 命令分发（唯一分发点）：输入事件不得绕过 router 直接改文档 */
  private dispatchCommand(cmd: EditCommand): boolean {
    return this.commandRouter.dispatch(cmd, this.editHost());
  }

  private editHost(): EditCommandHost {
    if (this.hostAdapter === null) {
      this.hostAdapter = new CanvasEditCommandHost(this);
    }
    return this.hostAdapter;
  }

  /**
   * 收到按键即校正焦点状态（契约 §2.2）。
   * 框架能把按键派发到本组件就代表已获焦；旧实现用内部 focused 标志丢弃按键，
   * 正是电脑模式"点进编辑器后敲键盘没反应"的根因之一。
   */
  private adoptKeyFocus(): void {
    if (!this.focused) {
      this.focused = true;
      this.caret.visible = true;
      this.startBlink();
    }
    this.focusConfirmed = true;
  }

  /** 按词移动（Ctrl+←/→）：以字素簇边界为准，不切碎 emoji/组合字符 */
  private moveWordOnce(direction: number, extend: boolean): void {
    const sel: SelectionInfo = this.selMgr.selection;
    if (extend) {
      const head: number = direction < 0 ? this.wordBoundaryLeft(this.doc.text, this.selMgr.head) :
        this.wordBoundaryRight(this.doc.text, this.selMgr.head);
      this.selectTo(head);
      return;
    }
    if (!sel.isEmpty()) {
      // 有选区时按词移动先收起选区到对应端（与系统编辑框一致）
      this.selMgr.collapse(direction < 0 ? sel.startOffset : sel.endOffset);
      this.doc.moveCaret(this.selMgr.head);
      this.afterCaretMove();
      return;
    }
    const target: number = direction < 0 ? this.wordBoundaryLeft(this.doc.text, this.doc.caretOffset) :
      this.wordBoundaryRight(this.doc.text, this.doc.caretOffset);
    this.selMgr.collapse(target);
    this.doc.moveCaret(target);
    this.afterCaretMove();
  }

  /** Ctrl+Backspace：按词删除（有选区时删选区） */
  private deleteWordBackwardFromKeyboard(): void {
    const sel: SelectionInfo = this.selMgr.selection;
    if (!sel.isEmpty()) {
      this.deleteByKeyboard(this.doc.caretOffset, true, true);
      return;
    }
    const start: number = this.wordBoundaryLeft(this.doc.text, this.doc.caretOffset);
    if (start >= this.doc.caretOffset) {
      return;
    }
    this.oldLines = this.lines;
    this.lastEditOffset = start;
    this.doc.delete(start, this.doc.caretOffset);
    this.selMgr.collapse(this.doc.caretOffset);
    this.previewMgr.cancel();
    this.afterEdit();
    if (this.onTextChange !== null) {
      this.onTextChange(this.doc.text, this.doc.version);
    }
  }

  /** 词左边界：先跳过空白/标点，再跳过词字符（CJK/字母/数字/下划线） */
  private wordBoundaryLeft(text: string, offset: number): number {
    let at: number = GraphemeUtil.snapToBoundary(text, offset);
    while (at > 0) {
      const prev: number = GraphemeUtil.moveLeft(text, at);
      if (this.isWordCodeAt(text, prev)) {
        break;
      }
      at = prev;
    }
    while (at > 0) {
      const prev: number = GraphemeUtil.moveLeft(text, at);
      if (!this.isWordCodeAt(text, prev)) {
        break;
      }
      at = prev;
    }
    return at;
  }

  /** 词右边界：与 wordBoundaryLeft 对称 */
  private wordBoundaryRight(text: string, offset: number): number {
    let at: number = GraphemeUtil.snapToBoundary(text, offset);
    while (at < text.length) {
      if (this.isWordCodeAt(text, at)) {
        break;
      }
      const next: number = GraphemeUtil.moveRight(text, at);
      if (next <= at) {
        break;
      }
      at = next;
    }
    while (at < text.length) {
      if (!this.isWordCodeAt(text, at)) {
        break;
      }
      const next: number = GraphemeUtil.moveRight(text, at);
      if (next <= at) {
        break;
      }
      at = next;
    }
    return at;
  }

  /** 词字符判定（CJK 汉字 / 拉丁字母 / 数字 / 下划线；与命中选词口径一致） */
  private isWordCodeAt(text: string, offset: number): boolean {
    if (offset < 0 || offset >= text.length) {
      return false;
    }
    const code: number | undefined = text.codePointAt(offset);
    if (code === undefined) {
      return false;
    }
    if (code >= 0x30 && code <= 0x39) {
      return true;
    }
    if (code >= 0x41 && code <= 0x5A) {
      return true;
    }
    if (code >= 0x61 && code <= 0x7A) {
      return true;
    }
    if (code === 0x5F) {
      return true;
    }
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true;
    }
    if (code >= 0x3400 && code <= 0x4DBF) {
      return true;
    }
    return false;
  }

  /** PageUp/PageDown：整屏滚动（只改滚动，不改光标） */
  private scrollByPage(direction: number): void {
    this.stopFling();
    this.stopScrollAnimation();
    this.hideSelectionMenu();
    const step: number = Math.max(this.theme.lineHeight, this.viewHeightVp * 0.9);
    this.scrollY += direction * step;
    this.ensureLayoutThroughY(this.scrollY + this.viewHeightVp);
    this.clampScroll();
    this.ensureVisibleLayout();
    this.drawNow();
    this.reportCursor();
    if (this.onScrollState !== null) {
      this.onScrollState(direction > 0 ? 1 : -1);
    }
  }

  /** 浮层键盘操作：Esc 关闭 / 方向键移动高亮 / Enter 执行（契约 §2.5） */
  private handleMenuKey(cmd: EditCommand): boolean {
    if (cmd.kind === EditCommandKind.DISMISS) {
      this.hideSelectionMenu();
      return true;
    }
    if (cmd.kind === EditCommandKind.MOVE_LEFT || cmd.kind === EditCommandKind.MOVE_UP) {
      this.moveMenuHighlight(-1);
      return true;
    }
    if (cmd.kind === EditCommandKind.MOVE_RIGHT || cmd.kind === EditCommandKind.MOVE_DOWN) {
      this.moveMenuHighlight(1);
      return true;
    }
    if (cmd.kind === EditCommandKind.INSERT_TEXT && cmd.text === '\n') {
      this.activateMenuItem(this.menuIndex);
      return true;
    }
    // 其它按键（含 Tab）：先收起浮层，再交还正常链路 / 焦点遍历
    this.hideSelectionMenu();
    return false;
  }

  private moveMenuHighlight(delta: number): void {
    const count: number = this.menuLabels().length;
    if (count <= 0) {
      return;
    }
    this.menuIndex = (this.menuIndex + delta + count) % count;
  }

  /** 浮层项顺序：与 selectionMenu() 的两行 ForEach 一致 */
  private menuLabels(): string[] {
    return ['撤销', '重做', '粗', '斜', '标题', '复制', '剪切', '粘贴', '全选', '查找', '分享'];
  }

  /** 浮层项执行：统一走命令（撤销/格式/剪贴板/查找），分享仍走宿主回调 */
  private activateMenuItem(index: number): void {
    this.hideSelectionMenu();
    let kind: EditCommandKind = EditCommandKind.NONE;
    if (index === 0) {
      kind = EditCommandKind.UNDO;
    } else if (index === 1) {
      kind = EditCommandKind.REDO;
    } else if (index === 2) {
      kind = EditCommandKind.TOGGLE_BOLD;
    } else if (index === 3) {
      kind = EditCommandKind.TOGGLE_ITALIC;
    } else if (index === 4) {
      kind = EditCommandKind.TOGGLE_HEADING;
    } else if (index === 5) {
      kind = EditCommandKind.COPY;
    } else if (index === 6) {
      kind = EditCommandKind.CUT;
    } else if (index === 7) {
      kind = EditCommandKind.PASTE;
    } else if (index === 8) {
      kind = EditCommandKind.SELECT_ALL;
    } else if (index === 9) {
      kind = EditCommandKind.FIND;
    } else {
      this.shareSelection();
      return;
    }
    this.dispatchCommand(new EditCommand(kind, '', EditorInputSource.POINTER));
  }

  // ---- EditCommandHost 公开落点（供 CanvasEditCommandHost 适配器转调） ----

  hostInsertText(text: string): void { this.insertFromKeyboard(text); }
  hostDeleteBackward(): void { this.dispatchLegacy(KeyAction.DELETE_BACKWARD, false); }
  hostDeleteForward(): void { this.dispatchLegacy(KeyAction.DELETE_FORWARD, false); }
  hostDeleteWordBackward(): void { this.deleteWordBackwardFromKeyboard(); }
  hostMoveLeft(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_LEFT, extend); }
  hostMoveRight(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_RIGHT, extend); }
  hostMoveUp(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_UP, extend); }
  hostMoveDown(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_DOWN, extend); }
  hostMoveWordLeft(extend: boolean): void { this.moveWordOnce(-1, extend); }
  hostMoveWordRight(extend: boolean): void { this.moveWordOnce(1, extend); }
  hostMoveLineStart(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_LINE_START, extend); }
  hostMoveLineEnd(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_LINE_END, extend); }
  hostMoveDocStart(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_DOC_START, extend); }
  hostMoveDocEnd(extend: boolean): void { this.dispatchLegacy(KeyAction.MOVE_DOC_END, extend); }
  hostPageUp(): void { this.scrollByPage(-1); }
  hostPageDown(): void { this.scrollByPage(1); }
  hostSelectAll(): void { this.dispatchLegacy(KeyAction.SELECT_ALL, false); }
  hostCopy(): void { this.dispatchLegacy(KeyAction.COPY, false); }
  hostCut(): void { this.dispatchLegacy(KeyAction.CUT, false); }
  hostPaste(): void { this.dispatchLegacy(KeyAction.PASTE, false); }
  hostUndo(): void { this.dispatchLegacy(KeyAction.UNDO, false); }
  hostRedo(): void { this.dispatchLegacy(KeyAction.REDO, false); }
  hostToggleBold(): void { this.toggleInlineStyle(StyleKind.BOLD); }
  hostToggleItalic(): void { this.toggleInlineStyle(StyleKind.ITALIC); }
  hostToggleHeading(): void { this.toggleParagraphStyle(1); }
  hostSave(): void {
    if (this.onRequestSave !== null) {
      this.onRequestSave();
    }
  }
  hostFind(): void { this.findSelection(); }
  hostDismiss(): boolean {
    if (this.menuVisible) {
      this.hideSelectionMenu();
      return true;
    }
    return false;
  }

  hostToggleImmersive(): void {
    if (this.onToggleImmersive !== null) {
      this.onToggleImmersive();
    }
  }
}

/**
 * EditCommandHost 薄适配器。
 * ArkTS 的 struct 不参与 class 的 implements 检查，故用本类把命令协议转调
 * CanvasTextEditor 的公开落点方法；协议方法只收发基本类型，不跨层传 class 实例。
 */
class CanvasEditCommandHost implements EditCommandHost {
  private target: CanvasTextEditor;

  constructor(target: CanvasTextEditor) {
    this.target = target;
  }

  insertText(text: string): void { this.target.hostInsertText(text); }
  deleteBackward(): void { this.target.hostDeleteBackward(); }
  deleteForward(): void { this.target.hostDeleteForward(); }
  deleteWordBackward(): void { this.target.hostDeleteWordBackward(); }
  moveLeft(extend: boolean): void { this.target.hostMoveLeft(extend); }
  moveRight(extend: boolean): void { this.target.hostMoveRight(extend); }
  moveUp(extend: boolean): void { this.target.hostMoveUp(extend); }
  moveDown(extend: boolean): void { this.target.hostMoveDown(extend); }
  moveWordLeft(extend: boolean): void { this.target.hostMoveWordLeft(extend); }
  moveWordRight(extend: boolean): void { this.target.hostMoveWordRight(extend); }
  moveLineStart(extend: boolean): void { this.target.hostMoveLineStart(extend); }
  moveLineEnd(extend: boolean): void { this.target.hostMoveLineEnd(extend); }
  moveDocStart(extend: boolean): void { this.target.hostMoveDocStart(extend); }
  moveDocEnd(extend: boolean): void { this.target.hostMoveDocEnd(extend); }
  pageUp(): void { this.target.hostPageUp(); }
  pageDown(): void { this.target.hostPageDown(); }
  selectAll(): void { this.target.hostSelectAll(); }
  copy(): void { this.target.hostCopy(); }
  cut(): void { this.target.hostCut(); }
  paste(): void { this.target.hostPaste(); }
  undo(): void { this.target.hostUndo(); }
  redo(): void { this.target.hostRedo(); }
  toggleBold(): void { this.target.hostToggleBold(); }
  toggleItalic(): void { this.target.hostToggleItalic(); }
  toggleHeading(): void { this.target.hostToggleHeading(); }
  save(): void { this.target.hostSave(); }
  find(): void { this.target.hostFind(); }
  dismiss(): boolean { return this.target.hostDismiss(); }
  toggleImmersive(): void { this.target.hostToggleImmersive(); }
}
