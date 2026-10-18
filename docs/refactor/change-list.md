# 多端交互重构 · 改动清单

> 范围：2026-10-18「多端交互重构与沉浸视觉升级」的 T1（编辑器输入归一）、T2（设备分流 + 沉浸标题栏）、
> T3（沉浸光感）交付，以及 T4 的回归与文档。契约见
> [multidevice-interaction-refactor.md](multidevice-interaction-refactor.md)。
> 行号对应当前工作树（源码最后修改 2026-10-18 03:53，Asia/Shanghai）。
> 路径均相对 `entry/src/main/ets/`，链接目标从本文件 `docs/refactor/` 出发。

## 验证状态

**本机没有 hvigor / HarmonyOS SDK / 模拟器 / hdc，未执行编译。本文不声称 `BUILD SUCCESSFUL`，
也不声称 Hypium 已通过；设备侧请按 [multidevice-self-test.md](multidevice-self-test.md) 执行。**

已完成的是静态检查与 Node 回归（`node tools/*.cjs`，全部 `exit=0`）：

| 脚本 | 检查项 | 输出 |
|---|---|---|
| `tools/arkts-guard.cjs` | 17 | `ArkTS guard: 17 checks passed (33 files scanned, 2 warning(s))` |
| `tools/device-profile-regression.cjs` | 25 | `Device profile regression: 25 checks passed` |
| `tools/flowtext-regression.cjs` | 97 | `FlowText regression: 97 checks passed` |
| `tools/window-regression.cjs` | 32 | `Window regression: 32 checks passed` |
| `tools/data-regression.cjs` | 28 | `Data regression: 28 checks passed` |
| `tools/shell-regression.cjs` | 20 | `Shell regression: 20 checks passed` |
| `tools/import-regression.cjs` | 5 | `Import regression: 5 checks passed` |
| **合计** | **224** | 重构前 130 项全部保留并通过，新增 94 项 |

`arkts-guard` 的 2 条 warning 是历史存量 `console.*`（`CanvasTextEditor.ets` 1 处诊断日志、
`ImeBridge.ets` 2 处 attach/清理告警），按约定只告警不失败；新代码一律用 `Logger`。

## T1 编辑器输入归一

| 文件 | 类型 | 关键行 | 作用 |
|---|---|---|---|
| [EditCommand.ets](../../entry/src/main/ets/editor/interaction/EditCommand.ets) | 新增 | 12 enum `EditCommandKind`；45 `EditorInputSource`；53 `EditorModifiers`；61 `get primary`；80 `EditCommand`；101 `isCaretCommand`；111 `isEditingCommand` | 统一命令对象与分类，输入层只产命令、不写业务分支 |
| [ShortcutMap.ets](../../entry/src/main/ets/editor/interaction/ShortcutMap.ets) | 新增 | 25–33 `SC_KEY_*`；36 `isPrintableKeyCode`；62 `resolveKeyText`；73 `resolvePrimaryChord`；135 `resolveShortcut`；143 Tab→NONE；146 Ctrl/Meta 优先；154 Alt 交还系统 | 键位表：Ctrl+A/C/X/V/Z/Y、Ctrl+Shift+Z、Ctrl+S/F/B/I、Ctrl+Home/End、Ctrl+←/→、Ctrl+Backspace、PageUp/Down、Home/End、Enter、Esc；**Tab 不消费**；组字中全部放行 |
| [EditorCommandRouter.ets](../../entry/src/main/ets/editor/interaction/EditorCommandRouter.ets) | 新增 | 14 `EditCommandHost`（全基本类型参数）；47 `EditorCommandRouter`；52 `dispatch` | 唯一分发点，按命令调用宿主，禁止跨层传 class 实例 |
| [InputArbiter.ets](../../entry/src/main/ets/editor/interaction/InputArbiter.ets) | 新增 | 16 `shouldConsumePreIme`；51 `ImeEchoGuard`；58 `recordKeyboardFallback`；70 `claim`；92 `reset` | preIme 消费策略 + 40ms IME 回声抑制（一条兜底只吞一条） |
| [CanvasTextEditor.ets](../../entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets) | 修改 | 36–40 导入命令层；257/259 `@Prop desktopMode/pointerPrimary`；322/324 `focused/imeUsable`；326 `echoGuard`；328 `commandRouter`；330 `hostAdapter`；763 `.onMouse`（806 右键）；834 `.onAxisEvent`（滚轮只滚动）；1030–1045 IME attach 结果 → `imeUsable`；1058 `applyPointerCursor`；1276 `handleKeyEvent`；1308 `handleKeyPreIme`；2648 `insertFromKeyboard`（先登记回声再插入）；2668 `dispatchCommand`；2672 `editHost`；2684 `adoptKeyFocus`（收到按键即校正 `focused`）；2694 `moveWordOnce`；2717 `deleteWordBackwardFromKeyboard`；2832 `handleMenuKey`（Esc/方向键/Enter）；2900–2935 `host*` 落点；2945 `CanvasEditCommandHost` 适配器 | 改为命令层分发；不再因内部 `focused` 丢键；Tab 不再插空格；右键菜单键盘化；滚轮不移动光标；指针优先时光标为 `TEXT_CURSOR` |
| [TextEditorHost.ets](../../entry/src/main/ets/editor/TextEditorHost.ets) | 修改 | 46 `@Prop desktopMode`；48 `@Prop pointerPrimary`；79/86/137–139 `onWindowActivated` 订阅与释放；159–160 透传给 CanvasTextEditor | 电脑/键鼠形态透传（V1 岛屿只传布尔），ACTIVE 时恢复编辑器焦点 |
| [EditorPane.ets](../../entry/src/main/ets/shell/EditorPane.ets) | 修改 | 44 工具条显示条件；69–70 传入 `desktopMode/pointerPrimary` | 电脑/键鼠显示格式工具条，手机保持最小 chrome |

## T2 设备分流与沉浸标题栏

