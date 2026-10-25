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
| `tools/arkts-guard.cjs` | 19 | `ArkTS guard: 19 checks passed (38 files scanned, 2 warning(s))` |
| `tools/device-profile-regression.cjs` | 27 | `Device profile regression: 27 checks passed` |
| `tools/flowtext-regression.cjs` | 127 | `FlowText regression: 127 checks passed` |
| `tools/window-regression.cjs` | 32 | `Window regression: 32 checks passed` |
| `tools/data-regression.cjs` | 28 | `Data regression: 28 checks passed` |
| `tools/shell-regression.cjs` | 57 | `Shell regression: 57 checks passed` |
| `tools/import-regression.cjs` | 5 | `Import regression: 5 checks passed` |
| **合计** | **295** | 重构前 130 项全部保留并通过，新增 165 项 |

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
| `tools/arkts-guard.cjs` | 新增 | 19 项静态红线（any/unknown、解构、对象展开、Object.assign、@Builder 链式、API≤26 基线、禁 `moveWindowTo`、startMoving 门控、8 位 statusBarContentColor、deviceType 不参与断点、模块级同名 const 仅同文件判重、相对 import 的文件与导出符号存在性、console.* 限定存量、module.json5 元数据、材质降级、属性链越界（build 提前闭合）、规则自检） |
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
# 期望：7 个脚本全部通过，合计 260 项

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

## 附十一：按《问题清单与鸿蒙UI修改建议（第二版）》修订（2026-10-18）

### 诊断核对

| 条目 | 结论 | 处理 |
|---|---|---|
| C01 关闭窗口保存失败仍退出 | **正确**：`close()` 用的是容错 `flushAll()`（单篇失败被吞），失败也 `terminateSelf` | 已改用 `flushAllStrict()`；失败**不关窗**，弹「重试保存 / 导出草稿 / 放弃并退出」；导出草稿走 `ExportService.saveText` |
| C02 撤销可用状态全局化 | **正确**：`canUndo/canRedo` 只看共享栈长度，`stepHistory` 却按 docId 取 | 已改为按 `activeDoc.id` 判断；新增回归 |
| C03 复制失败仍提示成功 | **正确**：`setData().catch(()=>{})` 后无条件 toast | 已 `await` 并区分成功/失败提示；选区菜单「分享」改为「复制到系统」 |
| C04 功能承诺与入口 | **正确（属路线图/文档治理）** | 本轮不改数据层；建议维护「已开放功能清单」，不把 Store 存在当用户可用 |
| U01 项目列表下沉留白 | **当前代码已无该结构**（标题后直接 Scroll，项目列表紧随；截图疑为旧构建） | 保留现有顶部对齐；真机复验 |
| U02 导航占宽 | **观察成立，但属产品级 IA 调整**（默认双栏、项目切换进目录），与现有三栏管理布局冲突 | 暂不重构；建议单独立项后实施 |
| U03 缺少标题/开写提示 | **正确**：标题只在窗口副标题/列表；`placeholder` prop 未绘制 | 编辑区上方新增轻量标题（点击就地重命名）+ 空文稿「开始写作…」占位 |
| U04 选中态/材质过重 | **正确**：项目/筛选/文稿行使用 sheen 渐变 | 改为 `activeBg` 平整浅选中，去掉列表渐变/投影 |
| U05 顶栏拥挤/单字标签 | **正确**：撤/重/查/专 单字、Logo 缺失、导出/导入/设置常驻 | 品牌 `Logo + Weaver` 置于最左；撤销/重做/查找/专注改全文案；导出/导入/设置收进「⋯」；保留键盘与读屏标签 |
| U06 工具热区偏小 | **正确**：28×26 | 触摸设备 48vp、键鼠 32vp；打字机胶囊外层 48vp 热区 |
| U07 格式/模式状态 | **正确**：B/I/H 恒 inactive，禁用只变颜色 | 新增 `inlineStyleMask`（1 粗/2 斜/4 标题）+ 选区 tick；按钮真实 `.enabled()`、选中态底色；格式命令后回焦正文 |
| U08 删除反馈 | **部分正确**：菜单已移废纸篓，但侧滑仍是永久删除且无撤销 | 侧滑改为「移入废纸篓」；移入后弹「撤销 / 知道了」；彻底删除仅废纸篓内 |

### 变更文件

- `store/AppStores.ets`：新增 `flushAllStrict()`
- `store/EditorStore.ets`：`canUndo/canRedo` 按 activeId
- `shell/DesktopTitleBar.ets`：严格关闭 + 阻断对话框 + 草稿导出；品牌区；低频动作收进 `⋯`
- `shell/EditorPane.ets`：文稿标题就地重命名、空文稿占位、复制等待结果、选区/格式 tick
- `shell/EditorTools.ets`：全文案、48vp 热区、真实 enabled/active、格式状态
- `shell/DocListPane.ets`：平整选中态、侧滑移废纸篓 + 撤销
- `shell/ProjectSidebar.ets`：平整选中态
- `editor/flowtext/CanvasTextEditor.ets`：`inlineStyleMask`、格式命令后回焦、菜单「复制到系统」
- `tools/*.cjs`：close/undo 回归更新

### 未完成/待确认

- **U02 默认双栏/项目切换进目录**：需要改导航信息架构与项目切换入口，建议单独确认后实施。
- **C04 功能清单**：属产品/文档治理，需要维护入口与「数据能力 vs 用户可用」矩阵。
- 本轮仍未编译/未跑设备；新增 `promptAction.showDialog`、`TextInput.onSubmit`、`ExportService` 路径需在设备构建中确认。

## 附十二：标题栏重设计、Symbol 图标与动画统一（2026-10-21）

### 现状分析

- **标题栏**：`DesktopTitleBar` 是 48vp 单行结构（品牌 + ☰ + 标题/副标题 + 工具 + 文本动作），能工作但品牌区弱、分隔与层级偏平，右侧动作全文本。
- **侧栏空白/异常出现**：`ProjectSidebar` 的 `Scroll` 未显式对齐；内容不足一屏时会被居中。新建项目后内容块高度变化，整块重新居中 → 看起来从底部滑出/跳动。
- **动画**：全仓仅 `InputDialog`、`WorkspaceDest`、编辑器 `EditorAnimator` 有显式动画；前两者各自硬编码 180ms；列表/选中态无统一令牌。侧栏行如果直接加 `.animation` 会牵连尺寸/位置，反而放大跳动。

### 修改

| 区域 | 调整 |
|---|---|
| 标题栏 | 品牌簇（22vp Logo + 14vp 半粗 Weaver）→ 细分隔 → Symbol 目录开关 → 标题/副标题 → 拖拽区 → 工具 → `more`；背景改为 `bgSurface` + 1px 下分隔，去掉整条玻璃模糊；图标按钮 36/44vp 热区、hover、focus、tabStop、120ms 颜色过渡 |
| 图标 | 全部使用 HarmonyOS Symbol：`open_sidebar`/`close_sidebar`、`undo`、`redo`、`bold`、`italic`、`h1_square`、`magnifyingglass`、`fullscreen`、`exit_full_screen`、`more`、`textformat`、`plus`、`folder`、`bookshelf`、`doc_text`、`star`、`lightbulb`、`trash` |
| 侧栏 | 项目行 `folder`、文库入口 `doc_text/star/lightbulb/trash`；新建按钮 `plus`；`Scroll` 增加 `.align(Alignment.TopStart)` + 内层 `constraintSize({minHeight:'100%'})` + `FlexAlign.Start`，内容永远从顶部开始 |
| 列表 | 新建文稿 `plus`；列表头改平整底色 + 1px 分隔；选中态 `activeBg` + 120ms 颜色过渡 |
| 动效 | 新增 `constants/Motion.ets`：fast 120 / normal 180 / slow 240，统一 `Curve.EaseOut`；`InputDialog`、`WorkspaceDest` 改用令牌；行选中/图标状态只动画颜色与透明度，不动尺寸/位置；侧栏不做插入位移动画 |

### 验证

- 新增 3 项 shell 回归：侧栏内容顶对齐且无 `translate`、标题栏使用 Symbol 且移除 `☰` 字符、工具组 Symbol 与 Motion 令牌齐全；
- 全量 **228 项**通过（FlowText 98 / 窗口 32 / 外壳 23 / 设备 25 / 数据 28 / 守卫 17 / 导入 5）；
- 设备侧需确认：不同宽度标题栏不挤压、Symbol 均有字形、侧栏项目数量变化不位移、颜色过渡不引发重排。

## 附十三：标题栏与内容融合、侧栏按钮归位（2026-10-21）

> 替代附十二中的“可见标题栏”形态：本轮按确认的 7 条验收项，把窗口头做成**透明拖拽层**，品牌/标题/工具全部下沉到 pane header。

