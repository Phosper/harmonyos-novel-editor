// 中文长文"一键排版"工具（纯逻辑，编辑器无关）
//
// 面向中文小说/长文的常见整理动作，与竞品"一键排版"对齐：
//   1) 整理空行：把连续 3+ 个换行压成 1 个空行（2 个换行）
//   2) 段首缩进：每个非空段落以两个全角空格（U+3000）开头，去掉其它前导空白
//   3) 中英文之间加空格：CJK 与拉丁字母/数字相邻处补一个半角空格
// 均为幂等、可撤销（调用方在替换前会记录撤销点）。
// 刻意不包含"半角标点转全角"：中文写作里标点全半角混杂，自动转换风险高，留待用户手动。

export class FormatOptions {
  collapseBlankLines: boolean = true;
  indentParagraphs: boolean = true;
  spaceBetweenCjkAndLatin: boolean = true;
}

export class FormatResult {
  text: string = '';
  changed: number = 0;
}

/** 是否 CJK 统一表意文字（含扩展 A 的粗略区间，足够中文场景） */
function isCjk(code: number): boolean {
  return (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0xF900 && code <= 0xFAFF) ||
    (code >= 0x3000 && code <= 0x303F);
}

/** 是否拉丁字母或数字 */
function isLatinOrDigit(code: number): boolean {
  return (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    (code >= 0x30 && code <= 0x39);
}

export class TextFormat {
  /** 整理空行：连续 >=3 个 \n 压成 2 个（保留 1 个空行） */
  private static collapseBlankLines(text: string): string {
    return text.replace(new RegExp('\\n{3,}', 'g'), '\n\n');
  }

  /** 段首缩进：每段以两个全角空格开头（先清除前导空白） */
  private static indentParagraphs(text: string): string {
    const lines: string[] = text.split('\n');
    const out: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.trim() === '') {
        out.push('');
        continue;
      }
      // 去掉已有前导半角/全角空格，再统一加两个全角空格
      const body: string = line.replace(new RegExp('^[ \\u3000\\t]+'), '');
      out.push('\u3000\u3000' + body);
    }
    return out.join('\n');
  }

  /** 中英文之间加空格（CJK 与拉丁字母/数字相邻时补空格） */
  private static spaceBetweenCjkAndLatin(text: string): string {
    const out: string[] = [];
    for (let i = 0; i < text.length; i++) {
      const cur: number = text.charCodeAt(i);
      out.push(text.charAt(i));
      if (i + 1 >= text.length) {
        break;
      }
      const next: number = text.charCodeAt(i + 1);
      const cjkLatin: boolean = isCjk(cur) && isLatinOrDigit(next);
      const latinCjk: boolean = isLatinOrDigit(cur) && isCjk(next);
      if (cjkLatin || latinCjk) {
        out.push(' ');
      }
    }
    return out.join('');
  }

  /** 执行排版，返回新文本与"改动行/处"的粗略计数 */
  static format(text: string, options: FormatOptions): FormatResult {
    let out: string = text;
    if (options.collapseBlankLines) {
      out = TextFormat.collapseBlankLines(out);
    }
    if (options.indentParagraphs) {
      out = TextFormat.indentParagraphs(out);
    }
    if (options.spaceBetweenCjkAndLatin) {
      out = TextFormat.spaceBetweenCjkAndLatin(out);
    }
    const res = new FormatResult();
    res.text = out;
    // 粗略计数：变化的行数（用于提示"将修改 N 处"）
    const before: string[] = text.split('\n');
    const after: string[] = out.split('\n');
    let changed: number = 0;
    const n: number = Math.max(before.length, after.length);
    for (let i = 0; i < n; i++) {
      const b: string = i < before.length ? before[i] : '';
      const a: string = i < after.length ? after[i] : '';
      if (b !== a) {
        changed++;
      }
    }
    res.changed = changed;
    return res;
  }
}
