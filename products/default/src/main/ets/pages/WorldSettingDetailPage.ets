// WorldSettingDetailPage.ets
import { router } from '@kit.ArkUI'
import { SemanticColors, GrayColors, GreenColors, IdGenerator } from '@ohos/common'
import { WorldSettingDao } from '@ohos/material'
import type { WorldSettingModel } from '@ohos/common'

@Entry
@Component
struct WorldSettingDetailPage {
  @State settingId: string = ''
  @State bookId: string = ''
  @State name: string = ''
  @State category: string = 'other'
  @State region: string = ''
  @State description: string = ''
  @State notes: string = ''
  @State isNew: boolean = false
  @State showCategoryPicker: boolean = false

  private categories: string[] = ['geography', 'politics', 'history', 'magic_tech', 'race', 'culture', 'other']

  private categoryLabel(cat: string): string {
    const labels: Record<string, string> = {
      'geography': '地理', 'politics': '政治', 'history': '历史',
      'magic_tech': '魔法科技', 'race': '种族', 'culture': '文化', 'other': '其他'
    }
    return labels[cat] ?? '其他'
  }

  aboutToAppear(): void {
    const raw: Object = router.getParams()
    this.settingId = this.getParamString(raw, 'settingId')
    this.bookId = this.getParamString(raw, 'bookId')
    this.isNew = this.getParamBool(raw, 'isNew')
    if (this.settingId !== '') {
      this.loadSetting()
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

  async loadSetting(): Promise<void> {
    const dao: WorldSettingDao = new WorldSettingDao()
    const model: WorldSettingModel | null = await dao.queryById(this.settingId)
    if (model !== null) {
      this.name = model.name
      this.category = model.category
      this.region = model.region
      this.description = model.description
      this.notes = model.notes
      this.bookId = model.bookId
    }
  }

  async save(): Promise<void> {
    if (this.name.trim() === '' || this.description.trim() === '') return
    const dao: WorldSettingDao = new WorldSettingDao()
    if (this.isNew || this.settingId === '') {
      const model: WorldSettingModel = {
        id: IdGenerator.generate(),
        bookId: this.bookId,
        name: this.name.trim(),
        category: this.category,
        region: this.region,
        description: this.description.trim(),
        notes: this.notes,
        content: ''
      }
      await dao.insert(model)
    } else {
      const model: WorldSettingModel = {
        id: this.settingId,
        bookId: this.bookId,
        name: this.name.trim(),
        category: this.category,
        region: this.region,
        description: this.description.trim(),
        notes: this.notes,
        content: ''
      }
      await dao.update(this.settingId, model)
    }
    router.back()
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() { Text('←').fontSize(20) }.width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { router.back() })
        Text(this.isNew ? '新建世界设定' : '世界设定详情')
          .fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Button('保存').fontSize(14).fontColor(GreenColors.G500).backgroundColor(Color.Transparent)
          .onClick(() => { this.save() })
      }
      .width('100%').height(56).padding({ left: 8, right: 8 })
      .backgroundColor(SemanticColors.BG_CARD)

      List({ space: 1 }) {
        ListItem() {
          Row() {
            Text('名称 *').fontSize(14).fontColor(GrayColors.G500).width(80)
            TextInput({ text: $$this.name, placeholder: '请输入名称' })
              .fontSize(14).fontColor(GrayColors.G900).layoutWeight(1)
              .backgroundColor(Color.Transparent)
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
        }

        ListItem() {
          Row() {
            Text('类别 *').fontSize(14).fontColor(GrayColors.G500).width(80)
            Row() {
              Text(this.categoryLabel(this.category))
                .fontSize(14).fontColor(GreenColors.G500).layoutWeight(1)
              Text('▼').fontSize(12).fontColor(GrayColors.G300)
            }
            .onClick(() => { this.showCategoryPicker = !this.showCategoryPicker })
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
        }

        if (this.showCategoryPicker) {
          ListItem() {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.categories, (cat: string) => {
                Text(this.categoryLabel(cat))
                  .fontSize(12)
                  .fontColor(cat === this.category ? '#FFFFFF' : GrayColors.G700)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .backgroundColor(cat === this.category ? GreenColors.G500 : GrayColors.G50)
                  .borderRadius(4)
                  .onClick(() => { this.category = cat; this.showCategoryPicker = false })
              }, (cat: string) => cat)
            }
            .width('100%').padding(12)
            .backgroundColor(SemanticColors.BG_CARD)
          }
        }

        ListItem() {
          Row() {
            Text('所属区域').fontSize(14).fontColor(GrayColors.G500).width(80)
            TextInput({ text: $$this.region, placeholder: '请输入所属区域' })
              .fontSize(14).fontColor(GrayColors.G900).layoutWeight(1)
              .backgroundColor(Color.Transparent)
          }
          .width('100%').height(48).padding({ left: 16, right: 16 })
          .backgroundColor(SemanticColors.BG_CARD)
        }

        ListItem() {
          Column() {
            Text('描述 *').fontSize(14).fontColor(GrayColors.G500).width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.description, placeholder: '请输入描述' })
              .fontSize(14).fontColor(GrayColors.G900).height(100)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)
        }

        ListItem() {
          Column() {
            Text('备注').fontSize(14).fontColor(GrayColors.G500).width('100%').padding({ left: 16, top: 12 })
            TextArea({ text: $$this.notes, placeholder: '请输入备注' })
              .fontSize(14).fontColor(GrayColors.G900).height(80)
              .backgroundColor(Color.Transparent).padding({ left: 16, right: 16 })
          }
          .width('100%').backgroundColor(SemanticColors.BG_CARD)
        }
      }
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor(SemanticColors.BG_PRIMARY)
  }
}
