import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { RelationshipDao } from '../data/RelationshipDao'
import type { CharacterModel, RelationshipModel } from '@ohos/common'

@Component
export struct RelationLabelSheet {
  @Prop characters: CharacterModel[] = []
  @Prop bookId: string = ''
  @State selectedCharAIndex: number = -1
  @State selectedCharBIndex: number = -1
  @State selectedType: string = 'neutral'
  @State label: string = ''
  @State notes: string = ''
  @State showCharAPicker: boolean = false
  @State showCharBPicker: boolean = false
  onChange?: () => void

  build() {
    Column() {
      Scroll() {
        Column() {
          Text('添加关系连线').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(GrayColors.G900)
            .width('100%').textAlign(TextAlign.Center)
            .padding({ top: 20, bottom: 16 })

          // ===== Character A selector (custom dropdown) =====
          Text('人物A').fontSize(13).fontColor(GrayColors.G500)
            .width('100%').padding({ left: 16, bottom: 4 })

          Column() {
            Row() {
              Text(this.selectedCharAIndex >= 0 ? this.characters[this.selectedCharAIndex].name : '请选择人物A')
                .fontSize(14).fontColor(this.selectedCharAIndex >= 0 ? GrayColors.G900 : GrayColors.G300)
                .layoutWeight(1)
              Text('▼').fontSize(10).fontColor(GrayColors.G300)
            }
            .width('100%').height(44).padding({ left: 12, right: 12 })
            .borderRadius(8)
            .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
            .backgroundColor(SemanticColors.BG_CARD)
            .onClick(() => { this.showCharAPicker = !this.showCharAPicker })

            if (this.showCharAPicker && this.characters.length > 0) {
              Column() {
                ForEach(this.characters, (ch: CharacterModel, idx: number) => {
                  Row() {
                    Text(ch.name).fontSize(14)
                      .fontColor(idx === this.selectedCharBIndex ? GrayColors.G300 : GrayColors.G900)
                      .layoutWeight(1)
                    if (idx === this.selectedCharAIndex) {
                      Text('✓').fontSize(14).fontColor(GreenColors.G500)
                    }
                    if (idx === this.selectedCharBIndex) {
                      Text('已选为人物B').fontSize(11).fontColor(GrayColors.G300)
                    }
                  }
                  .width('100%').height(40).padding({ left: 12, right: 12 })
                  .backgroundColor(idx === this.selectedCharAIndex ? GrayColors.G50 : Color.Transparent)
                  .onClick(() => {
                    if (idx !== this.selectedCharBIndex) {
                      this.selectedCharAIndex = idx
                      this.showCharAPicker = false
                    }
                  })
                }, (ch: CharacterModel) => ch.id)
              }
              .width('100%')
              .borderRadius(8)
              .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
              .backgroundColor(SemanticColors.BG_CARD)
            }
          }
          .width('100%')
          .margin({ left: 16, right: 16, bottom: 12 })

          // ===== Character B selector (custom dropdown) =====
          Text('人物B').fontSize(13).fontColor(GrayColors.G500)
            .width('100%').padding({ left: 16, bottom: 4 })

          Column() {
            Row() {
              Text(this.selectedCharBIndex >= 0 ? this.characters[this.selectedCharBIndex].name : '请选择人物B')
                .fontSize(14).fontColor(this.selectedCharBIndex >= 0 ? GrayColors.G900 : GrayColors.G300)
                .layoutWeight(1)
              Text('▼').fontSize(10).fontColor(GrayColors.G300)
            }
            .width('100%').height(44).padding({ left: 12, right: 12 })
            .borderRadius(8)
            .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
            .backgroundColor(SemanticColors.BG_CARD)
            .onClick(() => { this.showCharBPicker = !this.showCharBPicker })

            if (this.showCharBPicker && this.characters.length > 0) {
              Column() {
                ForEach(this.characters, (ch: CharacterModel, idx: number) => {
                  Row() {
                    Text(ch.name).fontSize(14)
                      .fontColor(idx === this.selectedCharAIndex ? GrayColors.G300 : GrayColors.G900)
                      .layoutWeight(1)
                    if (idx === this.selectedCharBIndex) {
                      Text('✓').fontSize(14).fontColor(GreenColors.G500)
                    }
                    if (idx === this.selectedCharAIndex) {
                      Text('已选为人物A').fontSize(11).fontColor(GrayColors.G300)
                    }
                  }
                  .width('100%').height(40).padding({ left: 12, right: 12 })
                  .backgroundColor(idx === this.selectedCharBIndex ? GrayColors.G50 : Color.Transparent)
                  .onClick(() => {
                    if (idx !== this.selectedCharAIndex) {
                      this.selectedCharBIndex = idx
                      this.showCharBPicker = false
                    }
                  })
                }, (ch: CharacterModel) => ch.id)
              }
              .width('100%')
              .borderRadius(8)
              .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
              .backgroundColor(SemanticColors.BG_CARD)
            }
          }
          .width('100%')
          .margin({ left: 16, right: 16, bottom: 16 })

          // Type selector
          Text('关系类型').fontSize(13).fontColor(GrayColors.G500)
            .width('100%').padding({ left: 16, bottom: 8 })

          Row({ space: 8 }) {
            Button('正面')
              .fontSize(13).height(36)
              .fontColor(this.selectedType === 'positive' ? '#FFFFFF' : GrayColors.G700)
              .backgroundColor(this.selectedType === 'positive' ? '#A4CE92' : GrayColors.G50)
              .borderRadius(8)
              .onClick(() => { this.selectedType = 'positive' })
            Button('中立')
              .fontSize(13).height(36)
              .fontColor(this.selectedType === 'neutral' ? '#FFFFFF' : GrayColors.G700)
              .backgroundColor(this.selectedType === 'neutral' ? '#9E9D9D' : GrayColors.G50)
              .borderRadius(8)
              .onClick(() => { this.selectedType = 'neutral' })
            Button('负面')
              .fontSize(13).height(36)
              .fontColor(this.selectedType === 'negative' ? '#FFFFFF' : GrayColors.G700)
              .backgroundColor(this.selectedType === 'negative' ? '#6F6E6E' : GrayColors.G50)
              .borderRadius(8)
              .onClick(() => { this.selectedType = 'negative' })
            Button('间接')
              .fontSize(13).height(36)
              .fontColor(this.selectedType === 'indirect' ? '#FFFFFF' : GrayColors.G700)
              .backgroundColor(this.selectedType === 'indirect' ? '#D5D5D5' : GrayColors.G50)
              .borderRadius(8)
              .onClick(() => { this.selectedType = 'indirect' })
          }
          .width('100%').padding({ left: 16, right: 16 })

          // Label input
          Text('关系标签').fontSize(13).fontColor(GrayColors.G500)
            .width('100%').padding({ left: 16, top: 16, bottom: 4 })
          TextInput({ text: $$this.label, placeholder: '例如：好友、师徒、敌人' })
            .fontSize(14).fontColor(GrayColors.G900)
            .placeholderColor(GrayColors.G300)
            .height(44).borderRadius(8)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
            .margin({ left: 16, right: 16, bottom: 12 })

          // Notes input
          Text('备注').fontSize(13).fontColor(GrayColors.G500)
            .width('100%').padding({ left: 16, bottom: 4 })
          TextArea({ text: $$this.notes, placeholder: '备注（可选）' })
            .fontSize(14).fontColor(GrayColors.G900)
            .placeholderColor(GrayColors.G300)
            .height(80).borderRadius(8)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: SemanticColors.BORDER_DEFAULT })
            .margin({ left: 16, right: 16, bottom: 20 })
        }
        .width('100%')
      }
      .layoutWeight(1)

