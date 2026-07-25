import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferenceHelper } from '@ohos/common'
import { DatabaseHelper } from '@ohos/common'
import { BreakpointService } from '@ohos/common'

const DOMAIN: number = 0x0000
const TAG: string = 'Weaver'

interface ContinueData {
  bookId: string
  chapterId: string
  chapterTitle: string
  cursorPosition: number
  timestamp: number
}

export default class MainAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onCreate')
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onNewWant')
    const data: ContinueData | undefined = this.parseContinueData(want)
    if (data !== undefined) {
      AppStorage.setOrCreate('continueData', data)
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN, TAG, 'MainAbility onContinue')
    const prefs: PreferenceHelper = PreferenceHelper.getInstance()
    if (!prefs.isInitialized()) {
      return AbilityConstant.OnContinueResult.REJECT
    }
    const currentBookId: string = AppStorage.get<string>('continue_bookId') ?? ''
    const currentChapterId: string = AppStorage.get<string>('continue_chapterId') ?? ''
    const currentTitle: string = AppStorage.get<string>('continue_title') ?? ''
    const cursorPos: number = AppStorage.get<number>('continue_cursor') ?? 0

    wantParam['continueData'] = JSON.stringify({
      bookId: currentBookId,
      chapterId: currentChapterId,
      chapterTitle: currentTitle,
      cursorPosition: cursorPos,
      timestamp: Date.now()
    })
    return AbilityConstant.OnContinueResult.AGREE
  }

  parseContinueData(want: Want): ContinueData | undefined {
    const params: Record<string, Object> | undefined = want.parameters
    if (params === undefined) return undefined
    const raw: Object | undefined = params['continueData']
    if (raw === undefined) return undefined
    try {
      const parsed: ContinueData = JSON.parse(raw as string) as ContinueData
      return parsed
    } catch (e) {
      return undefined
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, 'MainAbility onWindowStageCreate')

    try {
      const db: DatabaseHelper = DatabaseHelper.getInstance()
      await db.init(this.context)

      // Cache UIAbilityContext for file export
      AppStorage.setOrCreate('uiAbilityContext', this.context)

      const prefs: PreferenceHelper = PreferenceHelper.getInstance()
      await prefs.init(this.context)

      // Initialize breakpoint BEFORE loadContent so Index renders correct layout
      const mainWin: window.Window = await windowStage.getMainWindow()
      BreakpointService.getInstance().init(mainWin)

      // Initialize colorMode from current system configuration
      const currentColorMode: number = this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      AppStorage.setOrCreate('colorMode', currentColorMode)

      // Cache window for PcTitleBar interactions
      AppStorage.setOrCreate('mainWindow', mainWin)

      const isFirstLaunch: boolean = await prefs.isFirstLaunch()

      // Mark guided on first launch to skip guide page for testing
      if (isFirstLaunch) {
        await prefs.setGuided()
        await prefs.setMode('professional')
      }

      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Index load failed: code=%{public}d', err.code)
          return
        }
        try {
          mainWin.setWindowDecorVisible(false)
          mainWin.setWindowDecorHeight(40)
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'Window decor config failed')
        }
      })
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Initialization failed')
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Index fallback load failed')
        }
      })
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onBackground')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onDestroy')
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onConfigurationUpdate, colorMode=%{public}d', newConfig.colorMode ?? -1)
    const cm: number = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    AppStorage.setOrCreate('colorMode', cm)
  }
}
