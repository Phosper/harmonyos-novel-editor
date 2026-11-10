// 段落侧车仓储：一次替换一篇文稿的全部段落与行内样式。
//
// 当前阶段（P5 第一步）只给迁移与回归使用，**不接** EditorStore/FlowText；
// 正文事实源仍是 chapters.content，因此这里不会造成第二份可写正文。
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '../database/DatabaseHelper'
import { ParagraphDao, ParagraphRunDao } from '../database/ParagraphDao'
import { Logger } from '../utils/Logger'
import { DocModel, DocRows, DocParagraphRow, DocRunRow, documentRows } from '../editor/model/DocumentModel'
import { ParagraphKind } from '../editor/flowtext/model/EditorTypes'

export class ParagraphRepository {
  private readonly tx: relationalStore.Transaction | null
  private readonly paragraphs: ParagraphDao
  private readonly runs: ParagraphRunDao

  constructor(tx: relationalStore.Transaction | null = null) {
    this.tx = tx
    this.paragraphs = new ParagraphDao(tx)
    this.runs = new ParagraphRunDao(tx)
  }

  /**
   * 用段落模型整体替换一篇文稿的侧车数据。
   * 未传事务时自己开独立事务；传入事务时交给调用方提交/回滚。
   */
  async replaceDocument(docId: string, model: DocModel): Promise<void> {
    if (this.tx !== null) {
      await this.write(docId, model)
      return
    }
    const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
    try {
      const repo: ParagraphRepository = new ParagraphRepository(tx)
      await repo.write(docId, model)
      await tx.commit()
    } catch (e) {
      try {
        await tx.rollback()
      } catch (rollbackError) {
        Logger.error('Paragraph rollback failed: ' + String(rollbackError))
      }
      throw new Error(String(e))
    }
  }

  private async write(docId: string, model: DocModel): Promise<void> {
    const rows: DocRows = documentRows(model)
    // 空文档也必须留一行空段：否则“删光正文后继续写”会丢掉段落身份。
    if (rows.paragraphs.length === 0) {
      rows.paragraphs.push(new DocParagraphRow(docId, 'p1', 0, ParagraphKind.BODY, 0, ''))
    }
    // 先删 runs 再删 paragraphs（外键方向）；写回时反过来。
    await this.runs.deleteByDoc(docId)
    await this.paragraphs.deleteByDoc(docId)
    for (let i: number = 0; i < rows.paragraphs.length; i++) {
      await this.paragraphs.insertParagraph(docId, rows.paragraphs[i])
    }
    for (let i: number = 0; i < rows.runs.length; i++) {
      await this.runs.insertRun(docId, rows.runs[i])
    }
  }

  /**
   * 保存路径的差异写入：只改变化的段落/行内样式，避免每次输入都重写整篇侧车。
   * oldModel 为 null（新稿/侧车缺失）时退化为整篇写入。
   */
  async saveModel(docId: string, oldModel: DocModel | null, newModel: DocModel): Promise<void> {
    if (this.tx !== null) {
      await this.writeDiff(docId, oldModel, newModel)
      return
    }
    const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
    try {
      const repo: ParagraphRepository = new ParagraphRepository(tx)
      await repo.writeDiff(docId, oldModel, newModel)
      await tx.commit()
    } catch (e) {
      try {
        await tx.rollback()
      } catch (rollbackError) {
        Logger.error('Paragraph save rollback failed: ' + String(rollbackError))
      }
      throw new Error(String(e))
    }
  }

