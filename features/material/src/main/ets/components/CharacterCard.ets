// CharacterCard.ets
import { SemanticColors, GrayColors, GreenColors } from '@ohos/common'
import type { CharacterModel } from '@ohos/common'

@Component
export struct CharacterCard {
  @Prop character: CharacterModel

  build() {
    Column() {
      Column() {
        Text(this.character.name)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(GrayColors.G900)
        if (this.character.alias !== '') {
          Text(this.character.alias)
            .fontSize(12).fontColor(GrayColors.G300).margin({ top: 4 })
        }
      }
      .width('100%').layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Text(this.character.personality !== '' ? this.character.personality : '性格待补充')
        .fontSize(11).fontColor(GrayColors.G300)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding(8)
        .width('100%')
        .backgroundColor(GrayColors.G50)
    }
    .width(140).height(100)
    .borderRadius(16)
    .backgroundColor(SemanticColors.BG_CARD)
    .border({ width: 1, color: GrayColors.G100 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
  }
}
