# Implementation Plan: FlowText Sole Editor — 以全自绘编辑器作为唯一正文编辑面

**Input**: Feature specification from `spec/flowtext-sole-editor/spec.md`

## Summary

将已有自绘编辑器 FlowText（Canvas + @ohos.graphics.text 字形级排版 + IME Kit）由"可选动画引擎"提升为 Weaver **唯一**正文编辑面，并补齐四类能力：(1) 编辑正确性收口（IME 预上屏/提交、选区手柄、命中）；(2) 打字机"当前段垂直居中/滚动跟随"（需要**程序化滚动**能力，原型缺失）；(3) **接通字符级动画**（原型仅有数据通路、未接线）；(4) 引入**行内格式**（粗体/斜体/标题）及其持久化。完成后移除原生引擎与切换入口。

范围按已确认规格：正文＝纯文本 + 基础行内格式（**不含图片内联**）；单篇 ≤ 5 万字；打字机默认关闭。

## Technical Context

**Language/Version**: ArkTS / SDK 6.1.0(23)（`build-profile.json5` targetSdkVersion=compatibleSdkVersion=6.1.0(23)）
**Primary Dependencies**: 自绘编辑器 FlowText（Canvas + `DrawingRenderingContext` + `@ohos.graphics.text` typeset + IME Kit），已内联于 `entry/src/main/ets/editor/flowtext/`
**Storage**: 既有 RDB（`relationalStore`）+ Preferences；本特性需新增"行内格式标注"的持久化（见 R8）
**Testing**: `devecocli build` 构建验证 + 真机 UI 自动化（`devecocli ui layout/click/text`）+ 日志（`devecocli log`）
**Target Platform**: HarmonyOS (OpenHarmony)，手机优先（平板/2in1 后续）
**Project Type**: 鸿蒙原生 ArkTS 应用（单 entry 模块）
**Performance Goals**: 单篇 5 万字下输入响应 < 50ms、滚动 ≥ 50fps；字符动画不引起已有文本抖动
**Constraints**:
- FlowText 为 V1 `@Component`，应用层为 V2 `@ComponentV2`，经 V1 `TextEditorHost` 桥接（基本类型 props + 回调）
- FlowText 使用 px 内部绘制、对纹 vp（`pxPerVp` 换算）
- `TextEditorHost` 对外 props/callbacks 契约须保持向后兼容
- 无原生视觉，UI 验证以布局树/日志为准

**Scale/Scope**: 正文编辑区单点改造（含数据/持久化/渲染/交互/动画），不含搜索替换、大纲等辅助面板；涉及 `editor/`、`store/`、`shell/EditorPane.ets`、`pages/dest/SettingsDest.ets`、资源与数据库访问层。

## Project Structure

### Documentation (this feature)

```text
/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver/spec/flowtext-sole-editor/
├── spec.md              # 需求规格（Phase 1）
├── plan.md              # 架构设计（本文件）
└── tasks.md             # 任务分解（Phase 3，待生成）
```

### Source Code (repository root)

