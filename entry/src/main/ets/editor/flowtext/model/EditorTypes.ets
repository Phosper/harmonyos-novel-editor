/**
 * FlowText 公共类型（内部绘制/交互契约）
 */
/** 文本选区 */
export class SelectionInfo {
  startOffset: number = 0;
  endOffset: number = 0;

  isEmpty(): boolean {
    return this.startOffset === this.endOffset;
  }
}

/** 中文输入法预上屏信息 */
export class PreviewInfo {
  text: string = '';
  /** 预上屏文本在正文中的起始偏移（UTF-16 code unit） */
  startOffset: number = 0;
  endOffset: number = 0;

  isEmpty(): boolean {
    return this.text.length === 0;
  }
}

/** 视口信息（滚动） */
export class ViewportInfo {
  /** 内容垂直滚动偏移（px） */
  scrollY: number = 0;
  /** 可视区顶部（px，内容坐标） */
  top: number = 0;
  /** 可视区底部（px，内容坐标） */
  bottom: number = 0;

  constructor(scrollY: number, viewHeight: number) {
    this.scrollY = scrollY;
    this.top = scrollY;
    this.bottom = scrollY + viewHeight;
  }
}

/** 滚动策略 */
export enum ScrollPolicy {
  /** 普通：仅在光标越出视口时滚动使其可见 */
  NORMAL = 0,
  /** 打字机：使当前段中心对齐视口中心（随输入跟随） */
  CENTER = 1
}

/** 行内/段落样式种类 */
export enum StyleKind {
  /** 行内加粗 */
  BOLD = 0,
  /** 行内斜体 */
  ITALIC = 1,
  /** 段落标题 1 */
  HEADING_1 = 2,
  /** 段落标题 2 */
  HEADING_2 = 3,
  /** 段落标题 3 */
  HEADING_3 = 4,
  /** 正文段落（默认） */
  BODY = 5
}

/** 格式标注：施加于 [startOffset, endOffset) 的样式（行内与段落可叠加） */
export class FormatRun {
  startOffset: number = 0;
  endOffset: number = 0;
  /** 行内加粗 */
  bold: boolean = false;
  /** 行内斜体 */
  italic: boolean = false;
  /** 段落标题级别：0=正文，1/2/3=标题 */
  heading: number = 0;

  constructor(startOffset: number = 0, endOffset: number = 0,
    bold: boolean = false, italic: boolean = false, heading: number = 0) {
    this.startOffset = startOffset;
    this.endOffset = endOffset;
    this.bold = bold;
    this.italic = italic;
    this.heading = heading;
  }

  isEmpty(): boolean {
    return this.endOffset <= this.startOffset;
  }

  isDefault(): boolean {
    return !this.bold && !this.italic && this.heading === 0;
  }

  sameAs(o: FormatRun): boolean {
    return this.bold === o.bold && this.italic === o.italic && this.heading === o.heading;
  }

  clone(): FormatRun {
    return new FormatRun(this.startOffset, this.endOffset, this.bold, this.italic, this.heading);
  }
}
