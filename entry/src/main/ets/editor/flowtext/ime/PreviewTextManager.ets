/** Provisional text replaces one committed range and supports IME range updates. */
import { PreviewInfo } from '../model/EditorTypes';
export class PreviewTextManager {
  private info: PreviewInfo = new PreviewInfo();
  private composingValue: boolean = false;
  get previewInfo(): PreviewInfo { return this.info; }
  get isComposing(): boolean { return this.composingValue; }

  update(text: string, start: number, end: number = start, selectionStart: number = 0, selectionEnd: number = selectionStart): boolean {
    if (!this.composingValue) {
      this.info.startOffset = start === -1 ? selectionStart : start;
      this.info.endOffset = end === -1 ? selectionEnd : end;
      this.info.text = text;
      this.composingValue = true;
      return true;
    }
    if (start === -1 && end === -1) { this.info.text = text; return true; }
    const lo: number = start - this.info.startOffset;
    const hi: number = end - this.info.startOffset;
    if (lo < 0 || hi < lo || hi > this.info.text.length) { return false; }
    this.info.text = this.info.text.substring(0, lo) + text + this.info.text.substring(hi);
    return true;
  }
  commit(): PreviewInfo | null {
    if (!this.composingValue) { return null; }
    const result: PreviewInfo = new PreviewInfo();
    result.text = this.info.text;
    result.startOffset = this.info.startOffset;
    result.endOffset = this.info.endOffset;
    this.cancel();
    return result;
  }
  cancel(): void { this.info = new PreviewInfo(); this.composingValue = false; }
}
