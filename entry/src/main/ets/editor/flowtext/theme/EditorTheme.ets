import { TypewriterScaleOptions } from './TypewriterScale';

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
  /**
   * 非当前段落的淡化字色（打字机模式）。
   * 由宿主按当前主题的正文色/纸色混合得到（见 DesignTokens.blendHexColor），
   * 不在这里硬编码主题相关颜色。
   */
  dimTextColor: string = '#9AA0A6';

  /** 光标宽度（vp） */
  caretWidth: number = 2;
  /** 光标闪烁动画时长（ms）——保留字段以兼容旧调用；呼吸光标使用 caretBreathPeriodMs */
  caretBlinkDuration: number = 600;
  /** 呼吸光标一个完整明暗周期的时长（ms）：低频缓变，避免干扰阅读 */
  caretBreathPeriodMs: number = 2400;
  /** 打字机段落缩放层级：当前段 1.08×、相邻 0.98×、逐行 -0.02、下限 0.90× */
  typewriterScale: TypewriterScaleOptions = new TypewriterScaleOptions();
  /** 段落切换缩放动画时长（ms）；关闭后直接切换（可作为减少动态效果的降级） */
  typewriterScaleDurationMs: number = 180;
  /** 是否启用段落缩放过渡动画 */
  typewriterScaleAnimated: boolean = true;
  /** 呼吸光标刷新步长（ms）：约 16fps，低频呼吸足够平滑，避免常驻 60fps 重绘 */
  caretBreathStepMs: number = 60;

  /** 每行总高 = lineHeight + lineSpacing（末行除外由布局处处理） */
  lineStep(): number {
    return this.lineHeight + this.lineSpacing;
  }
}
