// HTML → 纯文本 / 标题提取（最小实现，面向"导入网页正文到文稿"）
// 只做块级换行 + 标签剥离 + 常见实体解码；不做 DOM 解析，够用且零依赖。
export class HtmlText {

  /** 取文档标题：优先 <title>，其次第一个 <h1>，都没有则返回空串 */
  static titleOf(html: string): string {
    const title: RegExpMatchArray | null =
      html.match(new RegExp('<title[^>]*>([\\s\\S]*?)</title>', 'i'))
    if (title !== null) {
      return HtmlText.decodeEntities(title[1]).trim()
    }
    const h1: RegExpMatchArray | null = html.match(new RegExp('<h1[^>]*>([\\s\\S]*?)</h1>', 'i'))
    if (h1 !== null) {
      return HtmlText.decodeEntities(HtmlText.stripTags(h1[1])).trim()
    }
    return ''
  }

  /** 剥掉全部标签，仅保留文字 */
  static stripTags(html: string): string {
    return html.replace(new RegExp('<[^>]*>', 'g'), '')
  }

  /**
   * HTML → 纯文本。块级元素转行、行内标签剥离、实体解码、压缩连续空行。
   * 返回的文本可直接作为文稿正文，不保留任何 HTML 结构。
   */
  static toPlainText(html: string): string {
    let s: string = html
    // 丢弃脚本/样式/注释整段内容
    s = s.replace(new RegExp('<script[^>]*>[\\s\\S]*?</script>', 'gi'), '')
    s = s.replace(new RegExp('<style[^>]*>[\\s\\S]*?</style>', 'gi'), '')
    s = s.replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), '')
    s = s.replace(new RegExp('<head[^>]*>[\\s\\S]*?</head>', 'gi'), '')
    // 块级边界 → 换行
    s = s.replace(new RegExp('<br\\s*/?>', 'gi'), '\n')
    s = s.replace(new RegExp('</(p|div|section|article|li|tr|h[1-6]|blockquote|pre|dd|dt)\\s*>', 'gi'), '\n')
    s = s.replace(new RegExp('<hr\\s*/?>', 'gi'), '\n')
    // 剩余标签剥离
    s = s.replace(new RegExp('<[^>]*>', 'g'), '')
    // 实体解码
    s = HtmlText.decodeEntities(s)
    // 行内多余空白压缩，但保留段落结构
    s = s.replace(new RegExp('[ \\t\\u00a0]+', 'g'), ' ')
    s = s.replace(new RegExp(' *\\n *', 'g'), '\n')
    s = s.replace(new RegExp('\\n{3,}', 'g'), '\n\n')
    return s.trim()
  }

  /** 常见命名实体解码（&amp; 必须最后处理，避免二次解码） */
  static decodeEntities(text: string): string {
    let s: string = text
    s = s.replace(new RegExp('&nbsp;', 'g'), ' ')
    s = s.replace(new RegExp('&lt;', 'g'), '<')
    s = s.replace(new RegExp('&gt;', 'g'), '>')
    s = s.replace(new RegExp('&quot;', 'g'), '"')
    s = s.replace(new RegExp('&apos;', 'g'), "'")
    s = s.replace(new RegExp('&#39;', 'g'), "'")
    s = s.replace(new RegExp('&mdash;', 'g'), '—')
    s = s.replace(new RegExp('&ndash;', 'g'), '–')
    s = s.replace(new RegExp('&hellip;', 'g'), '…')
    s = s.replace(new RegExp('&ldquo;', 'g'), '“')
    s = s.replace(new RegExp('&rdquo;', 'g'), '”')
    s = s.replace(new RegExp('&lsquo;', 'g'), '‘')
    s = s.replace(new RegExp('&rsquo;', 'g'), '’')
    s = s.replace(new RegExp('&amp;', 'g'), '&')
    return s
  }
}
