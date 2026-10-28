import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, On } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { app } from '../../../main/ets/store/AppStores';
import { chapterRepo } from '../../../main/ets/store/Repos';
import { ChapterModel } from '../../../main/ets/model/Chapter';
import { ParagraphKind } from '../../../main/ets/editor/flowtext/model/EditorTypes';
import { CanvasTextEditorController } from '../../../main/ets/editor/flowtext/CanvasTextEditor';
import { ensureWorkspace } from '../../../main/ets/shell/Navigator';
import { toggleFocusAnimated, exitFocusAnimated } from '../../../main/ets/shell/FocusTransition';

function desktopTestEnabled(): boolean {
  return deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc' ||
    AppStorage.get<boolean>('freeWindowMode') === true;
}

async function waitWindowStatus(driver: Driver, mainWindow: window.Window,
  expected: window.WindowStatusType, alternate?: window.WindowStatusType): Promise<void> {
  const deadline: number = Date.now() + 5000;
  while (mainWindow.getWindowStatus() !== expected && mainWindow.getWindowStatus() !== alternate &&
    Date.now() < deadline) {
    await driver.delayMs(50);
  }
  const status: window.WindowStatusType = mainWindow.getWindowStatus();
  expect(status === expected || (alternate !== undefined && status === alternate)).assertTrue();
}

async function componentsInWindow(driver: Driver, mainWindow: window.Window, selector: On): Promise<Component[]> {
  const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
  const matches: Component[] = await driver.findComponents(selector);
  const result: Component[] = [];
  // Some UiTest versions return null for no matches despite the declared array type.
  if (matches !== null) {
    for (const component of matches) {
      const center = await component.getBoundsCenter();
      if (center.x >= rect.left && center.x < rect.left + rect.width &&
        center.y >= rect.top && center.y < rect.top + rect.height) {
        result.push(component);
      }
    }
  }
  return result;
}

async function nativeCaptionButton(driver: Driver, mainWindow: window.Window, id: string): Promise<Component> {
  const matches: Component[] = await componentsInWindow(driver, mainWindow, ON.id(id));
  expect(matches.length).assertEqual(1);
  return matches[0];
}

async function assertNativeCaption(driver: Driver, mainWindow: window.Window): Promise<void> {
  // Hidden title background, but the system still owns all three caption buttons.
  expect(mainWindow.getWindowDecorVisible()).assertFalse();
  for (const id of ['EnhanceMaximizeBtn', 'EnhanceMinimizeBtn', 'EnhanceCloseBtn']) {
    const button: Component = await nativeCaptionButton(driver, mainWindow, id);
    expect(await button.isEnabled()).assertTrue();
  }
  for (const id of ['weaverWindowMaximize', 'weaverWindowMinimize', 'weaverWindowClose', 'weaverWindowTitle']) {
    expect((await componentsInWindow(driver, mainWindow, ON.id(id))).length).assertEqual(0);
  }
  expect((await componentsInWindow(driver, mainWindow, ON.id('enhanceAppLabel'))).length).assertEqual(0);
}

async function desktopWindow(driver: Driver): Promise<window.Window> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
    bundleName: 'com.chungu.weaver', moduleName: 'entry', abilityName: 'EntryAbility'
  });
  const deadline: number = Date.now() + 8000;
  let mainWindow: window.Window | undefined = AppStorage.get<window.Window>('mainWindow');
  while ((mainWindow === undefined || AppStorage.get<boolean>('uiReady') !== true) && Date.now() < deadline) {
    await driver.delayMs(50);
    mainWindow = AppStorage.get<window.Window>('mainWindow');
  }
  if (mainWindow === undefined) { throw new Error('EntryAbility did not publish its main window'); }
  // A clean installation may initially show the guide; start this suite at the workbench.
  await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
  while (!app.isReady && Date.now() < deadline) { await driver.delayMs(50); }
  expect(app.isReady).assertTrue();
  await driver.waitForComponent(ON.id('EnhanceMaximizeBtn'), 5000);
  await driver.delayMs(300);
  return mainWindow;
}

async function waitForEditor(driver: Driver, mainWindow: window.Window): Promise<CanvasTextEditorController> {
  const deadline: number = Date.now() + 5000;
  while (Date.now() < deadline) {
    const controller: CanvasTextEditorController | null = app.ui.editorController;
    if (controller !== null && controller.getText() === app.editor.content &&
      (await componentsInWindow(driver, mainWindow, ON.id('canvasTextEditor'))).length === 1) {
      return controller;
    }
    await driver.delayMs(50);
  }
  throw new Error('Workbench editor did not mount with the active document');
}

