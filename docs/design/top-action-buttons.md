# 顶部操作图标与原生三键配色（Email 参考）

> 2026-10-21 修订：**取消顶部按钮的沉浸光感圆片**，改为华为电子邮件那种裸图标；
> 同时要求原生三键（最小化/还原/关闭）的颜色跟随应用主题，而不是跟随系统深浅。
> 本文取代「顶部圆形沉浸光感按钮」的旧规范。

## 一致性结论（Email / 备忘录 / 本应用）

- **Pane 自己的头部**承载操作，不做一条全局工具栏；
- 高频操作是**裸 Symbol 图标**：无底色、无描边、无阴影、无实时模糊；
  只有指针悬停/键盘焦点时才浮出一层极淡的圆形底，按下再深一档；
- 图标深色（`textPrimary`）、线性、20vp 左右；分组之间用 1px 分隔线或留白，不画按钮框；
- 低频动作收进 more（⋯），窗口控制留在最右上角；
- 大标题、正文、列表在图标下方独立成层级，靠底色与间距分区，不靠重边框；
- **差异**：Email 顶栏图标更疏（间距约 12–16vp）；备忘录偏平板，图标与热区都更大。
  本项目以 Email 的 40vp 视觉基准为准，只把热区按输入方式放大。

## 设计规范（两套形态）

桌面 = PC / MatePad Edge 电脑模式；平板 = 触摸平板且非电脑模式。由
`LightTokens.topIconMetrics(pointerPrimary, tabletMode)` 统一给出，组件不自己拍数字。

| 项 | 桌面（电脑） | 平板（触摸） |
|---|---|---|
| 状态底 | **40vp 圆角方形**（8vp） | **44vp 圆形** |
| 点击热区 | 44vp（键鼠）/ 48vp | **56vp** |
| 图标 | 20vp | **24vp** |
| 相邻间距 | 12vp（margin 4） | 12vp（margin 6） |
| 触摸焦点 | `focusOnTouch(false)`：点按不抢焦点，状态底不残留 | 同左 |
| 静态外观 | **透明**：无底色、无高光描边、无阴影、**0 层实时模糊** |
| 普通 | 图标 `textPrimary` |
| Hover / 键盘焦点 | 40vp 圆形底 `hoverBg`，图标不变 |
| 按下 | 圆形底 `activeBg`（比 hover 深一档），120ms 标准曲线 |
| 选中 | 图标 `brand`；底保持透明（不叠浅底，避免像"按钮选中态"） |
| 禁用 | 整体 opacity 0.38，图标 `textTertiary`，不可点、不可聚焦 |
| 动效 | 只做底色渐变 120ms；无缩放、无位移、不做布局尺寸动画 |
| 无障碍 | `accessibilityText` = 动作名，禁用时追加"（不可用）"；`focusable/tabStop` |

## 为什么不放玻璃材质

顶栏同时存在 6–8 个动作，每个都叠一层「渐变 + 高光 + 阴影」会：

1. 在稿纸这种大面积暖白底上出现一排"白药丸"，与正文抢层级（用户实测反馈）；
2. 多个模糊面叠加，逼近每屏 ≤2 层实时模糊预算；
3. 与 Email / 备忘录的实际做法不一致——它们的顶栏就是裸图标。

因此材质只保留在**面板级**容器（侧栏薄纱、卡片、浮层），顶栏动作一律裸图标。

## 窗口三键（最小化/还原/关闭）：保留原生

- **不使用自绘三键**（用户明确要求）。三键始终是系统绘制的原生按钮：
  `setWindowTitleButtonVisible(true, true, true)`，位置/尺寸用 `getTitleButtonRect()` 避让。
- 颜色由**窗口 colorMode** 决定，而窗口在主窗创建前就固定了 colorMode：
  `EntryAbility.onCreate` 里先按默认浅色建窗（`applyAppColorMode(false)`），
  避免"系统深色 + 应用浅色"时被锁成白色三键；夜读用户在 prefs 加载后再重建一次。
- `setDecorButtonStyle` 官方只对"带窗口标题"的窗口生效，所以 `refreshDecorColorScheme`
  的顺序是 **显示装饰栏 → 下发样式 → 隐藏**，而不是对着隐藏的装饰栏下发。
  官方 FAQ 说明深色模式下三键会显示为白色以保证对比度
  （[faqs-computer-7](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-computer-7)）。
