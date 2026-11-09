// EPUB 解析（纯计算，无文件 IO、无 @kit 依赖，可在 Node 里回归）
//
// EPUB 本质是 zip 包，里面是：
//   META-INF/container.xml  → 指向 OPF 的路径
//   *.opf                   → 书名/作者 + manifest(href) + spine(阅读顺序)
//   *.xhtml                 → 正文
// 解压与读文件在 EpubImporter 里做；这里只负责"把一堆已解压的文本文件变成可分章的文稿"。
//
// 范围（用户确认）：按章拆分文稿、保留书名/作者/目录顺序；图片与样式降级为纯文本。

/** 已解压出的一个文本文件（路径相对于解压根） */
export interface EpubFile {
  path: string
  text: string
}

export interface EpubChapter {
  title: string
  content: string
}

export interface EpubBook {
  title: string
  author: string
  chapters: EpubChapter[]
}

const MAX_TITLE_LEN: number = 80

/** 去标签后的纯文本（行内空白收敛，段落保留换行） */
export function epubHtmlToText(html: string): string {
  let s: string = html
  s = s.replace(/<\?xml[\s\S]*?\?>/gi, ' ')
  s = s.replace(/<!--[\s\S]*?-->/g, ' ')
  s = s.replace(/<(script|style|head)[\s\S]*?<\/\1>/gi, ' ')
  s = s.replace(/<br\s*\/?>/gi, '\n')
  s = s.replace(/<\/(p|div|h1|h2|h3|h4|h5|h6|li|tr|section|article|blockquote|figcaption|dd|dt)>/gi, '\n')
  s = s.replace(/<[^>]+>/g, ' ')
  s = epubDecodeEntities(s)
  const lines: string[] = s.split('\n')
  const out: string[] = []
  for (let i: number = 0; i < lines.length; i++) {
    const line: string = lines[i].replace(/[ \t\u00A0\u3000]+/g, ' ').trim()
    if (line !== '') {
      out.push(line)
    }
  }
  return out.join('\n')
}

/** 常见实体 + 数字实体 */
export function epubDecodeEntities(text: string): string {
  let s: string = text
  s = s.replace(/&nbsp;/gi, ' ')
  s = s.replace(/&amp;/gi, '&')
  s = s.replace(/&lt;/gi, '<')
  s = s.replace(/&gt;/gi, '>')
  s = s.replace(/&quot;/gi, '"')
  s = s.replace(/&apos;/gi, "'")
  s = s.replace(/&mdash;/gi, '—')
  s = s.replace(/&ndash;/gi, '–')
  s = s.replace(/&hellip;/gi, '…')
  s = s.replace(/&ldquo;/gi, '“')
  s = s.replace(/&rdquo;/gi, '”')
  s = s.replace(/&lsquo;/gi, '‘')
  s = s.replace(/&rsquo;/gi, '’')
  s = s.replace(/&#(\d+);/g, (whole: string, code: string): string => {
    const value: number = Number.parseInt(code, 10)
    return Number.isFinite(value) ? String.fromCharCode(value) : whole
  })
  s = s.replace(/&#x([0-9a-fA-F]+);/g, (whole: string, code: string): string => {
    const value: number = Number.parseInt(code, 16)
    return Number.isFinite(value) ? String.fromCharCode(value) : whole
  })
  return s
}

/** 属性取值：先双引号、再单引号（不写一条复杂正则，ArkTS 更稳） */
function epubAttr(tag: string, name: string): string {
  const doubleQuoted: RegExp = new RegExp(name + '\\s*=\\s*"([^"]*)"', 'i')
  const a: RegExpMatchArray | null = tag.match(doubleQuoted)
  if (a !== null && a.length > 1) {
    return a[1]
  }
  const singleQuoted: RegExp = new RegExp(name + '\\s*=\\s*\'([^\']*)\'', 'i')
  const b: RegExpMatchArray | null = tag.match(singleQuoted)
  if (b !== null && b.length > 1) {
    return b[1]
  }
  return ''
}

/** 相对路径解析：处理 ./ ../ 与 URL 编码，去掉 #片段 与 ?查询 */
export function epubResolvePath(baseDir: string, href: string): string {
  let raw: string = href
  const hash: number = raw.indexOf('#')
  if (hash >= 0) {
    raw = raw.substring(0, hash)
  }
  const query: number = raw.indexOf('?')
  if (query >= 0) {
    raw = raw.substring(0, query)
  }
  try {
    raw = decodeURIComponent(raw)
  } catch (e) {
    raw = raw
  }
  // 以 / 开头表示包根：不能再拼 baseDir，否则会变成 OEBPS/abs/...
  const isRooted: boolean = raw.startsWith('/')
  const combined: string = isRooted ? raw.substring(1)
    : (baseDir === '' ? raw : baseDir + '/' + raw)
  const parts: string[] = combined.replace(/\\/g, '/').split('/')
  const out: string[] = []
  for (let i: number = 0; i < parts.length; i++) {
    const part: string = parts[i]
    if (part === '' || part === '.') {
      continue
    }
    if (part === '..') {
      if (out.length > 0) {
        out.pop()
      }
      continue
    }
    out.push(part)
  }
  return out.join('/')
}

function epubBaseDir(path: string): string {
  const at: number = path.lastIndexOf('/')
  return at < 0 ? '' : path.substring(0, at)
}

function epubFirstHeading(html: string): string {
  const m: RegExpMatchArray | null = html.match(/<h([1-3])[^>]*>([\s\S]*?)<\/h\1>/i)
  if (m === null || m.length < 3) {
    return ''
  }
  const text: string = epubHtmlToText(m[2]).replace(/\n/g, ' ')
  return text.length > MAX_TITLE_LEN ? text.substring(0, MAX_TITLE_LEN) : text
}

