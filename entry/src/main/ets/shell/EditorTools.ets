// 顶栏编辑器工具组（桌面窗口头 / 平板宽屏顶栏共用）
//
// 设计目标（2026-10-18 顶栏承载常用工具）：
//   - 只收高频动作：撤销/重做、行内格式、查找、打字机、沉浸编辑；
//   - 导出/导入/设置等低频动作留在窗口头的「⋯」菜单，避免顶栏拥挤；
//   - 统一 28vp 胶囊命中区 + hover + 两态（可用/禁用、开/关），
//   - compact 模式下折叠格式组，只保留撤销/重做/查找/打字机/沉浸。
import { tokensFor, WeaverColorSet, WeaverRadii, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import type { AppStores } from '../store/AppStores'
import { fireAndLog } from '../store/AppStores'
import { promptAction } from '@kit.ArkUI'
import { ChapterFormat } from '../model/Chapter'
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

  private hitSize(): number {
    return this.app !== null && this.app.ui.pointerPrimary ? 32 : 48
  }

  private hasDoc(): boolean {
    return this.app !== null && this.app.editor.hasDoc
  }

  private currentMask(): number {
    if (this.app === null || this.app.ui.editorController === null) {
      return 0
    }
    // 读取版本号以建立订阅；具体值只用于触发重新求值
    const tick: number = this.app.ui.selectionTick
    if (tick < 0) {
      return 0
    }
    return this.app.ui.editorController.inlineStyleMask()
  }

  private openMenu(): void {
    const stores: AppStores | null = this.app
    if (stores === null || !stores.editor.hasDoc) {
      return
    }
    const color: string = this.colors().textPrimary
    const undo: promptAction.Button = { text: stores.editor.canUndo ? '撤销' : '撤销（不可用）', color: color }
    const redo: promptAction.Button = { text: stores.editor.canRedo ? '重做' : '重做（不可用）', color: color }
    const format: promptAction.Button = { text: '格式与文稿动作', color: color }
    const find: promptAction.Button = { text: '查找替换', color: color }
    const typewriter: promptAction.Button = { text: stores.ui.typewriter ? '关闭打字机模式' : '开启打字机模式', color: color }
    const focus: promptAction.Button = { text: stores.ui.immersiveEditing ? '退出专注写作' : '专注写作', color: color }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '编辑', buttons: [undo, redo, format, find, typewriter, focus]
    }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0 && stores.editor.canUndo) {
        stores.editor.undo()
      } else if (data.index === 1 && stores.editor.canRedo) {
        stores.editor.redo()
      } else if (data.index === 2) {
        this.openFormatMenu()
      } else if (data.index === 3) {
        stores.ui.requestFind()
      } else if (data.index === 4) {
        this.toggleTypewriter()
      } else if (data.index === 5) {
        stores.ui.toggleImmersiveEditing()
      }
    })
  }

  private openFormatMenu(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const color: string = this.colors().textPrimary
    const bold: promptAction.Button = { text: '加粗', color: color }
    const italic: promptAction.Button = { text: '斜体', color: color }
    const heading: promptAction.Button = { text: '标题', color: color }
    const txt: promptAction.Button = { text: '文稿格式 · TXT', color: color }
    const md: promptAction.Button = { text: '文稿格式 · Markdown', color: color }
    const more: promptAction.Button = { text: '更多文稿动作', color: color }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '格式', buttons: [bold, italic, heading, txt, md, more]
    }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0) {
        this.applyInline(StyleKind.BOLD)
      } else if (data.index === 1) {
        this.applyInline(StyleKind.ITALIC)
      } else if (data.index === 2) {
        this.applyHeading()
      } else if (data.index === 3 || data.index === 4) {
        fireAndLog(stores.setChapterFormat(data.index === 3 ? ChapterFormat.TXT : ChapterFormat.MD), 'setChapterFormat')
      } else if (data.index === 5) {
        this.openDocumentMenu()
      }
    })
  }

  private openDocumentMenu(): void {
    const stores: AppStores | null = this.app
    if (stores === null) {
      return
    }
    const color: string = this.colors().textPrimary
    const format: promptAction.Button = { text: '一键排版', color: color }
    const fav: promptAction.Button = { text: '收藏 / 取消收藏', color: color }
    const inspiration: promptAction.Button = { text: '移入 / 移出灵感池', color: color }
    this.getUIContext().getPromptAction().showActionMenu({
      title: '文稿动作', buttons: [format, fav, inspiration]
    }, (err, data) => {
      if (err) {
        return
      }
      if (data.index === 0) {
        stores.formatActiveDoc()
      } else if (data.index === 1) {
        fireAndLog(stores.toggleFav(stores.editor.activeId), 'toggleFav')
      } else if (data.index === 2) {
        fireAndLog(stores.toggleInspiration(stores.editor.activeId), 'toggleInspiration')
      }
    })
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
      this.toolButton('撤', '撤销', false, this.canUndo(), () => {
        if (this.app !== null) {
          this.app.editor.undo()
        }
      }, false)
      this.toolButton('重', '重做', false, this.canRedo(), () => {
        if (this.app !== null) {
          this.app.editor.redo()
        }
      }, false)

      if (!this.compact) {
        Divider()
          .vertical(true).height(14).color(this.colors().divider)
          .margin({ left: 4, right: 4 })
        this.toolButton('B', '加粗', (this.currentMask() & 1) !== 0, this.hasDoc(), () => this.applyInline(StyleKind.BOLD), true)
        this.toolButton('I', '斜体', (this.currentMask() & 2) !== 0, this.hasDoc(), () => this.applyInline(StyleKind.ITALIC), true)
        this.toolButton('H', '标题', (this.currentMask() & 4) !== 0, this.hasDoc(), () => this.applyHeading(), true)
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
      .height(this.hitSize())
      .padding({ left: 8, right: 9 })
      .borderRadius(13)
      .backgroundColor(this.typewriterOn() ? this.colors().activeBg : Color.Transparent)
      .border({ width: 1, color: this.typewriterOn() ? this.colors().brand : Color.Transparent })
      .accessibilityText(this.typewriterOn() ? '打字机模式：已开启，点击关闭' : '打字机模式：已关闭，点击开启')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleTypewriter())

      this.toolButton('查', '查找', false, this.hasDoc(), () => {
        if (this.app !== null) {
          this.app.ui.requestFind()
        }
      }, false)

      if (!this.immersive) {
        this.toolButton('专', '专注写作（隐藏侧栏与列表）', false, this.hasDoc(), () => {
          if (this.app !== null) {
            this.app.ui.toggleImmersiveEditing()
          }
        }, false)
      }
      this.toolButton('⋯', '更多编辑工具与文稿动作', false, this.hasDoc(), () => this.openMenu(), false)
    }
  }

  @Builder
  toolButton(glyph: string, label: string, active: boolean, enabled: boolean, action: () => void, bold: boolean) {
    Row() {
      Text(glyph)
        .fontSize(glyph.length > 1 ? 12 : 13)
        .fontWeight(bold ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(enabled
          ? (active ? this.colors().brand : this.colors().textPrimary)
          : this.colors().textTertiary)
    }
    .width(glyph.length > 1 ? this.hitSize() + 12 : this.hitSize())
    .height(this.hitSize())
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(WeaverRadii.XS)
    .backgroundColor(active ? this.colors().activeBg : Color.Transparent)
    .opacity(enabled ? 1 : 0.45)
    .enabled(enabled)
    .accessibilityText(enabled ? label : label + '（不可用）')
    .hoverEffect(HoverEffect.Highlight)
    .focusable(enabled)
    .tabStop(enabled)
    .onClick(action)
  }
}
