// 章节（文稿）模型

/** 废纸篓保留天数（领域规则，DAO 清理与列表倒计时共用同一来源） */
export const TRASH_RETENTION_DAYS: number = 7

/** 文稿正文格式：TXT 纯文本 / MD Markdown */
export enum ChapterFormat {
  TXT = 'txt',
  MD = 'md'
}

export interface ChapterModel {
  id: string
  bookId: string
  title: string
  content: string
  format: ChapterFormat
  order: number
  wordCount: number
  /** 上次编辑光标位置（UTF-16 偏移），用于进入章节时恢复 */
  caretOffset: number
  createdAt: number
  updatedAt: number
  isFav: boolean
  isInspiration: boolean
  isTrash: boolean
  /** 行内/段落格式标注的序列化边车（T025；缺省为空 = 纯文本） */
  formatRuns?: string
}
