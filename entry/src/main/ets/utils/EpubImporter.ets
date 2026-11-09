// EPUB 导入的设备侧：复制 → 解压 → 读 container/OPF/章节 → 交给纯解析器
//
// 设计要点：
// 1) 失败要能说清"卡在哪一步"：返回 EpubLoadResult（错误码 + 一句人话），
//    不再只返回 undefined 让 UI 干说"跳过一个"。
// 2) 不假设包内结构：container.xml 缺了就先扫一遍找 *.opf；OPF 也没有就按 xhtml 兜底。
// 3) 只读用的文件，不遍历全部资源：大书不把图片读进内存。
import { fileIo } from '@kit.CoreFileKit'
import { zlib } from '@kit.BasicServicesKit'
import { Logger } from './Logger'
import { ImportService } from './ImportService'
import { epubContainerRootPath, epubOpfInfo, parseEpub } from './EpubParser'
import type { EpubBook, EpubFile, EpubOpfInfo } from './EpubParser'

const COPY_CHUNK_BYTES: number = 64 * 1024
/** 兜底扫描时最多读多少个 xhtml（防止有人在 zip 里塞上万个小文件） */
const MAX_FALLBACK_CHAPTERS: number = 200

export enum EpubError {
  OK = 0,
  COPY_FAILED = 1,
  UNZIP_FAILED = 2,
  NO_CONTAINER = 3,
  NO_OPF = 4,
  NO_CHAPTERS = 5
}

export class EpubLoadResult {
  book: EpubBook | undefined = undefined
  error: EpubError = EpubError.OK
  /** 给用户看的一句话（尽量短，toast 只有两行） */
  detail: string = ''

  constructor(error: EpubError = EpubError.OK, detail: string = '') {
    this.error = error
    this.detail = detail
  }
}

function epubLog(text: string): void {
  // hilog 里按 [EPUB] 过滤即可看到每一步
  console.info('[EPUB] ' + text)
}

export class EpubImporter {
  /**
   * 解析一本 EPUB。
   * @param uri 文件选择器给的内容 URI
   * @param cacheDir 应用缓存目录（解压临时区建在这里）
   */
  static async load(uri: string, cacheDir: string): Promise<EpubLoadResult> {
    const workDir: string = cacheDir + '/epub_' + Date.now().toString()
    const zipPath: string = workDir + '/book.epub'
    const outDir: string = workDir + '/out'
    try {
      await fileIo.mkdir(workDir, true)
      await EpubImporter.copyTo(uri, zipPath)
      epubLog('step=copy ok')
      // 解压目标必须先存在：部分版本不会替你建目录
      await fileIo.mkdir(outDir, true)
      try {
        await zlib.decompressFile(zipPath, outDir)
      } catch (e) {
        epubLog('step=unzip failed :: ' + String(e))
        return new EpubLoadResult(EpubError.UNZIP_FAILED, '解压失败（可能是加密/DRM 或文件损坏）')
      }
      epubLog('step=unzip ok')
      return await EpubImporter.parseFrom(outDir)
    } catch (e) {
      epubLog('step=copy failed :: ' + String(e))
      return new EpubLoadResult(EpubError.COPY_FAILED, '无法读取所选文件')
    } finally {
      await EpubImporter.cleanup(workDir)
    }
  }

  /** 解压后的目录 → 书（container → OPF → spine；缺失时逐级兜底） */
  private static async parseFrom(outDir: string): Promise<EpubLoadResult> {
    const files: EpubFile[] = []
    // 1) container.xml（大小写/层级都可能不同，先试常见写法，再扫一遍）
    let containerRel: string = await EpubImporter.locate(outDir, 'container.xml', 'meta-inf/container.xml')
    if (containerRel !== '') {
      const text: string = await EpubImporter.read(outDir, containerRel)
      files.push({ path: 'META-INF/container.xml', text: text })
      epubLog('step=container ok rel=' + containerRel)
    } else {
      epubLog('step=container missing')
    }
    // 2) OPF：先按 container 指路，找不到就扫 *.opf
    let opfRel: string = ''
    if (files.length > 0) {
      opfRel = epubContainerRootPath(files[0].text)
      if (opfRel !== '' && !(await EpubImporter.exists(outDir, opfRel))) {
        epubLog('step=opf missing at ' + opfRel)
        opfRel = ''
      }
    }
    if (opfRel === '') {
      opfRel = await EpubImporter.locate(outDir, '.opf', '')
    }
    let info: EpubOpfInfo = { title: '', author: '', spinePaths: [] }
    if (opfRel !== '') {
      const opfText: string = await EpubImporter.read(outDir, opfRel)
      files.push({ path: opfRel, text: opfText })
      info = epubOpfInfo(opfText, opfRel)
      epubLog('step=opf ok rel=' + opfRel + ' spine=' + info.spinePaths.length.toString())
    } else {
      epubLog('step=opf missing')
    }
    // 3) 读 spine 指向的章节；一个都没有就扫 html
    for (let i: number = 0; i < info.spinePaths.length; i++) {
      const rel: string = info.spinePaths[i]
      if (!(await EpubImporter.exists(outDir, rel))) {
        epubLog('step=chapter missing ' + rel)
        continue
      }
      files.push({ path: rel, text: await EpubImporter.read(outDir, rel) })
    }
    if (files.length <= 1) {
      const htmls: string[] = await EpubImporter.listBySuffix(outDir,
        ['.xhtml', '.html', '.htm'], MAX_FALLBACK_CHAPTERS)
      for (let i: number = 0; i < htmls.length; i++) {
        files.push({ path: htmls[i], text: await EpubImporter.read(outDir, htmls[i]) })
      }
      epubLog('step=fallback html=' + htmls.length.toString())
    }
    const book: EpubBook | undefined = parseEpub(files)
    if (book === undefined) {
      epubLog('step=no chapters files=' + files.length.toString())
      return new EpubLoadResult(EpubError.NO_CHAPTERS, '没有找到可导入的正文')
    }
    epubLog('step=done title=' + book.title + ' chapters=' + book.chapters.length.toString())
    const result: EpubLoadResult = new EpubLoadResult(EpubError.OK, '')
    result.book = book
    return result
  }

