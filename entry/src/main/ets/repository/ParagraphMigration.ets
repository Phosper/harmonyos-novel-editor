// P5 一次性迁移：把 chapters.content + format_runs 拆成段落侧车。
//
// 设计边界：
//   - 逐篇读全文、逐篇独立事务；中断后下次启动按 doc 是否已有段落行继续，不重复写；
//   - 只写 doc_paragraphs / doc_runs，不改 chapters.content，也不接编辑器；
//   - 完成标记写在 schema_meta，避免每次启动扫描全库。
import { ChapterDao } from '../database/ChapterDao'
import { MetaDao } from '../database/MetaDao'
import { ParagraphRepository } from './ParagraphRepository'
import { createDocument } from '../editor/model/DocumentModel'
import type { DocModel } from '../editor/model/DocumentModel'
import type { ChapterModel } from '../model/Chapter'
import { Logger } from '../utils/Logger'

const PARAGRAPH_MIGRATION_KEY: string = 'paragraph_v1'

export class ParagraphMigration {
  /** @returns 本次实际补齐的文稿数；没有待迁移文稿时返回 0 */
  async runIfNeeded(): Promise<number> {
    const meta: MetaDao = new MetaDao()
    const marker: string = await meta.get(PARAGRAPH_MIGRATION_KEY)
    const chapterDao: ChapterDao = new ChapterDao()
    // 每次启动只查“还没有段落侧车”的文稿：初次迁移与后来新建的文稿都走同一条路。
    const ids: string[] = await chapterDao.queryIdsWithoutParagraphs()
    if (ids.length === 0) {
      if (marker !== 'done') {
        await meta.set(PARAGRAPH_MIGRATION_KEY, 'done')
      }
      return 0
    }
    const repo: ParagraphRepository = new ParagraphRepository()
    let migrated: number = 0
    for (let i: number = 0; i < ids.length; i++) {
      const chapter: ChapterModel | null = await chapterDao.queryById(ids[i])
      if (chapter === null) {
        continue
      }
      const runs: string = chapter.formatRuns !== undefined ? chapter.formatRuns : ''
      const model: DocModel = createDocument(chapter.id, chapter.title, chapter.content, runs)
      await repo.replaceDocument(chapter.id, model)
      migrated++
      if (migrated % 50 === 0) {
        Logger.info('Paragraph migration progress: ' + migrated + '/' + ids.length)
      }
    }
    if (marker !== 'done') {
      await meta.set(PARAGRAPH_MIGRATION_KEY, 'done')
    }
    Logger.info('Paragraph migration complete: migrated=' + migrated + ', pending=' + ids.length)
    return migrated
  }
}

export const paragraphMigration: ParagraphMigration = new ParagraphMigration()