  private async writeDiff(docId: string, oldModel: DocModel | null, newModel: DocModel): Promise<void> {
    const newRows: DocRows = documentRows(newModel)
    if (newRows.paragraphs.length === 0) {
      newRows.paragraphs.push(new DocParagraphRow(docId, 'p1', 0, ParagraphKind.BODY, 0, ''))
    }
    if (oldModel === null) {
      await this.write(docId, newModel)
      return
    }
    const oldRows: DocRows = documentRows(oldModel)
    const oldParaById: Map<string, DocParagraphRow> = new Map<string, DocParagraphRow>()
    for (let i: number = 0; i < oldRows.paragraphs.length; i++) {
      oldParaById.set(oldRows.paragraphs[i].paraId, oldRows.paragraphs[i])
    }
    const newIds: Set<string> = new Set<string>()
    for (let i: number = 0; i < newRows.paragraphs.length; i++) {
      newIds.add(newRows.paragraphs[i].paraId)
    }
    // 删除消失的段落（同时删 runs，不依赖数据库外键在测试替身里也生效）。
    for (let i: number = 0; i < oldRows.paragraphs.length; i++) {
      const id: string = oldRows.paragraphs[i].paraId
      if (!newIds.has(id)) {
        await this.runs.deleteByPara(docId, id)
        await this.paragraphs.deleteParagraph(docId, id)
      }
    }
    // 插入/更新段落。
    for (let i: number = 0; i < newRows.paragraphs.length; i++) {
      const row: DocParagraphRow = newRows.paragraphs[i]
      const old: DocParagraphRow | undefined = oldParaById.get(row.paraId)
      if (old === undefined) {
        await this.paragraphs.insertParagraph(docId, row)
      } else if (old.ordinal !== row.ordinal || old.kind !== row.kind ||
        old.indent !== row.indent || old.text !== row.text) {
        await this.paragraphs.updateParagraph(docId, row)
      }
    }
    // 行内样式按段落整体比较；只有变化的段落才删旧写新。
    const oldRunByPara: Map<string, DocRunRow[]> = groupRunsByPara(oldRows.runs)
    const newRunByPara: Map<string, DocRunRow[]> = groupRunsByPara(newRows.runs)
    for (let i: number = 0; i < newRows.paragraphs.length; i++) {
      const id: string = newRows.paragraphs[i].paraId
      const oldRuns: DocRunRow[] = oldRunByPara.get(id) ?? []
      const newRuns: DocRunRow[] = newRunByPara.get(id) ?? []
      if (oldParaById.get(id) !== undefined && runSignature(oldRuns) === runSignature(newRuns)) {
        continue
      }
      await this.runs.deleteByPara(docId, id)
      for (let r: number = 0; r < newRuns.length; r++) {
        await this.runs.insertRun(docId, newRuns[r])
      }
    }
  }

  /** 读回一篇文稿的段落模型；没有任何段落行时返回 null（交给迁移/旧路径兜底） */
  async loadDocument(docId: string, title: string): Promise<DocModel | null> {
    const paragraphs = await this.paragraphs.listByDoc(docId)
    if (paragraphs.length === 0) {
      return null
    }
    const model: DocModel = new DocModel()
    model.id = docId
    model.title = title
    model.paragraphs = paragraphs
    model.runs = await this.runs.listByDoc(docId)
    // content_version 还没有落库，先给 1；写路径收口时再接 chapters.content_version。
    model.version = 1
    return model
  }
}

function groupRunsByPara(runs: DocRunRow[]): Map<string, DocRunRow[]> {
  const grouped: Map<string, DocRunRow[]> = new Map<string, DocRunRow[]>()
  for (let i: number = 0; i < runs.length; i++) {
    const run: DocRunRow = runs[i]
    let list: DocRunRow[] | undefined = grouped.get(run.paraId)
    if (list === undefined) {
      list = []
      grouped.set(run.paraId, list)
    }
    list.push(run)
  }
  return grouped
}

/** 行内样式的无序签名：DB 读回顺序与内存顺序可能不同，比较前先归一 */
function runSignature(runs: DocRunRow[]): string {
  const parts: string[] = []
  for (let i: number = 0; i < runs.length; i++) {
    const run: DocRunRow = runs[i]
    parts.push(run.start.toString() + ',' + run.end.toString() + ',' +
      (run.bold ? '1' : '0') + ',' + (run.italic ? '1' : '0'))
  }
  parts.sort()
  return parts.join(';')
}
