// 导图附加信息（概要 / 关系线）的宿主实现。
//
// 与 OutlineCommands 的分工：
//  - OutlineCommands：改**正文**（改名/增删/移动），走可撤销的编辑事务；
//  - 这里：改**侧车**（概要/关系线），不碰正文、不进内容版本号，所以不可撤销、
//    也不参与"正文是唯一真源"的一致性校验。
//
// 写路径沿用正文那套：内存副本先改、UI 立刻能看到，落库异步排队（整篇覆盖）。
import { app } from '../store/AppStores'
import { mapExtraRepo } from '../store/Repos'
import {
  OutlineExtras, OutlineExtraCommand, OutlineSummary, OutlineRelation, OutlineNodeStyle, OutlineBoundary,
  OUTLINE_EXTRA_ADD_SUMMARY, OUTLINE_EXTRA_REMOVE_SUMMARY,
  OUTLINE_EXTRA_ADD_RELATION, OUTLINE_EXTRA_REMOVE_RELATION,
  OUTLINE_EXTRA_ADD_BOUNDARY, OUTLINE_EXTRA_REMOVE_BOUNDARY, OUTLINE_EXTRA_SET_NODE_STYLE,
  isBlankNodeStyle
} from 'feature_contracts'
import { IdGenerator } from '../utils/IdGenerator'
import { Logger } from '../utils/Logger'

/** 当前打开文稿的附加信息（内存副本） */
let current: OutlineExtras = new OutlineExtras()
/** 串行写链：前一次落库没完不写下一次，避免整篇覆盖互相打架 */
let writeChain: Promise<void> = Promise.resolve()

function copyExtras(source: OutlineExtras): OutlineExtras {
  const out: OutlineExtras = new OutlineExtras()
  out.docId = source.docId
  for (let i: number = 0; i < source.summaries.length; i++) {
    const s: OutlineSummary = source.summaries[i]
    out.summaries.push(new OutlineSummary(s.id, s.startParaId, s.endParaId, s.text))
  }
  for (let i: number = 0; i < source.relations.length; i++) {
    const r: OutlineRelation = source.relations[i]
    out.relations.push(new OutlineRelation(r.id, r.fromParaId, r.toParaId, r.label))
  }
  for (let i: number = 0; i < source.boundaries.length; i++) {
    const b: OutlineBoundary = source.boundaries[i]
    out.boundaries.push(new OutlineBoundary(b.id, b.startParaId, b.endParaId, b.text))
  }
  for (let i: number = 0; i < source.nodeStyles.length; i++) {
    out.nodeStyles.push(copyNodeStyle(source.nodeStyles[i]))
  }
  return out
}

function copyNodeStyle(style: OutlineNodeStyle): OutlineNodeStyle {
  const out: OutlineNodeStyle = new OutlineNodeStyle(style.paraId)
  out.shape = style.shape
  out.fill = style.fill
  out.bold = style.bold
  out.label = style.label
  for (let i: number = 0; i < style.markers.length; i++) {
    out.markers.push(style.markers[i])
  }
  return out
}

/** 写入或删除一个段落的样式：整份替换（页面给的是最新的一份） */
function putNodeStyle(style: OutlineNodeStyle): void {
  const kept: OutlineNodeStyle[] = []
  for (let i: number = 0; i < current.nodeStyles.length; i++) {
    if (current.nodeStyles[i].paraId !== style.paraId) {
      kept.push(current.nodeStyles[i])
    }
  }
  // 回到"什么都没改"就不留行，避免侧车里堆空记录
  if (!isBlankNodeStyle(style)) {
    kept.push(copyNodeStyle(style))
  }
  current.nodeStyles = kept
}

function enqueueSave(chapterId: string, extras: OutlineExtras): void {
  const payload: OutlineExtras = copyExtras(extras)
  writeChain = writeChain.then((): Promise<void> => {
    return mapExtraRepo.replace(chapterId, payload)
  }).catch((e: Error): void => {
    Logger.warn('MapExtras save failed: ' + String(e))
  })
}

