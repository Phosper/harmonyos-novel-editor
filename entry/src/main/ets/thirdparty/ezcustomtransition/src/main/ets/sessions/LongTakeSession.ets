import { ezCustomTransitionConstants,
  LongTakeTransitionType } from '../Constants/ezCustomTransitionConstants';
import { LongTakeTransitionParam } from '../utils/LongTakeTransitionParam';
import { RectInfo_px } from '../utils/ComponentAttrUtils';
import { WindowUtils } from '../utils/WindowUtils';
import { CustomTransition } from '../utils/CustomNavigationUtils';
import { LongTakeSessionOptions } from '../utils/Options';

const TAG: string = 'LongTakeSession';

const INIT_BG_COLOR = '#00000000';

const DEFAULT_FINAL_BG_COLOR = '#33000000';

const DEFAULT_SCREEN_RADIUS = 9;

// 将自定义一镜到底转场动画进行封装，这样其他界面也需要做自定义一镜到底转场的话，可以直接复用，减少工作量
@Observed
export class LongTakeSession {
  public navDestinationBgColor: ResourceColor = INIT_BG_COLOR;

  public snapShotOpacity: number = 0;

  public postPageOpacity: number = 1;

  public translateX: number = 0;

  public translateY: number = 0;

  public scaleValue: number = 1;

  public clipWidth: Dimension = '100%';

  public clipHeight: Dimension = '100%';

  public radius: number = 0;

  public positionXValue: number = 0;

  public positionYValue: number = 0;

  public snapShotSize: SizeOptions = { width: '100%', height: '100%' };

  public snapShotPositionX: number = 0;

  public snapShotPositionY: number = 0;

  public options: LongTakeSessionOptions | undefined = undefined;

  public type: LongTakeTransitionType = LongTakeTransitionType.CardLongTake;

  private finalBgColor: ResourceColor = DEFAULT_FINAL_BG_COLOR;

  private animationCount: number = 0;

  private initScale: number = 1;

  private initTranslateX: number = 0;

  private initTranslateY: number = 0;

  private initClipWidth: Dimension = 0;

  private initClipHeight: Dimension = 0;

  private initPositionValueX: number = 0;

  private initPositionValueY: number = 0;

  private cardItemInfo_px: RectInfo_px = new RectInfo_px();

  private postPageSharedComponentId: string | undefined = undefined;

  private navDestinationId: string = '';

  private navPathStack: NavPathStack = new NavPathStack();

  private transitionParam: LongTakeTransitionParam = new LongTakeTransitionParam(new RectInfo_px());

  private isWindowSizeChanged: boolean = false;

