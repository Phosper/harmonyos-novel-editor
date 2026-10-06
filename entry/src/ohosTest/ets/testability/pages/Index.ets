import { CanvasTextEditor } from '../../../../main/ets/editor/flowtext/CanvasTextEditor';
import { FormatRun } from '../../../../main/ets/editor/flowtext/model/EditorTypes';
import { FlowTextFixture } from '../../test/FlowTextFixture';
@Entry
@Component
struct FlowTextTestPage {
  build() {
    Column() {
      Text('FlowText regression fixture').fontSize(16)
      CanvasTextEditor({
        controller: FlowTextFixture.controller,
        onCaretChange: (offset: number) => { FlowTextFixture.savedCaret = offset; },
        onSelectionChange: (start: number, end: number) => {
          FlowTextFixture.selectionStart = start;
          FlowTextFixture.selectionEnd = end;
        },
        onEdit: (value: string, runs: FormatRun[], caret: number) => {
          FlowTextFixture.savedText = value;
          FlowTextFixture.savedRuns = runs;
          FlowTextFixture.savedCaret = caret;
        }
      }).layoutWeight(1).width('100%')
    }.width('100%').height('100%').onAppear(() => { FlowTextFixture.ready = true; })
  }
}