| 区域 | 实现 |
|---|---|
| 窗口层 | `DesktopTitleBar` 改为**不占布局高度的透明 overlay**（`position(0,0)` + `hitTest none`），只负责原生 chrome 生命周期；拖动/双击最大化分散到侧栏品牌头、列表标题区、编辑区工具行左侧空白。三栏内容从窗口顶部开始，不再有 48vp 空白带 |
| 品牌 | Logo + Weaver 移入 `ProjectSidebar` 头部；侧栏收起后品牌随侧栏隐藏（与华为备忘录一致） |
| 目录开关 | 从中栏 `DocListPane` 头部左侧提供 `close_sidebar`/`open_sidebar`（Symbol），侧栏收起/展开位置固定；不再出现在窗口条 |
| 文稿标题 | 只保留编辑区内的内联标题（20vp），点击就地重命名；窗口副标题已移除，避免重复 |
| 应用动作 | 导出/导入/设置收进中栏头部的 `more` 菜单；手机/平板 `WorkspaceDest` 顶栏的“☰ 目录 / ⋮”也改用 `open_sidebar`/`more` Symbol |
| 工具 | `EditorTools` 移入编辑区顶部，与正文同一居中列（760vp 上限）；手机/平板仍保留，紧凑模式隐藏 B/I/H |
| 列表/侧栏 | 列表标题 20vp；项目/文库行使用 Symbol；选中态平整 |
| 动效 | 侧栏列表显式顶对齐（`align(TopStart)` + `minHeight` + `FlexStart`），新增项目只追加、不整块位移；行/图标只做 120ms 颜色过渡，不做宽高/位置动画 |

### 验收对照（7 条）

1. 顶部无独立“条”：背景/间距连续，无 1px 横线 —— 透明拖拽层；
2. 品牌在侧栏头；收起后中栏同位置显示展开目录 —— 已完成；
3. 文稿标题只出现一次 —— 宽屏内联标题、窄屏 topBar 标题二选一；
4. 拖动/双击最大化/原生三键可用，按钮不拖动 —— 拖拽层 + 原生按钮避让；
5. 侧栏切换不闪烁、新建项目不整块位移 —— Scroll 顶对齐 + 无插入位移动画；
6. 120/180/240ms 令牌、无宽度动画 —— `Motion.ets` + 仅颜色/透明度过渡；
7. 手机/平板抽屉、≥48vp、键盘/读屏 —— 现有 WorkspaceDest 抽屉 + Symbol 按钮 focusable/tabStop + accessibilityText。

### 已知限制

- 拖动热区：侧栏品牌头、列表标题区、编辑区工具行左侧空白；按钮/搜索/正文不触发拖动。
- 电脑模式工具行右侧预留 148vp 给系统原生三键；内容按 safeTop 避让状态栏（PC 通常为 0）。
- 侧栏收起后品牌不可见；这是华为式融合的取舍。
- 原生关闭按钮触发系统关闭，C01 的“自定义关闭前严格落库 + 重试”不再由按钮直接调用，数据安全依赖 `onBackground/onDestroy` 落库（需在设备上复验）。

## 附十四：应用更名“语流”与标题栏附近点击修复（2026-10-21）

### 任务一：用户可见名称统一为“语流”

| 位置 | 修改 |
|---|---|
| `AppScope/resources/base/element/string.json` | `app_name` = 语流（桌面/任务栏/启动器） |
| `entry/src/main/resources/base/element/string.json` | `EntryAbility_label` = 语流；`EntryAbility_desc` = 语流小说编辑器；`module_desc` = 语流小说编辑器主模块 |
| `GuideSwiperPage.ets` | “开始使用 语流” |
| `ProjectSidebar.ets` | 品牌文字与无障碍标签 = 语流 |
| `MobileShell.ets` / `WorkspaceDest.ets` / `AppShell.ets` | 书名/导出名兜底 = 语流 |
| `DesktopTitleBar.ets` | `TITLE_FALLBACK` = 语流；未保存草稿导出名 = 语流-未保存草稿 |

保留为非 UI 标识：`DB_NAME='Weaver.db'`、备份 JSON 的 `app:'Weaver'`（旧备份兼容）、Logger TAG、类名/常量名（`WeaverColorSet` 等）。

### 任务二：标题栏附近按钮点击

**根因**

1. `DesktopTitleBar` 虽然透明，但仍以 48vp 参与布局；后续改成 overlay 后仍位于内容之上，透明层/窗口 chrome 层容易与头部按钮的命中区重叠；
2. 头部按钮在键鼠形态下热区只有 32vp，且紧邻拖拽热区，状态重渲染时命中不稳定；
3. 拖动逻辑原先绑定在整条标题栏，融合布局下没有明确“空白区才拖动”的边界。

**修复**

- 主界面**完全不再挂载** `DesktopTitleBar`（仅保留引导页兼容壳 `PcWindowBar`）；窗口 chrome 由 EntryAbility 配置，不存在透明遮罩层；
- 拖动能力拆到三处**空白热区**：侧栏品牌头、列表标题区、编辑区工具行左侧留白；按钮、搜索、正文不绑定拖动；
- 头部图标热区提升为 **40vp（键鼠）/48vp（触摸）**；工具按钮 **36/48vp**；
- 移除 overlay/zIndex 造成的命中竞争，保持原视觉不变。

### 验证

- 新增 2 项外壳回归：资源与界面名称必须为“语流”、主界面不得再挂载布局占位的标题栏且三处头部具备拖动入口；
- 全量 **230 项**通过（FlowText 98 / 窗口 32 / 外壳 25 / 设备 25 / 数据 28 / ArkTS 17 / 导入 5）。


## 附十五：宽屏侧栏收起/展开动画（2026-10-21）

### 根因

`SideBarContainer.showSideBar` 的显隐是**状态切换语义**，不是可动画属性；直接翻 `app.ui.showSidebar` 会让容器在下一帧直接换布局，所以看起来瞬间收起。且 `ProjectSidebar` 宽度跟随外层，直接给外层做宽度动画会让内部文字逐帧换行。

### 修复

- 宽屏 `wideBody` 改为自绘 `Row`：
  - 侧栏外层宽度 `showSidebar ? sideBarWidthVp() : 0`；
  - 透明度 `1 → 0`、水平位移 `0 → -12vp`；
  - 内层 `ProjectSidebar` 保持**固定宽度**，外层 `clip(true)`，避免内容逐帧重排；
  - 宽度用临界阻尼弹簧 `curves.springMotion(0.4,1.0,0)`；内层透明度/位移 180ms 标准曲线（展开延迟 40ms），分阶段退场/让位；
  - 关闭后 `.enabled(false)`，避免隐藏按钮仍可被键盘/读屏聚焦。
- 内容区（Navigation/编辑区）保持常驻、`layoutWeight(1)` 自动回流，不重建、不丢状态。

### 验证

- 新增外壳检查：宽屏不得使用 `SideBarContainer(AUTO)` 的瞬时 showSideBar，必须同时具备 width/opacity/translate 与 Motion.normal；
- 全量 **231 项**通过（FlowText 98 / 窗口 32 / 外壳 26 / 设备 25 / 数据 28 / ArkTS 17 / 导入 5）。


> 动效规范与侧栏实现已沉淀到 [`docs/design/animation-guidelines.md`](../design/animation-guidelines.md)，后续动画改动先按该页检查。

## 附十六：光标/占位对齐、中栏实时同步、专注模式与侧栏引力动画（2026-10-21）

| 问题 | 根因 | 修复 |
|---|---|---|
| 光标与占位文字错位 | 占位是 `EditorPane` 里独立的 `Text` 叠加层，与 Canvas 使用两套字号/行高/基线/内边距 | 占位移入 `GlyphRenderer.drawPlaceholder`：读取正文首行的 `baseline`、`paddingLeft`、`fontSize`，用 TextBlob 绘制；EditorPane 删除叠加 Text；IME 组字时隐藏占位 |
| 中栏不实时同步 | 列表项只在 `reloadChapters`（数据库保存后）刷新；编辑 `onEdit` 未更新 `DocItem`；撤销/重做不经过 onEdit | 新增 `ProjectStore.updateDocPreview()` 就地更新 `subTitle/wordCount/badge/modified`；`EditorPane.onEdit` 每次有效编辑调用；`@Monitor('app.editor.contentRev')` 覆盖撤销/重做；长文摘要只处理前缀，避免每键全局正则 |
| 专注模式简陋 | 仅是“去掉侧栏”的 EditorPane，只有浮动退出按钮；且入场依赖 `@Monitor`/opacity 0，重复进入时可能空白 | 拆出独立 `FocusWorkspace`：组件每次挂载在 `aboutToAppear` 自触发入场（0.94/0.99/8vp → 1），始终保留可见兜底；专注头（标签+标题+状态+退出胶囊）+ 760vp 阅读列；退出先收缩 220ms 再恢复工作台 |
| 侧栏收起太快/生硬 | 单一 180ms EaseOut 同时驱动宽度/透明度/位移 | 外层宽度临界阻尼弹簧（0.4s，无回弹），内层透明度/位移 180ms 标准曲线 + 展开 40ms 延迟，形成分阶段“引力”收放；宽度固定内层 + clip，避免文字换行抖动 |