| 文件 | 类型 | 关键行 | 作用 |
|---|---|---|---|
| [DeviceProfile.ets](../../entry/src/main/ets/utils/DeviceProfile.ets) | 新增 | 23 `DeviceClass`；30 `InputModality`；37 `LayoutTier`；47 `DeviceSnapshot`；63 `tier`；74 `isDesktopChrome`；79 `pointerPrimary`；85 `detectDeviceClass`；111 `modalityFor`；133 `DeviceProfileService`；154 `attach`；178 `detach`；218 `refresh`；235 `onChange`；249 `onWindowActivated`；260 `notifyWindowActivated`；273 `notePointerActivity`；283 `bindWindow`；318 `readFreeWindow`；333 `readBreakPoint`；345 `readWindowStatus`；363 `emit`；379 单例 | 三条正交判据（断点/形态/输入）；窗口监听只注册一次；单订阅方异常隔离；`isInFreeWindowMode` 抛错回退 AppStorage 且只告警一次 |
| [UiStore.ets](../../entry/src/main/ets/store/UiStore.ets) | 修改 | 46/48/50/52 `@Trace deviceClass/freeWindowMode/pointerPrimary/isPcDevice`；125 `isWide`；133 `isDesktopMode`；138 `isTabletDevice`；143 `usesDesktopChrome`；148 `isPc`（兼容）；156 `applyDeviceSnapshot` | 供所有 UI 读取的统一快照；`isPc` 语义改为 `isDesktopMode && isWide` |
| [DesktopTitleBar.ets](../../entry/src/main/ets/shell/DesktopTitleBar.ets) | 新增 | 36 struct；37–41 `@Param app/safeTop/chromeHeight`；44/46 `@Local windowStatus/titleButtonWidth`；52 `aboutToAppear`；69 `aboutToDisappear`；79 `win`；84 `applyChrome`；96 `readStatus`；109 `refreshTitleButtonRect`（值不变不写 @Local）；121 `bindWindowListeners`；152 `unbindWindowListeners`（同一回调引用 off）；179 `startMove`；193 `minimize`；207 `toggleMaximize`；236 `close`（先 flushAll 再 terminateSelf）；254 `hostContext`；263 `terminate`；276 `onTitleTouch`（仅 `TouchType.Down`）；283 `onTitleMouse`（仅左键 Press + 升级指针形态）；302 `barTitle`；311 `barHeight`；327 `build`（48vp + safeTop，三键 46×48，accessibilityText，hoverEffect，focusable+tabStop，右避让 titleButtonWidth） | 沉浸标题栏：拖拽/双击最大化/三键/监听收口/关闭落库/无障碍 |
| [DesktopWindowChrome.ets](../../entry/src/main/ets/utils/DesktopWindowChrome.ets) | 修改 | 21 `DESKTOP_CHROME_HEIGHT_VP=48`；36 `configureDesktopChrome`（旧调用序列逐字保留）；61 `applyDesktopDecorMetrics`（高度 + 三键图标）；75 `configureImmersiveDesktopChrome`；87 `readTitleButtonWidthVp`；97 `isMaximizedStatus` | 原生装饰栏接管；尺寸配置单独拆出，避免破坏旧回归的调用序列 |
| [SafeArea.ets](../../entry/src/main/ets/utils/SafeArea.ets) | 修改 | 37 `readSafeArea(win?)`；57 `safeTopVp`；61 `safeBottomVp`；71 `watchSafeArea`（单一监听、幂等、返回解绑函数） | 全屏布局后读避让区；显式传窗口避免 AppStorage 时序问题 |
| [EntryAbility.ets](../../entry/src/main/ets/entryability/EntryAbility.ets) | 修改 | 26 `onDestroy` 兜底落库；41 `readDesktopMode`；44 `isInFreeWindowMode`；55 `bindFreeWindowMode`（写 AppStorage + 刷新 DeviceProfile）；74 `bindStageEvents`（ACTIVE → `windowActiveTick` + `notifyWindowActivated`）；89 `onWindowStageCreate`；108 `setWindowLayoutFullScreen(true)`；114–126 `loadContent` 成功后才接管原生 chrome；166 `onWindowStageDestroy` | 自由窗口初值与监听；避免 loadContent 前调用 `getUIContext()` |
| [AppShell.ets](../../entry/src/main/ets/shell/AppShell.ets) | 修改 | 71/125 `bindDeviceProfile`；129 `deviceProfile.onChange`；136 `attach(getUIContext, win)`；153 `handleSnapshot`；182 `topInset`（chrome 模式返回 0，防双算）；201 `navBarWidthVp`；220/227 侧栏宽度按 `usesDesktopChrome`；249 `GlowPageBackground`；254–258 `DesktopTitleBar`；280 `padding({top: topInset, bottom: safeBottom})`；283 `expandSafeArea`；292 `onHover` 升级指针形态 | 标题栏作为安全区下第一行；手机/平板保持原避让；断点变化同步快照 |
| [PcWindowBar.ets](../../entry/src/main/ets/shell/PcWindowBar.ets) | 修改 | 17 struct；20–101 原有 7 个窗口控制方法逐字保留；103–105 `build` 直接渲染 `DesktopTitleBar` | 兼容薄壳：旧回归从本文件抽取方法；新视觉统一到 DesktopTitleBar |
| [SystemBars.ets](../../entry/src/main/ets/utils/SystemBars.ets) | 修改 | 18 `OVERLAY_MASK_COLOR='#66000000'`；21 `contentFor`（8 位 ARGB）；26 `argbOf`；46 `setBars`；50 `statusBarContentColor`；61/76 常态与压暗 | 系统栏前景必须是 8 位 ARGB，避免被系统忽略 |
| [module.json5](../../entry/src/main/module.json5) | 修改 | 7–11 `deviceTypes phone/tablet/2in1`；16–21 `metadata ohos.arkui.UIMaterial.state = enable` | API 26 沉浸材质使能（仅 entry 生效） |

## T3 沉浸光感

