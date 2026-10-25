/**
 * 画布 / 命令层 → 编辑器控制器 的薄封装（D · 编辑器桥）。
 *
 * 存在的意义只有两条：
 *   1. 画布侧（CanvasPane / 卡片抽屉 / 命令面板）不必到处写 `controller === null` 判空；
 *   2. 偏移量的入参清洗（负数 / NaN）集中在一处，避免各调用点各写一遍钳制。
 *
 * 本文件**不持有状态**、不缓存文本、不监听事件：每次调用都直接问控制器，
 * 这样编辑器里的选区变了，画布侧下一次读数就是最新的。
 */
import { CanvasTextEditorController } from './flowtext/CanvasTextEditor';

export class CanvasSelectionBridge {
  /** 当前选中文字。controller 为 null（编辑器未挂载）时返回空串。 */
  static getSelectionText(controller: CanvasTextEditorController | null): string {
    if (controller === null) {
      return '';
    }
    return controller.getSelectedText();
  }

  /**
   * 把偏移滚进视口（素材行「跳回原文」用）。
   * controller 为 null 时不动作；偏移非有限数或为负时丢弃而不是钳成 0 ——
   * 把"没算出来的偏移"当成文首会把人送到错误的位置，静默不动更容易被发现。
   */
  static reveal(controller: CanvasTextEditorController | null, offset: number): void {
    if (controller === null) {
      return;
    }
    if (!Number.isFinite(offset) || offset < 0) {
      return;
    }
    controller.revealOffset(offset);
  }
}