```text
/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver/entry/src/main/ets/
├── editor/
│   ├── TextEditorHost.ets              # [核心改动] V1 桥接层：契约扩展（打字机/滚动/格式/选择）+ 事件回传
│   ├── RichTextEditorHost.ets          # [退役] 原生引擎宿主，最终从渲染路径移除
│   └── flowtext/                       # 自绘编辑器源码（唯一实现）
│       ├── CanvasTextEditor.ets        # [改动] 接线动画、程序化滚动、格式命令、选择手柄、滚动事件
│       ├── model/
│       │   ├── TextDocument.ets        # [改动] 引入行内格式标注（runs）与格式相关编辑
│       │   ├── EditorTypes.ets         # [改动] 增加 FormatRun/StyleKind/ScrollPolicy 等值类型
│       │   └── GraphemeUtil.ets        # [不变]
│       ├── render/
│       │   ├── TextLayoutEngine.ets    # [改动] 支持按 run 的差异化 TextStyle（粗/斜/标题）
│       │   ├── LayoutCache.ets         # [改动] 缓存键纳入格式版本
│       │   └── GlyphRenderer.ets       # [改动] 格式渲染 + 选区手柄绘制
│       ├── animation/
│       │   ├── GlyphAnimator.ets       # [接线] 字符入场/消退/行位移动画（已有逻辑，未调用）
│       │   ├── EditorAnimator.ets      # [不变]
│       │   └── AnimationSpec.ets       # [扩展] 滚动/居中缓动参数
│       ├── interaction/
│       │   ├── HitTester.ets           # [不变/微调]
│       │   ├── CursorState.ets         # [不变]
│       │   ├── SelectionManager.ets    # [改动] 选区手柄锚点与拖动
│       │   └── EditorGesture.ets       # [改动] 手柄命中与拖动
│       └── ime/
│           ├── ImeBridge.ets           # [改动] 接通 setPreviewText / onPreviewText
│           ├── KeyboardHandler.ets     # [扩展] 格式快捷键（Ctrl/⌘+B/I 等，按需）
│           └── PreviewTextManager.ets  # [接线] commit 调用点
├── shell/EditorPane.ets                # [改动] 单引擎选择分支收敛；传打字机/滚动/格式；接收选择/滚动事件
├── pages/dest/SettingsDest.ets         # [改动] 移除"编辑引擎"切换项；新增打字机开关入口（如需）
├── store/
│   ├── EditorStore.ets                 # [改动] 行内格式随正文一并管理/撤销重做/落库
│   ├── StoreModels.ets                 # [改动] OpenDoc 增加格式标注字段
│   └── AppStores.ets                   # [改动] 存取格式化正文
├── constants/DesignTokens.ets          # [改动] 移除/保留 EditorEngine 枚举（收敛后废弃）
└── utils/ExportService.ets / MarkdownRenderer.ets  # [评估] 导出是否需反映行内格式

# 持久化与数据访问（具体文件在 store/database 层，Phase 3 定位）
```

**Structure Decision**: 继续采用"FlowText 源码内联 + V1 `TextEditorHost` 桥接"的既有组织；所有增强都落在 `editor/flowtext/` 现有模块内，避免新增架构层级。行内格式的持久化沿用既有文稿存储通道，以"格式标注边车"形式增量扩展（见 R8），不改动既有正文文本字段。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 在自绘引擎内新增"行内格式"渲染与持久化 | 规格将行内格式列为必须（P1） | 复用原生富文本组件已被否（其滚动/动画能力边界，见 `harmonyos-richeditor-scroll-animation-boundary`） |
| 引入"格式标注"数据模型（旧数据无此字段） | 需要保存粗/斜/标题 | 仅存纯文本无法表达格式；用 Markdown 标记会污染正文字符串且与命中/选区耦合 |
| 单引擎收敛会移除原生路径 | 规格要求真单引擎、消除双维护 | 保留双引擎会造成模式切换与体验分裂，且规格已明确移除 |

## Research & Decisions

### R1: 单引擎收敛方式

- **Decision**: 将 `TextEditorHost`（FlowText）作为唯一渲染路径；`RichTextEditorHost` 从 `EditorPane` 渲染分支中移除；`EditorEngine` 枚举、`UiStore.editorEngine`/`setEditorEngine`、Preferences 中的 `engine` 键、`SettingsDest` 的切换项一并废弃。
- **Rationale**: 规格 US7/FR-001 要求真单引擎；移除可消除模式分裂与双份维护。
- **Alternatives considered**: 保留原生作"隐藏回退"（被否：仍属双维护，且规格已定"移除"）。

### R2: 打字机居中的实现路径（核心风险项）

