# Implementation Plan: 手机端 UI 重构 —— 断点栅格驱动的移动端体验重做

**Input**: Feature specification from `spec/mobile-ui-refactor/spec.md`

**Note**: 本文件由 SDD Phase 2 生成。所有设计均为架构/接口契约层面，不含实现代码。

## Summary

为 Weaver 的**手机形态**引入以**官方系统窗口宽度断点**为唯一驱动的响应式外壳：

- **`sm`（<600vp，手机竖屏）**：单列内容 + **底部页签栏**（项目 / 文稿 / 素材 / 关系图），移除旧版一整条堆叠文字功能条；打开文稿后进入沉浸式单列编辑页。
- **`md`（600–840vp，手机横屏 / 折叠展开 / 小平板）**：**侧栏 + 内容双栏**，内容区以顶部分段页签切换（文稿 / 素材 / 关系图）。
- **`lg`（≥840vp，平板 / 电脑）**：**完全保持重构前布局与视觉不变（零回归）**。

技术路径：保留现有三分栏骨架（`SideBarContainer` + `Navigation`）与全部业务组件（`ProjectSidebar` / `DocListPane` / `EditorPane` / `MaterialPane` / `GraphPane` / 二级 Dest），新增**断点感知的外壳编排**与**底部页签栏**，并对手机端共享视觉令牌（间距 / 圆角 / 热区 / 字号）做收敛式调整。断点来源改用官方 `UIContext.getWindowWidthBreakpoint()` + `window.on('windowSizeChange')`；内容区使用官方栅格 `GridRow/GridCol` 组织列数与正文缩进。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS NEXT），`compatibleSdkVersion = 6.1.0(23)`，Stage 模型，单 HAP（entry）
**Primary Dependencies**: ArkUI 声明式框架；状态管理 **V2**（`@ComponentV2` / `@Param` / `@Local` / `@Event` / `@ObservedV2` / `@Trace`）；`@kit.ArkUI`（`window` / `promptAction`）；容器组件 `SideBarContainer` / `Navigation` / `Tabs` / `GridRow` / `GridCol`
**Storage**: 现有 RelationalStore（RDB）+ Preferences（本次**不改动**数据层）
**Testing**: 构建验证 `devecocli build`；UI 验证 `devecocli ui screenshot` / `layout` / `click`（需连接设备或模拟器）；本特性**不要求**单元测试，采用截图人工复核
**Target Platform**: HarmonyOS `phone` / `tablet` / `2in1`（`deviceTypes` 已配置）；手机形态为主
**Project Type**: mobile-app（单 entry 模块）
**Performance Goals**: 断点切换无可感卡顿；单页组件节点 <300；列表滚动流畅；满足官方体验指标（点击响应 ≤100ms、滑动 ≤80ms、无连续丢帧）
**Constraints**: `lg` 零回归；布局判据**只用**系统断点；尺寸用 vp、字号用 fp；点击热区 ≥40vp（推荐 48vp）；正文对比度 ≥4.5:1、图标/标题 ≥3:1；禁用设备类型/方向/折叠状态判布局
**Scale/Scope**: 手机端可见界面约 9 类（主壳 / 文稿列表 / 项目文库 / 编辑器 / 素材 / 关系图 / 人物详情 / 世界观详情 / 灵感记录 / 设置 / 引导页）；预计新增 2–3 个组件、修改 ~12 个文件、新增 1 组移动端令牌

## Project Structure

### Documentation (this feature)

