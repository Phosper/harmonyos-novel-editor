// 导出服务 —— 支持 TXT / Markdown / HTML / JSON 备份，单篇与整本两种粒度
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Logger } from './Logger'
import { ChapterFormat } from '../model/Chapter'
import { MarkdownRenderer } from './MarkdownRenderer'
import { FormatRun, MAX_LIST_LEVEL, ParagraphKind, isListParagraph } from '../editor/flowtext/model/EditorTypes'
import { FormatCodec } from '../editor/flowtext/model/FormatCodec'

const EXPORT_WRITE_CHUNK_BYTES: number = 64 * 1024

/** 导出目标格式 */
export enum ExportFormat {
  TXT = 'txt',
  MD = 'md',
  HTML = 'html',
  JSON = 'json'
}

/** 待导出的一篇文稿 */
export interface ExportableChapter {
  title: string
  content: string
  format: ChapterFormat
  /** 行内/段落格式标注边车（T027；缺省为空） */
  runsJson?: string
}

export class ExportService {

  /** 单篇内容 → 目标格式的文本 */
  static renderChapter(chapter: ExportableChapter, target: ExportFormat, documentTitle: string): string {
    if (target === ExportFormat.TXT) {
      return ExportService.plainTextOf(chapter)
    }
    if (target === ExportFormat.HTML) {
      return MarkdownRenderer.wrapHtmlDocument(documentTitle, ExportService.htmlBodyOf(chapter))
    }
    const source: string = ExportService.sourceOf(chapter)
    const isMarkdownSource: boolean = chapter.format === ChapterFormat.MD || ExportService.hasFormat(chapter)
    if (target === ExportFormat.MD) {
      return source
    }
    // TXT
    return isMarkdownSource ? MarkdownRenderer.toPlainText(source) : source
  }

  // ===== 格式标注导出（T027） =====

  private static hasFormat(chapter: ExportableChapter): boolean {
    return chapter.runsJson !== undefined && chapter.runsJson !== ''
  }

  /** 正文源：若有格式标注则转为带标记的 Markdown，否则原样返回 */
  private static sourceOf(chapter: ExportableChapter): string {
    if (!ExportService.hasFormat(chapter)) {
      return chapter.content
    }
    return ExportService.applyMarkdown(chapter.content, chapter.runsJson as string)
  }

  /** TXT 正文中的标记符号也是原文；只有 Markdown 源需要去除语法标记。 */
  private static plainTextOf(chapter: ExportableChapter): string {
    return chapter.format === ChapterFormat.MD
      ? MarkdownRenderer.toPlainText(ExportService.sourceOf(chapter))
      : chapter.content
  }

  /** TXT 的格式边车不是 Markdown 源；正文里的语法符号仍是字面文本。 */
  private static htmlBodyOf(chapter: ExportableChapter): string {
    if (chapter.format === ChapterFormat.MD) {
      return MarkdownRenderer.toHtmlBody(ExportService.sourceOf(chapter))
    }
    if (ExportService.hasFormat(chapter)) {
      return ExportService.formattedToHtml(chapter.content, chapter.runsJson as string)
    }
    return ExportService.plainToHtml(chapter.content)
  }

