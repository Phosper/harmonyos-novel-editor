// 通用对话框 —— 文本输入 与 危险操作确认 两用
// 用组件内联渲染（Stack 覆盖）而不是 CustomDialog，理由：V2 组件向
// @CustomDialog 传参不受支持，内联渲染在 V1/V2 混合期最稳。
import { tokensFor, WeaverColorSet, WeaverRadii, DEFAULT_THEME_ID } from '../constants/DesignTokens'
import { Motion } from '../constants/Motion'
import type { AppStores } from '../store/AppStores'
import { glassPanelStyle } from './MaterialSurface'

@ComponentV2
export struct InputDialog {
  @Param app: AppStores | null = null
  @Param title: string = ''
  @Param placeholder: string = ''
  @Param initialValue: string = ''
  @Param confirmLabel: string = '确定'
  @Param message: string = ''
  @Param danger: boolean = false
  /** false = 仅确认（用于删除等破坏性操作） */
  @Param withInput: boolean = true
  @Event onConfirm: (value: string) => void = () => {}
  @Event onCancel: () => void = () => {}

  @Local value: string = ''

  aboutToAppear(): void {
    this.value = this.initialValue
  }

  private colors(): WeaverColorSet {
    return tokensFor(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID)
  }

  build() {
    Column() {
      Column() {
        Text(this.title)
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.colors().textPrimary)
          .width('100%').margin({ bottom: this.message !== '' || this.withInput ? 12 : 20 })

        if (this.message !== '') {
          Text(this.message)
            .fontSize(14).fontColor(this.colors().textSecondary).lineHeight(21)
            .width('100%').margin({ bottom: 16 })
        }

        if (this.withInput) {
          TextInput({ text: this.value, placeholder: this.placeholder })
            .onChange((v: string) => { this.value = v })
            .width('100%').height(44)
            .fontSize(15).fontColor(this.colors().textPrimary)
            .backgroundColor(this.colors().bgSurface)
            .border({ width: 1, color: this.colors().divider })
            .borderRadius(WeaverRadii.SM)
            .margin({ bottom: 20 })
        }

        Row() {
          Button('取消')
            .layoutWeight(1).height(42).fontSize(15)
            .backgroundColor(this.colors().bgSurface)
            .fontColor(this.colors().textSecondary)
            .borderRadius(WeaverRadii.SM)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.onCancel())
          Button(this.confirmLabel)
            .layoutWeight(1).height(42).fontSize(15)
            .backgroundColor(this.danger ? this.colors().danger : this.colors().brand)
            .fontColor(this.colors().onBrand)
            .borderRadius(WeaverRadii.SM)
            .margin({ left: 12 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.onConfirm(this.value))
        }.width('100%')
      }
      .width('88%')
      .constraintSize({ maxWidth: 420, maxHeight: '90%' })
      .padding(20)
      // 自绘内联弹窗（非系统 Dialog）→ systemMaterial 不生效，
      // 用浮层玻璃（backgroundBlurStyle + 渐变 + 1px 描边 + 大圆角阴影）复刻同等观感
      .attributeModifier(glassPanelStyle(this.app !== null ? this.app.ui.themeId : DEFAULT_THEME_ID))
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    // 遮罩：比原来的 #66000000 略浅，让玻璃卡片的"通透"更明显；
    // 出现/消失统一 180ms / Curve.EaseOut（与既有动效规范一致）
    .backgroundColor('#59000000')
    .transition(TransitionEffect.OPACITY.animation({ duration: Motion.normal, curve: Motion.standardCurve }))
    .onClick(() => this.onCancel())
  }
}
