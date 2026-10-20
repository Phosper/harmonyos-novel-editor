/**
 * 命令分发器 —— 编辑器输入链路的唯一分发点（契约 §2）
 *
 * 触摸 / 鼠标 / 键盘 / 输入法 / 外接键盘 → InputAdapter → EditCommand → 本类 → EditCommandHost。
 * 本类不持有文档状态，也不判断输入来源；只按命令调用宿主的**基本类型参数**方法。
 * （禁止把 class 实例传进 host 方法：V1 岛屿与输入层之间只允许基本类型。）
 */
import { EditCommand, EditCommandKind } from './EditCommand';

/**
 * 命令宿主：由 CanvasTextEditor 通过薄适配器（CanvasEditCommandHost）实现。
 * 参数与返回值只用基本类型，方便在 V1 @Component 岛屿内实现、也方便单测替身。
 */
export interface EditCommandHost {
  /** 插入文本（键盘兜底 / 粘贴等已归一的文本；换行为 '\n'） */
  insertText(text: string): void;
  deleteBackward(): void;
  deleteForward(): void;
  deleteWordBackward(): void;
  moveLeft(extend: boolean): void;
  moveRight(extend: boolean): void;
  moveUp(extend: boolean): void;
  moveDown(extend: boolean): void;
  moveWordLeft(extend: boolean): void;
  moveWordRight(extend: boolean): void;
  moveLineStart(extend: boolean): void;
  moveLineEnd(extend: boolean): void;
  moveDocStart(extend: boolean): void;
  moveDocEnd(extend: boolean): void;
  pageUp(): void;
  pageDown(): void;
  selectAll(): void;
  copy(): void;
  cut(): void;
  paste(): void;
  undo(): void;
  redo(): void;
  toggleBold(): void;
  toggleItalic(): void;
  toggleHeading(): void;
  save(): void;
  find(): void;
  /** @return 是否真的关闭了浮层（无浮层时返回 false，让 Esc 继续冒泡给系统） */
  dismiss(): boolean;
  /** 沉浸编辑开关（F11）：只改界面状态 */
  toggleImmersive(): void;
}

export class EditorCommandRouter {
  /**
   * 执行一条命令。
   * @return true 表示命令已被宿主处理（调用方应停止按键冒泡）
   */
  dispatch(cmd: EditCommand, host: EditCommandHost): boolean {
    switch (cmd.kind) {
      case EditCommandKind.INSERT_TEXT:
        if (cmd.text.length === 0) {
          return false;
        }
        host.insertText(cmd.text);
        return true;
      case EditCommandKind.DELETE_BACKWARD:
        host.deleteBackward();
        return true;
      case EditCommandKind.DELETE_FORWARD:
        host.deleteForward();
        return true;
      case EditCommandKind.DELETE_WORD_BACKWARD:
        host.deleteWordBackward();
        return true;
      case EditCommandKind.MOVE_LEFT:
        host.moveLeft(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_RIGHT:
        host.moveRight(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_UP:
        host.moveUp(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_DOWN:
        host.moveDown(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_WORD_LEFT:
        host.moveWordLeft(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_WORD_RIGHT:
        host.moveWordRight(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_LINE_START:
        host.moveLineStart(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_LINE_END:
        host.moveLineEnd(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_DOC_START:
        host.moveDocStart(cmd.mods.shift);
        return true;
      case EditCommandKind.MOVE_DOC_END:
        host.moveDocEnd(cmd.mods.shift);
        return true;
      case EditCommandKind.PAGE_UP:
        host.pageUp();
        return true;
      case EditCommandKind.PAGE_DOWN:
        host.pageDown();
        return true;
      case EditCommandKind.SELECT_ALL:
        host.selectAll();
        return true;
      case EditCommandKind.COPY:
        host.copy();
        return true;
      case EditCommandKind.CUT:
        host.cut();
        return true;
      case EditCommandKind.PASTE:
        host.paste();
        return true;
      case EditCommandKind.UNDO:
        host.undo();
        return true;
      case EditCommandKind.REDO:
        host.redo();
        return true;
      case EditCommandKind.TOGGLE_BOLD:
        host.toggleBold();
        return true;
      case EditCommandKind.TOGGLE_ITALIC:
        host.toggleItalic();
        return true;
      case EditCommandKind.TOGGLE_HEADING:
        host.toggleHeading();
        return true;
      case EditCommandKind.SAVE:
        host.save();
        return true;
      case EditCommandKind.FIND:
        host.find();
        return true;
      case EditCommandKind.DISMISS:
        return host.dismiss();
      case EditCommandKind.TOGGLE_IMMERSIVE:
        host.toggleImmersive();
        return true;
      case EditCommandKind.NONE:
      default:
        return false;
    }
  }
}
