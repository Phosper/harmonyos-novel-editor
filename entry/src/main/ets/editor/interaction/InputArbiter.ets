/**
 * 输入仲裁 —— 决定一个命令在 onKeyPreIme（①，先于输入法）阶段是否消费（契约 §2）
 *
 * 官方按键派发顺序：① onKeyPreIme + 快捷键 → ② 输入法 → ③ 系统默认 Key + onKeyEvent。
 * - 走位键 / 组合键 / Esc 必须在 ① 截获：否则方向键会被输入法拿去切候选词，
 *   Ctrl 组合也会被系统默认行为吞掉（PC 端"方向键/Ctrl+C 没反应"的根因）。
 * - 打印字符只能在**输入法不可用**（attach 失败）时于 ① 兜底消费；可用时放行给输入法组字。
 */
import { EditCommand, EditCommandKind, isCaretCommand, isEditingCommand } from './EditCommand';

/**
 * @param cmd        已解析命令
 * @param imeUsable  输入法 attach 是否成功（true 时字符键必须放行给 IME）
 * @return true 表示 onKeyPreIme 应消费该键（返回 true 并 stopPropagation）
 */
export function shouldConsumePreIme(cmd: EditCommand, imeUsable: boolean): boolean {
  if (cmd.kind === EditCommandKind.NONE) {
    return false;
  }
  // 组合键（Ctrl / Meta / Alt）优先于输入法：IME 不处理这些，系统默认行为又会误吞
  if (cmd.mods.primary || cmd.mods.alt) {
    return true;
  }
  // 走位键：必须在输入法之前截获，否则光标不动
  if (isCaretCommand(cmd.kind)) {
    return true;
  }
  // Esc：关闭编辑器浮层（无浮层时 host 返回 false，继续冒泡给系统）
  if (cmd.kind === EditCommandKind.DISMISS) {
    return true;
  }
  // F11 沉浸开关：属于界面命令，必须由编辑器消费，不能交给输入法
  if (cmd.kind === EditCommandKind.TOGGLE_IMMERSIVE) {
    return true;
  }
  // 字符键（含数字）：输入法可用时**必须**放行。
  // 数字键在输入法组字态是"选择候选词"的按键（1..9），若在 preIme 抢走上屏，
  // 就会出现"预输入文字时按数字不能选词、直接打出数字"的冲突。
  // 数字的键盘兜底放在 ③ onKeyEvent（输入法没用掉该键才会到达），见 ShortcutMap.digitFromKeyCode。
  if (cmd.kind === EditCommandKind.INSERT_TEXT) {
    return !imeUsable;
  }
  // 删除/撤销/粘贴等编辑命令：IME 可用时让 IME 处理（保留组合态语义）
  if (isEditingCommand(cmd.kind)) {
    return !imeUsable;
  }
  return !imeUsable;
}

/**
 * IME 回声抑制：键盘兜底插入后 40ms 内到达的同文本 IME 回调视为回声丢弃，防止双输入。
 *
 * 典型场景：输入法 attach 异步完成恰好与按键同时发生 ——
 * ① 阶段按 imeUsable=false 走了键盘兜底插入；
 * ② 输入法随后又回调 insertText(同一字符) → claim() 命中并丢弃。
 * 仅"键盘兜底刚插入过同文本"才丢弃，正常连续两次输入同一字符（间隔 > 40ms 或来源为 IME）不受影响。
 */
export class ImeEchoGuard {
  /** 回声窗口（ms）；契约规定 40ms */
  private readonly windowMs: number = 40;
  private armedText: string = '';
  private armedAtMs: number = 0;

  /** 键盘兜底插入后登记：随后的同文本 IME 回调按回声处理 */
  recordKeyboardFallback(text: string, nowMs: number): void {
    if (text.length === 0) {
      return;
    }
    this.armedText = text;
    this.armedAtMs = nowMs;
  }

  /**
   * IME 回调到达时判定。
   * @return true 表示这是键盘兜底的回声，应丢弃；命中后立即解除登记（一条兜底只吞一条回声）
   */
  claim(text: string, nowMs: number): boolean {
    if (this.armedText.length === 0) {
      return false;
    }
    if (text !== this.armedText) {
      return false;
    }
    const elapsed: number = nowMs - this.armedAtMs;
    if (elapsed < 0 || elapsed > this.windowMs) {
      return false;
    }
    this.armedText = '';
    this.armedAtMs = 0;
    return true;
  }

  /** 是否处于待回声窗口（诊断用） */
  get armed(): boolean {
    return this.armedText.length > 0;
  }

  /** 文档切换/失焦时清空，避免跨文稿误吞输入 */
  reset(): void {
    this.armedText = '';
    this.armedAtMs = 0;
  }
}