/** 打开导图前读一次；失败按"没有附加信息"处理，不挡用户看图 */
export async function loadMapExtras(chapterId: string): Promise<OutlineExtras> {
  try {
    current = await mapExtraRepo.load(chapterId)
  } catch (e) {
    Logger.warn('MapExtras load failed: ' + String(e))
    current = new OutlineExtras()
  }
  current.docId = chapterId
  return current
}

export function currentMapExtras(): OutlineExtras {
  return current
}

/** 关闭导图/切文稿时丢弃内存副本，等写链落完再清 */
export function dropMapExtras(): void {
  current = new OutlineExtras()
}

function removeSummary(summaryId: string): boolean {
  const kept: OutlineSummary[] = []
  let removed: boolean = false
  for (let i: number = 0; i < current.summaries.length; i++) {
    if (current.summaries[i].id === summaryId) {
      removed = true
    } else {
      kept.push(current.summaries[i])
    }
  }
  current.summaries = kept
  return removed
}

function removeBoundary(boundaryId: string): boolean {
  const kept: OutlineBoundary[] = []
  let removed: boolean = false
  for (let i: number = 0; i < current.boundaries.length; i++) {
    if (current.boundaries[i].id === boundaryId) {
      removed = true
    } else {
      kept.push(current.boundaries[i])
    }
  }
  current.boundaries = kept
  return removed
}

function removeRelation(relationId: string): boolean {
  const kept: OutlineRelation[] = []
  let removed: boolean = false
  for (let i: number = 0; i < current.relations.length; i++) {
    if (current.relations[i].id === relationId) {
      removed = true
    } else {
      kept.push(current.relations[i])
    }
  }
  current.relations = kept
  return removed
}

/**
 * 执行一条附加信息命令。同步返回新副本（导图页立刻重算图元），落库异步排队。
 * 返回 null = 这次没改成（导图页给提示，不改自己的显示）。
 */
export function applyMapExtraCommand(command: OutlineExtraCommand): OutlineExtras | null {
  const doc = app.editor.activeDoc
  if (doc === undefined) {
    return null
  }
  const chapterId: string = doc.id
  if (chapterId === '' || current.docId !== chapterId) {
    return null
  }

  if (command.kind === OUTLINE_EXTRA_ADD_SUMMARY) {
    if (command.fromId === '' || command.toId === '') {
      return null
    }
    const text: string = command.text.trim() === '' ? '概要' : command.text.trim()
    current.summaries.push(new OutlineSummary(IdGenerator.generate(), command.fromId, command.toId, text))
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_REMOVE_SUMMARY) {
    if (!removeSummary(command.extraId)) {
      return null
    }
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_ADD_RELATION) {
    if (command.fromId === '' || command.toId === '' || command.fromId === command.toId) {
      return null
    }
    const label: string = command.text.trim() === '' ? '相关' : command.text.trim()
    current.relations.push(new OutlineRelation(IdGenerator.generate(), command.fromId, command.toId, label))
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_REMOVE_RELATION) {
    if (!removeRelation(command.extraId)) {
      return null
    }
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_ADD_BOUNDARY) {
    if (command.fromId === '' || command.toId === '') {
      return null
    }
    current.boundaries.push(new OutlineBoundary(IdGenerator.generate(), command.fromId, command.toId,
      command.text.trim()))
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_REMOVE_BOUNDARY) {
    if (!removeBoundary(command.extraId)) {
      return null
    }
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }

  if (command.kind === OUTLINE_EXTRA_SET_NODE_STYLE) {
    const style: OutlineNodeStyle | null = command.style
    if (style === null || style.paraId === '') {
      return null
    }
    putNodeStyle(style)
    enqueueSave(chapterId, current)
    return copyExtras(current)
  }
  return null
}
