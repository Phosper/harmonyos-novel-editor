// 时间格式化工具 —— 灵感等列表统一展示，消除多处重复实现
export function formatDateTime(ts: number): string {
  const d: Date = new Date(ts)
  return (d.getMonth() + 1) + '月' + d.getDate() + '日 ' +
    d.getHours().toString().padStart(2, '0') + ':' + d.getMinutes().toString().padStart(2, '0')
}

/** 相对时间（列表用）：刚刚 / N 分钟前 / N 小时前 / 昨天 / M月D日 */
export function formatRelativeTime(ts: number): string {
  const diff: number = Date.now() - ts
  if (diff < 60000) return '刚刚'
  if (diff < 3600000) return Math.floor(diff / 60000).toString() + ' 分钟前'
  if (diff < 86400000) return Math.floor(diff / 3600000).toString() + ' 小时前'
  if (diff < 172800000) return '昨天'
  const d: Date = new Date(ts)
  const now: Date = new Date()
  if (d.getFullYear() === now.getFullYear()) {
    return (d.getMonth() + 1).toString() + '月' + d.getDate().toString() + '日'
  }
  return d.getFullYear().toString() + '年' + (d.getMonth() + 1).toString() + '月' +
    d.getDate().toString() + '日'
}