- **Decision**: 在 FlowText 内部实现**程序化滚动**（`scrollY` 已存在且仅由触摸拖动更新），新增"确保光标可见/居中"策略；`TextEditorHost` 向外暴露打字机开合与滚动策略；由 `UiStore.typewriter`（默认关）驱动。
- **Rationale**: 原型**没有**任何把 `scrollY` 设为"使当前段居中"的方法（调研结论：无 scrollTo/居中能力）；这是"打字机"落地的前提。
- **Alternatives considered**:
  - 用原生 RichEditor 的 `getCaretRect` 驱动外层 Scroll → 已 spike 证伪（RichEditor 不离交滚动权）。
  - 只在输入时隐藏 chrome、不做居中 → 不满足 US1 验收（居中偏差 ±10%）。

### R3: 字符级动画接线（原型有代码、无调用）

- **Decision**: 将 `GlyphAnimator.createEditAnimations` 接入编辑提交路径（原 `afterEdit`/`relayout` 处仅清空动画），并在渲染侧启用 `GlyphRenderer.drawAnimatedGlyph`；补齐"行位移过渡"。
- **Rationale**: 调研显示 `runGlyphAnimation` 无调用点、`GlyphAnimator` import 未使用、`oldLines` 只写不读 —— 动画代码齐备但未通电，属最低成本高收益项。
- **Alternatives considered**: 另起动画框架（被否：重复造轮子，且现有动画器已覆盖需求）。

### R4: 选区手柄

- **Decision**: 在 `SelectionManager` 维护手柄锚点（起点/终点），`GlyphRenderer` 绘制手柄，`EditorGesture` 增加手柄命中与拖动分支。
- **Rationale**: 规格 US2 验收要求"拖动选区手柄连续更新"；原型仅有文本拖动选择与长按选词，无手柄。
- **Alternatives considered**: 仅长按选词（不满足验收）。

### R5: IME 预上屏与提交

- **Decision**: 在 `ImeBridge.registerListeners` 中订阅 `setPreviewText`/预上屏相关回调，接通 `PreviewTextManager.update`；并在提交时调用其 `commit`。
- **Rationale**: 调研显示 `onPreviewText` 从未触发、`commit` 无调用点；预上屏呈现与提交正确性是 US2 的硬性验收。
- **Alternatives considered**: 依赖组合插入直接落字（会破坏"候选未提交不写入正文"的验收）。

### R6: 行内格式的渲染模型

- **Decision**: 在 `TextDocument` 引入**非重叠、按偏移排序的格式标注（runs）**；`TextLayoutEngine` 按 run 构造差异化 `TextStyle`（粗体/斜体/标题字号/字重）；`LayoutCache` 的键纳入"格式版本"，以保证格式变更后重排。
- **Rationale**: 格式是"范围属性"，必须与字形/命中/选区对齐；以 run 表示最直接，且与现有按行/按 run 的排版天然吻合。
- **Alternatives considered**:
  - 在正文字符串内嵌 Markdown 标记：污染文本、影响字数/命中/光标（否）。
  - 逐字形存样式：冗余、合并开销大（否）。

### R7: 格式的命令与交互

- **Decision**: 提供"对当前选区施加/取消格式"的命令（`toggleInlineStyle`）与"段落样式（标题）"命令；交互入口沿用现有工具栏/菜单（不新增页面），可选用物理键盘快捷键。
- **Rationale**: 规格 US3 要求可设置粗/斜/标题；复用现有工具栏/更多菜单符合既有 UI 结构。
- **Alternatives considered**: 新增浮动格式菜单（后续可加，非必需）。

### R8: 行内格式的持久化

- **Decision**: 以**格式标注边车**随文稿存储（与既有正文字段并存、向后兼容）：旧文稿无标注即等价的纯文本；打开时若无标注则按纯文本处理，保存时按需写入。
- **Rationale**: 不改动既有正文文本字段与数据模型主干，历史数据零迁移即可打开；格式以"偏移区间 + 样式"表达，天然与文本解耦。
- **Alternatives considered**:
  - 改为富文档格式（增量存储）：改动面过大、迁移风险高（否）。
  - 在正文内联标记：与 R6 同因被否。