  /** 正文先转义，再直接添加格式标签；避免 Markdown 二次解释原文字面符号。 */
  private static formattedToHtml(content: string, runsJson: string): string {
    const runs: FormatRun[] = FormatCodec.decode(runsJson)
    const lines: string[] = content.split('\n')
    const out: string[] = []
    let base: number = 0
    let listIndent: number = -1
    for (let li: number = 0; li < lines.length; li++) {
      const raw: string = lines[li]
      // 仅去掉 CRLF 分隔符中的 CR；格式偏移仍按原文 UTF-16 长度推进。
      const line: string = li < lines.length - 1 && raw.endsWith('\r')
        ? raw.substring(0, raw.length - 1) : raw
      const kind: number = ExportService.paragraphAttrFor(runs, base, base + raw.length + 1, 0)
      const indent: number = ExportService.paragraphAttrFor(runs, base, base + raw.length + 1, 1)
      const body: string = line.length === 0 ? '<br>' : ExportService.applyInlineHtml(line, runs, base)
      if (isListParagraph(kind)) {
        const level: number = Number.isFinite(indent) ? Math.max(0, Math.min(MAX_LIST_LEVEL, Math.round(indent))) : 0
        if (listIndent !== level) {
          if (listIndent >= 0) { out.push('</ul>') }
          // 层级是段落属性；保留缩进，不为首项缺失的上级虚构空列表项。
          out.push('<ul style="margin-left: ' + (level * 2).toString() + 'em;">')
          listIndent = level
        }
        out.push(ExportService.htmlListItem(body, kind))
      } else {
        if (listIndent >= 0) {
          out.push('</ul>')
          listIndent = -1
        }
        const tag: string = kind >= ParagraphKind.H1 && kind <= ParagraphKind.H3 ? 'h' + kind.toString() : 'p'
        out.push('<' + tag + ' style="white-space: pre-wrap;">' + body + '</' + tag + '>')
      }
      base += raw.length + 1
    }
    if (listIndent >= 0) { out.push('</ul>') }
    return out.join('\n')
  }

  private static htmlListItem(body: string, kind: number): string {
    if (kind === ParagraphKind.BULLET) {
      return '<li style="white-space: pre-wrap;">' + body + '</li>'
    }
    const done: boolean = kind === ParagraphKind.TODO_DONE
    const checkbox: string = done
      ? '<input type="checkbox" disabled checked aria-label="已完成"> '
      : '<input type="checkbox" disabled aria-label="未完成"> '
    const text: string = done ? '<del>' + body + '</del>' : body
    return '<li style="white-space: pre-wrap; list-style-type: none;">' + checkbox + text + '</li>'
  }

  /** 格式边界沿用 UTF-16 偏移；旧标注也不能把代理对拆进两个标签。 */
  private static applyInlineHtml(line: string, runs: FormatRun[], base: number): string {
    const lineEnd: number = base + line.length
    let out: string = ''
    let i: number = 0
    while (i < line.length) {
      const abs: number = base + i
      let bold: boolean = false
      let italic: boolean = false
      let nextBoundary: number = lineEnd
      for (const run of runs) {
        if (abs >= run.startOffset && abs < run.endOffset) {
          bold = run.bold
          italic = run.italic
          nextBoundary = Math.min(nextBoundary, run.endOffset)
        } else if (run.startOffset > abs) {
          nextBoundary = Math.min(nextBoundary, run.startOffset)
        }
      }
      let j: number = i + 1
      while (j < line.length && base + j < nextBoundary) { j++ }
      if (j < line.length && line.charCodeAt(j - 1) >= 0xD800 && line.charCodeAt(j - 1) <= 0xDBFF &&
        line.charCodeAt(j) >= 0xDC00 && line.charCodeAt(j) <= 0xDFFF) {
        j++
      }
      let seg: string = MarkdownRenderer.escapeHtml(line.substring(i, j))
      if (bold) { seg = '<strong>' + seg + '</strong>' }
      if (italic) { seg = '<em>' + seg + '</em>' }
      out += seg
      i = j
    }
    return out
  }

  /** 按格式标注把纯正文转为 Markdown（标题前缀 + 行内 ** / *） */
  private static applyMarkdown(content: string, runsJson: string): string {
    const runs: FormatRun[] = FormatCodec.decode(runsJson)
    if (runs.length === 0) {
      return content
    }
    const lines: string[] = content.split('\n')
    const out: string[] = []
    let base: number = 0
    for (let li: number = 0; li < lines.length; li++) {
      const line: string = lines[li]
      // 按**整段**取属性，而不是只看段首那个码元：
      // 在段首插入过文字后，段落标注可能从段中开始（模型侧 reading 有兜底，
      // 这里用同一套区间判定，保证导出的列表前缀不会时有时无）。
      const kind: number = ExportService.paragraphAttrFor(runs, base, base + line.length + 1, 0)
      const indent: number = ExportService.paragraphAttrFor(runs, base, base + line.length + 1, 1)
      let text: string = ExportService.applyInlineMarkdown(line, runs, base)
      const prefix: string = ExportService.paragraphPrefix(kind, indent)
      if (prefix !== '') {
        text = prefix + text
      }
      out.push(text)
      base += line.length + 1
    }
    return out.join('\n')
  }