async function waitFocusState(driver: Driver, immersive: boolean): Promise<void> {
  const deadline: number = Date.now() + 5000;
  while (app.ui.immersiveEditing !== immersive && Date.now() < deadline) { await driver.delayMs(50); }
  expect(app.ui.immersiveEditing).assertEqual(immersive);
  await driver.delayMs(400);
}

async function restoreWindow(driver: Driver, mainWindow: window.Window, rect: window.Rect,
  status: window.WindowStatusType): Promise<void> {
  if (mainWindow.getWindowStatus() !== window.WindowStatusType.FLOATING) {
    await mainWindow.recover();
    await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
  }
  await mainWindow.resize(rect.width, rect.height);
  await mainWindow.moveWindowTo(rect.left, rect.top);
  if (status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN) {
    await mainWindow.maximize();
    await waitWindowStatus(driver, mainWindow, window.WindowStatusType.MAXIMIZE, window.WindowStatusType.FULL_SCREEN);
  }
  await driver.delayMs(300);
}

export default function windowChromeTest(): void {
  let mainWindow: window.Window;
  let fixtureId: string = '';
  let previousDocId: string = '';
  let previousSidebar: boolean = true;
  const fixtureTitle: string = '窗口验收-' + Date.now().toString();
  describe('WindowChromeRegression', () => {
    beforeAll(async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      mainWindow = await desktopWindow(driver);
      previousDocId = app.editor.activeId;
      previousSidebar = app.ui.showSidebar;
      const chapter: ChapterModel = await app.createChapter(fixtureTitle);
      fixtureId = chapter.id;
      ensureWorkspace();
      await waitForEditor(driver, mainWindow);
    });
    afterAll(async () => {
      if (fixtureId === '') { return; }
      if (app.ui.immersiveEditing) {
        exitFocusAnimated(mainWindow.getUIContext());
        await waitFocusState(Driver.create(), false);
      }
      // Delete only the temporary document this suite owns, preserving the previous document.
      await app.editor.flushAllStrict();
      await app.hardDeleteChapter(fixtureId);
      if (previousDocId !== '') { await app.openChapter(previousDocId); }
      app.ui.showSidebar = previousSidebar;
    });
    it('desktopKeepsNativeCaptionButtonsWithoutDuplicateTitleBar', 0, async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      await assertNativeCaption(driver, mainWindow);
      expect(app.ui.captionInset >= mainWindow.getTitleButtonRect().width).assertTrue();
      expect((await componentsInWindow(driver, mainWindow, ON.text(fixtureTitle))).length > 0).assertTrue();
    });
    it('desktopTopHoverAndNativeMaximizeRecover', 0, async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      const original: window.Rect = mainWindow.getWindowProperties().windowRect;
      const originalStatus: window.WindowStatusType = mainWindow.getWindowStatus();
      try {
        if (originalStatus !== window.WindowStatusType.FLOATING) {
          await mainWindow.recover();
          await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
        }
        await (await nativeCaptionButton(driver, mainWindow, 'EnhanceMaximizeBtn')).click();
        await waitWindowStatus(driver, mainWindow, window.WindowStatusType.MAXIMIZE, window.WindowStatusType.FULL_SCREEN);
        const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
        const x: number = rect.left + Math.floor(rect.width / 2);
        await driver.mouseMoveTo({ x: x, y: rect.top + 300 });
        await driver.mouseMoveTo({ x: x, y: rect.top + 1 });
        await driver.delayMs(300);
        await assertNativeCaption(driver, mainWindow);
        await (await nativeCaptionButton(driver, mainWindow, 'EnhanceMaximizeBtn')).click();
        await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
        await assertNativeCaption(driver, mainWindow);
      } finally {
        await restoreWindow(driver, mainWindow, original, originalStatus);
      }
    });
    it('desktopPaneHeaderDragAndNarrowGuideKeepNativeCaption', 0, async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      const original: window.Rect = mainWindow.getWindowProperties().windowRect;
      const originalStatus: window.WindowStatusType = mainWindow.getWindowStatus();
      let guideShown: boolean = false;
      try {
        if (originalStatus !== window.WindowStatusType.FLOATING) {
          await mainWindow.recover();
          await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
        }
        app.ui.showSidebar = true;
        await mainWindow.resize(Math.round(mainWindow.getUIContext().vp2px(1100)), original.height);
        await driver.delayMs(400);
        const before: window.Rect = mainWindow.getWindowProperties().windowRect;
        // The sidebar Pane's brand header owns dragging; no global custom title is mounted.
        const brands: Component[] = await componentsInWindow(driver, mainWindow, ON.text('语流'));
        expect(brands.length).assertEqual(1);
        const point = await brands[0].getBoundsCenter();
        await driver.mouseDrag(point, { x: point.x + 60, y: point.y + 60 });
        await driver.delayMs(300);
        const after: window.Rect = mainWindow.getWindowProperties().windowRect;
        expect(after.left !== before.left || after.top !== before.top).assertTrue();
        await mainWindow.resize(Math.round(mainWindow.getUIContext().vp2px(620)), original.height);
        await driver.delayMs(400);
        await assertNativeCaption(driver, mainWindow);
        expect(app.editor.activeId).assertEqual(fixtureId);
        await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/GuideSwiperPage' });
        guideShown = true;
        const start: Component = await driver.waitForComponent(ON.text('开始使用 语流'), 5000);
        expect(start !== null && start !== undefined).assertTrue();
        await assertNativeCaption(driver, mainWindow);
      } finally {
        if (guideShown) {
          await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
          ensureWorkspace();
        }
        await restoreWindow(driver, mainWindow, original, originalStatus);
        app.ui.showSidebar = previousSidebar;
        await waitForEditor(driver, mainWindow);
      }
    });
    it('desktopFocusRoundTripsKeepDraftAndNativeCaption', 0, async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      let controller: CanvasTextEditorController = await waitForEditor(driver, mainWindow);
      const expected: string = app.editor.content + '专注草稿😀\n字面 *原文*';
      controller.setCaretPosition(app.editor.content.length);
      controller.insertTextAtCaret('专注草稿😀\n字面 *原文*');
      expect(app.editor.content).assertEqual(expected);
      try {
        for (let pass: number = 0; pass < 2; pass++) {
          // Same transition entry as toolbar; verify the visible exit pill and keyboard exit separately.
          toggleFocusAnimated(mainWindow.getUIContext());
          await waitFocusState(driver, true);
          const exit: Component = await driver.waitForComponent(ON.text('退出专注'), 5000);
          expect(exit !== null && exit !== undefined).assertTrue();
          await assertNativeCaption(driver, mainWindow);
          controller = await waitForEditor(driver, mainWindow);
          expect(controller.getText()).assertEqual(expected);
          if (pass === 0) { await exit.click(); }
          else {
            controller.focus();
            await driver.waitForIdle(200, 5000);
            await driver.triggerKey(KeyCode.KEYCODE_ESCAPE);
          }
          await waitFocusState(driver, false);
          controller = await waitForEditor(driver, mainWindow);
          expect(controller.getText()).assertEqual(expected);
          expect(app.editor.activeId).assertEqual(fixtureId);
          await assertNativeCaption(driver, mainWindow);
        }
      } finally {
        if (app.ui.immersiveEditing) {
          exitFocusAnimated(mainWindow.getUIContext());
          await waitFocusState(driver, false);
        }
      }
    });
    it('desktopDraftAndTodoFormatPersistAfterStrictSaveAndTabReopen', 0, async () => {
      if (!desktopTestEnabled()) { return; }
      const driver: Driver = Driver.create();
      const controller: CanvasTextEditorController = await waitForEditor(driver, mainWindow);
      const expected: string = app.editor.content + '\n保存清单🚀';
      controller.setCaretPosition(app.editor.content.length);
      controller.insertTextAtCaret('\n保存清单🚀');
      controller.setParagraphKind(ParagraphKind.TODO);
      const expectedRuns: string = app.editor.runsJson;
      expect(controller.paragraphKind()).assertEqual(ParagraphKind.TODO);
      expect(expectedRuns.length > 0).assertTrue();
      await app.editor.flushAllStrict();
      const saved: ChapterModel | null = await chapterRepo.loadOne(fixtureId);
      expect(saved !== null).assertTrue();
      if (saved === null) { throw new Error('Strict save did not leave a readable document'); }
      expect(saved.content).assertEqual(expected);
      expect(saved.formatRuns ?? '').assertEqual(expectedRuns);
      await app.closeTab(fixtureId);
      await app.openChapter(fixtureId);
      ensureWorkspace();
      const reopened: CanvasTextEditorController = await waitForEditor(driver, mainWindow);
      expect(reopened.getText()).assertEqual(expected);
      expect(app.editor.runsJson).assertEqual(expectedRuns);
      expect(app.editor.activeDoc?.dirty).assertFalse();
      await assertNativeCaption(driver, mainWindow);
    });
  });
}
