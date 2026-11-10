// 段落侧车 DAO：doc_paragraphs / doc_runs。
// 真正的正文写入口仍是 ChapterDao.saveDraft；本文件只服务 P5 的迁移与后续读路径切换。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { DocParagraph, DocInlineRun, DocParagraphRow, DocRunRow } from '../editor/model/DocumentModel'

export class ParagraphDao extends BaseDao<DocParagraph> {
  protected getTableName(): string {
    return 'doc_paragraphs'
  }

  protected rowToModel(rs: relationalStore.ResultSet): DocParagraph {
    return new DocParagraph(this.safeGetString(rs, 'para_id'), this.safeGetLong(rs, 'kind'),
      this.safeGetString(rs, 'text'), this.safeGetLong(rs, 'indent'),
      this.safeGetDouble(rs, 'ordinal'))
  }

  async insertParagraph(docId: string, row: DocParagraphRow): Promise<void> {
    await this.insertRow({
      doc_id: docId,
      para_id: row.paraId,
      ordinal: row.ordinal,
      kind: row.kind,
      indent: row.indent,
      text: row.text
    })
  }

  async updateParagraph(docId: string, row: DocParagraphRow): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    predicates.equalTo('para_id', row.paraId)
    await this.updateRow({
      ordinal: row.ordinal,
      kind: row.kind,
      indent: row.indent,
      text: row.text
    }, predicates)
  }

  async deleteParagraph(docId: string, paraId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    predicates.equalTo('para_id', paraId)
    await this.deleteRow(predicates)
  }

  async deleteByDoc(docId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    await this.deleteRow(predicates)
  }

  async listByDoc(docId: string): Promise<DocParagraph[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    predicates.orderByAsc('ordinal')
    return this.queryRows(predicates)
  }
}

export class ParagraphRunDao extends BaseDao<DocInlineRun> {
  protected getTableName(): string {
    return 'doc_runs'
  }

  protected rowToModel(rs: relationalStore.ResultSet): DocInlineRun {
    return new DocInlineRun(this.safeGetString(rs, 'para_id'), this.safeGetLong(rs, 'start_off'),
      this.safeGetLong(rs, 'end_off'), this.safeGetBool(rs, 'bold'), this.safeGetBool(rs, 'italic'))
  }

  async insertRun(docId: string, row: DocRunRow): Promise<void> {
    await this.insertRow({
      doc_id: docId,
      para_id: row.paraId,
      start_off: row.start,
      end_off: row.end,
      bold: row.bold ? 1 : 0,
      italic: row.italic ? 1 : 0
    })
  }

  async deleteByDoc(docId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    await this.deleteRow(predicates)
  }

  async deleteByPara(docId: string, paraId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    predicates.equalTo('para_id', paraId)
    await this.deleteRow(predicates)
  }

  async listByDoc(docId: string): Promise<DocInlineRun[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('doc_id', docId)
    predicates.orderByAsc('start_off')
    return this.queryRows(predicates)
  }
}
