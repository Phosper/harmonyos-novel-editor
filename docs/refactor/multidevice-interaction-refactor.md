# 多端交互重构与沉浸视觉升级 —— 实施契约（2026-10-18）

> 本文件是本次重构的**唯一接口契约**。所有并行改动必须遵守本文件的类型、文件归属与
> 行为约定，避免跨人合并冲突。工程基线：HarmonyOS API 26（`targetSdkVersion = 26.0.0`），
> Stage 模型，ArkTS；设备类型 `phone / tablet / 2in1`。
>
> **写入方式警告**：本工程位于 CIFS 共享盘，`write` / `edit` 工具会因硬链接失败报
> `EPERM`。**所有文件改动必须用 `bash` 的 `cat > 文件 <<'EOF'` 或 `python3` 完成**，
> 改完用 `read` / `grep` 复核。

## 0. 官方依据（必须按此实现，不得使用非官方/废弃接口）

| 能力 | 官方接口 | 起始版本 | 说明 |
|---|---|---|---|
| 自由窗口（电脑模式）判定 | `window.Window.isInFreeWindowMode(): boolean` | API 22 | PC 与平板自由多窗 / MatePad Edge 电脑模式的**唯一**判据 |
| 自由窗口模式变化 | `window.Window.on('freeWindowModeChange', Callback<boolean>)` | API 22 | 配对 `off` |
| 沉浸标题栏 | `setWindowDecorVisible(false)` | API 11 | 隐藏原生标题栏，页面延伸至标题栏区域 |
| 标题栏高度 | `setWindowDecorHeight(h)` / `getWindowDecorHeight()` | API 11 | 取值 `[37,112]` vp |
| 三键区 | `getTitleButtonRect()` / `on('windowTitleButtonRectChange')` | API 11 | 矩形坐标相对**窗口右上角** |
| 三键样式/显隐 | `setDecorButtonStyle()` / `setWindowTitleButtonVisible()` | API 14 | 仅自由窗口下生效 |
| 悬浮标题栏 | `setTitleAndDockHoverShown(false, true)` | API 14 | 保留 Dock，禁用 hover 悬浮标题栏 |
| 窗口拖动 | `startMoving()`（**只能在 `onTouch` 的 `TouchType.Down` 回调中调用**） | API 14 | 用 `moveWindowTo` 会不跟手，禁止 |
| 窗口状态 | `getWindowStatus()` / `on('windowStatusChange')` | API 12/11 | `WindowStatusType` |
| 安全区 | `getWindowAvoidArea()` / `on('avoidAreaChange')` | API 9 | `TYPE_SYSTEM` 不含底部，底部用 `TYPE_NAVIGATION_INDICATOR` |
| 沉浸光感材质 | `new uiMaterial.ImmersiveMaterial({...})` + `.systemMaterial(m)` | API 26 | 需 `targetAPIVersion ≥ 26.0.0`，已满足 |
| 材质能力探测 | `uiMaterial.isImmersiveMaterialSupported()` / `getGlobalMaterialLevel()` | API 26 | 不支持时必须优雅降级 |
| 材质使能 | `module.json5` metadata `ohos.arkui.UIMaterial.state = enable` | API 26 | 仅 entry 模块生效 |
| 毛玻璃 | `.backgroundBlurStyle(BlurStyle)` / `.backgroundEffect({...})` | API 11 | 非标题栏/页签区域用此实现玻璃感 |
| 键鼠 | `onKeyEvent` / `onKeyPreIme` / `getModifierKeyState()` / `onMouse` / `onAxisEvent` / `onHover` | 11+ | 见 §2 归一化 |

**禁止**：`window.moveWindowTo` 做拖动；`setWindowLayoutFullScreen` 之后不读避让区；用设备类型
判断布局断点（CodeLinter `one-multi-breakpoint-check`）；`getUIContext()` 在 `loadContent` 之前调用；
6 位色值的 `statusBarContentColor`（必须 8 位 ARGB）。

## 1. 设备能力与分流（T2 交付，其他模块只读）

