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
// 明确未做（留给下一步）：段内插入/删除的增量命令、撤销记录、落库。
import { FormatRun, ParagraphKind, isListParagraph, MAX_LIST_LEVEL } from '../flowtext/model/EditorTypes'
import { FormatCodec } from '../flowtext/model/FormatCodec'

/** 一个段落：id 稳定，kind 是 ParagraphKind，text 不含换行 */
export class DocParagraph {
  id: string = ''
  kind: number = ParagraphKind.BODY
  /** 列表层级（0–2）：只有列表/待办段有意义 */
  indent: number = 0
  text: string = ''

  constructor(id: string = '', kind: number = ParagraphKind.BODY, text: string = '',
    indent: number = 0) {
    this.id = id
    this.kind = kind
    this.text = text
    this.indent = indent
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
      attrs[0], line, attrs[1])
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
    const empty: DocParagraph = new DocParagraph(nextParagraphId(model), left.kind, '', left.indent)
    const insertAt: number = at === 0 ? index : index + 1
    model.paragraphs.splice(insertAt, 0, empty)
    model.version++
    return empty.id
  }
  const right: DocParagraph = new DocParagraph(nextParagraphId(model), left.kind,
    left.text.substring(at), left.indent)
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
