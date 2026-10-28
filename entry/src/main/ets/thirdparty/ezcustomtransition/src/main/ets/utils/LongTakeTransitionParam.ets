import { LongTakeTransitionType } from '../../../../Index';
import { RectInfo_px } from './ComponentAttrUtils';
import { LongTakeTransitionOptions } from './Options';

export class LongTakeTransitionParam {
  public componentId: string = '';

  public transitionType: LongTakeTransitionType = LongTakeTransitionType.CardLongTake;

  // 响应点击事件的组件的区域和位置信息，单位为px
  public componentRectInfo: RectInfo_px = new RectInfo_px();

  public options: LongTakeTransitionOptions | undefined = undefined;

  constructor(componentRectInfo: RectInfo_px, options?: LongTakeTransitionOptions) {
    this.componentRectInfo = componentRectInfo;
    this.options = options;
  }
}