### R9: 5 万字性能策略

- **Decision**: 沿用并强化 `LayoutCache` 的"按需/增量布局"；渲染仅覆盖可见视口；格式变更仅失效受影响区段；避免整篇 typeset 与全量重绘。
- **Rationale**: 自绘方案的最大性能风险是"整篇排版"；原型已有版本化懒加载布局缓存，应以其为基础扩展。
- **Alternatives considered**: 一次性全量布局（5 万字下会卡顿，否）。

### R10: 滚动即隐藏 chrome

- **Decision**: FlowText 在滚动时产生滚动状态，经 `TextEditorHost` 回调上抛给 `EditorPane`，复用既有 `UiStore.immersive` 机制实现顶栏/工具条显隐。
- **Rationale**: 现有沉浸机制（`UiStore.immersive` + `noteTyping`）已存在；自绘引擎天然可上报滚动，无需系统滚动事件。
- **Alternatives considered**: 依赖系统滚动事件（原生方案才有的问题；自绘无此约束）。

### R11: 分期交付（降低一次性风险）

- **Decision**: 分三期：**A** 正确性收口（IME 预览/提交、选区手柄、命中）+ 程序化滚动/打字机居中 + 字符动画接线 + 滚动隐藏 chrome；**B** 行内格式（模型/渲染/命令/持久化）；**C** 单引擎收敛与全量回归。
- **Rationale**: 规格已建议分期；先交付"可日用正确性 + 招牌打字机/动画"，再叠加格式，最后收敛，风险逐段收敛、每期可构建可验证。
- **Alternatives considered**: 一次性全部实现（回归面过大、定位困难，否）。

### R12: 验证方式

- **Decision**: 每期以 `devecocli build` 通过 + 真机 UI 自动化（`ui layout/click/text`、`log`）验证；保留并善用 `DIAG_ENABLED` 诊断日志输出滚动/居中/动画/格式关键量；对无法用布局树断言的视觉项（动画、居中偏移）以日志量化代替。
- **Rationale**: 当前模型无原生视觉，需以可量化信号验证。
- **Alternatives considered**: 仅人工肉眼验收（不可复现，否）。

## Data Model

### 文档与格式模型（编辑器内部）

| 概念 | 含义 | 关键属性 |
|------|------|----------|
| 正文文本 | 单一字符串 | 字符序列（含换行） |
| 光标/选区 | 偏移与区间 | `caretOffset`、`selection{start,end}` |
| 格式标注（Run） | 施加于文本区间的行内格式 | `start`、`end`、`style`（bold/italic）、`paragraphStyle`（heading 等级/正文） |
| 格式集合 | 非重叠、按 start 排序、相邻同式可合并 | 列表，随编辑增删自动维护不变式 |
| 版本号 | 正文/格式的变更代数 | `version`（正文）、`formatVersion`（格式）；用于布局缓存失效与撤销 |
| 视图状态 | 滚动与视口 | `scrollY`、`viewport`、`caretRect` |

**不变式**：格式区间与文本偏移一致（插入/删除时同步平移/裁剪）；格式区间不交叉；段落样式以段为单位（不跨段合并冲突）。

### 持久化模型（对既有存储的增量）

| 项 | 说明 |
|----|------|
| 既有正文字段 | **不变**（纯文本） |
| 新增格式边车 | 每条文稿可选的"格式标注集合"序列化（偏移区间 + 样式）；缺失即纯文本 |
| 向后兼容 | 旧文稿无格式边车 → 以纯文本打开；保存时按需写入；导入/导出按现有格式策略处理 |
| 撤销/重做历史 | 历史条目需同时覆盖正文与格式（当前历史仅存正文快照，需扩展） |

