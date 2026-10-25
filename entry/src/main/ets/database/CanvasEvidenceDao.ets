// 思路板素材 DAO（topic_evidence 表）：引文 / 判断 / 笔记
//
// 引文的 quote_text 是原文快照，正文实时读取走编辑器（这里不复制正文段落）。
import { relationalStore } from '@kit.ArkData'
import { BaseDao } from './BaseDao'
import { CanvasEvidenceItem, canvasSqlPlaceholders } from '../model/CanvasStoreModels'
import { CanvasEvidenceKind } from '../model/CanvasTypes'

// ArkTS 枚举不能当对象用，故显式列出；未知值回退 NOTE（不影响展示，只是分组不同）。
function canvasEvidenceKindOf(value: string): CanvasEvidenceKind {
  if (value === CanvasEvidenceKind.QUOTE) {
    return CanvasEvidenceKind.QUOTE
  }
  if (value === CanvasEvidenceKind.JUDGEMENT) {
    return CanvasEvidenceKind.JUDGEMENT
  }
  return CanvasEvidenceKind.NOTE
}

export class CanvasEvidenceDao extends BaseDao<CanvasEvidenceItem> {
  protected getTableName(): string {
    return 'topic_evidence'
  }

  protected rowToModel(rs: relationalStore.ResultSet): CanvasEvidenceItem {
    const item: CanvasEvidenceItem = new CanvasEvidenceItem()
    item.id = this.safeGetString(rs, 'id')
    item.cardId = this.safeGetString(rs, 'topic_id')
    item.kind = canvasEvidenceKindOf(this.safeGetString(rs, 'kind'))
    item.docId = this.safeGetString(rs, 'doc_id')
    item.paraIndex = this.safeGetLong(rs, 'para_index')
    item.startOff = this.safeGetLong(rs, 'start_off')
    item.endOff = this.safeGetLong(rs, 'end_off')
    item.fingerprint = this.safeGetString(rs, 'fingerprint')
    item.quoteText = this.safeGetString(rs, 'quote_text')
    item.userText = this.safeGetString(rs, 'user_text')
    item.sourceLabel = this.safeGetString(rs, 'source_label')
    item.createdAt = this.safeGetLong(rs, 'created_at')
    return item
  }

  async insert(data: CanvasEvidenceItem): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      id: data.id,
      topic_id: data.cardId,
      kind: data.kind,
      doc_id: data.docId,
      para_index: data.paraIndex,
      start_off: data.startOff,
      end_off: data.endOff,
      fingerprint: data.fingerprint,
      quote_text: data.quoteText,
      user_text: data.userText,
      source_label: data.sourceLabel,
      created_at: data.createdAt
    }
    await this.insertRow(valueBucket)
  }

  /** 只改素材正文（引文改 quote_text，判断/笔记改 user_text）；来源字段不动。 */
  async updateText(id: string, quoteText: string, userText: string): Promise<void> {
    const valueBucket: relationalStore.ValuesBucket = {
      quote_text: quoteText,
      user_text: userText
    }
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.updateRow(valueBucket, predicates)
  }

  async delete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('id', id)
    await this.deleteRow(predicates)
  }

  /** 删卡片时连带删掉它的素材（避免孤儿行）。 */
  async deleteByCard(cardId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.newPredicates()
    predicates.equalTo('topic_id', cardId)
    await this.deleteRow(predicates)
  }

  async queryByCard(cardId: string): Promise<CanvasEvidenceItem[]> {
    const p: relationalStore.RdbPredicates = this.newPredicates()
    p.equalTo('topic_id', cardId)
    p.orderByAsc('created_at')
    return this.queryRows(p)
  }

  /**
   * 批量取多张卡的素材（一次 IN 查询）。卡片库/画布要显示每张卡的素材数，
   * 逐卡查询会变成 N 次往返（几十张卡就是几十次 IO）。
   */
  async queryByCards(cardIds: string[]): Promise<CanvasEvidenceItem[]> {
    if (cardIds.length === 0) {
      return []
    }
    const sql: string = 'SELECT * FROM topic_evidence WHERE topic_id IN (' +
      canvasSqlPlaceholders(cardIds.length) + ') ORDER BY created_at ASC'
    const args: relationalStore.ValueType[] = []
    for (let i: number = 0; i < cardIds.length; i++) {
      args.push(cardIds[i])
    }
    return this.querySqlRows(sql, args)
  }
}