/** 按路径取文件；找不到返回 undefined（spine 里可能引用了缺失文件） */
function epubFind(files: EpubFile[], path: string): EpubFile | undefined {
  const target: string = path.toLowerCase()
  for (let i: number = 0; i < files.length; i++) {
    if (files[i].path.toLowerCase() === target) {
      return files[i]
    }
  }
  return undefined
}

/** OPF 里查到的书信息（导入器读章节文件时也用它） */
export interface EpubOpfInfo {
  title: string
  author: string
  /** 按 spine 顺序解析好的包内路径 */
  spinePaths: string[]
}

/** container.xml → OPF 的包内路径（找不到返回空串） */
export function epubContainerRootPath(containerXml: string): string {
  const m: RegExpMatchArray | null = containerXml.match(/<rootfile\b[^>]*>/i)
  if (m === null) {
    return ''
  }
  return epubAttr(m[0], 'full-path')
}

/** 解析 OPF：书名、作者、spine 指向的章节文件（相对 OPF 所在目录解析） */
export function epubOpfInfo(opfXml: string, opfPath: string): EpubOpfInfo {
  const baseDir: string = epubBaseDir(opfPath)
  let title: string = ''
  let author: string = ''
  const titleMatch: RegExpMatchArray | null = opfXml.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/i)
  if (titleMatch !== null && titleMatch.length > 1) {
    title = epubDecodeEntities(titleMatch[1].replace(/<[^>]+>/g, '')).trim()
  }
  const authorMatch: RegExpMatchArray | null = opfXml.match(/<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>/i)
  if (authorMatch !== null && authorMatch.length > 1) {
    author = epubDecodeEntities(authorMatch[1].replace(/<[^>]+>/g, '')).trim()
  }
  const idToPath: Map<string, string> = new Map<string, string>()
  const items: RegExpMatchArray | null = opfXml.match(/<item\b[^>]*>/gi)
  if (items !== null) {
    for (let i: number = 0; i < items.length; i++) {
      const id: string = epubAttr(items[i], 'id')
      const href: string = epubAttr(items[i], 'href')
      if (id !== '' && href !== '') {
        idToPath.set(id, epubResolvePath(baseDir, href))
      }
    }
  }
  const spinePaths: string[] = []
  const refs: RegExpMatchArray | null = opfXml.match(/<itemref\b[^>]*>/gi)
  if (refs !== null) {
    for (let i: number = 0; i < refs.length; i++) {
      const idref: string = epubAttr(refs[i], 'idref')
      const mapped: string | undefined = idToPath.get(idref)
      if (mapped !== undefined && !spinePaths.includes(mapped)) {
        spinePaths.push(mapped)
      }
    }
  }
  const info: EpubOpfInfo = { title: title, author: author, spinePaths: spinePaths }
  return info
}

/**
 * 把解压后的文件解析成书：书名/作者 + 按 spine 顺序的章节。
 * 任何一步缺失都退化为"按文件顺序取正文"，避免整本导入失败。
 */
export function parseEpub(files: EpubFile[]): EpubBook | undefined {
  if (files.length === 0) {
    return undefined
  }
  // 1) container.xml → OPF 路径
  const container: EpubFile | undefined = epubFind(files, 'META-INF/container.xml')
  let opfPath: string = ''
  if (container !== undefined) {
    const m: RegExpMatchArray | null = container.text.match(/<rootfile\b[^>]*>/i)
    if (m !== null) {
      opfPath = epubAttr(m[0], 'full-path')
    }
  }
  const opf: EpubFile | undefined = opfPath === '' ? undefined : epubFind(files, opfPath)
  // 书名/作者/章节顺序统一由 epubOpfInfo 决定（导入器读文件时也用它，避免两份规则）
  const info: EpubOpfInfo = opf === undefined
    ? { title: '', author: '', spinePaths: [] }
    : epubOpfInfo(opf.text, opf.path)
  const title: string = info.title
  const author: string = info.author
  const spinePaths: string[] = info.spinePaths.slice()
  // 2) 没有可用的 spine：按 .xhtml/.html 文件名顺序兜底
  if (spinePaths.length === 0) {
    const sorted: EpubFile[] = files.filter((f: EpubFile): boolean =>
      f.path.toLowerCase().endsWith('.xhtml') || f.path.toLowerCase().endsWith('.html')).slice()
    sorted.sort((a: EpubFile, b: EpubFile): number => a.path < b.path ? -1 : (a.path > b.path ? 1 : 0))
    for (let i: number = 0; i < sorted.length; i++) {
      spinePaths.push(sorted[i].path)
    }
  }
  // 3) 逐章转文本
  const chapters: EpubChapter[] = []
  for (let i: number = 0; i < spinePaths.length; i++) {
    const file: EpubFile | undefined = epubFind(files, spinePaths[i])
    if (file === undefined) {
      continue
    }
    const content: string = epubHtmlToText(file.text)
    if (content === '') {
      continue
    }
    const heading: string = epubFirstHeading(file.text)
    const fallback: string = '第 ' + (chapters.length + 1).toString() + ' 部分'
    chapters.push({ title: heading === '' ? fallback : heading, content: content })
  }
  if (chapters.length === 0) {
    return undefined
  }
  const bookTitle: string = title !== '' ? title : chapters[0].title
  const book: EpubBook = { title: bookTitle, author: author, chapters: chapters }
  return book
}
