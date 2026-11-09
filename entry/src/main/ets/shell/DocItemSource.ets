// 文稿列表的 LazyForEach 数据源
//
// 为什么需要它：列表原来是 `List + ForEach`，每次 build 都会把**全部**文稿行建出来；
// 文稿上百篇时，切换项目/搜索/改一篇摘要都会整列重建。LazyForEach 只建可视区附近的行。
//
// 与 store 的配合：
//  - 行内字段（标题/摘要/字数/选中态）是 @ObservedV2 + @Trace，就地更新即可刷新，不需要通知；
//  - 数组本身被整体替换（切项目/切文库/搜索/增删文稿）时由宿主调 reload() 通知重取。
//
// 注意：LazyForEach 的 dataSource **不能**事后重新赋值，改动一律走 reload()。
import { DocItem } from '../store/StoreModels'

export class DocItemSource implements IDataSource {
  private items: DocItem[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.items.length
  }

  getData(index: number): DocItem {
    return this.items[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener)
    if (at >= 0) {
      this.listeners.splice(at, 1)
    }
  }

  /** 整体替换（只传投影后的可见行） */
  reload(items: DocItem[]): void {
    this.items = items
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded()
    }
  }
}
