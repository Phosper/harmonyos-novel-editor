/**
 * FlowText 主题配置
 *
 * 编辑器视觉参数：字号、行高、行距、颜色等。
 * 所有长度单位均为 vp（与排版引擎输出一致）。
 */
export class EditorTheme {
  /** 字号（vp） */
  fontSize: number = 16;
  /** 行高（vp，含字体内边距） */
  lineHeight: number = 24;
  /** 行间距（vp，仅行与行之间） */
  lineSpacing: number = 4;
  /** 水平内边距（vp） */
  paddingLeft: number = 12;
  paddingRight: number = 12;
  paddingTop: number = 8;
  paddingBottom: number = 8;

  /** 正文字色 */
  textColor: string = '#1F2329';
  /** 光标颜色 */
  caretColor: string = '#0A59F7';
  /** 选区高亮颜色 */
  selectionColor: string = '#4D0A59F7';
  /** 画布背景色 */
  backgroundColor: string = '#FFFFFF';
  /** 占位文本颜色 */
  placeholderColor: string = '#9AA0A6';
  /** 预上屏文本颜色（拼音组合态） */
  previewColor: string = '#5C6470';

  /** 光标宽度（vp） */
  caretWidth: number = 2;
  /** 光标闪烁动画时长（ms） */
  caretBlinkDuration: number = 600;

  /** 每行总高 = lineHeight + lineSpacing（末行除外由布局处处理） */
  lineStep(): number {
    return this.lineHeight + this.lineSpacing;
  }
}