      // Bottom buttons
      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14).height(44).layoutWeight(1)
          .fontColor(GrayColors.G700)
          .backgroundColor(GrayColors.G50)
          .borderRadius(8)
          .onClick(() => {
            if (this.onChange) {
              this.onChange()
            }
          })
        Button('保存')
          .fontSize(14).height(44).layoutWeight(1)
          .fontColor('#FFFFFF')
          .backgroundColor(GreenColors.G500)
          .borderRadius(8)
          .onClick(() => { this.saveRelationship() })
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }

  async saveRelationship(): Promise<void> {
    if (this.selectedCharAIndex < 0 || this.selectedCharBIndex < 0) {
      return
    }
    if (this.bookId === '') {
      return
    }
    const model: RelationshipModel = {
      id: IdGenerator.generate(),
      bookId: this.bookId,
      characterIdA: this.characters[this.selectedCharAIndex].id,
      characterIdB: this.characters[this.selectedCharBIndex].id,
      type: this.selectedType,
      label: this.label.trim(),
      notes: this.notes.trim()
    }
    const dao: RelationshipDao = new RelationshipDao()
    await dao.insert(model)
    this.selectedCharAIndex = -1
    this.selectedCharBIndex = -1
    this.selectedType = 'neutral'
    this.label = ''
    this.notes = ''
    if (this.onChange) {
      this.onChange()
    }
  }
}