### 验证

- 全量 **234 项**通过（FlowText 98 / 窗口 32 / 外壳 29 / 设备 25 / 数据 28 / ArkTS 17 / 导入 5）；
- 外壳新增 3 项：占位必须由 Canvas 渲染、中栏实时预览/撤销同步已接线、专注头/退出/淡入动画存在；
- 设备侧仍需验证：光标与占位基线、各种输入路径的中栏同步、专注进出动画、低端机/减少动效。

### 附十六补充：重复进入专注的 100% 异常

- 旧实现把专注面的可见性绑定到 AppShell 的 `focusEntered`；退出时置 false，再次进入若 `@Monitor` 未触发，页面就停在 opacity 0（截图中的空白页）。
- 现在专注面提取为独立 `FocusWorkspace`：
  - 每次进入都会重新挂载并在 `aboutToAppear` 自行触发入场动画；
  - 未完成态是 `opacity 0.94 / scale 0.99 / y 8vp`，**始终可见**，不会空白；
  - 退出按钮在组件内部先收缩再调用 `exitImmersiveEditing`；
  - 反复进入/退出不依赖外部状态通知的时序。

## 附十七：顶部圆形沉浸光感按钮（2026-10-21，已被附十八取代）

- 参考华为电子邮件（标准电脑应用，视觉圆约 40vp）与备忘录（平板略大）的一致性：
  pane header 内的圆形材质按钮、深色图标、浅色高光底、轻阴影、低频动作收进 more。
- 新增 `shell/ImmersiveIconButton.ets`：40vp 视觉圆、44/48vp 热区、18vp Symbol、
  普通/hover/按下/选中/禁用/焦点/深色状态；零实时模糊，守住每屏 ≤2 层预算。
- 新增 `WeaverGlassKind.ICON`、`iconGlass()`、`glassIconStyle()`、`GLASS_ICON_*` token。
- 替换 `EditorTools`、`DocListPane` 头部、`ProjectSidebar` 新建项目为统一圆钮。
- 设计规范与状态表：`docs/design/top-action-buttons.md`。

### 附十七补充：首轮编译报错与修复（10505001 / 10605008）

把 `ImmersiveIconButton` 交给 hvigor 后，`CompileArkTS` 一次抛出 87 个错误，根因只有一处结构性写法：

- **属性链写到 `build()` 的闭合花括号之后**。原文件把根节点挂在了 `build() { ... }` 的 `}` 上：

  ```ts
  build() {
    Stack() { /* 视觉层 */ }
    .width(this.visualSize)   // 属于 build 内部，合法
  }                            // ← build 在这里结束
  .width(this.hitSize)         // ← 非法：属性链落到了 struct 成员层
  .enabled(this.enabled)
  ```

  解析器把 `.width(...)` 当成 struct 成员声明，于是连带报出 `Unexpected token`、`',' expected`、
  `Duplicate identifier`、`arkts-no-standalone-this`、`arkts-no-any-unknown` 等 80 余条级联错误。
  修复：热区与视觉层拆成两层 `Stack`，**所有**修饰符都在 `build()` 内闭合，根节点就是热区，
  视觉层 `hitTestBehavior(HitTestMode.None)` 只负责绘制。

- 其余 6 条独立错误一并修掉：
  - `@Param symbol: Resource` 无默认值 → 补 `@Require`（10905327）；
  - `@Param enabled` 与 `CustomComponent` 内置 `enabled(value: boolean)` 同名冲突
    （`Type 'boolean' is not assignable to type '(value: boolean) => CommonAttribute'`）→ 改名 `isEnabled`，
    调用方 `EditorTools` 同步改；
  - `Stack` 没有 `justifyContent`/`alignItems` → 改用 `alignContent(Alignment.Center)`；
  - 状态色抽成 `overlayColor()` / `glyphColor(): ResourceColor`，避免长三元表达式与隐式返回类型。

- 复盘写进静态守卫：`arkts-guard` 新增“属性链不得落到 struct 成员层”规则（按 struct 体作用域判定，
  `@Builder` 全局函数内的顶层链式调用合法不误报），并用合成片段自检，防止同类错误再流到设备侧编译。
- 全量回归随之变为 **236 项**（ArkTS 18 / 外壳 30 / 窗口 32 / 设备 25 / 数据 28 / FlowText 98 / 导入 5）。

### 附十八：顶栏改裸图标 + 原生三键跟随主题（2026-10-21 用户确认）

设备侧实测反馈两条，均按华为电子邮件（标准电脑应用）对齐：

1. **顶部按钮不要沉浸光感材质**。原实现给每个顶栏动作套了 40vp 浅色高光圆片
   （渐变 + 1px 高光 + 轻阴影），在稿纸这种大面积暖白底上变成一排“白药丸”，
   与正文抢层级，也和 Email 的实际做法不符 —— Email 顶栏就是裸图标。
   - `shell/ImmersiveIconButton.ets` → `shell/TopActionButton.ets`：删除材质层、
     `attributeModifier`、高光与阴影、按下缩放；静态完全透明，只在 hover / 键盘焦点时
     浮出 40vp `hoverBg` 圆底，按下换 `activeBg`（120ms 标准曲线，无位移/无缩放）。
   - 图标 18 → **20vp**，相邻净间距 8 → **12vp**（Email 更疏），热区仍 44/48vp。
   - 删除材质链路：`WeaverGlassKind.ICON`、`iconGlass()`、`glassIconStyle()`、`GLASS_ICON_RADIUS`；
     尺寸 token 更名 `TOP_ICON_SIZE / HIT_POINTER / HIT_TOUCH / FONT / MARGIN`；
     `SPEC_CACHE` 6→5 槽、`MODIFIER_CACHE` 7→6 槽、`WeaverGlassKind` 回到 5 个枚举。
   - 专注模式退出胶囊同步去掉玻璃（改为仅 hover 底色的扁平胶囊），避免同一屏两种按钮语言。
2. **稿纸下右上角三个窗口按钮仍是白色**。主工作台已不再挂载 `DesktopTitleBar`，
   原生三键样式没人下发，系统就沿用“跟随系统深浅”的默认值：系统深色 + 应用浅色主题时，
   稿纸上的最小化/还原/关闭是白色，几乎看不见。
   - 新增 `utils/DesktopWindowChrome.syncDesktopDecorButtons(dark)`：读 `AppStorage.mainWindow`，
     仅桌面窗口（`isPcDevice` 或 `freeWindowMode`）下发 `setDecorButtonStyle`，
     手机/平板直接跳过，避免 801 告警刷屏。
   - `UiStore.syncSystemBars()` 末尾按**实际主题**（`themeById(themeId).dark`，不是 `darkMode`）
     调用它，覆盖启动、切换主题、跟随系统深浅、窗口状态变化四个时机；
     浅色主题 → `COLOR_MODE_LIGHT`（深色图标），夜读 → `COLOR_MODE_DARK`（白色图标）。
   - 失败分支沿用 try/catch 降级，不阻断启动。

验证：全量 **238 项** 通过（ArkTS 19 / 外壳 31 / 窗口 32 / 设备 25 / 数据 28 / FlowText 98 / 导入 5）。
外壳回归新增两条断言：顶栏组件不含任何材质关键字（`glassIconStyle|attributeModifier|backgroundBlurStyle|linearGradient|border|shadow`），
以及 `syncDesktopDecorButtons` 的桌面门控 + `UiStore` 接线；`arkts-guard` 的文件清单同步改名。

### 附十八补充：两次「成员撞名」编译错误（10505001）

新组件连着踩了同一类坑：**struct 成员名不能与 CustomComponent 自带的属性方法同名**。

1. `@Param enabled: boolean` → 与 `enabled(value: boolean): CommonAttribute` 撞名，
   报 `Type 'boolean' is not assignable to type '(value: boolean) => CommonAttribute'`。
   改名 `isEnabled`，调用方 `EditorTools` 同步改。
2. `private background(): ResourceColor` → 与 `background(content, options)` 撞名，
   报 `Type '() => ResourceColor' is not assignable to 'background(...)'`。
   改名 `overlayColor()`。

两次都不是逻辑错误，而是 ArkUI 把组件成员并进 `CustomComponent` 类型后的命名空间冲突。
已在 `arkts-guard` 增加第 17 条规则（共 19 项）：

- 维护 `ATTR_NAMES`（width/height/background/enabled/opacity/margin/onClick… 共 54 个内置属性名）；
- 只扫描**直接位于 struct 体**的成员（用花括号作用域栈判定，`interface LibEntry.id`
  这类非组件成员不会误报）；
