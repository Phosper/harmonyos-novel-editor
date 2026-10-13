import { CanvasTextEditorController } from '../../../main/ets/editor/flowtext/CanvasTextEditor';
import { FormatRun } from '../../../main/ets/editor/flowtext/model/EditorTypes';
export class FlowTextFixture {
  static controller: CanvasTextEditorController = new CanvasTextEditorController();
  static ready: boolean = false;
  static savedText: string = '';
  static savedCaret: number = 0;
  static savedRuns: FormatRun[] = [];
  static selectionStart: number = 0;
  static selectionEnd: number = 0;
  private static keyReleases: Map<number, number> = new Map();
  static recordKeyRelease(code: number): void {
    FlowTextFixture.keyReleases.set(code, FlowTextFixture.keyReleaseCount(code) + 1);
  }
  static keyReleaseCount(code: number): number {
    return FlowTextFixture.keyReleases.get(code) ?? 0;
  }
}
