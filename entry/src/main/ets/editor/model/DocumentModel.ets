// 段落级正文模型（P5 的语义层，纯计算、可在 Node 回归）
//
// 目标：正文不再只是"一整段字符串 + 偏移边车"，而是**有稳定身份的段落**。
// 这样大纲/导图拖动一个主题时，才知道"整节正文"是哪几段（ADR-002 §2.5）。
//
// 本文件只做三件事，不碰数据库、不碰 UI：
//   1) 从"文本 + 格式边车"解析出段落（也是旧数据的迁移函数）；
//   2) 把段落投影回 FlowText 需要的 text + run[]（编辑器内核不用改）；
//   3) 结构性编辑：分裂 / 合并 / 改段落种类 / 移动整节——都按"保留左段 id"的规则。
//
// 本文件不碰数据库：documentRows() 只给持久化层出行，实际落库在 repository/ParagraphRepository。
// 明确未做（留给下一步）：段内插入/删除的增量命令、撤销记录、接编辑器。
import { FormatRun, ParagraphKind, isListParagraph, MAX_LIST_LEVEL } from '../flowtext/model/EditorTypes'
import { FormatCodec } from '../flowtext/model/FormatCodec'

/** 一个段落：id 稳定，kind 是 ParagraphKind，text 不含换行 */
export class DocParagraph {
  id: string = ''
  kind: number = ParagraphKind.BODY
  /** 列表层级（0–2）：只有列表/待办段有意义 */
  indent: number = 0
  text: string = ''
  /**
   * 持久化排序。按实数使用：插入时取相邻中点，避免每次回车都把后续行全部重写。
   * SQLite 的 INTEGER 列也能存非整数；DAO 用 getDouble 读回。
   */
  ordinal: number = 0

  constructor(id: string = '', kind: number = ParagraphKind.BODY, text: string = '',
    indent: number = 0, ordinal: number = 0) {
    this.id = id
    this.kind = kind
    this.text = text
    this.indent = indent
    this.ordinal = ordinal
  }
}

/** 段内行内样式（偏移相对该段起点） */
export class DocInlineRun {
  paraId: string = ''
  start: number = 0
  end: number = 0
  bold: boolean = false
  italic: boolean = false

  constructor(paraId: string = '', start: number = 0, end: number = 0,
    bold: boolean = false, italic: boolean = false) {
    this.paraId = paraId
    this.start = start
    this.end = end
    this.bold = bold
    this.italic = italic
  }
}

export class DocModel {
  id: string = ''
  title: string = ''
  paragraphs: DocParagraph[] = []
  runs: DocInlineRun[] = []
  /** 内容版本：只有正文/结构变化才自增（光标不算） */
  version: number = 0
}

/** 段落 → 全文偏移区间（投影与锚点都用它） */
export class ParaSpan {
  id: string = ''
  start: number = 0
  end: number = 0

  constructor(id: string = '', start: number = 0, end: number = 0) {
    this.id = id
    this.start = start
    this.end = end
  }
}

export class Projection {
  text: string = ''
  runsJson: string = ''
  spans: ParaSpan[] = []
}

/** doc_paragraphs 一行：持久化层用，DocModel 本身不持有 docId/ordinal */
export class DocParagraphRow {
  docId: string = ''
  paraId: string = ''
  ordinal: number = 0
  kind: number = ParagraphKind.BODY
  indent: number = 0
  text: string = ''

  constructor(docId: string = '', paraId: string = '', ordinal: number = 0,
    kind: number = ParagraphKind.BODY, indent: number = 0, text: string = '') {
    this.docId = docId
    this.paraId = paraId
    this.ordinal = ordinal
    this.kind = kind
    this.indent = indent
    this.text = text
  }
}

/** doc_runs 一行：偏移相对段首 */
export class DocRunRow {
  docId: string = ''
  paraId: string = ''
  start: number = 0
  end: number = 0
  bold: boolean = false
  italic: boolean = false

  constructor(docId: string = '', paraId: string = '', start: number = 0, end: number = 0,
    bold: boolean = false, italic: boolean = false) {
    this.docId = docId
    this.paraId = paraId
    this.start = start
    this.end = end
    this.bold = bold
    this.italic = italic
  }
}

