// 导图附加信息（概要 / 关系线）的读写。
//
// 设计取舍：
//  - 一张文稿的附加信息最多几十行，所以"整篇覆盖"（先删后插）比增量 diff 可靠得多，
//    也避免"删了段落，概要还指着不存在的 paraId"这类脏数据。
//  - 每章一条查询，不用 IN 列表：备份导出是一次性动作，换来的是不依赖原生 SQL，
//    本地回归的库替身也能覆盖到。
import { relationalStore } from '@kit.ArkData'
import { dbHelper } from '../database/DatabaseHelper'
import { MapSummaryDao, MapRelationDao, MapNodeDao, MapBoundaryDao } from '../database/MapExtraDao'
import { OutlineExtras, OutlineSummary, OutlineRelation, OutlineNodeStyle, OutlineBoundary } from 'feature_contracts'
import { Logger } from '../utils/Logger'
import { IdGenerator } from '../utils/IdGenerator'

/** 备份里的一行概要（带 chapterId，恢复时按章节重映射） */
export interface MapSummaryBackupRow {
  chapterId: string
  id: string
  startParaId: string
  endParaId: string
  text: string
}

/** 备份里的一行关系线 */
export interface MapRelationBackupRow {
  chapterId: string
  id: string
  fromParaId: string
  toParaId: string
  label: string
}

/** 备份里的一行外框 */
export interface MapBoundaryBackupRow {
  chapterId: string
  id: string
  startParaId: string
  endParaId: string
  text: string
}

/** 备份里的一行节点样式 */
export interface MapNodeStyleBackupRow {
  chapterId: string
  paraId: string
  shape: string
  fill: string
  bold: boolean
  markers: string[]
  label: string
}

export interface MapExtraBackupBundle {
  summaries: MapSummaryBackupRow[]
  relations: MapRelationBackupRow[]
  boundaries: MapBoundaryBackupRow[]
  nodeStyles: MapNodeStyleBackupRow[]
}

export interface MapExtraBackupLoose {
  summaries?: MapSummaryBackupRow[]
  relations?: MapRelationBackupRow[]
  boundaries?: MapBoundaryBackupRow[]
  nodeStyles?: MapNodeStyleBackupRow[]
}

export class MapExtraRepository {
  private readonly tx: relationalStore.Transaction | null

  constructor(tx: relationalStore.Transaction | null = null) {
    this.tx = tx
  }

  private summaryDao(): MapSummaryDao {
    return new MapSummaryDao(this.tx)
  }

  private relationDao(): MapRelationDao {
    return new MapRelationDao(this.tx)
  }

  private nodeDao(): MapNodeDao {
    return new MapNodeDao(this.tx)
  }

  private boundaryDao(): MapBoundaryDao {
    return new MapBoundaryDao(this.tx)
  }

  /** 读一篇文稿的附加信息；没有就是空对象（导图页照常渲染） */
  async load(chapterId: string): Promise<OutlineExtras> {
    const extras: OutlineExtras = new OutlineExtras()
    extras.docId = chapterId
    if (chapterId === '') {
      return extras
    }
    extras.summaries = await this.summaryDao().listByDoc(chapterId)
    extras.relations = await this.relationDao().listByDoc(chapterId)
    extras.boundaries = await this.boundaryDao().listByDoc(chapterId)
    extras.nodeStyles = await this.nodeDao().listByDoc(chapterId)
    return extras
  }

  /** 整篇覆盖：删掉这篇的全部附加信息，再按当前内存副本重写 */
  async replace(chapterId: string, extras: OutlineExtras): Promise<void> {
    if (chapterId === '') {
      return
    }
    if (this.tx !== null) {
      await this.replaceRows(chapterId, extras)
      return
    }
    const tx: relationalStore.Transaction = await dbHelper.beginTransaction()
    try {
      await new MapExtraRepository(tx).replaceRows(chapterId, extras)
      await tx.commit()
    } catch (e) {
      try {
        await tx.rollback()
      } catch (rollbackError) {
        Logger.error('Map extra rollback failed: ' + String(rollbackError))
      }
      throw new Error(String(e))
    }
  }

  private async replaceRows(chapterId: string, extras: OutlineExtras): Promise<void> {
    const summaryDao: MapSummaryDao = this.summaryDao()
    const relationDao: MapRelationDao = this.relationDao()
    const nodeDao: MapNodeDao = this.nodeDao()
    const boundaryDao: MapBoundaryDao = this.boundaryDao()
    await summaryDao.deleteByDoc(chapterId)
    await relationDao.deleteByDoc(chapterId)
    await nodeDao.deleteByDoc(chapterId)
    await boundaryDao.deleteByDoc(chapterId)
    const now: number = Date.now()
    for (let i: number = 0; i < extras.summaries.length; i++) {
      await summaryDao.insertSummary(chapterId, extras.summaries[i], now + i)
    }
    for (let i: number = 0; i < extras.relations.length; i++) {
      await relationDao.insertRelation(chapterId, extras.relations[i], now + i)
    }
    for (let i: number = 0; i < extras.boundaries.length; i++) {
      await boundaryDao.insertBoundary(chapterId, extras.boundaries[i], now + i)
    }
    for (let i: number = 0; i < extras.nodeStyles.length; i++) {
      await nodeDao.insertStyle(chapterId, extras.nodeStyles[i], now + i)
    }
  }

