import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { promptAction, window } from '@kit.ArkUI'
import { applyAppColorMode, rememberAppContext } from '../utils/AppChromeMode'
import { refreshDecorColorScheme } from '../utils/DesktopWindowChrome'
import { ezCustomTransition } from '../thirdparty/ezcustomtransition/Index'
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { prefs } from '../utils/PreferenceHelper';
import { setAppContext } from '../utils/AppContext';
import { Logger } from '../utils/Logger';
import { app } from '../store/AppStores';
import { configureDesktopChrome, restoreDesktopChrome } from '../utils/DesktopWindowChrome';
import { deviceProfile } from '../utils/DeviceProfile';
import { tokensFor, WeaverColorSet } from '../constants/DesignTokens'
import { ExportService } from '../utils/ExportService'
import type { EditorDraftSnapshot } from '../store/EditorStore'

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  /** 是否电脑形态（PC 或自由窗口/平板电脑模式）：只决定是否接管原生标题栏 */
  private isDesktop: boolean = false;
  /** 自由窗口模式（window.isInFreeWindowMode()，API 22）：桌面 chrome 的唯一判据 */
  private freeWindow: boolean = false;
  private contentReady: boolean = false;
  private freeWindowListener: ((isFree: boolean) => void) | null = null;
  private stageListener: ((event: window.WindowStageEventType) => void) | null = null;
  private windowStage: window.WindowStage | null = null;
  private closeListener: (() => Promise<boolean>) | null = null
  private closeWindow: window.Window | null = null
  private closePending: boolean = false
  private closeDialogWindow: window.Window | null = null

  /** 窗口状态监听（最大化/还原后重发三键样式） */
  private decorStatusListener: ((status: window.WindowStatusType) => void) | null = null

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    setAppContext(this.context)
    // 系统 chrome（三键 / 系统菜单）跟随应用主题：登记 ApplicationContext，后续 setTheme 会下发
    rememberAppContext(this.context.getApplicationContext())
    // 窗口在主窗创建前就固定 colorMode（系统三键的颜色由它决定）。默认主题是浅色，
    // 先按浅色建窗，避免"系统深色 + 应用浅色纸墨"时三键被画成白色；
    // 用户如果用夜读，loadFromPrefs 会再改回来并重建三键。
    applyAppColorMode(false)
    Logger.info('Ability onCreate');
  }

  onDestroy(): void {
    this.onWindowStageDestroy()
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
      free = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc';
    }
    this.freeWindow = free;
    AppStorage.setOrCreate<boolean>('freeWindowMode', free);
    return deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc' || free;
  }

  /** 自由窗口模式变化：写入 AppStorage 并让 DeviceProfile 重算快照（API 22，配 off） */
  private bindFreeWindowMode(win: window.Window): void {
    const listener: (isFree: boolean) => void = (isFree: boolean): void => {
      if (this.mainWindow !== win) { return }
      const wasDesktop: boolean = this.isDesktop
      this.freeWindow = isFree;
      this.isDesktop = isFree || deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc'
      AppStorage.setOrCreate<boolean>('freeWindowMode', isFree);
      if (this.contentReady) {
        if (this.isDesktop) {
          configureDesktopChrome(win)
          this.watchWindowStatus(win)
        } else if (wasDesktop) {
          this.unwatchWindowStatus()
          restoreDesktopChrome(win)
        }
        this.syncCloseListener(win)
      }
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
    this.windowStage = windowStage
    const listener: (event: window.WindowStageEventType) => void = (event: window.WindowStageEventType): void => {
      if (this.windowStage !== windowStage) { return }
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
    if (this.mainWindow !== null) {
      this.onWindowStageDestroy()
    }
    // 一镜到底转场：注册窗口/装饰信息（必须在 loadContent 前）
    ezCustomTransition.init(windowStage);

    const mainWin: window.Window = windowStage.getMainWindowSync()
    this.mainWindow = mainWin
    this.contentReady = false

    AppStorage.setOrCreate<window.Window>('mainWindow', mainWin)

    // 电脑形态判据：PC 或 window.isInFreeWindowMode()（平板电脑模式 = 自由窗口）。
    // **不再**用 deviceInfo.deviceType 决定布局与断点，只用于 DeviceClass 归类。
    this.isDesktop = this.readDesktopMode(mainWin)
    AppStorage.setOrCreate<boolean>('isPcDevice', deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc')
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
      if (this.mainWindow !== mainWin) { return }
      windowStage.loadContent(url, (err: BusinessError) => {
        if (this.mainWindow !== mainWin) { return }
        if (err.code) {
          Logger.error('Failed to load the content: ' + JSON.stringify(err));
          return;
        }
        Logger.info('Succeeded in loading the content.');
        // 原生标题栏依赖已加载的 UIContent；全屏热区显隐也要独立配置。
        // 48vp 装饰栏高度 / 三键颜色由 DesktopTitleBar（引导页）或 UiStore.syncSystemBars()
        // （主工作台）通过 applyDesktopDecorMetrics 下发；这里只做"隐藏原生标题 + 保留 Dock"，
        // 保持旧回归对调用序列的精确断言。
        if (this.mainWindow === mainWin) {
          this.contentReady = true
          // 首帧已就绪：此后允许重建装饰栏（避免启动闪一下原生标题栏）
          AppStorage.setOrCreate<boolean>('uiReady', true)
          if (this.isDesktop) {
            configureDesktopChrome(mainWin)
            // 窗口按浅色创建（默认主题）；只有用户实际选的是深色时才需要重建三键，
            // 避免浅色主题下每次启动都闪一下原生标题栏。
            if (app.ui.darkMode) {
              refreshDecorColorScheme(true)
            }
            this.watchWindowStatus(mainWin)
          }
          this.syncCloseListener(mainWin)
        }
        // 全屏布局（沉浸式）必须在内容加载成功后再下一次：
        // `setWindowLayoutFullScreen` 依赖已加载的 UIContent，早了会静默失败 ——
        // 失败后状态栏/导航条仍是不透明的系统底色，页面背景再 expandSafeArea 也画不进去
        // （平板实测：顶部一条白/黑带，与纸色割裂）。
        mainWin.setWindowLayoutFullScreen(true).then(() => {
          if (this.mainWindow !== mainWin) { return }
          Logger.info('setWindowLayoutFullScreen ok (after content)')
          app.ui.syncSystemBars()
        }).catch((e: Error) => {
          Logger.warn('setWindowLayoutFullScreen after content failed: ' + String(e))
        })
        // 窗口底色由 SystemBars.applySystemBars 统一设为主题底色（勿在此设回透明）：
        // 状态栏全透明后，状态栏区域由窗口底色/根背景承托，须与页面同色。
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
    this.unbindCloseListener()
    this.unwatchWindowStatus()
    this.closePending = false
    this.closeDialogWindow = null
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
    const stage: window.WindowStage | null = this.windowStage
    const stageCb: ((event: window.WindowStageEventType) => void) | null = this.stageListener
    if (stage !== null && stageCb !== null) {
      try {
        stage.off('windowStageEvent', stageCb)
      } catch (e) {
        Logger.warn('off windowStageEvent failed: ' + String(e))
      }
    }
    this.stageListener = null
    this.windowStage = null
    deviceProfile.detach()
    if (AppStorage.get<window.Window>('mainWindow') === win) {
      AppStorage.delete('mainWindow')
      AppStorage.setOrCreate<boolean>('uiReady', false)
    }
    this.mainWindow = null
    Logger.info('Ability onWindowStageDestroy');
  }

  /** 窗口状态变化（最大化/还原/全屏）后重新下发三键样式与系统栏配色 */
  private watchWindowStatus(w: window.Window): void {
    if (this.decorStatusListener !== null) {
      return
    }
    const cb: (status: window.WindowStatusType) => void = (status: window.WindowStatusType) => {
      if (this.mainWindow !== w || status === window.WindowStatusType.UNDEFINED) {
        return
      }
      app.ui.syncSystemBars()
    }
    this.decorStatusListener = cb
    try {
      w.on('windowStatusChange', cb)
    } catch (e) {
      Logger.warn('on windowStatusChange failed: ' + String(e))
      this.decorStatusListener = null
    }
  }

  private unwatchWindowStatus(): void {
    const cb: ((status: window.WindowStatusType) => void) | null = this.decorStatusListener
    if (cb === null || this.mainWindow === null) {
      return
    }
    try {
      this.mainWindow.off('windowStatusChange', cb)
    } catch (e) {
      Logger.warn('off windowStatusChange failed: ' + String(e))
    }
    this.decorStatusListener = null
  }

  /** 原生三键继续由系统绘制；API 15+ 异步关闭回调等待严格保存。 */
  private syncCloseListener(win: window.Window): void {
    if (this.mainWindow !== win || !this.contentReady || !this.freeWindow) {
      this.unbindCloseListener()
      return
    }
    if (this.closeWindow === win && this.closeListener !== null) { return }
    this.unbindCloseListener()
    const listener: () => Promise<boolean> = (): Promise<boolean> => this.handleWindowWillClose(win)
    try {
      win.on('windowWillClose', listener)
      this.closeWindow = win
      this.closeListener = listener
    } catch (e) {
      Logger.warn('on windowWillClose failed: ' + String(e))
    }
  }

  private unbindCloseListener(): void {
    const win: window.Window | null = this.closeWindow
    const listener: (() => Promise<boolean>) | null = this.closeListener
    this.closeWindow = null
    this.closeListener = null
    if (win !== null && listener !== null) {
      try {
        win.off('windowWillClose', listener)
      } catch (e) {
        Logger.warn('off windowWillClose failed: ' + String(e))
      }
    }
  }

  /** true 阻止关闭；reject 会让系统继续关闭，因此所有失败必须收敛成 true。 */
  private async handleWindowWillClose(win: window.Window): Promise<boolean> {
    if (this.mainWindow !== win || this.closeWindow !== win || this.closePending ||
      this.closeDialogWindow !== null) { return true }
    this.closePending = true
    try {
      await app.flushAllStrict()
      return this.mainWindow !== win || this.closeWindow !== win
    } catch (e) {
      Logger.warn('windowWillClose: strict save failed: ' + String(e))
      if (this.mainWindow === win) {
        this.showCloseBlockedDialog(win)
      }
      return true
    } finally {
      if (this.mainWindow === win) { this.closePending = false }
    }
  }

  private showCloseBlockedDialog(win: window.Window): void {
    if (this.mainWindow !== win || this.closeDialogWindow !== null) { return }
    this.closeDialogWindow = win
    try {
      const colors: WeaverColorSet = tokensFor(app.ui.themeId)
      const retry: promptAction.Button = { text: '重试保存', color: colors.brand }
      const exportDraft: promptAction.Button = { text: '导出草稿', color: colors.textPrimary }
      const discard: promptAction.Button = { text: '放弃并退出', color: colors.danger }
      win.getUIContext().getPromptAction().showDialog({
        title: '尚有未保存内容',
        message: '保存失败，窗口已保持打开。可重试保存，先导出草稿，或明确放弃本次修改。',
        buttons: [retry, exportDraft, discard]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (this.closeDialogWindow !== win || this.mainWindow !== win) { return }
        this.closeDialogWindow = null
        if (result.index === 0) {
          this.retryClose(win)
        } else if (result.index === 1) {
          this.exportDraftsBeforeClose(win)
        } else if (result.index === 2) {
          this.terminateWindow(win)
        }
      }).catch((e: Error) => {
        if (this.closeDialogWindow === win) { this.closeDialogWindow = null }
        Logger.warn('close-blocked dialog failed: ' + String(e))
      })
    } catch (e) {
      this.closeDialogWindow = null
      Logger.warn('close-blocked dialog unavailable: ' + String(e))
    }
  }

  private retryClose(win: window.Window): void {
    this.handleWindowWillClose(win).then((blocked: boolean) => {
      if (!blocked) { this.terminateWindow(win) }
    }).catch((e: Error) => {
      Logger.warn('retry close failed; window kept open: ' + String(e))
    })
  }

  private exportDraftsBeforeClose(win: window.Window): void {
    if (this.mainWindow !== win) { return }
    try {
      const drafts: EditorDraftSnapshot[] = app.editor.snapshotDrafts()
      const payload: string = JSON.stringify({
        exportedAt: new Date().toISOString(), reason: 'close-blocked-unsaved', drafts: drafts
      }, null, 2)
      ExportService.saveText('Weaver-未保存草稿-' + Date.now().toString() + '.json', payload)
        .then((ok: boolean) => {
          if (this.mainWindow !== win) { return }
          win.getUIContext().getPromptAction().showToast({
            message: ok ? '草稿已导出，可重试保存后再关闭' : '导出取消或失败，草稿仍在窗口中'
          })
        }).catch((e: Error) => { Logger.warn('export drafts failed: ' + String(e)) })
    } catch (e) {
      Logger.warn('export drafts unavailable: ' + String(e))
    }
  }

  private terminateWindow(win: window.Window): void {
    if (this.mainWindow !== win) { return }
    try {
      this.context.terminateSelf().catch((e: Error) => {
        Logger.warn('terminateSelf failed: ' + String(e))
      })
    } catch (e) {
      Logger.warn('terminateSelf threw: ' + String(e))
    }
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
      const wasDesktop: boolean = this.isDesktop
      this.isDesktop = this.readDesktopMode(this.mainWindow)
      if (wasDesktop && !this.isDesktop && this.contentReady) {
        this.unwatchWindowStatus()
        restoreDesktopChrome(this.mainWindow)
      }
      if (this.contentReady) {
        this.syncCloseListener(this.mainWindow)
      }
      deviceProfile.refresh()
    }
    if (this.isDesktop && this.contentReady && this.mainWindow !== null) {
      configureDesktopChrome(this.mainWindow)
      this.watchWindowStatus(this.mainWindow)
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