export class DocRows {
  paragraphs: DocParagraphRow[] = []
  runs: DocRunRow[] = []
}

function nextParagraphId(model: DocModel): string {
  let max: number = 0
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    const id: string = model.paragraphs[i].id
    if (id.startsWith('p')) {
      const value: number = Number.parseInt(id.substring(1), 10)
      if (Number.isFinite(value) && value > max) {
        max = value
      }
    }
  }
  return 'p' + (max + 1).toString()
}

/** 该段落的 [种类, 层级]：取覆盖段首的那条 run（与编辑器/导出一致） */
function attrsAt(runs: FormatRun[], start: number, end: number): number[] {
  let fallback: number[] = [ParagraphKind.BODY, 0]
  for (let i: number = 0; i < runs.length; i++) {
    const run: FormatRun = runs[i]
    if (run.heading === ParagraphKind.BODY || run.endOffset <= start || run.startOffset >= end) {
      continue
    }
    if (run.startOffset <= start && run.endOffset >= start) {
      return [run.heading, run.indent]
    }
    if (fallback[0] === ParagraphKind.BODY) {
      fallback = [run.heading, run.indent]
    }
  }
  return fallback
}

/**
 * 从"整篇文本 + 格式边车"建立段落模型。
 * 这也是旧数据的迁移函数：没有段落身份的老文稿走同一条路。
 */
export function createDocument(id: string, title: string, text: string, runsJson: string): DocModel {
  const model: DocModel = new DocModel()
  model.id = id
  model.title = title
  const all: FormatRun[] = runsJson === '' ? [] : FormatCodec.decode(runsJson)
  const lines: string[] = text.split('\n')
  let offset: number = 0
  for (let i: number = 0; i < lines.length; i++) {
    const line: string = lines[i]
    const start: number = offset
    const end: number = offset + line.length
    const attrs: number[] = attrsAt(all, start, end)
    const paragraph: DocParagraph = new DocParagraph('p' + (i + 1).toString(),
      attrs[0], line, attrs[1], i)
    model.paragraphs.push(paragraph)
    // 行内样式裁到本段，并转成段内偏移
    for (let r: number = 0; r < all.length; r++) {
      const run: FormatRun = all[r]
      if (!run.bold && !run.italic) {
        continue
      }
      const from: number = Math.max(run.startOffset, start)
      const to: number = Math.min(run.endOffset, end)
      if (to > from) {
        model.runs.push(new DocInlineRun(paragraph.id, from - start, to - start, run.bold, run.italic))
      }
    }
    offset = end + 1
  }
  model.version = 1
  return model
}

/** 段落 → 全文偏移（含段间换行） */
export function paragraphSpans(model: DocModel): ParaSpan[] {
  const spans: ParaSpan[] = []
  let offset: number = 0
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    const p: DocParagraph = model.paragraphs[i]
    spans.push(new ParaSpan(p.id, offset, offset + p.text.length))
    offset += p.text.length + 1
  }
  return spans
}

/** 投影回 FlowText：段落种类 → 全文 heading run，行内样式平移 */
export function project(model: DocModel): Projection {
  const spans: ParaSpan[] = paragraphSpans(model)
  const lines: string[] = []
  const runs: FormatRun[] = []
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    const p: DocParagraph = model.paragraphs[i]
    const span: ParaSpan = spans[i]
    lines.push(p.text)
    if (p.kind !== ParagraphKind.BODY && p.text.length > 0) {
      runs.push(new FormatRun(span.start, span.end, false, false, p.kind, p.indent))
    }
  }
  for (let i: number = 0; i < model.runs.length; i++) {
    const inline: DocInlineRun = model.runs[i]
    const span: ParaSpan | undefined = findSpan(spans, inline.paraId)
    if (span === undefined) {
      continue
    }
    const start: number = span.start + inline.start
    const end: number = span.start + inline.end
    if (end > start) {
      runs.push(new FormatRun(start, end, inline.bold, inline.italic, ParagraphKind.BODY, 0))
    }
  }
  runs.sort((a: FormatRun, b: FormatRun): number => a.startOffset - b.startOffset)
  const projection: Projection = new Projection()
  projection.text = lines.join('\n')
  projection.runsJson = runs.length === 0 ? '' : FormatCodec.encode(runs)
  projection.spans = spans
  return projection
}

