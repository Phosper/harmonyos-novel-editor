// 唯一 ID 生成器
export class IdGenerator {
  static generate(): string {
    const ts: number = Date.now()
    const rand: string = Math.floor(Math.random() * 0xffffffff).toString(16)
    return 'wv_' + ts.toString(36) + '_' + rand
  }
}
