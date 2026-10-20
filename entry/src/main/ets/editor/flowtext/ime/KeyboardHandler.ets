/**
 * FlowText 物理键盘处理（PC / 平板外接键盘）
 *
 * ## 为什么需要这一层
 * IME Kit 只覆盖**软键盘**输入（insertText / deleteLeft / deleteRight / moveCursor）。
 * 电脑端（2in1）接物理键盘时，系统不会把按键转成 IME 回调——那些事件走
 * ArkUI 的 `onKeyEvent`。缺少这层处理的表现是：电脑端能点、能显示光标，
 * 但**敲键盘完全没反应**（输入、删除、移动光标都不生效）。
 *
 * ## 归一化设计
 * 手机与电脑的输入最终都归一到同一组"编辑意图"，由文档模型统一执行：
 *   insertText / deleteBackward / deleteForward / moveCaret / selectAll / undo / redo
 * 触摸走 IME → 本类 → TextDocument；物理键盘走 onKeyEvent → 本类 → TextDocument。
 * 两条链路共用 TextDocument，故行为一致（同一套字素簇边界逻辑）。
 *
 * 注意：物理键盘的按键**不应**同时交给 IME 处理，否则会双输。
 * 本类处理完后调用 stopPropagation()阻止冒泡，并让宿主不要重复走 IME。
 */
import { KeyCode } from '@kit.InputKit';

/*
 * 少数键码在个别 SDK 版本的 KeyCode 中没有稳定导出符号（Home/End/标点区），
 * 这里按官方 js-apis-keycode（API 26）的数值定义本地常量：
 *   KEYCODE_GRAVE=2056、KEYCODE_MINUS=2057、KEYCODE_SLASH=2064、KEYCODE_AT=2065、KEYCODE_PLUS=2066、
 *   KEYCODE_MOVE_HOME=2081、KEYCODE_MOVE_END=2082。
 * 数值以官方文档为准；不要凭记忆改。
 */
const KEY_GRAVE: number = 2056;
const KEY_MINUS: number = 2057;
const KEY_SLASH: number = 2064;
const KEY_AT: number = 2065;
const KEY_PLUS: number = 2066;
const KEY_MOVE_HOME: number = 2081;
const KEY_MOVE_END: number = 2082;

/** 归一化后的编辑意图 */
export enum KeyAction {
  NONE = 0,
  /** 插入文本（携带 text） */
  INSERT = 1,
  /** 向后删除（Backspace） */
  DELETE_BACKWARD = 2,
  /** 向前删除（Delete） */
  DELETE_FORWARD = 3,
  /** 按字符移动光标 */
  MOVE_LEFT = 4,
  MOVE_RIGHT = 5,
  /** 按行移动光标（上下键） */
  MOVE_UP = 6,
  MOVE_DOWN = 7,
  /** 移动到行首 */
  MOVE_LINE_START = 8,
  /** 移动到行尾 */
  MOVE_LINE_END = 9,
  /** 移动到文首 */
  MOVE_DOC_START = 10,
  /** 移动到文末 */
  MOVE_DOC_END = 11,
  /** 全选 */
  SELECT_ALL = 12,
  /** 撤销 */
  UNDO = 13,
  /** 重做 */
  REDO = 14,
  /** 复制（Ctrl+C） */
  COPY = 16,
  /** 剪切（Ctrl+X） */
  CUT = 17,
  /** 粘贴（Ctrl+V） */
  PASTE = 18,
  /** 退格删除选区（无选区时等于 DELETE_BACKWARD） */
  NONE_PASSTHROUGH = 15
}

export class KeyboardEvent {
  action: KeyAction = KeyAction.NONE;
  /** INSERT 时携带的文本 */
  text: string = '';
  /** 是否带 Ctrl（用于区分 Ctrl+Z 与普通 Z） */
  ctrl: boolean = false;
  /** 是否带 Shift */
  shift: boolean = false;
}