/**
 * 持久化映射：DocModel → 段落表/行内样式表的行。
 * 纯函数，DAO 与 Node 回归共用同一套序号与相对偏移，避免两处各写一份。
 */
export function documentRows(model: DocModel): DocRows {
  const rows: DocRows = new DocRows()
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    const p: DocParagraph = model.paragraphs[i]
    rows.paragraphs.push(new DocParagraphRow(model.id, p.id, p.ordinal, p.kind, p.indent, p.text))
  }
  for (let i: number = 0; i < model.runs.length; i++) {
    const run: DocInlineRun = model.runs[i]
    if (!run.bold && !run.italic) {
      continue
    }
    rows.runs.push(new DocRunRow(model.id, run.paraId, run.start, run.end, run.bold, run.italic))
  }
  return rows
}

/**
 * 把编辑器上报的「全文 + 格式」合并到旧段落模型，尽量保留 para_id。
 *
 * 编辑器目前只上报整篇文本，没有逐段命令；这里用“公共前缀/后缀 + 中间窗口”
 * 做增量对齐：连续输入只改一段时，其余段落的 id 完全不动；插入/删除段落时，
 * 只有变化窗口内的段才新建/移除 id。窗口内的规则与 ADR-002 §2.5 一致：
 *   - 一段拆成多段：左段保留 id，右段新建；
 *   - 多段合成一段：保留左段 id；
 *   - 同长度窗口：按位置保留 id（视为逐段改写）。
 *
 * 这不是最终的命令服务：撤销/重做恢复旧文本时，仍可能给恢复出来的段新 id；
 * 命令级撤销落地后，由命令记录直接恢复原身份。
 */
export function reconcileDocument(oldModel: DocModel | null, docId: string, title: string,
  text: string, runsJson: string): DocModel {
  const next: DocModel = createDocument(docId, title, text, runsJson)
  if (oldModel === null || oldModel.paragraphs.length === 0) {
    return next
  }
  const oldLines: string[] = paragraphTexts(oldModel)
  const newLines: string[] = paragraphTexts(next)
  let prefix: number = 0
  while (prefix < oldLines.length && prefix < newLines.length &&
    oldLines[prefix] === newLines[prefix]) {
    prefix++
  }
  let suffix: number = 0
  while (suffix < oldLines.length - prefix && suffix < newLines.length - prefix &&
    oldLines[oldLines.length - 1 - suffix] === newLines[newLines.length - 1 - suffix]) {
    suffix++
  }
  const tempIds: string[] = []
  const finalIds: string[] = []
  for (let i: number = 0; i < next.paragraphs.length; i++) {
    tempIds.push(next.paragraphs[i].id)
    finalIds.push('')
  }
  for (let i: number = 0; i < prefix; i++) {
    finalIds[i] = oldModel.paragraphs[i].id
  }
  for (let i: number = 0; i < suffix; i++) {
    finalIds[next.paragraphs.length - 1 - i] = oldModel.paragraphs[oldModel.paragraphs.length - 1 - i].id
  }
  assignMiddleIds(oldModel, prefix, oldModel.paragraphs.length - suffix,
    next, prefix, next.paragraphs.length - suffix, finalIds)
  let maxId: number = Math.max(maxParagraphNumber(oldModel.paragraphs),
    maxParagraphNumber(next.paragraphs))
  for (let i: number = 0; i < finalIds.length; i++) {
    if (finalIds[i] === '') {
      maxId++
      finalIds[i] = 'p' + maxId.toString()
    }
  }
  const idMap: Map<string, string> = new Map<string, string>()
  for (let i: number = 0; i < next.paragraphs.length; i++) {
    const temp: string = tempIds[i]
    const final: string = finalIds[i]
    if (temp !== final) {
      idMap.set(temp, final)
    }
    next.paragraphs[i].id = final
  }
  if (idMap.size > 0) {
    for (let i: number = 0; i < next.runs.length; i++) {
      const mapped: string | undefined = idMap.get(next.runs[i].paraId)
      if (mapped !== undefined) {
        next.runs[i].paraId = mapped
      }
    }
  }
  assignOrdinals(oldModel, next)
  normalizeInline(next)
  next.version = oldModel.version + 1
  return next
}

