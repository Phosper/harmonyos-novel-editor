import { describe, beforeAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, MouseButton } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

async function waitWindowStatus(driver: Driver, mainWindow: window.Window,
  expected: window.WindowStatusType, alternate?: window.WindowStatusType): Promise<void> {
  const deadline: number = Date.now() + 5000;
  while (mainWindow.getWindowStatus() !== expected && mainWindow.getWindowStatus() !== alternate &&
    Date.now() < deadline) {
    await driver.delayMs(50);
  }
  if (alternate === undefined) { expect(mainWindow.getWindowStatus()).assertEqual(expected); }
  else { expect(mainWindow.getWindowStatus() === expected || mainWindow.getWindowStatus() === alternate).assertTrue(); }
}

async function desktopWindow(driver: Driver): Promise<window.Window> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
    bundleName: 'com.chungu.weaver', moduleName: 'entry', abilityName: 'EntryAbility'
  });
  await driver.waitForComponent(ON.id('weaverWindowMaximize'), 8000);
  await driver.delayMs(100);
  const mainWindow: window.Window | undefined = AppStorage.get<window.Window>('mainWindow');
  if (mainWindow === undefined) {
    throw new Error('EntryAbility did not publish its main window');
  }
  return mainWindow;
}

async function assertNativeChromeHidden(driver: Driver, mainWindow: window.Window): Promise<void> {
  expect(mainWindow.getWindowDecorVisible()).assertFalse();
  const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
  // These IDs were observed in the native container before the fix.
  for (const id of ['enhanceAppLabel', 'EnhanceMaximizeBtn', 'EnhanceMinimizeBtn', 'EnhanceCloseBtn']) {
    const buttons = await driver.findComponents(ON.id(id));
    // Some native UiTest versions return null for an empty result despite the array declaration.
    if (buttons !== null) {
      for (const button of buttons) {
        const center = await button.getBoundsCenter();
        // TestAbility may remain visible behind a floating EntryAbility window.
        const inside: boolean = center.x >= rect.left && center.x < rect.left + rect.width &&
          center.y >= rect.top && center.y < rect.top + rect.height;
        if (inside) {
          console.info('Unexpected native control: ' + id + ' at ' + center.x + ',' + center.y +
            ' in main window ' + rect.left + ',' + rect.top + ',' + rect.width + ',' + rect.height);
        }
        expect(inside).assertFalse();
      }
    }
  }
}

export default function windowChromeTest(): void {
  let mainWindow: window.Window;
  describe('WindowChromeRegression', () => {
    beforeAll(async () => {
      if (deviceInfo.deviceType === '2in1') {
        mainWindow = await desktopWindow(Driver.create());
      }
    });
    it('desktopHidesNativeTitleAndButtonsAfterLoad', 0, async () => {
      if (deviceInfo.deviceType !== '2in1') { return; }
      const driver: Driver = Driver.create();
      await assertNativeChromeHidden(driver, mainWindow);
      expect((await driver.findComponents(ON.id('weaverWindowMaximize'))).length).assertEqual(1);
    });
    it('desktopTopHoverAndCustomMaximizeRecover', 0, async () => {
      if (deviceInfo.deviceType !== '2in1') { return; }
      const driver: Driver = Driver.create();
      const status: window.WindowStatusType = mainWindow.getWindowStatus();
      if (status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN) {
        await mainWindow.recover();
        await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
      }
      await (await driver.findComponent(ON.id('weaverWindowMaximize'))).click();
      await waitWindowStatus(driver, mainWindow, window.WindowStatusType.MAXIMIZE, window.WindowStatusType.FULL_SCREEN);
      expect(mainWindow.getWindowStatus() === window.WindowStatusType.MAXIMIZE ||
        mainWindow.getWindowStatus() === window.WindowStatusType.FULL_SCREEN).assertTrue();
      const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
      const x: number = rect.left + Math.floor(rect.width / 2);
      await driver.mouseMoveTo({ x: x, y: rect.top + 300 });
      await driver.mouseMoveTo({ x: x, y: rect.top + 1 });
      await driver.delayMs(300);
      // Click the brand margin: the center now intentionally starts dragging the custom title.
      await driver.mouseClick({ x: rect.left + 20, y: rect.top + 20 }, MouseButton.MOUSE_BUTTON_LEFT);
      await assertNativeChromeHidden(driver, mainWindow);
      await (await driver.findComponent(ON.id('weaverWindowMaximize'))).click();
      await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
      await assertNativeChromeHidden(driver, mainWindow);
    });
    it('desktopNarrowWindowAndGuideKeepCustomControls', 0, async () => {
      if (deviceInfo.deviceType !== '2in1') { return; }
      const driver: Driver = Driver.create();
      if (mainWindow.getWindowStatus() !== window.WindowStatusType.FLOATING) {
        await mainWindow.recover();
        await waitWindowStatus(driver, mainWindow, window.WindowStatusType.FLOATING);
      }
      const original: window.Rect = mainWindow.getWindowProperties().windowRect;
      let guideShown: boolean = false;
      try {
        await mainWindow.resize(900, 1000);
        await driver.delayMs(300);
        expect((await driver.findComponents(ON.id('weaverWindowMaximize'))).length).assertEqual(1);
        const before: window.Rect = mainWindow.getWindowProperties().windowRect;
        const title = await driver.findComponent(ON.id('weaverWindowTitle'));
        const dragPoint = await title.getBoundsCenter();
        await driver.mouseDrag(dragPoint, { x: dragPoint.x + 60, y: dragPoint.y + 60 });
        await driver.delayMs(300);
        const after: window.Rect = mainWindow.getWindowProperties().windowRect;
        expect(after.left !== before.left || after.top !== before.top).assertTrue();
        await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/GuideSwiperPage' });
        guideShown = true;
        await driver.waitForComponent(ON.text('开始使用 Weaver'), 5000);
        expect((await driver.findComponents(ON.id('weaverWindowMaximize'))).length).assertEqual(1);
        await assertNativeChromeHidden(driver, mainWindow);
      } finally {
        await mainWindow.resize(original.width, original.height);
        await mainWindow.moveWindowTo(original.left, original.top);
        if (guideShown) {
          await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' });
        }
      }
    });
  });
}
