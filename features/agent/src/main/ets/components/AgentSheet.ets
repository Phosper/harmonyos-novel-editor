import { GrayColors, GreenColors, SemanticColors, IdGenerator } from '@ohos/common'
import { BookDao, ChapterDao } from '@ohos/editor'
import { CharacterDao } from '@ohos/material'
import type { ChapterModel, CharacterModel } from '@ohos/common'

enum QuickCommand {
  WRITING_STATS = 'writing_stats',
  LAST_POSITION = 'last_position',
  CHARACTER_OVERVIEW = 'character_overview'
}

interface ChatMessage {
  id: string
  role: string
  content: string
  timestamp: number
}

interface QuickCommandItem {
  cmd: QuickCommand
  label: string
}

const QUICK_COMMANDS: QuickCommandItem[] = [
  { cmd: QuickCommand.WRITING_STATS, label: '📊 当前写作统计' },
  { cmd: QuickCommand.LAST_POSITION, label: '📍 上次写到哪了' },
  { cmd: QuickCommand.CHARACTER_OVERVIEW, label: '👤 人物设定快览' }
]

@Component
export struct AgentSheet {
  @Prop currentBookId: string = ''
  @Prop currentChapterId: string = ''
  @Prop chapterTitle: string = ''
  @Prop chapterContent: string = ''
  @State messages: ChatMessage[] = []
  @State inputText: string = ''
  @State showQuickCommands: boolean = true
  private scroller: Scroller = new Scroller()