  /**
   * 段落 → Markdown 行首标记。
   *
   * 段落种类（ParagraphKind）与标题级别共用 FormatRun.heading：1–3 是标题，
   * 4/5/6 是列表 / 未完成待办 / 已完成待办。旧实现直接 `'######'.substring(0, level)`，
   * 于是列表段会被导出成 `####`–`######` 的假标题——必须先按种类分派。
   */
  private static paragraphPrefix(kind: number, indent: number): string {
    if (kind >= 1 && kind <= 3) {
      return '######'.substring(0, kind) + ' '
    }
    if (kind === 4) {
      return ExportService.listPad(indent) + '- '
    }
    if (kind === 5) {
      return ExportService.listPad(indent) + '- [ ] '
    }
    if (kind === 6) {
      return ExportService.listPad(indent) + '- [x] '
    }
    return ''
  }

  /** 列表层级 → 两个空格缩进（0–2 层） */
  private static listPad(indent: number): string {
    const level: number = Math.max(0, Math.min(2, indent))
    let pad: string = ''
    for (let i: number = 0; i < level; i++) {
      pad += '  '
    }
    return pad
  }

  /**
   * 段落属性取值：field=0 取种类，field=1 取层级。
   * 只认带段落语义的 run（种类/层级非 0），并优先取覆盖段首的那条 ——
   * 行内加粗等标注切出的 heading=0 分段不能把列表/标题读成正文。
   */
  private static paragraphAttrFor(runs: FormatRun[], start: number, end: number, field: number): number {
    let fallback: number = 0
    let hasFallback: boolean = false
    for (let i: number = 0; i < runs.length; i++) {
      const r: FormatRun = runs[i]
      if (r.endOffset <= start || r.startOffset >= end) {
        continue
      }
      if (r.heading === 0 && r.indent === 0) {
        continue
      }
      const value: number = field === 0 ? r.heading : r.indent
      if (r.startOffset <= start && r.endOffset > start) {
        return value
      }
      if (!hasFallback) {
        fallback = value
        hasFallback = true
      }
    }
    return hasFallback ? fallback : 0
  }

  /** 行内标记：按格式区间切分并包裹 ** / * */
  private static applyInlineMarkdown(line: string, runs: FormatRun[], base: number): string {
    const lineStart: number = base
    const lineEnd: number = base + line.length
    let out: string = ''
    let i: number = 0
    while (i < line.length) {
      const abs: number = lineStart + i
      let bold: boolean = false
      let italic: boolean = false
      let nextBoundary: number = lineEnd
      for (let r: number = 0; r < runs.length; r++) {
        const run: FormatRun = runs[r]
        if (abs >= run.startOffset && abs < run.endOffset) {
          bold = run.bold
          italic = run.italic
          if (run.endOffset < nextBoundary) {
            nextBoundary = run.endOffset
          }
        } else if (run.startOffset > abs && run.startOffset < nextBoundary) {
          nextBoundary = run.startOffset
        }
      }
      let j: number = i
      while (j < line.length && lineStart + j < nextBoundary) {
        j++
      }
      if (j <= i) {
        j = i + 1
      }
      let seg: string = line.substring(i, j)
      if (bold) {
        seg = '**' + seg + '**'
      }
      if (italic) {
        seg = '*' + seg + '*'
      }
      out += seg
      i = j
    }
    return out
  }

