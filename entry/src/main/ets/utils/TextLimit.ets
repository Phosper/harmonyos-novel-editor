// 正文容量守卫 —— 在入库前拦住超过 RdbStore 单条上限的正文
//
// 背景（官方文档依据）：
// RdbStore 通过共享内存传输数据，**单条数据必须严格小于 2MB**。
// 超限时 insert 可能"看起来成功"，但之后 query 用 getString 取该值会失败或抛异常
// —— 表现是文稿写进去了、再打开却读不出来，属于静默数据损坏。
//
// 为什么要按字节而不是 string.length：
// ArkTS 的 string.length 是 UTF-16 码元数，一个汉字占 1；
// 而 UTF-8 编码后一个汉字占 3 字节。中文长篇按 length 判断会低估约 3 倍，
// 等真正超限时已经晚了。这里统一换算成 UTF-8 字节数再比较。

/** 单条文稿正文入库上限（字节）。取 1.75MB 而非 2MB：给同行其他字段留余量 */
export const MAX_CONTENT_BYTES: number = 1792 * 1024

/**
 * 计算字符串的 UTF-8 字节数。
 * 不用 TextEncoder：它会为整篇正文分配一份等大字节数组，
 * 而超长正文正是这里最需要避免额外内存占用的场景。
 */
export function utf8ByteLength(text: string): number {
  let bytes: number = 0
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i)
    if (code < 0x80) {
      bytes += 1
    } else if (code < 0x800) {
      bytes += 2
    } else if (code >= 0xD800 && code <= 0xDBFF) {
      // 高位代理：与随后的低位代理合成一个码点，共 4 字节
      const next: number = i + 1 < text.length ? text.charCodeAt(i + 1) : 0
      if (next >= 0xDC00 && next <= 0xDFFF) {
        bytes += 4
        i++
      } else {
        // 落单的代理字符，按 3 字节计
        bytes += 3
      }
    } else {
      bytes += 3
    }
  }
  return bytes
}

/** 正文是否超出可入库上限 */
export function exceedsContentLimit(text: string): boolean {
  return utf8ByteLength(text) > MAX_CONTENT_BYTES
}

/** 面向用户的超限提示（说明原因并给出拆分建议） */
export function contentLimitMessage(): string {
  const mb: number = Math.floor(MAX_CONTENT_BYTES / 1024 / 1024 * 10) / 10
  return '正文超过单篇上限（约 ' + mb.toString() +
    'MB），请拆分为多篇保存。\n超长正文无法安全入库，强行写入会导致该篇内容无法再次打开。'
}

/**
 * 正文的「字数」——按用户感知的字符计，不按UTF-16 码元。
 *
 * 与超限判断不同，这里**不能**直接复用 GraphemeUtil：
 *  1. database/ 与 utils/ 是低层，不应反向依赖 editor/ 下的编辑器内部工具；
 *  2. 字数只需跳过代理对（每个代理对算1 字），不必处理 ZWJ 序列与修饰符。
 * 故在此给一个轻量实现，语义与 GraphemeUtil.graphemeLength 对齐。
 */
export function countChars(text: string): number {
  let count: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    // 高代理：若后面紧跟低代理，则这一对合起来算1 字
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next: number = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        i++;
      }
    }
    count++;
  }
  return count;
}
