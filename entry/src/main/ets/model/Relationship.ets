// 人物关系模型
export enum RelationshipType {
  POSITIVE = 'positive', // 正面（恋人/家人/朋友）
  NEUTRAL = 'neutral',   // 中立（同学/同事）
  NEGATIVE = 'negative', // 负面（敌对/背叛）
  INDIRECT = 'indirect'  // 间接/过去
}

export interface RelationshipModel {
  id: string
  bookId: string
  characterIdA: string
  characterIdB: string
  type: RelationshipType
  label: string
  notes: string
  createdAt: number
  updatedAt: number
}