- 由于窗口在创建时就固定了 colorMode，之后再改应用 colorMode 不会自动重绘三键，所以：
  - `AppChromeMode.applyAppColorMode()` 在主题写入时同步应用 colorMode；
  - `refreshDecorColorScheme()` 在**启动完成**与**主题明暗变化**时切换一次装饰栏显隐，
    让系统按新 colorMode 重建三键（只在这两个时机，避免可见闪烁）；
  - `windowStatusChange` 监听：最大化/还原/全屏后重新下发三键样式与系统栏配色。

## 三键配色（历史说明）

- 窗口 `setWindowDecorVisible(false)` + `setWindowTitleButtonVisible(true,true,true)`：
  标题栏隐藏、三键保留，由系统绘制；
- 三键颜色通过 `setDecorButtonStyle({ colorMode })` 下发：**只改明暗**，
  图标尺寸与按钮间距一律交还系统默认（一旦 app 指定，系统会重排三键，视觉上像互相重叠）：
  - 浅色主题（纸墨/米纸/青笺）→ `COLOR_MODE_LIGHT` → 深色图标；
  - 深色主题（夜读）→ `COLOR_MODE_DARK` → 白色图标；
- 下发时机：`UiStore.syncSystemBars()` 末尾调用 `syncDesktopDecorButtons(t.dark)`，
  覆盖启动、切换主题、跟随系统深浅、窗口状态变化；
- 顶栏/工具行右侧避让：`UiStore.captionInset = max(getTitleButtonRect().width + 24, 168)`，
  `EditorPane` 与 `FocusWorkspace` 都用它，窗口缩放后自动重排，图标不会被三键压住；
- 只在桌面窗口（`isPcDevice` 或 `freeWindowMode`）下发，手机/平板不刷 801 告警；
- 3 个失败分支全部 try/catch，只降级不断链。

## 菜单：一律用系统菜单组件

自绘弹层无法复刻系统的弹出曲线与面板材质，和华为电子邮件始终"差一口气"。因此两处菜单都改回原生：

| 入口 | API | 触发 | 备注 |
|---|---|---|---|
| 列表头「⋯」 | `bindMenu` + `Menu/MenuItem` | 点击 | 电脑 14vp 字号、平板 16vp；同一份菜单两套外观 |
| 列表行操作 | `bindContextMenu` + `Menu/MenuItem` | 电脑**右键** / 触摸**长按** | 无预览图 → 非模态、无蒙层，就是"用一个菜单栏" |

- 触发器**不能复用 `TopActionButton`**：自定义组件外层有壳，`bindMenu` 挂在壳上时点击会被
  组件内部的 `onClick` 吃掉，菜单不弹（实测）。`MenuButton` 因此把状态底 + `⋯` 字形直接画在
  一个普通 `Stack` 上，让 `bindMenu` 成为唯一的点击接收者；
- 触发器的形态仍走 `topIconMetrics(pointerPrimary, tabletMode, desktopMode)`：
  电脑 40vp 方形（8vp 圆角）、平板 44vp 圆形 —— 少传 `desktopMode` 会退化成圆形（已修）；
- 位置与对齐：`bindMenu(..., { placement: Placement.BottomRight })` —— 菜单右边缘与 ⋯ 对齐、
  向左展开，不越过本栏边界（默认 `BottomLeft` 会从左边缘向右长，压到右栏）；
- 位置、材质、动画、点击后关闭全部由系统负责，和电子邮件同一套观感；
- 不再使用 `showActionMenu`（半模态动作面板，带「取消」）与自绘 `bindPopup`；
- 行菜单内容：废纸篓「恢复 / 彻底删除」；普通文稿「重命名 / 收藏（或取消）/ 灵感（移入或移出）/ 移入废纸篓」；
- 电脑端行菜单只有右键，触摸端只有长按（`contextTrigger()` 按 `usesDesktopChrome` 分流）。

## 设置：半模态面板（不是右侧页面）

- `AppShell` 持有 `showSettings`，用 `bindSheet(this.showSettings, this.settingsSheet(), options)`：
  `preferType: SheetType.CENTER`（桌面上居中浮出）、`showClose: true`（右上角 X）、
  `title: { title: '设置' }`、`height: SheetSize.LARGE`；