```text
spec/mobile-ui-refactor/
├── spec.md              # 需求规格（Phase 1 输出）
├── plan.md              # 本文件（Phase 2 输出）
└── tasks.md             # 任务拆解（Phase 3 输出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── shell/
│   ├── AppShell.ets             # [改] 断点分发：lg 走现有三分栏（不动），sm/md 走 MobileShell
│   ├── MobileShell.ets          # [新] 手机端外壳编排（sm 单列 / md 双栏），内嵌 Navigation 与路由
│   ├── MobileTabBar.ets         # [新] 手机端底部页签栏（项目/文稿/素材/关系图）
│   ├── MobileSectionTabs.ets    # [新] md 内容区顶部分段页签（文稿/素材/关系图）
│   ├── ProjectSidebar.ets       # [改] 令牌/间距/热区手机化；lg 外观与结构不变
│   ├── DocListPane.ets          # [改] 列表行间距/热区；lg 不变
│   ├── EditorPane.ets           # [改] sm：次要操作收纳"更多"；lg 保留现有工具条
│   ├── MaterialPane.ets         # [改] 手机端边距/热区
│   ├── GraphPane.ets            # [改] 手机端顶栏与图例间距
│   ├── WorkspaceDest.ets        # [改] 顶栏按断点呈现（lg 不变）
│   ├── InputDialog.ets          # [改] 手机端宽度/圆角/按钮热区
│   ├── PcWindowBar.ets          # [保持] 桌面专属，不动
│   └── Navigator.ets            # [保持] 路由单例，不动
├── constants/
│   └── DesignTokens.ets         # [改] 新增移动端间距/尺寸/热区令牌（明暗语义色沿用）
├── store/
│   └── UiStore.ets              # [改] 新增 mobileTab 与断点派生（isMobile/isMedium）
├── utils/
│   └── BreakPoint.ets           # [保持/微调] SM/MD/LG 映射与辅助
└── pages/
    ├── GuideSwiperPage.ets      # [改] 手机端边距/按钮热区
    └── dest/
        ├── SettingsDest.ets     # [改] 统一标题栏/行高/热区
        ├── CharacterDetailDest.ets
        ├── WorldSettingDetailDest.ets
        └── InspirationCreateDest.ets
```

**Structure Decision**: 采用**就地演进**（in-place evolution）而非新建工程层。理由：现有 `shell/` 已按"外壳 → 面板 → 编辑层"分层，三分栏骨架与业务组件均已通过编译与多轮修复；零回归要求 `lg` 路径原样保留，因此不重写、只**新增断点分发与手机端外壳**，并复用全部既有业务组件。数据层（`database/` `repository/` `store/` 业务逻辑）、`editor/flowtext/`、导出导入等**完全不动**。

## Complexity Tracking

| Violation / 复杂度点 | Why Needed | Simpler Alternative Rejected Because |
|----------------------|------------|--------------------------------------|
| sm 与 lg 使用两个 `Navigation` 实例（分支渲染，同一模块级 `nav` 单例） | 手机端需整屏底部页签 + 全屏推入式编辑；lg 需 `Navigation` 在第三栏内 | 单一 Navigation 无法同时满足"底栏固定 + 编辑页全覆盖"与"三栏分栏"；分支渲染同一时刻只挂载一个，路由栈由 `nav` 单例保持 |
| 新增 `MobileShell` 外壳编排层 | 三种断点下的 chrome（标题栏/侧栏/底栏）差异大，集中编排避免散落 if-else | 直接在 `AppShell.build()` 内堆叠三分支会使单文件节点与分支爆炸，且难以独立回归 `lg` |
| md 引入新视觉（侧栏+内容双栏） | 用户明确选择"md 切换双栏"；md 含手机横屏与折叠展开 | 若 md 沿用旧窄三栏，与"渐进式响应"目标割裂；已按"lg 才是不动边界"界定 |

## Research & Decisions

> 依据：本地官方文档库（`devecocli docs`）与项目既有调研 `docs/research/03`、`05`、`02`。

**D-01 手机端导航范式**
- **Decision**: 采用**底部页签导航**（官方"基础底部导航"范式：`Tabs` + `barPosition: End` + `BarMode.Fixed` + 图标加文字自定义页签）。
- **Rationale**: 官方《常见导航样式案例》将底部导航列为常规手机导航；官方《屏幕类型布局场景》指出 ≥840vp 才改侧边导航，即手机端用底栏；Effie 亦以底栏式移动端为参考。
- **Alternatives considered**: 顶部页签（否决：手机端顶部已有标题栏，再叠页签仍拥挤）；侧边抽屉（否决：隐藏核心板块，发现性差）。

**D-02 断点来源**
- **Decision**: 唯一判据为官方系统窗口宽度断点 `UIContext.getWindowWidthBreakpoint()`，刷新挂 `window.on('windowSizeChange')`；沿用现有 `utils/BreakPoint.ets` 的 `SM/MD/LG` 映射（`WIDTH_XS|SM→SM`、`MD→MD`、`LG|XL→LG`）。
- **Rationale**: 官方明文"断点必须由窗口宽度决定，不能由设备类型/方向/折叠状态决定"；系统阈值可能被产品化调整，自写阈值会漂移。
- **Alternatives considered**: `mediaquery.matchMediaSync` 自查阈值（否决：与窗口断点口径可能不一致）；`@Env(SystemProperties.BREAK_POINT)`（暂缓：API 22+ 可用但会改变消费方式，改动面更大）。

