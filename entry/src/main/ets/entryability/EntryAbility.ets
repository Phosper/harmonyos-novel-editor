import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { prefs } from '../utils/PreferenceHelper';
import { setAppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { app } from '../store/AppStores';
import { configureDesktopChrome } from '../utils/DesktopWindowChrome';
import { deviceProfile } from '../utils/DeviceProfile';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  /** 是否电脑形态（PC 或自由窗口/平板电脑模式）：只决定是否接管原生标题栏 */
  private isDesktop: boolean = false;
  /** 自由窗口模式（window.isInFreeWindowMode()，API 22）：桌面 chrome 的唯一判据 */
  private freeWindow: boolean = false;
  private contentReady: boolean = false;
  private freeWindowListener: ((isFree: boolean) => void) | null = null;
  private stageListener: ((event: window.WindowStageEventType) => void) | null = null;

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

  /**
   * 电脑形态判据。
   * 布局断点**不看**设备类型（CodeLinter one-multi-breakpoint-check），
   * 这里只回答"要不要接管原生标题栏"：PC 或自由窗口模式（含平板电脑模式）都要。
   *
   * 注意：此处绝不能调用 getUIContext() —— loadContent 之前窗口还没有 UIContent，
   * 调用会抛 "This window state is abnormal / 1300002" 并被系统按 JS 错误杀进程。
   */
  private readDesktopMode(win: window.Window): boolean {
    let free: boolean = false;
    try {
      free = win.isInFreeWindowMode();
    } catch (e) {
      // API < 22 / 非自由窗口能力设备：降级为设备类型判据（只影响 chrome，不影响布局）
      Logger.warn('isInFreeWindowMode unavailable: ' + String(e));
    }
    this.freeWindow = free;
    AppStorage.setOrCreate<boolean>('freeWindowMode', free);
    return deviceInfo.deviceType === '2in1' || free;
  }

  /** 自由窗口模式变化：写入 AppStorage 并让 DeviceProfile 重算快照（API 22，配 off） */
  private bindFreeWindowMode(win: window.Window): void {
    const listener: (isFree: boolean) => void = (isFree: boolean): void => {
      this.freeWindow = isFree;
      AppStorage.setOrCreate<boolean>('freeWindowMode', isFree);
      deviceProfile.refresh();
    };
    this.freeWindowListener = listener;
    try {
      win.on('freeWindowModeChange', listener);
    } catch (e) {
      Logger.warn('on freeWindowModeChange failed: ' + String(e));
    }
  }

  /**
   * 窗口前台/激活事件。
   * ACTIVE 时写 `windowActiveTick` 供旧的轮询式调用方使用；同时通知 DeviceProfile，
   * 由它转成订阅回调（AppStorage 不是响应式的，编辑器无法用 @StorageProp 监听）。
   */
  private bindStageEvents(windowStage: window.WindowStage): void {
    const listener: (event: window.WindowStageEventType) => void = (event: window.WindowStageEventType): void => {
      if (event === window.WindowStageEventType.ACTIVE) {
        AppStorage.setOrCreate<number>('windowActiveTick', Date.now());
        deviceProfile.notifyWindowActivated();
      }
    };
    this.stageListener = listener;
    try {
      windowStage.on('windowStageEvent', listener);
    } catch (e) {
      Logger.warn('on windowStageEvent failed: ' + String(e));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.info('Ability onWindowStageCreate');

    const mainWin: window.Window = windowStage.getMainWindowSync()
    this.mainWindow = mainWin
    this.contentReady = false

    AppStorage.setOrCreate<window.Window>('mainWindow', mainWin)

    // 电脑形态判据：PC 或 window.isInFreeWindowMode()（平板电脑模式 = 自由窗口）。
    // **不再**用 deviceInfo.deviceType 决定布局与断点，只用于 DeviceClass 归类。
    this.isDesktop = this.readDesktopMode(mainWin)
    AppStorage.setOrCreate<boolean>('isPcDevice', deviceInfo.deviceType === '2in1')
    this.bindFreeWindowMode(mainWin)
    this.bindStageEvents(windowStage)

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
        // 原生标题栏依赖已加载的 UIContent；全屏热区显隐也要独立配置。
        // 自绘栏的 48vp 高度由 DesktopTitleBar 通过 applyDesktopDecorMetrics 下发，
        // 这里只做"隐藏原生标题 + 保留 Dock"这一组（旧回归对调用序列有精确断言）。
        if (this.mainWindow === mainWin) {
          this.contentReady = true
          if (this.isDesktop) {
            configureDesktopChrome(mainWin)
          }
        }
        // 窗口底色由 SystemBars.applySystemBars 统一设为主题底色（勿在此设回透明）：
        // 状态栏全透明后，状态栏区域由窗口底色/根背景承托，须与页面同色。
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
    this.contentReady = false
    // 窗口级监听随窗口走：这里显式 off，避免窗口重建后重复回调
    const win: window.Window | null = this.mainWindow
    const freeCb: ((isFree: boolean) => void) | null = this.freeWindowListener
    if (win !== null && freeCb !== null) {
      try {
        win.off('freeWindowModeChange', freeCb)
      } catch (e) {
        Logger.warn('off freeWindowModeChange failed: ' + String(e))
      }
    }
    this.freeWindowListener = null
    this.stageListener = null
    this.mainWindow = null
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
    // 窗口可能在被切到后台期间进出自由窗口模式（如平板插拔键盘进入电脑模式）：前台重读一次
    if (this.mainWindow !== null) {
      this.isDesktop = this.readDesktopMode(this.mainWindow)
    }
    if (this.isDesktop && this.contentReady && this.mainWindow !== null) {
      configureDesktopChrome(this.mainWindow)
    }
    // 前台时窗口才真正就绪；按实际主题同步系统栏前景色
    app.ui.syncSystemBars()
  }

  onBackground(): void {
    // 退到后台立即落库：这是比"等 30 秒安全网"更可靠的一道保险
    app.flushAll();
    Logger.info('Ability onBackground');
  }
}
