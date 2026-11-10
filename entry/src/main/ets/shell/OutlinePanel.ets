// 大纲面板（桌面优先）：列出标题，点一条跳回正文，可整节上移/下移
//
// 这是 P5 段落身份的第一个真实消费者：
//   - 上移/下移不是"换两行文字"，而是把**标题 + 下属整节**一起搬走（DocumentModel.moveSection）；
//   - 搬完的正文经 applyGeneratedContent 走统一编辑事务，段落 id 由 reconcile 保住，
//     所以将来锚点/引用不会因为调顺序而失效。
import { tokensFor, WeaverColorSet, WeaverRadii, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { app as appStores } from '../store/AppStores'
import { EditorStore } from '../store/EditorStore'
import { extractHeadings } from '../editor/OutlineExtract'
import type { OutlineHeading } from 'feature_contracts'
import {
  createDocument, paragraphSpans, project, moveSectionUp, moveSectionDown
} from '../editor/model/DocumentModel'
import type { DocModel, ParaSpan, Projection } from '../editor/model/DocumentModel'
import { Logger } from '../utils/Logger'

/** 面板里的一行（标题 + 位置 + 是否可移动） */
class OutlineRow {
  title: string = ''
  level: number = 1
  startOffset: number = 0
  canUp: boolean = false
  canDown: boolean = false
}

@ComponentV2
export struct OutlinePanel {
  @Param app: AppStores | null = null
  /** 原生窗口三键区宽度：头部右侧要避开，否则「关闭」会被压住 */
  @Param captionInset: number = 0
  @Event onClose: () => void = () => {}

  @Local rows: OutlineRow[] = []
  /** 正文版本变化（撤销/重做/外部替换）时刷新列表 */
  @Local editorWatch: EditorStore = appStores.editor

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  aboutToAppear(): void {
    this.load()
  }

  @Monitor('editorWatch.contentRev')
  onContentRevChanged(): void {
    this.load()
  }

  private load(): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      this.rows = []
      return
    }
    const headings: OutlineHeading[] = extractHeadings(stores.editor.content, stores.editor.runsJson)
    const next: OutlineRow[] = []
    for (let i: number = 0; i < headings.length; i++) {
      const row: OutlineRow = new OutlineRow()
      row.title = headings[i].title
      row.level = headings[i].level
      row.startOffset = headings[i].startOffset
      row.canUp = i > 0
      row.canDown = i < headings.length - 1
      next.push(row)
    }
    this.rows = next
  }

  /** 点标题：正文滚到该处并把光标放过去 */
  private jumpTo(offset: number): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const controller = stores.ui.editorController
    if (controller !== null) {
      controller.revealOffset(offset)
      controller.focus()
    }
  }

  /**
   * 整节上移/下移。
   * 用当前正文重建模型（段落 id 由 createDocument 生成，与库里侧车通过 reconcile 对齐），
   * 移动后投影回 text + runs，交给统一编辑事务落库。
   */
  private move(index: number, up: boolean): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return
    }
    if (index < 0 || index >= this.rows.length) {
      return
    }
    const docId: string = stores.editor.activeId
    const model: DocModel = createDocument(docId, stores.editor.title,
      stores.editor.content, stores.editor.runsJson)
    const spans: ParaSpan[] = paragraphSpans(model)
    const headingStart: number = this.rows[index].startOffset
    let paraIndex: number = -1
    for (let i: number = 0; i < spans.length; i++) {
      if (spans[i].start === headingStart) {
        paraIndex = i
        break
      }
    }
    if (paraIndex < 0) {
      this.toast('找不到这一节（正文可能刚被修改）')
      return
    }
    const moved: boolean = up ? moveSectionUp(model, paraIndex) : moveSectionDown(model, paraIndex)
    if (!moved) {
      this.toast(up ? '已经是第一节' : '已经是最后一节')
      return
    }
    const projection: Projection = project(model)
    if (!stores.editor.applyGeneratedContent(docId, projection.text, projection.runsJson)) {
      this.toast('调整失败：文稿未打开')
      return
    }
    stores.editor.flushDoc(docId).catch((e: Error) => {
      Logger.warn('OutlinePanel: flush failed: ' + String(e))
    })
    this.load()
    this.toast(up ? '已上移一节' : '已下移一节')
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message })
    } catch (e) {
      Logger.warn('OutlinePanel: toast failed: ' + String(e))
    }
  }

  @Builder
  rowView(row: OutlineRow, index: number) {
    Column() {
      Row() {
        Text(row.title)
          .fontSize(row.level === 1 ? 13 : 12)
          .fontColor(this.colors().textPrimary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('↑')
          .fontSize(12)
          .fontColor(row.canUp ? this.colors().textSecondary : this.colors().divider)
          .width(28).height(28).textAlign(TextAlign.Center)
          .accessibilityText('上移这一节')
          .onClick(() => { if (row.canUp) { this.move(index, true) } })
        Text('↓')
          .fontSize(12)
          .fontColor(row.canDown ? this.colors().textSecondary : this.colors().divider)
          .width(28).height(28).textAlign(TextAlign.Center)
          .accessibilityText('下移这一节')
          .onClick(() => { if (row.canDown) { this.move(index, false) } })
      }
      .width('100%')
      .padding({ left: 6 + (row.level - 1) * 12, right: 4, top: 4, bottom: 4 })
      .alignItems(VerticalAlign.Center)
      .borderRadius(WeaverRadii.XS)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => { this.jumpTo(row.startOffset) })
    }
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('大纲').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.colors().textPrimary)
        Blank()
        Text('关闭')
          .fontSize(12).fontColor(this.colors().textSecondary)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => { this.onClose() })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 8 + this.captionInset })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: this.colors().divider })

      if (this.rows.length === 0) {
        Column() {
          Text('还没有标题').fontSize(12).fontColor(this.colors().textTertiary)
          Text('在正文里把几句设成 H1–H3，就会出现在这里')
            .fontSize(11).fontColor(this.colors().textTertiary).margin({ top: 6 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rows, (row: OutlineRow, index: number) => {
            ListItem() {
              this.rowView(row, index)
            }
          }, (row: OutlineRow, index: number) => row.startOffset.toString() + ':' + index.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width(280)
    .height('100%')
    .backgroundColor(this.colors().bgCard)
    .border({ width: { left: 1 }, color: this.colors().divider })
  }
}