新增 `entry/src/main/ets/utils/DeviceProfile.ets`：

```ts
export enum DeviceClass { PHONE = 0, TABLET = 1, PC = 2 }
export enum InputModality { TOUCH = 0, POINTER = 1, MIXED = 2 }
export enum LayoutTier { SINGLE = 0, DOUBLE = 1, TRIPLE = 2 }

/** 一次快照：不可变语义，读的时候整体替换 */
export class DeviceSnapshot {
  deviceClass: DeviceClass = DeviceClass.PHONE
  /** window.isInFreeWindowMode()：PC 与平板电脑模式（MatePad Edge）均为 true */
  freeWindow: boolean = false
  windowStatus: number = 0            // window.WindowStatusType
  breakPoint: BreakPoint = BreakPoint.SM
  modality: InputModality = InputModality.TOUCH
  /** 顶部标题栏高度（含安全区，vp）；0 表示无自绘标题栏 */
  chromeHeightVp: number = 0
  /** 原生三键区宽度（保留原生三键时内容需右避让，vp） */
  titleButtonWidthVp: number = 0
  safeTopVp: number = 0
  safeBottomVp: number = 0

  get tier(): LayoutTier          // SINGLE: SM；DOUBLE: MD；TRIPLE: LG
  get isDesktopChrome(): boolean  // freeWindow === true
  get pointerPrimary(): boolean   // modality === POINTER（仅实测到指针输入；MIXED 不作为键鼠优先）
}
```

`UiStore` 新增（供所有 UI 读取，**T2 拥有**）：

- `@Trace deviceClass: DeviceClass`
- `@Trace freeWindowMode: boolean`
- `@Trace pointerPrimary: boolean`
- `get isDesktopMode(): boolean` → `deviceClass === PC || freeWindowMode`
- `get isTabletDevice(): boolean` → `deviceClass === TABLET`
- `get usesDesktopChrome(): boolean` → `freeWindowMode`（平板电脑模式同样走桌面 chrome）
- 保留 `get isPc()`，语义改为 `isDesktopMode && isWide`（兼容旧调用）

**分流规则（三层正交，不得互相替代）**

1. 布局层级 `LayoutTier` 只由窗口宽度断点决定（沿用 `BreakPoint.ets`）。
2. 设备形态 `DeviceClass` 只决定 chrome 与命中区风格（手机/平板/电脑），不决定断点。
3. 输入形态 `InputModality` 决定悬停、右键、快捷键、焦点策略；触摸为主时不启用 hover-only 交互。

布局映射：

| 形态 | 布局 | 交互要点 |
|---|---|---|
| 手机（PHONE，SM/MD） | 单列 `MobileShell`，文稿列表 + 整屏编辑 | 触摸手势、选区手柄、长按菜单；不显示 hover、不显示窗口三键 |
| 平板（TABLET，MD） | 侧栏抽屉 + 单列内容（`MobileShell.medium`） | 触摸为主；侧栏可滑出；命中区 ≥ 48vp |
| 平板（TABLET，LG） | 侧栏 + 列表 + 内容三栏或双栏分栏 | 触摸为主、键鼠可选；分栏比例可拖拽 |
| 电脑（PC 或 freeWindow） | 自绘沉浸标题栏 + 三栏 + 桌面工具条 | 键鼠优先：快捷键、hover、右键菜单、滚轮、焦点环 |

## 2. 编辑器交互归一（T1 交付）

统一链路：

```
触摸 / 鼠标 / 键盘 / 输入法 / 外接键盘
        ↓（各端只做输入适配，不写业务分支）
InputAdapter（CanvasTextEditor 内的输入适配器）
        ↓
EditCommand（统一命令对象）
        ↓
EditorCommandRouter（唯一分发点，按命令执行）
        ↓
EditCommandHost（由 CanvasTextEditor 实现：文档/选区/光标/排版/动画）
```

新增文件（均在 `entry/src/main/ets/editor/interaction/`）：

