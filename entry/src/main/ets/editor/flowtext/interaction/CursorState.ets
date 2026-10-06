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
  /** 可见性（失焦/键盘隐藏时隐藏；编辑时闪烁） */
  visible: boolean = true;

  clone(): CursorState {
    const c = new CursorState();
    c.x = this.x;
    c.y = this.y;
    c.height = this.height;
    c.visible = this.visible;
    return c;
  }
}
