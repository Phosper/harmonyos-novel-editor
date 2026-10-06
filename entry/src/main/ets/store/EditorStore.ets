// 编辑器状态：打开的文稿、正文草稿、光标、保存与撤销/重做
//
// 相对旧实现修掉的数据可靠性问题：
// 1. 旧版自动保存只写「当前章节」，切标签页/切项目时不落库 → 切走即丢稿。
//    这里改为：切走前必存（activate/close/切项目/退后台/销毁都会 flush），
//    另加编辑停顿防抖保存 + 定时安全网兜底。
// 2. 旧版 performAutoSave 在正文为空时直接 return → 一篇被清空的文稿永远存不下去。
//    这里不再对空内容做任何特殊处理。
// 3. 旧版撤销栈从来没有写入点（pushUndoState 零调用），撤销/重做是死按钮。
//    这里由 setContent 自动记录历史快照（带时间窗合并，避免逐键一条）。
import { ChapterFormat } from '../model/Chapter'
import type { ChapterModel } from '../model/Chapter'
import { DOC_TAB_COLORS } from '../constants/DesignTokens'
import { OpenDoc, SaveState, HistoryEntry } from './StoreModels'
import { chapterRepo } from './Repos'
import { Logger } from '../utils/Logger'
import { exceedsContentLimit, utf8ByteLength, contentLimitMessage, countChars } from '../utils/TextLimit'

/** 编辑停顿多久后落库 */
const SAVE_DEBOUNCE_MS: number = 1200
/** 安全网：无论是否继续编辑，最多多久落库一次 */
const SAVE_SAFETY_MS: number = 30000
/** 历史快照合并窗口：窗口内的连续输入合并为一条，避免逐键一条 */
const HISTORY_MERGE_MS: number = 600
const MAX_HISTORY: number = 120

@ObservedV2
export class EditorStore {
  @Trace openDocs: OpenDoc[] = []
  @Trace activeId: string = ''
  @Trace saveState: SaveState = SaveState.IDLE
  @Trace saveHint: string = ''
  /**
   * 正文被「外部」整体替换的版本号：撤销 / 重做回退 draft 时自增。
   *
   * 为什么需要它：编辑器（Canvas 自绘）把正文视为自己的内部状态，
   * 只在 docId 变化时从外部载入一次。若 store 侧改了 draft 而不带这个信号，
   * 画布上的文字不会跟着回退 —— 表现为「点了撤销，界面纹丝不动」，
   * 而库里其实已经写回旧内容，两边越差越远。
   * 编辑器每收到一次该值变化就重新载入一次 draft，从而与 store 对齐。
   */
  @Trace contentRev: number = 0

  private undoStack: HistoryEntry[] = []
  private redoStack: HistoryEntry[] = []
  private debounceTimer: number = -1
  private safetyTimer: number = -1
  private lastHistoryAt: number = 0
  /** 撤销/重做/载入期间抑制历史记录，避免把回退动作本身也记成一步 */
  private restoring: boolean = false

  // ===== 派生 =====

  get activeDoc(): OpenDoc | undefined {
    return this.openDocs.find((d: OpenDoc) => d.id === this.activeId)
  }

  get hasDoc(): boolean {
    return this.activeDoc !== undefined
  }

  get title(): string {
    const d: OpenDoc | undefined = this.activeDoc
    return d !== undefined ? d.title : ''
  }

  get content(): string {
    const d: OpenDoc | undefined = this.activeDoc
    return d !== undefined ? d.draft : ''
  }

  /** 当前文稿的格式标注边车（T024） */
  get runsJson(): string {
    const d: OpenDoc | undefined = this.activeDoc
    return d !== undefined ? d.runsJson : ''
  }

  get format(): ChapterFormat {
    const d: OpenDoc | undefined = this.activeDoc
    return d !== undefined ? d.format : ChapterFormat.TXT
  }

  get caret(): number {
    const d: OpenDoc | undefined = this.activeDoc
    return d !== undefined ? d.caret : 0
  }

  get wordCount(): number {
    // 按字符计而非码元：emoji / 组合字符算1 字，否则会被多算
    return countChars(this.content)
  }

  get canUndo(): boolean {
    return this.undoStack.length > 0
  }

  get canRedo(): boolean {
    return this.redoStack.length > 0
  }

  get dirtyCount(): number {
    let n: number = 0
    for (const d of this.openDocs) {
      if (d.dirty) {
        n++
      }
    }
    return n
  }

  // ===== 标签页 =====

