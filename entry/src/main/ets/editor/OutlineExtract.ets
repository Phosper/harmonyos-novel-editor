// 从正文抽标题 → 导图快照（宿主侧，纯计算）
//
// 只读导图的数据来源：正文 + 格式边车。规则与导出、编辑器读段落属性保持一致：
// 段落的种类取"覆盖段首的那条 run"，行内加粗/斜体切出来的 heading=0 分段不能把标题读丢。
//
// 不做的事：不改正文、不建第二份标题树（ADR-002）。P5 段落身份落地后，这里换成按 paraId 取。
import { FormatCodec } from './flowtext/model/FormatCodec'
import type { FormatRun } from './flowtext/model/EditorTypes'
import { OutlineSnapshot, buildOutline } from 'feature_contracts'
import type { OutlineHeading } from 'feature_contracts'

const HEADING_MIN: number = 1
const HEADING_MAX: number = 3

/** 该段落（按段首偏移判断）的标题级别；0 = 不是标题 */
function headingAt(runs: FormatRun[], paragraphStart: number, paragraphEnd: number): number {
  let fallback: number = 0
  for (let i: number = 0; i < runs.length; i++) {
    const run: FormatRun = runs[i]
    if (run.endOffset <= paragraphStart || run.startOffset >= paragraphEnd) {
      continue
    }
    if (run.heading < HEADING_MIN || run.heading > HEADING_MAX) {
      continue
    }
    // 覆盖段首的那条最权威（与 TextDocument.paragraphAttrsAt / 导出的取值规则一致）
    if (run.startOffset <= paragraphStart && run.endOffset >= paragraphStart) {
      return run.heading
    }
    if (fallback === 0) {
      fallback = run.heading
    }
  }
  return fallback
}

/** 正文 + 边车 → 扁平标题列表（按文档顺序） */
export function extractHeadings(text: string, runsJson: string): OutlineHeading[] {
  const out: OutlineHeading[] = []
  if (runsJson === '' || text === '') {
    return out
  }
  const runs: FormatRun[] = FormatCodec.decode(runsJson)
  if (runs.length === 0) {
    return out
  }
  let start: number = 0
  for (;;) {
    let end: number = text.indexOf('\n', start)
    if (end < 0) {
      end = text.length
    }
    const level: number = headingAt(runs, start, end)
    const title: string = text.substring(start, end).trim()
    if (level >= HEADING_MIN && level <= HEADING_MAX && title !== '') {
      const heading: OutlineHeading = {
        title: title, level: level, startOffset: start, endOffset: end
      }
      out.push(heading)
    }
    if (end >= text.length) {
      break
    }
    start = end + 1
  }
  return out
}

/** 生成可发布给结构包的快照（含合成根节点） */
export function buildOutlineSnapshot(docId: string, docTitle: string, text: string,
  runsJson: string, version: number): OutlineSnapshot {
  const snapshot: OutlineSnapshot = new OutlineSnapshot()
  snapshot.docId = docId
  snapshot.docTitle = docTitle
  snapshot.version = version
  snapshot.nodes = buildOutline(docTitle, extractHeadings(text, runsJson))
  return snapshot
}