### 编辑状态契约（Store 侧，保持对外兼容）

| 方向 | 名称 | 说明 |
|------|------|------|
| 状态 | `openDocs/activeId/contentRev/caret/wordCount/saveState/format` | 既有字段语义不变 |
| 方法 | `setContent/setCaret/flushActive/undo/redo/applyExternalContent/openChapter/activateChapter/closeTab` | 既有签名不变 |
| 扩展 | 格式随正文一起管理：内容回灌需携带格式；格式变更推高 `contentRev` 以触发布局失效 | 新增但保持既有调用方兼容 |

## Contracts & Interfaces

### 对外契约（TextEditorHost → EditorPane，保持兼容）

| 方向 | 名称 | 类型/签名 | 说明 |
|------|------|-----------|------|
| 输入 | docId | string | 文稿标识（变化即重载） |
| 输入 | contentRev | number | 整体替换版本号（撤销/重做/回灌） |
| 输入 | fontSize / lineHeight / textColor / bgColor / caretColor / placeholder | number/string | 视觉参数 |
| 输入（新增） | typewriter | boolean | 打字机模式（默认 false） |
| 输入（新增） | scrollPolicy | ScrollPolicy | 滚动策略（普通 / 居中跟随） |
| 输入 | loadText(docId): string | 函数 | 取回正文 |
| 输入 | loadCaret(docId): number | 函数 | 取回光标 |
| 输入（新增） | loadFormat(docId): FormatRun[] | 函数 | 取回格式标注 |
| 输出 | onTextChange(text) | 回调 | 正文变化 |
| 输出 | onCaretChange(offset) | 回调 | 光标变化 |
| 输出（新增） | onSelectionChange(range) | 回调 | 选区变化（用于工具栏态） |
| 输出（新增） | onFormatChange(runs) | 回调 | 格式变化（随内容落库） |
| 输出（新增） | onScrollState(state) | 回调 | 滚动方向/状态（驱动沉浸显隐） |
| 输出 | onRequestSave() / onUndo() / onRedo() | 回调 | 既有语义不变（须修复当前 `onRequestSave` 未触发的问题） |

### 自绘编辑器契约（CanvasTextEditor / Controller，扩展）

**Component props（含既有 + 新增）**：`fontSize`、`lineHeight`、`lineSpacing`、`textColor`、`bgColor`、`caretColor`、`placeholder`、`controller`；**新增** `typewriter`、`scrollPolicy`、`runs`（格式标注）。

**Component 回调**：`onTextChange(text, version)`、`onCaretChange(offset)`、`onUndo()`、`onRedo()`；**新增** `onSelectionChange(start, end)`、`onFormatChange(runs)`、`onScrollState(state)`。

**Controller 公开方法**：既有 `bind/setText/getText/setCaretPosition/focus/blur/insertTextAtCaret/deleteLeftAtCaret`；**新增** `setRuns(runs)`、`getRuns()`、`toggleInlineStyle(kind, range)`、`toggleParagraphStyle(level, range)`、`ensureCaretVisible(policy)`、`scrollBy(deltaVp)`。

### 滚动策略（ScrollPolicy）

| 值 | 语义 |
|----|------|
| NORMAL | 常规：仅在光标越出视口时才滚动使其可见 |
| CENTER | 打字机：使当前段中心对齐视口中心（打字机开启时） |

### 格式样式（StyleKind）

| 值 | 语义 |
|----|------|
| BOLD | 行内加粗 |
| ITALIC | 行内斜体 |
| HEADING_1 / HEADING_2 / HEADING_3 | 段落标题（按段落生效） |
| BODY | 正文段落（默认） |

**契约兼容性说明**：`TextEditorHost` 的既有 props/callbacks 签名保持不变，新增项均为可选（缺省即旧行为），以保证 `EditorPane` 与 Store 的渐进式改造。
