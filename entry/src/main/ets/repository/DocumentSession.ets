// 打开的文稿会话缓存：只保存已经由 loadOne 读出的段落模型。
//
// 目的：保存时不再为了对齐 para_id 把整篇段落表重新读一遍。
// 它不是第二个正文事实源：模型只在 loadOne 时从侧车/旧正文建立，
// saveDraft 提交成功后才用新模型替换；落库仍由 ChapterRepository 与保存队列负责。
import { DocModel } from '../editor/model/DocumentModel'

export class DocumentSession {
  private models: Map<string, DocModel> = new Map<string, DocModel>()
  /** 该模型是否已经有对应侧车行；旧稿/新稿首次保存前为 false */
  private persisted: Set<string> = new Set<string>()

  has(docId: string): boolean {
    return this.models.has(docId)
  }

  get(docId: string): DocModel | undefined {
    return this.models.get(docId)
  }

  isPersisted(docId: string): boolean {
    return this.persisted.has(docId)
  }

  put(docId: string, model: DocModel, persisted: boolean): void {
    this.models.set(docId, model)
    if (persisted) {
      this.persisted.add(docId)
    } else {
      this.persisted.delete(docId)
    }
  }

  evict(docId: string): void {
    this.models.delete(docId)
    this.persisted.delete(docId)
  }

  clear(): void {
    this.models.clear()
    this.persisted.clear()
  }

  size(): number {
    return this.models.size
  }
}

/** 进程内单例；窗口/页面切换不清，关闭文稿或重置编辑器时才释放。 */
export const documentSession: DocumentSession = new DocumentSession()
