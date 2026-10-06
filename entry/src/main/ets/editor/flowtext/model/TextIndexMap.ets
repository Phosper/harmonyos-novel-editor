/** Explicit conversion at native APIs: Unicode scalar index, UTF-8 byte index and UTF-16 offset. */
export class TextIndexMap {
  private utf16: number[] = [0];
  private utf8: number[] = [0];
  constructor(value: string = '') {
    let at: number = 0;
    let bytes: number = 0;
    while (at < value.length) {
      const point: number | undefined = value.codePointAt(at);
      const code: number = point === undefined ? 0 : point;
      at += code > 0xFFFF ? 2 : 1;
      bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
      this.utf16.push(at);
      this.utf8.push(bytes);
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
  toUtf8(offset: number): number { return this.utf8[this.toScalar(offset)]; }
  fromUtf8(offset: number): number { return this.utf16[this.floorIndex(this.utf8, offset)]; }
  /** Lines retain only their own mapping, so old prefix lines do not retain whole-document tables. */
  slice(start: number, end: number): TextIndexMap {
    const result: TextIndexMap = new TextIndexMap();
    const first: number = this.toScalar(start);
    const last: number = this.toScalar(end);
    result.utf16 = [];
    result.utf8 = [];
    for (let i: number = first; i <= last; i++) {
      result.utf16.push(this.utf16[i] - start);
      result.utf8.push(this.utf8[i] - this.utf8[first]);
    }
    return result;
  }
}