  /** 备份导出：按章节逐篇读（调用方给的是本书的全部章节 id） */
  async exportByChapterIds(chapterIds: string[]): Promise<MapExtraBackupBundle> {
    const summaries: MapSummaryBackupRow[] = []
    const relations: MapRelationBackupRow[] = []
    const boundaries: MapBoundaryBackupRow[] = []
    const nodeStyles: MapNodeStyleBackupRow[] = []
    for (let i: number = 0; i < chapterIds.length; i++) {
      const chapterId: string = chapterIds[i]
      const one: OutlineExtras = await this.load(chapterId)
      for (let k: number = 0; k < one.summaries.length; k++) {
        const s: OutlineSummary = one.summaries[k]
        summaries.push({
          chapterId: chapterId,
          id: s.id,
          startParaId: s.startParaId,
          endParaId: s.endParaId,
          text: s.text
        })
      }
      for (let k: number = 0; k < one.relations.length; k++) {
        const r: OutlineRelation = one.relations[k]
        relations.push({
          chapterId: chapterId,
          id: r.id,
          fromParaId: r.fromParaId,
          toParaId: r.toParaId,
          label: r.label
        })
      }
      for (let k: number = 0; k < one.boundaries.length; k++) {
        const b: OutlineBoundary = one.boundaries[k]
        boundaries.push({
          chapterId: chapterId,
          id: b.id,
          startParaId: b.startParaId,
          endParaId: b.endParaId,
          text: b.text
        })
      }
      for (let k: number = 0; k < one.nodeStyles.length; k++) {
        const n: OutlineNodeStyle = one.nodeStyles[k]
        nodeStyles.push({
          chapterId: chapterId,
          paraId: n.paraId,
          shape: n.shape,
          fill: n.fill,
          bold: n.bold,
          markers: n.markers,
          label: n.label
        })
      }
    }
    return { summaries: summaries, relations: relations, boundaries: boundaries, nodeStyles: nodeStyles }
  }

  /**
   * 备份恢复：章节 id 全部换成新的，附加信息自己的 id 也重新发号，
   * 免得两份备份里的 id 撞车。找不到对应章节的行直接丢（正文都没了，附加信息没有落点）。
   */
  async restoreRows(input: MapExtraBackupLoose, chapterIdMap: Map<string, string>): Promise<void> {
    const summaries: MapSummaryBackupRow[] = input.summaries ?? []
    const relations: MapRelationBackupRow[] = input.relations ?? []
    const boundaries: MapBoundaryBackupRow[] = input.boundaries ?? []
    const nodeStyles: MapNodeStyleBackupRow[] = input.nodeStyles ?? []
    const now: number = Date.now()
    for (let i: number = 0; i < summaries.length; i++) {
      const row: MapSummaryBackupRow = summaries[i]
      const mapped: string | undefined = chapterIdMap.get(row.chapterId)
      if (mapped === undefined || mapped === '') {
        continue
      }
      await this.summaryDao().insertSummary(mapped,
        new OutlineSummary(IdGenerator.generate(), row.startParaId, row.endParaId, row.text), now + i)
    }
    for (let i: number = 0; i < relations.length; i++) {
      const row: MapRelationBackupRow = relations[i]
      const mapped: string | undefined = chapterIdMap.get(row.chapterId)
      if (mapped === undefined || mapped === '') {
        continue
      }
      await this.relationDao().insertRelation(mapped,
        new OutlineRelation(IdGenerator.generate(), row.fromParaId, row.toParaId, row.label), now + i)
    }
    for (let i: number = 0; i < boundaries.length; i++) {
      const row: MapBoundaryBackupRow = boundaries[i]
      const mapped: string | undefined = chapterIdMap.get(row.chapterId)
      if (mapped === undefined || mapped === '') {
        continue
      }
      await this.boundaryDao().insertBoundary(mapped,
        new OutlineBoundary(IdGenerator.generate(), row.startParaId, row.endParaId, row.text), now + i)
    }
    for (let i: number = 0; i < nodeStyles.length; i++) {
      const row: MapNodeStyleBackupRow = nodeStyles[i]
      const mapped: string | undefined = chapterIdMap.get(row.chapterId)
      if (mapped === undefined || mapped === '') {
        continue
      }
      const style: OutlineNodeStyle = new OutlineNodeStyle(row.paraId)
      style.shape = row.shape
      style.fill = row.fill
      style.bold = row.bold
      style.markers = row.markers
      style.label = row.label
      await this.nodeDao().insertStyle(mapped, style, now + i)
    }
  }
}
