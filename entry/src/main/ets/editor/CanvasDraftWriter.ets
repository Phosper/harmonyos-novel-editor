/**
 * 思路板 → 初稿生成器（D · 编辑器桥，纯逻辑，可被 Node 回归直接执行）
 *
 * 输入：写作卡的子卡大纲行（canvasFlatten 的结果）+ 卡片查询回调 + 素材列表。
 * 输出：{ content, runs, runsJson }，交给调用方新建文稿后落库（本文件不碰数据库）。
 *
 * 两条硬规则（见 docs/design/canvas-contract.md §1 / 桌面交接文档 §6.6）：
 *   1. **content 里绝不写 `#`**：标题级别只存在 format_runs.heading 里，
 *      导出时才由 utils/ExportService.applyMarkdown 合成 Markdown 前缀。
 *   2. 每个节点（章 / 节 / 目）末尾留一段 `【待展开】`，正文是纯文本、不带格式标注。
 *
 * 偏移约定与编辑器一致：FormatRun 的区间是 [start, end) 且**含段末换行符**
 * （TextDocument.paragraphAttrsBounds 同款语义），否则"整行加标题"在导出时读不到级别。
 */
import { CanvasCardData, CanvasEvidenceData, CanvasEvidenceKind, CanvasOutlineRow } from '../model/CanvasTypes';
import { FormatRun } from './flowtext/model/EditorTypes';
import { FormatCodec } from './flowtext/model/FormatCodec';

/** 每节末尾的占位段（纯文本，不带任何标注） */
const CANVAS_DRAFT_PENDING_MARK: string = '【待展开】';
/** 标题级别上限：对应 CANVAS_MAX_DEPTH（章 / 节 / 目） */
const CANVAS_DRAFT_MAX_HEADING: number = 3;

export interface CanvasDraftInput {
  /** 写作卡的子卡大纲：canvasFlatten 的结果，深度优先、同级已按 ord 排好 */
  rows: CanvasOutlineRow[]
  /** 素材全集：数组顺序即落稿顺序；按 cardId 归属到各节点 */
  evidence: CanvasEvidenceData[]
  /** 卡片查询回调：取标题用；返回 undefined 时该节点标题按空串写（不阻断生成） */
  cardOf: (cardId: string) => CanvasCardData | undefined
  /** 写作卡自己的素材（可选；非空时放在所有章节之前，不加标题） */
  rootEvidence?: CanvasEvidenceData[]
}

export interface CanvasDraftResult {
  /** 纯正文，不含 `#` */
  content: string
  /** 只含标题级 run（heading 1/2/3），正文段落不带标注 */
  runs: FormatRun[]
  /** FormatCodec.encode(runs)：可直接写 chapter.runsJson */
  runsJson: string
}

export class CanvasDraftWriter {
  /**
   * 生成初稿。空大纲 → 空稿（content='' / runs=[] / runsJson=''），调用方不必特判。
   */
  static build(input: CanvasDraftInput): CanvasDraftResult {
    const parts: string[] = [];
    const runs: FormatRun[] = [];
    const grouped: Map<string, CanvasEvidenceData[]> = CanvasDraftWriter.groupEvidence(input.evidence);
    let offset: number = 0;
    const rootBlock: string = CanvasDraftWriter.evidenceBlockFromList(input.rootEvidence);
    if (rootBlock !== '') {
      parts.push(rootBlock);
      offset += rootBlock.length;
    }
    for (let i: number = 0; i < input.rows.length; i++) {
      const row: CanvasOutlineRow = input.rows[i];
      // 1) 标题行：标题文字 + '\n'，级别只写进 runs
      const title: string = CanvasDraftWriter.titleOf(input.cardOf, row.cardId);
      const line: string = title + '\n';
      const level: number = CanvasDraftWriter.headingOf(row.depth);
      if (level > 0) {
        runs.push(new FormatRun(offset, offset + line.length, false, false, level, 0));
      }
      parts.push(line);
      offset += line.length;
      // 2) 该节点的素材：顺序照传进来的数组，quotation 带出处，判断/笔记原样
      const block: string = CanvasDraftWriter.evidenceBlock(grouped, row.cardId);
      parts.push(block);
      offset += block.length;
      // 3) 每节末尾的占位，让"没写的地方"在初稿里可见
      const pending: string = CANVAS_DRAFT_PENDING_MARK + '\n';
      parts.push(pending);
      offset += pending.length;
    }
    const content: string = parts.join('');
    return { content: content, runs: runs, runsJson: FormatCodec.encode(runs) };
  }