  private initParams(): void {
    let postNode = WindowUtils.window.getUIContext().getFrameNodeById(this.postPageSharedComponentId);
    let stackNode = WindowUtils.window.getUIContext()
      .getFrameNodeById(this.getNavDestinationId() + ezCustomTransitionConstants.POST_PAGE_STACK_ID);
    let snapShotStackNode = WindowUtils.window.getUIContext()
      .getFrameNodeById(this.getNavDestinationId() + ezCustomTransitionConstants.POST_PAGE_SNAPSHOT_STACK_ID);

    let isWindowLayoutFullScreen: boolean = WindowUtils.window.getWindowProperties().isLayoutFullScreen;

    let stackPosition_vp = stackNode?.getPositionToWindowWithTransform();
    let stackSize_px = stackNode?.getMeasuredSize();
    let stackCenterX_px = vp2px(stackPosition_vp?.x) + (stackSize_px?.width!) / 2;

    if (!this.postPageSharedComponentId || !postNode || !snapShotStackNode || !stackSize_px) {
      if (!stackSize_px?.width || !stackSize_px?.height) {
        return;
      }

      let initScaleX = this.cardItemInfo_px.width / stackSize_px?.width!;
      let initScaleY = this.cardItemInfo_px.height / stackSize_px?.height!;

      this.initPositionValueY = (stackPosition_vp?.y! != 0) ? 0
        : (isWindowLayoutFullScreen ? 0 : -px2vp(WindowUtils.topAvoidAreaHeight_px));

      if (initScaleX >= initScaleY) {
        this.initScale = initScaleX;
        this.initTranslateX = px2vp(this.cardItemInfo_px.left + this.cardItemInfo_px.width / 2 - stackCenterX_px);
        this.initClipWidth = px2vp(stackSize_px?.width);
        this.initClipHeight = px2vp((this.cardItemInfo_px.height) / this.initScale);
        this.snapShotSize = { width: px2vp(stackSize_px?.width) };
        this.initTranslateY = px2vp(this.cardItemInfo_px.top
          - ((vp2px(this.initClipHeight) - vp2px(this.initClipHeight) * this.initScale) / 2))
          - stackPosition_vp?.y!;
      } else {
        this.initScale = initScaleY;
        this.initTranslateY = px2vp(this.cardItemInfo_px.top
          - (stackSize_px?.height! * (1 - this.initScale) / 2))
          - stackPosition_vp?.y!;
        this.initClipHeight = px2vp(stackSize_px?.height);
        this.initClipWidth = px2vp((this.cardItemInfo_px.width) / this.initScale);
        this.initTranslateX = px2vp(this.cardItemInfo_px.left + this.cardItemInfo_px.width / 2 - stackCenterX_px);
        this.snapShotSize = { height: px2vp(stackSize_px?.height) };
      }
    } else {
      let snapShotStackPositionToWindow_vp = snapShotStackNode?.getPositionToWindowWithTransform();
      let postNodePositionX_vp = postNode.getPositionToWindowWithTransform().x;
      let postNodePositionY_vp = postNode.getPositionToWindowWithTransform().y;
      let postNodeWidth_px = postNode.getMeasuredSize().width;
      let postNodeHeight_px = postNode.getMeasuredSize().height;
      console.log(TAG, 'the size is ' + postNodeWidth_px + ' and ' + postNodeHeight_px
        + ' and ' + vp2px(postNodePositionX_vp) + ' and ' + vp2px(postNodePositionY_vp));

      this.initScale = this.cardItemInfo_px.width / postNodeWidth_px;
      this.initClipHeight = px2vp(this.cardItemInfo_px.height / this.initScale);

      if (postNodeHeight_px == 0 || this.transitionParam.options?.type === LongTakeTransitionType.ImageLongTake) {
        postNodeHeight_px = postNodeHeight_px ?? this.cardItemInfo_px.height / this.initScale;
        this.initPositionValueX = -postNodePositionX_vp + stackPosition_vp?.y!;
        this.snapShotPositionY = postNodePositionY_vp + px2vp(postNodeHeight_px) / 2
          - this.initClipHeight / 2 - snapShotStackPositionToWindow_vp?.y!;
        this.initPositionValueY = -(postNodePositionY_vp + px2vp(postNodeHeight_px) / 2
          - this.initClipHeight / 2 - stackPosition_vp?.y!);
        this.snapShotPositionX = postNodePositionX_vp - snapShotStackPositionToWindow_vp?.x!;
        this.initTranslateY = px2vp(this.cardItemInfo_px.top)
          - (this.initClipHeight * (1 - this.initScale) / 2)
          - stackPosition_vp?.y!;
      } else if (!this.transitionParam.options?.type ||
        this.transitionParam.options?.type === LongTakeTransitionType.CardLongTake) {
        this.initPositionValueX = -postNodePositionX_vp + stackPosition_vp?.x!;
        this.initPositionValueY = -postNodePositionY_vp + stackPosition_vp?.y!;
        this.snapShotPositionY = postNodePositionY_vp - snapShotStackPositionToWindow_vp?.y!;
        this.snapShotPositionX = postNodePositionX_vp - snapShotStackPositionToWindow_vp?.x!;
        this.initTranslateY = px2vp(this.cardItemInfo_px.top
          - vp2px(this.initClipHeight) * (1 - this.initScale) / 2)
          - stackPosition_vp?.y!;
      }

      this.initClipWidth = px2vp(postNodeWidth_px);
      this.snapShotSize = { width: px2vp(postNodeWidth_px) };
      this.initTranslateX = px2vp(this.cardItemInfo_px.left + this.cardItemInfo_px.width / 2 - stackCenterX_px);
    }
    console.log(TAG, 'the value is initScale: ' + this.initScale + ' initTranslateX ' + this.initTranslateX
      + ' initClipWidth ' + this.initClipWidth + ' initClipHeight ' + this.initClipHeight + ' initTranslateY '
      + this.initTranslateY + ' initPositionValue ' + this.initPositionValueY);
  }

  public doAnimation(isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy): void {
    if (isPush && !isExit) {
      this.doEnterAnimation(transitionProxy);
    } else if (!isPush && isExit) {
      this.doBackAnimation(transitionProxy);
    }
  }

  public doEnterAnimation(transitionProxy?: NavigationTransitionProxy): void {
    this.initParams();
    this.scaleValue = this.initScale;
    this.translateX = this.initTranslateX;
    this.clipWidth = this.initClipWidth;
    this.clipHeight = this.initClipHeight;
    this.translateY = this.initTranslateY;
    this.positionYValue = this.initPositionValueY;
    this.positionXValue = this.initPositionValueX;
    this.radius = (this.cardItemInfo_px.cornerRadius ?? 0) / this.initScale;
    this.transitionParam.options?.onEnterTransitionStart?.();
    this.snapShotOpacity = 1;
    this.postPageOpacity = 0;

    let animationCount = ++this.animationCount;

    // 开始做动画效果
    animateTo({
      duration: 250,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (animationCount === this.animationCount) {
          this.radius = 0;
          this.animationCount = 0;
          this.transitionParam.options?.onEnterTransitionEnd?.();
        }
        if (transitionProxy) {
          transitionProxy.finishTransition();
        }
      }
    }, () => {
      this.translateX = 0;
      this.scaleValue = 1.0;
      this.translateY = 0;
      this.clipWidth = '100%';
      this.clipHeight = '100%';
      this.positionYValue = 0;
      this.positionXValue = 0;
      this.navDestinationBgColor = this.finalBgColor;
      this.radius = DEFAULT_SCREEN_RADIUS;
    })