  // ===== 包内文件访问（都相对解压目录） =====

  private static async exists(outDir: string, rel: string): Promise<boolean> {
    try {
      const file: fileIo.File = await fileIo.open(outDir + '/' + rel, fileIo.OpenMode.READ_ONLY)
      await fileIo.close(file)
      return true
    } catch (e) {
      return false
    }
  }

  private static async read(outDir: string, rel: string): Promise<string> {
    try {
      return await ImportService.readText(outDir + '/' + rel)
    } catch (e) {
      return ''
    }
  }

  /** 递归列出文件（相对路径）；任何失败都当作"列不出来" */
  private static async list(outDir: string): Promise<string[]> {
    try {
      const names: string[] = await fileIo.listFile(outDir, { recursion: true })
      return names
    } catch (e) {
      epubLog('list failed :: ' + String(e))
      return []
    }
  }

  /**
   * 在解压目录里找一个文件：
   *  - candidate 是首选相对路径（可空）
   *  - suffix 用于扫描匹配（如 '.opf'、'container.xml'）
   */
  private static async locate(outDir: string, suffix: string, candidate: string): Promise<string> {
    if (candidate !== '' && await EpubImporter.exists(outDir, candidate)) {
      return candidate
    }
    const names: string[] = await EpubImporter.list(outDir)
    const lowered: string = suffix.toLowerCase()
    for (let i: number = 0; i < names.length; i++) {
      const name: string = names[i]
      const lower: string = name.toLowerCase()
      const hit: boolean = lowered === '.opf' ? lower.endsWith('.opf')
        : (lower === lowered || lower.endsWith('/' + lowered))
      if (hit) {
        // listFile 可能返回相对路径，也可能带 outDir 前缀，统一成相对
        return name.startsWith(outDir + '/') ? name.substring(outDir.length + 1) : name
      }
    }
    return ''
  }

  private static async listBySuffix(outDir: string, suffixes: string[], limit: number): Promise<string[]> {
    const names: string[] = await EpubImporter.list(outDir)
    const out: string[] = []
    for (let i: number = 0; i < names.length && out.length < limit; i++) {
      const lower: string = names[i].toLowerCase()
      for (let s: number = 0; s < suffixes.length; s++) {
        if (lower.endsWith(suffixes[s])) {
          out.push(names[i].startsWith(outDir + '/') ? names[i].substring(outDir.length + 1) : names[i])
          break
        }
      }
    }
    out.sort((a: string, b: string): number => a < b ? -1 : (a > b ? 1 : 0))
    return out
  }

  /** URI → 沙箱文件（选择器给的是内容 URI，zlib 只认路径） */
  private static async copyTo(uri: string, dest: string): Promise<void> {
    const src: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    const dst: fileIo.File = await fileIo.open(dest,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(COPY_CHUNK_BYTES)
      for (;;) {
        const length: number = await fileIo.read(src.fd, buffer)
        if (length <= 0) {
          break
        }
        await fileIo.write(dst.fd, buffer, { length: length })
      }
    } finally {
      await fileIo.close(src)
      await fileIo.close(dst)
    }
  }

  /** 临时目录必须清掉：解压出来的 xhtml 可能很多 */
  private static async cleanup(dir: string): Promise<void> {
    try {
      await fileIo.rmdir(dir)
    } catch (e) {
      Logger.warn('EPUB cleanup failed: ' + String(e))
    }
  }
}
