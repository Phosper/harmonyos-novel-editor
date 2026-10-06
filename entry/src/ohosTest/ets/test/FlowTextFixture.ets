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
}
