/**
 * 格式标注的紧凑序列化（T025 持久化边车）
 *
 * 采用 "start,end,bold,italic,heading" 以 ';' 连接的自描述串，避免 JSON 反序列化在
 * ArkTS 下的类型强转开销与限制；旧数据（空串）解码为"无格式"即纯文本。
 */
import { FormatRun } from './EditorTypes';

export class FormatCodec {
  static encode(runs: FormatRun[]): string {
    const parts: string[] = [];
    for (let i = 0; i < runs.length; i++) {
      const r: FormatRun = runs[i];
      const b: string = r.bold ? '1' : '0';
      const it: string = r.italic ? '1' : '0';
      // 第 6 段 indent 为可选扩展：旧数据没有该段也能解出（缺省 0）
      parts.push(r.startOffset.toString() + ',' + r.endOffset.toString() + ',' + b + ',' + it + ',' +
        r.heading.toString() + ',' + r.indent.toString());
    }
    return parts.join(';');
  }

  static decode(s: string): FormatRun[] {
    const out: FormatRun[] = [];
    if (s === '') {
      return out;
    }
    const parts: string[] = s.split(';');
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i];
      if (seg === '') {
        continue;
      }
      const f: string[] = seg.split(',');
      if (f.length < 5) {
        continue;
      }
      const indent: number = f.length > 5 ? Number(f[5]) : 0;
      out.push(new FormatRun(Number(f[0]), Number(f[1]), f[2] === '1', f[3] === '1', Number(f[4]),
        isNaN(indent) ? 0 : indent));
    }
    return out;
  }
}
