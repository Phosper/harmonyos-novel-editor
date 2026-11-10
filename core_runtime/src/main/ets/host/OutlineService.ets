// 大纲快照的宿主侧中转（ADR-003 §2.3：可选包只能通过宿主服务拿数据）
//
// 为什么需要它：导图在另一个包里，不能直接 import entry 的 EditorStore。
// 宿主打开导图前 publish 一份只读快照；导图点了某个主题就把"要回到哪个偏移"写回来，
// 宿主关闭导图时 take 走并定位。两个包都只依赖 core_runtime，不互相依赖。
//
// 可变状态放在 core_runtime（允许），契约包保持无状态。
import { OutlineSnapshot } from 'feature_contracts'
import { OutlineCommand } from 'feature_contracts'
import { OutlineExtras } from 'feature_contracts'
import { OutlineExtraCommand } from 'feature_contracts'

/**
 * 宿主注册的命令处理者：把命令翻成正文编辑，成功后返回**新的快照**。
 * 返回 null = 失败（导图页给提示，不改自己的显示）。
 */
export type OutlineCommandHandler = (command: OutlineCommand) => OutlineSnapshot | null

/**
 * 附加信息（概要/关系线）的处理者：改的是侧车，不碰正文。
 * 与结构命令一样同步返回新副本——落库由宿主异步排队。
 */
export type OutlineExtrasHandler = (command: OutlineExtraCommand) => OutlineExtras | null

class OutlineService {
  private snapshot: OutlineSnapshot | null = null
  private pendingReveal: number = -1
  /** 宿主注入；未注入时 dispatch 直接失败（导图只读） */
  private handler: OutlineCommandHandler | null = null
  /** 当前文稿的附加信息（概要/关系线）：不进正文，也不进快照版本号 */
  private extras: OutlineExtras = new OutlineExtras()
  private extrasHandler: OutlineExtrasHandler | null = null

  /** 发布当前文稿的大纲（导图页打开前调用） */
  publish(snapshot: OutlineSnapshot): void {
    this.snapshot = snapshot
  }

  /** 导图页读取；没有快照时返回 null（页面显示空态，不崩） */
  current(): OutlineSnapshot | null {
    return this.snapshot
  }

  /** 宿主在打开导图时注册；关闭后可置 null，避免泄漏页面 */
  setCommandHandler(handler: OutlineCommandHandler | null): void {
    this.handler = handler
  }

  /**
   * 导图发起的结构编辑。同步返回新快照（写正文是同步的内存操作，落库异步另行排队），
   * 调用方拿到后直接重排即可，不需要额外的"变更通知"通道。
   */
  dispatch(command: OutlineCommand): OutlineSnapshot | null {
    if (this.handler === null) {
      return null
    }
    const next: OutlineSnapshot | null = this.handler(command)
    if (next !== null) {
      this.snapshot = next
    }
    return next
  }

  /** 导图里点了某个主题：记下正文偏移，等宿主关闭后定位 */
  requestReveal(offset: number): void {
    this.pendingReveal = offset
  }

  /** 宿主在打开导图前发布附加信息（概要/关系线）；没有时发布空对象 */
  publishExtras(extras: OutlineExtras): void {
    this.extras = extras
  }

  /** 导图页读附加信息；宿主没发布过时返回空对象（不崩） */
  currentExtras(): OutlineExtras {
    return this.extras
  }

  setExtrasHandler(handler: OutlineExtrasHandler | null): void {
    this.extrasHandler = handler
  }

  /** 导图发起的附加信息编辑：成功返回新副本，失败返回 null */
  dispatchExtra(command: OutlineExtraCommand): OutlineExtras | null {
    if (this.extrasHandler === null) {
      return null
    }
    const next: OutlineExtras | null = this.extrasHandler(command)
    if (next !== null) {
      this.extras = next
    }
    return next
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
    this.extras = new OutlineExtras()
    this.extrasHandler = null
  }
}

const outlineHost: OutlineService = new OutlineService()

/** 全局唯一实例：同进程内所有包拿到的是同一份 */
export function outlineService(): OutlineService {
  return outlineHost
}
