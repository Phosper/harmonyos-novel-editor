// Markdown → HTML 渲染（最小可用子集，面向小说/长文本）
// 支持：标题 #~######、粗体 **__、斜体 *_、删除线 ~~、行内代码 `、
//       引用 >、无序列表 - *、有序列表 1.、分隔线 ---、代码围栏 ```、段落与软换行。
// 刻意不支持表格/图片/链接语法：长篇正文实际用不到，且减少解析面。
export class MarkdownRenderer {

  static escapeHtml(text: string): string {
    let out: string = text
    out = out.replace(new RegExp('&', 'g'), '&amp;')
    out = out.replace(new RegExp('<', 'g'), '&lt;')
    out = out.replace(new RegExp('>', 'g'), '&gt;')
    out = out.replace(new RegExp('"', 'g'), '&quot;')
    return out
  }

  /** 行内标记（输入必须是已转义的文本） */
  private static inline(escaped: string): string {
    let s: string = escaped
    s = s.replace(new RegExp('`([^`]+)`', 'g'), '<code>$1</code>')
    s = s.replace(new RegExp('\\*\\*([^*]+)\\*\\*', 'g'), '<strong>$1</strong>')
    s = s.replace(new RegExp('__([^_]+)__', 'g'), '<strong>$1</strong>')
    s = s.replace(new RegExp('~~([^~]+)~~', 'g'), '<del>$1</del>')
    s = s.replace(new RegExp('\\*([^*]+)\\*', 'g'), '<em>$1</em>')
    s = s.replace(new RegExp('_([^_]+)_', 'g'), '<em>$1</em>')
    return s
  }

  /** Markdown 正文 → HTML 片段 */
  static toHtmlBody(markdown: string): string {
    const lines: string[] = markdown.replace(new RegExp('\\r\\n', 'g'), '\n').split('\n')
    const out: string[] = []
    let paragraph: string[] = []
    let quote: string[] = []
    let listOpen: string = ''      // 'ul' | 'ol' | ''
    let inFence: boolean = false
    let fence: string[] = []

    const flushParagraph = (): void => {
      if (paragraph.length > 0) {
        out.push('<p>' + paragraph.join('<br>') + '</p>')
        paragraph = []
      }
    }
    const flushQuote = (): void => {
      if (quote.length > 0) {
        out.push('<blockquote>' + quote.join('<br>') + '</blockquote>')
        quote = []
      }
    }
    const closeList = (): void => {
      if (listOpen !== '') {
        out.push('</' + listOpen + '>')
        listOpen = ''
      }
    }
    const flushAll = (): void => {
      flushParagraph()
      flushQuote()
      closeList()
    }

    for (const raw of lines) {
      const line: string = raw
      const trimmed: string = line.trim()

      // 代码围栏
      if (trimmed.startsWith('```')) {
        if (inFence) {
          out.push('<pre><code>' + MarkdownRenderer.escapeHtml(fence.join('\n')) + '</code></pre>')
          fence = []
          inFence = false
        } else {
          flushAll()
          inFence = true
          fence = []
        }
        continue
      }
      if (inFence) {
        fence.push(line)
        continue
      }

      // 空行
      if (trimmed === '') {
        flushAll()
        continue
      }

      // 分隔线
      if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
        flushAll()
        out.push('<hr>')
        continue
      }

      // 标题
      const heading: RegExpMatchArray | null = trimmed.match(new RegExp('^(#{1,6})\\s+(.*)$'))
      if (heading !== null) {
        flushAll()
        const level: number = heading[1].length
        out.push('<h' + level + '>' + MarkdownRenderer.inline(MarkdownRenderer.escapeHtml(heading[2])) +
          '</h' + level + '>')
        continue
      }

      // 引用
      if (trimmed.startsWith('> ')) {
        flushParagraph()
        closeList()
        quote.push(MarkdownRenderer.inline(MarkdownRenderer.escapeHtml(trimmed.substring(2))))
        continue
      }

      // 无序列表
      const bullet: RegExpMatchArray | null = trimmed.match(new RegExp('^[-*]\\s+(.*)$'))
      if (bullet !== null) {
        flushParagraph()
        flushQuote()
        if (listOpen !== 'ul') {
          closeList()
          out.push('<ul>')
          listOpen = 'ul'
        }
        out.push('<li>' + MarkdownRenderer.inline(MarkdownRenderer.escapeHtml(bullet[1])) + '</li>')
        continue
      }

      // 有序列表
      const ordered: RegExpMatchArray | null = trimmed.match(new RegExp('^\\d+\\.\\s+(.*)$'))
      if (ordered !== null) {
        flushParagraph()
        flushQuote()
        if (listOpen !== 'ol') {
          closeList()
          out.push('<ol>')
          listOpen = 'ol'
        }
        out.push('<li>' + MarkdownRenderer.inline(MarkdownRenderer.escapeHtml(ordered[1])) + '</li>')
        continue
      }

      // 普通段落行
      flushQuote()
      closeList()
      paragraph.push(MarkdownRenderer.inline(MarkdownRenderer.escapeHtml(trimmed)))
    }