**D-03 三档布局映射**
- **Decision**: `sm`→单列+底部页签；`md`→侧栏+内容双栏；`lg`→现有三栏不动。
- **Rationale**: 对应用户选择与官方"分栏 ≥600vp"阈值；`lg` 覆盖真实平板/电脑，满足"平板/电脑不动"。
- **Alternatives considered**: 仅按 sm/lg 两档（否决：手机横屏会退化为单列或误触三栏）；md 沿用旧窄三栏（否决：与渐进目标不一致）。

**D-04 「项目/文库」承载**
- **Decision**: `sm` 下作为**第 4 个底部页签**（项目 / 文稿 / 素材 / 关系图）；`md` 下作为常驻**侧栏**。
- **Rationale**: 用户批准的推荐项即"底栏承载项目/文稿/素材/关系图"；官方页签数允许 2–5 个。
- **Alternatives considered**: 标题栏入口 + 抽屉（否决：核心导航藏在二级入口，发现性差）。

**D-05 md 视觉与"平板不动"边界**
- **Decision**: `md` 套用新的手机端视觉（侧栏+内容双栏）；`lg` 保持重构前视觉。以 `lg`（≥840vp）作为"平板/电脑不动"的边界。
- **Rationale**: 用户明确选择 md 切双栏；md 官方语义含"折叠展开/小平板"，但真实平板/电脑均落 `lg`。
- **Alternatives considered**: md 也保持旧视觉（否决：割裂）；严格把 md 归入"平板不动"（与用户选择冲突）。
- **Risk**: 处于 600–840vp 的小平板/折叠展开用户会看到新视觉；已记录为假设，可在评审调整。

**D-06 颜色令牌策略**
- **Decision**: 保留现有集中式明暗双主题语义令牌（`constants/DesignTokens.ets`），本次仅确保对比度达标与观感统一；**不**迁移为 `$r('sys.color.*')` 资源引用。
- **Rationale**: 迁移会牵动全仓取色点，与"lg 零回归 + 控制改动面"冲突；当前令牌已具备明暗双套。
- **Alternatives considered**: 全量迁移系统色资源（暂缓：收益合规但风险/工作量高）。

**D-07 栅格使用边界**
- **Decision**: 内容区（文稿/素材列表列数、卡片排布、正文缩进）使用 `GridRow/GridCol`；三分栏骨架**不使用**栅格（沿用 `SideBarContainer` + `Navigation` + `layoutWeight`）。
- **Rationale**: 官方明确"三分栏归 SideBarContainer+Navigation"，栅格用于"挪移/缩进/重复"；且 `span` 恒等于 `columns` 会触发 `grid-columns-span` 反例。
- **Alternatives considered**: 用栅格重写外壳（否决：逆官方推荐、语义不符、易触规则）。

**D-08 底部栏实现**
- **Decision**: 用官方 `Tabs`（底部位置 + 固定模式 + 自定义 `tabBar`），栏高参考官方 56vp 并叠加底部系统避让区；`sm` 内容区切换采用状态驱动 + `Tabs` 控制器同步。
- **Rationale**: 官方底部导航即 `Tabs` 方案，选中态/切换动效系统自带，最少自绘。
- **Alternatives considered**: 全自绘 `Row` 页签（否决：需自行处理选中态与无障碍）。

**D-09 复用 vs 重写**
- **Decision**: 复用全部既有业务组件，仅新增外壳编排/页签组件并做共享视觉微调；业务 `@Param`/`@Event` 契约保持不变。
- **Rationale**: 现有组件已多次修复且功能完备；重写风险高、背离"不退化"。
- **Alternatives considered**: 重写手机端全套（否决：工作量与回归风险不可接受）。

**D-10 断点切换的状态保持**
- **Decision**: 断点/手机页签/工作区视图等 UI 状态集中放在 `UiStore`（`@ObservedV2`）；路由栈保留在模块级 `nav` 单例，切换断点不丢路由。
- **Rationale**: 现有架构即以 `app.ui` 为单一真相源；`nav` 单例保证重建后栈仍在。
- **Alternatives considered**: 断点切换时重置路由（否决：会丢失用户当前位置）。