- 用合成片段自检「interface 字段不算、struct 成员必须抓到」，避免规则空转。

### 附十九：打开文稿后顶栏图标被原生三键压住（2026-10-21）

现象：有文档时编辑区工具行最右侧的「专注」图标被最大化按钮盖掉一半，右上角看起来“按钮重叠”。

原因：工具行只按固定值 `148vp` 右避让原生三键。148 是 3×48vp 的理论值，实际三键区
（含系统内边距/hover 底）更宽，且这个数字和窗口宽度无关，窄窗口下更容易压到内容。

修复：

- `DeviceSnapshot.titleButtonWidthVp`（`getTitleButtonRect()` 实测）落到 `UiStore.titleButtonWidthVp`，
  由 `applyDeviceSnapshot()` 在窗口尺寸/状态变化时更新；
- 新增 `UiStore.captionInset`：`max(实测宽 + 24vp 呼吸, 168vp)`，未测到时按 144 + 24 兜底；
  下限 168 是因为实测值可能**只含按钮本身**，比旧写死值还窄；
- `EditorPane.headerRightInset()` 与 `FocusWorkspace.desktopRightInset()` 改用它，
  非桌面窗口仍为 12vp 常规边距；
- 由于 `titleButtonWidthVp` 是 `@Trace`，窗口宽度变化会自然触发工具行重新布局，不需要重启。
- 顺带修掉第二个诱因：`applyDesktopDecorMetrics` 之前给 `setDecorButtonStyle` 传了
  `buttonIconSize: 18`，系统会按 app 指定的尺寸重排三键，按钮被挤成一团、更像“重叠”。
  现在只下发 `colorMode`，图标尺寸与按钮间距交还系统默认（与电子邮件一致）；
  `window-regression` 相应改为断言「只设 colorMode」。

验证：外壳回归新增一条「top-right tools reserve the measured native caption area」，
断言 `captionInset` 的公式、store 接线，以及两个面板不再写死 148/150。

### 附二十：真正的原因——工具行在窄编辑列里溢出（2026-10-21 第三次）

前两次都在调「右侧避让宽度」，但截图里的关键线索是：**工具行从编辑列最左边缘就开始了**
（拖动留白被挤成 0），最后几个图标被推到窗口最右侧、压在原生三键下面。这不是避让不够，
而是**内容根本放不下**——`Row` 不会压缩定宽子项，它直接往右溢出，溢出部分穿过 padding
落进三键区；把避让从 148 加到 168 只会让溢出更多。

正确做法是把「放不下」这件事显式处理：

- `EditorPane` 用 `onAreaChange` 实测头部宽度（`headerWidth`），
  `toolSpace = headerWidth − 12 − captionInset` 传给 `EditorTools`；
- `EditorTools` 用 `rowWidth(level)` 精确算出 5 档所需宽度，`level()` 取第一个放得下的档位：
  L0 全量 450 / L1 打字机改图标 420 / L2 ⋯+查找+专注 232 / L3 ⋯+查找 188 / L4 仅撤销重做；
- L2/L3 的 ⋯ 调 `showActionMenu`，菜单包含 加粗 / 斜体 / 标题 / 打字机 / 专注写作，
  收起的动作不会丢；L2/L3 把图标 `gap` 由 4 收成 0（热区贴紧），再省 16vp；
- 删除 `compact`（原先按窗口断点拍脑袋），因为「窗口很宽 + 编辑列很窄」才是这次的真实场景；
- `Row().clip(true)` 仅作首帧兜底（测量晚到一帧时也不会画到三键上）。

验证：外壳回归新增「editor tool group collapses by measured width and keeps an overflow menu」，
断言分档函数、`space` 接线、⋯ 菜单五项齐全、`gap` 参数；全量 **240 项** 通过。

### 附二十一：右上角两个"看不清"的问题（2026-10-21）

截图里有三处异常，根因只有两个：

1. **溢出菜单图标是「应用格」不是省略号**。`sys.symbol.more` 在 HarmonyOS 符号集里
   是 2×2 方格（App 宫格），不是 "⋯"；列表头的「更多」也一直是这个图形。
   符号表里**没有**可用的省略号（只有 `ellipsis_message` 这类消息气泡图形），
   所以给 `TopActionButton` 加了 `glyphText` 参数，用文本字形 `'⋯'` 画省略号；
   回归里加了「不允许 `$r('sys.symbol.more')`」+「必须用 glyphText」的双向断言。
2. **系统绘制的 chrome 跟着系统深浅，而不是应用主题**。用户系统是深色、应用用浅色纸墨，于是：
   - 右上角三键是**白色**图标，在米白稿纸上几乎看不见；
   - `showActionMenu` 是深色面板，而我们按应用主题传了深色文字 → 「加粗/斜体/标题…」糊成一片。

   先试的 `setDecorButtonStyle({ colorMode })` 不生效：装饰栏已被 `setWindowDecorVisible(false)`
   隐藏，该接口只在「带窗口标题的主窗口」上生效，实测三键仍为白色。
   真正的开关是**应用自己的 colorMode**——系统三键、系统菜单/对话框都跟随它。

   新增 `utils/AppChromeMode.ets`：
   - `rememberAppContext(ctx)`：`EntryAbility.onCreate` 登记 `ApplicationContext`；
   - `applyAppColorMode(dark)`：调用 `ApplicationContext.setColorMode(...)`；
   - `UiStore.setTheme()` 与 `loadFromPrefs()` 在写入主题后立即调用，
     所以「浅色纸墨 → 深色三键 + 浅色菜单」「夜读 → 白三键 + 深色菜单」，
     启动首帧前就对齐，不会闪一下白三键。

   自绘 UI 不受影响（配色仍来自 DesignTokens）；`setDecorButtonStyle` 的调用保留作双保险。

验证：外壳回归新增「system chrome follows the app theme instead of the OS dark mode」，
断言 `applyAppColorMode` 的接线与省略号图标；全量 **241 项** 通过。

### 附二十二：右上角三键改为自绘（2026-10-21，已被附二十三推翻）

附二十一的 `ApplicationContext.setColorMode` 解决了系统菜单的明暗，但**没有**改变那三个按钮：
装饰栏隐藏后，系统绘制的小化/还原/关闭恒为白色，`setDecorButtonStyle` 在该状态下是空操作
（文档也写明只对"带窗口标题的主窗口"生效）。用户明确要求「就固定在该稿纸颜色下，右上角直接黑色」，
所以改成完全自绘：

- `DesktopWindowChrome.configureDesktopChrome`：`setWindowTitleButtonVisible(false,false,false)`
  （原先 true,true,true）。
- 新增 `shell/WindowControls.ets`：三个裸图标按钮（`minus` / `square` / `rectangle_on_rectangle` /
  `xmark`），热区 40vp、图标 14vp，颜色跟随主题（浅色主题即近黑），hover 用 `hoverBg`。
- 关闭沿用旧标题栏语义：`flushAllStrict()` → `terminateSelf()`，失败弹「重试保存 / 放弃并退出」，不静默丢稿。
- 挂载：`AppShell` 与 `GuideSwiperPage` 根 `Stack` 右上角；外层是全屏 `HitTestMode.Transparent` Row，
  容器不吃点击，只有三个按钮响应；内容右侧仍由 `UiStore.captionInset` 避让。
- `utils/WindowDrag.ets` 补 `minimizeWindow()` / `isWindowMaximized()`。

验证：`window-regression` 的 `setWindowTitleButtonVisible` 断言改为 `false×3`；
外壳回归新增「window controls are self-drawn and theme-coloured, native ones hidden」，
断言四个图标、落库后退出、尺寸、两个页面都挂载；全量 **242 项** 通过。

### 附二十三：撤回自绘三键 + 状态底改方形 + 补窗口状态监听（2026-10-21）

用户三点反馈，逐条落地：

1. **状态底必须是方形**。圆形高亮是平板 App 的语言，电脑应用（Email / 备忘录桌面版）
   用的是圆角矩形。`TopActionButton` 的 hover/按下底由 `borderRadius(size / 2)` 改为
   `TOP_ICON_RADIUS = 8`（40vp 方形圆角）；打字机胶囊圆角也从 13 收到 8，统一方言语义。
2. **允许监听**。`EntryAbility` 新增 `windowStatusChange` 监听：最大化/还原/全屏后
   重新下发三键样式与系统栏配色；`onDestroy` 里 `off`，避免泄漏。
