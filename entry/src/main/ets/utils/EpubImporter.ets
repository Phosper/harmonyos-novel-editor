// EPUB 导入的设备侧：把用户选的文件复制到缓存 → 解压 → 只读需要的文本 → 交给纯解析器
//
// 为什么不像 txt/md 那样直接读字符串：EPUB 是 zip（二进制）。
// 为什么只读"container → OPF → spine 指向的章节"而不是遍历全部文件：
//   1) 不依赖 listFile 的递归返回值行为（各版本有差异）；
//   2) 只读真正要用的文件，大书也不会把图片全读进内存。
import { fileIo } from '@kit.CoreFileKit'
import { zlib } from '@kit.BasicServicesKit'
import { Logger } from './Logger'
import { ImportService } from './ImportService'
import { epubContainerRootPath, epubOpfInfo, parseEpub } from './EpubParser'
import type { EpubBook, EpubFile, EpubOpfInfo } from './EpubParser'

const COPY_CHUNK_BYTES: number = 64 * 1024

export class EpubImporter {
  /**
   * 解析一本 EPUB。
   * @param uri 文件选择器给的内容 URI
   * @param cacheDir 应用缓存目录（解压临时区建在这里）
   * @returns 解析结果；任何一步失败返回 undefined（调用方提示，不抛到 UI）
   */
  static async load(uri: string, cacheDir: string): Promise<EpubBook | undefined> {
    const workDir: string = cacheDir + '/epub_' + Date.now().toString()
    const zipPath: string = workDir + '/book.epub'
    const outDir: string = workDir + '/out'
    try {
      await fileIo.mkdir(workDir, true)
      await EpubImporter.copyTo(uri, zipPath)
      await zlib.decompressFile(zipPath, outDir)
      const containerText: string = await ImportService.readText(outDir + '/META-INF/container.xml')
      const opfRel: string = epubContainerRootPath(containerText)
      if (opfRel === '') {
        Logger.error('EPUB: container.xml has no rootfile')
        return undefined
      }
      const opfText: string = await ImportService.readText(outDir + '/' + opfRel)
      const info: EpubOpfInfo = epubOpfInfo(opfText, opfRel)
      const files: EpubFile[] = []
      files.push({ path: 'META-INF/container.xml', text: containerText })
      files.push({ path: opfRel, text: opfText })
      for (let i: number = 0; i < info.spinePaths.length; i++) {
        const rel: string = info.spinePaths[i]
        try {
          const text: string = await ImportService.readText(outDir + '/' + rel)
          files.push({ path: rel, text: text })
        } catch (e) {
          // spine 里引用了缺失文件：跳过这一章，不整本失败
          Logger.warn('EPUB: chapter missing ' + rel + ' :: ' + String(e))
        }
      }
      return parseEpub(files)
    } catch (e) {
      Logger.error('EPUB import failed: ' + String(e))
      return undefined
    } finally {
      await EpubImporter.cleanup(workDir)
    }
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
