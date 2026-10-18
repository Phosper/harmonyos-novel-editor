/**
 * FlowText 光标状态（px 坐标）
 */
export class CursorState {
  /** 光标左端 x（vp，内容坐标） */
  x: number = 0;
  /** 光标顶端 y（vp，内容坐标） */
  y: number = 0;
  /** 光标高度（vp，约等于当前行高） */
  height: number = 0;
  /** 可见性（失焦/键盘隐藏时隐藏） */
  visible: boolean = true;
  /**
   * 不透明度（0–1）：打字机式"呼吸光标"用。
   * 1 = 完全实心；呼吸时在 [0.42, 1] 之间缓变，不做硬闪烁。
   */
  alpha: number = 1;

  clone(): CursorState {
    const c = new CursorState();
    c.x = this.x;
    c.y = this.y;
    c.height = this.height;
    c.visible = this.visible;
    c.alpha = this.alpha;
    return c;
  }
}
