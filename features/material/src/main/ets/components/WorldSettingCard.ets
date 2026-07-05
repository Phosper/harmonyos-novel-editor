// WorldSettingCard.ets
import { SemanticColors, GrayColors, GreenColors } from '@ohos/common'
import type { WorldSettingModel } from '@ohos/common'

@Component
export struct WorldSettingCard {
  @Prop setting: WorldSettingModel

  private categoryLabel(cat: string): string {
    const labels: Record<string, string> = {
      'geography': '地理', 'politics': '政治', 'history': '历史',
      'magic_tech': '魔法科技', 'race': '种族', 'culture': '文化', 'other': '其他'
    }
    return labels[cat] ?? '其他'
  }

  build() {
    Column() {
      Text(this.setting.name)
        .fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(GrayColors.G900)
        .margin({ bottom: 6 })

      Text(this.categoryLabel(this.setting.category))
        .fontSize(11).fontColor(GreenColors.G500)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor(GreenColors.G100)
        .borderRadius(4)

      if (this.setting.region !== '') {
        Text(this.setting.region).fontSize(12).fontColor(GrayColors.G300).margin({ top: 8 })
      }

      Text(this.setting.description !== '' ? this.setting.description : '描述待补充')
        .fontSize(11).fontColor(GrayColors.G300)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding(8).margin({ top: 6 })
        .width('100%').backgroundColor(GrayColors.G50)
        .borderRadius(4)
    }
    .width(140).height(130)
    .padding(12)
    .borderRadius(16)
    .backgroundColor(SemanticColors.BG_CARD)
    .border({ width: 1, color: GrayColors.G100 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
  }
}
