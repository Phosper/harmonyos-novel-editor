// AbilityStage：一镜到底转场的配置变更入口
//
// ezcustomtransition 需要在配置变化（深浅色/语言/窗口形态）时刷新内部转场参数，
// 否则动画起始/结束尺寸会沿用旧配置。这里只做转发，不承载业务逻辑。
import { AbilityStage, Configuration } from '@kit.AbilityKit'
import { ezCustomTransition } from '../thirdparty/ezcustomtransition/Index'

export default class MyAbilityStage extends AbilityStage {
  onConfigurationUpdate(newConfig: Configuration): void {
    ezCustomTransition.onConfigurationChanged()
  }
}
