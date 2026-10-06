// 仓储单例 —— Repository 本身无状态（只包一层 DAO），全应用共用一份即可，
// 避免各处 new XxxRepository() 造成重复实例与潜在状态漂移。
import { BookRepository } from '../repository/BookRepository'
import { ChapterRepository } from '../repository/ChapterRepository'
import { MaterialRepository } from '../repository/MaterialRepository'
import { RelationshipRepository } from '../repository/RelationshipRepository'

export const bookRepo: BookRepository = new BookRepository()
export const chapterRepo: ChapterRepository = new ChapterRepository()
export const materialRepo: MaterialRepository = new MaterialRepository()
export const relationRepo: RelationshipRepository = new RelationshipRepository()