/**
 * 保留旧段落的 ordinal；新段落取相邻旧段落的中点。
 * 这样插入/删除只改少数行，不需要把后面所有 ordinal 重排。
 */
function assignOrdinals(oldModel: DocModel, next: DocModel): void {
  const oldById: Map<string, DocParagraph> = new Map<string, DocParagraph>()
  for (let i: number = 0; i < oldModel.paragraphs.length; i++) {
    oldById.set(oldModel.paragraphs[i].id, oldModel.paragraphs[i])
  }
  const assigned: boolean[] = []
  for (let i: number = 0; i < next.paragraphs.length; i++) {
    const old: DocParagraph | undefined = oldById.get(next.paragraphs[i].id)
    if (old !== undefined) {
      next.paragraphs[i].ordinal = old.ordinal
      assigned.push(true)
    } else {
      assigned.push(false)
    }
  }
  let needReindex: boolean = false
  for (let i: number = 0; i < next.paragraphs.length; i++) {
    if (assigned[i]) {
      continue
    }
    let prev: number = -1
    for (let j: number = i - 1; j >= 0; j--) {
      if (assigned[j]) {
        prev = j
        break
      }
    }
    let following: number = -1
    for (let j: number = i + 1; j < next.paragraphs.length; j++) {
      if (assigned[j]) {
        following = j
        break
      }
    }
    if (prev >= 0 && following >= 0) {
      const before: number = next.paragraphs[prev].ordinal
      const after: number = next.paragraphs[following].ordinal
      if (after - before < 0.000001) {
        needReindex = true
        break
      }
      next.paragraphs[i].ordinal = (before + after) / 2
    } else if (prev >= 0) {
      next.paragraphs[i].ordinal = next.paragraphs[prev].ordinal + 1
    } else if (following >= 0) {
      next.paragraphs[i].ordinal = next.paragraphs[following].ordinal - 1
    } else {
      next.paragraphs[i].ordinal = i
    }
    assigned[i] = true
  }
  if (needReindex) {
    for (let i: number = 0; i < next.paragraphs.length; i++) {
      next.paragraphs[i].ordinal = i
    }
  }
}

function paragraphTexts(model: DocModel): string[] {
  const lines: string[] = []
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    lines.push(model.paragraphs[i].text)
  }
  return lines
}

function maxParagraphNumber(paragraphs: DocParagraph[]): number {
  let max: number = 0
  for (let i: number = 0; i < paragraphs.length; i++) {
    const id: string = paragraphs[i].id
    if (id.startsWith('p')) {
      const value: number = Number.parseInt(id.substring(1), 10)
      if (Number.isFinite(value) && value > max) {
        max = value
      }
    }
  }
  return max
}

function assignMiddleIds(oldModel: DocModel, oldStart: number, oldEnd: number,
  next: DocModel, newStart: number, newEnd: number, finalIds: string[]): void {
  const oldLen: number = oldEnd - oldStart
  const newLen: number = newEnd - newStart
  if (oldLen <= 0 || newLen <= 0) {
    return
  }
  // 一段拆多段：左段保留 id；多段合一段：保留左段 id。
  if (oldLen === 1 || newLen === 1) {
    finalIds[newStart] = oldModel.paragraphs[oldStart].id
    return
  }
  // 同长度窗口按位置视为逐段改写，id 不动。
  if (oldLen === newLen) {
    for (let i: number = 0; i < oldLen; i++) {
      finalIds[newStart + i] = oldModel.paragraphs[oldStart + i].id
    }
    return
  }
  // 窗口很大（整篇粘贴/替换）时不做 LCS，按位置保留前 min 段，其余新建。
  if (oldLen * newLen > 40000) {
    const shared: number = Math.min(oldLen, newLen)
    for (let i: number = 0; i < shared; i++) {
      finalIds[newStart + i] = oldModel.paragraphs[oldStart + i].id
    }
    return
  }
  const dp: number[][] = []
  for (let i: number = 0; i <= oldLen; i++) {
    const row: number[] = []
    for (let j: number = 0; j <= newLen; j++) {
      row.push(0)
    }
    dp.push(row)
  }
  for (let i: number = 1; i <= oldLen; i++) {
    for (let j: number = 1; j <= newLen; j++) {
      if (oldModel.paragraphs[oldStart + i - 1].text === next.paragraphs[newStart + j - 1].text) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1])
      }
    }
  }
  let i: number = oldLen
  let j: number = newLen
  while (i > 0 && j > 0) {
    if (oldModel.paragraphs[oldStart + i - 1].text === next.paragraphs[newStart + j - 1].text) {
      finalIds[newStart + j - 1] = oldModel.paragraphs[oldStart + i - 1].id
      i--
      j--
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--
    } else {
      j--
    }
  }
}