export class KeyboardHandler {
  /**
   * 把一次按键事件翻译为编辑意图。
   *
   * @param keyCode KeyCode 常量
   * @param keyText 按键文本（字符键为实际字符，如 'a'、'中'）
   * @param typeDown 是否为按下（Up 事件忽略，避免长按重复触发）
   * @param ctrl / shift / alt 修饰键状态
   */
  static translate(keyCode: number, keyText: string, typeDown: boolean,
    ctrl: boolean, shift: boolean, alt: boolean): KeyboardEvent {
    const out: KeyboardEvent = new KeyboardEvent();
    if (!typeDown) {
      return out;
    }
    out.ctrl = ctrl;
    out.shift = shift;

    // 组合键优先（Ctrl+Z / Ctrl+Y / Ctrl+A 等）
    if (ctrl) {
      switch (keyCode) {
        case KEY_MOVE_HOME:
          out.action = KeyAction.MOVE_DOC_START;
          return out;
        case KEY_MOVE_END:
          out.action = KeyAction.MOVE_DOC_END;
          return out;
        case KeyCode.KEYCODE_A:
          out.action = KeyAction.SELECT_ALL;
          return out;
        case KeyCode.KEYCODE_Z:
          // Ctrl+Shift+Z 为重做
          out.action = shift ? KeyAction.REDO : KeyAction.UNDO;
          return out;
        case KeyCode.KEYCODE_Y:
          out.action = KeyAction.REDO;
          return out;
        case KeyCode.KEYCODE_C:
          out.action = KeyAction.COPY;
          return out;
        case KeyCode.KEYCODE_X:
          out.action = KeyAction.CUT;
          return out;
        case KeyCode.KEYCODE_V:
          out.action = KeyAction.PASTE;
          return out;
        default:
          return out;
      }
    }
    // Alt 组合留给系统（Alt+Tab 等），不拦截
    if (alt) {
      return out;
    }

    switch (keyCode) {
      case KeyCode.KEYCODE_DEL:
        out.action = KeyAction.DELETE_BACKWARD;
        return out;
      case KeyCode.KEYCODE_FORWARD_DEL:
        out.action = KeyAction.DELETE_FORWARD;
        return out;
      case KeyCode.KEYCODE_DPAD_LEFT:
        // Shift+左 = 按词选择；本实现按字符移动 + 后续可扩展选区
        out.action = KeyAction.MOVE_LEFT;
        return out;
      case KeyCode.KEYCODE_DPAD_RIGHT:
        out.action = KeyAction.MOVE_RIGHT;
        return out;
      case KeyCode.KEYCODE_DPAD_UP:
        out.action = KeyAction.MOVE_UP;
        return out;
      case KeyCode.KEYCODE_DPAD_DOWN:
        out.action = KeyAction.MOVE_DOWN;
        return out;
      case KEY_MOVE_HOME:
        out.action = KeyAction.MOVE_LINE_START;
        return out;
      case KEY_MOVE_END:
        out.action = KeyAction.MOVE_LINE_END;
        return out;
      case KeyCode.KEYCODE_ENTER:
      case KeyCode.KEYCODE_NUMPAD_ENTER:
        // 回车插入换行（与软键盘的 enterKeyType=NONE 行为一致）
        out.action = KeyAction.INSERT;
        out.text = '\n';
        return out;
      case KeyCode.KEYCODE_TAB:
        // Tab 必须交还框架焦点遍历（契约 §2.3）：不产生编辑命令，由调用方 return false 放行
        out.action = KeyAction.NONE_PASSTHROUGH;
        return out;
      case KeyCode.KEYCODE_ESCAPE:
        out.action = KeyAction.NONE_PASSTHROUGH;
        return out;
      default:
        break;
    }

    // 字符键：keyText 非空且非控制字符时插入。
    // 需排除 Shift/Ctrl/Alt 等修饰键本身（它们 keyText 可能是 'Shift' 等）。
    if (keyText.length === 1 && KeyboardHandler.isPrintableKey(keyCode)) {
      out.action = KeyAction.INSERT;
      out.text = shift ? KeyboardHandler.toUpper(keyText) : keyText;
      return out;
    }
    // 数字键兜底：keyText 缺失时按 keyCode 推出 0-9（与 ShortcutMap 口径一致）
    const digit: string = KeyboardHandler.digitFromKeyCode(keyCode);
    if (digit !== '') {
      out.action = KeyAction.INSERT;
      out.text = digit;
      return out;
    }
    return out;
  }

  /** 数字键兜底：keyText 缺失时按 keyCode 推出 0-9 */
  private static digitFromKeyCode(keyCode: number): string {
    if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
      return String.fromCharCode(0x30 + (keyCode - KeyCode.KEYCODE_0));
    }
    if (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9) {
      return String.fromCharCode(0x30 + (keyCode - KeyCode.KEYCODE_NUMPAD_0));
    }
    return '';
  }

  /** 是否为可打印字符键（排除功能键与修饰键） */
  private static isPrintableKey(keyCode: number): boolean {
    if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
      return true;
    }
    if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
      return true;
    }
    if (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9) {
      return true;
    }
    if (keyCode === KeyCode.KEYCODE_SPACE || keyCode === KeyCode.KEYCODE_COMMA || keyCode === KeyCode.KEYCODE_PERIOD) {
      return true;
    }
    // 标点类键位：` - = [ ] \\ ; ' / @ +（用范围判断，避免逐个列举遗漏）
    if (keyCode >= KEY_GRAVE && keyCode <= KEY_PLUS) {
      return true;
    }
    // 小键盘运算符（官方已确认的成员）
    if (keyCode === KeyCode.KEYCODE_NUMPAD_ADD || keyCode === KeyCode.KEYCODE_NUMPAD_SUBTRACT ||
      keyCode === KeyCode.KEYCODE_NUMPAD_MULTIPLY || keyCode === KeyCode.KEYCODE_NUMPAD_DIVIDE ||
      keyCode === KeyCode.KEYCODE_NUMPAD_DOT || keyCode === KeyCode.KEYCODE_NUMPAD_COMMA ||
      keyCode === KeyCode.KEYCODE_NUMPAD_EQUALS || keyCode === KeyCode.KEYCODE_NUMPAD_LEFT_PAREN ||
      keyCode === KeyCode.KEYCODE_NUMPAD_RIGHT_PAREN) {
      return true;
    }
    return false;
  }

  /**
   * Shift 转换：把 keyText 转为大写。
   * 数字行的 Shift 符号（! @ #）系统通常已在 keyText 中给出正确字符，
   * 强行 toUpperCase 不会破坏；但为避免破坏非字母符号，仅处理字母。
   */
  private static toUpper(text: string): string {
    if (text >= 'a' && text <= 'z') {
      return text.toUpperCase();
    }
    return text;
  }
}
