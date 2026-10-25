// 设置面板（对标华为电子邮件「设置」）
//
// 版式：分区标题 + 圆角分组卡片 + 行内「标题 / 副标题 / 值·勾选」；
// 由 bindSheet 半模态承载（标题与关闭键由 sheet 提供，面板不再自画标题）。
// 主题选择是单选（✓），写作开关用 Switch；末尾保留一条强调色的恢复默认动作。
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { app } from '../store/AppStores'
import { tokensFor, WeaverColorSet, WeaverRadii, THEMES, WeaverTheme, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { AvatarService } from '../utils/AvatarService'
import { UserAvatar } from './UserAvatar'

@ComponentV2
export struct SettingsPanel {
  /** 未登录时输入的昵称（登录即写入首选项，不经过服务端） */
  @Local loginName: string = ''

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  private tablet(): boolean {
    return app.ui.tabletMode
  }

  private rowHeight(): number {
    return this.tablet() ? 72 : 60
  }

  private titleFont(): number {
    return this.tablet() ? 17 : 16
  }

  private subFont(): number {
    return this.tablet() ? 14 : 12
  }

  private cardRadius(): number {
    return this.tablet() ? 18 : 14
  }

  private themeSubtitle(theme: WeaverTheme): string {
    return theme.dark ? '深色 · 柔和护眼' : '浅色 · 纸感底色'
  }

  private resetDefaults(): void {
    app.ui.setTheme(DEFAULT_THEME_ID)
    app.ui.typewriter = false
  }

  private loggedIn(): boolean {
    return app.ui.isLoggedIn()
  }

  private canLogin(): boolean {
    return this.loginName.trim() !== ''
  }

  private async submitLogin(): Promise<void> {
    if (!this.canLogin()) {
      return
    }
    await app.ui.signIn(this.loginName)
    this.loginName = ''
  }

  private async signOutUser(): Promise<void> {
    await app.ui.signOut()
  }

  /**
   * 上传头像：系统图库单选 → 复制进沙箱 → 记住路径。
   * 用户取消时 pickAndCopy 返回空串，保持原头像不动。
   */
  private async pickAvatar(): Promise<void> {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
    const path: string = await AvatarService.pickAndCopy(context.filesDir)
    if (path === '') {
      return
    }
    const old: string = app.ui.avatarPath
    await app.ui.setAvatar(path)
    AvatarService.removeFile(old)
  }

  private async removeAvatar(): Promise<void> {
    const old: string = app.ui.avatarPath
    await app.ui.removeAvatar()
    AvatarService.removeFile(old)
  }

  /**
   * 账号分组：放在设置页最上方（原来独立的账号半模态已并入这里）。
   * 未登录 → 昵称输入 + 登录；已登录 → 头像 + 昵称 + 退出登录。
   */
  @Builder
  accountSection() {
    Column() {
      Row() {
        // 点头像也能换：比只留一行文字动作更符合"头像"的直觉
        UserAvatar({ avatarSize: 48 })
          .accessibilityText('更换头像')
          .onClick(() => {
            this.pickAvatar()
          })

        Column() {
          Text(this.loggedIn() ? app.ui.nickname : '未登录')
            .fontSize(this.titleFont())
            .fontWeight(FontWeight.Medium)
            .fontColor(this.colors().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.loggedIn() ? '头像与昵称只保存在本机' : '昵称仅保存在本机')
            .fontSize(this.subFont())
            .fontColor(this.colors().textTertiary)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        if (this.loggedIn()) {
          Text('退出登录')
            .fontSize(this.subFont() + 1)
            .fontColor(this.colors().brand)
            .padding({ left: 12, right: 4, top: 10, bottom: 10 })
            .accessibilityText('退出登录')
            .onClick(() => {
              this.signOutUser()
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })

      // 头像上传不依赖登录：换头像随时可用，昵称再单独登录
      this.rowDivider()
      this.avatarActions()

      if (!this.loggedIn()) {
        this.rowDivider()
        Row() {
          TextInput({ text: this.loginName, placeholder: '输入昵称，最多 20 字' })
            .maxLength(20)
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(this.colors().textPrimary)
            .placeholderColor(this.colors().textTertiary)
            .backgroundColor(this.colors().bgSurface)
            .border({ width: 1, color: this.colors().divider })
            .borderRadius(WeaverRadii.SM)
            .onChange((v: string) => {
              this.loginName = v
            })
            .onSubmit(() => {
              this.submitLogin()
            })
          Button('登录')
            .height(40)
            .margin({ left: 10 })
            .fontSize(15)
            .backgroundColor(this.canLogin() ? this.colors().brand : this.colors().activeBg)
            .fontColor(this.canLogin() ? this.colors().onBrand : this.colors().textTertiary)
            .enabled(this.canLogin())
            .accessibilityText('登录')
            .onClick(() => {
              this.submitLogin()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.colors().bgCard)
    .borderRadius(this.cardRadius())
    .clip(true)
    .margin({ bottom: 8 })
  }

  /** 头像动作：上传 / 移除（不依赖登录态，头像只存本机） */
  @Builder
  avatarActions() {
    Row() {
      Text('更换头像')
        .fontSize(this.subFont() + 1)
        .fontColor(this.colors().brand)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .accessibilityText('更换头像')
        .onClick(() => {
          this.pickAvatar()
        })
      if (app.ui.avatarPath !== '') {
        Text('移除头像')
          .fontSize(this.subFont() + 1)
          .fontColor(this.colors().textSecondary)
          .padding({ left: 0, right: 16, top: 12, bottom: 12 })
          .accessibilityText('移除头像')
          .onClick(() => {
            this.removeAvatar()
          })
      }
      Blank()
    }
    .width('100%')
  }

  /** 外观分组标题：调色板图标（HarmonyOS Symbol paintpalette），指明这里是换主题的地方 */
  @Builder
  themeTitle() {
    Row() {
      SymbolGlyph($r('sys.symbol.paintpalette'))
        .fontSize(this.tablet() ? 15 : 14)
        .fontColor([this.colors().textTertiary])
        .margin({ right: 6 })
      Text('外观')
        .fontSize(this.tablet() ? 14 : 13)
        .fontColor(this.colors().textTertiary)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 20, bottom: 8 })
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(this.tablet() ? 14 : 13)
      .fontColor(this.colors().textTertiary)
      .width('100%')
      .padding({ left: 4, right: 4, top: 20, bottom: 8 })
  }

  @Builder
  rowDivider() {
    Divider()
      .color(this.colors().divider)
      .margin({ left: 16, right: 16 })
  }

  /** 主题行：名称 + 明暗说明 + 选中勾 */
  @Builder
  themeRow(theme: WeaverTheme) {
    Row() {
      Column() {
        Text(theme.name)
          .fontSize(this.titleFont())
          .fontColor(this.colors().textPrimary)
          .maxLines(1)
        Text(this.themeSubtitle(theme))
          .fontSize(this.subFont())
          .fontColor(this.colors().textTertiary)
          .margin({ top: 3 })
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (app.ui.themeId === theme.id) {
        Text('✓')
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.colors().brand)
      }
    }
    .width('100%')
    .height(this.rowHeight())
    .padding({ left: 16, right: 16 })
    .backgroundColor(app.ui.themeId === theme.id ? this.colors().activeBg : Color.Transparent)
    .accessibilityText(theme.name + (app.ui.themeId === theme.id ? '，已选中' : ''))
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => { app.ui.setTheme(theme.id) })
  }

  /** 开关行：标题 + 说明 + Switch */
  @Builder
  switchRow(title: string, subtitle: string, on: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(this.titleFont())
          .fontColor(this.colors().textPrimary)
          .maxLines(1)
        Text(subtitle)
          .fontSize(this.subFont())
          .fontColor(this.colors().textTertiary)
          .margin({ top: 3 })
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .onChange((value: boolean) => onChange(value))
    }
    .width('100%')
    .constraintSize({ minHeight: this.rowHeight() })
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .accessibilityText(title)
  }

  /** 只读值行：左侧标题、右侧值 */
  @Builder
  valueRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(this.titleFont()).fontColor(this.colors().textPrimary)
      Text(value).fontSize(this.titleFont()).fontColor(this.colors().textTertiary)
        .layoutWeight(1).textAlign(TextAlign.End)
    }
    .width('100%').height(this.rowHeight())
    .padding({ left: 16, right: 16 })
    .accessibilityText(label + '：' + value)
  }

  private showLegal(title: string, body: string): void {
    promptAction.showDialog({ title: title, message: body, buttons: [{ text: '知道了', color: this.colors().brand }] })
      .catch(() => {})
  }

  /** 动作行：强调色文字（对齐电子邮件的「添加账户」） */
  @Builder
  actionRow(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(this.titleFont())
        .fontColor(this.colors().brand)
    }
    .width('100%')
    .height(this.rowHeight())
    .padding({ left: 16, right: 16 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(onTap)
    .accessibilityText(label)
  }

  build() {
    Column() {
      this.sectionTitle('账号')
      this.accountSection()

      this.themeTitle()
      Column() {
        ForEach(THEMES, (theme: WeaverTheme, index: number) => {
          this.themeRow(theme)
          if (index < THEMES.length - 1) {
            this.rowDivider()
          }
        }, (theme: WeaverTheme) => theme.id)

        this.rowDivider()
        this.actionRow('恢复默认设置', () => this.resetDefaults())
      }
      .width('100%')
      .backgroundColor(this.colors().bgCard)
      .borderRadius(this.cardRadius())
      .clip(true)

      this.sectionTitle('写作')
      Column() {
        this.switchRow('打字机模式', '当前段落居中，其余段落淡化显示', app.ui.typewriter,
          (value: boolean) => { app.ui.typewriter = value })
      }
      .width('100%')
      .backgroundColor(this.colors().bgCard)
      .borderRadius(this.cardRadius())
      .clip(true)

      this.sectionTitle('关于')
      Column() {
        this.valueRow('版本', '1.0.0')
        this.rowDivider()
        this.actionRow('服务协议', () => this.showLegal('服务协议', '语流为本地优先的写作工具：文稿保存在本机，不上传服务器；导出/备份由你主动发起。完整条款以正式发布版为准。'))
        this.rowDivider()
        this.actionRow('隐私政策', () => this.showLegal('隐私政策', '语流不收集个人身份信息，不读取其他应用数据；仅在导入/导出时访问你选择的文件。'))
      }
      .width('100%')
      .backgroundColor(this.colors().bgCard)
      .borderRadius(this.cardRadius())
      .clip(true)

      Text('语流 · 本地优先的写作工具')
        .fontSize(12)
        .fontColor(this.colors().textTertiary)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 24, bottom: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }
}