function findSpan(spans: ParaSpan[], id: string): ParaSpan | undefined {
  for (let i: number = 0; i < spans.length; i++) {
    if (spans[i].id === id) {
      return spans[i]
    }
  }
  return undefined
}

/**
 * 合并相邻且同段、同一样式的 run。
 * 分裂/合并之后很容易留下"[0,2) 粗 + [2,4) 粗"这种碎片，
 * 不归一化的话每次编辑都会让边车越来越碎。
 */
function normalizeInline(model: DocModel): void {
  const sorted: DocInlineRun[] = model.runs.slice()
  sorted.sort((a: DocInlineRun, b: DocInlineRun): number => {
    if (a.paraId !== b.paraId) {
      return a.paraId < b.paraId ? -1 : 1
    }
    return a.start - b.start
  })
  const out: DocInlineRun[] = []
  for (let i: number = 0; i < sorted.length; i++) {
    const run: DocInlineRun = sorted[i]
    if (run.end <= run.start) {
      continue
    }
    const last: DocInlineRun | undefined = out.length > 0 ? out[out.length - 1] : undefined
    if (last !== undefined && last.paraId === run.paraId && last.end === run.start &&
      last.bold === run.bold && last.italic === run.italic) {
      last.end = run.end
      continue
    }
    out.push(run)
  }
  model.runs = out
}

/** 相邻 ordinal 的中点；间隙耗尽时交给 assignOrdinals 的 reindex 兜底 */
function ordinalBetween(before: number, after: number): number {
  if (after - before > 0.000001) {
    return (before + after) / 2
  }
  return before + 1
}

/** 段落索引（找不到 = -1） */
export function indexOfParagraph(model: DocModel, id: string): number {
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    if (model.paragraphs[i].id === id) {
      return i
    }
  }
  return -1
}

/** 全局偏移落在哪一段（段尾归本段） */
export function paragraphIdAt(model: DocModel, offset: number): string {
  const spans: ParaSpan[] = paragraphSpans(model)
  for (let i: number = 0; i < spans.length; i++) {
    if (offset <= spans[i].end) {
      return spans[i].id
    }
  }
  return spans.length === 0 ? '' : spans[spans.length - 1].id
}

/**
 * 分裂段落：左段保留原 id，右段新建 id；跨界的行内 run 一分为二。
 * 右段继承左段的种类（标题被拆开时两段都还是标题，与 Word/备忘录一致）。
 */
export function splitParagraph(model: DocModel, index: number, offset: number): string {
  if (index < 0 || index >= model.paragraphs.length) {
    return ''
  }
  const left: DocParagraph = model.paragraphs[index]
  const at: number = Math.max(0, Math.min(offset, left.text.length))
  if (at === 0 || at === left.text.length) {
    // 段首/段尾分裂等价于插入一个空段落
    const empty: DocParagraph = new DocParagraph(nextParagraphId(model), left.kind, '', left.indent,
      at === 0 ? left.ordinal - 1 : left.ordinal + 1)
    const insertAt: number = at === 0 ? index : index + 1
    model.paragraphs.splice(insertAt, 0, empty)
    model.version++
    return empty.id
  }
  const following: DocParagraph | undefined = index + 1 < model.paragraphs.length
    ? model.paragraphs[index + 1] : undefined
  const rightOrdinal: number = following !== undefined
    ? ordinalBetween(left.ordinal, following.ordinal) : left.ordinal + 1
  const right: DocParagraph = new DocParagraph(nextParagraphId(model), left.kind,
    left.text.substring(at), left.indent, rightOrdinal)
  left.text = left.text.substring(0, at)
  const kept: DocInlineRun[] = []
  for (let i: number = 0; i < model.runs.length; i++) {
    const run: DocInlineRun = model.runs[i]
    if (run.paraId !== left.id) {
      kept.push(run)
      continue
    }
    if (run.end <= at) {
      kept.push(run)
    } else if (run.start >= at) {
      kept.push(new DocInlineRun(right.id, run.start - at, run.end - at, run.bold, run.italic))
    } else {
      kept.push(new DocInlineRun(left.id, run.start, at, run.bold, run.italic))
      kept.push(new DocInlineRun(right.id, 0, run.end - at, run.bold, run.italic))
    }
  }
  model.runs = kept
  normalizeInline(model)
  model.paragraphs.splice(index + 1, 0, right)
  model.version++
  return right.id
}

