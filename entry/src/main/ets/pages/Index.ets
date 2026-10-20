// 应用入口
//
// Navigation 现在位于 AppShell 内部（作为三分栏模型的第二/三栏，与 SideBarContainer 组合），
// 因此这里不再需要 @Provider 提供 navStack。
//
// 路由栈放在 shell/Navigator.ets 的模块级单例中：二级页面与各面板都能直接发起跳转，
// 避免逐层 @Event 透传。
import { AppShell } from '../shell/AppShell'
import { app } from '../store/AppStores'
import { pageGlow } from '../constants/LightTokens'

@Entry
@ComponentV2
struct Index {
  build() {
    // @Entry 的 build 根节点必须是容器组件，故包一层 Column。
    // 兜底铺一层页面光感渐变（AppShell 内部的 GlowPageBackground 是主层；
    // 这里保证加载中/窗口边角也是"上亮下暗"，不会闪出纯色底）。
    Column() {
      AppShell()
    }
    .width('100%').height('100%')
    .linearGradient({ angle: 180, colors: pageGlow(app.ui.themeId) })
  }
}
