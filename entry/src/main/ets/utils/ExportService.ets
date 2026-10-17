// 导出服务 —— 支持 TXT / Markdown / HTML / JSON 备份，单篇与整本两种粒度
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Logger } from './Logger'
import { ChapterFormat } from '../model/Chapter'
import { MarkdownRenderer } from './MarkdownRenderer'
import { FormatRun } from '../editor/flowtext/model/EditorTypes'
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
    const source: string = ExportService.sourceOf(chapter)
    const isMarkdownSource: boolean = chapter.format === ChapterFormat.MD || ExportService.hasFormat(chapter)
    if (target === ExportFormat.MD) {
      return source
    }
    if (target === ExportFormat.HTML) {
      const body: string = isMarkdownSource
        ? MarkdownRenderer.toHtmlBody(source)
        : ExportService.plainToHtml(source)
      return MarkdownRenderer.wrapHtmlDocument(documentTitle, body)
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
      const level: number = ExportService.headingFor(runs, base)
      let text: string = ExportService.applyInlineMarkdown(line, runs, base)
      if (level > 0) {
        text = '######'.substring(0, level) + ' ' + text
      }
      out.push(text)
      base += line.length + 1
    }
    return out.join('\n')
  }

  private static headingFor(runs: FormatRun[], offset: number): number {
    for (let i: number = 0; i < runs.length; i++) {
      const r: FormatRun = runs[i]
      if (offset >= r.startOffset && offset < r.endOffset) {
        return r.heading
      }
    }
    return 0
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
        const chSource: string = ExportService.sourceOf(ch)
        const chIsMd: boolean = ch.format === ChapterFormat.MD || ExportService.hasFormat(ch)
        body += (chIsMd
          ? MarkdownRenderer.toHtmlBody(chSource)
          : ExportService.plainToHtml(chSource)) + '\n<hr>\n'
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
    const lines: string[] = text.replace(new RegExp('\\r\\n', 'g'), '\n').split('\n')
    const out: string[] = []
    for (const line of lines) {
      if (line.trim() === '') {
        continue
      }
      out.push('<p>' + MarkdownRenderer.escapeHtml(line) + '</p>')
    }
    return out.join('\n')
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
