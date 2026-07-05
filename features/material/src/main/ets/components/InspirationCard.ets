// InspirationCard.ets
import { SemanticColors, GrayColors } from '@ohos/common'
import type { InspirationModel } from '@ohos/common'

@Component
export struct InspirationCard {
  @Prop inspiration: InspirationModel
  @Prop showBookInfo: boolean = false
  @Prop bookName: string = ''

  build() {
    Column() {
      Text(this.inspiration.content)
        .fontSize(13).fontColor(GrayColors.G700)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(18)
        .padding(12)
        .layoutWeight(1)

      if (this.showBookInfo && this.bookName !== '') {
        Text(this.bookName)
          .fontSize(10).fontColor(GrayColors.G300)
          .padding({ left: 12, bottom: 8 })
          .width('100%')
      }
    }
    .width(150).height(100)
    .borderRadius(16)
    .backgroundColor(SemanticColors.BG_CARD)
    .border({ width: 1, color: GrayColors.G100 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
  }
}
