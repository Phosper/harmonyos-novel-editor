// EPUB → 单篇文稿（纯计算，可 Node 回归）
//
// 用户提出的第二种导入方式：不拆成几十篇，而是**一篇文稿 + 文内目录**：
//   目录（H1）
//   · 中文版序
//   · 前言
//   ...
//
//   中文版序（H1）
//   正文…
//
//   前言（H1）
//   正文…
//
// 章节名用 H1 写进格式边车，所以大纲/导图能直接长出来，不需要另存一份标题树。
import { FormatRun } from '../editor/flowtext/model/EditorTypes'
import { FormatCodec } from '../editor/flowtext/model/FormatCodec'
import type { EpubBook } from './EpubParser'

export interface MergedDocument {
  content: string
  runsJson: string
  /** 文内章节数（不含目录页） */
  chapterCount: number
}

/**
 * 合并为一篇。
 * @param withToc 是否在开头插入「目录」页（默认 true，用户要的"外挂目录页"）
 */
export function mergeEpubChapters(book: EpubBook, withToc: boolean): MergedDocument {
  let content: string = ''
  const runs: FormatRun[] = []
  const addLine = (text: string, heading: number): void => {
    const start: number = content.length
    content += text + '\n'
    if (heading > 0 && text.length > 0) {
      runs.push(new FormatRun(start, start + text.length, false, false, heading, 0))
    }
  }
  if (withToc && book.chapters.length > 0) {
    addLine('目录', 1)
    for (let i: number = 0; i < book.chapters.length; i++) {
      addLine('· ' + book.chapters[i].title, 0)
    }
    addLine('', 0)
  }
  for (let i: number = 0; i < book.chapters.length; i++) {
    const chapter = book.chapters[i]
    addLine(chapter.title, 1)
    const paragraphs: string[] = chapter.content.split('\n')
    for (let p: number = 0; p < paragraphs.length; p++) {
      addLine(paragraphs[p], 0)
    }
    addLine('', 0)
  }
  const merged: MergedDocument = {
    content: content,
    runsJson: FormatCodec.encode(runs),
    chapterCount: book.chapters.length
  }
  return merged
}