3. **不许自绘三键**。删除 `shell/WindowControls.ets` 与两个页面的挂载，恢复
   `setWindowTitleButtonVisible(true, true, true)`，回到原生三键框架。
   颜色改走原生机制：
   - `applyAppColorMode()` 让应用 colorMode 跟随主题（浅色主题 → 系统画深色图标）；
   - 新增 `refreshDecorColorScheme()`：窗口创建时已固定 colorMode，之后改不会自动重绘，
     因此启动完成、以及主题明暗切换时各切一次装饰栏显隐，让系统按新 colorMode 重建三键；
   - `windowStatusChange` 监听在窗口状态变化后重发一次，防止最大化/还原后样式丢失。

   > 说明：系统三键的图标颜色没有独立 API（`DecorButtonStyle` 只有 `colorMode`/尺寸/间距，
   > 且要求"带窗口标题"的窗口），唯一的原生开关就是窗口/应用的 colorMode。

回归：`window-regression` 恢复 `true×3`，并按"配置 3 次 + 重建三键 2 次"更新调用序列；
外壳回归用「top action state background is a desktop rounded square」与
「native caption buttons stay native and follow the app colour mode」两个检查替换自绘三键检查；
全量 **243 项**通过。

### 附二十四：平板形态单独成档（2026-10-21）

用户对比平板版语流与华为电子邮件后确认五项修正，并要求**电脑（PC + MatePad Edge 电脑模式）
与平板分开处理**。落地如下：

1. **平板尺寸档**：新增 `LightTokens.TopIconMetrics` + `topIconMetrics(pointerPrimary, tabletMode)`；
   `UiStore.tabletMode = deviceClass === TABLET && !freeWindowMode`。
   电脑：40vp 圆角方形状态底 / 44-48 热区 / 20vp 图标；平板：44vp 圆形 / 56 热区 / 24 图标。
2. **状态底形状分流**：`TopActionButton.stateRadius()` = `circular ? visualSize/2 : 8`。
   另加 `focusOnTouch(pointerPrimary)`，触摸点按不再抢焦点，灰底不会残留在按钮上。
3. **平板整体放大**：列表大标题 20→28、行标题 14→17、摘要 12→13、时间 11→12、
   行高 56→64、搜索框 36→44、列表栏 320→380、侧栏行 44/40→52/48、编辑工具行 48→56。
4. **系统栏黑边**：`applySystemBars` 的状态栏/导航条底色由"全透明"改为**主题底色**。
   透明依赖"布局真的延伸到系统栏"，平板实测没延伸就露出系统黑底，形成上下黑边。
5. **空态**：收敛到 760vp 阅读列居中；平板首页自动打开最近文稿（三栏也打开），
   不再停在右侧一大片空白。

验证：外壳回归新增「tablet chrome scales up and uses circular state backgrounds」，
覆盖 `tabletMode` 判据、四组尺寸常量、圆形分流、`focusOnTouch`、列表/侧栏/工具行放大、
380 列表宽、自动打开最近文稿、系统栏底色；全量 **244 项**通过。

### 附二十五：平板黑边与电脑三键白色的最后两个根因（2026-10-21）

1. **平板上下黑边：背景没画到系统栏区域**。
   之前把 `expandSafeArea([SYSTEM], [TOP, BOTTOM])` 加在**背景透明的容器**上——
   扩展的是那个空容器，真正绘制的 `GlowPageBackground` / `Index` 渐变仍被限制在安全区内，
   系统栏区域露出窗口/系统底色（深色主题下就是黑）。
   改为把 `expandSafeArea` 加在**实际绘制背景的层**上：`pages/Index.ets` 根 `Column`
   与 `shell/AppShell.ets` 根 `Stack`；`applySystemBars` 的主题底色继续兜底。

2. **电脑三键白色：窗口在拿到主题前就创建了**。窗口创建时即固化 colorMode，之后改不动已画好的三键。
   - `EntryAbility.onCreate` 先 `applyAppColorMode(false)`（默认主题是浅色），让窗口一开始就按浅色创建；
   - 夜读用户在 prefs 加载后 `refreshDecorColorScheme(true)` 重建一次；
   - 重建按官方约束执行 **显示装饰栏 → applyDesktopDecorMetrics → 隐藏**，
     因为 `setDecorButtonStyle` 只对"带窗口标题"的窗口生效；
   - 浅色主题启动不做这次切换，避免闪一下原生标题栏。

验证：外壳回归新增「window chrome colour is fixed before the window exists」；全量 **245 项**通过。

### 附二十六：三点菜单改锚定下拉 + 平板系统栏最后一步（2026-10-21）

1. **「⋯」不再是模态动作面板**。之前用 `showActionMenu`，出来的是带「取消」的居中面板。
   新增 `shell/MenuButton.ets`：`TopActionButton(⋯)` + `bindPopup`，锚在按钮下方展开、
   无箭头、`autoCancel` 点外部收起、点菜单项先关再执行。同一份实现两套度量
   （电脑 180/40/14/12，平板 236/52/16/16），符合"同一种菜单、不同显示外观"。
   替换位置：列表头「更多」（导出/导入/设置）、编辑器精简档「更多格式」（五项）。
   行内右键菜单仍保留系统 `showActionMenu`（长按上下文菜单语义不同）。

2. **平板顶/底栏仍有一条白（或黑）带**。上一轮把 `expandSafeArea` 挪到真正绘制的背景层了，
   但截图显示状态栏仍是系统白底——说明 `setWindowLayoutFullScreen(true)` 没生效：
   该接口依赖已加载的 UIContent，我们在 `loadContent` **之前**调用，属于静默失败。
   现在在 `loadContent` 成功回调里**再下一次** `setWindowLayoutFullScreen(true)`，
   成功后重新 `syncSystemBars()`；页面背景（Index 渐变 + AppShell 光感）已经 expand 到系统栏区域，
   两者合起来才能做到"纸色铺满、状态栏透明、前景自动深色"。

验证：外壳回归新增「the ⋯ menu is an anchored dropdown shared by desktop and tablet」；
全量 **246 项**通过。

### 附二十七：三点菜单的对齐与动效（2026-10-21）

附二十六把菜单改成了锚定下拉，但两处不对：

1. **会侵入右侧分栏**。中栏的 ⋯ 紧贴分栏边界，`Placement.Bottom` 是"以按钮为中心"展开，
   180/236vp 的菜单自然越过边界压到右栏上。改为右边缘对齐、向左展开：
   `offset.x = -(menuWidth/2 - anchorWidth/2)`（锚宽按 44/48/56 取），
   菜单右边缘与按钮右边缘齐平，整块留在本栏内。
2. **动效不是我们的语言**。默认弹出是系统的缩放/居中动画。改为显式过渡：
   `TransitionEffect.OPACITY.animation({ duration: Motion.fast, curve: Motion.standardCurve })`
   （120ms 标准曲线淡入淡出），`targetSpace: 6` 让菜单贴近按钮；
   表面交给 `bindPopup` 的 `popupColor / radius / shadow`，菜单内容不再自绘背景与阴影，
   避免透明弹层 + 自绘阴影叠出双重投影。

验证：外壳回归的菜单检查扩展了右对齐公式、`offset`、`TransitionEffect.OPACITY.animation` 与
`Motion.fast` 断言；全量 **246 项**通过。

### 附二十八：菜单底色/动效 + 横滑动作按形态分流（2026-10-21）

1. **菜单底色与面板不一致**：原来用 `bgCard`（近白），而列表/编辑面是 `bgPrimary`（米纸），
   浮起来就是一块白。改为 `popupColor = bgPrimary`，只用阴影分层。
2. **弹出动效不够顺**：120ms 太快，且和系统默认动画抢占。改为 200ms（`Motion.normal`）
   标准曲线淡入淡出，`targetSpace: 6`；菜单内容不自绘阴影，避免双影。
3. **电脑端不该出现横滑操作**：`canSwipe() = !usesDesktopChrome`，桌面走 `ListItem` 的普通分支
   （不带 `swipeAction`），动作改由**长按 / 右键**菜单触发（`DocRow` 新增右键）。
4. **触摸端横滑学备忘录**：原来是整条 96vp 红色"移入废纸篓"按钮；现在左滑露出
   **四个圆形图标动作**（收藏 / 灵感 / 重命名 / 删除），44vp（平板 48）圆形、白字、固定强调色，
   行保持圆角；`List` 挂 `Scroller`，动作执行前 `closeAllSwipeActions()` 收起。

验证：外壳回归新增「swipe actions are touch-only and follow the Notes circular layout」，
断言 `canSwipe` 判据、条件渲染两条分支、四个动作图形、圆形半径、收起调用、右键菜单；
全量 **247 项**通过。

### 附二十九：菜单回归系统组件（2026-10-21）

自绘 `bindPopup` 的菜单在动效、材质、底色上始终和电子邮件差一口气。这轮全部改回**系统菜单**：

- 「⋯」：`TopActionButton(⋯).bindMenu(this.menuView)`，`menuView` = `Menu(){ MenuItem({content}) }`，
  电脑字号 14 / 平板 16；位置、材质、动画、点击关闭交给系统。