- `onWillDismiss` 里 `action.dismiss()` 并把 `showSettings` 复位，点遮罩/关闭都能正确收起；
- 设置内容抽成 `SettingsPanel`（无标题栏、无背景），半模态与旧的 `SettingsDest` 页面共用同一份；
- 入口（列表头 ⋯ → 设置、平板顶栏「设置」）都改成打开面板，不再 `nav.pushPath`。

## 列表横滑动作：电脑没有，触摸学备忘录

| 形态 | 交互 |
|---|---|
| 电脑（PC / MatePad Edge 电脑模式） | **不提供横滑**；右键弹出原生菜单（重命名/收藏/灵感/废纸篓） |
| 手机 / 平板 / 折叠屏 | 行左滑露出**一组圆形图标按钮**（收藏 / 灵感 / 重命名 / 删除），行保持圆角；执行后自动收起 |

- 圆形钮 44vp（平板 48），白字 + 固定强调色（收藏 `#E8A33D`、灵感 `#4C8DFF`、重命名 `#8B8B90`、
  删除 `#E04B4B`），不随主题明暗变 —— 与备忘录一致，保证深浅色下对比度都够；
- 动作执行前先 `closeAllSwipeActions()`，不留展开态；
- 电脑端判据是 `usesDesktopChrome`（PC 与 Edge 电脑模式），不是"有没有鼠标"。

## 平板其它尺寸放大

| 元素 | 电脑 | 平板 |
|---|---|---|
| 列表页大标题 | 20vp | **28vp** |
| 列表行标题 / 摘要 / 时间 | 14 / 12 / 11vp | **17 / 13 / 12vp** |
| 列表行高 | ≥56vp | **≥64vp** |
| 搜索框高度 | 36vp | **44vp** |
| 列表头内边距 | 16 / 12 | **20 / 16** |
| 侧栏行高（项目 / 文库） | 44 / 40vp | **52 / 48vp** |
| 编辑工具行高 | 48vp | **56vp** |
| 列表栏宽度（LG） | 320vp | **380vp** |

平板进入首页会**自动打开最近文稿**（即使三栏），避免右侧一大块空态；空态本身收敛到 760vp 阅读列。

## 宽度分档（窄编辑列不溢出）

编辑器工具组按**实测可用宽度**分档，绝不把图标画到右上角原生三键下面：

| 档 | 可用宽度（vp） | 显示 |
|---|---|---|
| L0 | ≥ 450 | 撤销 重做 ｜ B I H1 ｜「打字机」胶囊 查找 专注 |
| L1 | ≥ 420 | 同上，打字机收成纯图标 |
| L2 | ≥ 232 | 撤销 重做 ｜ ⋯ ｜ 查找 专注 |
| L3 | ≥ 188 | 撤销 重做 ｜ ⋯ ｜ 查找 |
| L4 | < 188 | 只留撤销 / 重做 |

- 可用宽度 = `headerWidth`（头部 `onAreaChange` 实测）− 12vp 左内边距 − `captionInset`；
- L2/L3 的 ⋯ 用 `showActionMenu` 弹出「加粗 / 斜体 / 标题 / 打字机 / 专注写作」，功能不丢；
- L2/L3 图标 `gap` 由 4 收成 0（44vp 热区贴紧），再省 16vp；
- 为什么不用窗口断点：窗口可以很宽、编辑列却很窄（三栏 + 侧栏 + 列表之后只剩 ~370vp）。

## 组件与 token

- 组件：`shell/TopActionButton.ets`（`@Param isEnabled`，避开 `CustomComponent.enabled` 同名冲突）
- 尺寸 token：`TOP_ICON_SIZE=40` / `TOP_ICON_HIT_POINTER=44` / `TOP_ICON_HIT_TOUCH=48` /
  `TOP_ICON_FONT=20` / `TOP_ICON_MARGIN=4`
- 使用位置：
  - `EditorTools`：撤销/重做/B/I/H/查找/专注；
  - `DocListPane`：目录开关、新建文稿、更多；
  - `ProjectSidebar`：新建项目。
- 打字机是带文字的两态模式，L0 保留胶囊、L1 起收成图标；专注模式的退出按钮同样是扁平胶囊（仅 hover 底色）。
- 已删除：`WeaverGlassKind.ICON`、`iconGlass()`、`MaterialSurface.glassIconStyle()`、
  `GLASS_ICON_*`（改为 `TOP_ICON_*`）。