- `EditCommand.ets`
  - `enum EditCommandKind { NONE, INSERT_TEXT, DELETE_BACKWARD, DELETE_FORWARD, DELETE_WORD_BACKWARD, MOVE_LEFT, MOVE_RIGHT, MOVE_UP, MOVE_DOWN, MOVE_WORD_LEFT, MOVE_WORD_RIGHT, MOVE_LINE_START, MOVE_LINE_END, MOVE_DOC_START, MOVE_DOC_END, PAGE_UP, PAGE_DOWN, SELECT_ALL, COPY, CUT, PASTE, UNDO, REDO, TOGGLE_BOLD, TOGGLE_ITALIC, TOGGLE_HEADING, SAVE, FIND, DISMISS }`
  - `enum InputSource { TOUCH, POINTER, KEYBOARD, IME }`
  - `class Modifiers { ctrl = false; shift = false; alt = false; meta = false }`
  - `class EditCommand { kind = EditCommandKind.NONE; text = ''; mods = new Modifiers(); source = InputSource.KEYBOARD; repeat = false }`
  - `function isCaretCommand(kind): boolean`，`function isEditingCommand(kind): boolean`
- `ShortcutMap.ets`
  - `function resolveShortcut(keyCode: number, keyText: string, isDown: boolean, mods: Modifiers, composing: boolean): EditCommand`
  - 键位表：`Ctrl+A/C/X/V/Z/Y`；`Ctrl+Shift+Z` 重做；`Ctrl+S` 保存；`Ctrl+F` 查找；`Ctrl+B/ Ctrl+I` 粗/斜；`Ctrl+Home/End` 文首/文末；`Ctrl+←/→` 按词移动；`Shift+方向/Home/End/Up/Down` 扩选；`PageUp/PageDown` 翻页；`Home/End` 行首/行尾；`Backspace/Delete`；`Enter` 换行；`Esc` 关闭浮层；`Tab` **不消费**（交还焦点遍历）。
  - **打印字符不在此处决定插入**：有输入法时由 IME `insertText` 提交；仅当输入法不可用（attach 失败）时才由键盘兜底插入（见下）。
- `EditorCommandRouter.ets`
  - `interface EditCommandHost { insertText(text: string): void; ... }`（方法集合见实现，全部使用基本类型，禁止传 class 实例跨层）
  - `class EditorCommandRouter { dispatch(cmd: EditCommand, host: EditCommandHost): boolean }`
- `InputArbiter.ets`
  - `shouldConsumePreIme(cmd: EditCommand, imeUsable: boolean): boolean`：走位/组合键在 preIme 截获；字母键放行给输入法；`imeUsable === false` 时允许字符键在 preIme 直接消费。
  - `class ImeEchoGuard { claim(text: string, nowMs: number): boolean }`：键盘兜底插入后 40ms 内到达的同文本 IME 回调视为回声丢弃，防止双输入。

`CanvasTextEditor` 改造要求：

1. 实现 `EditCommandHost`，`applyKeyCommand` 迁到 router 分发；保留原有触摸/选区/动画逻辑不变。
2. `handleKeyPreIme` / `handleKeyEvent` 只做事件→命令的转换，**不再**依据内部 `focused` 标志丢弃按键（框架能派发按键即代表已获焦；收到按键时把 `focused` 校正为 true）。
3. `Tab` 不再插入两个空格（返回 `false`，恢复焦点遍历）；缩进改用 `Ctrl+]` / `Ctrl+[`（可选）。
4. 输入法 attach 失败时置 `imeUsable = false`，字符键走键盘兜底；attach 成功时字符键交给 IME。
5. 电脑模式（`pointerPrimary` / `desktopMode`）下：
   - 悬停时用 `getUIContext().getCursorController().setCursor(pointer.PointerStyle.TEXT_CURSOR)` 显示文本光标（移出时 `restoreDefault()`；不用 `.pointerStyle()`——它只是 type 别名取不到枚举值）；
   - 右键菜单支持 `Esc` 关闭、方向键移动高亮、`Enter` 执行；
   - 滚轮只改滚动，不移动光标；
   - 鼠标移出组件时结束拖选（已存在，保留）。
