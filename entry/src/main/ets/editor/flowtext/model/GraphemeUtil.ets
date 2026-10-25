/** Unicode 17 extended grapheme boundaries (UAX #29); offsets remain UTF-16. */
import { GRAPHEME_BREAK_DATA, EXTENDED_PICTOGRAPHIC_DATA, INDIC_CONJUNCT_DATA } from './UnicodeGraphemeData';

function property(code: number, ranges: number[]): number {
  let lo: number = 0;
  let hi: number = ranges.length / 3 - 1;
  while (lo <= hi) {
    const mid: number = Math.floor((lo + hi) / 2);
    if (code < ranges[mid * 3]) { hi = mid - 1; }
    else if (code > ranges[mid * 3 + 1]) { lo = mid + 1; }
    else { return ranges[mid * 3 + 2]; }
  }
  return 0;
}
function gcb(code: number): number {
  if (code >= 0xAC00 && code <= 0xD7A3) { return (code - 0xAC00) % 28 === 0 ? 12 : 13; }
  return property(code, GRAPHEME_BREAK_DATA);
}
function previous(text: string, at: number): number {
  let p: number = at - 1;
  if (p > 0 && text.charCodeAt(p) >= 0xDC00 && text.charCodeAt(p) <= 0xDFFF &&
    text.charCodeAt(p - 1) >= 0xD800 && text.charCodeAt(p - 1) <= 0xDBFF) { p--; }
  return p;
}
function codeAt(text: string, at: number): number {
  const code: number | undefined = text.codePointAt(at);
  return code === undefined ? 0 : code;
}
export class GraphemeUtil {
  static isBoundary(text: string, offset: number): boolean {
    if (offset <= 0 || offset >= text.length) { return true; }
    if (previous(text, offset + 1) < offset) { return false; }
    const left: number = previous(text, offset);
    const a: number = gcb(codeAt(text, left));
    const b: number = gcb(codeAt(text, offset));
    if (a === 1 && b === 2) { return false; }
    if (a === 1 || a === 2 || a === 3 || b === 1 || b === 2 || b === 3) { return true; }
    if (a === 9 && (b === 9 || b === 10 || b === 12 || b === 13)) { return false; }
    if ((a === 12 || a === 10) && (b === 10 || b === 11)) { return false; }
    if ((a === 13 || a === 11) && b === 11) { return false; }
    if (b === 4 || b === 5 || b === 8 || a === 7) { return false; }
    // GB9c: Indic consonant + Extend/Linker sequence containing a Linker.
    if (property(codeAt(text, offset), INDIC_CONJUNCT_DATA) === 1) {
      let p: number = left;
      let linker: boolean = false;
      while (p >= 0) {
        const kind: number = property(codeAt(text, p), INDIC_CONJUNCT_DATA);
        if (kind === 2) { linker = true; }
        else if (kind !== 3) {
          if (kind === 1 && linker) { return false; }
          break;
        }
        p = previous(text, p);
      }
    }
    // GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic.
    if (a === 5 && property(codeAt(text, offset), EXTENDED_PICTOGRAPHIC_DATA) === 1) {
      let p: number = previous(text, left);
      while (p >= 0 && gcb(codeAt(text, p)) === 4) { p = previous(text, p); }
      if (p >= 0 && property(codeAt(text, p), EXTENDED_PICTOGRAPHIC_DATA) === 1) { return false; }
    }
    if (a === 6 && b === 6) {
      let count: number = 0;
      let p: number = left;
      while (p >= 0 && gcb(codeAt(text, p)) === 6) { count++; p = previous(text, p); }
      if (count % 2 === 1) { return false; }
    }
    return true;
  }
  static snapToBoundary(text: string, offset: number): number {
    let at: number = Number.isFinite(offset) ? Math.max(0, Math.min(Math.floor(offset), text.length)) : 0;
    while (at > 0 && !GraphemeUtil.isBoundary(text, at)) { at--; }
    return at;
  }
  static moveLeft(text: string, offset: number): number {
    const at: number = GraphemeUtil.snapToBoundary(text, offset);
    return at <= 0 ? 0 : GraphemeUtil.snapToBoundary(text, previous(text, at));
  }
  static moveRight(text: string, offset: number): number {
    const at: number = GraphemeUtil.snapToBoundary(text, offset);
    if (at >= text.length) { return text.length; }
    let next: number = at + (codeAt(text, at) > 0xFFFF ? 2 : 1);
    while (next < text.length && !GraphemeUtil.isBoundary(text, next)) {
      next += codeAt(text, next) > 0xFFFF ? 2 : 1;
    }
    return next;
  }
  static graphemeLength(text: string): number {
    let count: number = 0;
    let at: number = 0;
    while (at < text.length) { count++; at = GraphemeUtil.moveRight(text, at); }
    return count;
  }
}
