// PcSidebar.ets V2 — with press/hover/focus feedback + dual-mode colors
import { PcRadii, PcInteraction, pcColors, type LibItem, type ProjectItem, type PcColorSet } from './PcDesignTokens'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { router } from '@kit.ArkUI'

@Component
export struct PcSidebar {
  @StorageLink('colorMode') colorMode: number = 1

  readonly libDefs: LibItem[] = [
    { id: 'all', label: '全部文稿', icon: '≡', count: 0, active: false },
    { id: 'fav', label: '收藏', icon: '★', count: 0, active: false },
    { id: 'insp', label: '灵感池', icon: '✦', count: 0, active: false },
    { id: 'priv', label: '私密', icon: '◈', count: 0, active: false },
    { id: 'trash', label: '废纸篓', icon: '◻', count: 0, active: false }
  ]
  @Prop activeLibId: string = 'all'
  @Prop libCounts: Record<string, number> = {}
  @State projectsFolded: boolean = false
  @State userFolded: boolean = false
  @State showNewProjectInput: boolean = false
  @State newProjectName: string = ''
  @State userName: string = '创作者'
  @Prop projects: ProjectItem[] = []

  // Hover & press tracking
  @State hoveredLibId: string = ''
  @State hoveredProjId: string = ''
  @State pressedItemId: string = ''

  statusBarPad: number = 0
  onChangeLib: (libId: string) => void = (libId: string): void => { libId }
  onNewDoc: () => void = (): void => { }
  onCreateProject: (name: string) => void = (name: string): void => { name }
  onSelectProject: (bookId: string) => void = (bookId: string): void => { bookId }
  onToggleFold: () => void = (): void => { }