6. `TextEditorHost` 新增 `@Prop desktopMode: boolean`、`@Prop pointerPrimary: boolean`（默认 false，保持 V1 岛屿契约：只传基本类型）。
7. `EditorPane` 从 `app.ui.isDesktopMode` / `app.ui.pointerPrimary` 传参；电脑/平板（键鼠）显示格式工具条，手机保持最小 chrome。

**不得回退**：触摸点击定位、拖选、选区手柄、长按选词、双指/滚动惯性、软键盘 IME 组字、打字机滚动。

## 3. 沉浸标题栏（T2 交付）

新增 `entry/src/main/ets/shell/DesktopTitleBar.ets`（替换 `PcWindowBar.ets`，后者保留薄壳转导出以兼容测试）：

- 高度 `48vp`（≥ 系统下限 37vp），背景为沉浸材质（T3 提供 `GlassBarStyle`）或主题渐变兜底；
- 左侧标题（`app.project.bookName`，空则 `Weaver`），中间为拖拽热区（`layoutWeight(1)`），右侧最小化 / 最大化-还原 / 关闭三键；
- 拖拽：`onTouch(TouchType.Down)` 调 `startMoving()`；`onMouse(Press, Left)` 兜底；双击空白区 `maximize()`/`recover()`；
- 关闭：先 `app.flushAll()`，再 `getUIContext().getHostContext() as common.UIAbilityContext` → `terminateSelf()`；
- 监听 `windowStatusChange`（切图标 + 重读安全区）、`windowTitleButtonRectChange`（避免压住原生三键）、`avoidAreaChange`；
- 标题栏可见条件：`app.ui.usesDesktopChrome`（自由窗口模式），**不再**用 `deviceInfo.deviceType === '2in1'`。
- 无障碍：三键 `accessibilityText('最小化' | '最大化' | '还原' | '关闭')`，`hoverEffect(HoverEffect.Highlight)`，键盘可聚焦（`focusable(true)` + `tabStop(true)`）。

`AppShell` 改造：

- 用 `usesDesktopChrome` 决定渲染 `DesktopTitleBar`，并把它放在安全区之下的第一行；
- 根容器 padding：`top = chromeHeight + safeTop`（chrome 显示时 `safeTop` 已含在 chrome 内，避免双算，需在实现处明确并注释）；
- 手机/平板保持现有 `expandSafeArea` + 避让逻辑，不得与电脑模式冲突；
- 断点变化时同步 `DeviceSnapshot`，并把 `windowSizeChange`/`freeWindowModeChange`/`avoidAreaChange` 统一到 `DeviceProfile` 订阅。

`EntryAbility.ets` 改造：`isInFreeWindowMode()` 初值 + `on('freeWindowModeChange')` 写入 `AppStorage('freeWindowMode')`；`windowStage.on('windowStageEvent')` 在 `ACTIVE` 时置 `AppStorage('windowActiveTick', Date.now())` 供编辑器重新聚焦（T1 读取，见下）。

> T1 通过 `AppStorage.get<number>('windowActiveTick')` 的监听不可用（AppStorage 非响应），
> 因此由 T2 在 `DeviceProfile` 暴露 `onWindowActivated(cb)` 订阅函数；T1 在 `TextEditorHost`
> `aboutToAppear` 订阅、`aboutToDisappear` 取消，回调里 `controller.focus()`。

## 4. 沉浸光感（T3 交付）

新增 `entry/src/main/ets/constants/LightTokens.ets`：

- `class GlassSpec { style: uiMaterial.ImmersiveStyle; blur: BlurStyle; gradient: Array<[string, number]>; borderColor: string; opacity: number }`
- `function immersiveSupported(): boolean`（模块内缓存一次 `uiMaterial.isImmersiveMaterialSupported()`）
- `function materialLevel(): uiMaterial.MaterialLevel`
- `function immersiveMaterial(style: uiMaterial.ImmersiveStyle, interactive: boolean): uiMaterial.ImmersiveMaterial | undefined`
- `function chromeGlass(themeId: string): GlassSpec`、`function cardGlass(themeId: string): GlassSpec`、
  `function pageGlow(themeId: string): Array<[string, number]>`（页面光感渐变）
