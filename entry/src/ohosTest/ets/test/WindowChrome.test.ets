import { describe, beforeAll, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, MouseButton } from '@kit.TestKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';

async function desktopWindow(driver: Driver): Promise<window.Window> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
    bundleName: 'com.chungu.weaver', moduleName: 'entry', abilityName: 'EntryAbility'
  });
  await driver.waitForComponent(ON.text('□'), 8000);
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
      expect((await driver.findComponents(ON.text('□'))).length).assertEqual(1);
    });
    it('desktopTopHoverAndCustomMaximizeRecover', 0, async () => {
      if (deviceInfo.deviceType !== '2in1') { return; }
      const driver: Driver = Driver.create();
      const status: window.WindowStatusType = mainWindow.getWindowStatus();
      if (status === window.WindowStatusType.MAXIMIZE || status === window.WindowStatusType.FULL_SCREEN) {
        await mainWindow.recover();
        await driver.delayMs(200);
      }
      await (await driver.findComponent(ON.text('□'))).click();
      await driver.delayMs(300);
      expect(mainWindow.getWindowStatus() === window.WindowStatusType.MAXIMIZE ||
        mainWindow.getWindowStatus() === window.WindowStatusType.FULL_SCREEN).assertTrue();
      const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
      const x: number = rect.left + Math.floor(rect.width / 2);
      await driver.mouseMoveTo({ x: x, y: rect.top + 300 });
      await driver.mouseMoveTo({ x: x, y: rect.top + 1 });
      await driver.delayMs(300);
      await driver.mouseClick({ x: x, y: rect.top + 20 }, MouseButton.MOUSE_BUTTON_LEFT);
      await assertNativeChromeHidden(driver, mainWindow);
      await (await driver.findComponent(ON.text('□'))).click();
      await driver.delayMs(300);
      expect(mainWindow.getWindowStatus()).assertEqual(window.WindowStatusType.FLOATING);
      await assertNativeChromeHidden(driver, mainWindow);
    });
    it('desktopNarrowWindowAndGuideKeepCustomControls', 0, async () => {
      if (deviceInfo.deviceType !== '2in1') { return; }
      const driver: Driver = Driver.create();
      const original: window.Rect = mainWindow.getWindowProperties().windowRect;
      let guideShown: boolean = false;
      try {
        await mainWindow.resize(900, 1000);
        await driver.delayMs(300);
        expect((await driver.findComponents(ON.text('□'))).length).assertEqual(1);
        const before: window.Rect = mainWindow.getWindowProperties().windowRect;
        const x: number = before.left + Math.floor(before.width / 2);
        await driver.mouseDrag({ x: x, y: before.top + 20 }, { x: x + 60, y: before.top + 80 });
        await driver.delayMs(300);
        const after: window.Rect = mainWindow.getWindowProperties().windowRect;
        expect(after.left !== before.left || after.top !== before.top).assertTrue();
        await mainWindow.getUIContext().getRouter().replaceUrl({ url: 'pages/GuideSwiperPage' });
        guideShown = true;
        await driver.waitForComponent(ON.text('开始使用 Weaver'), 5000);
        expect((await driver.findComponents(ON.text('□'))).length).assertEqual(1);
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