**D-11 编辑器次要操作收纳**
- **Decision**: `sm` 下格式(TXT/MD)/收藏/灵感/撤销重做收纳进"更多"操作菜单（复用现有 `promptAction.showActionMenu` 能力），保存态与字数弱化展示；不新增第三方键盘工具条依赖。
- **Rationale**: 官方"简洁=避免信息过载"；现有 `showActionMenu` 已用于列表行菜单，复用成本低。
- **Alternatives considered**: 自绘键盘上方工具条（暂缓：IME 避让复杂、收益有限）。

**D-12 截图验证方式**
- **Decision**: 每个用户故事在设备上以 `devecocli ui screenshot` 采集 ≥1 张关键界面截图，人工复核并记录；`lg` 需与改造前对照确认零回归。若无设备则降级为构建验证并在交付说明中如实标注。
- **Rationale**: 用户明确要求截图验证并承诺连接设备/模拟器；官方工具链支持。
- **Alternatives considered**: 纯构建验证（否决：不满足用户要求）。

**D-13 首帧断点时序**
- **Decision**: 沿用现有 `AppShell.aboutToAppear` 内取断点 + 绑定 `windowSizeChange` 的做法；断点变化时重算外壳。`windowSizeChange` 回调只做 UI 刷新，不做耗时逻辑。
- **Rationale**: 官方要求布局只监听 `windowSizeChange`；现有实现已满足，避免回归。
- **Alternatives considered**: 在 `windowStatusChange` 里取尺寸（否决：官方指出该回调时尺寸尚未刷新）。

## Data Model

> 本特性为 UI 层，无新增持久化实体；下列为**内存 UI 状态模型**与**布局派生描述**。

### 新增 / 变更的 UI 状态（`UiStore`，`@ObservedV2`）

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `breakPoint` | `BreakPoint`（SM/MD/LG） | LG | 现有字段；由系统断点派生 |
| `mobileTab` | `MobileTab`（PROJECT/DOCS/MATERIALS/GRAPH） | DOCS | **新增**：`sm` 底部页签当前选中项 |
| `showSidebar` | boolean | true | 现有；`sm` 下恒 false（侧栏不以此形态出现） |
| `view` | `EditorViewMode` | EMPTY | 现有；`sm/md` 的素材/关系图页签与之同步 |
| `darkMode` / `paperTheme` | boolean / PaperTheme | — | 现有；不变 |
| `isPcDevice` | boolean | false | 现有；仅用于桌面专属外壳判断 |

**派生（只读，不入库）**：`isMobile`＝`breakPoint===SM`；`isMedium`＝`breakPoint===MD`；`isWide`＝`breakPoint===LG`。

### 布局派生描述（按断点，指导渲染分支）

| 断点 | 外壳 chrome | 侧栏 | navBar / 主页 | 内容区 | 是否影响 lg |
|------|-------------|------|----------------|--------|-------------|
| `sm` | 精简标题栏（≤标题+2 入口） | 不作为常驻；项目页签内呈现 | `MobileShell` 主页：顶部分段内容 + **底部页签栏** | 单列 | 否 |
| `md` | 精简标题栏 | `SideBarContainer` 常驻（项目/文库） | 右侧 `Navigation` 的 navBar | 顶部分段页签（文稿/素材/关系图）+ 双栏 | 否 |
| `lg` | 现有 `appBar`（PC 另加 `PcWindowBar`） | 现有 `SideBarContainer(AUTO)` | 现有 `DocListPane` | 现有 `Navigation` 三栏 | **是（保持不动）** |

### 状态转换

- **断点变化**（`windowSizeChange`→重算）：进入 `sm` 时确保 `mobileTab` 有效、`showSidebar=false`；进入 `md/lg` 时 `showSidebar=true`；进入 `lg` 时若工作区未在栈上按现有逻辑补齐。
- **手机页签切换**（仅 `sm`）：`PROJECT`→侧栏内容；`DOCS`→文稿列表；`MATERIALS/GRAPH`→同步 `app.ui.view` 并渲染对应面板。
- **打开文稿**：任一断点均通过既有 `nav.pushPath({name:'workspace'})`；`sm` 为全屏覆盖，`md` 覆盖右栏。
- **返回/系统返回**：由 `Navigation` 路由栈接管，`sm` 返回落到主页（保留页签选中）。

