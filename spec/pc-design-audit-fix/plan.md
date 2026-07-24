# Implementation Plan: Weavr PC 端 HarmonyOS Design 审查整改

**Input**: Feature specification from `spec/pc-design-audit-fix/spec.md`

## Summary

对 Weavr 现有 PC 端三分栏布局进行 HarmonyOS Design 合规整改。核心改动五方面：(1) 为所有可交互元素补全按压/悬停/键盘焦点三态反馈，(2) 通过 `setWindowDecorVisible(false)` 隐藏系统标题栏并新建自定义标题栏组件，(3) 建立深色/浅色双模式色彩 Token 体系，(4) 清理误导性 Token 命名并统一手机/PC 端蓝色强调色，(5) 添加无障碍语义标签、修复折叠导航指示器、优化查找栏过渡动画、修正折叠按钮布局 hack。

遵循现有项目架构，不引入 MVVM 重构，不新增模块。全部改动局限在 8 个现有文件和 1 个新建文件，预计 ~480 行代码变更。

## Technical Context

**Language/Version**: ArkTS (HarmonyOS API Level 22, SDK 6.0.2)
**Primary Dependencies**: @kit.ArkUI (window, stateStyles, onHover, focusable, accessibilityText, TransitionEffect), @kit.AbilityKit (ConfigurationConstant.ColorMode, onConfigurationUpdate), 现有项目模块 (@ohos/common, @ohos/editor 等)
**Storage**: 无新增存储需求（深色模式通过 AppStorage 传播系统状态）
**Testing**: build_project 编译验证 + 2in1 设备人工交互验证
**Target Platform**: HarmonyOS 6.0.2, 设备类型 phone/tablet/2in1，PC 布局阈值 ≥ 840vp 宽度
**Project Type**: 现有 HarmonyOS 多模块 HAR/HAP 项目（1 entry + 6 HAR libraries）
**Performance Goals**: 60fps 无掉帧，按压反馈 < 50ms，hover 过渡 100ms，深色切换 < 300ms
**Constraints**: 不改变现有三分栏骨架、不改变断点逻辑、不引入新模块、不替换 Unicode 图标为 SVG
**Scale/Scope**: 8 个现有文件修改 + 1 个新文件，~480 行变更，0 个新增模块依赖

## Project Structure

### Documentation (this feature)

```text
spec/pc-design-audit-fix/
├── spec.md              # 需求规格（Phase 1 产出）
└── plan.md              # 本文件（Phase 2 产出）
```

### Source Code (repository root)

```text
D:\Project_code\Weaver\
├── products/default/src/main/ets/
│   ├── entryability/
│   │   └── MainAbility.ets              # [修改] +setWindowDecorVisible, +onConfigurationUpdate
│   ├── pages/
│   │   └── Index.ets                    # [修改] 统一蓝色 Token 引用
│   └── pclayout/
│       ├── PcTitleBar.ets               # [新建] 自定义标题栏组件
│       ├── PcShell.ets                  # [修改] -statusBarHeight, +PcTitleBar, Rail 指示器
│       ├── PcSidebar.ets               # [修改] +stateStyles, +onHover, +focusable, +accessibility
│       ├── PcDocList.ets               # [修改] +stateStyles, +onHover, +focusable, +accessibility
│       ├── PcEditorZone.ets            # [修改] +stateStyles, +onHover, +focusable, +accessibility, +查找栏动效
│       ├── PcAgentPanel.ets            # [修改] +stateStyles, +onHover, +accessibility
│       ├── PcDesignTokens.ets          # [修改] Token 重命名, +PcInteraction, +双模式色值
│       └── WeaverViewModel.ets         # [修改] Token 重命名引用更新
├── common/src/main/ets/constants/
│   └── Colors.ets                       # [修改] SemanticColors 统一蓝色
└── products/default/src/main/resources/
    └── dark/element/
        └── color.json                   # [修改] 补充 PC 暗色资源定义
```

**Structure Decision**: 遵循现有项目架构。Weavr 已有清晰的模块划分（entry 含 pclayout/ 子目录、common 含 constants/）。本次改动全部限制在现有文件范围内，仅在 pclayout/ 下新增一个 `PcTitleBar.ets`（标题栏职责独立，~80 行）。不引入 MVVM 重构——pclayout/ 已有 WeaverViewModel.ets 承担数据层，PcShell.ets 承担编排层，架构足够。

## Complexity Tracking

无 Constitution 违规项。本次为对已有布局的合规性精修，不涉及架构级复杂度增加。

## Research & Decisions

### 决策 1: 标题栏融合 → `setWindowDecorVisible(false)`

- **Decision**: 在 `MainAbility.onWindowStageCreate` 中调用 `mainWin.setWindowDecorVisible(false)`，仅在断点为 LG（≥ 840vp）时生效。配合自定义 `PcTitleBar.ets` 提供窗口拖拽和应用标识。
- **Rationale**: HarmonyOS 官方窗口装饰控制 API，API 22 已正式支持。自由窗口模式下隐藏标题栏后需自定义拖拽区域（`window.startWindowMove()`）以保持窗口可移动性。
- **Alternatives considered**: `setWindowLayoutFullScreen(true)` — 此 API 改变布局区域但不隐藏装饰，适用场景不同。保留系统装饰仅压扁自定义顶栏 — 不改动窗口架构，但"双层帽"问题未根除，纵向空间浪费不可接受。

