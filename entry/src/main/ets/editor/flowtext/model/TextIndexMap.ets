/**
 * Explicit conversion at native APIs: Unicode scalar index vs UTF-16 offset.
 *
 * 只维护 utf16 一张表：原来的 utf8 表同样按码点逐字 push，但
 * toUtf8/fromUtf8 在整个工程（含 ohosTest）**没有任何调用点** ——
 * 这个类是每次 typeset 都要重建的（见 TextLayoutEngine.buildTypesetWindow），
 * 等于每次都白做一半的 O(n) 分配与内存占用，在长文上是纯浪费。
 */
export class TextIndexMap {
  private utf16: number[] = [0];
  constructor(value: string = '') {
    let at: number = 0;
    while (at < value.length) {
      const point: number | undefined = value.codePointAt(at);
      const code: number = point === undefined ? 0 : point;
      at += code > 0xFFFF ? 2 : 1;
      this.utf16.push(at);
    }
  }
  private floorIndex(values: number[], offset: number): number {
    let lo: number = 0;
    let hi: number = values.length - 1;
    while (lo < hi) {
      const mid: number = Math.ceil((lo + hi) / 2);
      if (values[mid] <= offset) { lo = mid; } else { hi = mid - 1; }
    }
    return lo;
  }
  toScalar(offset: number): number { return this.floorIndex(this.utf16, offset); }
  fromScalar(index: number): number { return this.utf16[Math.max(0, Math.min(Math.floor(index), this.utf16.length - 1))]; }
  /** Lines retain only their own mapping, so old prefix lines do not retain whole-document tables. */
  slice(start: number, end: number): TextIndexMap {
    const result: TextIndexMap = new TextIndexMap();
    const first: number = this.toScalar(start);
    const last: number = this.toScalar(end);
    result.utf16 = [];
    for (let i: number = first; i <= last; i++) {
      result.utf16.push(this.utf16[i] - start);
    }
    return result;
  }
}