    // 收尾：未闭合的围栏按代码块输出，避免内容丢失
    if (inFence) {
      out.push('<pre><code>' + MarkdownRenderer.escapeHtml(fence.join('\n')) + '</code></pre>')
    }
    flushAll()
    return out.join('\n')
  }

  /** 包裹为独立 HTML 文档（自带排版样式，供浏览器/Web 组件查看） */
  static wrapHtmlDocument(title: string, bodyHtml: string): string {
    const safeTitle: string = MarkdownRenderer.escapeHtml(title)
    return '<!DOCTYPE html>\n' +
      '<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n' +
      '<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
      '<title>' + safeTitle + '</title>\n' +
      '<style>\n' +
      'body{margin:0 auto;padding:32px 20px 64px;max-width:42em;' +
      'font-family:system-ui,-apple-system,"HarmonyOS Sans SC",serif;' +
      'font-size:17px;line-height:2;color:#1a1a1a;background:#fff;' +
      'word-wrap:break-word;}\n' +
      'h1,h2,h3,h4,h5,h6{line-height:1.4;margin:1.6em 0 .6em;}\n' +
      'p{margin:0 0 1em;}\n' +
      'blockquote{margin:0 0 1em;padding:.4em 1em;border-left:3px solid #7AB75F;color:#4a4a4a;}\n' +
      'code{font-family:ui-monospace,monospace;background:#f2f2f2;padding:.1em .35em;border-radius:4px;}\n' +
      'pre{background:#f2f2f2;padding:12px 14px;border-radius:8px;overflow-x:auto;}\n' +
      'pre code{background:none;padding:0;}\n' +
      'hr{border:none;border-top:1px solid #d5d5d5;margin:2em 0;}\n' +
      'ul,ol{padding-left:1.4em;}\n' +
      'li{margin:.2em 0;}\n' +
      '</style>\n</head>\n<body>\n' + bodyHtml + '\n</body>\n</html>\n'
  }

  /** 纯文本（TXT 导出）：去掉 Markdown 标记，保留换行与缩进结构 */
  static toPlainText(markdown: string): string {
    let out: string = markdown.replace(new RegExp('\\r\\n', 'g'), '\n')
    out = out.replace(new RegExp('^```.*$', 'gm'), '')
    out = out.replace(new RegExp('^(#{1,6})\\s+', 'gm'), '')
    out = out.replace(new RegExp('^>\\s?', 'gm'), '')
    out = out.replace(new RegExp('^\\s*[-*]\\s+', 'gm'), '')
    out = out.replace(new RegExp('^\\s*\\d+\\.\\s+', 'gm'), '')
    out = out.replace(new RegExp('`([^`]+)`', 'g'), '$1')
    out = out.replace(new RegExp('\\*\\*([^*]+)\\*\\*', 'g'), '$1')
    out = out.replace(new RegExp('__([^_]+)__', 'g'), '$1')
    out = out.replace(new RegExp('~~([^~]+)~~', 'g'), '$1')
    out = out.replace(new RegExp('\\*([^*]+)\\*', 'g'), '$1')
    out = out.replace(new RegExp('_([^_]+)_', 'g'), '$1')
    return out
  }
}
