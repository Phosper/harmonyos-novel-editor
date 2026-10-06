// 灵感模型（bookId 为 null 表示暂不归类）
export interface InspirationModel {
  id: string
  bookId: string | null
  content: string
  createdAt: number
  updatedAt: number
}
