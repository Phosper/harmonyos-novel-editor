// PcAgentPanel.ets V2 — with press/hover/focus + dual-mode colors
import { PcRadii, PcInteraction, pcColors, type AgentMessage, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'

@Component
export struct PcAgentPanel {
  @StorageLink('colorMode') colorMode: number = 1

  @State inputText: string = ''
  @State show: boolean = false
  @State messages: AgentMessage[] = []

  // Hover tracking
  @State hoveredBtnId: string = ''

  onClose: () => void = (): void => { }
  onSend: (text: string) => void = (text: string): void => { text }

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  quickAction(text: string): void {
    const updated: AgentMessage[] = []
    for (let i: number = 0; i < this.messages.length; i++) { updated.push(this.messages[i]) }
    updated.push({ role: 'user', text: text })
    updated.push({ role: 'ai', text: 'AI 功能开发中，敬请期待' })
    this.messages = updated
  }

  sendMessage(): void {
    if (this.inputText.trim() === '') return
    const updated: AgentMessage[] = []
    for (let i: number = 0; i < this.messages.length; i++) { updated.push(this.messages[i]) }
    updated.push({ role: 'user', text: this.inputText })
    updated.push({ role: 'ai', text: 'AI 功能开发中，敬请期待' })
    this.messages = updated
    this.onSend(this.inputText)
    this.inputText = ''
  }

  build() {
    Column() {
      Row() {
        Row({ space: 8 }) {
          Circle({ width: 8, height: 8 }).fill(this.getColors().EMPHASIZE)
          Text('写作伴侣').fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.getColors().TEXT_PRIMARY)
        }.alignItems(VerticalAlign.Center)
        Button() { Text('✕').fontSize(16).fontColor(this.getColors().TEXT_TERTIARY).accessibilityText('关闭写作伴侣') }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(Color.Transparent) }
        })
        .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'close' : '' })
        .backgroundColor(this.hoveredBtnId === 'close' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .focusable(true)
        
        .onClick(() => { this.onClose() })
      }
      .width('100%').height(48).padding({ left: 16, right: 16 }).justifyContent(FlexAlign.SpaceBetween)
      .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })

      Text('有什么可以帮你的？').fontSize(13).fontColor(this.getColors().TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 4 })

      Column({ space: 6 }) {
        Button('📍 上次写到哪了').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(this.getColors().BG_SECONDARY)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
          })
          .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'qa1' : '' })
          .backgroundColor(this.hoveredBtnId === 'qa1' ? this.getColors().HOVER_BG : this.getColors().BG_SECONDARY)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .border({ width: 1, color: this.getColors().EMPHASIZE }).borderRadius(10)
          .height(38).width('100%').padding({ left: 12 })
          .onClick(() => { this.quickAction('上次写到哪了') })
        Button('👥 检查人名一致性').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(this.getColors().BG_SECONDARY)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
          })
          .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'qa2' : '' })
          .backgroundColor(this.hoveredBtnId === 'qa2' ? this.getColors().HOVER_BG : this.getColors().BG_SECONDARY)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .border({ width: 1, color: this.getColors().EMPHASIZE }).borderRadius(10)
          .height(38).width('100%').padding({ left: 12 })
          .onClick(() => { this.quickAction('检查人名一致性') })
        Button('🔍 检查设定漏洞').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(this.getColors().BG_SECONDARY)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
          })
          .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'qa3' : '' })
          .backgroundColor(this.hoveredBtnId === 'qa3' ? this.getColors().HOVER_BG : this.getColors().BG_SECONDARY)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .border({ width: 1, color: this.getColors().EMPHASIZE }).borderRadius(10)
          .height(38).width('100%').padding({ left: 12 })
          .onClick(() => { this.quickAction('检查设定漏洞') })
        Button('⚔ 检查关系冲突').fontSize(13).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(this.getColors().BG_SECONDARY)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(this.getColors().BG_SECONDARY) }
          })
          .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'qa4' : '' })
          .backgroundColor(this.hoveredBtnId === 'qa4' ? this.getColors().HOVER_BG : this.getColors().BG_SECONDARY)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .border({ width: 1, color: this.getColors().EMPHASIZE }).borderRadius(10)
          .height(38).width('100%').padding({ left: 12 })
          .onClick(() => { this.quickAction('检查关系冲突') })
      }.width('100%').padding({ left: 16, right: 16 })

      List() {
        ForEach(this.messages, (msg: AgentMessage, idx: number) => {
          ListItem() {
            Column() {
              Text(msg.text).fontSize(13)
                .fontColor(msg.role === 'user' ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
                .padding({ left: 13, right: 13, top: 10, bottom: 10 })
            }
            .borderRadius(14)
            .backgroundColor(msg.role === 'user' ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY)
            .border(msg.role === 'user' ? { width: 0 } : { width: 1, color: this.getColors().DIVIDER })
            .alignSelf(msg.role === 'user' ? ItemAlign.End : ItemAlign.Start)
            .constraintSize({ maxWidth: '85%' }).margin({ left: 16, right: 16, bottom: 10 })
          }
        }, (msg: AgentMessage, idx: number): string => idx.toString())
      }.layoutWeight(1)

      Row({ space: 6 }) {
        TextInput({ text: $$this.inputText, placeholder: '向伴侣提问...' })
          .fontSize(13).fontColor(this.getColors().TEXT_PRIMARY).backgroundColor(this.getColors().BG_SECONDARY)
          .border({ width: 1, color: this.getColors().DIVIDER }).borderRadius(PcRadii.SM)
          .layoutWeight(1).height(36)
          .focusable(true)
          
          .onSubmit(() => { this.sendMessage() })
        Button('发送').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .backgroundColor(this.getColors().EMPHASIZE).borderRadius(PcRadii.SM)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().EMPHASIZE_PRESSED) },
            normal: { .backgroundColor(this.getColors().EMPHASIZE) }
          })
          .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'send' : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .height(36).padding({ left: 14, right: 14 })
          .onClick(() => { this.sendMessage() })
      }
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(this.getColors().BG_SECONDARY).border({ width: { top: 1 }, color: this.getColors().DIVIDER })
    }
    .width(320).height('100%').backgroundColor(this.getColors().LIST_BG)
    .border({ width: { left: 1 }, color: this.getColors().DIVIDER })
  }
}