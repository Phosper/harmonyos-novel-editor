/** Owns an IME client, including pending attach and exact listener cleanup. */
import { inputMethod } from '@kit.IMEKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ImeEchoGuard } from '../../interaction/InputArbiter';

class ImeSelectionReport {
  value: string;
  start: number;
  end: number;
  attempts: number = 0;

  constructor(value: string, start: number, end: number) {
    this.value = value;
    this.start = start;
    this.end = end;
  }

  matches(value: string, start: number, end: number): boolean {
    return this.value === value && this.start === start && this.end === end;
  }
}

export class ImeBridge {
  private controller: inputMethod.InputMethodController = inputMethod.getController();
  private isAttached: boolean = false;
  private regularRegistered: boolean = false;
  private previewRegistered: boolean = false;
  private pending: Promise<void> | null = null;
  private generation: number = 0;
  private pendingGeneration: number = 0;
  // Selection IPC is serialized: one in flight and only the latest pending report.
  // Retry only a current report; a newer composition/selection always takes priority.
  private selectionInFlight: ImeSelectionReport | null = null;
  private selectionPending: ImeSelectionReport | null = null;
  private selectionRetryTimer: number = -1;
  private selectionRetryRevision: number = 0;
  private readonly selectionRetryDelays: number[] = [32, 128];
  /**
   * 键盘兜底与 IME 回声仲裁（由 CanvasTextEditor 注入）。
   * 放在监听入口而不是宿主回调里：实体监听是唯一真实到达路径，
   * 宿主回调只负责把文本写进文档。
   */
  private echoGuard: ImeEchoGuard | null = null;
  onInsertText: ((text: string) => void) | null = null;
  onDeleteLeft: ((length: number) => void) | null = null;
  onDeleteRight: ((length: number) => void) | null = null;
  onMoveCursor: ((direction: inputMethod.Direction) => void) | null = null;
  onSelectByRange: ((start: number, end: number) => void) | null = null;
  onSendFunctionKey: ((type: inputMethod.EnterKeyType) => void) | null = null;
  onSendKeyboardStatus: ((status: inputMethod.KeyboardStatus) => void) | null = null;
  onPreviewText: ((text: string, start: number, end: number) => void) | null = null;
  onPreviewFinish: (() => void) | null = null;
  onGetTextLeft: ((length: number) => string) | null = null;
  onGetTextRight: ((length: number) => string) | null = null;
  onGetCursorIndex: (() => number) | null = null;
  get attached(): boolean { return this.isAttached; }

  /** 注入回声守卫（宿主在 aboutToAppear 调用一次） */
  setEchoGuard(guard: ImeEchoGuard): void {
    this.echoGuard = guard;
  }

  private insertListener = (value: string): void => {
    // 键盘兜底刚插入过同文本（40ms 内）→ 这是 IME 回声，丢弃，防止双输入
    if (this.echoGuard !== null && this.echoGuard.claim(value, Date.now())) { return; }
    if (this.onInsertText !== null) { this.onInsertText(value); }
  };
  private leftListener = (n: number): void => { if (this.onDeleteLeft !== null) { this.onDeleteLeft(n); } };
  private rightListener = (n: number): void => { if (this.onDeleteRight !== null) { this.onDeleteRight(n); } };
  private moveListener = (d: inputMethod.Direction): void => { if (this.onMoveCursor !== null) { this.onMoveCursor(d); } };
  private rangeListener = (r: inputMethod.Range): void => { if (this.onSelectByRange !== null) { this.onSelectByRange(r.start, r.end); } };
  private functionListener = (k: inputMethod.FunctionKey): void => { if (this.onSendFunctionKey !== null) { this.onSendFunctionKey(k.enterKeyType); } };
  private statusListener = (s: inputMethod.KeyboardStatus): void => { if (this.onSendKeyboardStatus !== null) { this.onSendKeyboardStatus(s); } };
  private previewListener = (s: string, r: inputMethod.Range): void => { if (this.onPreviewText !== null) { this.onPreviewText(s, r.start, r.end); } };
  private finishListener = (): void => { if (this.onPreviewFinish !== null) { this.onPreviewFinish(); } };
  private textLeftListener = (n: number): string => { return this.onGetTextLeft === null ? '' : this.onGetTextLeft(n); };
  private textRightListener = (n: number): string => { return this.onGetTextRight === null ? '' : this.onGetTextRight(n); };
  private indexListener = (): number => { return this.onGetCursorIndex === null ? 0 : this.onGetCursorIndex(); };

  attach(showKeyboard: boolean, textInputType: number, enterKeyType: number): Promise<void> {
    if (this.isAttached) {
      this.resumeSelectionSync();
      return Promise.resolve();
    }
    if (this.pending !== null) {
      if (this.pendingGeneration === this.generation) { return this.pending; }
      return this.pending.then(() => this.attach(showKeyboard, textInputType, enterKeyType));
    }
    const token: number = ++this.generation;
    this.clearSelectionSync();
    this.pendingGeneration = token;
    this.pending = this.attachClient(token, showKeyboard, textInputType, enterKeyType);
    return this.pending;
  }

  private async attachClient(token: number, showKeyboard: boolean, textInputType: number, enterKeyType: number): Promise<void> {
    try {
      this.registerPreviewListeners();
      await this.controller.attach(showKeyboard, { inputAttribute: { textInputType: textInputType, enterKeyType: enterKeyType } });
      if (token !== this.generation) {
        await this.controller.detach();
      } else { this.registerListeners(); this.isAttached = true; }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('FlowText IME attach failed: ' + error.code + ' ' + error.message);
      this.unregisterListeners();
      await this.controller.detach().catch(() => {});
      this.isAttached = false;
    } finally { this.pending = null; }
  }

