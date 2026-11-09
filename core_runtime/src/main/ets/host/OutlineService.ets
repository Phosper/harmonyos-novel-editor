// 大纲快照的宿主侧中转（ADR-003 §2.3：可选包只能通过宿主服务拿数据）
//
// 为什么需要它：导图在另一个包里，不能直接 import entry 的 EditorStore。
// 宿主打开导图前 publish 一份只读快照；导图点了某个主题就把"要回到哪个偏移"写回来，
// 宿主关闭导图时 take 走并定位。两个包都只依赖 core_runtime，不互相依赖。
//
// 可变状态放在 core_runtime（允许），契约包保持无状态。
import { OutlineSnapshot } from 'feature_contracts'

class OutlineService {
  private snapshot: OutlineSnapshot | null = null
  private pendingReveal: number = -1

  /** 发布当前文稿的大纲（导图页打开前调用） */
  publish(snapshot: OutlineSnapshot): void {
    this.snapshot = snapshot
  }

  /** 导图页读取；没有快照时返回 null（页面显示空态，不崩） */
  current(): OutlineSnapshot | null {
    return this.snapshot
  }

  /** 导图里点了某个主题：记下正文偏移，等宿主关闭后定位 */
  requestReveal(offset: number): void {
    this.pendingReveal = offset
  }

  /** 宿主取走待定位偏移（取完即清，避免下次打开误跳） */
  takeReveal(): number {
    const offset: number = this.pendingReveal
    this.pendingReveal = -1
    return offset
  }

  /** 文稿关闭/切换时丢弃快照，防止拿旧文稿的大纲去定位新文稿 */
  clear(): void {
    this.snapshot = null
    this.pendingReveal = -1
  }
}

const outlineHost: OutlineService = new OutlineService()

/** 全局唯一实例：同进程内所有包拿到的是同一份 */
export function outlineService(): OutlineService {
  return outlineHost
}
