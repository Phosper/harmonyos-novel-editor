// 统一日志 —— 替代旧版散落的空 catch 与 console.info
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x005702
const TAG: string = 'Weaver'

export class Logger {
  static debug(message: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', message)
  }

  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message)
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message)
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message)
  }
}
