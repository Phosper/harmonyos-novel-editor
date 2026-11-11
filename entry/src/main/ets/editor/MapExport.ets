// 导图导出的宿主实现：文本直接写文件，图片先打包成 PNG 再写。
//
// 为什么放在宿主：写文件要弹系统保存框（picker），而且 PixelMap 的打包属于
// 系统能力；结构包只负责"把结构变成文本 / 抓一张图"，不认识文件系统。
import { image } from '@kit.ImageKit'
import { ExportService } from '../utils/ExportService'
import { OUTLINE_EXPORT_PNG } from 'feature_contracts'
import { Logger } from '../utils/Logger'

/** 文件名里的非法字符换成下划线，避免保存框直接报错 */
function safeName(title: string): string {
  const trimmed: string = title.trim() === '' ? '导图' : title.trim()
  let out: string = ''
  for (let i: number = 0; i < trimmed.length && i < 40; i++) {
    const ch: string = trimmed.charAt(i)
    if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' || ch === '"' ||
      ch === '<' || ch === '>' || ch === '|') {
      out += '_'
    } else {
      out += ch
    }
  }
  return out
}

async function savePng(fileName: string, pixelMap: image.PixelMap): Promise<boolean> {
  const packer: image.ImagePacker = image.createImagePacker()
  try {
    const options: image.PackingOption = { format: 'image/png', quality: 100 }
    const buffer: ArrayBuffer = await packer.packing(pixelMap, options)
    return ExportService.saveBytes(fileName, buffer)
  } finally {
    try {
      packer.release()
    } catch (e) {
      Logger.warn('MapExport: packer release failed: ' + String(e))
    }
  }
}

/**
 * 受理一次导出。
 * 返回 false 只表示"没受理"（没有页面可抓/参数不全）；写文件是异步的，
 * 失败会在日志里留痕（保存框被用户取消属于正常路径）。
 */
export function exportOutlineFile(format: string, text: string, pixelMap: image.PixelMap | null,
  title: string): boolean {
  const base: string = safeName(title)
  if (format === OUTLINE_EXPORT_PNG) {
    if (pixelMap === null) {
      return false
    }
    savePng(base + '.png', pixelMap).catch((e: Error): void => {
      Logger.error('MapExport: png save failed: ' + String(e))
    })
    return true
  }
  if (text === '') {
    return false
  }
  const name: string = format === 'opml' ? (base + '.opml') : (format === 'mm' ? (base + '.mm') : (base + '.md'))
  ExportService.saveText(name, text).catch((e: Error): void => {
    Logger.error('MapExport: text save failed: ' + String(e))
  })
  return true
}
