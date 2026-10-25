import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ImportService } from '../../../main/ets/utils/ImportService';
import { ExportService, ExportFormat, ExportableChapter } from '../../../main/ets/utils/ExportService';
import { ChapterFormat } from '../../../main/ets/model/Chapter';

export default function abilityTest() {
  describe('ActsAbilityTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    })
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    })
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    })
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    })
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      hilog.info(0x0000, 'testTag', '%{public}s', 'it begin');
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    })
    it('nativeImportPreservesUtf8AcrossReadChunks', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const path: string = context.cacheDir + '/weaver-import-read-regression.txt';
      const value: string = '段落A😀𠮷\n'.repeat(12000);
      const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(value);
      try {
        const file: fileIo.File = fileIo.openSync(path,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          expect(fileIo.writeSync(file.fd, bytes.buffer)).assertEqual(bytes.byteLength);
        } finally { fileIo.closeSync(file); }
        expect(await ImportService.readText(path)).assertEqual(value);
      } finally {
        if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
      }
    })
    it('nativeTxtExportKeepsLiteralSymbolsWithFormatting', 0, () => {
      const value: string = '# 字面标题\n*星号* _下划线_ `代码` ~~波浪线~~\n1. 原编号';
      const chapter: ExportableChapter = {
        title: '文稿', content: value, format: ChapterFormat.TXT, runsJson: '0,6,1,0,0'
      };
      expect(ExportService.renderChapter(chapter, ExportFormat.TXT, chapter.title)).assertEqual(value);
      expect(ExportService.renderBook('项目', [chapter], ExportFormat.TXT).includes(value)).assertTrue();
    })
  })
}
