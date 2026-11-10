// 导图附加信息（概要 / 关系线）的 DAO。两张表都以 chapter_id 为主键前缀，
// 随 chapters 级联删除（DatabaseHelper 已开 PRAGMA foreign_keys = ON）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { OutlineSummary, OutlineRelation } from 'feature_contracts'

export class MapSummaryDao extends BaseDao<OutlineSummary> {
  protected getTableName(): string {
    return 'doc_map_summary'
  }

  protected rowToModel(rs: relationalStore.ResultSet): OutlineSummary {
    return new OutlineSummary(this.safeGetString(rs, 'summary_id'), this.safeGetString(rs, 'start_para_id'),
      this.safeGetString(rs, 'end_para_id'), this.safeGetString(rs, 'text'))
  }

  async listByDoc(chapterId: string): Promise<OutlineSummary[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.orderByAsc('created_at')
    return this.queryRows(predicates)
  }

  async insertSummary(chapterId: string, summary: OutlineSummary, createdAt: number): Promise<void> {
    await this.insertRow({
      chapter_id: chapterId,
      summary_id: summary.id,
      start_para_id: summary.startParaId,
      end_para_id: summary.endParaId,
      text: summary.text,
      created_at: createdAt
    })
  }

  async updateText(chapterId: string, summaryId: string, text: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.equalTo('summary_id', summaryId)
    await this.updateRow({ text: text }, predicates)
  }

  async deleteSummary(chapterId: string, summaryId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.equalTo('summary_id', summaryId)
    await this.deleteRow(predicates)
  }

  async deleteByDoc(chapterId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    await this.deleteRow(predicates)
  }
}

export class MapRelationDao extends BaseDao<OutlineRelation> {
  protected getTableName(): string {
    return 'doc_map_relation'
  }

  protected rowToModel(rs: relationalStore.ResultSet): OutlineRelation {
    return new OutlineRelation(this.safeGetString(rs, 'relation_id'), this.safeGetString(rs, 'from_para_id'),
      this.safeGetString(rs, 'to_para_id'), this.safeGetString(rs, 'label'))
  }

  async listByDoc(chapterId: string): Promise<OutlineRelation[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.orderByAsc('created_at')
    return this.queryRows(predicates)
  }

  async insertRelation(chapterId: string, relation: OutlineRelation, createdAt: number): Promise<void> {
    await this.insertRow({
      chapter_id: chapterId,
      relation_id: relation.id,
      from_para_id: relation.fromParaId,
      to_para_id: relation.toParaId,
      label: relation.label,
      kind: 'relate',
      created_at: createdAt
    })
  }

  async deleteRelation(chapterId: string, relationId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.equalTo('relation_id', relationId)
    await this.deleteRow(predicates)
  }

  async deleteByDoc(chapterId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    await this.deleteRow(predicates)
  }
}
