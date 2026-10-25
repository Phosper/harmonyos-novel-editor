// 人物模型
export enum CharacterType {
  PROTAGONIST = 'protagonist', // 主角
  SUPPORT = 'support',         // 配角
  VILLAIN = 'villain',         // 反派
  ORG = 'org',                 // 组织/势力
  PLACE = 'place'              // 地点
}

export interface CharacterModel {
  id: string
  bookId: string
  name: string
  alias: string
  age: string
  appearance: string
  personality: string
  background: string
  notes: string
  characterType: CharacterType
  createdAt: number
  updatedAt: number
}
