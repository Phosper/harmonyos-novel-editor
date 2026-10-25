// 头像上传：系统图库选择器 → 复制进应用沙箱 → 返回本地文件路径
//
// 为什么必须复制：PhotoViewPicker 返回的是媒体库 URI（file://media/Photo/...），
// 该 URI 的读权限只对本次会话有效。直接把 URI 存进首选项，重启后取不到图，
// 头像是空白。所以选完立刻把字节复制到 filesDir，头像只认沙箱里的绝对路径。
//
// 不申请读媒体权限：PhotoViewPicker 由系统代选，选中的单张图授权给本应用，
// 复制完成后权限即可丢弃（module.json5 无需新增权限声明）。
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo as fs, fileUri } from '@kit.CoreFileKit'
import { Logger } from './Logger'

const AVATAR_PREFIX: string = '/avatar_'
const DEFAULT_EXT: string = '.jpg'

export class AvatarService {
  /**
   * 弹出系统图库（只看图片、单选），选中后复制到 filesDir。
   * 返回沙箱绝对路径；用户取消或失败返回空串（调用方据此保持原头像）。
   */
  static async pickAndCopy(filesDir: string): Promise<string> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options)
      const uris: string[] = result.photoUris
      if (uris.length === 0) {
        return ''
      }
      return AvatarService.copyToSandbox(uris[0], filesDir)
    } catch (e) {
      Logger.error('AvatarService: pick failed: ' + String(e))
      return ''
    }
  }

  /** 读源 fd → 写目标 fd；文件名带时间戳，避免覆盖正在被 Image 引用的旧文件 */
  private static copyToSandbox(uri: string, filesDir: string): string {
    const target: string = filesDir + AVATAR_PREFIX + Date.now() + AvatarService.extOf(uri)
    let src: fs.File | null = null
    let out: fs.File | null = null
    try {
      src = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      out = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.copyFileSync(src.fd, out.fd)
      return target
    } catch (e) {
      Logger.error('AvatarService: copy failed: ' + String(e))
      return ''
    } finally {
      AvatarService.closeQuietly(src)
      AvatarService.closeQuietly(out)
    }
  }

  /** 换头像/移除头像后清掉旧文件，避免沙箱里越攒越多 */
  static removeFile(path: string): void {
    if (path === '') {
      return
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path)
      }
    } catch (e) {
      Logger.warn('AvatarService: remove failed: ' + String(e))
    }
  }

  static exists(path: string): boolean {
    if (path === '') {
      return false
    }
    try {
      return fs.accessSync(path)
    } catch (e) {
      return false
    }
  }

  /**
   * Image 只认应用沙箱 URI（file://<bundleName>/<sandboxPath>），不是文件系统绝对路径。
   * 用官方 fileUri.getUriFromPath 转换；失败返回空串，调用方回落到占位人像。
   */
  static toImageSrc(path: string): string {
    if (path === '') {
      return ''
    }
    try {
      return fileUri.getUriFromPath(path)
    } catch (e) {
      Logger.error('AvatarService: toImageSrc failed: ' + String(e))
      return ''
    }
  }

  private static closeQuietly(file: fs.File | null): void {
    if (file === null) {
      return
    }
    try {
      fs.closeSync(file)
    } catch (e) {
      Logger.warn('AvatarService: close failed: ' + String(e))
    }
  }

  /** 取 URI 后缀；媒体库 URI 可能带查询串，先截掉 */
  private static extOf(uri: string): string {
    const clean: string = uri.split('?')[0]
    const dot: number = clean.lastIndexOf('.')
    if (dot < 0 || dot < clean.length - 6) {
      return DEFAULT_EXT
    }
    const ext: string = clean.substring(dot).toLowerCase()
    if (ext === '.jpg' || ext === '.jpeg' || ext === '.png' || ext === '.webp' || ext === '.heic') {
      return ext
    }
    return DEFAULT_EXT
  }
}
