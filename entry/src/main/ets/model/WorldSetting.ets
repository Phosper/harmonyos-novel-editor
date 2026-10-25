// 世界设定模型
export enum WorldCategory {
  GEOGRAPHY = 'geography', // 地理
  POLITICS = 'politics',   // 政治
  HISTORY = 'history',     // 历史
  MAGIC_TECH = 'magic_tech', // 魔法科技
  RACE = 'race',           // 种族
  CULTURE = 'culture',     // 文化
  OTHER = 'other'          // 其他
}

export interface WorldSettingModel {
  id: string
  bookId: string
  name: string
  category: WorldCategory
  region: string
  description: string
  notes: string
  content: string
  createdAt: number
  updatedAt: number
}