| 文件 | 类型 | 关键行 | 作用 |
|---|---|---|---|
| [LightTokens.ets](../../entry/src/main/ets/constants/LightTokens.ets) | 新增 | 21 `WeaverGlassLevel`；28 `WeaverGlassKind`；37 动效 180ms；39 `GLASS_MAX_BLUR_LAYERS=2`；46 `WeaverGlassSpec`；82 `glassAlpha`（6/8 位 → 8 位 ARGB）；100 `immersiveSupported`（缓存一次）；116 `materialLevel`；132 `materialAvailable`；148 `glassLevel`；159 `blurEnabled`；189 `immersiveMaterial`；211 `sheetMaterial`；216 `chromeMaterial`；229 `GLASS_NONE_GRADIENT`；325 `glassSpec`；338–358 `chromeGlass/cardGlass/panelGlass/veilGlass/sheenGlass`；363 `pageGlow`；390 `glowHalo`；407/409 光晕参数 | 材质能力探测与三级降级（FULL/REDUCED/OFF）；四主题色板与缓存，避免每帧构造 |
| [MaterialSurface.ets](../../entry/src/main/ets/shell/MaterialSurface.ets) | 新增 | 50 `WeaverGlassModifier`；61 `applyNormalAttribute`（FULL 才 `backgroundBlurStyle`，否则 `gradientSolid`）；131–156 六个 `glass*Style`；167/168 `GlowPageBackground`（一层、`hitTestBehavior(None)`、`accessibilityLevel('no')`）；191/192 `GlassBar`；201/202 `GlassCard`；211/212 `GlassPanel`；224 `systemMaterialFor` | 属性修改器按主题缓存；玻璃面统一实现；降级路径零模糊 |

**覆盖矩阵**（契约 §4 要求的全部位置）

| 位置 | 关键行 | 玻璃面 |
|---|---|---|
| [AppShell.ets](../../entry/src/main/ets/shell/AppShell.ets) | 249 页面背景；435 顶栏/侧栏头 | `GlowPageBackground` + `glassBarStyle` |
| [DesktopTitleBar.ets](../../entry/src/main/ets/shell/DesktopTitleBar.ets) | 400 | `glassBarStyle`（实时模糊层 ①） |
| [MobileShell.ets](../../entry/src/main/ets/shell/MobileShell.ets) | 61 页面背景；168 标题栏 | `GlowPageBackground` + `glassBarStyle` |
| [DocListPane.ets](../../entry/src/main/ets/shell/DocListPane.ets) | 224 | `glassBarStyle`（列表头） |
| [ProjectSidebar.ets](../../entry/src/main/ets/shell/ProjectSidebar.ets) | 91/126 选中薄纱；152 侧栏底 | `sheenGlass` + `bgSurface`（零模糊） |
| [WorkspaceDest.ets](../../entry/src/main/ets/shell/WorkspaceDest.ets) | 290 | 宽屏 `glassVeilStyle` / 窄屏 `glassBarStyle` |
| [InputDialog.ets](../../entry/src/main/ets/shell/InputDialog.ets) | 79 | `glassPanelStyle`（浮层） |
| [MobileTabBar.ets](../../entry/src/main/ets/shell/MobileTabBar.ets) | 58 | `glassTabBarStyle`（实时模糊层 ②） |
| [MobileSectionTabs.ets](../../entry/src/main/ets/shell/MobileSectionTabs.ets) | 49 | `glassVeilStyle` |
| [SettingsPanel.ets](../../entry/src/main/ets/shell/SettingsPanel.ets) | 34 | `sheenGlass`（主题选中） |
| [Index.ets](../../entry/src/main/ets/pages/Index.ets) | 23 | `pageGlow`（兜底层） |
| [GuideSwiperPage.ets](../../entry/src/main/ets/pages/GuideSwiperPage.ets) | 72 | `GlowPageBackground` |
| [SettingsDest.ets](../../entry/src/main/ets/pages/dest/SettingsDest.ets) | 22/30 | `GlowPageBackground` + `glassBarStyle` |
| [EditorPane.ets](../../entry/src/main/ets/shell/EditorPane.ets) | 239/400 | 浮动卡片与工具条（主题令牌） |

## T4 回归与交付文档

| 文件 | 类型 | 作用 |
|---|---|---|
| `tools/device-profile-regression.cjs` | 新增 | 25 项：`detectDeviceClass`（2in1/tablet/phone/异常）、`modalityFor`（含 pointerSeen 升级）、`DeviceSnapshot.tier/isDesktopChrome/pointerPrimary`、`attach/refresh` 快照、`readFreeWindow` 抛错回退 AppStorage、监听注册/注销、订阅/emit 异常隔离、`notePointerActivity` 幂等 |
| `tools/window-regression.cjs` | 扩展（17→32） | 原 17 项逐字保留；新增 DesktopTitleBar：沉浸装饰顺序、拖拽门控（触摸 Down / 左键 Press）、最大化/还原/全屏、图标与标题兜底、高度防双算、控制失败隔离、关闭先 flushAll 再 terminateSelf（含落库失败仍关闭）、监听注册与精确注销、状态/三键矩形回调、无窗口安全、PcWindowBar 薄壳 |
| `tools/flowtext-regression.cjs` | 扩展（60→81） | 原 60 项逐字保留；新增 ShortcutMap 全键位表（Ctrl+A/C/X/V/Z/Y、Ctrl+Shift+Z、Ctrl+S/F/B/I、Ctrl+Home/End、Ctrl+←/→、Ctrl+Backspace、PageUp/Down、Home/End、Enter、Esc、Tab→NONE）、`shouldConsumePreIme`、`ImeEchoGuard`（40ms/异文本/只吞一条/reset）、preIme 兜底与焦点校正、Esc 浮层、真实适配器 + 真实 IME 监听的回声抑制 |
| `tools/arkts-guard.cjs` | 新增 | 17 项静态红线（any/unknown、解构、对象展开、Object.assign、@Builder 链式、API≤26 基线、禁 `moveWindowTo`、startMoving 门控、8 位 statusBarContentColor、deviceType 不参与断点、模块级同名 const 仅同文件判重、152 条相对 import 的文件与导出符号存在性、console.* 限定存量、module.json5 元数据、材质降级、规则自检） |
| `docs/refactor/multidevice-self-test.md` | 新增 | 四形态自测清单（42 个用例：键鼠 18 + 标题栏 8 + 光感 8 + 触摸 8），每项「操作步骤 / 预期结果 / 失败判定」，附构建命令与 Hypium 判定 |
| `docs/refactor/change-list.md` | 新增 | 本文件 |
| `README.md` | 修改 | 构建/验证段落加入本次重构、208 项回归与设备自测入口 |

