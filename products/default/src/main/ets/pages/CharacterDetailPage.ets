// CharacterDetailPage.ets
import { router } from '@kit.ArkUI'
import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { CharacterDao } from '@ohos/material'
import type { CharacterModel } from '@ohos/common'

@Entry
@Component
struct CharacterDetailPage {
  @State characterId: string = ''
  @State bookId: string = ''
  @State name: string = ''
  @State alias: string = ''
  @State age: string = ''
  @State appearance: string = ''
  @State personality: string = ''
  @State backgroundText: string = ''
  @State notes: string = ''
  @State isNew: boolean = false

  aboutToAppear(): void {
    const raw: Object = router.getParams()
    this.characterId = this.getParamString(raw, 'characterId')
    this.bookId = this.getParamString(raw, 'bookId')
    this.isNew = this.getParamBool(raw, 'isNew')
    if (this.characterId !== '') {
      this.loadCharacter()
    }
  }

  private getParamString(obj: Object, key: string): string {
    const entries: [string, Object][] = Object.entries(obj)
    for (let i = 0; i < entries.length; i++) {
      if (entries[i][0] === key) {
        return String(entries[i][1])
      }
    }
    return ''
  }

  private getParamBool(obj: Object, key: string): boolean {
    const entries: [string, Object][] = Object.entries(obj)
    for (let i = 0; i < entries.length; i++) {
      if (entries[i][0] === key) {
        const val: Object = entries[i][1]
        return val === true || String(val) === 'true'
      }
    }
    return false
  }

  async loadCharacter(): Promise<void> {
    const dao: CharacterDao = new CharacterDao()
    const model: CharacterModel | null = await dao.queryById(this.characterId)
    if (model !== null) {
      this.name = model.name
      this.alias = model.alias
      this.age = model.age
      this.appearance = model.appearance
      this.personality = model.personality
      this.backgroundText = model.background
      this.notes = model.notes
      this.bookId = model.bookId
    }
  }

  async save(): Promise<void> {
    if (this.name.trim() === '') {
      return
    }
    if (this.bookId === '') {
      return
    }
    const dao: CharacterDao = new CharacterDao()
    if (this.isNew || this.characterId === '') {
      const model: CharacterModel = {
        id: IdGenerator.generate(),
        bookId: this.bookId,
        name: this.name.trim(),
        alias: this.alias,
        age: this.age,
        appearance: this.appearance,
        personality: this.personality,
        background: this.backgroundText,
        notes: this.notes
      }
      await dao.insert(model)
    } else {
      const model: CharacterModel = {
        id: this.characterId,
        bookId: this.bookId,
        name: this.name.trim(),
        alias: this.alias,
        age: this.age,
        appearance: this.appearance,
        personality: this.personality,
        background: this.backgroundText,
        notes: this.notes
      }
      await dao.update(this.characterId, model)
    }
    router.back()
  }

  build() {
    Column() {
      Row() {
        Button() { Text('←').fontSize(20) }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
        Text(this.isNew ? '新建人物' : '人物详情')
          .fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button('保存')
          .fontSize(14).fontColor(GreenColors.G500).backgroundColor(Color.Transparent)
          .onClick(() => { this.save() })
      }
      .width('100%').height(56).padding({ left: 8, right: 8 })
      .backgroundColor(SemanticColors.BG_CARD)

      Scroll() {
        Column() {
          // 姓名 *
          Row() {
            Text('姓名 *').fontSize(14).fontColor(GrayColors.G500).width(80)
            TextInput({ text: $$this.name, placeholder: '请输入姓名' })
              .fontSize(14).fontColor(GrayColors.G900).layoutWeight(1)
              .backgroundColor(Color.Transparent)
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 别名
          Row() {
            Text('别名').fontSize(14).fontColor(GrayColors.G500).width(80)
            TextInput({ text: $$this.alias, placeholder: '请输入别名' })
              .fontSize(14).fontColor(GrayColors.G900).layoutWeight(1)
              .backgroundColor(Color.Transparent)
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 年龄
          Row() {
            Text('年龄').fontSize(14).fontColor(GrayColors.G500).width(80)
            TextInput({ text: $$this.age, placeholder: '请输入年龄' })
              .fontSize(14).fontColor(GrayColors.G900).layoutWeight(1)
              .backgroundColor(Color.Transparent)
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 外貌
          Column() {
            Text('外貌').fontSize(14).fontColor(GrayColors.G500)
              .width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.appearance, placeholder: '请输入外貌描述' })
              .fontSize(14).fontColor(GrayColors.G900).height(80)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 性格
          Column() {
            Text('性格').fontSize(14).fontColor(GrayColors.G500)
              .width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.personality, placeholder: '请输入性格描述' })
              .fontSize(14).fontColor(GrayColors.G900).height(80)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 背景故事
          Column() {
            Text('背景故事').fontSize(14).fontColor(GrayColors.G500)
              .width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.backgroundText, placeholder: '请输入背景故事' })
              .fontSize(14).fontColor(GrayColors.G900).height(80)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)

          Divider().width('100%').height(1).color(SemanticColors.BORDER_DEFAULT)

          // 备注
          Column() {
            Text('备注').fontSize(14).fontColor(GrayColors.G500)
              .width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.notes, placeholder: '请输入备注' })
              .fontSize(14).fontColor(GrayColors.G900).height(80)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)
        }
        .width('100%')
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