  /** 整本 → 目标格式的文本（逐篇加标题分隔） */
  static renderBook(bookTitle: string, chapters: ExportableChapter[], target: ExportFormat): string {
    if (target === ExportFormat.HTML) {
      let body: string = '<h1>' + MarkdownRenderer.escapeHtml(bookTitle) + '</h1>\n'
      for (const ch of chapters) {
        body += '<h2>' + MarkdownRenderer.escapeHtml(ch.title) + '</h2>\n'
        body += ExportService.htmlBodyOf(ch) + '\n<hr>\n'
      }
      return MarkdownRenderer.wrapHtmlDocument(bookTitle, body)
    }
    const parts: string[] = []
    for (let i: number = 0; i < chapters.length; i++) {
      const ch: ExportableChapter = chapters[i]
      const heading: string = target === ExportFormat.MD
        ? '# ' + ch.title
        : ch.title + '\n' + ExportService.repeatChar('=', ch.title.length)
      const text: string = target === ExportFormat.MD
        ? ExportService.sourceOf(ch)
        : ExportService.plainTextOf(ch)
      parts.push(heading + '\n\n' + text)
    }
    const join: string = target === ExportFormat.MD ? '\n\n---\n\n' : '\n\n\n'
    return bookTitle + '\n\n' + parts.join(join)
  }

  // 纯文本文稿转 HTML：逐行成段并转义，不走 Markdown 行内规则
  // （否则正文里的 *、_、反引号会被误当成强调标记）
  private static plainToHtml(text: string): string {
    return ExportService.formattedToHtml(text, '')
  }

  private static repeatChar(ch: string, count: number): string {
    let s: string = ''
    for (let i: number = 0; i < count; i++) {
      s += ch
    }
    return s
  }

  /** 先统一编码，再按实际写入的字节数推进；短写可能发生在 UTF-8 字符中间。 */
  private static async writeText(fd: number, text: string): Promise<void> {
    if (text.length === 0) {
      return
    }
    const bytes: Uint8Array = new util.TextEncoder().encodeInto(text)
    const buffer: ArrayBuffer = bytes.buffer as ArrayBuffer
    let offset: number = 0
    while (offset < bytes.byteLength) {
      const end: number = Math.min(offset + EXPORT_WRITE_CHUNK_BYTES, bytes.byteLength)
      const chunk: ArrayBuffer = buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + end)
      // 不传 WriteOptions.offset：该字段表示文件位置，默认文件指针会随实际写入推进。
      const written: number = await fileIo.write(fd, chunk)
      if (!Number.isInteger(written) || written <= 0 || written > chunk.byteLength) {
        throw new Error('文件写入未完成：无有效写入进度')
      }
      offset += written
    }
  }

  /** 弹系统保存框并写出文本 */
  static async saveText(defaultFileName: string, text: string): Promise<boolean> {
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [defaultFileName]
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
      const saveResult: Array<string> = await documentPicker.save(options)
      if (saveResult.length === 0) {
        return false
      }
      const uri: string = saveResult[0]
      const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
      let writeFailed: boolean = false
      try {
        await ExportService.writeText(file.fd, text)
        await fileIo.fsync(file.fd)
      } catch (e) {
        writeFailed = true
        throw e as Error
      } finally {
        try {
          await fileIo.close(file)
        } catch (e) {
          if (!writeFailed) {
            throw e as Error
          }
          // 关闭也失败时保留原始写入错误，便于调用方报告真正的失败原因。
          Logger.error('Export close after failure: ' + String(e))
        }
      }
      return true
    } catch (e) {
      Logger.error('Export failed: ' + String(e))
      throw e as Error
    }
  }

  /** 导出 JSON 备份载荷 */
  static async exportBackupJson(fileName: string, payload: Object): Promise<boolean> {
    return ExportService.saveText(fileName + '_backup.json', JSON.stringify(payload, null, 2))
  }

  /** 目标格式在保存框里的文件后缀与显示名 */
  static extensionOf(target: ExportFormat): string {
    if (target === ExportFormat.MD) return '.md'
    if (target === ExportFormat.HTML) return '.html'
    if (target === ExportFormat.JSON) return '.json'
    return '.txt'
  }
}
