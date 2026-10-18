/**
 * 键位表 —— 物理/外接键盘事件 → EditCommand（契约 §2）
 *
 * 设计边界：
 * - 这里只做"按键 → 编辑意图"的纯函数翻译，**不直接插入文本**。
 *   打印字符仍然要由输入法 insertText 提交；只有输入法不可用（attach 失败）时，
 *   InputArbiter 才允许该 INSERT_TEXT 命令在 preIme 阶段被消费，由键盘兜底插入。
 * - Tab 一律返回 NONE：必须交还框架焦点遍历（不再插入两个空格）。
 * - 无修饰键的 Alt 组合也返回 NONE，交还系统（Alt+Tab 等）。
 *
 * 键码来源：@ohos.multimodalInput.keyCode（KEYCODE_PAGE_UP=2068、KEYCODE_PAGE_DOWN=2069、
 * KEYCODE_ESCAPE=2070、KEYCODE_DEL=2055、KEYCODE_FORWARD_DEL=2071）；
 * MOVE_HOME/MOVE_END（2081/2082）在部分 SDK 的 KeyCode 枚举里未导出，与 KeyboardHandler 一致用本地常量。
 */
import { KeyCode } from '@kit.InputKit';
import { EditCommand, EditCommandKind, EditorInputSource, EditorModifiers } from './EditCommand';

/**
 * 官方 js-apis-keycode（API 26）数值，全部用本地常量表达：
 *   KEYCODE_GRAVE=2056、KEYCODE_MINUS=2057、KEYCODE_SLASH=2064、KEYCODE_AT=2065、KEYCODE_PLUS=2066、
 *   KEYCODE_PAGE_UP=2068、KEYCODE_PAGE_DOWN=2069、KEYCODE_MOVE_HOME=2081、KEYCODE_MOVE_END=2082。
 * 用本地常量而不是 KeyCode 成员，是为了避免个别 SDK 版本未导出符号导致编译失败；
 * 数值以官方文档为准，不要凭记忆改。
 */
const SC_KEY_GRAVE: number = 2056;
const SC_KEY_MINUS: number = 2057;
const SC_KEY_SLASH: number = 2064;
const SC_KEY_AT: number = 2065;
const SC_KEY_PLUS: number = 2066;
const SC_KEY_PAGE_UP: number = 2068;
const SC_KEY_PAGE_DOWN: number = 2069;
const SC_KEY_MOVE_HOME: number = 2081;
const SC_KEY_MOVE_END: number = 2082;
const SC_KEY_F11: number = 2100;

/** 是否可打印字符键（与 KeyboardHandler 的键码范围保持一致，避免两套判定漂移） */
function isPrintableKeyCode(keyCode: number): boolean {
  if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
    return true;
  }
  if (keyCode >= KeyCode.KEYCODE_A && keyCode <= KeyCode.KEYCODE_Z) {
    return true;
  }
  if (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9) {
    return true;
  }
  if (keyCode === KeyCode.KEYCODE_SPACE) {
    return true;
  }
  // 主键盘标点区：` - = [ ] \\ ; ' / @ +（2056..2066）
  if (keyCode >= SC_KEY_GRAVE && keyCode <= SC_KEY_PLUS) {
    return true;
  }
  if (keyCode === KeyCode.KEYCODE_NUMPAD_ADD || keyCode === KeyCode.KEYCODE_NUMPAD_SUBTRACT ||
    keyCode === KeyCode.KEYCODE_NUMPAD_MULTIPLY || keyCode === KeyCode.KEYCODE_NUMPAD_DIVIDE ||
    keyCode === KeyCode.KEYCODE_NUMPAD_DOT) {
    return true;
  }
  return false;
}

/** Shift + 数字行的符号（0-9 → )!@#$%^&*(） */
const SHIFTED_DIGITS: string = ')!@#$%^&*('

/**
 * 数字键兜底：部分键盘布局/系统版本里数字行的 `keyText` 为空或不是数字，
 * 仅靠 keyText 判断会导致"字母能打、数字打不出来"。这里按官方 keyCode 数值
 * （KEYCODE_0=2000..KEYCODE_9=2009、小键盘 2103..2112）直接推出字符。
 * @return 0-9 之一；非数字键返回 ''
 */