/**
 * 合并相邻两段：保留**左段 id**，右段的行内 run 平移到左段后删除右段。
 * 左段的种类不变（与前文合并后跟随前一段，是行业惯例）。
 */
export function mergeParagraphs(model: DocModel, index: number): boolean {
  if (index < 0 || index + 1 >= model.paragraphs.length) {
    return false
  }
  const left: DocParagraph = model.paragraphs[index]
  const right: DocParagraph = model.paragraphs[index + 1]
  const shift: number = left.text.length
  const kept: DocInlineRun[] = []
  for (let i: number = 0; i < model.runs.length; i++) {
    const run: DocInlineRun = model.runs[i]
    if (run.paraId === right.id) {
      kept.push(new DocInlineRun(left.id, run.start + shift, run.end + shift, run.bold, run.italic))
    } else {
      kept.push(run)
    }
  }
  model.runs = kept
  normalizeInline(model)
  left.text = left.text + right.text
  model.paragraphs.splice(index + 1, 1)
  model.version++
  return true
}

export function setParagraphKind(model: DocModel, index: number, kind: number): boolean {
  if (index < 0 || index >= model.paragraphs.length) {
    return false
  }
  const next: number = Math.max(ParagraphKind.BODY, Math.min(ParagraphKind.TODO_DONE, Math.round(kind)))
  if (model.paragraphs[index].kind === next) {
    return false
  }
  model.paragraphs[index].kind = next
  // 非列表段落没有层级：切回正文/标题时把 indent 归零，避免"残留缩进"
  if (!isListParagraph(next)) {
    model.paragraphs[index].indent = 0
  }
  model.version++
  return true
}

/**
 * 「一节」的范围：从标题段开始，到下一个**同级或更高级**标题之前。
 * 非标题段的"节"就是它自己。
 */
export function sectionRange(model: DocModel, index: number): number[] {
  if (index < 0 || index >= model.paragraphs.length) {
    return [index, index]
  }
  const level: number = model.paragraphs[index].kind
  if (level < ParagraphKind.H1 || level > ParagraphKind.H3) {
    return [index, index + 1]
  }
  let end: number = index + 1
  while (end < model.paragraphs.length) {
    const kind: number = model.paragraphs[end].kind
    if (kind >= ParagraphKind.H1 && kind <= ParagraphKind.H3 && kind <= level) {
      break
    }
    end++
  }
  return [index, end]
}

/**
 * 在指定下标插入一个新段落（结构编辑：新建同级/子级）。
 * @returns 新段落的 id；越界返回空串
 */
export function insertParagraph(model: DocModel, at: number, kind: number, text: string): string {
  const index: number = Math.max(0, Math.min(at, model.paragraphs.length))
  const level: number = Math.max(ParagraphKind.BODY, Math.min(ParagraphKind.TODO_DONE, Math.round(kind)))
  const paragraph: DocParagraph = new DocParagraph(nextParagraphId(model), level, text, 0)
  model.paragraphs.splice(index, 0, paragraph)
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    model.paragraphs[i].ordinal = i
  }
  model.version++
  return paragraph.id
}

/**
 * 删除整节（标题 + 下属正文），并清掉这些段落的行内样式。
 * 与 moveSection 一样，其他段落的 id 不变。
 */