### 决策 2: 按压反馈 → `stateStyles`

- **Decision**: 对全量 Button 使用 `stateStyles({ pressed: { .backgroundColor(...) }, normal: { .backgroundColor(...) } })`。对 Row 级可点击区域使用相同模式。实心强调按钮（蓝色背景）在 pressed 时加深至 `EMPHASIZE_PRESSED`；透明工具栏按钮在 pressed 时显示浅灰底色。
- **Rationale**: `stateStyles` 是 ArkUI 原生伪类样式机制，无需手动管理 `@State isPressed`，代码量最小。比 `onTouch` 手动切换更简洁且性能更优（系统级处理）。
- **Alternatives considered**: 手动 `onTouch` + `@State` — 每个按钮需要独立状态变量，~50+ 个额外 @State 声明，代码膨胀。`@Styles` 函数复用 — 可配合 stateStyles 使用但在 Row 上不可用（Row 不继承 Button 的 stateStyles 支持），覆盖面不足。

### 决策 3: 鼠标悬停 → `onHover` + `@State`

- **Decision**: 每个可交互元素添加 `@State isHovered: boolean = false`，绑定 `.onHover((isHover: boolean) => { this.isHovered = isHover })`，`backgroundColor` 根据 `isHovered` 动态切换。过渡统一使用 `.animation({ duration: 100 })`。
- **Rationale**: `onHover` 是 ArkUI 唯一的鼠标悬停检测 API，无其他替代方案。100ms 过渡符合 OpenHarmony 公开参考（简单颜色变化 ≤ 100ms）。
- **Alternatives considered**: 无。`onHover` 是唯一可用 API。

### 决策 4: 键盘焦点 → `focusable` + `focusBorder`

- **Decision**: 为关键导航路径上的元素设置 `.focusable(true)` 和 `.focusBorder({ color: PcColors.FOCUSED, width: 2, style: FocusBorderStyle.SOLID })`。利用 ArkUI 默认的布局树顺序作为 Tab 键移动顺序，该顺序天然匹配视觉布局（侧栏 → 文稿列表 → 编辑区）。
- **Rationale**: ArkUI 内置焦点系统零配置即可工作。布局树顺序 = 视觉顺序，无需手动指定 tabIndex。
- **Alternatives considered**: 自定义焦点管理器 — 完全不必要的复杂度，仅用于覆盖默认行为时才有意义。

### 决策 5: 深色模式 → AppStorage + `onConfigurationUpdate`

- **Decision**: `MainAbility.onConfigurationUpdate` 中写入 `AppStorage.setOrCreate('colorMode', newConfig.colorMode)`；PC 组件通过 `@StorageLink('colorMode')` 监听变化；`PcColors` 改为函数式取值（`pcColors(dark: boolean)`）或组件内计算属性，根据 mode 返回浅/深色值。
- **Rationale**: HarmonyOS 标准深色模式适配模式。UIAbility 的 `onConfigurationUpdate` 是系统级配置变更的唯一入口。AppStorage 是跨组件状态传播的推荐方式。
- **Alternatives considered**: 每组件独立监听 `getContext().config.colorMode` — 重复代码多，无法统一过渡时机。硬编码双套色值不响应系统切换 — 仅支持手动切换，不符合平台要求。

### 决策 6: Token 重命名 → 直接删除 + 机械替换

- **Decision**: 从 `PcDesignTokens.ets` 中删除 `GREEN` / `GREEN_DEEP` / `GREEN_SOFT` / `LINE_2` / `INFO` 五个 Token；新增 `EMPHASIZE_DIMMED` 替代 INFO；全项目 grep + 替换旧引用。
- **Rationale**: 这些 Token 仅被 PC 布局代码（pclayout/ + WeaverViewModel.ets）引用，影响面可控。机械替换零风险。
- **Alternatives considered**: 保留旧名并加 alias — 增加维护复杂度，仅推迟问题，不解决根本歧义。

### 决策 7: 标题栏组件 → 独立文件

- **Decision**: 新建 `PcTitleBar.ets` 作为独立组件，在 `PcShell.ets` 顶部引用。
- **Rationale**: 标题栏有独立职责（窗口拖拽、品牌展示、窗口控制区），与 `PcShell` 的布局编排职责分离。`PcShell` 目前已 184 行，不应继续膨胀。
- **Alternatives considered**: 内联在 `PcShell.build()` 开头 — 更简单但会使 PcShell 突破 200+ 行，且标题栏逻辑与布局逻辑混杂。

## Data Model

### 交互状态模型

每个可交互元素维护至多四种运行时布尔状态：