## API 版本依据

| 能力 | 官方接口 | 起始版本 | 本工程落点 |
|---|---|---|---|
| 自由窗口判定 | `window.Window.isInFreeWindowMode()` | 22 | `DeviceProfile.readFreeWindow`、`EntryAbility.readDesktopMode` |
| 自由窗口变化 | `on('freeWindowModeChange')` + `off` | 22 | `DeviceProfile.bindWindow`、`EntryAbility.bindFreeWindowMode` |
| 隐藏原生标题栏 | `setWindowDecorVisible(false)` | 11 | `configureDesktopChrome` |
| 标题栏高度 | `setWindowDecorHeight` / `getWindowDecorHeight` | 11 | `applyDesktopDecorMetrics`（48 ∈ [37,112]） |
| 三键区 | `getTitleButtonRect()` / `on('windowTitleButtonRectChange')` | 11 | `readTitleButtonWidthVp`、`DesktopTitleBar.bindWindowListeners` |
| 三键样式/显隐 | `setDecorButtonStyle()` / `setWindowTitleButtonVisible()` | 14 | `applyDesktopDecorMetrics` / `configureDesktopChrome` |
| 悬浮标题栏 | `setTitleAndDockHoverShown(false, true)` | 14 | `configureDesktopChrome`（保留 Dock） |
| 窗口拖动 | `startMoving()`（仅 `onTouch(TouchType.Down)`） | 14 | `DesktopTitleBar.onTitleTouch`、`PcWindowBar.onTitleTouch` |
| 窗口状态 | `getWindowStatus()` / `on('windowStatusChange')` | 12 / 11 | `DesktopTitleBar.readStatus`、`DeviceProfile.readWindowStatus` |
| 安全区 | `getWindowAvoidArea()` / `on('avoidAreaChange')` | 9 | `SafeArea.readSafeArea/watchSafeArea` |
| 沉浸材质 | `new uiMaterial.ImmersiveMaterial()` + `.systemMaterial()` | 26 | `LightTokens.immersiveMaterial`、`MaterialSurface.systemMaterialFor` |
| 材质能力探测 | `isImmersiveMaterialSupported()` / `getGlobalMaterialLevel()` / `getMaterialInfo()` | 26 | `LightTokens.immersiveSupported/materialLevel/materialAvailable` |
| 材质使能 | `module.json5` metadata `ohos.arkui.UIMaterial.state = enable` | 26 | `module.json5` 16–21 |
| 毛玻璃 | `backgroundBlurStyle(BlurStyle)` / `backgroundEffect({...})` | 11 | `MaterialSurface.applyNormalAttribute`（非标题栏区域） |
| 键鼠 | `onKeyEvent` / `onKeyPreIme` / `getModifierKeyState()` / `onMouse` / `onAxisEvent` / `onHover` | 11+ | `CanvasTextEditor`、`DesktopTitleBar`、`AppShell` |
| 指针光标 | `getCursorController().setCursor()` + `pointer.PointerStyle` | 12 | `CanvasTextEditor.applyPointerCursor` |
| 系统栏 | `setWindowSystemBarProperties`（8 位 ARGB 前景） | 9 | `SystemBars.setBars` |

`tools/arkts-guard.cjs` 会扫描上表所有接口名，断言其最小版本 ≤ 26，并拒绝 `moveWindowTo` 做拖动。

## 源码审阅备注（T4 只读，未修改 `entry/`）

