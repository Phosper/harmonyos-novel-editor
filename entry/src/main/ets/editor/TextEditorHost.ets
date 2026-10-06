/**
 * 编辑宿主 —— 正文编辑面的唯一入口（薄接口层）
 *
 * 设计意图：应用层只依赖本组件的契约，不直接依赖具体编辑器实现。
 * 当前实现已替换为 FlowText 自绘编辑器（Canvas + IME Kit）；
 * 契约签名保持与原 TextArea 实现一致，调用方零改动。
 *
 * 契约（保持不可变）：
 *   输入  docId                 文稿标识；变化即视为"换了一篇"，需要重载正文与光标
 *   输入  contentRev            store 侧「整体替换正文」的版本号（撤销/重做会自增）。
 *                                 画布把正文当自己的内部状态，只靠 docId 变化收不到
 *                                 撤销信号，必须额外监听这个版本号才能把正文回退。
 *   输入  loadText(docId)       同步取回该文稿正文
 *   输入  loadCaret(docId)      同步取回该文稿上次光标位置
 *   输入  fontSize / lineHeight / textColor / bgColor / caretColor / placeholder
 *   输出  onTextChange(text)    正文变化（写入侧自行做落库防抖）
 *   输出  onCaretChange(offset) 光标位置变化
 *   输出  onRequestSave()       用户主动要求保存（失焦等）
 *   输出  onUndo() / onRedo()   物理键盘 Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y
 *                                （历史栈在 store，编辑器内不持有，故由宿主转接）
 *
 * 状态管理说明：本组件是 V1 `@Component`，因为 FlowText 是纯 V1 组件，
 * 而 V1 组件不能用装饰器接收 V2 的 @ObservedV2 实例。此边界只传基本类型与函数，
 * 故 V2 应用层可以安全地把它嵌套进去。
 */
import { Logger } from '../utils/Logger'
import { CanvasTextEditor, CanvasTextEditorController } from './flowtext/CanvasTextEditor'
import { ScrollPolicy, FormatRun } from './flowtext/model/EditorTypes'

@Component
export struct TextEditorHost {
  @Prop @Watch('onDocChanged') docId: string = ''
  @Prop @Watch('onContentRevChanged') contentRev: number = 0
  @Prop fontSize: number = 16
  @Prop lineHeight: number = 24
  @Prop textColor: string = '#182431'
  @Prop bgColor: string = '#FFFFFF'
  @Prop caretColor: string = '#007DFF'
  @Prop placeholder: string = '开始写作…'
  /** 打字机模式（默认关）：开启后当前段垂直居中跟随 */
  @Prop typewriter: boolean = false
  /** 滚动策略（打字机关时为 NORMAL） */
  @Prop scrollPolicy: ScrollPolicy = ScrollPolicy.NORMAL

  loadText: (docId: string) => string = () => ''
  loadCaret: (docId: string) => number = () => 0
  /** 取回该文稿的行内格式标注（Phase B 起使用） */
  loadFormat: (docId: string) => FormatRun[] = () => []
  onTextChange: (text: string) => void = () => {}
  onEdit: (text: string, runs: FormatRun[], caret: number) => void = () => {}
  onCaretChange: (offset: number) => void = () => {}
  /** 选区变化（Phase A 仅上抛，供工具栏态） */
  onSelectionChange: (start: number, end: number) => void = () => {}
  /** 格式变化（Phase B 落库） */
  onFormatChange: (runs: FormatRun[]) => void = () => {}
  /** 滚动状态：1 向下 / -1 向上 / 0 停止（沉浸显隐） */
  onScrollState: (state: number) => void = () => {}
  /** 选区"查找"请求（携带选中文本） */
  onRequestFind: (text: string) => void = () => {}
  /** 选区"分享"请求（携带选中文本） */
  onRequestShare: (text: string) => void = () => {}
  /** 控制器就绪回调：应用层据此触发格式命令（T026） */
  onControllerReady: (controller: CanvasTextEditorController) => void = () => {}
  onRequestSave: () => void = () => {}
  onUndo: () => void = () => {}
  onRedo: () => void = () => {}