- 低算力/不支持材质的降级：`glassLevel(themeId): GlassLevel { FULL, REDUCED, OFF }`，`OFF` 时只用不透明度 + 1px 描边，禁用 blur。

新增 `entry/src/main/ets/shell/MaterialSurface.ets`：

- `@Builder function GlowPageBackground(themeId: string)`：`linearGradient` + 顶部径向光晕，只画一层，不吃点击；
- `@Builder function GlassBar(themeId: string, content: () => void)`：chrome 玻璃条（`backgroundBlurStyle` + 渐变）；
- `@Builder function GlassCard(themeId: string, content: () => void)`：卡片玻璃；
- 所有 builder 内部**不得**引入 `any`、动态属性、`Object.assign`。

覆盖范围（必须全部覆盖，保持一致性）：

`AppShell` 背景 / `DesktopTitleBar`（T2 应用）/ `MobileShell` 标题栏 / `DocListPane` 头部与选中态 /
`ProjectSidebar` / `WorkspaceDest` / `SettingsDest` / `InputDialog` 遮罩与卡片 / `GuideSwiperPage` /
`Index` / `EditorPane` 浮动字数与工具条。

约束：

- 每屏最多 2 层实时模糊（顶栏 + 底栏/浮层），卡片用渐变+描边，避免过度绘制；
- 深色/浅色都要有对应渐变与描边，对比度 ≥ 4.5:1；
- 动效统一 `180ms / Curve.EaseOut`（与既有规范一致）；
- `module.json5` 增加 metadata（T2 落盘，T3 提供片段）：
  ```json5
  "metadata": [{ "name": "ohos.arkui.UIMaterial.state", "value": "enable" }]
  ```

## 5. 文件归属（写入范围，避免冲突）

| 归属 | 文件 |
|---|---|
| T1 editor-input | `entry/src/main/ets/editor/**`（含 `TextEditorHost.ets`）、`entry/src/main/ets/shell/EditorPane.ets` |
| T2 device-shell | `entry/src/main/ets/utils/DeviceProfile.ets`（新）、`utils/BreakPoint.ets`、`utils/SafeArea.ets`、`utils/DesktopWindowChrome.ets`、`utils/SystemBars.ets`、`entryability/EntryAbility.ets`、`shell/AppShell.ets`、`shell/DesktopTitleBar.ets`（新）、`shell/PcWindowBar.ets`、`store/UiStore.ets`、`entry/src/main/module.json5` |
| T3 visual | `entry/src/main/ets/constants/DesignTokens.ets`、`constants/LightTokens.ets`（新）、`shell/MaterialSurface.ets`（新）、`shell/MobileShell.ets`、`shell/DocListPane.ets`、`shell/ProjectSidebar.ets`、`shell/WorkspaceDest.ets`、`shell/InputDialog.ets`、`shell/MobileTabBar.ets`、`shell/MobileSectionTabs.ets`、`shell/SettingsPanel.ets`、`pages/**` |
| T4 verify-docs | `tools/**`、`docs/**`（本文件除外）、`README.md` |

**任何跨归属修改先通过 Lead**；不得改动 `build-profile.json5` 的 SDK 版本与签名。

## 6. 验收口径

1. `node tools/flowtext-regression.cjs`、`data-regression.cjs`、`shell-regression.cjs`、`window-regression.cjs`、`import-regression.cjs` 全绿（现有 130 项不得减少）。
2. 新增回归覆盖：设备分流、快捷键映射、IME 回声抑制、标题栏拖拽/三键、材质降级。
3. 设备侧构建：`./tools/Test-FlowText.ps1 -DevEcoRoot <CLT> -JavaRoot <jbr> -BuildOnly` 输出 `BUILD SUCCESSFUL`，Hypium `Failure:0 Error:0 Ignore:0`。
4. 手工验收清单见 `docs/refactor/multidevice-self-test.md`（T4 产出）。
