// 状态层可观察模型（状态管理 V2）
//
// 为什么必须是 @ObservedV2 类而不是普通 interface：
// V1 的 @State/@ObjectLink 只能观察「第一层属性」，所以旧代码里到处是
// `this.editorTabs = this.editorTabs.map(t => ({...t, dirty: true}))` 这种
// 手工整体替换来骗过刷新。V2 的 @ObservedV2 + @Trace 把观察能力放在数据本身，
// 逐字段赋值即可驱动 UI，列表项也能就地更新而不必重建数组。
import { ChapterFormat } from '../model/Chapter'

/** 文稿列表项（就绪于 LazyForEach/Repeat 的稳定身份，改动就地更新） */
@ObservedV2
export class DocItem {
  readonly id: string = ''
  @Trace title: string = ''
  @Trace subTitle: string = ''
  @Trace coverColor: string = '#007DFF'
  @Trace badge: string = ''
  @Trace modified: string = ''
  @Trace wordCount: number = 0
  @Trace isTrash: boolean = false
  @Trace expireDays: number = 0
  @Trace isFav: boolean = false
  @Trace isInspiration: boolean = false
  @Trace format: ChapterFormat = ChapterFormat.TXT
  /** 是否为当前打开文稿（放在项上而不是由父组件计算，选中态变化才不会让整列重渲染） */
  @Trace selected: boolean = false

  constructor(id: string) {
    this.id = id
  }
}

/** 打开中的文稿（编辑标签页） */
@ObservedV2
export class OpenDoc {
  readonly id: string = ''
  readonly format: ChapterFormat = ChapterFormat.TXT
  @Trace title: string = ''
  @Trace color: string = '#007DFF'
  @Trace active: boolean = false
  /** 内存中的正文草稿，可能与库中不一致 */
  @Trace draft: string = ''
  @Trace caret: number = 0
  /** 有未落库的改动 */
  @Trace dirty: boolean = false
  /** 行内/段落格式标注的序列化边车（T024/T025） */
  @Trace runsJson: string = ''

  constructor(id: string, title: string, format: ChapterFormat, color: string,
    draft: string, caret: number, runsJson: string = '') {
    this.id = id;
    this.title = title;
    this.format = format;
    this.color = color;
    this.draft = draft;
    this.caret = caret;
    this.runsJson = runsJson;
  }
}

/** 项目（书籍）列表项 */
@ObservedV2
export class ProjectItem {
  readonly id: string = ''
  @Trace name: string = ''
  @Trace color: string = '#007DFF'
  @Trace docCount: number = 0
  @Trace active: boolean = false

  constructor(id: string) {
    this.id = id
  }
}

/** 保存状态 */
export enum SaveState {
  IDLE = 0,
  SAVING = 1,
  FAILED = 2,
  /** 正文超出单篇入库上限：需用户拆篇，重试无意义 */
  TOO_LARGE = 3
}

/** 撤销/重做条目：记录某篇文稿的一个历史快照 */
export class HistoryEntry {
  readonly docId: string
  readonly text: string
  readonly caret: number
  readonly runsJson: string

  constructor(docId: string, text: string, caret: number, runsJson: string = '') {
    this.docId = docId;
    this.text = text;
    this.caret = caret;
    this.runsJson = runsJson;
  }
}