- 行操作：`ListItem().bindContextMenu(this.rowMenu(item), this.contextTrigger())`，
  `contextTrigger()` 按 `usesDesktopChrome` 返回 `ResponseType.RightClick`（电脑）或
  `ResponseType.LongPress`（触摸）。**不设预览图** → 非模态、无蒙层，就是菜单栏本身，
  不再是 `showActionMenu` 的半模态动作面板。
- 删除：`showRowMenu()`（showActionMenu）、`MenuButton` 里的 `bindPopup / offset / transition`、
  `DocRow` 的长按手势与右键 onMouse（菜单已上移到 `ListItem`）。
- 行菜单文案与动作集中到 `rowMenuLabels(item)` + `onRowMenuAction(item, index)`。

验证：外壳回归把菜单检查改为「menus use the native menu components instead of custom popups」，
并断言行菜单走 `bindContextMenu` / `ResponseType`、禁止 `showRowMenu`/`showActionMenu`；全量 **247 项**通过。

### 附三十：⋯ 菜单点不开 + 电脑端状态底变圆（2026-10-21）

1. **点 ⋯ 不弹菜单**。`bindMenu` 原本挂在 `TopActionButton`（自定义组件）上：自定义组件外层是壳，
   点击先被组件内部的 `.onClick` 消费，壳上的 `bindMenu` 收不到点击。
   `MenuButton` 改为把状态底 + `⋯` 字形直接画在一个普通 `Stack` 上（悬停/按下/禁用/无障碍照旧），
   `bindMenu` 成为唯一的点击接收者。
2. **电脑端 ⋯ 的状态底是圆形**。`MenuButton` 只传了 `pointerPrimary` / `tabletMode`，
   漏了 `desktopMode`，`topIconMetrics` 便走了"非电脑 → 圆形"分支。
   现在 `MenuButton` 新增 `desktopMode` 参数，列表头与编辑器工具组都传
   `usesDesktopChrome`；电脑 40vp 方形（8vp 圆角）、平板仍是 44vp 圆形。

验证：外壳菜单检查补了三条断言：触发器不得包 `TopActionButton({...})`、必须
`bindMenu(this.menuView)`、必须传 `desktopMode`；全量 **247 项**通过。

### 附三十一：设置改半模态 + ⋯ 菜单右对齐（2026-10-21）

1. **设置不再从右侧推页面**。`SettingsDest` 拆成 `SettingsPanel`（纯内容）+ 旧页面外壳；
   `AppShell` 用 `bindSheet` 弹出居中半模态：`preferType: SheetType.CENTER`、`showClose: true`、
   `title: 设置`、`height: SheetSize.LARGE`，`onWillDismiss` 里复位状态。
   入口（列表头 ⋯→设置、平板顶栏「设置」）都改为打开面板。
2. **⋯ 菜单超出中栏**。`bindMenu` 默认 `Placement.BottomLeft`，菜单从左边缘向右展开，
   而 ⋯ 离分栏边界只有几十 vp，于是压到右栏。改为
   `bindMenu(this.menuView, { placement: Placement.BottomRight })`：右边缘与 ⋯ 对齐、向左展开，
   与电子邮件三点菜单的位置/长度一致。

验证：外壳回归新增「settings open as a centered half-modal sheet, not a right-side page」，
并在菜单检查里断言 `Placement.BottomRight`；全量 **248 项**通过。

### 附三十二：全应用一镜到底转场（2026-10-21）

按 `hmos-arkui-longtake-transition` skill 集成，并把三方库**源码内置**（不引网络依赖）：

1. **库**：把 `@hmanimations/ezcustomtransition`（Apache-2.0，约 1200 行）的
   `Index.ets` + `src/main/ets/**` 放到 `entry/src/main/ets/thirdparty/ezcustomtransition/`，
   保留 LICENSE；业务侧用相对路径导入，无需 `ohpm install`。
2. **AbilityStage**：新增 `entryability/MyAbilityStage.ets`，`onConfigurationUpdate` 里转发
   `ezCustomTransition.onConfigurationChanged()`；`module.json5` 增加模块级 `srcEntry`。
3. **初始化**：`EntryAbility.onWindowStageCreate` 首行 `ezCustomTransition.init(windowStage)`。
4. **Navigation**：`AppShell` 与 `MobileShell`（两处 Navigation）都挂
   `customNavContentTransition(...)`，转场期间 `enabled(false)`（`navInteractive`）。
5. **触发**：`DocListPane` 行 `ListItem` 加 `.id('doc_row_'+id)`；点击时（仅 `enableLongTake`
   且非宽屏）`generateLongTakeParam(uiContext, id, 0)`，
   经 `shell/LongTakeBridge.ets` 暂存，由 `AppShell/MobileShell.openDoc` 在真正 push 时
   `pushPath({ name: WORKSPACE, param: LongTakeNavParam })`；宽屏三栏不抓参数（避免参数泄漏）。
6. **目标页**：`WorkspaceDest` 原内容抽成 `contentBody()`，用 `LongTakeTransitionDelegate` 包裹；
   `onReady` 解析参数并 `longTakeSession.init(..., { pop: () => nav.pop() })`；
   背景改由 `navDestinationBgColor` 管理。**注意**：随仓库的是库的 1.0.0 源码，
   没有 1.2+ 的 `useSpringCurve` / `setNewSize` —— 尺寸变化由库内 `WindowUtils`
   监听 `windowSizeChange` 自行处理，调用侧保持最小 API 面。

范围说明：宽屏三栏下工作区是常驻第三栏、不产生页面推进，因此不做一镜到底（避免"整块第三栏
从一行卡片撑开"的怪动画）；手机/平板与窄窗的"列表 → 编辑页"是完整页面转场，全部启用。

验证：外壳回归新增「long-take transition is wired through Navigation on both shells」，
覆盖库导出、AbilityStage、init、两个 Navigation、delegate/session/onSizeChange、
触发门控与行 id；`window-regression` 为三方库加空实现替身；全量 **249 项**通过。

### 附三十三：设置页按电子邮件重做（2026-10-21）

原设置页是"标题 + 一串等高行"，没有分组、没有副标题、开关与单选混在一起，和电子邮件的设置差得远。

新版版式（[`shell/SettingsPanel.ets`](entry/src/main/ets/shell/SettingsPanel.ets)）：

- **分区标题 + 圆角分组卡片**：`外观` / `写作`，卡片 `bgCard` + 圆角 14（平板 18）+ `clip(true)`；
- **行结构统一**：左侧「标题 16 + 副标题 12」、右侧「勾 / Switch」；分割线左右各内缩 16；
- **主题行**：名称 + 「浅色 · 纸感底色 / 深色 · 柔和护眼」，选中显示 ✓ 并叠 `activeBg`；
- **开关行**：打字机模式 + 一句话说明 + 原生 Switch；
- **动作行**：强调色的「恢复默认设置」（对齐电子邮件「添加账户」的视觉层级）；
- 底部一行小字「语流 · 本地优先的写作工具」收尾；
- 平板形态行高 72、字号 +1；半模态背景改为 `bgSurface`，卡片才浮得出来；
- 内容只保留一份：`shell/SettingsPanel`，半模态与旧路由页 `SettingsDest` 共用，
  删掉了 `SettingsDest` 里重复的一套。

验证：外壳回归的设置检查改为断言分区标题、主题行/开关行/动作行、卡片圆角、单一内容源；
全量 **249 项**通过。

#### 附三十二补充：编译期 API 对齐（2026-10-21）

首次编译暴露了三处版本差异 —— skill 文档描述的是 1.2+ 的 API，而随仓库内置的是库 **1.0.0**：

| 报错 | 原因 | 处理 |
|---|---|---|
| `'useSpringCurve' does not exist in LongTakeTransitionOptions` | 1.0.0 没有弹簧曲线选项 | 去掉第 4 个参数，`generateLongTakeParam(uiContext, id, 0)` |
| `Object literal ... arkts-no-untyped-obj-literals` | 顺带的空对象字面量问题 | 同上（不传 options 即彻底消失） |
| `Property 'setNewSize' does not exist on LongTakeSession` | 1.0.0 由库内 `WindowUtils` 监听 `windowSizeChange` | 删掉目标页的 `onSizeChange`，尺寸由库自理 |

结论：调用侧只依赖 1.0.0 稳定 API（`init` / `customNavContentTransition` / `generateLongTakeParam` /
`LongTakeTransitionDelegate` / `navDestinationBgColor`），后续若升级库再补弹簧曲线与手动尺寸。

### 附三十四：软键盘避让（多设备合规 P0，2026-10-21）

按 `hmos-multidevice-avoid-areas` 复核发现：只有 IME 状态回调，**没有键盘高度的布局避让**，
编辑器末行/光标在键盘弹出时可能被盖住。补齐三层：

1. **避让区读取**（`utils/SafeArea.ets`）：`readSafeArea` 与 `avoidAreaChange` 监听都增加
   `window.AvoidAreaType.TYPE_KEYBOARD`，暴露 `keyboardHeightVp()`；弹出/收起/切换输入法都会更新。