  /**
   * 深度 → 标题级别：1/2/3 原样，>3 夹到 3；depth<=0（写作卡自身/异常输入）返回 0 表示不写标题，
   * 避免把根卡伪装成"一、"。
   */
  private static headingOf(depth: number): number {
    if (!Number.isFinite(depth) || depth <= 0) {
      return 0;
    }
    const rounded: number = Math.round(depth);
    return rounded > CANVAS_DRAFT_MAX_HEADING ? CANVAS_DRAFT_MAX_HEADING : rounded;
  }

  /** 取标题并压平换行：标题里的 '\n' 会把"一行一节点"的偏移对应破坏掉 */
  private static titleOf(cardOf: (cardId: string) => CanvasCardData | undefined, cardId: string): string {
    const card: CanvasCardData | undefined = cardOf(cardId);
    if (card === undefined) {
      return '';
    }
    return card.title.split('\r').join(' ').split('\n').join(' ');
  }

  /** 按 cardId 归组，保持传入顺序（Map 只用于分流，顺序由 push 顺序保证） */
  private static groupEvidence(list: CanvasEvidenceData[]): Map<string, CanvasEvidenceData[]> {
    const grouped: Map<string, CanvasEvidenceData[]> = new Map<string, CanvasEvidenceData[]>();
    for (let i: number = 0; i < list.length; i++) {
      const ev: CanvasEvidenceData = list[i];
      const bucket: CanvasEvidenceData[] | undefined = grouped.get(ev.cardId);
      if (bucket === undefined) {
        const fresh: CanvasEvidenceData[] = [];
        fresh.push(ev);
        grouped.set(ev.cardId, fresh);
      } else {
        bucket.push(ev);
      }
    }
    return grouped;
  }

  /** 某个节点的素材块：每条素材一行，块尾换行；没有素材返回空串 */
  private static evidenceBlock(grouped: Map<string, CanvasEvidenceData[]>, cardId: string): string {
    return CanvasDraftWriter.evidenceBlockFromList(grouped.get(cardId));
  }

  private static evidenceBlockFromList(list: CanvasEvidenceData[] | undefined): string {
    if (list === undefined) {
      return '';
    }
    const lines: string[] = [];
    for (let i: number = 0; i < list.length; i++) {
      const line: string = CanvasDraftWriter.evidenceLine(list[i]);
      if (line !== '') {
        lines.push(line);
      }
    }
    if (lines.length === 0) {
      return '';
    }
    return lines.join('\n') + '\n';
  }

  /**
   * 单条素材 → 一行正文。
   * - 引文：原文（引自《书名》N 章 M 段）——书名/章节由写素材的一方拼进 sourceLabel，
   *   生成器只负责加"（引自…）"外壳，不猜书名；sourceLabel 为空时只写原文。
   * - 判断 / 笔记：原样输出（userText 为空的旧数据回落到 quoteText，避免整条丢失）。
   */
  private static evidenceLine(ev: CanvasEvidenceData): string {
    if (ev.kind === CanvasEvidenceKind.QUOTE) {
      const body: string = CanvasDraftWriter.trimTail(ev.quoteText !== '' ? ev.quoteText : ev.userText);
      if (body === '') {
        return '';
      }
      const label: string = CanvasDraftWriter.trimTail(ev.sourceLabel);
      if (label === '') {
        return body;
      }
      return body + '（引自' + label + '）';
    }
    return CanvasDraftWriter.trimTail(ev.userText !== '' ? ev.userText : ev.quoteText);
  }

  /** 去掉尾部换行（素材正文自带 '\n' 时不要写出空行，破坏"一条素材一行"） */
  private static trimTail(text: string): string {
    let out: string = text;
    while (out.length > 0) {
      const ch: string = out.charAt(out.length - 1);
      if (ch === '\n' || ch === '\r') {
        out = out.substring(0, out.length - 1);
      } else {
        break;
      }
    }
    return out;
  }
}