function digitFromKeyCode(keyCode: number): string {
  if (keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
    return String.fromCharCode(0x30 + (keyCode - KeyCode.KEYCODE_0));
  }
  if (keyCode >= KeyCode.KEYCODE_NUMPAD_0 && keyCode <= KeyCode.KEYCODE_NUMPAD_9) {
    return String.fromCharCode(0x30 + (keyCode - KeyCode.KEYCODE_NUMPAD_0));
  }
  return '';
}

/**
 * 数字键的最终文本。
 * @param digit  digitFromKeyCode 的结果（只有当 keyCode 确实是数字键时才调用）
 * 优先采用 keyText（能正确表达 Shift 符号；部分键盘布局会给出空串），
 * 否则回落到 digit，并对主键盘 Shift+数字做符号映射（1 → ! 等）。
 */
function resolveDigitText(keyCode: number, digit: string, keyText: string, shift: boolean): string {
  // Shift + 主键盘数字：无论 keyText 已是符号还是仍是数字，都归一到符号位（! @ # …）
  if (shift && keyCode >= KeyCode.KEYCODE_0 && keyCode <= KeyCode.KEYCODE_9) {
    return SHIFTED_DIGITS.charAt(digit.charCodeAt(0) - 0x30);
  }
  if (keyText.length === 1 && keyText.charCodeAt(0) >= 0x20) {
    return keyText;
  }
  return digit;
}

/** Shift 只对 a-z 做显式大写：标点/数字行的 Shift 符号系统已在 keyText 给出 */
function resolveKeyText(keyText: string, shift: boolean): string {
  if (!shift) {
    return keyText;
  }
  if (keyText >= 'a' && keyText <= 'z') {
    return keyText.toUpperCase();
  }
  return keyText;
}

/** 组合键（Ctrl / Meta）：返回 true 表示已识别并写入 out.kind */
function resolvePrimaryChord(keyCode: number, mods: EditorModifiers, out: EditCommand): boolean {
  switch (keyCode) {
    case KeyCode.KEYCODE_A:
      out.kind = EditCommandKind.SELECT_ALL;
      return true;
    case KeyCode.KEYCODE_C:
      out.kind = EditCommandKind.COPY;
      return true;
    case KeyCode.KEYCODE_X:
      out.kind = EditCommandKind.CUT;
      return true;
    case KeyCode.KEYCODE_V:
      out.kind = EditCommandKind.PASTE;
      return true;
    case KeyCode.KEYCODE_Z:
      out.kind = mods.shift ? EditCommandKind.REDO : EditCommandKind.UNDO;
      return true;
    case KeyCode.KEYCODE_Y:
      out.kind = EditCommandKind.REDO;
      return true;
    case KeyCode.KEYCODE_S:
      out.kind = EditCommandKind.SAVE;
      return true;
    case KeyCode.KEYCODE_F:
      out.kind = EditCommandKind.FIND;
      return true;
    case KeyCode.KEYCODE_B:
      out.kind = EditCommandKind.TOGGLE_BOLD;
      return true;
    case KeyCode.KEYCODE_I:
      out.kind = EditCommandKind.TOGGLE_ITALIC;
      return true;
    case SC_KEY_MOVE_HOME:
      out.kind = EditCommandKind.MOVE_DOC_START;
      return true;
    case SC_KEY_MOVE_END:
      out.kind = EditCommandKind.MOVE_DOC_END;
      return true;
    case KeyCode.KEYCODE_DPAD_LEFT:
      out.kind = EditCommandKind.MOVE_WORD_LEFT;
      return true;
    case KeyCode.KEYCODE_DPAD_RIGHT:
      out.kind = EditCommandKind.MOVE_WORD_RIGHT;
      return true;
    case KeyCode.KEYCODE_DEL:
      // Ctrl+Backspace：按词删除（契约命令集含 DELETE_WORD_BACKWARD）
      out.kind = EditCommandKind.DELETE_WORD_BACKWARD;
      return true;
    default:
      return false;
  }
}