export function removeSection(model: DocModel, headIndex: number): boolean {
  const range: number[] = sectionRange(model, headIndex)
  const start: number = range[0]
  const end: number = range[1]
  if (start >= end || start < 0 || end > model.paragraphs.length) {
    return false
  }
  // 至少要留下一个段落，否则编辑器会拿到空文档（空文档应由上层显式处理）
  if (end - start >= model.paragraphs.length) {
    return false
  }
  const removed: Set<string> = new Set<string>()
  for (let i: number = start; i < end; i++) {
    removed.add(model.paragraphs[i].id)
  }
  model.paragraphs.splice(start, end - start)
  if (removed.size > 0) {
    model.runs = model.runs.filter((run: DocInlineRun): boolean => !removed.has(run.paraId))
  }
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    model.paragraphs[i].ordinal = i
  }
  model.version++
  return true
}

/** 上一个标题段的下标（-1 = 前面没有标题） */
export function previousHeadingIndex(model: DocModel, index: number): number {
  for (let i: number = Math.min(index - 1, model.paragraphs.length - 1); i >= 0; i--) {
    const kind: number = model.paragraphs[i].kind
    if (kind >= ParagraphKind.H1 && kind <= ParagraphKind.H3) {
      return i
    }
  }
  return -1
}

/** 从 from 开始（含）往后第一个标题段的下标（-1 = 后面没有标题） */
export function nextHeadingIndex(model: DocModel, from: number): number {
  for (let i: number = Math.max(0, from); i < model.paragraphs.length; i++) {
    const kind: number = model.paragraphs[i].kind
    if (kind >= ParagraphKind.H1 && kind <= ParagraphKind.H3) {
      return i
    }
  }
  return -1
}

/** 「上移一节」：把当前节挪到上一节前面 */
export function moveSectionUp(model: DocModel, headIndex: number): boolean {
  const prev: number = previousHeadingIndex(model, headIndex)
  if (prev < 0) {
    return false
  }
  return moveSection(model, headIndex, prev)
}

/** 「下移一节」：把当前节挪到下一节后面 */
export function moveSectionDown(model: DocModel, headIndex: number): boolean {
  const range: number[] = sectionRange(model, headIndex)
  const next: number = nextHeadingIndex(model, range[1])
  if (next < 0) {
    return false
  }
  const nextRange: number[] = sectionRange(model, next)
  return moveSection(model, headIndex, nextRange[1])
}

/**
 * 移动整节：把 headIndex 那一节（标题 + 下属内容）移到 targetIndex 之前。
 * id 一律不变——这样锚点、导图节点、引用都不会失效。
 * @returns 是否真的移动了
 */
export function moveSection(model: DocModel, headIndex: number, targetIndex: number): boolean {
  const range: number[] = sectionRange(model, headIndex)
  const start: number = range[0]
  const end: number = range[1]
  if (start >= end) {
    return false
  }
  let target: number = Math.max(0, Math.min(targetIndex, model.paragraphs.length))
  if (target >= start && target <= end) {
    return false
  }
  const block: DocParagraph[] = model.paragraphs.splice(start, end - start)
  if (target > end) {
    target -= (end - start)
  }
  for (let i: number = 0; i < block.length; i++) {
    model.paragraphs.splice(target + i, 0, block[i])
  }
  // 整节移动会改变大段顺序；这里统一重排 ordinal（结构编辑不频繁）。
  for (let i: number = 0; i < model.paragraphs.length; i++) {
    model.paragraphs[i].ordinal = i
  }
  model.version++
  return true
}

/** 列表缩进（±1）：层级存在段落上，不塞进正文（导出时再按层级生成缩进） */
export function changeIndent(model: DocModel, index: number, delta: number): boolean {
  if (index < 0 || index >= model.paragraphs.length || delta === 0) {
    return false
  }
  const paragraph: DocParagraph = model.paragraphs[index]
  if (!isListParagraph(paragraph.kind)) {
    return false
  }
  const next: number = Math.max(0, Math.min(MAX_LIST_LEVEL, paragraph.indent + delta))
  if (next === paragraph.indent) {
    return false
  }
  paragraph.indent = next
  model.version++
  return true
}
