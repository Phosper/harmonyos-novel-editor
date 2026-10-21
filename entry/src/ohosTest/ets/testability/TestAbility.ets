import { UIAbility } from '@kit.AbilityKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import { FlowTextFixture } from '../test/FlowTextFixture';
export default class TestAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    FlowTextFixture.ready = false;
    stage.loadContent('testability/pages/Index', (error) => {
      if (error.code) {
        this.failStartup('FlowText test page failed: ' + error.message);
        return;
      }
      if (deviceInfo.deviceType === '2in1') {
        // The fixture stays behind EntryAbility; its native buttons must not pollute window assertions.
        try {
          const fixtureWindow: window.Window = stage.getMainWindowSync();
          fixtureWindow.setWindowDecorVisible(false);
          fixtureWindow.setWindowTitleButtonVisible(false, false, false);
        } catch (error) {
          this.failStartup('Cannot isolate fixture window chrome: ' + String(error));
          return;
        }
      }
      this.startWhenFixtureReady().catch((error: Error) => {
        this.failStartup('FlowText test fixture failed to start: ' + error.message);
      });
    });
  }

  private async startWhenFixtureReady(): Promise<void> {
    const driver: Driver = Driver.create();
    const deadline: number = Date.now() + 15000;
    while (!FlowTextFixture.ready) {
      if (Date.now() >= deadline) { throw new Error('Page did not appear within 15 seconds'); }
      // Yield the UI event loop: synchronous native model tests can otherwise prevent the first render.
      await driver.delayMs(25);
    }
    const editor = await driver.waitForComponent(ON.id('canvasTextEditor'), Math.max(1, deadline - Date.now()));
    if (editor === null) { throw new Error('Canvas editor did not mount within 15 seconds'); }
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(), abilityDelegatorRegistry.getArguments(), testsuite);
  }

  private failStartup(message: string): void {
    console.error(message);
    abilityDelegatorRegistry.getAbilityDelegator().finishTest(message, -1).catch(() => {});
  }
}
