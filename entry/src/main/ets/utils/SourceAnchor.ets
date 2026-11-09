// 来源锚解析（交接稿 R3 / F06）
//
// 问题：摘录存的是"当时的偏移 + 指纹"，原文前面插入一段之后旧偏移就指向别处了。
// 旧实现直接 `revealOffset(startOff)`，等于"假装还准"。
//
// 这里给出四态结果，调用方按状态决定是跳、是提示、还是拒绝：
//   EXACT      原位未变（偏移与摘录都对得上）
//   RELOCATED  原位漂移，按摘录文字重新找到唯一位置
//   AMBIGUOUS  找到多处相同文字：取离原位置最近的一处，但必须提示用户核对
//   MISSING    找不到（原文已改 / 摘录为空 / 文稿不匹配）
//
// 纯函数、无 UI 依赖，可在 Node 里直接回归。
import { canvasFingerprint } from '../editor/CanvasCapture'

export enum AnchorState {
  EXACT = 0,
  RELOCATED = 1,
  AMBIGUOUS = 2,
  MISSING = 3
}

export interface AnchorResolution {
  state: AnchorState
  /** 可用于滚动的起点；MISSING 时等于原值，调用方不应使用 */
  start: number
  end: number
  /** 给用户看的一句话（EXACT 为空串） */
  message: string
}

function clampOffset(value: number, lo: number, hi: number): number {
  if (!Number.isFinite(value)) {
    return lo
  }
  return Math.max(lo, Math.min(hi, value))
}

export class SourceAnchorResolver {
  /**
   * @param text 目标文稿的**当前**正文
   * @param startOff 摘录时记录的起点
   * @param endOff 摘录时记录的终点
   * @param quoteText 摘录时的原文快照（可能为空：早期数据没存）
   * @param fingerprint 摘录时的指纹（可能为空）
   */
  static resolve(text: string, startOff: number, endOff: number,
    quoteText: string, fingerprint: string): AnchorResolution {
    const start: number = clampOffset(startOff, 0, text.length)
    const end: number = clampOffset(endOff, start, text.length)
    const quote: string = quoteText === undefined || quoteText === null ? '' : quoteText
    const print: string = fingerprint === undefined || fingerprint === null ? '' : fingerprint
    const inPlace: string = text.substring(start, end)
    // 1) 原位未变：有摘录就比摘录，没摘录就比指纹（早期数据）
    if (end > start) {
      if (quote !== '' && inPlace === quote) {
        return { state: AnchorState.EXACT, start: start, end: end, message: '' }
      }
      if (quote === '' && print !== '' && canvasFingerprint(inPlace) === print) {
        return { state: AnchorState.EXACT, start: start, end: end, message: '' }
      }
    }
    // 2) 没有可用来重定位的摘录：不能凭空猜位置
    if (quote.trim() === '') {
      return {
        state: AnchorState.MISSING, start: start, end: end,
        message: '这条摘录没有保存原文快照，无法确认位置'
      }
    }
    // 3) 全文找摘录：要求整段原文出现（不做模糊匹配，避免"看起来对"的错跳）
    const hits: number[] = []
    let from: number = 0
    for (;;) {
      const at: number = text.indexOf(quote, from)
      if (at < 0) {
        break
      }
      hits.push(at)
      from = at + 1
    }
    if (hits.length === 0) {
      return {
        state: AnchorState.MISSING, start: start, end: end,
        message: '原文已修改，找不到这段摘录'
      }
    }
    if (hits.length === 1) {
      const only: number = hits[0]
      return {
        state: AnchorState.RELOCATED, start: only, end: only + quote.length,
        message: '原文位置已变化，已按摘录重新定位'
      }
    }
    // 多处命中：取离原位置最近的一处，但标记为"需要核对"
    let best: number = hits[0]
    let bestDistance: number = Math.abs(best - start)
    for (let i: number = 1; i < hits.length; i++) {
      const distance: number = Math.abs(hits[i] - start)
      if (distance < bestDistance) {
        best = hits[i]
        bestDistance = distance
      }
    }
    return {
      state: AnchorState.AMBIGUOUS, start: best, end: best + quote.length,
      message: '找到 ' + hits.length.toString() + ' 处相同文字，已定位到最接近原位置的一处，请核对'
    }
  }
}