    animateTo({
      delay: 50,
      duration: 50,
      curve: Curve.EaseOut,
    }, () => {
      this.snapShotOpacity = 0;
    })

    animateTo({
      duration: 100,
      curve: Curve.EaseOut,
    }, () => {
      this.postPageOpacity = 1.0;
    })
  }

  public doBackAnimation(transitionProxy?: NavigationTransitionProxy): void {
    if (this.animationCount == 0) {
      this.radius = DEFAULT_SCREEN_RADIUS;
    }
    ++this.animationCount;
    this.transitionParam.options?.onBackTransitionStart?.();

    if (this.isWindowSizeChanged) {
      animateTo({
        duration: 250,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.transitionParam.options?.onBackTransitionEnd?.();
          if (transitionProxy) {
            transitionProxy.finishTransition();
          }
        }
      }, () => {
        this.scaleValue = 0.05;
        this.translateX = 0;
        this.translateY = 0;
        this.radius = (this.cardItemInfo_px.cornerRadius ?? 0) / this.initScale;
        this.navDestinationBgColor = INIT_BG_COLOR;
      })

      animateTo({
        duration: 250,
        curve: Curve.EaseOut,
      }, () => {
        this.snapShotOpacity = 0;
      })

      animateTo({
        duration: 250,
        curve: Curve.EaseInOut,
      }, () => {
        this.postPageOpacity = 0;
      })
    } else {
      animateTo({
        duration: 250,
        curve: Curve.EaseOut,
        onFinish: () => {
          this.transitionParam.options?.onBackTransitionEnd?.();
          if (transitionProxy) {
            transitionProxy.finishTransition();
          }
        }
      }, () => {
        this.scaleValue = this.initScale;
        this.translateX = this.initTranslateX;
        this.clipWidth = this.initClipWidth;
        this.clipHeight = this.initClipHeight;
        this.translateY = this.initTranslateY;
        this.radius = (this.cardItemInfo_px.cornerRadius ?? 0) / this.initScale;
        this.positionXValue = this.initPositionValueX;
        this.positionYValue = this.initPositionValueY;
        this.navDestinationBgColor = INIT_BG_COLOR;
      })
      animateTo({
        delay: 50,
        duration: 150,
        curve: Curve.EaseOut,
      }, () => {
        this.snapShotOpacity = 1;
      })

      animateTo({
        delay: 100,
        duration: 120,
        curve: Curve.EaseIn,
      }, () => {
        this.postPageOpacity = 0;
      })
    }
  }

  public getNavDestinationId(): string {
    return this.navDestinationId;
  }

  public getPathStack(): NavPathStack {
    return this.navPathStack;
  }

  public getTransitionParam(): LongTakeTransitionParam {
    return this.transitionParam;
  }

  public init(context: NavDestinationContext, param: LongTakeTransitionParam, options: LongTakeSessionOptions): void {
    this.navPathStack = context?.pathStack;
    if (!context || !param || !context.navDestinationId || !param.componentRectInfo || !options) {
      console.log(TAG, 'init param is invalid!');
      return;
    }
    if (param.componentRectInfo.width == 0 || param.componentRectInfo.height == 0) {
      return;
    }

    try {
      // 先初始化一些转场信息
      this.transitionParam = param;
      this.cardItemInfo_px = param.componentRectInfo;
      this.postPageSharedComponentId = options.alignTargetId;
      this.options = options;
      this.navDestinationId = context.navDestinationId;
      this.type = param.options?.type ?? LongTakeTransitionType.CardLongTake;
      this.finalBgColor = this.type ? Color.Black : DEFAULT_FINAL_BG_COLOR;

      CustomTransition.getInstance().registerNavParam(context.navDestinationId,
        (isPush: boolean, isExit: boolean, transitionProxy: NavigationTransitionProxy) => {
          this.doAnimation(isPush, isExit, transitionProxy);
        }, undefined);
      return;
    } catch (e) {
      console.log(TAG, 'initLongTakeTransition error ' + e);
      return;
    }
  }

  public setWindowSizeChanged(): void {
    this.isWindowSizeChanged = true;
  }
}