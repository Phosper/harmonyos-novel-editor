import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { prefs } from '../utils/PreferenceHelper';
import { setAppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { app } from '../store/AppStores';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    setAppContext(this.context)
    Logger.info('Ability onCreate');
  }

  onDestroy(): void {
    // 兜底落库：即使页面没走 aboutToDisappear，也不让内存里的草稿消失
    app.flushAll()
    app.destroy();
    Logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.info('Ability onWindowStageCreate');

    const mainWin: window.Window = windowStage.getMainWindowSync()

    AppStorage.setOrCreate<window.Window>('mainWindow', mainWin)

    // 设备形态判据用 deviceInfo.deviceType，而不是"窗口宽度 > 某阈值"：
    //  1) 宽度判据会把 1280vp 宽的大平板误判成桌面形态，从而给它画上桌面窗口控制按钮；
    //  2) 宽度判据若想换算 vp，需要屏幕密度，而此处绝不能调用 window.getUIContext()——
    //     loadContent 之前窗口还没有 UIContent，调用会抛
    //     "This window state is abnormal / 1300002" 并被系统按 JS 错误直接杀进程。
    const isDesktop: boolean = deviceInfo.deviceType === '2in1'
    AppStorage.setOrCreate<boolean>('isPcDevice', isDesktop)

    if (isDesktop) {
      try {
        // 隐藏系统窗口装饰（标题栏 + 最小化/最大化/关闭三键），改由 PcWindowBar 自绘承载
        mainWin.setWindowDecorVisible(false)
        // 与 PcWindowBar 高度保持一致，避免自绘条与系统预留高度打架
        mainWin.setWindowDecorHeight(36)
      } catch (e) {
        Logger.warn('Window decor config failed: ' + String(e))
      }
    }

    // 沉浸式：**所有设备**（手机/平板/PC）布局扩展到系统栏区域，系统栏透明。
    // 必须在 loadContent 之前开启：官方明确，未开全屏布局时
    // getWindowAvoidArea 读到的避让高度可能与实际不符，页面避让必然错位。
    mainWin.setWindowLayoutFullScreen(true).catch((e: Error) => {
      Logger.warn('setWindowLayoutFullScreen failed: ' + String(e))
    })
    app.ui.syncSystemBars()

    const loadPage = (url: string): void => {
      windowStage.loadContent(url, (err: BusinessError) => {
        if (err.code) {
          Logger.error('Failed to load the content: ' + JSON.stringify(err));
          return;
        }
        Logger.info('Succeeded in loading the content.');
        // 窗口底色透明：让页面自身的背景铺满（含状态栏/导航条区域），实现真正沉浸；
        // 若给不透明底色，状态栏区域会露出一条与页面不一致的色带。
        try {
          mainWin.setWindowBackgroundColor('#00000000')
        } catch (e) {
          Logger.warn('setWindowBackgroundColor failed: ' + String(e))
        }
        // 内容加载完成后再按实际主题设一次系统栏
        app.ui.syncSystemBars()
      });
    }

    let systemDark: boolean = false
    try {
      const colorMode: ConfigurationConstant.ColorMode =
        this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      this.context.getApplicationContext().setColorMode(colorMode)
      systemDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } catch (err) {
      Logger.error('Failed to set colorMode: ' + JSON.stringify(err));
    }

    // 单一 init 链：首选项初始化 + 深色初值 + 首启检测，避免竞态
    prefs.init(this.context)
      .then(async () => {
        // 用户在设置里显式选过深色模式时以用户选择为准，否则跟随系统；
        // 走 applySystemDarkMode 以同步联动稿纸主题
        const explicit: boolean = await prefs.isDarkExplicit()
        if (!explicit) {
          await app.ui.applySystemDarkMode(systemDark)
        }
        // 主题确定后校正系统栏前景色（明/暗）
        app.ui.syncSystemBars()
        return prefs.isFirstLaunch()
      })
      .then((first: boolean) => { loadPage(first ? 'pages/GuideSwiperPage' : 'pages/Index') })
      .catch((e: Error) => {
        Logger.error('Ability init chain failed: ' + String(e))
        loadPage('pages/Index')
      })
  }

  onWindowStageDestroy(): void {
    Logger.info('Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const systemDark: boolean =
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    // 只在用户没有显式选择过时跟随系统（旧实现会每次覆盖用户设置）。
    // 走 applySystemDarkMode 而不是直写 darkMode，让稿纸主题一起联动。
    prefs.isDarkExplicit().then((explicit: boolean) => {
      if (!explicit) {
        app.ui.applySystemDarkMode(systemDark)
      }
    })
  }

  onForeground(): void {
    Logger.info('Ability onForeground');
    // 前台时窗口才真正就绪；按实际主题同步系统栏前景色
    app.ui.syncSystemBars()
  }

  onBackground(): void {
    // 退到后台立即落库：这是比"等 30 秒安全网"更可靠的一道保险
    app.flushAll();
    Logger.info('Ability onBackground');
  }
}