1. **`pointerPrimary` 与契约字面不一致（低风险）**：契约 §1 定义为
   `modality !== TOUCH`，当前 [DeviceProfile.ets:79](../../entry/src/main/ets/utils/DeviceProfile.ets#L79)
   实现为 `modality === POINTER`。目前 `modalityFor` 只会产出 `TOUCH/POINTER`（`MIXED` 未使用），
   两者行为等价；若后续启用 `MIXED`，需按契约改回 `!== TOUCH`。回归测试已按当前实现断言并注明。
2. **`modalityFor` 注释与实际不一致（文档级）**：[DeviceProfile.ets:103–110](../../entry/src/main/ets/utils/DeviceProfile.ets#L103-L110)
   的函数注释仍写"平板 = 触摸为主、键鼠可选（MIXED）"，而实现与紧随其后的行内注释一致地返回
   `TOUCH`（首次指针输入后升级 `POINTER`）。建议删掉注释里的 `MIXED` 表述，避免误读。
3. **`PcWindowBar.close()` 仍是 `destroyWindow()`**：[PcWindowBar.ets:77–89](../../entry/src/main/ets/shell/PcWindowBar.ets#L77-L89)。
   它是兼容薄壳（不再渲染），行为契约被 `tools/window-regression.cjs` 锁定；真正在用的关闭路径是
   [DesktopTitleBar.close()](../../entry/src/main/ets/shell/DesktopTitleBar.ets#L236)（先 `flushAll` 再 `terminateSelf`）。
   不建议为了统一而改薄壳，否则旧回归与历史调用方都会受影响。
4. **历史 `console.*` 存量**：`CanvasTextEditor.diag` 1 处、`ImeBridge` 2 处，已被 guard 设为 warning。
   本次新增文件均使用 `Logger`。
5. **`EditorPane` 工具条条件较宽**：[EditorPane.ets:44](../../entry/src/main/ets/shell/EditorPane.ets#L44)
   使用 `isWide || isDesktopMode || pointerPrimary`，即宽屏触摸平板也会显示格式工具条。符合契约
   "电脑/平板（键鼠）显示工具条"的意图，但平板 LG 纯触摸场景请在自测 V/M 组确认不拥挤。

## 复现

```bash
# 本机（无 SDK 也能跑）
for f in tools/*.cjs; do node "$f" || echo "FAILED $f"; done
# 期望：7 个脚本全部通过，合计 224 项

# 设备侧（DevEco / 命令行工具链）
./tools/Test-FlowText.ps1 -DevEcoRoot '<DevEcoRoot>' -JavaRoot '<JDK>' -BuildOnly
./tools/Test-FlowText.ps1 -DevEcoRoot '<DevEcoRoot>' -JavaRoot '<JDK>' -Device '<hdc 设备号>'
```

## 附：Lead 集成修订（回归 208 项通过后的收尾）

T1–T3 交付后，Lead 做了以下集成/纠正（均已包含在 208 项回归与静态守卫的最终结果中）：

| 文件 | 位置 | 修订内容 |
|---|---|---|
| `utils/DeviceProfile.ets` | :79、:112-125 | `pointerPrimary` 只认 `POINTER`；平板（含 MatePad Edge 电脑模式）基线为 `TOUCH`，仅实测到指针输入后升级，避免纯触摸平板被误开 hover-only/指针光标 |
| `editor/flowtext/CanvasTextEditor.ets` | :758-836 | 鼠标事件 / 滚轮触发 `notePointerActivity()`；`:1058` 光标改用官方 `cursorController.setCursor(pointer.PointerStyle.TEXT_CURSOR)`（原 `.pointerStyle()` 取不到枚举值） |
| 同上 | :876、:1021 | 软键盘判据由 `deviceInfo.deviceType !== '2in1'` 改为 `!this.desktopMode`（平板电脑模式不是 2in1） |
| `editor/interaction/ShortcutMap.ets` | :24-33、:50 | 键码按官方 API 26 修正：GRAVE=2056、MINUS=2057、SLASH=2064、AT=2065、PLUS=2066；标点范围改为 2056..2066；常量加 `SC_` 前缀 |
| `shell/AppShell.ets` | :213-238、:408-450 | 三形态交互分流：平板触摸 52vp 顶栏/48vp 命中区/无 hover，电脑 44vp + hover + 撤销重做；侧栏与 navBar 宽度按电脑/平板/其他分档 |
| 同上 | :294 | 根容器 `onHover` 触发一次输入形态升级 |
| `shell/DocListPane.ets` 三处调用点 | AppShell:367 / MobileShell:186 / WorkspaceDest:124 | 传入 `themeId: app.ui.themeId`，深色主题下列表头/选中态不再回落默认亮色玻璃 |
| `pages/GuideSwiperPage.ets` | :104-119 | 首启页标题栏判据由 `deviceType === '2in1'` 改为 `freeWindowMode / isPcDevice`（AppStorage），与主界面统一 |
| `docs/refactor/multidevice-interaction-refactor.md` | §1、§2 | 契约同步为实现语义（`pointerPrimary === POINTER`、cursorController + `TEXT_CURSOR`） |

## 附二：首次真实编译（API 26 / 2in1）报错与修复

2026-10-18 设备侧 `hvigorw assembleHap`（`requiredDeviceType=2in1`）首轮 `CompileArkTS`
报 7 个 ERROR / 39 个 WARN。逐条修复如下（修复后本地 208 项回归与静态守卫全部通过）：

| 报错 | 文件 | 根因 | 修复 |
|---|---|---|---|
| 10505001 ×3 | AppShell:367 / MobileShell:186 / WorkspaceDest:124 | `themeId` 实际是内部 `DocRow` 的 `@Param`，不是 `DocListPane` 的参数 | 删除三处调用点的 `themeId:` 实参（`DocListPane` 内部已用 `app.ui.themeId` 传给 `DocRow`） |
| 10905204 ×3 | `MaterialSurface.ets` 194/204/214 | 全局 `@Builder` 里直接调用函数型参数 `content()` 不符合 UI 组件语法（`@BuilderParam` 只能用于组件） | 删除未被使用的 `GlassBar/GlassCard/GlassPanel` 三个包装 builder，只保留 `GlowPageBackground` 与 `AttributeModifier`/`systemMaterialFor` |
| WARN 21 | `utils/SafeArea.ets` | 全局 `px2vp` 已废弃 | 改为按定义换算 `vp = px / display.getDefaultDisplaySync().densityPixels`（缓存密度，失败退 1:1） |
| WARN 22/23 | `utils/SystemBars.ets` | `setWindowSystemBarProperties` 在 2in1 不可用 | 2in1 平台跳过系统栏属性设置（保留窗口底色设置）；平台判断集中到 `DeviceProfile.isPcPlatform()` |
| WARN 35 | `editor/flowtext/CanvasTextEditor.ets:602` | 读取系统剪贴板需 `ohos.permission.READ_PASTEBOARD` | **最终未声明该权限**：实测声明后安装失败（`9568289 grant request permissions failed`，该权限需 ACL/受限签名，个人调试证书不具备）。改为不声明权限 + 应用内剪贴板兜底（copy/cut 写 `appClipboard`，paste 系统剪贴板失败时回落）；跨应用粘贴需 ACL 或安全控件 `PasteButton`，属已知限制 |
| WARN 39 | `pages/GuideSwiperPage.ets` | 全局 `router.replaceUrl` 已废弃 | 改为 `this.getUIContext().getRouter().replaceUrl(...)` |

> 修复后仍需在设备侧重新执行 `assembleHap` 确认 `COMPILE RESULT:SUCCESS`；本机无 SDK，不能代替真编译。

## 附三：第二轮 UI / 输入修复（2026-10-18）

| 文件 | 关键改动 |
|---|---|
| `shell/DesktopTitleBar.ets` | 重写为统一窗口头：`☰ + 书名/章节 + 导出/导入/设置 + 窗口三键`；删除与 appBar/工作区重复的标题；按钮统一 44–48vp 命中区、hover、焦点与无障碍；保留窗口拖拽/最大化/关闭/监听契约（`barTitle` 等名称保留以兼容回归） |
| `shell/AppShell.ets` | 电脑模式不再叠第二条 appBar（平板宽屏才保留触摸版）；标题栏注入导出/导入；侧栏默认 260vp（可拉 240–400）；移除重复的撤销/重做入口 |
| `shell/ProjectSidebar.ets` | 信息架构重构：删除「Weaver / 新建文稿 / 当前项目名」冗余，改为「项目 + 新建」「项目列表」「文库筛选」；内容可滚动；统一 40–44vp 行高、hover/选中两态、1px 右边框 |
| `shell/DocListPane.ets` | 列表头改为「书名 + 筛选·篇数 + 搜索 + 新建」；行 hover 高亮；列右边框；空列表文案改指「右上角 +」 |
| `shell/WorkspaceDest.ets` | 宽屏不再渲染同名 topBar（标题只在窗口头出现一次） |
| `shell/EditorPane.ets` | 合并原 toolBar+quickBar 为一条统一工具条；撤销/重做/加粗/斜体/H1/查找/排版/格式/收藏/灵感统一按钮样式与禁用态；新增两态「打字机」按钮；`toggleTypewriterMode()` 同时写 store 与编辑器控制器；空状态版式统一 |
| `editor/interaction/ShortcutMap.ets` | 数字键按 keyCode 兜底（0-9 / 小键盘 / Shift 符号），不再依赖 `keyText` |
| `editor/interaction/InputArbiter.ets` | 修正：数字**不再**在 preIme 强制上屏（那会抢走输入法组字态的候选选词）；字符类按键统一遵循 ①preIme→②输入法→③onKeyEvent，数字兜底只发生在 ③（输入法没用掉该键时） |
| `editor/flowtext/ime/KeyboardHandler.ets` | 旧翻译器补同样的数字兜底（保持测试口径一致） |
| `editor/flowtext/CanvasTextEditor.ets` | 打字机：`@Prop @Watch` + `typewriterOverride` + `applyTypewriter()` 即时重排/居中；控制器新增 `setTypewriter()`（含绑定前暂存） |
| `store/UiStore.ets` | 新增 `setTypewriter(on)`，`toggleTypewriter()` 走同一入口 |
| `tools/flowtext-regression.cjs` | 新增 3 项：数字键全键位/小键盘/Shift 符号、组字态数字必须交给输入法选词、③onKeyEvent 数字上屏；打字机从工具条到 V1 编辑器的接线校验（81 → 84） |

### 补充：响应式细节

- `DesktopTitleBar`：窗口宽度非 LG 时把「导出/导入/设置」收进「⋯」菜单，标题最大宽从 340 降到 200，避免小窗口挤压。
- `EditorPane`：工具条按自身可用宽度（`onAreaChange`）切换两态——`<700vp` 只保留「撤销/重做/打字机/⋯」，`≥700vp` 展开格式与排版动作；高度用 `constraintSize({minHeight})` 不写死，避免压缩裁切。
- `ProjectSidebar`/`DocListPane`：行高统一 40–44vp，栏间 1px 分隔线，hover/选中两态；侧栏内容改为可滚动。

## 附四：打字机按段落居中 + 非当前段落淡化（2026-10-18）

| 文件 | 关键改动 |
|---|---|
| `editor/flowtext/CanvasTextEditor.ets` | ① 段落识别 `paragraphStartAt/paragraphEndAt` + `refreshTypewriterFocus()`（dirty 缓存，热路径不重复扫描）；② `typewriterScrollTarget()`：段落高度 ≤ 视口 80% 时整段居中，超长段落退化为光标行居中；③ `leadPadVp()` 允许负 `scrollY`（首段也能居中），`clampScroll`/目标夹取同步支持；④ `followTypewriter()` 在点击/键盘移动/窗口缩放/改字号/切主题后重新居中；⑤ `drawNow` 把当前段落行区间与淡化开关传给渲染器；⑥ 新增 `dimTextColor` prop，仅显示层使用 |
| `editor/flowtext/render/GlyphRenderer.ets` | `draw()` 增加可选 `dimEnabled/focusLineStart/focusLineEnd`；当前段落之外的行用 `dimTextColor` 画（缓存的整 run TextBlob 与慢路径、字形动画都按行取色）；顺手修正缓存路径画刷颜色未初始化的隐患 |
| `editor/flowtext/theme/EditorTheme.ets`、`render/GlyphRenderer.ets` | 新增 `dimTextColor` 主题字段；`RenderTheme` 增加 `dimTextColor` 画刷色 |
| `constants/DesignTokens.ets` | 新增 `blendHexColor(fg,bg,ratio)`：按主题正文色×纸色推导淡化色，深浅主题通用，不硬编码 |
| `shell/EditorPane.ets`、`editor/TextEditorHost.ets` | 计算并透传 `dimTextColor`（正文色向纸色混合 50%，对比度仍可读） |
| `tools/flowtext-regression.cjs` | 新增 4 项：段落边界（首/空/中/末）、段落/首末段/超长段居中目标、负滚动与关闭复位、渲染器按段落淡化（84 → 88） |

> 打字机现在只影响**显示与滚动**：不写文档、不动光标/选区、不影响撤销重做与 IME 组合输入。

## 附五：光标动画 / 呼吸光标 / 顶栏工具 / 沉浸编辑（2026-10-18）

| 文件 | 关键改动 |
|---|---|
| `editor/flowtext/CanvasTextEditor.ets` | ① 指针点击（鼠标/触控板）走 `placeCaretImmediately()`，不启动弹簧动画；手指点按仍走 `moveCaretAnimated()`。② 呼吸光标：`startBlink()` 由"600ms 硬闪烁 visible"改为余弦 alpha 呼吸（0.5→1，2.4s 周期、60ms 步进），光标移动动画期间保持实心。③ F11 → `TOGGLE_IMMERSIVE` 命令（`hostToggleImmersive` 转发宿主）。 |
| `editor/flowtext/interaction/CursorState.ets` | 新增 `alpha`（0–1），`clone()` 一并复制。 |
| `editor/flowtext/render/GlyphRenderer.ets` | `drawCaret()` 按 `caret.alpha` 着色；接近 0 才跳过（不做全灭硬闪）。 |
| `editor/flowtext/theme/EditorTheme.ets` | 新增 `caretBreathPeriodMs`、`caretBreathStepMs`。 |
| `editor/interaction/{EditCommand,ShortcutMap,InputArbiter,EditorCommandRouter}.ets` | 新增 `TOGGLE_IMMERSIVE`（F11）：preIme 消费、路由转发宿主。 |
| `shell/EditorTools.ets`（新） | 顶栏工具组：撤销/重做、B/I/H、查找、打字机两态、专注写作；compact 折叠格式组；28vp 胶囊 + hover + 无障碍。桌面窗口头与平板顶栏共用。 |
| `shell/DesktopTitleBar.ets` | 顶栏承载工具组 + 副标题「章节 · 字数 · 保存状态」；沉浸模式只留标题/统计/退出专注/三键；按顶栏实测宽度折叠工具与低频动作。 |
| `shell/AppShell.ets` | 新增 `immersiveBody()`：正文在窗口内居中铺开（maxWidth 880），隐藏侧栏/列表/工具条；平板顶栏接入 `EditorTools` 与字数。 |
| `shell/EditorPane.ets` | 移除编辑器内部工具条（工具上移顶栏）；监听 `app.ui.findRequestTick` 打开查找；注入 `app.ui.editorController`；手机/平板提供浮动「退出专注」；手机才显示浮动字数。 |
| `shell/WorkspaceDest.ets` | 「更多」弹层新增「专注写作」入口（手机/平板可进入沉浸）。 |
| `store/UiStore.ets` | 新增 `immersiveEditing`、`findRequestTick`、`editorController` 与切换/退出/查找请求方法。 |
| `tools/flowtext-regression.cjs` | 新增 3 项：F11 命令链、指针点击不启动弹簧动画、呼吸 alpha 渲染（88 → 91）。 |

## 附六：打字机段落视觉层级（缩放）与平滑切换（2026-10-18）

**默认参数**（`TypewriterScaleOptions`，位于 `editor/flowtext/theme/TypewriterScale.ets`）

| 参数 | 默认值 | 含义 |
|---|---|---|
| `focusScale` | **1.08** | 当前段落缩放（约束建议 1.05–1.12） |
| `adjacentScale` | **0.98** | 紧邻当前段落的行缩放 |
| `scaleStep` | **0.02** | 每远离一行再缩小 0.02 |
| `minScale` | **0.90** | 缩放下限（不低于 0.88–0.92） |
| `typewriterScaleDurationMs` | **180ms** | 段落切换过渡时长（`ease-out`） |
| `typewriterScaleAnimated` | **true** | 关闭后直接切换（可作为减少动态效果降级） |

| 文件 | 关键改动 |
|---|---|
| `editor/flowtext/theme/TypewriterScale.ets`（新） | 纯函数：`typewriterLineDistance` / `typewriterScaleForDistance`（focus→adjacent→step→min，支持浮点边界连续过渡）/ `typewriterDimWeight`（0–1 行内平滑淡化） |
| `editor/flowtext/render/GlyphRenderer.ets` | 每行按行距计算缩放与淡化权重；文字以**文本列左边缘 + 基线**为轴心用 `canvas.scale` 绘制（所有行左对齐，当前段放大后右边界正好回到原列宽；纯绘制层，不触发重排）；光标、选区同步按同一轴心/基线变换，避免放大段里错位；淡化改为权重插值，切换时颜色平滑过渡 |
| `editor/flowtext/CanvasTextEditor.ets` | ① 打字机开启时文本列按 `1/focusScale` 收窄，并让缩放轴心使用**收窄前的基准列宽**（放大后左右正好占回预留空间，不向左侧溢出）；行高/段距不变；② 滚动以**光标行**为居中单位（同一段内换行也逐行跟随），段落只决定缩放/淡化层级；③ `twAnimFirst/twAnimLast` 浮点焦点边界 + `EditorAnimator` 同一条动画驱动"淡化 + 缩放"；③ 快速切段先取当前插值值再重定向（不堆积动画），重排/切稿直接吸附；④ `drawNow` 同时下发缩放与淡化边界；⑤ 关闭打字机停止动画并重建普通宽度 |
| `editor/flowtext/theme/EditorTheme.ets` | 新增 `typewriterScale`、`typewriterScaleDurationMs`、`typewriterScaleAnimated` |
| `tools/flowtext-regression.cjs` | 新增 3 项：默认参数与逐行衰减/下限、渲染层逐行 `scale`（含上下限）、段落切换重定向不堆叠（91 → 94） |

> 缩放只影响绘制与滚动：不改文本、光标偏移量、选区模型、撤销重做与 IME。切换段落时旧段恢复、新段放大、上下行缩放与淡化由同一条 180ms 缓动同步过渡。

## 附七：打字机越界 / 光标滞后 / 光标水平错位修复（2026-10-18）

| 问题 | 根因 | 修复 |
|---|---|---|
| 高亮行文字越界 | 缩放轴心曾取收窄列的**中心**，放大后左侧溢出；且字形动画/斜体过冲没有兜底裁剪 | ① 轴心改为**文本列左边缘**，所有行左对齐，当前段放大后右边界回到原列宽；② 布局宽度额外预留 **8vp** 安全边；③ 文字绘制增加 `clipRect` 硬裁剪（编辑区可视矩形），异常超长 run 或字形动画也不会越界（不支持裁剪的实现自动跳过） |
| 快速输入时光标滞后 | 每次按键都在 `ensureCaretVisible(CENTER)` 启动 160ms 滚动动画，快速输入不断打断上一段动画，视口追不上文字 | ① 编辑事务（afterEdit）在打字机模式下使用**即时滚动**；② CENTER 模式下目标只差 ≤1.5 行时直接对齐、不播动画；大跳转（点击跨段）仍保留平滑动画；③ 光标在 `afterEdit` 内先于绘制更新 |
| 光标水平偶发错位 | 渲染器用 `caret.y` 猜光标行时使用了 `line.height + line.step` 区间，与下一行**重叠**；且此前 `caretScalePending` 未被 draw 赋值（恒为 1），缩放段里文字放大而光标不放大 | ① 由编辑器按 `caretOffset` 用 `HitTester.lineIndexOf` 算出**精确光标行号**传给渲染器；y 区间兜底改为不含 `line.step`；② `draw()` 中显式计算光标行的缩放与基线，光标/选区与文字共用同一轴心与缩放；③ 光标 x 仍来自原生行 `getOffsetForStringIndex` 的实测边界 |

| 文件 | 改动 |
|---|---|
| `editor/flowtext/render/GlyphRenderer.ets` | `draw()` 新增 `caretLineIndex`；光标行缩放预计算；文字 `clipRect` 裁剪；新增 `paddingRightVp/viewWidthVp/viewHeightVp` 主题字段 |
| `editor/flowtext/CanvasTextEditor.ets` | 布局预留 8vp 安全边；`drawNow` 传精确光标行号；`afterEdit` 打字机即时滚动；CENTER 近一行直接对齐 |
| `tools/flowtext-regression.cjs` | 新增 1 项：光标必须使用精确行号的缩放（错误行号会产生横向偏移）（94 → 95） |

## 附八：顶栏窗口三键改为华为原生（2026-10-18）

| 文件 | 改动 |
|---|---|
| `utils/DesktopWindowChrome.ets` | `setWindowTitleButtonVisible(false,false,false)` 改为 `(true,true,true)`：按官方“窗口沉浸式”做法只隐藏标题栏装饰，**保留系统原生最小化/最大化(还原)/关闭三键**（华为原生样式，hover/贴边/最大化还原/无障碍均由系统负责） |
| `shell/DesktopTitleBar.ets` | 删除自绘 `─/□/✕` 字符按钮与分隔线；保留 `getTitleButtonRect` 右避让（`padding-right = titleButtonWidth`），自绘动作区不遮挡三键；`close/minimize/toggleMaximize` 方法保留（供窗口回归与兼容壳使用） |
| `tools/window-regression.cjs` | 断言由 `(false,false,false)` 更新为 `(true,true,true)`，用例名改为“隐藏标题栏但保留原生三键” |

> 数据安全：关闭改由系统原生按钮触发，仍由 `EntryAbility.onBackground` / `onDestroy` 的 `app.flushAll()` 落库，
> 与自绘关闭路径等价（30 秒安全网 + 退后台落库）。

## 附九：打字机高亮段越界加固（2026-10-18）

| 加固层 | 做法 |
|---|---|
| ① 布局预留加大 | 打字机列宽 = `(可用宽度 - 16) / focusScale`，放大后左右各留 8vp，不再贴边 |
| ② 实测行宽硬夹取 | 渲染器按每行 `实测宽度` 计算 `fit = 可用宽度 / line.width`，实际缩放取 `min(层级缩放, fit)`。正常排版 `fit ≥ 1.08` 不影响效果；设备取整/超长不可断 run/旧缓存导致行宽异常时自动收敛，**从数学上不可能越界** |
| ③ 布局状态兜底同步 | `drawNow` 前校验“排版引擎构建时的打字机状态”与当前 prop 是否一致；不一致则重建排版（保留阅读位置），修复“文字已缩放、排版仍按全宽换行”的错配 |
| ④ 绘制硬裁剪 | 文本绘制统一 `clipRect` 到编辑区可视矩形（不支持裁剪的环境自动跳过），兜住斜体/字形动画过冲 |
| ⑤ 光标/选区一致 | 光标、选区使用与文字相同的 `fittedScale` 轴心与比例，不会出现文字收敛而光标仍按 1.08 偏移 |

| 文件 | 改动 |
|---|---|
| `editor/flowtext/render/GlyphRenderer.ets` | 新增 `fittedScale()`；文本/选区/光标统一改用实测行宽夹取 |
| `editor/flowtext/CanvasTextEditor.ets` | 安全边 8→16vp；`engineTypewriter` 记录 + `drawNow` 绘制前同步重建 |
| `tools/flowtext-regression.cjs` | 新增 1 项：宽行按 176/170 收敛、窄行保留 1.08（95 → 96） |

## 附十：高亮段文字轴心与光标/选区不一致（越界根因，2026-10-18）

现象：高亮段左侧被裁（首字缺失）、右侧贴边；上方淡化段落整体向右缩进；光标与文字错位。

根因：上一轮把**光标/选区**缩放轴心改成了文本列左边缘，但 `drawText` 里文字仍按
`paddingLeft + textColumnWidth/2`（收窄列的中心）缩放。列已按 `1/focusScale` 收窄，导致：

- 当前段（1.08×）围绕收窄列中心放大 → 左边缘被推到 `paddingLeft` 左侧约 `4% * content`，被裁剪；
- 非当前段（0.90–0.98×）围绕同一中心缩小 → 左边缘右移，看起来整段缩进；
- 光标/选区按左边缘轴心变换 → 与文字横向错位。

修复：`drawText` 的 `pivotX` 改为 `textPivotPx()`（文本列左边缘），与光标、选区共用同一轴心；
删除 `columnWidth` 局部变量。这样所有行左边界对齐，当前段放大后右边界回到原列宽，不裁剪、不缩进。

| 文件 | 改动 |
|---|---|
| `editor/flowtext/render/GlyphRenderer.ets` | `drawText` 每行缩放轴心由列中心改为 `textPivotPx()`；与 selection/caret 统一 |
| `tools/flowtext-regression.cjs` | 新增 1 项：缩放段文字左边界必须保持 `paddingLeft`，光标必须使用同一轴心（96 → 97） |