## Contracts & Interfaces

> 均为组件契约与边界，不含实现。

### 新增组件契约

**MobileShell**（`shell/MobileShell.ets`，`@ComponentV2`）
- 输入：`@Param app: AppStores | null`（沿用全局单例 `app` 的传入方式）。
- 职责：按 `breakPoint` 渲染 `sm` 单列或 `md` 双栏；内嵌 `Navigation(nav)`（显式 `Stack` 模式、隐藏标题/工具条）与 `navDestination(pageMap)`，`pageMap` 覆盖既有路由 `workspace/settings/character/world/inspiration`。
- 输出/事件：无对外回调；交互通过 `app.ui` 与 `nav` 驱动（与现有面板一致）。

**MobileTabBar**（`shell/MobileTabBar.ets`，`@ComponentV2`）
- 输入：`@Param items: TabItem[]`（含 id/label/图标资源），`@Param selected: MobileTab`，`@Param darkMode: boolean`。
- 输出：`@Event onSelect: (tab: MobileTab) => void`。
- 约束：每页签热区高度 ≥ 官方底栏高度（56vp 参考值）；选中态有明确色与图标区分；满足无障碍（`accessibilityText`）。

**MobileSectionTabs**（`shell/MobileSectionTabs.ets`，`@ComponentV2`）
- 输入：`@Param selected: EditorViewMode`（或映射后的分段枚举）、`@Param darkMode: boolean`。
- 输出：`@Event onSelect: (section) => void`（映射到 `app.showEditor/showMaterials/showGraph`）。

### 变更组件契约（保持向后兼容）

| 组件 | 契约变化 | 兼容性 |
|------|----------|--------|
| `AppShell` | 新增断点分发：`lg` 走原 `mainLayout`，`sm/md` 走 `MobileShell` | 不改变既有对外行为 |
| `EditorPane` | 新增/复用"更多"菜单承载次要操作；`sm` 下不渲染旧横向工具条 | 事件仍走 `app.editor.*`；`lg` 保留旧工具条 |
| `WorkspaceDest` | 顶部页签按断点呈现；`sm` 不重复展示页签（由底栏承担） | `lg` 不变 |
| `DocListPane` / `MaterialPane` / `GraphPane` / `ProjectSidebar` | 仅令牌/间距/热区调整 | `@Param`/`@Event` 不变 |
| `UiStore` | 新增 `mobileTab` 与派生只读属性 | 现有字段/方法不变 |
| `BreakPoint` | 若需，新增断点与布局档位辅助 | 现有枚举/函数不变 |

### 既有对外契约（必须保持）

- 路由名常量 `Routes`（`workspace/settings/character/world/inspiration`）与模块级 `nav: NavPathStack` 保持不变。
- `ShellDialog` 枚举与 `app.ui.requestDialog/closeDialog` 不变。
- 编辑器宿主 `TextEditorHost` 的 `@Prop`/事件契约不变（FlowText 集成成果不动）。
- 数据层 `repository`/`database`/业务 `store` 方法签名不变。

### 官方能力引用（设计依据，非代码）

| 能力 | 用途 | 依据 |
|------|------|------|
| `UIContext.getWindowWidthBreakpoint()` | 取窗口宽度断点 | 官方 API 13+ |
| `window.on('windowSizeChange')` | 断点刷新唯一监听 | 官方布局刷新建议 |
| `Tabs(barPosition: End, barMode: Fixed)` + 自定义 `tabBar` | 底部页签 | 官方《常见导航样式案例》 |
| `SideBarContainer`（Embed/AUTO） | md 侧栏 / lg 三栏 | 官方侧边栏组件 |
| `Navigation`（显式 `Stack`/分栏） | sm 全屏路由 / md·lg 内容区 | 官方组件导航 |
| `GridRow/GridCol`（`columns` 按断点、`span/offset` 整数） | 列表列数 / 正文缩进 | 官方栅格布局 |
| `GridRow` 缩进规格（md 8 列取 6 列 offset1；lg 12 列取 8 列 offset2） | 宽屏正文留白 | 官方缩进布局 |

### 与需求的追溯

- US1 ↔ D-01 / D-04 / D-08；US2 ↔ D-11；US3 ↔ D-06 / D-09；US4 ↔ D-02 / D-03 / D-07。