  getColors(): PcColorSet {
    return pcColors(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
  }

  confirmNewProject(): void {
    if (this.newProjectName.trim() === '') return
    this.onCreateProject(this.newProjectName.trim())
    this.showNewProjectInput = false
    this.newProjectName = ''
  }

  build() {
    Column() {
      Row() { Blank() }.width('100%').height(36)

      Button('+ 新建文稿')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.getColors().EMPHASIZE)
        .backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
        .stateStyles({
          pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
          normal: { .backgroundColor(Color.Transparent) }
        })
        .border({ width: 1, color: this.getColors().DIVIDER, style: BorderStyle.Dashed })
        .onHover((isHover: boolean) => { this.pressedItemId = isHover ? 'newdoc' : '' })
        .animation({ duration: PcInteraction.HOVER_DURATION })
        .focusable(true)
        
        .width('100%').height(34).margin({ bottom: 14, left: 4, right: 4 })
        .onClick(() => { this.onNewDoc() })

      Column({ space: 2 }) {
        ForEach(this.libDefs, (item: LibItem) => {
          Row() {
            Text(item.icon).fontSize(15)
              .fontColor(item.id === this.activeLibId ? this.getColors().EMPHASIZE : this.getColors().TEXT_SECONDARY)
              .width(20).textAlign(TextAlign.Center)
            Text(item.label).fontSize(14)
              .fontColor(item.id === this.activeLibId ? this.getColors().EMPHASIZE : this.getColors().TEXT_SECONDARY)
              .fontWeight(item.id === this.activeLibId ? FontWeight.Medium : FontWeight.Regular)
              .layoutWeight(1)
            if ((this.libCounts[item.id] ?? 0) > 0) {
              Text((this.libCounts[item.id] ?? 0).toString())
                .fontSize(item.id === 'trash' ? 10 : 10).fontColor(item.id === this.activeLibId ? '#FFFFFF' : item.id === 'trash' ? this.getColors().DANGER : this.getColors().TEXT_SECONDARY)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(item.id === 'trash' ? 6 : 8)
                .backgroundColor(item.id === this.activeLibId ? this.getColors().EMPHASIZE : item.id === 'trash' ? '#19FA2A2D' : this.getColors().DIVIDER)
            }
          }
          .width('100%').height(38).padding({ left: 12, right: 12 })
          .borderRadius(PcRadii.SM)
          .backgroundColor(
            this.pressedItemId === item.id ? this.getColors().CLICK_EFFECT :
            this.hoveredLibId === item.id ? this.getColors().HOVER_BG :
            item.id === this.activeLibId ? this.getColors().ACTIVE_BG : Color.Transparent
          )
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.pressedItemId = item.id }
            else { this.pressedItemId = '' }
          })
          .onHover((isHover: boolean) => { this.hoveredLibId = isHover ? item.id : '' })
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .onClick(() => { this.onChangeLib(item.id) })
        }, (item: LibItem): string => item.id)
      }.width('100%')

      Divider().width('100%').height(1).color(this.getColors().DIVIDER).margin({ top: 8, bottom: 8 })

      Row() {
        Text('项目').fontSize(11).fontColor(this.getColors().TEXT_TERTIARY).letterSpacing(2).layoutWeight(1)
        Row({ space: 2 }) {
          Button() { Text('+').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY).accessibilityText('新建项目') }
          .width(22).height(22).backgroundColor(Color.Transparent).borderRadius(5)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(Color.Transparent) }
          })
          .onHover((isHover: boolean) => { this.pressedItemId = isHover ? 'addproj' : '' })
          .backgroundColor(this.pressedItemId === 'addproj' ? this.getColors().HOVER_BG : Color.Transparent)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .onClick(() => { this.showNewProjectInput = !this.showNewProjectInput; this.newProjectName = '' })
          Button() { Text(this.projectsFolded ? '▸' : '▾').fontSize(14).fontColor(this.getColors().TEXT_TERTIARY).accessibilityText('展开/折叠项目列表') }
          .width(22).height(22).backgroundColor(Color.Transparent).borderRadius(5)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(Color.Transparent) }
          })
          .onHover((isHover: boolean) => { this.pressedItemId = isHover ? 'toggleproj' : '' })
          .backgroundColor(this.pressedItemId === 'toggleproj' ? this.getColors().HOVER_BG : Color.Transparent)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .onClick(() => { this.projectsFolded = !this.projectsFolded })
        }
      }.width('100%').padding({ left: 12, right: 12 }).margin({ top: 18, bottom: 8 })

      if (this.showNewProjectInput) {
        Row({ space: 6 }) {
          TextInput({ text: $$this.newProjectName, placeholder: '项目名称' })
            .fontSize(13).height(36).backgroundColor(this.getColors().BG_SECONDARY)
            .borderRadius(PcRadii.SM).border({ width: 1, color: this.getColors().EMPHASIZE }).layoutWeight(1)
          Button() { Text('✓').fontSize(14).accessibilityText('确认创建项目') }
          .width(30).height(30).fontColor(this.getColors().EMPHASIZE)
          .backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
          .stateStyles({
            pressed: { .backgroundColor(this.getColors().CLICK_EFFECT) },
            normal: { .backgroundColor(Color.Transparent) }
          })
          .onHover((isHover: boolean) => { this.pressedItemId = isHover ? 'confirmproj' : '' })
          .backgroundColor(this.pressedItemId === 'confirmproj' ? this.getColors().HOVER_BG : Color.Transparent)
          .animation({ duration: PcInteraction.HOVER_DURATION })
          .focusable(true)
          
          .onClick(() => { this.confirmNewProject() })
        }.width('100%').padding({ left: 8, right: 8, bottom: 6 })
      }

      if (!this.projectsFolded) {
        Column({ space: 2 }) {
          ForEach(this.projects, (proj: ProjectItem) => {
            Row() {
              Circle({ width: 8, height: 8 }).fill(proj.color)
              Text('📖 ' + proj.name).fontSize(14)
                .fontColor(proj.active ? this.getColors().EMPHASIZE : this.getColors().TEXT_PRIMARY)
                .fontWeight(proj.active ? FontWeight.Medium : FontWeight.Regular).layoutWeight(1)
              Text(proj.docCount.toString())
                .fontSize(11).fontColor(proj.active ? this.getColors().EMPHASIZE : this.getColors().TEXT_TERTIARY)
            }
            .width('100%').height(38).padding({ left: 12, right: 12 })
            .borderRadius(PcRadii.SM)
            .backgroundColor(
              this.pressedItemId === proj.id ? this.getColors().CLICK_EFFECT :
              this.hoveredProjId === proj.id ? this.getColors().HOVER_BG :
              proj.active ? this.getColors().ACTIVE_BG : Color.Transparent
            )
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) { this.pressedItemId = proj.id }
              else { this.pressedItemId = '' }
            })
            .onHover((isHover: boolean) => { this.hoveredProjId = isHover ? proj.id : '' })
            .animation({ duration: PcInteraction.HOVER_DURATION })
            .focusable(true)
            
            .onClick(() => { this.onSelectProject(proj.id) })
          }, (proj: ProjectItem): string => proj.id)
        }.width('100%').transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
      }

      Blank()

      Button() { Text('⚙').fontSize(18).fontColor(this.getColors().TEXT_TERTIARY) }
      .width('100%').height(40).backgroundColor(Color.Transparent).borderRadius(PcRadii.SM)
      .onHover((isHover: boolean) => { this.pressedItemId = isHover ? 'settings' : '' })
      .backgroundColor(this.pressedItemId === 'settings' ? this.getColors().HOVER_BG : Color.Transparent)
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .onClick(() => { router.pushUrl({ url: 'pages/ThemePage' }) })

      Row() {
        if (!this.userFolded) {
          Row() { Text('创').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#FFFFFF') }
          .width(28).height(28).borderRadius(14).backgroundColor(this.getColors().EMPHASIZE)
          .justifyContent(FlexAlign.Center).margin({ right: 10 })
          Column() {
            Text(this.userName).fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.getColors().TEXT_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('本地版 · 数据属于你').fontSize(10).fontColor(this.getColors().TEXT_TERTIARY)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        Text(this.userFolded ? '▸' : '▾').fontSize(10).fontColor(this.getColors().TEXT_TERTIARY)
      }.width('100%').height(40).padding({ left: 12, right: 10 }).borderRadius(PcRadii.SM)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) { this.pressedItemId = 'user' }
        else { this.pressedItemId = '' }
      })
      .backgroundColor(
        this.pressedItemId === 'user' ? this.getColors().CLICK_EFFECT :
        this.hoveredProjId === 'user' ? this.getColors().HOVER_BG : Color.Transparent
      )
      .onHover((isHover: boolean) => { this.hoveredProjId = isHover ? 'user' : '' })
      .animation({ duration: PcInteraction.HOVER_DURATION })
      .focusable(true)
      
      .onClick(() => { this.userFolded = !this.userFolded })
    }
    .width('100%').height('100%').padding({ left: 10, right: 10, top: 0, bottom: 10 })
    .backgroundColor(this.getColors().SIDEBAR_BG)
  }
}