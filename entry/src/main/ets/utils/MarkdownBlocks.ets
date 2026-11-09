// Markdown 块级语法 ↔ 段落标注（交接稿 R4 / F07）
//
// 边界约定（只做这一层，不追求完整 Markdown）：
//  - 导入：ATX 标题（# ~ ###）、无序列表（- * +）、待办（- [ ] / - [x]）转成段落种类，
//    并把行首标记从正文里去掉。**四级以上标题与其它语法保持原文**，不静默丢弃。
//  - 导出：段落种类合成行首标记；若该行本身已带同类标记就跳过，
//    避免"导入的 # 标题再设 H1"导出成 `# # 标题`。
//  - 行内 `**`/`*` 不解析（保持字面量），这是当前明确的限制。
import { FormatRun, ParagraphKind, MAX_LIST_LEVEL } from '../editor/flowtext/model/EditorTypes'

const HEADING_RE: RegExp = /^(#{1,6})[ \t]+/
const TODO_RE: RegExp = /^([ \t]*)[-*+][ \t]+\[([ xX])\][ \t]+/
const LIST_RE: RegExp = /^([ \t]*)[-*+][ \t]+/
const MARKED_HEADING_RE: RegExp = /^[ \t]*#{1,6}[ \t]+/
const MARKED_LIST_RE: RegExp = /^[ \t]*[-*+][ \t]+/

/** 一行 Markdown 的块级信息：kind=0 表示正文（不做任何处理） */
export class MarkdownLineInfo {
  kind: number = 0
  indent: number = 0
  /** 需要从行首去掉的字符数（0 = 原样保留） */
  markerLength: number = 0

  constructor(kind: number, indent: number, markerLength: number) {
    this.kind = kind
    this.indent = indent
    this.markerLength = markerLength
  }
}

/** 解析结果：去掉块级标记后的正文 + 段落标注 */
export interface MarkdownParseResult {
  content: string
  runs: FormatRun[]
}

function indentLevel(prefix: string): number {
  let spaces: number = 0
  for (let i: number = 0; i < prefix.length; i++) {
    spaces += prefix.charAt(i) === '\t' ? 2 : 1
  }
  const level: number = Math.floor(spaces / 2)
  return Math.max(0, Math.min(MAX_LIST_LEVEL, level))
}

export class MarkdownBlocks {
  /**
   * 识别单行的块级语法。
   * 只认模型支持的三种：1–3 级标题、无序列表、待办（未完成/已完成）。
   */
  static parseLine(line: string): MarkdownLineInfo {
    const todo: RegExpExecArray | null = TODO_RE.exec(line)
    if (todo !== null) {
      const kind: number = todo[2] === ' ' ? ParagraphKind.TODO : ParagraphKind.TODO_DONE
      return new MarkdownLineInfo(kind, indentLevel(todo[1]), todo[0].length)
    }
    const list: RegExpExecArray | null = LIST_RE.exec(line)
    if (list !== null) {
      return new MarkdownLineInfo(ParagraphKind.BULLET, indentLevel(list[1]), list[0].length)
    }
    const heading: RegExpExecArray | null = HEADING_RE.exec(line)
    if (heading !== null) {
      const level: number = heading[1].length
      // 四级以上没有对应段落种类：保留原文（含 #），不静默改写
      if (level <= 3) {
        return new MarkdownLineInfo(level, 0, heading[0].length)
      }
    }
    return new MarkdownLineInfo(ParagraphKind.BODY, 0, 0)
  }

  /** 整篇解析：返回去掉块级标记的正文与逐段标注（标注含段末换行） */
  static parse(markdown: string): MarkdownParseResult {
    const lines: string[] = markdown.split('\n')
    const out: string[] = []
    const runs: FormatRun[] = []
    let base: number = 0
    for (let i: number = 0; i < lines.length; i++) {
      const raw: string = lines[i]
      const info: MarkdownLineInfo = MarkdownBlocks.parseLine(raw)
      const text: string = info.markerLength > 0 ? raw.substring(info.markerLength) : raw
      out.push(text)
      const hasNewline: boolean = i < lines.length - 1
      const end: number = base + text.length + (hasNewline ? 1 : 0)
      if (info.kind !== ParagraphKind.BODY && end > base) {
        runs.push(new FormatRun(base, end, false, false, info.kind, info.indent))
      }
      base = end
    }
    const result: MarkdownParseResult = { content: out.join('\n'), runs: runs }
    return result
  }

  /**
   * 导出时该行是否已经自带同类行首标记。
   * 有则不再追加，避免重复标记（`# # 标题` / `- - 项`）。
   */
  static alreadyMarked(line: string, kind: number): boolean {
    if (kind >= ParagraphKind.H1 && kind <= ParagraphKind.H3) {
      return MARKED_HEADING_RE.test(line)
    }
    if (kind >= ParagraphKind.BULLET && kind <= ParagraphKind.TODO_DONE) {
      return MARKED_LIST_RE.test(line)
    }
    return false
  }
}