  detach(): void {
    this.generation++;
    this.clearSelectionSync();
    this.unregisterListeners();
    if (this.isAttached) { this.controller.detach().catch(() => {}); }
    this.isAttached = false;
  }

  updateCursor(left: number, top: number, width: number, height: number): void {
    if (this.isAttached) {
      this.controller.updateCursor({ left: Math.round(left), top: Math.round(top), width: Math.round(width), height: Math.round(height) }).catch(() => {});
    }
  }
  changeSelection(value: string, start: number, end: number): void {
    if (!this.isAttached) { return; }
    this.cancelSelectionRetry();
    // A -> B -> A while A is in flight only needs the in-flight A to finish.
    if (this.selectionInFlight !== null && this.selectionInFlight.matches(value, start, end)) {
      this.selectionPending = null;
      return;
    }
    this.selectionPending = new ImeSelectionReport(value, start, end);
    this.sendPendingSelection();
  }
  hideKeyboard(): void { if (this.isAttached) { this.controller.hideTextInput().catch(() => {}); } }
  showKeyboard(): void {
    if (this.isAttached) {
      this.resumeSelectionSync();
      this.controller.showTextInput().catch(() => {});
    }
  }

  private cancelSelectionRetry(): void {
    this.selectionRetryRevision++;
    if (this.selectionRetryTimer >= 0) {
      clearTimeout(this.selectionRetryTimer);
      this.selectionRetryTimer = -1;
    }
  }

  private clearSelectionSync(): void {
    this.cancelSelectionRetry();
    this.selectionInFlight = null;
    this.selectionPending = null;
  }

  /** A fresh focus/keyboard request can retry a report parked after three failures. */
  private resumeSelectionSync(): void {
    if (this.selectionPending === null || this.selectionInFlight !== null ||
      this.selectionRetryTimer >= 0) { return; }
    this.selectionPending.attempts = 0;
    this.sendPendingSelection();
  }

  private sendPendingSelection(): void {
    if (!this.isAttached || this.selectionInFlight !== null || this.selectionPending === null ||
      this.selectionRetryTimer >= 0) { return; }
    const report: ImeSelectionReport = this.selectionPending;
    const token: number = this.generation;
    this.selectionPending = null;
    this.selectionInFlight = report;
    report.attempts++;
    try {
      this.controller.changeSelection(report.value, report.start, report.end)
        .then(() => this.finishSelectionSync(token, report, true))
        .catch(() => this.finishSelectionSync(token, report, false));
    } catch (error) {
      this.finishSelectionSync(token, report, false);
    }
  }

  private finishSelectionSync(token: number, report: ImeSelectionReport, succeeded: boolean): void {
    // The native promise cannot be cancelled. Its completion belongs only to its old client.
    if (token !== this.generation || this.selectionInFlight !== report) { return; }
    this.selectionInFlight = null;
    if (succeeded || this.selectionPending !== null) {
      this.sendPendingSelection();
      return;
    }
    this.selectionPending = report;
    if (report.attempts > this.selectionRetryDelays.length) {
      console.warn('FlowText IME selection sync failed after ' + report.attempts + ' attempts');
      return;
    }
    const revision: number = ++this.selectionRetryRevision;
    this.selectionRetryTimer = setTimeout(() => {
      if (token !== this.generation || revision !== this.selectionRetryRevision) { return; }
      this.selectionRetryTimer = -1;
      this.sendPendingSelection();
    }, this.selectionRetryDelays[report.attempts - 1]);
  }

  private registerListeners(): void {
    this.regularRegistered = true;
    this.controller.on('insertText', this.insertListener);
    this.controller.on('deleteLeft', this.leftListener);
    this.controller.on('deleteRight', this.rightListener);
    this.controller.on('moveCursor', this.moveListener);
    this.controller.on('selectByRange', this.rangeListener);
    this.controller.on('sendFunctionKey', this.functionListener);
    this.controller.on('sendKeyboardStatus', this.statusListener);
    this.controller.on('getLeftTextOfCursor', this.textLeftListener);
    this.controller.on('getRightTextOfCursor', this.textRightListener);
    this.controller.on('getTextIndexAtCursor', this.indexListener);
  }
  private registerPreviewListeners(): void {
    this.previewRegistered = true;
    this.controller.on('setPreviewText', this.previewListener);
    this.controller.on('finishTextPreview', this.finishListener);
  }
  private unregisterListeners(): void {
    try {
      if (this.regularRegistered) {
        this.controller.off('insertText', this.insertListener);
        this.controller.off('deleteLeft', this.leftListener);
        this.controller.off('deleteRight', this.rightListener);
        this.controller.off('moveCursor', this.moveListener);
        this.controller.off('selectByRange', this.rangeListener);
        this.controller.off('sendFunctionKey', this.functionListener);
        this.controller.off('sendKeyboardStatus', this.statusListener);
        this.controller.off('getLeftTextOfCursor', this.textLeftListener);
        this.controller.off('getRightTextOfCursor', this.textRightListener);
        this.controller.off('getTextIndexAtCursor', this.indexListener);
      }
      if (this.previewRegistered) {
        this.controller.off('setPreviewText', this.previewListener);
        this.controller.off('finishTextPreview', this.finishListener);
      }
    } catch (error) { console.warn('FlowText IME listener cleanup: ' + String(error)); }
    this.regularRegistered = false;
    this.previewRegistered = false;
  }
}
