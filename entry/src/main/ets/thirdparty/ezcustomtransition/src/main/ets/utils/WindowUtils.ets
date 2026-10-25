import { window } from '@kit.ArkUI';
import { ezCustomTransitionConstants } from '../Constants/ezCustomTransitionConstants';

const TAG = 'WindowUtils';

export class WindowUtils {
  public static window: window.Window;

  public static windowWidth_px: number;

  public static windowHeight_px: number;

  public static topAvoidAreaHeight_px: number;

  public static navigationIndicatorHeight_px: number;

  public static init(windowStage: window.WindowStage) {
    // 获取窗口宽高
    WindowUtils.window = windowStage.getMainWindowSync();
    WindowUtils.windowWidth_px = WindowUtils.window.getWindowProperties().windowRect.width;
    WindowUtils.windowHeight_px = WindowUtils.window.getWindowProperties().windowRect.height;

    AppStorage.setOrCreate(ezCustomTransitionConstants.WINDOW_SIZE,
      { width: WindowUtils.windowWidth_px, height: WindowUtils.windowHeight_px });

    // 获取上方避让区(状态栏等)高度
    let avoidArea = WindowUtils.window.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    WindowUtils.topAvoidAreaHeight_px = avoidArea.topRect.height;

    // 获取导航条高度
    let navigationArea = WindowUtils.window.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    WindowUtils.navigationIndicatorHeight_px = navigationArea.bottomRect.height;

    console.log(TAG, 'the width is ' + WindowUtils.windowWidth_px + '  ' + WindowUtils.windowHeight_px + '  '
      + WindowUtils.topAvoidAreaHeight_px + '  ' + WindowUtils.navigationIndicatorHeight_px);

    // 监听窗口尺寸、状态栏高度及导航条高度的变化并更新
    try {
      WindowUtils.window.on('windowSizeChange', (data) => {
        console.log(TAG, 'on windowSizeChange, the width is ' + data.width + ', the height is ' + data.height);
        WindowUtils.windowWidth_px = data.width;
        WindowUtils.windowHeight_px = data.height;
        AppStorage.setOrCreate(ezCustomTransitionConstants.ON_WINDOW_SIZE_CHANGED, Date.now());
        AppStorage.setOrCreate(ezCustomTransitionConstants.WINDOW_SIZE, { width: data.width, height: data.height });
      })

      WindowUtils.window.on('avoidAreaChange', (data) => {
        if (data.type == window.AvoidAreaType.TYPE_SYSTEM) {
          let topRectHeight = data.area.topRect.height;
          console.log(TAG, 'on avoidAreaChange, the top avoid area height is ' + topRectHeight);
          WindowUtils.topAvoidAreaHeight_px = topRectHeight;
        } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          let bottomRectHeight = data.area.bottomRect.height;
          console.log(TAG, 'on avoidAreaChange, the navigation indicator height is ' + bottomRectHeight);
          WindowUtils.navigationIndicatorHeight_px = bottomRectHeight;
        }
      })
    } catch (exception) {
      console.log(TAG, 'register failed ' + JSON.stringify(exception));
    }
  }
}