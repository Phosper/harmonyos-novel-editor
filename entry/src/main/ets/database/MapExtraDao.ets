// 导图附加信息（概要 / 关系线）的 DAO。两张表都以 chapter_id 为主键前缀，
// 随 chapters 级联删除（DatabaseHelper 已开 PRAGMA foreign_keys = ON）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { OutlineSummary, OutlineRelation, OutlineNodeStyle, OutlineBoundary } from 'feature_contracts'

/** 标记列表在库里存成逗号分隔：图标本身不含逗号，够用且可读 */
function joinMarkers(markers: string[]): string {
  let out: string = ''
  for (let i: number = 0; i < markers.length; i++) {
    out = i === 0 ? markers[i] : out + ',' + markers[i]
  }
  return out
}

function splitMarkers(text: string): string[] {
  const out: string[] = []
  if (text === '') {
    return out
  }
  const parts: string[] = text.split(',')
  for (let i: number = 0; i < parts.length; i++) {
    if (parts[i] !== '') {
      out.push(parts[i])
    }
  }
  return out
}

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

/** 节点级样式：一个段落在库里最多一行 */
export class MapNodeDao extends BaseDao<OutlineNodeStyle> {
  protected getTableName(): string {
    return 'doc_map_node'
  }

  protected rowToModel(rs: relationalStore.ResultSet): OutlineNodeStyle {
    const style: OutlineNodeStyle = new OutlineNodeStyle(this.safeGetString(rs, 'para_id'))
    style.shape = this.safeGetString(rs, 'shape')
    style.fill = this.safeGetString(rs, 'fill')
    style.bold = this.safeGetBool(rs, 'bold')
    style.markers = splitMarkers(this.safeGetString(rs, 'markers'))
    style.label = this.safeGetString(rs, 'label')
    return style
  }

  async listByDoc(chapterId: string): Promise<OutlineNodeStyle[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    return this.queryRows(predicates)
  }

  async insertStyle(chapterId: string, style: OutlineNodeStyle, updatedAt: number): Promise<void> {
    await this.insertRow({
      chapter_id: chapterId,
      para_id: style.paraId,
      shape: style.shape,
      fill: style.fill,
      bold: style.bold ? 1 : 0,
      markers: joinMarkers(style.markers),
      label: style.label,
      updated_at: updatedAt
    })
  }

  async deleteByDoc(chapterId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    await this.deleteRow(predicates)
  }
}

/** 外框：一张文稿下若干行，按创建顺序读 */
export class MapBoundaryDao extends BaseDao<OutlineBoundary> {
  protected getTableName(): string {
    return 'doc_map_boundary'
  }

  protected rowToModel(rs: relationalStore.ResultSet): OutlineBoundary {
    return new OutlineBoundary(this.safeGetString(rs, 'boundary_id'), this.safeGetString(rs, 'start_para_id'),
      this.safeGetString(rs, 'end_para_id'), this.safeGetString(rs, 'text'))
  }

  async listByDoc(chapterId: string): Promise<OutlineBoundary[]> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    predicates.orderByAsc('created_at')
    return this.queryRows(predicates)
  }

  async insertBoundary(chapterId: string, boundary: OutlineBoundary, createdAt: number): Promise<void> {
    await this.insertRow({
      chapter_id: chapterId,
      boundary_id: boundary.id,
      start_para_id: boundary.startParaId,
      end_para_id: boundary.endParaId,
      text: boundary.text,
      created_at: createdAt
    })
  }

  async deleteByDoc(chapterId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('chapter_id', chapterId)
    await this.deleteRow(predicates)
  }
}
