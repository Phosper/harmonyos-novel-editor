/**
 * 编辑器统一命令（契约 §2 交互归一）
 *
 * 输入层（触摸 / 鼠标 / 键盘 / 输入法 / 外接键盘）只负责把事件翻译成 EditCommand，
 * 再由 EditorCommandRouter 单点分发到 EditCommandHost 执行；输入层不写业务分支。
 *
 * 命名约束：ArkTS 禁止跨文件顶层类型重名，且不得与系统类型撞名，
 * 故修饰键/输入源分别使用 EditorModifiers / EditorInputSource 前缀。
 */

/** 归一化后的编辑命令种类（与契约 §2 列举顺序一致） */
export enum EditCommandKind {
  NONE = 0,
  INSERT_TEXT = 1,
  DELETE_BACKWARD = 2,
  DELETE_FORWARD = 3,
  DELETE_WORD_BACKWARD = 4,
  MOVE_LEFT = 5,
  MOVE_RIGHT = 6,
  MOVE_UP = 7,
  MOVE_DOWN = 8,
  MOVE_WORD_LEFT = 9,
  MOVE_WORD_RIGHT = 10,
  MOVE_LINE_START = 11,
  MOVE_LINE_END = 12,
  MOVE_DOC_START = 13,
  MOVE_DOC_END = 14,
  PAGE_UP = 15,
  PAGE_DOWN = 16,
  SELECT_ALL = 17,
  COPY = 18,
  CUT = 19,
  PASTE = 20,
  UNDO = 21,
  REDO = 22,
  TOGGLE_BOLD = 23,
  TOGGLE_ITALIC = 24,
  TOGGLE_HEADING = 25,
  SAVE = 26,
  FIND = 27,
  DISMISS = 28,
  /** 沉浸编辑开关（F11）：只切换界面状态，不改正文 */
  TOGGLE_IMMERSIVE = 29
}

/** 命令来自哪类输入方式（只影响策略，不影响执行结果） */
export enum EditorInputSource {
  TOUCH = 0,
  POINTER = 1,
  KEYBOARD = 2,
  IME = 3
}

/** 修饰键快照：键盘/鼠标/快捷键共用，避免各输入分支各读一份 */
export class EditorModifiers {
  ctrl: boolean = false;
  shift: boolean = false;
  alt: boolean = false;
  /** Meta/Command（Mac 布局外接键盘；与 Ctrl 同义处理） */
  meta: boolean = false;

  /** 主修饰键：Ctrl 或 Meta 任一按下 */
  get primary(): boolean {
    return this.ctrl || this.meta;
  }

  get none(): boolean {
    return !this.ctrl && !this.shift && !this.alt && !this.meta;
  }

  clone(): EditorModifiers {
    const out: EditorModifiers = new EditorModifiers();
    out.ctrl = this.ctrl;
    out.shift = this.shift;
    out.alt = this.alt;
    out.meta = this.meta;
    return out;
  }
}

/** 一次编辑意图（命令对象）：输入层 → router → host，禁止在中间层改写语义 */
export class EditCommand {
  kind: EditCommandKind = EditCommandKind.NONE;
  /** 仅 INSERT_TEXT 使用的待插入文本 */
  text: string = '';
  mods: EditorModifiers = new EditorModifiers();
  source: EditorInputSource = EditorInputSource.KEYBOARD;
  /** 是否为按住不放的重复触发（用于未来按键加速策略，当前不影响语义） */
  repeat: boolean = false;

  constructor(kind: EditCommandKind = EditCommandKind.NONE, text: string = '',
    source: EditorInputSource = EditorInputSource.KEYBOARD) {
    this.kind = kind;
    this.text = text;
    this.source = source;
  }
}

/**
 * 走位类命令：这类键在 onKeyPreIme 阶段必须截获，
 * 否则编辑框获焦时会被输入法当作"候选词导航"消费掉（PC/外接键盘方向键失效的根因之一）。
 */
export function isCaretCommand(kind: EditCommandKind): boolean {
  return kind === EditCommandKind.MOVE_LEFT || kind === EditCommandKind.MOVE_RIGHT ||
    kind === EditCommandKind.MOVE_UP || kind === EditCommandKind.MOVE_DOWN ||
    kind === EditCommandKind.MOVE_WORD_LEFT || kind === EditCommandKind.MOVE_WORD_RIGHT ||
    kind === EditCommandKind.MOVE_LINE_START || kind === EditCommandKind.MOVE_LINE_END ||
    kind === EditCommandKind.MOVE_DOC_START || kind === EditCommandKind.MOVE_DOC_END ||
    kind === EditCommandKind.PAGE_UP || kind === EditCommandKind.PAGE_DOWN;
}

/** 会改写正文/格式或文档状态的命令（IME 不可用时需要在键盘层兜底） */
export function isEditingCommand(kind: EditCommandKind): boolean {
  return kind === EditCommandKind.INSERT_TEXT ||
    kind === EditCommandKind.DELETE_BACKWARD ||
    kind === EditCommandKind.DELETE_FORWARD ||
    kind === EditCommandKind.DELETE_WORD_BACKWARD ||
    kind === EditCommandKind.CUT ||
    kind === EditCommandKind.PASTE ||
    kind === EditCommandKind.UNDO ||
    kind === EditCommandKind.REDO ||
    kind === EditCommandKind.TOGGLE_BOLD ||
    kind === EditCommandKind.TOGGLE_ITALIC ||
    kind === EditCommandKind.TOGGLE_HEADING;
}
