// 导图 → 文本格式（M6/X5）。
//
// 为什么是这三种：Xmind 自己就能导入 Markdown / OPML / FreeMind，
// 而 SDK 里没有"内存里打 zip"的能力（zlib 只有按文件的 gzip），造不出真正的 .xmind。
// 所以对外互通走这三条纯文本通道 —— 全是纯函数，可以在 Node 里逐字符回归。
import { OutlineSnapshot } from './OutlineLayout'
import type { OutlineNode } from './OutlineLayout'

/** XML 属性转义：文本里可能有引号、尖括号（标题常常带） */
function escapeXml(text: string): string {
  let out: string = ''
  for (let i: number = 0; i < text.length; i++) {
    const ch: string = text.charAt(i)
    if (ch === '&') {
      out += '&amp;'
    } else if (ch === '<') {
      out += '&lt;'
    } else if (ch === '>') {
      out += '&gt;'
    } else if (ch === '"') {
      out += '&quot;'
    } else if (ch === '\'') {
      out += '&apos;'
    } else {
      out += ch
    }
  }
  return out
}

/** 按 parentIndex 把扁平节点整理成"父 → 子下标"，再递归生成，三条格式共用 */
function childrenOf(nodes: OutlineNode[]): Map<number, number[]> {
  const map: Map<number, number[]> = new Map<number, number[]>()
  for (let i: number = 0; i < nodes.length; i++) {
    map.set(i, [])
  }
  for (let i: number = 1; i < nodes.length; i++) {
    const parent: number = nodes[i].parentIndex
    const kids: number[] | undefined = map.get(parent)
    if (kids !== undefined) {
      kids.push(i)
    }
  }
  return map
}

/**
 * Markdown：根当一级标题，其余按层级缩进成列表。
 * 缩进用两个空格（CommonMark 里 2 空格就能表达嵌套）。
 */
export function outlineMarkdown(snapshot: OutlineSnapshot): string {
  if (snapshot.nodes.length === 0) {
    return ''
  }
  const kidsOf: Map<number, number[]> = childrenOf(snapshot.nodes)
  const lines: string[] = []
  const root: OutlineNode = snapshot.nodes[0]
  lines.push('# ' + root.title)
  lines.push('')
  const walk = (index: number, depth: number): void => {
    const kids: number[] = kidsOf.get(index) === undefined ? [] : kidsOf.get(index) as number[]
    for (let k: number = 0; k < kids.length; k++) {
      const node: OutlineNode = snapshot.nodes[kids[k]]
      let pad: string = ''
      for (let i: number = 1; i < depth; i++) {
        pad += '  '
      }
      lines.push(pad + '- ' + node.title)
      walk(kids[k], depth + 1)
    }
  }
  walk(0, 1)
  return lines.join('\n') + '\n'
}

/** OPML：大纲的标准格式（Xmind / 幕布 / 各种大纲工具都认） */
export function outlineOpml(snapshot: OutlineSnapshot): string {
  if (snapshot.nodes.length === 0) {
    return ''
  }
  const kidsOf: Map<number, number[]> = childrenOf(snapshot.nodes)
  const root: OutlineNode = snapshot.nodes[0]
  const lines: string[] = []
  lines.push('<?xml version="1.0" encoding="UTF-8"?>')
  lines.push('<opml version="2.0">')
  lines.push('  <head>')
  lines.push('    <title>' + escapeXml(root.title) + '</title>')
  lines.push('  </head>')
  lines.push('  <body>')
  const walk = (index: number, depth: number): void => {
    let pad: string = '    '
    for (let i: number = 0; i < depth; i++) {
      pad += '  '
    }
    const node: OutlineNode = snapshot.nodes[index]
    const kids: number[] = kidsOf.get(index) === undefined ? [] : kidsOf.get(index) as number[]
    if (kids.length === 0) {
      lines.push(pad + '<outline text="' + escapeXml(node.title) + '"/>')
      return
    }
    lines.push(pad + '<outline text="' + escapeXml(node.title) + '">')
    for (let k: number = 0; k < kids.length; k++) {
      walk(kids[k], depth + 1)
    }
    lines.push(pad + '</outline>')
  }
  walk(0, 0)
  lines.push('  </body>')
  lines.push('</opml>')
  return lines.join('\n') + '\n'
}

/** FreeMind（.mm）：Xmind 能直接导入的另一种纯文本格式 */
export function outlineFreemind(snapshot: OutlineSnapshot): string {
  if (snapshot.nodes.length === 0) {
    return ''
  }
  const kidsOf: Map<number, number[]> = childrenOf(snapshot.nodes)
  const lines: string[] = []
  lines.push('<map version="1.0.1">')
  const walk = (index: number, depth: number): void => {
    let pad: string = ''
    for (let i: number = 0; i < depth; i++) {
      pad += '  '
    }
    const node: OutlineNode = snapshot.nodes[index]
    const kids: number[] = kidsOf.get(index) === undefined ? [] : kidsOf.get(index) as number[]
    if (kids.length === 0) {
      lines.push(pad + '<node TEXT="' + escapeXml(node.title) + '"/>')
      return
    }
    lines.push(pad + '<node TEXT="' + escapeXml(node.title) + '">')
    for (let k: number = 0; k < kids.length; k++) {
      walk(kids[k], depth + 1)
    }
    lines.push(pad + '</node>')
  }
  walk(0, 0)
  lines.push('</map>')
  return lines.join('\n') + '\n'
}

/** 导出格式（页面按钮与宿主的保存逻辑共用这几个字符串） */
export const OUTLINE_EXPORT_MD: string = 'md'
export const OUTLINE_EXPORT_OPML: string = 'opml'
export const OUTLINE_EXPORT_FREEMIND: string = 'mm'
export const OUTLINE_EXPORT_PNG: string = 'png'

/** 格式 → 默认文件名后缀 */
export function outlineExportExtension(format: string): string {
  if (format === OUTLINE_EXPORT_OPML) {
    return '.opml'
  }
  if (format === OUTLINE_EXPORT_FREEMIND) {
    return '.mm'
  }
  if (format === OUTLINE_EXPORT_PNG) {
    return '.png'
  }
  return '.md'
}
