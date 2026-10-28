import { CustomTransition } from '../utils/CustomNavigationUtils';

const TAG: string = 'LeftRightInteractiveSession';

// 左右可交互转场的封装类
@Observed
export class LeftRightInteractiveSession {
  public translateX: number | string = '0%';

  private doEnterInteractiveAnimation(): void {
    this.translateX = '100%'
    animateTo({
      duration: 300,
      onFinish: () => {
        this.translateX = '0%';
      }
    }, () => {
      this.translateX = '0%';
    })
  }

  private doExitInteractiveAnimation(): void {
    this.translateX = '0%';
    animateTo({
      duration: 300
    }, () => {
      this.translateX = '100%';
    })
  }

  public init(context: NavDestinationContext): void {
    if (!context || !context.navDestinationId) {
      return;
    }

    try {
      CustomTransition.getInstance().registerNavParam(context.navDestinationId,
        undefined, (operation: NavigationOperation) => {
        if (operation === NavigationOperation.PUSH) {
          this.doEnterInteractiveAnimation();
        } else {
          this.doExitInteractiveAnimation();
        }
      });
    } catch (e) {
      console.log(TAG, 'initLongTakeTransition error ' + e);
    }
  }
}