// 书籍（项目）模型
export enum BookMode {
  NORMAL = 'normal',
  PROFESSIONAL = 'professional'
}

export interface BookModel {
  id: string
  name: string
  mode: BookMode
  createdAt: number
  updatedAt: number
}
