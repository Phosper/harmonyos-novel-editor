// 导图命令的宿主实现（M2）
//
// 数据流：结构包 dispatch(命令) → 这里把命令翻成段落模型编辑 → project() → 统一编辑事务
//        → 保存队列 → 用新模型重新生成快照返回给导图页。
//
// 为什么全部走 applyGeneratedContent：它已经是"一步可撤销 + 通知画布回灌 + 触发防抖保存"的
// 唯一入口（初稿生成、大纲上移下移都在用），导图的改名/增删/移动因此免费获得撤销与保存。
import { app } from '../store/AppStores'
import { documentSession } from '../repository/DocumentSession'
import {
  reconcileDocument, indexOfParagraph, sectionRange, project, insertParagraph, removeSection,
  setParagraphKind, moveSectionUp, moveSectionDown, previousHeadingIndex, nextHeadingIndex
} from './model/DocumentModel'
import type { DocModel, Projection } from './model/DocumentModel'
import { buildOutlineSnapshotFromModel } from './OutlineExtract'
import { OutlineCommand, OutlineCommandKind } from 'feature_contracts'
import type { OutlineSnapshot } from 'feature_contracts'
import { Logger } from '../utils/Logger'

const HEADING_MIN: number = 1
const HEADING_MAX: number = 3

/** 当前打开文稿的模型（与库里侧车对齐 id；未保存的编辑由 reconcile 保住旧 id） */
function currentModel(): DocModel | null {
  const doc = app.editor.activeDoc
  if (doc === undefined) {
    return null
  }
  const cached: DocModel | undefined = documentSession.get(doc.id)
  return reconcileDocument(cached === undefined ? null : cached, doc.id, doc.title, doc.draft, doc.runsJson)
}

/** 把模型写回正文；成功返回新快照，失败返回 null */
function commit(model: DocModel): OutlineSnapshot | null {
  const doc = app.editor.activeDoc
  if (doc === undefined) {
    return null
  }
  const projection: Projection = project(model)
  if (!app.editor.applyGeneratedContent(doc.id, projection.text, projection.runsJson)) {
    return null
  }
  app.editor.flushDoc(doc.id).catch((e: Error) => {
    Logger.warn('OutlineCommands: flush failed: ' + String(e))
  })
  return buildOutlineSnapshotFromModel(model, app.editor.contentRev)
}

/**
 * 执行一条导图命令。
 * 只做结构编辑；不校验 UI 语义（例如删除前的二次确认由导图页负责）。
 */
export function applyOutlineCommand(command: OutlineCommand): OutlineSnapshot | null {
  const model: DocModel | null = currentModel()
  if (model === null) {
    return null
  }
  const index: number = indexOfParagraph(model, command.paraId)
  if (index < 0) {
    Logger.warn('OutlineCommands: paragraph not found ' + command.paraId)
    return null
  }
  const level: number = model.paragraphs[index].kind

  if (command.kind === OutlineCommandKind.RENAME) {
    const text: string = command.text.trim()
    if (text === '' || text === model.paragraphs[index].text) {
      return null
    }
    model.paragraphs[index].text = text
    model.version++
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.SET_KIND) {
    const target: number = Math.max(HEADING_MIN, Math.min(HEADING_MAX, command.level))
    if (target === level) {
      return null
    }
    if (!setParagraphKind(model, index, target)) {
      return null
    }
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.INSERT_SIBLING) {
    // 同级：插到当前节之后（含其所有子节），保持"这一节整体在下一条同级之前"
    const range: number[] = sectionRange(model, index)
    const text: string = command.text.trim() === '' ? '新主题' : command.text.trim()
    insertParagraph(model, range[1], level, text)
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.INSERT_CHILD) {
    // 子级：插到当前节末尾，级别 +1（最多 H3）
    const range: number[] = sectionRange(model, index)
    const text: string = command.text.trim() === '' ? '新主题' : command.text.trim()
    insertParagraph(model, range[1], Math.min(HEADING_MAX, level + 1), text)
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.DELETE_SECTION) {
    if (!removeSection(model, index)) {
      return null
    }
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.MOVE_UP) {
    if (!moveSectionUp(model, index)) {
      return null
    }
    return commit(model)
  }

  if (command.kind === OutlineCommandKind.MOVE_DOWN) {
    if (!moveSectionDown(model, index)) {
      return null
    }
    return commit(model)
  }
  return null
}

/**
 * 导图里的撤销/重做。
 * 结构编辑本来就落在正文撤销栈里（一次命令 = 一步），所以这里只是把
 * "退一步"翻译成正文撤销，再用恢复后的模型重建快照。
 */
export function applyOutlineHistory(redo: boolean): OutlineSnapshot | null {
  const doc = app.editor.activeDoc
  if (doc === undefined) {
    return null
  }
  if (redo) {
    if (!app.editor.canRedo) {
      return null
    }
    app.editor.redo()
  } else {
    if (!app.editor.canUndo) {
      return null
    }
    app.editor.undo()
  }
  const model: DocModel | null = currentModel()
  if (model === null) {
    return null
  }
  return buildOutlineSnapshotFromModel(model, app.editor.contentRev)
}

/** 给导图页用的"能不能动"判断（灰化按钮用），不写正文 */
export function canMoveOutline(paraId: string, up: boolean): boolean {
  const model: DocModel | null = currentModel()
  if (model === null) {
    return false
  }
  const index: number = indexOfParagraph(model, paraId)
  if (index < 0) {
    return false
  }
  if (up) {
    return previousHeadingIndex(model, index) >= 0
  }
  return nextHeadingIndex(model, sectionRange(model, index)[1]) >= 0
}

/** 供"新建节点后自动进入改名"使用：段落是否仍是标题（防止类型误用） */
export function isHeadingKind(kind: number): boolean {
  return kind >= HEADING_MIN && kind <= HEADING_MAX
}
