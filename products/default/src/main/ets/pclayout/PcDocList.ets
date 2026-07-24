// PcDocList.ets V2 — with press/hover/focus feedback + dual-mode colors
import { PcRadii, PcInteraction, pcColors, type DocListItem, type PcColorSet, MidTabMode } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'

@Component
export struct PcDocList {
  @StorageLink('colorMode') colorMode: number = 1

  @Prop listTitle: string = '全部文稿'
  @State searchText: string = ''
  @State midTab: MidTabMode = MidTabMode.CHAPTERS
  @Prop showMidSeg: boolean = false
  @Prop docItems: DocListItem[] = []
  @Prop isTrashView: boolean = false

  // Hover & press tracking
  @State hoveredDocId: string = ''
  @State pressedDocId: string = ''
  @State hoveredBtnId: string = ''

  statusBarPad: number = 0
  onChangeMidTab: (mode: MidTabMode) => void = (mode: MidTabMode): void => { mode }
  onSearch: (text: string) => void = (text: string): void => { text }
  onSelectDoc: (docId: string) => void = (docId: string): void => { docId }
  onNewDoc: () => void = (): void => { }
  onDeleteDoc: (docId: string) => void = (docId: string): void => { docId }
  onHardDelete: (docId: string) => void = (docId: string): void => { docId }
  onRestoreDoc: (docId: string) => void = (docId: string): void => { docId }
  onToggleFold: () => void = (): void => { }

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  switchMidTab(mode: MidTabMode): void { this.midTab = mode; this.onChangeMidTab(mode) }

