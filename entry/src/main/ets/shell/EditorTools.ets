// 顶栏编辑器工具组（桌面窗口头 / 平板宽屏顶栏共用）
//
// 设计目标（2026-10-18 顶栏承载常用工具）：
//   - 只收高频动作：撤销/重做、行内格式、查找、打字机、沉浸编辑；
//   - 导出/导入/设置等低频动作留在窗口头的「⋯」菜单，避免顶栏拥挤；
//   - 统一 28vp 胶囊命中区 + hover + 两态（可用/禁用、开/关），
//   - compact 模式下折叠格式组，只保留撤销/重做/查找/打字机/沉浸。
import { tokensFor, WeaverColorSet, WeaverRadii, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { StyleKind } from '../editor/flowtext/model/EditorTypes'

@ComponentV2
export struct EditorTools {
  @Param app: AppStores | null = null
  /** 窄宽度：隐藏 B/I/H1，减少顶栏宽度 */
  @Param compact: boolean = false
  /** 沉浸模式下隐藏"进入沉浸"按钮（退出入口由窗口头/浮动按钮提供） */
  @Param immersive: boolean = false

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  private canUndo(): boolean {
    return this.app !== null && this.app.editor.canUndo
  }

  private canRedo(): boolean {
    return this.app !== null && this.app.editor.canRedo
  }

  private typewriterOn(): boolean {
    return this.app !== null && this.app.ui.typewriter
  }

  private toggleTypewriter(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const next: boolean = !stores.ui.typewriter
    stores.ui.setTypewriter(next)
    if (stores.ui.editorController !== null) {
      stores.ui.editorController.setTypewriter(next)
    }
  }

  private applyInline(kind: StyleKind): void {
    if (this.app !== null && this.app.ui.editorController !== null) {
      this.app.ui.editorController.toggleInlineStyle(kind)
    }
  }

  private applyHeading(): void {
    if (this.app !== null && this.app.ui.editorController !== null) {
      this.app.ui.editorController.toggleParagraphStyle(1)
    }
  }

  build() {
    Row() {
      this.toolButton('撤', '撤销', this.canUndo(), () => {
        if (this.app !== null) {
          this.app.editor.undo()
        }
      }, false)
      this.toolButton('重', '重做', this.canRedo(), () => {
        if (this.app !== null) {
          this.app.editor.redo()
        }
      }, false)

      if (!this.compact) {
        Divider()
          .vertical(true).height(14).color(this.colors().divider)
          .margin({ left: 4, right: 4 })
        this.toolButton('B', '加粗', false, () => this.applyInline(StyleKind.BOLD), true)
        this.toolButton('I', '斜体', false, () => this.applyInline(StyleKind.ITALIC), true)
        this.toolButton('H', '标题', false, () => this.applyHeading(), true)
      }

      Divider()
        .vertical(true).height(14).color(this.colors().divider)
        .margin({ left: 4, right: 4 })

      // 打字机：两态胶囊（开启=品牌色 + 圆点 + 浅底）
      Row() {
        Circle({ width: 5, height: 5 })
          .fill(this.typewriterOn() ? this.colors().brand : this.colors().textTertiary)
          .margin({ right: 5 })
        Text('打字机')
          .fontSize(11)
          .fontColor(this.typewriterOn() ? this.colors().brand : this.colors().textSecondary)
      }
      .height(26)
      .padding({ left: 8, right: 9 })
      .borderRadius(13)
      .backgroundColor(this.typewriterOn() ? this.colors().activeBg : Color.Transparent)
      .border({ width: 1, color: this.typewriterOn() ? this.colors().brand : Color.Transparent })
      .accessibilityText(this.typewriterOn() ? '打字机模式：已开启，点击关闭' : '打字机模式：已关闭，点击开启')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleTypewriter())

      this.toolButton('查', '查找', false, () => {
        if (this.app !== null) {
          this.app.ui.requestFind()
        }
      }, false)

      if (!this.immersive) {
        this.toolButton('专', '专注写作（隐藏侧栏与列表）', false, () => {
          if (this.app !== null) {
            this.app.ui.toggleImmersiveEditing()
          }
        }, false)
      }
    }
  }

  @Builder
  toolButton(glyph: string, label: string, active: boolean, action: () => void, bold: boolean) {
    Row() {
      Text(glyph)
        .fontSize(13)
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(active || bold ? this.colors().textPrimary : this.colors().textSecondary)
    }
    .width(28).height(26)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(WeaverRadii.XS)
    .accessibilityText(label)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }
}