  async openChapter(ch: ChapterModel): Promise<void> {
    const existing: OpenDoc | undefined = this.openDocs.find((d: OpenDoc) => d.id === ch.id)
    if (existing !== undefined) {
      await this.activate(ch.id)
      return
    }
    const colors: string[] = DOC_TAB_COLORS
    const color: string = colors[this.openDocs.length % colors.length]
    this.openDocs.push(new OpenDoc(ch.id, ch.title, ch.format, color, ch.content, ch.caretOffset,
      ch.formatRuns !== undefined ? ch.formatRuns : ''))
    await this.activate(ch.id)
  }

  /** 切换当前文稿：先落库上一篇，避免切走丢稿 */
  async activate(id: string): Promise<void> {
    if (this.activeId === id) {
      return
    }
    await this.flushActive()
    this.activeId = id
    for (const d of this.openDocs) {
      d.active = d.id === id
    }
  }

  async close(id: string): Promise<void> {
    const idx: number = this.openDocs.findIndex((d: OpenDoc) => d.id === id)
    if (idx < 0) {
      return
    }
    await this.flushDoc(id)
    const wasActive: boolean = this.openDocs[idx].active
    const wasId: string = this.activeId
    this.openDocs.splice(idx, 1)
    if (this.openDocs.length === 0) {
      this.activeId = ''
      return
    }
    if (wasActive || wasId === id) {
      this.activeId = ''
      const next: OpenDoc = this.openDocs[Math.min(idx, this.openDocs.length - 1)]
      await this.activate(next.id)
    }
  }

  /** 关闭与某篇文稿相关的标签（文稿被删除时用） */
  async closeIfOpen(chapterId: string): Promise<void> {
    if (this.openDocs.some((d: OpenDoc) => d.id === chapterId)) {
      await this.close(chapterId)
    }
  }

  rename(id: string, title: string): void {
    const doc: OpenDoc | undefined = this.openDocs.find((d: OpenDoc) => d.id === id)
    if (doc !== undefined) {
      doc.title = title
    }
  }

  reorder(fromId: string, toId: string): void {
    const from: number = this.openDocs.findIndex((d: OpenDoc) => d.id === fromId)
    const to: number = this.openDocs.findIndex((d: OpenDoc) => d.id === toId)
    if (from < 0 || to < 0 || from === to) {
      return
    }
    const moved: OpenDoc = this.openDocs[from]
    this.openDocs.splice(from, 1)
    this.openDocs.splice(to, 0, moved)
  }

  // ===== 编辑 =====

