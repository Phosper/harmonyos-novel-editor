// 用户头像：有自定义图片就显示图片（圆形裁切），否则回落到系统占位人像
//
// 只读组件：上传/移除在设置页的账号分组里做，侧栏只负责展示，
// 两个位置共用同一份 UiStore.avatarPath，不会出现两套头像状态。
import { app } from '../store/AppStores'
import { tokensFor, WeaverColorSet } from '../constants/DesignTokens'
import { AvatarService } from '../utils/AvatarService'

@ComponentV2
export struct UserAvatar {
  /**
   * 直径（vp）。不能叫 size —— 'size' 是 CustomComponent 自带属性
   * （CommonMethod.size），@Param 同名会编译失败：property is not assignable。
   */
  @Param avatarSize: number = 28

  private colors(): WeaverColorSet {
    return tokensFor(app.ui.themeId)
  }

  /** 头像不绑定登录态：本机可以先放一张图，昵称仍可空着（侧栏显示「请登录」） */
  private hasPhoto(): boolean {
    return app.ui.avatarPath !== ''
  }

  /** 沙箱 URI（fileUri.getUriFromPath）；空串时不要交给 Image（会报参数错误） */
  private photoSrc(): string {
    return AvatarService.toImageSrc(app.ui.avatarPath)
  }

  build() {
    Stack() {
      if (this.hasPhoto() && this.photoSrc() !== '') {
        Image(this.photoSrc())
          .width(this.avatarSize)
          .height(this.avatarSize)
          .objectFit(ImageFit.Cover)
          .borderRadius(this.avatarSize / 2)
          .accessibilityText('用户头像')
      } else {
        SymbolGlyph(app.ui.isLoggedIn()
          ? $r('sys.symbol.person_crop_circle_fill_1')
          : $r('sys.symbol.person_crop_circle_dashed'))
          .fontSize(this.avatarSize - 4)
          .fontColor([app.ui.isLoggedIn() ? this.colors().brand : this.colors().textTertiary])
          .accessibilityText(app.ui.isLoggedIn() ? '已登录头像' : '未登录头像')
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .clip(true)
  }
}
