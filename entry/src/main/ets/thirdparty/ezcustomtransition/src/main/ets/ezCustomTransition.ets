import { WindowUtils } from './utils/WindowUtils'
import { window } from '@kit.ArkUI'
import { AnimateCallback, CustomTransition} from './utils/CustomNavigationUtils';
import { ezCustomTransitionConstants, LongTakeTransitionType } from './Constants/ezCustomTransitionConstants';
import { ComponentAttrUtils } from './utils/ComponentAttrUtils';
import { LongTakeTransitionParam } from './utils/LongTakeTransitionParam';
import { CustomTransitionOptions, LongTakeTransitionOptions } from './utils/Options';
import { SnapShotImage } from './utils/SnapShotImage';

const TAG: string = 'ezCustomTransition';

export class ezCustomTransition {
  public static init(windowStage: window.WindowStage) {
    WindowUtils.init(windowStage);
  }

  public static onConfigurationChanged(): void {
    AppStorage.setOrCreate(ezCustomTransitionConstants.CONFIGURATION_UPDATE, Date.now());
  }

  public static generateLongTakeParam(uiContext: UIContext, cardId: string, cornerRadius: number,
    options?: LongTakeTransitionOptions): LongTakeTransitionParam | undefined {
    if (!uiContext || !cardId) {
      console.error(TAG, 'generateLongTakeParam error, cardId is invalid');
      return undefined;
    }

    try {
      let pixelMap = uiContext.getComponentSnapshot().getSync(cardId);
      console.log(TAG, `get ${cardId} snapshot sync success!`);
      SnapShotImage.pixelMap = pixelMap;
    } catch (error) {
      console.error(`getSync ${cardId} failed, errorCode: ` + error.code + "; message: " + error.message);
      return undefined;
    }

    let cardRectInfo = ComponentAttrUtils.getRectInfoById(uiContext, cardId, cornerRadius);
    console.log(TAG, 'getRectInfoById value is ' + JSON.stringify(cardRectInfo))
    if (!cardRectInfo) {
      return undefined;
    }
    let transitionParam: LongTakeTransitionParam = new LongTakeTransitionParam(cardRectInfo, options);
    transitionParam.componentId = cardId;
    transitionParam.transitionType = options?.type ?? LongTakeTransitionType.CardLongTake;
    return transitionParam;
  }

  public static customNavContentTransition(from: NavContentInfo, to: NavContentInfo,
    operation: NavigationOperation, options?: CustomTransitionOptions): NavigationAnimatedTransition | undefined {
    if (!from || !to) {
      return undefined;
    }
    from.navDestinationId = from.navDestinationId ?? '-1';
    to.navDestinationId = to.navDestinationId ?? '-1';

    // 针对点击按钮A走自定义转场点击按钮B走默认转场的场景，需要对是否注册了animation进行判断，来决定是否走自定义转场
    let fromParam: AnimateCallback = CustomTransition.getInstance().getAnimateParam(from.navDestinationId);
    let toParam: AnimateCallback = CustomTransition.getInstance().getAnimateParam(to.navDestinationId);

    CustomTransition.getInstance().operation = operation;
    if (CustomTransition.getInstance().interactive) {
      // 考虑自己写跟手动画的和用注册的interactive动画的场景
      // if ((!fromParam.animation && !toParam.animation) && (!fromParam.interactive && !toParam.interactive)) {
      //   console.log(TAG, 'the interactive transition and custom transition both undefined');
      //   return undefined;
      // }
      let customAnimation: NavigationAnimatedTransition = {
        onTransitionEnd: (isSuccess: boolean) => {
          options?.onTransitionEnd?.();
          CustomTransition.getInstance().proxy = undefined;
        },
        transition: (transitionProxy: NavigationTransitionProxy) => {
          options?.onTransitionStart?.();
          CustomTransition.getInstance().proxy = transitionProxy;
          let targetIndex: string | undefined = operation == NavigationOperation.PUSH ?
            (to.navDestinationId) : (from.navDestinationId);
          if (targetIndex) {
            CustomTransition.getInstance().fireInteractiveAnimation(targetIndex, operation);
          }
        },
        isInteractive: CustomTransition.getInstance().interactive
      }
      return customAnimation;
    }

    if (operation === NavigationOperation.PUSH && !toParam.animation) {
      return undefined;
    } else if (operation === NavigationOperation.POP && !fromParam.animation) {
      return undefined;
    }
    // 一切判断完成后，构造customAnimation给系统侧调用，执行自定义转场动画
    let customAnimation: NavigationAnimatedTransition = {
      onTransitionEnd: (isSuccess: boolean) => {
        options?.onTransitionEnd?.();
        console.log(TAG, `current custom transition result is ${isSuccess}`);
      },
      timeout: 1000,
      transition: (transitionProxy: NavigationTransitionProxy) => {
        options?.onTransitionStart?.();
        console.log(TAG, 'trigger custom transition callback');
        if (fromParam.animation) {
          fromParam.animation(operation == NavigationOperation.PUSH, true, transitionProxy);
        }
        if (toParam.animation) {
          toParam.animation(operation == NavigationOperation.PUSH, false, transitionProxy);
        }
      }
    };
    return customAnimation;
  }
}