/**
 * 把一次按键事件解析为命令。
 *
 * @param keyCode      KeyCode 常量
 * @param keyText      按键文本（字符键为实际字符）
 * @param isDown       是否按下（抬起事件不产生命令，避免长按重复执行）
 * @param mods         修饰键快照
 * @param composing    输入法组字中：所有键交还输入法，编辑器不拦截
 */
export function resolveShortcut(keyCode: number, keyText: string, isDown: boolean,
  mods: EditorModifiers, composing: boolean): EditCommand {
  const out: EditCommand = new EditCommand(EditCommandKind.NONE, '', EditorInputSource.KEYBOARD);
  if (!isDown || composing) {
    return out;
  }
  out.mods = mods.clone();
  // Tab 必须交还焦点遍历：显式不消费（旧实现插入两个空格，是 PC 端焦点无法移出编辑器的根因）
  if (keyCode === KeyCode.KEYCODE_TAB) {
    return out;
  }
  if (mods.primary) {
    if (resolvePrimaryChord(keyCode, mods, out)) {
      return out;
    }
    // 未识别的 Ctrl/Meta 组合交还系统（如 Ctrl+Shift+Esc），不要吞键
    return new EditCommand(EditCommandKind.NONE, '', EditorInputSource.KEYBOARD);
  }
  // Alt 组合留给系统（Alt+Tab / Alt+F4 等）
  if (mods.alt) {
    return out;
  }
  switch (keyCode) {
    case KeyCode.KEYCODE_DPAD_LEFT:
      out.kind = EditCommandKind.MOVE_LEFT;
      return out;
    case KeyCode.KEYCODE_DPAD_RIGHT:
      out.kind = EditCommandKind.MOVE_RIGHT;
      return out;
    case KeyCode.KEYCODE_DPAD_UP:
      out.kind = EditCommandKind.MOVE_UP;
      return out;
    case KeyCode.KEYCODE_DPAD_DOWN:
      out.kind = EditCommandKind.MOVE_DOWN;
      return out;
    case SC_KEY_MOVE_HOME:
      out.kind = EditCommandKind.MOVE_LINE_START;
      return out;
    case SC_KEY_MOVE_END:
      out.kind = EditCommandKind.MOVE_LINE_END;
      return out;
    case SC_KEY_PAGE_UP:
      out.kind = EditCommandKind.PAGE_UP;
      return out;
    case SC_KEY_PAGE_DOWN:
      out.kind = EditCommandKind.PAGE_DOWN;
      return out;
    case KeyCode.KEYCODE_DEL:
      out.kind = EditCommandKind.DELETE_BACKWARD;
      return out;
    case KeyCode.KEYCODE_FORWARD_DEL:
      out.kind = EditCommandKind.DELETE_FORWARD;
      return out;
    case KeyCode.KEYCODE_ENTER:
    case KeyCode.KEYCODE_NUMPAD_ENTER:
      out.kind = EditCommandKind.INSERT_TEXT;
      out.text = '\n';
      return out;
    case KeyCode.KEYCODE_ESCAPE:
      out.kind = EditCommandKind.DISMISS;
      return out;
    case SC_KEY_F11:
      // F11：窗口内沉浸编辑（不进入系统全屏）
      out.kind = EditCommandKind.TOGGLE_IMMERSIVE;
      return out;
    default:
      break;
  }
  // 数字键：**不依赖 keyText**（见 resolveDigitText 注释），直接产出 INSERT_TEXT，
  // 由 InputArbiter 在 preIme 阶段上屏，避免被输入法当作候选选择吞掉。
  const digitCode: string = digitFromKeyCode(keyCode);
  if (digitCode !== '') {
    out.kind = EditCommandKind.INSERT_TEXT;
    out.text = resolveDigitText(keyCode, digitCode, keyText, mods.shift);
    return out;
  }

  // 打印字符：翻译成 INSERT_TEXT，但是否由键盘兜底插入由 InputArbiter(imeUsable) 决定
  if (keyText.length === 1 && isPrintableKeyCode(keyCode)) {
    const text: string = resolveKeyText(keyText, mods.shift);
    if (text.length === 1 && text.charCodeAt(0) >= 0x20) {
      out.kind = EditCommandKind.INSERT_TEXT;
      out.text = text;
    }
  }
  return out;
}
