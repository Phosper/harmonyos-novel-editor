// Index.ets — App Shell: Tab container with breakpoint-based navigation
import { BreakPoint, PreferenceHelper, PrefKeys, SemanticColors, GrayColors } from '@ohos/common'
import { EditorPage } from './EditorPage'
import { MaterialTabPage } from './MaterialTabPage'
import { RelationshipTabPage } from './RelationshipTabPage'
import { MyTabPage } from './MyTabPage'
import { PcShell } from '../pclayout/PcShell'

@Entry
@Component
struct Index {
  @StorageLink('currentBreakPoint') breakPoint: BreakPoint = BreakPoint.SM
  @StorageLink('weaver_mode') @Watch('onModeChanged') weaverMode: string = 'normal'
  @State currentTabIndex: number = 0

  onModeChanged(): void {
    this.currentTabIndex = 0
  }

  async aboutToAppear(): Promise<void> {
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    await prefs.init(getContext(this))
    const mode: string = await prefs.getString(PrefKeys.MODE, 'normal')
    AppStorage.setOrCreate('weaver_mode', mode)
    this.weaverMode = mode
  }

  @Builder
  buildEditorTab() {
    EditorPage()
  }

  @Builder
  buildMaterialTab() {
    MaterialTabPage()
  }

  @Builder
  buildRelationshipTab() {
    RelationshipTabPage()
  }

  @Builder
  buildMyTab() {
    MyTabPage()
  }

  build() {
    if (this.breakPoint === BreakPoint.SM) {
      this.buildBottomTabs()
    } else if (this.breakPoint === BreakPoint.MD) {
      this.buildSideTabs()
    } else {
      this.buildPcLayout()
    }
  }

  @Builder
  buildPcLayout() {
    PcShell()
  }

  @Builder
  buildBottomTabs() {
    Tabs({ barPosition: BarPosition.End, index: $$this.currentTabIndex }) {
      TabContent() { this.buildEditorTab() }
        .tabBar(this.buildTabLabel('✏️', '编辑', 0))

      if (this.weaverMode === 'professional') {
        TabContent() { this.buildMaterialTab() }
          .tabBar(this.buildTabLabel('📦', '素材', 1))
        TabContent() { this.buildRelationshipTab() }
          .tabBar(this.buildTabLabel('🕸', '关系', 2))
        TabContent() { this.buildMyTab() }
          .tabBar(this.buildTabLabel('👤', '我的', 3))
      } else {
        TabContent() { this.buildMyTab() }
          .tabBar(this.buildTabLabel('👤', '我的', 1))
      }
    }
    .barHeight(56)
    .backgroundColor(SemanticColors.BG_PRIMARY)
    .onChange((index: number) => { this.currentTabIndex = index; AppStorage.setOrCreate('active_tab_index', index) })
  }

  @Builder
  buildSideTabs() {
    Tabs({ barPosition: BarPosition.Start, index: $$this.currentTabIndex }) {
      TabContent() { this.buildEditorTab() }
        .tabBar(this.buildTabLabel('✏️', '编辑', 0))

      if (this.weaverMode === 'professional') {
        TabContent() { this.buildMaterialTab() }
          .tabBar(this.buildTabLabel('📦', '素材', 1))
        TabContent() { this.buildRelationshipTab() }
          .tabBar(this.buildTabLabel('🕸', '关系', 2))
        TabContent() { this.buildMyTab() }
          .tabBar(this.buildTabLabel('👤', '我的', 3))
      } else {
        TabContent() { this.buildMyTab() }
          .tabBar(this.buildTabLabel('👤', '我的', 1))
      }
    }
    .barWidth(72)
    .backgroundColor(SemanticColors.BG_PRIMARY)
    .onChange((index: number) => { this.currentTabIndex = index; AppStorage.setOrCreate('active_tab_index', index) })
  }

  @Builder
  buildTabLabel(icon: string, title: string, index: number) {
    Column() {
      Text(icon).fontSize(18)
      Text(title)
        .fontSize(12)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentTabIndex === index ? SemanticColors.INTERACTIVE_PRIMARY : GrayColors.G500)
        .animation({ duration: 200, curve: Curve.EaseInOut })
    }
    .padding({ top: 4, bottom: 4 })
  }
}