  private flowController: CanvasTextEditorController = new CanvasTextEditorController()
  /** 已载入的文稿标识，用于区分「切换文稿」与「普通重渲染」 */
  private loadedDocId: string = ''
  /** 已消费到的 contentRev 版本号，避免同一版本被重复回灌 */
  private appliedRev: number = -1

  aboutToAppear(): void {
    this.appliedRev = this.contentRev
    this.onControllerReady(this.flowController)
    this.reload()
  }

  onDocChanged(): void {
    this.reload()
  }

  /**
   * store 侧整体替换了正文（撤销 / 重做）：把 draft 与光标回灌到画布。
   * 回灌不抢焦点，也不重置滚动之外的状态。
   */
  onContentRevChanged(): void {
    if (this.contentRev === this.appliedRev) {
      return
    }
    this.appliedRev = this.contentRev
    if (this.docId === '') {
      return
    }
    const text: string = this.loadText(this.docId)
    const caret: number = this.loadCaret(this.docId)
    const runs: FormatRun[] = this.loadFormat(this.docId)
    // 先回灌格式：撤销/重做可能只改了格式（正文未变），此时也要对齐
    // 画布内容已与 store 一致时无需重载（重载会打断当前动画与滚动位置）
    if (this.flowController.getText() === text) {
      this.flowController.setRuns(runs)
      this.flowController.setCaretPosition(caret)
      return
    }
    this.flowController.setDocument(text, runs, caret)
    Logger.info('TextEditorHost: rev sync doc=' + this.docId + ' chars=' + text.length)
  }

  private reload(): void {
    if (this.docId === '' || this.docId === this.loadedDocId) {
      return
    }
    this.loadedDocId = this.docId
    // 换文稿视为一次新的载入基线，把版本号对齐到当前值
    this.appliedRev = this.contentRev
    const text: string = this.loadText(this.docId)
    const caret: number = this.loadCaret(this.docId)
    this.flowController.setDocument(text, this.loadFormat(this.docId), caret)
    this.flowController.focus()
    Logger.info('TextEditorHost: loaded doc=' + this.docId + ' chars=' + text.length)
  }

  aboutToDisappear(): void {
    this.flowController.blur()
  }

  build() {
    // 根节点用容器组件包住 CanvasTextEditor：这样调用方挂在本组件上的 layoutWeight
    // 作用在一个语义明确的容器上，CanvasTextEditor 自身再用 layoutWeight 填满容器，
    // 避免"外部 layoutWeight + 内部 height('100%')"两套尺寸规则互相打架。
    Column() {
      CanvasTextEditor({
        fontSize: this.fontSize,
        lineHeight: this.lineHeight,
        lineSpacing: 4,
        textColor: this.textColor,
        bgColor: this.bgColor,
        caretColor: this.caretColor,
        placeholder: this.placeholder,
        typewriter: this.typewriter,
        scrollPolicy: this.scrollPolicy,
        controller: this.flowController,
        onEdit: (text: string, runs: FormatRun[], caret: number) => {
          this.onEdit(text, runs, caret)
        },
        onTextChange: (text: string, version: number) => {
          // 用户输入。注意：普通输入不会让 contentRev 递增（只有撤销/重做才递增），
          // 而 setText 载入也不会回调 onTextChange，因此这里不存在"回灌—上报"回环，
          // 不需要额外的抑制标志。
          this.onTextChange(text)
        },
        onCaretChange: (offset: number) => {
          this.onCaretChange(offset)
        },
        onSelectionChange: (start: number, end: number) => {
          this.onSelectionChange(start, end)
        },
        onFormatChange: (runs: FormatRun[]) => {
          this.onFormatChange(runs)
        },
        onScrollState: (state: number) => {
          this.onScrollState(state)
        },
        onRequestSave: () => {
          this.onRequestSave()
        },
        onRequestFind: (text: string) => {
          this.onRequestFind(text)
        },
        onRequestShare: (text: string) => {
          this.onRequestShare(text)
        },
        onUndo: () => {
          this.onUndo()
        },
        onRedo: () => {
          this.onRedo()
        }
      })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor(this.bgColor)
  }
}
