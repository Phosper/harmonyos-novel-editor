import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { PreferenceHelper } from '@ohos/common'
import { DatabaseHelper } from '@ohos/common'

const DOMAIN: number = 0x0000
const TAG: string = 'Weaver'

export default class MainAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'MainAbility onCreate')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, 'MainAbility onWindowStageCreate')

    try {
      // Initialize database
      const db: DatabaseHelper = DatabaseHelper.getInstance()
      await db.init(this.context)
      hilog.info(DOMAIN, TAG, 'Database initialized successfully')

      // Initialize preferences
      const prefs: PreferenceHelper = PreferenceHelper.getInstance()
      await prefs.init(this.context)

      // Check if first launch
      const isFirstLaunch: boolean = await prefs.isFirstLaunch()

      if (isFirstLaunch) {
        windowStage.loadContent('pages/GuideSwiperPage', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'GuideSwiperPage load failed: code=%{public}d', err.code)
          }
        })
      } else {
        windowStage.loadContent('pages/Index', (err) => {
          if (err.code) {
            hilog.error(DOMAIN, TAG, 'Index load failed: code=%{public}d', err.code)
          }
        })
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Initialization failed')
      // Fallback: load index directly
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
}