  /** One editor transaction, including format offsets shifted by typing. */
  setEditorState(text: string, runsJson: string, caret: number): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc === undefined) { return }
    if (doc.draft === text && doc.runsJson === runsJson) { doc.caret = caret; return }
    this.remember(doc)
    doc.draft = text
    doc.runsJson = runsJson
    doc.caret = caret
    doc.dirty = true
    this.scheduleFlush()
    this.saveState = SaveState.IDLE
    this.saveHint = '编辑中…'
  }

  /** 编辑器上报正文变化 */
  setContent(text: string): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc === undefined || doc.draft === text) {
      return
    }
    this.remember(doc)
    doc.draft = text
    doc.dirty = true
    this.scheduleFlush()
    this.saveState = SaveState.IDLE
    this.saveHint = '编辑中…'
  }

  /** 编辑器上报光标变化 */
  setCaret(offset: number): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc !== undefined) {
      doc.caret = offset
    }
  }

  /** 编辑器上报格式变化（T024）：作为一步可撤销编辑 */
  setFormatRuns(json: string): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc === undefined || doc.runsJson === json) {
      return
    }
    this.remember(doc)
    doc.runsJson = json
    doc.dirty = true
    this.scheduleFlush()
    this.saveState = SaveState.IDLE
    this.saveHint = '编辑中…'
  }

  /**
   * 程序化整体替换正文（一键排版 / 查找替换等编辑器无关操作）。
   * 作为**一步可撤销编辑**：先记录当前状态，再替换正文并自增 contentRev，
   * 通知编辑器回灌（原生 RichEditor 与自绘 FlowText 都监听 contentRev）。
   */
  applyExternalContent(text: string): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc === undefined || doc.draft === text) {
      return
    }
    this.remember(doc)
    this.restoring = true
    doc.draft = text
    doc.runsJson = ''
    doc.dirty = true
    this.restoring = false
    this.contentRev++
    this.scheduleFlush()
    this.saveState = SaveState.IDLE
    this.saveHint = '编辑中…'
  }

  private remember(doc: OpenDoc): void {
    if (this.restoring) {
      return
    }
    const now: number = Date.now()
    if (this.undoStack.length === 0 || this.undoStack[this.undoStack.length - 1].docId !== doc.id ||
      now - this.lastHistoryAt > HISTORY_MERGE_MS) {
      this.undoStack.push(new HistoryEntry(doc.id, doc.draft, doc.caret, doc.runsJson))
      if (this.undoStack.length > MAX_HISTORY) {
        this.undoStack.shift()
      }
      this.lastHistoryAt = now
    }
    this.redoStack = this.redoStack.filter((entry: HistoryEntry): boolean => entry.docId !== doc.id)
  }

  undo(): void {
    this.stepHistory(this.undoStack, this.redoStack)
  }

  redo(): void {
    this.stepHistory(this.redoStack, this.undoStack)
  }

  private stepHistory(from: HistoryEntry[], to: HistoryEntry[]): void {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc === undefined) {
      return
    }
    // 历史是跨文稿共享的，只取属于当前文稿的条目
    let index: number = from.length - 1
    while (index >= 0 && from[index].docId !== doc.id) { index-- }
    if (index < 0) { return }
    const entry: HistoryEntry = from.splice(index, 1)[0]
    to.push(new HistoryEntry(doc.id, doc.draft, doc.caret, doc.runsJson))
    this.restoring = true
    doc.draft = entry.text
    doc.caret = entry.caret
    doc.runsJson = entry.runsJson
    doc.dirty = true
    this.restoring = false
    // 通知编辑器把画布正文回退到新 draft（否则界面与数据会不一致）
    this.contentRev++
    this.scheduleFlush()
  }

  // ===== 保存 =====

  private scheduleFlush(): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer)
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1
      this.flushActive()
    }, SAVE_DEBOUNCE_MS)
  }

  startTimers(): void {
    if (this.safetyTimer !== -1) {
      return
    }
    this.safetyTimer = setInterval(() => {
      this.flushAll()
    }, SAVE_SAFETY_MS)
  }

  stopTimers(): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = -1
    }
    if (this.safetyTimer !== -1) {
      clearInterval(this.safetyTimer)
      this.safetyTimer = -1
    }
  }

  /**
   * 落库单篇。正文为空也照常写入 —— 用户清空一篇文稿必须是可保存的意图，
   * 而不是被静默忽略。
   */
  async flushDoc(id: string): Promise<void> {
    const doc: OpenDoc | undefined = this.openDocs.find((d: OpenDoc) => d.id === id)
    if (doc === undefined || !doc.dirty) {
      return
    }
    // 超出单篇入库上限：这是"请拆分成多篇"的操作问题，不是存储故障。
    // 提前拦下并给出可执行提示，避免用户在界面上反复点"重试"却永远失败。
    if (exceedsContentLimit(doc.draft)) {
      const bytes: number = utf8ByteLength(doc.draft)
      Logger.error('Save aborted, content too large [' + id + ']: ' + bytes + ' bytes')
      this.saveState = SaveState.TOO_LARGE
      this.saveHint = contentLimitMessage()
      return
    }
    this.saveState = SaveState.SAVING
    try {
      await chapterRepo.updateContent(id, doc.draft)
      await chapterRepo.updateCaretOffset(id, doc.caret)
      await chapterRepo.updateFormatRuns(id, doc.runsJson)
      doc.dirty = false
      this.saveState = SaveState.IDLE
      this.saveHint = '已保存'
    } catch (e) {
      Logger.error('Save chapter failed [' + id + ']: ' + String(e))
      this.saveState = SaveState.FAILED
      this.saveHint = '保存失败，点击重试'
      throw new Error(String(e))
    }
  }

  async flushActive(): Promise<void> {
    const doc: OpenDoc | undefined = this.activeDoc
    if (doc !== undefined) {
      await this.flushDoc(doc.id)
    }
  }

  /** 全部落库：退后台、销毁、切项目、退出编辑页时调用 */
  async flushAll(): Promise<void> {
    const ids: string[] = this.openDocs.map((d: OpenDoc) => d.id)
    for (const id of ids) {
      try {
        await this.flushDoc(id)
      } catch (e) {
        Logger.error('flushAll: chapter ' + id + ' failed, continue')
      }
    }
  }

  retrySave(): void {
    if (this.saveState === SaveState.SAVING) {
      return
    }
    // 超长不是可重试的故障：重试必然再次失败，直接忽略避免无谓写库尝试
    if (this.saveState === SaveState.TOO_LARGE) {
      return
    }
    this.flushAll()
  }

  /** 文稿被删除/移出当前项目时，丢弃其内存草稿与历史，避免复活已删数据 */
  discard(id: string): void {
    this.undoStack = this.undoStack.filter((e: HistoryEntry) => e.docId !== id)
    this.redoStack = this.redoStack.filter((e: HistoryEntry) => e.docId !== id)
  }

  reset(): void {
    this.openDocs = []
    this.activeId = ''
    this.undoStack = []
    this.redoStack = []
    this.contentRev++
  }
}