2. **快照与状态**：`DeviceSnapshot.keyboardHeightVp`、`UiStore.keyboardHeight`（`@Trace`，带去重写入），
   页面与编辑器订阅同一份值。
3. **布局让位 + 光标可见**：
   - `AppShell` 根内容 `padding.bottom = Math.max(safeBottom, keyboardHeight)` ——
     键盘通常已覆盖导航条区域，取 max 避免双重留白；
   - `CanvasTextEditor.onAreaChange` 在高度变化（键盘开合、窗口缩放）后调用
     `ensureCaretVisible(effectivePolicy())`，把光标滚进可视区；
   - `AppShell.aboutToAppear` 显式 `setKeyboardAvoidMode(KeyboardAvoidMode.NONE)`：
     框架默认是 `OFFSET`（整页上移），会与我们的 padding 叠加成"抬两次"，必须关掉。

验证：外壳回归新增「soft keyboard avoidance is wired from avoid area to layout and caret」；
设备分流回归的避让区读取次数由 4 改为 6（SYSTEM + NAV + KEYBOARD 各两次）；
全量 **250 项**通过。

### 附三十五：折叠屏识别（多设备合规 P1，2026-10-21）

按 `hmos-multidevice-fold-state` 复核发现：折叠屏在 `deviceInfo.deviceType` 上通常返回 `phone`，
项目只按 deviceType 归类，导致**展开态仍是手机档**（圆形 40/48/20、手机字号、列表 320vp）。

修复：

1. **识别改用 display**（`utils/DeviceProfile.ets`）：新增 `FoldInfo` + `readFoldInfo()`，
   用 `display.isFoldable()` 判定折叠设备，用 `display.getFoldStatus()` 判定
   `FOLD_STATUS_EXPANDED / FOLD_STATUS_HALF_FOLDED`（平板级可视面积）；读取失败按非折叠降级。
2. **快照与状态**：`DeviceSnapshot.foldable / foldExpanded`、`UiStore.foldExpanded`（`@Trace`）；
   `tabletMode = (deviceClass === TABLET || foldExpanded) && !freeWindowMode`。
   折叠屏**折叠态**仍走手机档，展开/半折叠切到平板档（字号、行高、圆形底、列表宽度、工具行高）。
3. **状态监听**：`display.on('foldStatusChange')` 单独注册并在 `detach()` 里 `off` ——
   半折叠/悬停态不一定改变窗口尺寸，只靠 `windowSizeChange` 会漏掉。
4. 电脑模式优先：`freeWindowMode` 为真时 `tabletMode` 仍为 false，MatePad Edge 电脑模式不受影响。

验证：设备分流回归新增「foldable devices are classified by display state, not deviceType」
（展开→`foldExpanded=true`、折叠→false、监听注册与释放）；外壳回归补折叠档断言；
全量 **252 项**通过。

### 附三十六：方向策略（P2）+ Pura X View 特殊适配（2026-10-21）

1. **方向策略显式声明**（`hmos-multidevice-natural-orientation`）：
   `module.json5` 的 EntryAbility 增加 `"orientation": "auto_rotation"`，
   明确「跟随系统旋转」，并保持布局只按宽度断点响应、不解释 rotation 语义；
   2in1/电脑模式不受旋转影响。
2. **Pura X View（440×744，大圆角、高状态栏）**：
   - `DeviceSnapshot.shortScreen`（高度 < 800 且非电脑模式）与 `cornerRadiusVp`
     （`Display.getRoundedCorner()`，API 23，取四角最大半径）；
   - 设置半模态在短屏降为 `SheetSize.MEDIUM`，744vp 高度下不截断；
   - 其余（动态 safeTop、expandSafeArea、弹窗 90% 高度约束）此前已满足；
   - 清单与待办见 `docs/design/pura-x-view-adaptation.md`（滑动隐藏顶/底栏、增强启动页列为待确认项）。

验证：外壳回归新增「Pura X View style short screens get compact chrome metrics」；
设备分流回归的 display 替身补 `getDefaultDisplaySync/getRoundedCorner`，并断言 744vp → shortScreen、
圆角 24vp；全量 **253 项**通过。

### 附三十七：Pura X View 专项（含横屏，2026-10-21）

Pura X View 是**阔直板**（440×744、16:9.5、四边圆角更大、顶部避让更高），不是折叠屏 Pura X。

- **形态识别**：`DeviceSnapshot.wideBar`。判据用 min/max 而非 width/height：
  短边 400–520vp、长边 700–800vp、长宽比 < 1.9，且非折叠、非电脑模式 ——
  **横竖屏都命中**（旋转后宽高互换），普通直板机（≈360×800、比例 2.2）不命中。
- **紧凑 chrome（横竖屏一致）**：移动顶栏 48→40、编辑工具行 56→44、编辑页顶栏 52→48；
  左右内边距改用 `UiStore.cornerInset = clamp(圆角, 16, 28)`，避免被大圆角裁切。
- **弹层**：设置半模态在矮屏（宽直板 744/440 高）用 `SheetSize.MEDIUM`；输入弹窗已有 90% 高度约束。
- **方向**：`orientation: auto_rotation`；横屏走 MD 断点两栏，chrome 仍按 wideBar 压缩。

验证：设备分流回归新增「wide-bar devices are recognised in both portrait and landscape」
（440×744 → true、旋转为 744×440 仍 true、360×800 → false）；外壳回归补 wideBar 判据与三处紧凑尺寸；
全量 **254 项**通过。

### 附三十八：编辑器动效重做（P0：内容即时、光标连续，2026-10-21）

用户反馈四个体验点：拖手柄不流畅、IME 上屏动画怪、滚动不流畅、删除动画丑。统一结论：
**动画重心从"字符"移到"光标"** —— 内容变化同帧完成，光标用弹簧跟随。

改动（`editor/flowtext/CanvasTextEditor.ets`）：

1. **移除逐字动画**：`afterEdit` 不再调用 `GlyphAnimator.createEditAnimations` / `runGlyphAnimation`，
   清空 `anims`；字符增删、IME 上屏立即呈现，不再有入场/退场/让位插值。
2. **光标弹簧重写**：新增 `startCaretSpring(target, durationMs, keepVelocity)`：
   - 临界阻尼弹簧逐帧积分（刚度 900 / 阻尼 60，约 120ms 落定），不再用忽略 duration 的
     `interpolating-spring`；
   - 编辑重定向时**保留速度**（`caretVelX/caretVelY`），连续输入不再是"刹停再起步"；
   - 快打档位：输入间隔 < 60ms 用 80ms，否则 140ms；点击/方向键按距离 160–200ms；
   - 钳制在起终点区间内，避免光标跨越相邻行/字符。
3. **拖手柄 1:1**：鼠标与触摸进入手柄拖动前都 `stopCaretAnimation()`，拖动期间不做任何插值。
4. 光标动画期间常亮、落定后恢复呼吸；`settleCaret` 仍负责上报 IME 光标位置。

**修复跟进（连续输入追不上字符）**：首版每次按键都重建动画，弹簧进度被反复归零，且刚度 900 偏软，
长按重复输入时目标每 30–50ms 前进一格、光标只走了 30–50ms 的行程 → 视觉上"永远慢一个字"。
改为**持久弹簧循环**：`caretTarget` 字段原地更新，循环在跑时只改目标不重建动画；刚度提到 2400
（ω≈49）、阻尼 98 临界；循环结束时 `settleCaret` 定格到最新目标。参数与重定向逻辑已纳入外壳回归。

**二次修复（仍差一个字符）**：弹簧再快也有带宽上限——键重复间隔约 30ms 时，ω=49 的临界弹簧
每键只能走掉约 77% 的剩余距离，稳态滞后 ≈ 0.6–1 个字符宽，这是物理限制而不是参数没调好。
最终规则改为**按输入节奏分流**（对齐 VSCode/CodeMirror 的实际行为）：

- 快速重复输入（间隔 < 90ms）→ 光标**同帧到位**，不插值；
- 跨度 > 2.5 个字符的编辑（IME 整句上屏/换行/粘贴）→ 同帧到位；
- 方向键/翻页连按（间隔 < 80ms）→ 同帧到位；
- 只有慢速敲字与单字符删改才播 140ms 弹簧（既有动效又不滞后）。

验证：外壳回归新增「P0 motion: characters are instant, only the caret animates」
（无 `createEditAnimations`、`anims.clear`、弹簧参数、快打档位、两处手柄拖动停动画）；
全量 **255 项**通过。

### 附三十九：上屏动画恢复 + 光标防乱飞 + 专注模式一镜到底（2026-10-21）

1. **IME 整句上屏要有动画**：去掉"跨度 > 2.5 字符直接吸附"的规则，单次提交改为 220ms 弹簧；
   只有快速重复输入（<90ms）才同帧到位（那是键重复，不是一次编辑）。
