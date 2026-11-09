// 思路板 · 素材抽屉（右侧浮层；窄屏全屏）
//
// 规格来源：AI 施工单 §6.5、契约 §2/§3/§5。
// - 宽屏 392vp 浮层，窄屏（BreakPoint.SM）全屏；Esc / ✕ 关闭。
// - 结构：标题 + 别名 + 标签 + 我的一句话 + 素材分组（引文/判断/笔记）+ 添加素材，
//   底部「从父卡移出」「删除卡片」；头部另有「从这块白板移除」。移除 ≠ 删除：移出只改当前白板的贴放。
// - 只读数据走 CanvasStore 的同步查询（cardOf / evidenceOf / occurrences / depthOf 类的纯函数），
//   写动作全部 fireAndLog 收敛，不让异常冒到 UI 线程。
import {
  CanvasCardData, CanvasEvidenceData, CanvasEvidenceKind, CanvasCardKind, canvasDepthOf
} from '../model/CanvasTypes'
import { CanvasSpec } from '../constants/CanvasSpec'
import { DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { app, fireAndLog } from '../store/AppStores'
import { ensureWorkspace } from './Navigator'
import { closeCanvasAnimated } from './CanvasTransition'
import type { CanvasCardPatch } from '../model/CanvasStoreModels'
import {
  canvasPalette, CanvasPalette, CanvasLayout, canvasDepthLabel, canvasEvidenceLabel
} from './CanvasTheme'
import { SourceAnchorResolver, AnchorState } from '../utils/SourceAnchor'
import type { AnchorResolution } from '../utils/SourceAnchor'
import type { CanvasTextEditorController } from '../editor/flowtext/CanvasTextEditor'

const DRAWER_KEY_ESCAPE: number = 2070

@ComponentV2
export struct EvidenceDrawer {
  @Require @Param cardId: string
  /** 窄屏（手机竖屏）时全屏铺满 */
  @Param narrow: boolean = false
  @Param themeId: string = DEFAULT_THEME_ID
  /** 2in1 原生三键占位：头部 ✕ 必须让开，否则被系统关闭按钮盖住 */
  @Param captionInset: number = 0
  @Event onClose: () => void = () => {}

  /** 添加素材表单 */
  @Local adding: boolean = false
  @Local draftText: string = ''
  @Local draftKind: CanvasEvidenceKind = CanvasEvidenceKind.NOTE
  @Local confirmDelete: boolean = false
  /** 卡片元信息编辑草稿（失焦/提交时保存） */
  @Local titleDraft: string = ''
  @Local aliasDraft: string = ''
  @Local tagsDraft: string = ''
  @Local summaryDraft: string = ''
  @Local saveState: string = ''
  /** 素材就地编辑 */
  @Local editingEvidenceId: string = ''
  @Local editingText: string = ''

  aboutToAppear(): void {
    // 不要主动 requestFocus：祖先容器默认不可获焦，会抛 150002；Esc 交给 defaultFocus。
    this.syncDrafts()
  }

  @Monitor('cardId')
  onCardChanged(): void {
    this.adding = false
    this.draftText = ''
    this.draftKind = CanvasEvidenceKind.NOTE
    this.confirmDelete = false
    this.editingEvidenceId = ''
    this.editingText = ''
    this.syncDrafts()
  }

  private syncDrafts(): void {
    const c: CanvasCardData | undefined = this.card()
    if (c === undefined) {
      return
    }
    this.titleDraft = c.title
    this.aliasDraft = c.aliases
    this.tagsDraft = c.tags
    this.summaryDraft = c.summary
    this.saveState = ''
  }

  private sharedText(): string {
    const n: number = app.canvas.occurrences(this.cardId).length
    return n > 1 ? '此卡在 ' + n.toString() + ' 块白板使用，修改会同步' : ''
  }

  /** 保存元信息；标题为空时回退，不写库。 */
  private saveCard(): void {
    const title: string = this.titleDraft.trim()
    if (title === '') {
      this.titleDraft = this.cardTitle()
      this.saveState = '标题不能为空'
      return
    }
    const c: CanvasCardData | undefined = this.card()
    if (c === undefined) {
      return
    }
    const nextAliases: string = this.aliasDraft.trim()
    const nextTags: string = this.tagsDraft.trim()
    const nextSummary: string = this.summaryDraft.trim()
    if (c.title === title && c.aliases === nextAliases &&
      c.tags === nextTags && c.summary === nextSummary) {
      this.saveState = ''
      return
    }
    const patch: CanvasCardPatch = {
      title: title,
      aliases: nextAliases,
      tags: nextTags,
      summary: nextSummary
    }
    this.saveState = '保存中…'
    app.canvas.updateCard(this.cardId, patch).then((ok: boolean) => {
      this.saveState = ok ? '已保存' : '保存失败，重试'
    })
  }

  private startEdit(ev: CanvasEvidenceData): void {
    this.editingEvidenceId = ev.id
    this.editingText = ev.kind === CanvasEvidenceKind.QUOTE ? ev.quoteText : ev.userText
  }

  private cancelEdit(): void {
    this.editingEvidenceId = ''
    this.editingText = ''
  }

  private saveEdit(ev: CanvasEvidenceData): void {
    const text: string = this.editingText.trim()
    if (text === '') {
      return
    }
    const isQuote: boolean = ev.kind === CanvasEvidenceKind.QUOTE
    app.canvas.updateEvidenceText(ev.id, isQuote ? text : ev.quoteText,
      isQuote ? ev.userText : text).then((ok: boolean) => {
      if (ok) {
        this.editingEvidenceId = ''
        this.editingText = ''
      }
    })
  }

  private pal(): CanvasPalette {
    return canvasPalette(this.themeId)
  }

  private card(): CanvasCardData | undefined {
    return app.canvas.cardOf(this.cardId)
  }

  private cardTitle(): string {
    const c: CanvasCardData | undefined = this.card()
    return c === undefined ? '卡片已被删除' : c.title
  }

  private isWriting(): boolean {
    const c: CanvasCardData | undefined = this.card()
    return c !== undefined && c.kind === CanvasCardKind.WRITING
  }

  private depthValue(): number {
    return canvasDepthOf(app.canvas.placements, this.cardId)
  }

  private whereText(): string {
    const where: string[] = app.canvas.occurrences(this.cardId)
    const head: string = where.length === 0
      ? '还没有放到任何白板'
      : '出现在：' + where.join(' / ')
    return head + ' · 内容由所有白板共享 · 当前：' + canvasDepthLabel(this.depthValue())
  }

  private evidenceOfKind(kind: CanvasEvidenceKind): CanvasEvidenceData[] {
    const all: CanvasEvidenceData[] = app.canvas.evidenceOf(this.cardId)
    const out: CanvasEvidenceData[] = []
    for (let i: number = 0; i < all.length; i++) {
      if (all[i].kind === kind) {
        out.push(all[i])
      }
    }
    return out
  }

  private groupedCount(kind: CanvasEvidenceKind): number {
    return this.evidenceOfKind(kind).length
  }

  private evidenceKey(ev: CanvasEvidenceData): string {
    return ev.id
  }

  private sourceLine(ev: CanvasEvidenceData): string {
    if (ev.sourceLabel !== '') {
      return ev.sourceLabel
    }
    if (ev.docId !== '') {
      return '第 ' + (ev.paraIndex + 1).toString() + ' 段'
    }
    return ''
  }

  private canDetach(): boolean {
    return this.depthValue() > 0
  }

  private close(): void {
    // 关闭前把未失焦的字段落一次，避免“点了 ✕ 刚才的字没保存”
    this.saveCard()
    this.onClose()
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message })
  }

  /**
   * 跳回原文：同一文稿内用 controller.revealOffset 精确定位并滚进视口。
   * 跨文稿仍要求先打开（打开后再跳的链路留到 P3b）。
   */
  private jumpToSource(ev: CanvasEvidenceData): void {
    if (ev.kind !== CanvasEvidenceKind.QUOTE) {
      return
    }
    if (ev.docId === '') {
      this.toast('这条引文没有绑定原文')
      return
    }
    fireAndLog(this.jumpToSourceAsync(ev), 'EvidenceDrawer.jumpToSource')
  }

  /** 同文稿直接定位；跨文稿先打开、关画布，再等编辑器就绪后定位。 */
  private async jumpToSourceAsync(ev: CanvasEvidenceData): Promise<void> {
    try {
      if (app.editor.activeId !== ev.docId) {
        await app.openChapter(ev.docId)
        ensureWorkspace()
        closeCanvasAnimated(this.getUIContext())
        // 不用固定延时猜"编辑器好了没"：轮询真实条件（控制器已绑定且文稿匹配），
        // 有上限，超时明确提示而不是盲跳（交接稿 R3 的另一半问题）。
        this.applyAnchorWhenReady(ev, 0)
        return
      }
      // 同文稿也要先收起画布，否则用户仍停在全窗口画布上
      ensureWorkspace()
      closeCanvasAnimated(this.getUIContext())
      this.applyAnchorWhenReady(ev, 0)
    } catch (e) {
      this.toast('原文已不存在或无法打开')
    }
  }

  /** 等编辑器挂载（最多约 2 秒）后再核验锚点并定位 */
  private applyAnchorWhenReady(ev: CanvasEvidenceData, attempt: number): void {
    const ctl: CanvasTextEditorController | null = app.ui.editorController
    if (ctl !== null && app.editor.activeId === ev.docId) {
      this.applyAnchor(ctl, ev)
      return
    }
    if (attempt >= 40) {
      this.toast('编辑器未就绪，请稍后在正文里手动查找这段文字')
      return
    }
    setTimeout(() => {
      this.applyAnchorWhenReady(ev, attempt + 1)
    }, 50)
  }

  /**
   * 核验来源锚后定位：原文改过就按摘录重新找，找不到就明说，绝不"假装还准"。
   * 命中时把摘录区间选中，用户能一眼确认对应的是哪一段。
   */
  private applyAnchor(ctl: CanvasTextEditorController, ev: CanvasEvidenceData): void {
    const res: AnchorResolution = SourceAnchorResolver.resolve(
      ctl.getText(), ev.startOff, ev.endOff, ev.quoteText, ev.fingerprint)
    if (res.state === AnchorState.MISSING) {
      this.toast(res.message)
      return
    }
    ctl.selectRange(res.start, res.end)
    ctl.revealOffset(res.start)
    ctl.focus()
    if (res.message !== '') {
      this.toast(res.message)
    }
  }

  private submitEvidence(): void {
    const text: string = this.draftText.trim()
    if (text === '') {
      return
    }
    const isQuote: boolean = this.draftKind === CanvasEvidenceKind.QUOTE
    fireAndLog(app.canvas.addEvidence(this.cardId, this.draftKind, {
      docId: '',
      paraIndex: -1,
      startOff: -1,
      endOff: -1,
      fingerprint: '',
      quoteText: isQuote ? text : '',
      userText: isQuote ? '' : text,
      sourceLabel: ''
    }), 'EvidenceDrawer.addEvidence')
    this.draftText = ''
    this.adding = false
  }

  private detach(): void {
    if (!this.canDetach()) {
      return
    }
    fireAndLog(app.canvas.detachCard(this.cardId), 'EvidenceDrawer.detachCard')
    this.toast('已从父卡移出，成为画布上的独立卡片')
    this.close()
  }

  private onBoard(): boolean {
    for (let i: number = 0; i < app.canvas.placements.length; i++) {
      if (app.canvas.placements[i].cardId === this.cardId) {
        return true
      }
    }
    return false
  }

  /** 只删当前白板的贴放：卡片仍在卡片库与其他白板（规格 §2.4）。 */
  private removeFromBoard(): void {
    fireAndLog(app.canvas.removePlacement(this.cardId), 'EvidenceDrawer.removePlacement')
    this.toast('已从这块白板移除；卡片仍在卡片库与其他白板')
    this.close()
  }

  private removeCard(): void {
    if (!this.confirmDelete) {
      this.confirmDelete = true
      return
    }
    fireAndLog(app.canvas.deleteCard(this.cardId), 'EvidenceDrawer.deleteCard')
    this.confirmDelete = false
    this.close()
  }

  @Builder
  kindChip(kind: CanvasEvidenceKind, label: string) {
    Text(label)
      .fontSize(11.5)
      .fontColor(this.draftKind === kind ? this.pal().onBrand : this.pal().textSecondary)
      .backgroundColor(this.draftKind === kind ? this.pal().textPrimary : this.pal().chipBg)
      .borderRadius(99)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .margin({ right: 6 })
      .onClick(() => {
        this.draftKind = kind
      })
  }

  @Builder
  evidenceRow(ev: CanvasEvidenceData) {
    Row() {
      Text(canvasEvidenceLabel(ev.kind))
        .fontSize(10.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.kindTextColor(ev.kind))
        .backgroundColor(this.kindBgColor(ev.kind))
        .borderRadius(5)
        .border({ width: 1, color: this.kindLineColor(ev.kind) })
        .padding({ left: 7, right: 7, top: 1, bottom: 1 })
      Column() {
        if (this.editingEvidenceId === ev.id) {
          Column() {
            TextArea({ text: this.editingText })
              .accessibilityText('编辑素材')
              .onChange((value: string) => {
                this.editingText = value
              })
              .fontSize(13.3)
              .lineHeight(21)
              .height(88)
              .backgroundColor(this.pal().activeBg)
              .borderRadius(8)
              .padding(8)
              .width('100%')
            Row() {
              Blank()
              Text('取消')
                .fontSize(11.5)
                .fontColor(this.pal().textTertiary)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .onClick(() => {
                  this.cancelEdit()
                })
              Text('保存')
                .fontSize(11.5)
                .fontColor(this.pal().onBrand)
                .backgroundColor(this.pal().textPrimary)
                .borderRadius(7)
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .margin({ left: 6 })
                .onClick(() => {
                  this.saveEdit(ev)
                })
            }
            .width('100%')
            .margin({ top: 6 })
          }
          .width('100%')
        } else {
          Text(ev.kind === CanvasEvidenceKind.QUOTE ? ev.quoteText : ev.userText)
            .fontSize(13.3)
            .lineHeight(21)
            .fontColor(this.pal().textPrimary)
            .width('100%')
        }
        Row() {
          if (this.sourceLine(ev) !== '') {
            Text(this.sourceLine(ev))
              .fontSize(11.3)
              .fontColor(this.pal().textTertiary)
          }
          if (ev.kind === CanvasEvidenceKind.QUOTE) {
            Text('跳回原文')
              .fontSize(11.3)
              .fontColor(this.pal().textPrimary)
              .decoration({ type: TextDecorationType.Underline, color: this.pal().textTertiary })
              .margin({ left: 10 })
              .onClick(() => {
                this.jumpToSource(ev)
              })
              .accessibilityText('跳回原文')
          }
          Blank()
          Text('编辑')
            .fontSize(11)
            .fontColor(this.pal().textTertiary)
            .onClick(() => {
              this.startEdit(ev)
            })
          Text('删除')
            .fontSize(11)
            .fontColor(this.pal().textTertiary)
            .margin({ left: 10 })
            .onClick(() => {
              fireAndLog(app.canvas.deleteEvidence(ev.id), 'EvidenceDrawer.deleteEvidence')
            })
        }
        .width('100%')
        .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 9 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .border({ width: { bottom: 1 }, color: { bottom: this.pal().divider } })
  }

  private kindTextColor(kind: CanvasEvidenceKind): string {
    if (kind === CanvasEvidenceKind.QUOTE) {
      return this.pal().quoteText
    }
    if (kind === CanvasEvidenceKind.JUDGEMENT) {
      return this.pal().judgeText
    }
    return this.pal().noteText
  }

  private kindBgColor(kind: CanvasEvidenceKind): string {
    if (kind === CanvasEvidenceKind.QUOTE) {
      return this.pal().quoteBg
    }
    if (kind === CanvasEvidenceKind.JUDGEMENT) {
      return this.pal().judgeBg
    }
    return this.pal().noteBg
  }

  private kindLineColor(kind: CanvasEvidenceKind): string {
    if (kind === CanvasEvidenceKind.QUOTE) {
      return this.pal().quoteLine
    }
    if (kind === CanvasEvidenceKind.JUDGEMENT) {
      return this.pal().judgeLine
    }
    return this.pal().noteLine
  }

  @Builder
  groupHeader(label: string, count: number) {
    Row() {
      Text(label)
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal().textSecondary)
      Text(count.toString())
        .fontSize(11)
        .fontColor(this.pal().textTertiary)
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 6 })
  }

  @Builder
  addForm() {
    Column() {
      Row() {
        this.kindChip(CanvasEvidenceKind.QUOTE, '引文')
        this.kindChip(CanvasEvidenceKind.JUDGEMENT, '判断')
        this.kindChip(CanvasEvidenceKind.NOTE, '笔记')
      }
      .width('100%')
      .margin({ bottom: 8 })
      TextArea({ text: this.draftText, placeholder: '写点什么（判断/笔记可直接手写；引文请从原文摘取）' })
        .fontSize(13.3)
        .height(88)
        .width('100%')
        .backgroundColor(this.pal().chipBg)
        .borderRadius(9)
        .onChange((value: string) => {
          this.draftText = value
        })
      Row() {
        Blank()
        Text('取消')
          .fontSize(12.5)
          .fontColor(this.pal().textSecondary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick(() => {
            this.adding = false
            this.draftText = ''
          })
        Text('保存')
          .fontSize(12.5)
          .fontColor(this.pal().onBrand)
          .backgroundColor(this.pal().textPrimary)
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .margin({ left: 6 })
          .onClick(() => {
            this.submitEvidence()
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 10 })
  }

  build() {
    Row() {
      Column() {
        // ===== 头部 =====
        Column() {
          Row() {
            Column() {
              TextInput({ text: this.titleDraft, placeholder: '卡片标题' })
                .accessibilityText('卡片标题')
                .onChange((value: string) => {
                  this.titleDraft = value
                })
                .onSubmit(() => {
                  this.saveCard()
                })
                .onBlur(() => {
                  this.saveCard()
                })
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal().textPrimary)
                .backgroundColor(Color.Transparent)
                .padding(0)
                .width('100%')
              TextInput({ text: this.aliasDraft, placeholder: '别名（逗号分隔，可选）' })
                .accessibilityText('卡片别名')
                .onChange((value: string) => {
                  this.aliasDraft = value
                })
                .onSubmit(() => {
                  this.saveCard()
                })
                .onBlur(() => {
                  this.saveCard()
                })
                .fontSize(11.5)
                .fontColor(this.pal().textTertiary)
                .backgroundColor(Color.Transparent)
                .padding(0)
                .margin({ top: 2 })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text('✕')
              .fontSize(15)
              .fontColor(this.pal().textTertiary)
              .width(30)
              .height(30)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.close()
              })
              .accessibilityText('关闭素材抽屉')
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          TextInput({ text: this.tagsDraft, placeholder: '标签（逗号分隔，可选）' })
            .accessibilityText('卡片标签')
            .onChange((value: string) => {
              this.tagsDraft = value
            })
            .onSubmit(() => {
              this.saveCard()
            })
            .onBlur(() => {
              this.saveCard()
            })
            .fontSize(11.5)
            .fontColor(this.pal().textSecondary)
            .backgroundColor(this.pal().activeBg)
            .borderRadius(9)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .width('100%')
            .margin({ top: 8 })
          TextArea({ text: this.summaryDraft, placeholder: '一句话：这张卡到底在说什么' })
            .accessibilityText('卡片一句话')
            .onChange((value: string) => {
              this.summaryDraft = value
            })
            .onBlur(() => {
              this.saveCard()
            })
            .fontSize(12.8)
            .lineHeight(20)
            .fontColor(this.pal().textSecondary)
            .backgroundColor(this.pal().activeBg)
            .borderRadius(9)
            .padding(10)
            .height(64)
            .width('100%')
            .margin({ top: 8 })
          Row() {
            Text(this.sharedText())
              .fontSize(11)
              .fontColor(this.pal().textTertiary)
              .layoutWeight(1)
            Text(this.saveState)
              .fontSize(11)
              .fontColor(this.saveState === '保存失败，重试' || this.saveState === '标题不能为空'
                ? this.pal().danger : this.pal().textTertiary)
          }
          .width('100%')
          .margin({ top: 6 })
          Text(this.whereText())
            .fontSize(11.5)
            .fontColor(this.pal().textTertiary)
            .width('100%')
            .margin({ top: 9 })
          if (this.onBoard()) {
            Text('从这块白板移除')
              .fontSize(11.5)
              .fontColor(this.pal().danger)
              .decoration({ type: TextDecorationType.Underline, color: this.pal().danger })
              .margin({ top: 6 })
              .onClick(() => {
                this.removeFromBoard()
              })
              .accessibilityText('从这块白板移除')
          }
        }
        .width('100%')
        .padding({
          left: CanvasLayout.DRAWER_PAD,
          right: CanvasLayout.DRAWER_PAD + this.captionInset,
          top: CanvasLayout.DRAWER_PAD,
          bottom: 12
        })
        .border({ width: { bottom: 1 }, color: { bottom: this.pal().divider } })

        // ===== 素材分组 =====
        Scroll() {
          Column() {
            if (this.isWriting()) {
              Text('写作卡本身也可以有素材；章节是子卡，不是素材。')
                .fontSize(11.5)
                .fontColor(this.pal().textTertiary)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10 })
            }
            this.groupHeader('引文', this.groupedCount(CanvasEvidenceKind.QUOTE))
            ForEach(this.evidenceOfKind(CanvasEvidenceKind.QUOTE), (evQuote: CanvasEvidenceData) => {
              this.evidenceRow(evQuote)
            }, (evQuote: CanvasEvidenceData): string => this.evidenceKey(evQuote))
            this.groupHeader('判断', this.groupedCount(CanvasEvidenceKind.JUDGEMENT))
            ForEach(this.evidenceOfKind(CanvasEvidenceKind.JUDGEMENT), (evJudge: CanvasEvidenceData) => {
              this.evidenceRow(evJudge)
            }, (evJudge: CanvasEvidenceData): string => this.evidenceKey(evJudge))
            this.groupHeader('笔记', this.groupedCount(CanvasEvidenceKind.NOTE))
            ForEach(this.evidenceOfKind(CanvasEvidenceKind.NOTE), (evNote: CanvasEvidenceData) => {
              this.evidenceRow(evNote)
            }, (evNote: CanvasEvidenceData): string => this.evidenceKey(evNote))
            if (this.groupedCount(CanvasEvidenceKind.QUOTE) +
              this.groupedCount(CanvasEvidenceKind.JUDGEMENT) +
              this.groupedCount(CanvasEvidenceKind.NOTE) === 0) {
              Text('还没有素材。判断与笔记可以手写，引文从原文摘取。')
                .fontSize(12)
                .fontColor(this.pal().textTertiary)
                .width('100%')
                .padding({ left: 16, right: 16, top: 6, bottom: 14 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)

        // ===== 底部动作 =====
        Column() {
          if (this.adding) {
            this.addForm()
          }
          Row() {
            Text('＋ 添加素材')
              .fontSize(12.5)
              .fontColor(this.pal().onBrand)
              .backgroundColor(this.pal().textPrimary)
              .borderRadius(8)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .onClick(() => {
                this.adding = !this.adding
              })
            Text('从父卡移出')
              .fontSize(12.5)
              .fontColor(this.canDetach() ? this.pal().textPrimary : this.pal().textTertiary)
              .opacity(this.canDetach() ? 1 : 0.45)
              .enabled(this.canDetach())
              .borderRadius(8)
              .border({ width: 1, color: this.pal().divider })
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .margin({ left: 8 })
              .onClick(() => {
                this.detach()
              })
            Blank()
            Text(this.confirmDelete ? '确认删除？' : '删除卡片')
              .fontSize(12.5)
              .fontColor(this.pal().danger)
              .borderRadius(8)
              .border({ width: 1, color: this.pal().danger })
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .onClick(() => {
                this.removeCard()
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 12 })
        .border({ width: { top: 1 }, color: { top: this.pal().divider } })
      }
      .id('canvas-drawer-root')
      .padding({ bottom: this.narrow ? app.ui.keyboardHeight : 0 })
      .width(this.narrow ? '100%' : CanvasSpec.DRAWER_WIDTH)
      .height('100%')
      .backgroundColor(this.pal().cardBg)
      .shadow({ radius: 30, color: this.pal().divider, offsetX: -12, offsetY: 0 })
      .border({ width: { left: this.narrow ? 0 : 1 }, color: { left: this.pal().divider } })
      .focusable(true)
      .defaultFocus(true)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Down && event.keyCode === DRAWER_KEY_ESCAPE) {
          this.close()
          return true
        }
        return false
      })
      .accessibilityText('素材抽屉：' + this.cardTitle() + '，' + this.whereText())
      .accessibilityGroup(true)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
