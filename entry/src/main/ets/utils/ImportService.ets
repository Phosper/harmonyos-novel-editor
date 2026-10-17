// 导入服务 —— 系统文件选择器 → 读出内容并判定类型
// 支持 .txt / .md / .markdown / .html / .htm / .json（Weaver 备份）
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { Logger } from './Logger'
import { ChapterFormat } from '../model/Chapter'

export enum ImportKind {
  TEXT = 'text',
  MD = 'md',
  HTML = 'html',
  BACKUP = 'backup'
}

export interface ImportedFile {
  /** 文件名（含后缀） */
  fileName: string
  uri: string
  kind: ImportKind
  /** 作为文稿入库时的默认格式 */
  format: ChapterFormat
  text: string
}

const MAX_FILES: number = 20
const MAX_BYTES: number = 16 * 1024 * 1024

export class ImportService {

  /** 弹选择器并读出全部选中文件；读失败的文件会跳过并记日志 */
  static async pickAndRead(): Promise<ImportedFile[]> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions()
    options.maxSelectNumber = MAX_FILES
    options.fileSuffixFilters = ['文稿与备份|.txt,.md,.markdown,.html,.htm,.json']
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const uris: string[] = await documentPicker.select(options)
    const files: ImportedFile[] = []
    for (const uri of uris) {
      const name: string = ImportService.baseName(uri)
      try {
        const text: string = await ImportService.readText(uri)
        const kind: ImportKind = ImportService.kindOf(name)
        files.push({
          fileName: name,
          uri: uri,
          kind: kind,
          format: kind === ImportKind.MD ? ChapterFormat.MD : ChapterFormat.TXT,
          text: text
        })
      } catch (e) {
        Logger.error('Import skipped [' + name + ']: ' + String(e))
      }
    }
    return files
  }

  /** 去掉后缀的文件名，作为文稿标题 */
  static titleOf(file: ImportedFile): string {
    const dot: number = file.fileName.lastIndexOf('.')
    const base: string = dot > 0 ? file.fileName.substring(0, dot) : file.fileName
    return base.trim() === '' ? '未命名' : base.trim()
  }

  static kindOf(fileName: string): ImportKind {
    const name: string = fileName.toLowerCase()
    if (name.endsWith('.md') || name.endsWith('.markdown')) return ImportKind.MD
    if (name.endsWith('.html') || name.endsWith('.htm')) return ImportKind.HTML
    if (name.endsWith('.json')) return ImportKind.BACKUP
    return ImportKind.TEXT
  }

  private static baseName(uri: string): string {
    const parts: string[] = uri.split('/')
    const last: string = parts.length > 0 ? parts[parts.length - 1] : uri
    let name: string = last
    try {
      name = decodeURIComponent(last)
    } catch (e) {
      name = last
    }
    const query: number = name.indexOf('?')
    return query > 0 ? name.substring(0, query) : name
  }

  /** 从已取得访问权限的文件读取完整 UTF-8 文本，拒绝不完整的读取。 */
  static async readText(uri: string): Promise<string> {
    const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat: fileIo.Stat = await fileIo.stat(file.fd)
      const size: number = stat.size
      if (size <= 0) {
        return ''
      }
      if (size > MAX_BYTES) {
        throw new Error('文件过大（' + size + ' 字节），上限 ' + MAX_BYTES)
      }
      const bytes: Uint8Array = new Uint8Array(size)
      let offset: number = 0
      while (offset < size) {
        // read 的 offset 是文件位置，并非写入目标缓冲区的位置；每块需显式拼接。
        // 不传 offset，沿当前文件指针连续读取，支持短读及跨块的 UTF-8 字符。
        const chunk: ArrayBuffer = new ArrayBuffer(Math.min(64 * 1024, size - offset))
        const readLen: number = await fileIo.read(file.fd, chunk, { length: chunk.byteLength })
        if (readLen <= 0) {
          throw new Error('文件读取未完成，请重试')
        }
        bytes.set(new Uint8Array(chunk, 0, readLen), offset)
        offset += readLen
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true })
      return decoder.decodeToString(bytes)
    } finally {
      await fileIo.close(file)
    }
  }
}