```
┌─────────────────────────────────────────────────┐
│                   normal                          │
│                      │                            │
│         ┌────────────┼────────────┐              │
│         ▼            ▼            ▼              │
│      pressed      hovered      focused           │
│   (touch/mouse   (cursor      (Tab key           │
│    down 即时)     over 100ms)  即时边框)          │
└─────────────────────────────────────────────────┘
```

状态之间非互斥——一个元素可同时处于 hovered + focused（鼠标悬停 + 键盘焦点）。

### 色彩模式模型

```
colorMode ∈ { COLOR_MODE_LIGHT (1), COLOR_MODE_DARK (0) }
         │
         ▼
  PcColors.resolve(mode) → {
    EMPHASIZE:    '#007DFF' (固定，品牌色不变)
    BG_PRIMARY:   mode===LIGHT ? '#F1F3F5' : '#1A1A1A'
    TEXT_PRIMARY:  mode===LIGHT ? '#182431' : '#E8E8E8'
    ...共 ~20 色值
  }
```

### Token 重命名映射

| 旧名称 | 新名称 | 说明 |
|--------|--------|------|
| `PcColors.GREEN` | `PcColors.EMPHASIZE` | 本就相同值 #007DFF |
| `PcColors.GREEN_DEEP` | `PcColors.EMPHASIZE_PRESSED` | 本就相同值 #006CDE |
| `PcColors.GREEN_SOFT` | `PcColors.EMPHASIZE_FADED` | 本就相同值 #19007DFF |
| `PcColors.LINE_2` | `PcColors.DIVIDER` | 统一分割线 Token |
| `PcColors.INFO` | `PcColors.EMPHASIZE_DIMMED` | 新增，30% 透明度蓝 |

## Contracts & Interfaces

### 新建组件: PcTitleBar

**文件路径**: `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcTitleBar.ets`

```
组件职责:
  - 替代系统原生标题栏，展示应用品牌标识
  - 提供窗口拖拽交互区域
  - 提供系统窗口控制按钮区域（预留）

尺寸: width('100%'), height(32vp)

布局结构:
  Row {
    // 左侧: Logo + 应用名
    [W] Weaver 鸿蒙全场景
    // 中央: 可拖拽空白区
    Blank()  // 绑定 onTouch → window.startWindowMove()
    // 右侧: 窗口控制预留区
  }

对外接口:
  无 @Prop/@Link 依赖 — 完全自包含，仅读取 PcColors 和 PcInteraction
```

### 修改组件: PcShell

**变更摘要**:
- 移除 `@State statusBarHeight: number = 0`
- 移除 `aboutToAppear` 中的 `win.getAvoidArea()` 调用
- 在 `build()` 根 Row 顶部添加 `PcTitleBar()`
- 将 `activeLibId` 状态暴露给 collapsed Rail 区域以启用选中指示器
- Rail 图标 `Circle(...).opacity(0)` → `opacity(activeLibId === 'xxx' ? 1 : 0)`

### 修改: MainAbility

**变更摘要**:
- `onWindowStageCreate` 中 `BreakpointService.getInstance().init(mainWin)` 之后添加:
  - `mainWin.setWindowDecorVisible(false)` (条件: 仅 LG 断点生效，通过检查当前窗口宽度)
  - `mainWin.setWindowSystemBarProperties({ statusBarContentColor: '#182431' })`
- 新增 `onConfigurationUpdate(newConfig: Configuration)` 回调:
  - `AppStorage.setOrCreate('colorMode', newConfig.colorMode)`

### 无障碍合约

所有纯图标按钮（无文本标签）必须添加语义标注：

| 组件 | 图标 | accessibilityText |
|------|------|-------------------|
| PcShell Rail `≡` | ≡ | '显示侧边栏' |
| PcShell Rail `★` | ★ | '收藏' |
| PcShell Rail `✦` | ✦ | '灵感池' |
| PcSidebar `◁` | ◁ | '收起侧边栏' |
| PcSidebar `+` (项目) | + | '新建项目' |
| PcSidebar `▸/▾` | ▸/▾ | '展开/折叠项目列表' |
| PcDocList `▷` | ▷ | '收起文稿列表' |
| PcDocList `×` (删除) | × | '删除文稿' |
| PcDocList `◆` | ◆ | '已置顶' |
| PcEditorZone `×` (Tab) | × | '关闭标签' |
| PcEditorZone `⛶` | ⛶ | '全屏模式' |
| PcEditorZone `✕` (查找) | ✕ | '关闭查找' |
| PcAgentPanel `✕` | ✕ | '关闭写作伴侣' |

### Token 迁移合约

全项目 grep 验证：迁移后 `GREEN`, `GREEN_DEEP`, `GREEN_SOFT`, `LINE_2` 在 `pclayout/` 目录和 `WeaverViewModel.ets` 中零匹配。同时 `common/Colors.ets` 的 `SemanticColors.INTERACTIVE_PRIMARY` 值更新为 `'#007DFF'`，`Index.ets` 中 `GreenColors.G500` 引用替换为 `SemanticColors.INTERACTIVE_PRIMARY`。