  build() {
    Column() {
      Row() {
        Text(this.listTitle).fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().TEXT_PRIMARY).layoutWeight(1)
        Button() { Text('▷').fontSize(14).fontColor(this.getColors().TEXT_SECONDARY).accessibilityText('收起文稿列表') }
        .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(Color.Transparent) }
        })
        .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'fold' : '' })
        .backgroundColor(this.hoveredBtnId === 'fold' ? this.getColors().HOVER_BG : Color.Transparent)
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .focusable(true)
        
        .onClick(() => { this.onToggleFold() })
      }.width('100%').padding({ left: 16, right: 8, top: 10, bottom: 8 })

      Row({ space: 6 }) {
        Text('⌕').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY)
        TextInput({ text: $$this.searchText, placeholder: '搜索文稿...' })
          .fontSize(13).fontColor(this.getColors().TEXT_PRIMARY)
          .backgroundColor(Color.Transparent).border({ width: 0 }).layoutWeight(1)
          .onChange((value: string) => {
            this.onSearch(value)
          })
      }
      .width('100%').height(36).padding({ left: 10, right: 10 })
      .backgroundColor(this.getColors().BG_SECONDARY)
      .border({ width: 1, color: this.hoveredBtnId === 'search' ? this.getColors().EMPHASIZE : this.getColors().DIVIDER })
      .borderRadius(PcRadii.SM).margin({ left: 16, right: 16, bottom: 10 })
      .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'search' : '' })
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .focusable(true)
      

      if (this.showMidSeg) {
        Row({ space: 6 }) {
          Button('章节')
            .fontSize(13).fontColor(this.midTab === MidTabMode.CHAPTERS ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
            .backgroundColor(this.midTab === MidTabMode.CHAPTERS ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY)
            .stateStyles({
              pressed: { .backgroundColor(this.midTab === MidTabMode.CHAPTERS ? this.getColors().EMPHASIZE_PRESSED : this.getColors().CLICK_EFFECT) },
              normal: { .backgroundColor(this.midTab === MidTabMode.CHAPTERS ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY) }
            })
            .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'seg_chapters' : '' })
            .animation({ duration: PcInteraction.HOVER_DURATION })
            .focusable(true)
            
            .borderRadius(PcRadii.SM).height(34).layoutWeight(1)
            .border({ width: this.midTab === MidTabMode.CHAPTERS ? 0 : 1, color: this.getColors().DIVIDER })
            .onClick(() => { this.switchMidTab(MidTabMode.CHAPTERS) })
          Button('资料库')
            .fontSize(13).fontColor(this.midTab === MidTabMode.MATERIALS ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
            .backgroundColor(this.midTab === MidTabMode.MATERIALS ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY)
            .stateStyles({
              pressed: { .backgroundColor(this.midTab === MidTabMode.MATERIALS ? this.getColors().EMPHASIZE_PRESSED : this.getColors().CLICK_EFFECT) },
              normal: { .backgroundColor(this.midTab === MidTabMode.MATERIALS ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY) }
            })
            .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'seg_materials' : '' })
            .animation({ duration: PcInteraction.HOVER_DURATION })
            .focusable(true)
            
            .borderRadius(PcRadii.SM).height(34).layoutWeight(1)
            .border({ width: this.midTab === MidTabMode.MATERIALS ? 0 : 1, color: this.getColors().DIVIDER })
            .onClick(() => { this.switchMidTab(MidTabMode.MATERIALS) })
          Button('关联图')
            .fontSize(13).fontColor(this.midTab === MidTabMode.GRAPH ? '#FFFFFF' : this.getColors().TEXT_SECONDARY)
            .backgroundColor(this.midTab === MidTabMode.GRAPH ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY)
            .stateStyles({
              pressed: { .backgroundColor(this.midTab === MidTabMode.GRAPH ? this.getColors().EMPHASIZE_PRESSED : this.getColors().CLICK_EFFECT) },
              normal: { .backgroundColor(this.midTab === MidTabMode.GRAPH ? this.getColors().EMPHASIZE : this.getColors().BG_SECONDARY) }
            })
            .onHover((isHover: boolean) => { this.hoveredBtnId = isHover ? 'seg_graph' : '' })
            .animation({ duration: PcInteraction.HOVER_DURATION })
            .focusable(true)
            
            .borderRadius(PcRadii.SM).height(34).layoutWeight(1)
            .border({ width: this.midTab === MidTabMode.GRAPH ? 0 : 1, color: this.getColors().DIVIDER })
            .onClick(() => { this.switchMidTab(MidTabMode.GRAPH) })
        }
        .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 4 })
        .border({ width: { bottom: 1 }, color: this.getColors().DIVIDER })
      }

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.docItems, (doc: DocListItem) => {
            Column() {
              Row() {
                Text('📄').fontSize(16).fontColor('#8A8A8A').margin({ right: 8 })

                Text(doc.title).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor('#1D1D1D').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)

                Button() { Text('×').fontSize(14).fontColor('#999999') }
                .width(28).height(28).backgroundColor(Color.Transparent).borderRadius(6)
                .stateStyles({
                  pressed: { .backgroundColor('#19000000') },
                  normal: { .backgroundColor(Color.Transparent) }
                })
                .onHover((isHover: boolean) => { this.hoveredDocId = isHover ? 'del_' + doc.id : '' })
                .onClick(() => { this.onDeleteDoc(doc.id) })
              }.width('100%').alignItems(VerticalAlign.Center)

              Text(doc.subTitle).fontSize(13).fontColor('#757575')
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .lineHeight(18).width('100%').margin({ top: 8, bottom: 12 })

              Row() {
                Text('🕐').fontSize(10).fontColor('#9E9E9E').margin({ right: 4 })
                Text(doc.modified).fontSize(12).fontColor('#9E9E9E')
              }.width('100%')

              if (this.isTrashView) {
                if (doc.expireDays > 0) {
                  Text('还剩 ' + doc.expireDays.toString() + ' 天自动删除')
                    .fontSize(11).fontColor('#757575').margin({ top: 12 })
                }
                Row({ space: 12 }) {
                  Button('还原').fontSize(12).fontColor(this.getColors().EMPHASIZE)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1, color: this.getColors().DIVIDER })
                    .borderRadius(8).height(28).layoutWeight(1)
                    .onClick(() => { this.onRestoreDoc(doc.id) })
                  Button('永久删除').fontSize(12).fontColor('#999999')
                    .backgroundColor(Color.Transparent)
                    .border({ width: 1, color: this.getColors().DIVIDER })
                    .borderRadius(8).height(28).layoutWeight(1)
                    .onClick(() => { this.onHardDelete(doc.id) })
                }.width('100%').margin({ top: 12 })
              }
            }
            .width('100%').padding(16)
            .backgroundColor(
              doc.selected ? '#F0F7FF' :
              this.hoveredDocId === doc.id ? '#F7F7F7' :
              '#FFFFFF'
            )
            .border({
              width: 1,
              color: doc.selected ? '#B3D8FF' :
                     this.hoveredDocId === doc.id ? '#DCDCDC' :
                     '#E5E5E5'
            })
            .borderRadius(12)
            .shadow({
              radius: 4,
              color: 'rgba(0,0,0,0.04)',
              offsetY: 2
            })
            .onHover((isHover: boolean) => { this.hoveredDocId = isHover ? doc.id : '' })
            .animation({ duration: 100 })
            .onClick(() => { this.onSelectDoc(doc.id) })
          }, (doc: DocListItem): string => doc.id)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: 10, right: 10, top: 4, bottom: 10 })
      }.layoutWeight(1).scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').backgroundColor(this.getColors().LIST_BG)
  }
}