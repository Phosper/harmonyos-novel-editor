// 选区 → 卡片引文 的纯计算层（无 UI、无 @kit 依赖，可在 Node 里回归）
//
// 只负责三件事：
//   1) 把选区偏移夹到合法范围，生成原文快照；
//   2) 算段号（数 offset 之前的换行）；
//   3) 生成稳定指纹，供“跳回原文”时判断原文是否被改过。

/** 一次捕获的完整落库字段（与 CanvasEvidenceInput 同形，避免 ARKTS 结构类型问题） */
export interface CanvasCapturePayload {
  docId: string
  paraIndex: number
  startOff: number
  endOff: number
  fingerprint: string
  quoteText: string
  userText: string
  sourceLabel: string
}

/** FNV-1a 32 位；只用于“是否变化”的判断，不做安全用途。 */
export function canvasFingerprint(text: string): string {
  let hash: number = 0x811c9dc5
  for (let i: number = 0; i < text.length; i++) {
    hash = hash ^ text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16)
}

/** offset 之前有多少个换行（0 基段号）。 */
export function canvasParagraphIndex(text: string, offset: number): number {
  const end: number = Math.max(0, Math.min(offset, text.length))
  let n: number = 0
  for (let i: number = 0; i < end; i++) {
    if (text.charCodeAt(i) === 10) {
      n++
    }
  }
  return n
}

/** 出处：优先“文稿名 · 第 N 段”，没有标题时只写段号。 */
export function canvasSourceLabel(docTitle: string, paraIndex: number): string {
  const title: string = docTitle.trim()
  if (title === '') {
    return '第 ' + (paraIndex + 1).toString() + ' 段'
  }
  return title + ' · 第 ' + (paraIndex + 1).toString() + ' 段'
}

/** 夹取并生成 payload；选区为空/越界时返回 undefined，调用方给提示。 */
export function canvasCapturePayload(docId: string, docTitle: string, text: string,
  start: number, end: number): CanvasCapturePayload | undefined {
  const s: number = Math.max(0, Math.min(start, text.length))
  const e: number = Math.max(s, Math.min(end, text.length))
  if (e <= s) {
    return undefined
  }
  const quote: string = text.substring(s, e)
  if (quote.trim() === '') {
    return undefined
  }
  const para: number = canvasParagraphIndex(text, s)
  return {
    docId: docId,
    paraIndex: para,
    startOff: s,
    endOff: e,
    fingerprint: canvasFingerprint(quote),
    quoteText: quote,
    userText: '',
    sourceLabel: canvasSourceLabel(docTitle, para)
  }
}
