// common/src/main/ets/model/Chapter.ets

export interface ChapterModel {
  id: string
  bookId: string
  title: string
  content: string
  order: number
  wordCount: number
  createdAt: number
  updatedAt: number
}