2. **长按方向键/退格偶发"乱飞"**：`stop/重建` 时旧动画的残余帧仍可能写光标坐标。新增
   `caretSpringEpoch` 代际令牌：start/stop 自增，帧回调与 onFinish 先校验代际，过期直接丢弃；
   同时把方向键连按的"置位 from"移到 repeat 判断之后，避免用旧坐标起步。
3. **专注模式一镜到底**：新增 `shell/FocusTransition.ets`，`FOCUS_EDITOR_ID` 共享元素；
   `WorkspaceDest`（两处）与 `FocusWorkspace` 的编辑区都挂 `geometryTransition`，
   进入/退出统一包在 `animateTo(340ms, springMotion(0.6,0.85))` 里 —— 视觉上右栏编辑区
   向左扩大铺满窗口，退出时收回原栏；所有入口（编辑区按钮、工具条、更多菜单、窗口头退出）
   都改走动画版切换。

验证：外壳回归更新「P0 motion」并新增「focus mode uses a shared-element long-take transition」；
全量 **256 项**通过。

### 附四十：P0-1 工具条重排（2026-10-21）

按备忘录「正文▾ + 图标组」的信息架构重排编辑器工具条：

- **段落样式下拉**：`正文 / 标题 1 / 标题 2`，触发器显示当前值（`paragraphLabel()`），
  下拉用原生 `bindMenu`（`Placement.BottomLeft`）；当前段落级别由新增的
  `CanvasTextEditor.paragraphLevel()`（`doc.headingAt(caret)`）回读，随 `selectionTick` 订阅刷新。
- **H2 暴露**：模型 `HEADING_2` 已有，下拉与溢出菜单都补上；H1/H2 互切沿用 `toggleHeading` 语义
  （同级再点回正文）。
- **分组**：撤销/重做 | B I 段落▾ | 打字机 查找 专注，组间 1px 分割线；L2/L3 仍收进 ⋯
  （items 变为 加粗/斜体/标题 1/标题 2/打字机/专注写作）。
- **悬停提示**：`TopActionButton` 增加 `bindPopup` 气泡，指针悬停显示 `label` 文案（键鼠优先时）。
- **宽度档**：`rowWidth` 用 `paragraphMenuWidth()`（桌面 84 / 平板 96）替换原 H1 图标槽位，
  收纳阈值保持“宁早收一档也不压到原生三键”。

验证：外壳回归新增「toolbar exposes paragraph style as a value dropdown」；
全量 **257 项**通过。

### 附四十一：P0-2 标题区（大标题 + 元信息 + 吸顶，2026-10-21）

- **大标题**：28vp / Medium，重命名输入态同步放大到 22；标题行高 40，左右 16 内边距。
- **元信息行**（标题下 28vp）：项目 chip（8vp 品牌色圆点 + 项目名，`app.project.currentBook`；无项目时整块不渲染）
  + 字数/保存态（`docStatus()`，12vp 三级色）。
- **吸顶**：标题区与元信息作为 Canvas 之上的固定头，正文在 Canvas 内滚动时标题不动；
  小屏（`showTitle=false` 的宿主）仍不重复展示。
- 复用 `WeaverRadii`/主题色，未新增硬编码颜色。

验证：外壳回归新增「document title block shows big title, project chip and meta」；
全量 **258 项**通过。

### 附四十二：P0-3 工具条空闲淡出（2026-10-21）

- `EditorTools` 增加 `@Local idle`：3 秒无操作 → `.opacity(0.55)`；鼠标移入、输入/选区变化
  （`@Monitor('app.ui.selectionTick')`）立即恢复并重新计时；`aboutToDisappear` 清理定时器。
- 过渡用 `Motion.normal + standardCurve`，与现有工具栏动画一致。

验证：外壳回归新增「toolbar fades out when idle and wakes on activity」；全量 **259 项**通过。

### 附四十三：P0-4 专注模式精修（2026-10-21）

- 正文列 `constraintSize({ maxWidth: 720 })` 居中（头部仍 760，容纳退出入口）；
- 右下角常驻 **退出胶囊**：36vp（触摸 44）、默认 72% 不透明、hover 100%、点击退出；
- 根节点补 **Esc** 退出（`KeyEvent` Down + `KEYCODE_ESCAPE`，编辑器未消费时生效）；
- 进入/退出仍走 `geometryTransition(FOCUS_EDITOR_ID)` + `animateTo` 一镜到底。

验证：外壳回归新增「focus mode centers a 720vp column and offers an exit pill plus Esc」；全量 **260 项**通过。

### 附四十四：账号并入设置 + 头像上传 + 四点更多图标（2026-10-22）

按定案重排入口：**设置只有一个入口 —— 侧栏左下角的账号行**；账号页并入设置页顶部，
并补上**自定义头像上传**。同步把全项目的三点「⋯」换成鸿蒙四点 `dot_grid_2x2`，
「外观」分组改用调色板图标。

1. **左下角只留账号行**：`shell/ProjectSidebar.ets` 底部固定一行（头像 + 昵称；未登录是
   占位人像 + 品牌色「请登录」文字按钮），点击打开设置。原来单列的「设置」行、账号半模态
   已删除（`shell/AccountPanel.ets` 移除）。
2. **设置页顶部分组「账号」**：`shell/SettingsPanel.ets` 的 `accountSection()` ——
   48vp 头像 + 昵称 + 副标题；未登录时下方是昵称输入（≤20 字）+ 登录按钮；
   已登录时右侧「退出登录」，下方一行「更换头像 / 移除头像」。
3. **头像上传（本次修正）**：`utils/AvatarService.ets`
   - `photoAccessHelper.PhotoViewPicker` 单选图片（`PhotoViewMIMETypes.IMAGE_TYPE`）；
   - **选中后立刻复制**进 `filesDir/avatar_<ts>.<ext>`：图库返回的媒体 URI 只在本次会话可读，
     直接存 URI 会导致重启后头像空白；走 fd 复制（`openSync` + `copyFileSync`），
     失败/取消返回空串、保持原头像；后缀白名单 jpg/jpeg/png/webp/heic，其余回落 jpg；
   - 换头像或移除时删除旧文件，避免沙箱堆积；
   - 不需要新增权限：系统图库代选，不申请读媒体权限。
4. **头像展示共用组件**：`shell/UserAvatar.ets` —— 有自定义图片就 `Image('file://'+path)`
   圆形裁切，否则回落到 `person_crop_circle_fill_1` / `person_crop_circle_dashed`。
   侧栏（26/28vp）与设置页（48vp）用同一份 `UiStore.avatarPath`，不会两套状态。
   上传入口不依赖登录态：先换头像、再设昵称都行（头像与昵称都只存本机）。
   Image 使用官方 `fileUri.getUriFromPath` 转成应用沙箱 URI（绝对路径 `file://` 拼不出来）。
5. **持久化与自愈**：`UiStore.avatarPath`（`@Trace`）+ 首选项 `weaver_avatar`；
   `loadFromPrefs` 回读后校验文件仍存在，缺失则清空路径，避免显示空白头像。
6. **不用华为账号**：仍是本机身份（账号服务未接入），登录=记住昵称；头像同样只在本机。
7. **入口收敛**：删除侧栏「设置」行、中栏文稿列表「更多」里的「设置」项（只剩导出/导入）、
   窗口头「应用」菜单的「设置」项、编辑区「更多」弹层的设置二级页（`sheetPage` 一并删除）。
   手机 chrome 的「设置」保留（手机无侧栏账号行，否则无路可达）。
8. **四点 / 调色板**：`MenuButton.ets`、`EditorPane.ets`（收起态）、`WorkspaceDest.ets`
   统一 `sys.symbol.dot_grid_2x2`，全项目不再有『⋯』字形；设置页「外观」标题前加
   `sys.symbol.paintpalette`。

回归：外壳 57 项（相关 3 项：账号行唯一入口 / 四点与调色板 / 头像上传链路）。

**编译期踩坑（已修）**：`UserAvatar` 的 `@Param size` 与 CustomComponent 自带属性 `size` 冲突，
hvigor 报 `10505001 Property 'size' is not assignable to the same property in base type 'CustomComponent'`；
改名为 `avatarSize`。同时把 ArkTS 守卫的「成员不得与内置属性同名」规则从手工白名单改为扫描
`shell/*.ets` 全部组件，并加了 `@Param size` 合成片段的自我校验 —— 这条坑原本能漏过守卫。

**未验证**：本机无 SDK，未编译。真机需确认
`PhotoViewPicker` 在 2in1/手机上能拉起并返回可读 URI、复制后 `Image('file://'+path)` 能显示、
四个系统 Symbol（`dot_grid_2x2`/`paintpalette`/两个人像）可取到；关注圆形裁切边缘与
48vp 头像在高分屏下的清晰度。