  addMessage(role: string, content: string): void {
    const msg: ChatMessage = {
      id: IdGenerator.generate(),
      role: role,
      content: content,
      timestamp: Date.now()
    }
    this.messages = this.messages.concat([msg])
    this.showQuickCommands = false
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  async handleQuickCommand(cmd: QuickCommand): Promise<void> {
    const label: string = QUICK_COMMANDS.find((item) => item.cmd === cmd)?.label ?? ''
    if (label === '') {
      return
    }
    this.addMessage('user', label)

    let reply: string = ''

    if (cmd === QuickCommand.WRITING_STATS) {
      if (this.currentBookId === '') {
        reply = '⚠️ 请先在侧边栏选择一本书籍。'
      } else {
        const bookDao: BookDao = new BookDao()
        const chapterDao: ChapterDao = new ChapterDao()
        const bookName: string = (await bookDao.queryById(this.currentBookId))?.name ?? '未知'
        const chapters: ChapterModel[] = await chapterDao.queryByBook(this.currentBookId)
        let totalWords: number = 0
        for (let i = 0; i < chapters.length; i++) {
          totalWords += chapters[i].wordCount
        }
        reply = '📖 **《' + bookName + '》写作统计**\n\n' +
          '• 总章节数：' + chapters.length + ' 章\n' +
          '• 总字数：' + totalWords + ' 字\n' +
          '• 平均每章：' + (chapters.length > 0 ? Math.floor(totalWords / chapters.length) : 0) + ' 字'
      }
    }

    if (cmd === QuickCommand.LAST_POSITION) {
      if (this.currentChapterId === '') {
        reply = '⚠️ 请先在侧边栏选择一个章节。'
      } else {
        const dao: ChapterDao = new ChapterDao()
        const chapter: ChapterModel | null = await dao.queryById(this.currentChapterId)
        if (chapter === null) {
          reply = '⚠️ 未找到当前章节。'
        } else {
          const endContent: string = chapter.content.length > 80
            ? chapter.content.substring(chapter.content.length - 80) : chapter.content
          reply = '📍 **上次编辑**\n\n' +
            '• 章节：' + chapter.title + '\n' +
            '• 字数：' + chapter.wordCount + ' 字\n' +
            '• 上次更新：' + new Date(chapter.updatedAt).toLocaleString() + '\n\n' +
            '末尾内容：\n> ' + (endContent !== '' ? endContent : '（空）')
        }
      }
    }

    if (cmd === QuickCommand.CHARACTER_OVERVIEW) {
      if (this.currentBookId === '') {
        reply = '⚠️ 请先在侧边栏选择一本书籍。'
      } else {
        const dao: CharacterDao = new CharacterDao()
        const chars: CharacterModel[] = await dao.queryByBook(this.currentBookId)
        if (chars.length === 0) {
          reply = '📝 当前书籍暂无人物设定，去「素材」页创建吧。'
        } else {
          const lines: string[] = ['👤 **人物设定快览**（共 ' + chars.length + ' 人）\n']
          for (let i = 0; i < chars.length; i++) {
            const c: CharacterModel = chars[i]
            const parts: string[] = ['### ' + c.name]
            if (c.alias !== '') {
              parts.push('（' + c.alias + '）')
            }
            if (c.age !== '') {
              parts.push(', ' + c.age + '岁')
            }
            if (c.personality !== '') {
              parts.push('\n性格：' + c.personality)
            }
            if (c.appearance !== '') {
              parts.push('\n外貌：' + c.appearance)
            }
            if (c.background !== '') {
              parts.push('\n背景：' + c.background)
            }
            lines.push(parts.join(''))
          }
          reply = lines.join('\n\n')
        }
      }
    }

    this.addMessage('assistant', reply)
  }

  build() {
    Column() {
      if (this.messages.length === 0) {
        Column() {
          Text('AI 写作伴侣').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(GrayColors.G900)
            .padding({ top: 16, bottom: 8 })

          Text('你好！我是 Weaver 写作伴侣，可以帮你统计写作进度、回顾上次编辑位置、查看人物设定。')
            .fontSize(13)
            .fontColor(GrayColors.G500)
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16, bottom: 16 })
            .width('100%')
        }
        .width('100%')
      }

      List({ scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            Row() {
              if (msg.role === 'assistant') {
                Column() {
                  Text(msg.content)
                    .fontSize(14)
                    .fontColor(GrayColors.G900)
                    .padding(12)
                    .backgroundColor(SemanticColors.BG_SURFACE)
                    .borderRadius({ topLeft: 4, topRight: 12, bottomLeft: 12, bottomRight: 12 })
                    .constraintSize({ maxWidth: '80%' })
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              } else {
                Column() {
                  Text(msg.content)
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .padding(12)
                    .backgroundColor(GreenColors.G500)
                    .borderRadius({ topLeft: 12, topRight: 4, bottomLeft: 12, bottomRight: 12 })
                    .constraintSize({ maxWidth: '80%' })
                }
                .alignItems(HorizontalAlign.End)
                .width('100%')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              }
            }
            .width('100%')
          }
        }, (msg: ChatMessage) => msg.id)
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)

      if (this.showQuickCommands && this.currentBookId !== '') {
        Row({ space: 8 }) {
          ForEach(QUICK_COMMANDS, (item: QuickCommandItem) => {
            Button(item.label)
              .fontSize(12)
              .height(32)
              .padding({ left: 12, right: 12 })
              .backgroundColor(GrayColors.G50)
              .fontColor(GrayColors.G700)
              .borderRadius(16)
              .onClick(() => { this.handleQuickCommand(item.cmd) })
          }, (item: QuickCommandItem) => item.cmd)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }

      Row({ space: 8 }) {
        TextInput({ text: $$this.inputText, placeholder: '输入消息...' })
          .fontSize(14)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(SemanticColors.BG_SURFACE)
          .borderRadius(20)
          .padding({ left: 16, right: 16 })

        Button('发送')
          .fontSize(13)
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(GreenColors.G500)
          .fontColor('#FFFFFF')
          .borderRadius(20)
          .onClick(() => {
            if (this.inputText.trim() === '') return
            this.addMessage('user', this.inputText.trim())
            this.inputText = ''
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor(SemanticColors.BG_CARD)
      .border({ width: { top: 1 }, color: SemanticColors.BORDER_DEFAULT })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(SemanticColors.BG_CARD)
  }
}
