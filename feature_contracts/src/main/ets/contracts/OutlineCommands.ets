// 导图 → 正文的结构命令（ADR-002 §2.5；M2 起使用）
//
// 为什么用命令对象而不是回调函数：结构包（HSP）只能通过 core_runtime 跟宿主说话，
// 命令是纯数据、可序列化、可测试；宿主负责翻译成 DocumentModel 的编辑并回写正文。
//
// 只带基本类型与稳定身份（paraId），不带正文、不带编辑器对象。

export enum OutlineCommandKind {
  /** 改标题文本（paraId 必须指向一个 H1–H3 段落） */
  RENAME = 0,
  /** 在当前节之后插入一个同级标题 */
  INSERT_SIBLING = 1,
  /** 在当前节末尾插入一个子级标题 */
  INSERT_CHILD = 2,
  /** 改段落级别（1–3） */
  SET_KIND = 3,
  /** 删除整节（标题 + 下属正文），由 UI 负责二次确认 */
  DELETE_SECTION = 4,
  /** 整节上移 / 下移 */
  MOVE_UP = 5,
  MOVE_DOWN = 6
}

export class OutlineCommand {
  kind: OutlineCommandKind = OutlineCommandKind.RENAME
  /** 目标节点（空串表示"根"，只有部分命令允许） */
  paraId: string = ''
  /** RENAME 的新标题；INSERT_* 的初始标题（空则用默认名） */
  text: string = ''
  /** SET_KIND 的目标级别（1–3） */
  level: number = 1

  constructor(kind: OutlineCommandKind = OutlineCommandKind.RENAME, paraId: string = '',
    text: string = '', level: number = 1) {
    this.kind = kind
    this.paraId = paraId
    this.text = text
    this.level = level
  }
}
