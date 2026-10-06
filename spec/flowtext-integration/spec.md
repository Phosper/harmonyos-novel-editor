# Feature Specification: FlowText Integration — 将自绘编辑器接入 Weaver

**Created**: 2026-09-29  
**Status**: Draft  
**Input**: Weaver 项目现有 `editor/TextEditorHost.ets` 使用系统 `TextArea`，BitFun（潜）已完成 FlowText 自绘文本编辑器的可用性回归修复（FlowTextTest 项目，18 任务全部完成并真机验证通过）。现在需要将 FlowText 接入 Weaver，替换 TextArea 实现。

## Overview

Weaver 是一款鸿蒙原生小说编辑器，其正文编辑面当前使用系统 `TextArea` 组件，存在以下局限：
- 缺少连贯的行间/字间动画（换行/回行/光标移动均为瞬时跳变）
- 无法精细控制字形级排版（行距、基线、排版缓存）
- 难以实现「流畅优雅」的编辑体验

FlowText 是 BitFun（潜）自研的 Canvas + ArkGraphics2D 字形级全自绘文本编辑器组件包，已完成可用性回归修复（点击定位精确、光标平滑移动、字符增删动画连贯、IME/中文输入链路正常）。根据 BitFun 的规划，FlowText 将以「源码模块 → 闭源 HAR」两阶段引入 Weaver。

本轮为第一阶段（源码模块集成）：将 FlowText 的源码作为内联模块放入 Weaver 项目，替换 `TextEditorHost.ets` 中的 `TextArea` 实现，使 Weaver 的正文编辑获得 FlowText 的全部交互能力。

## User Scenarios & Testing

### User Story 1 — 正文编辑使用自绘编辑器 (Priority: P1)

用户在 Weaver 中打开/新建一篇文稿，编辑器使用 FlowText 自绘组件呈现正文，支持精确点击定位光标、平滑光标移动、字符插入/删除动画、换行/回行连贯过渡。

**Why this priority**: 这是集成的核心目标，替换 TextArea 后用户应无感知地获得更好的编辑体验，而非看到退化或崩溃。

**Independent Test**: 在 Weaver 中新建文稿、输入中英文混合文本、点击不同位置、增删字符，验证编辑体验与 FlowTextTest 一致。

**Acceptance Scenarios**:

1. **Given** 用户打开 Weaver 并新建一篇文稿，**When** 用户在编辑区点击任意可见位置，**Then** 光标精确落在最近字形边界，无跳飞。
2. **Given** 编辑区有文本，**When** 用户连续输入 30+ 字符，**Then** 字符以入场动画呈现，已有文本位置稳定不跳，光标停在插入点之后。
3. **Given** 编辑区有文本，**When** 用户连续删除字符，**Then** 被删字符收缩淡出，已有文本不跳，光标位置正确。
4. **Given** 编辑区有多行文本，**When** 用户在行尾输入触发折行，**Then** 折行字形出现在下一行正确位置，无瞬间跳变。

---

### User Story 2 — 集成不影响已有功能 (Priority: P1)

所有 Weaver 现有编辑相关功能（新建/打开/关闭文稿、收藏/灵感/废纸篓、自动保存、字数统计、撤销/重做、导出/导入）在替换编辑器后正常工作，不退化。

**Why this priority**: 集成不能破坏已有功能，这是上线的底线。

**Independent Test**: 逐一执行 Weaver 已有的文稿操作流程，对比替换前后的行为一致性。

**Acceptance Scenarios**:

1. **Given** 用户处于编辑态，**When** 切到其他文稿再切回，**Then** 正文与光标位置正确恢复。
2. **Given** 用户编辑文稿后，**When** 关闭标签页，**Then** 自动保存生效（脏标记清除，字数更新）。
3. **Given** 编辑器显示正文，**When** 切换深色/浅色模式，**Then** 编辑区颜色与稿纸主题同步更新。
4. **Given** 用户正在编辑，**When** 按下保存/切走/后台，**Then** 正文内容正确落库，重新打开内容一致。

---

### User Story 3 — 多稿纸主题适配 (Priority: P2)

FlowText 编辑器的视觉样式跟随 Weaver 的稿纸主题系统（素白/青笺/茶墨/夜读），包括背景色、正文字色、光标颜色等。

**Why this priority**: 稿纸主题是 Weaver 的设计卖点之一，自绘编辑器必须正确呈现用户选择的主题。

**Independent Test**: 切换四种稿纸主题，观察编辑区的背景色、文字色、光标色是否正确变化。

**Acceptance Scenarios**:

1. **Given** 编辑器打开并显示正文，**When** 用户在设置中选择不同稿纸主题，**Then** 编辑区背景色、文字色、光标色立即同步。
2. **Given** 用户使用夜读主题，**When** 编辑正文，**Then** 背景为深色、文字为浅色，视觉舒适。

---

### Edge Cases

- FlowText 的 `onTextChange(text, version)` 回调带 `version` 参数，Weaver 的 `EditorStore.setContent(text)` 只接受 `text` —— 需正确适配。
- FlowText 使用 px 单位（`DrawingRenderingContext(LengthMetricsUnit.PX)`），Weaver 使用 vp —— FlowText 内部有 `pxPerVp` 换算，集成时需确保初始化正确。
- Weaver 的行高公式：`paperLineHeightVp = round(fontSize * lineHeightRatio)`，直接传给 FlowText 的 `lineHeight` prop。
- `docId` 变化时 FlowText 需要重新加载文本（`controller.setText(...)`），而非如 TextArea 那样用 `@Prop` + `@Watch` 驱动。

## Requirements

### Functional Requirements

- **FR-001**: Weaver MUST 将 FlowText 源码（`flowtext/src/main/ets/editor/`）以源码模块形式集成到 Weaver 项目中，使 `CanvasTextEditor` 组件可以在 Weaver 中 import 和使用。
- **FR-002**: System MUST 在 `TextEditorHost.ets` 中将系统 `TextArea` 替换为 `CanvasTextEditor`，保持对外契约不变（`docId/fontSize/lineHeight/textColor/bgColor/caretColor/placeholder` 输入 + `onTextChange/onCaretChange/onRequestSave` 输出）。
- **FR-003**: System MUST 正确映射 FlowText 的 `onTextChange(text, version)` 回调到 Weaver 的 `onTextChange(text)`（忽略 version 参数）。
- **FR-004**: System MUST 处理 `docId` 变化时通过 `CanvasTextEditorController.setText()` 加载新文稿正文，通过 `setCaretPosition()` 恢复光标位置。
- **FR-005**: System MUST 在 `aboutToAppear`/`aboutToDisappear` 生命周期中正确初始化/销毁 FlowText 资源（IME attach/detach、动画停止等）。
- **FR-006**: System MUST 保证 FlowText 的视觉参数与 Weaver 稿纸主题联动：背景色 → `backgroundColor`、正文字色 → `textColor`、光标色 → `caretColor`、字号 → `fontSize`。
- **FR-007**: System MUST 确保集成后 Weaver 的构建通过（`devecocli build`），无新增编译错误。
- **FR-008**: System MUST 保证所有已有编辑功能（新建/打开/关闭/自动保存/撤销/格式化切换/收藏/灵感/导出/导入）不退化。

### Key Entities

- **CanvasTextEditor**: FlowText 的核心组件（V1 `@Component`），基于 Canvas + IME Kit 的自绘编辑器。属性：`fontSize/lineHeight/lineSpacing/caretColor/placeholder/controller`。回调：`onTextChange(text, version)/onCaretChange(offset)`。
- **CanvasTextEditorController**: FlowText 的控制接口，用于 `setText/getText/setCaretPosition/focus/blur` 等外部操作。
- **EditorTheme**: FlowText 的主题配置类，含 padding/textColor/backgroundColor/caretColor/selectionColor 等视觉参数。
- **TextEditorHost**: Weaver 现有的编辑宿主组件（V1 `@Component`），作为 V2 应用层（EditorPane）与 V1 自绘编辑器之间的桥接层。集成后内部实现从 `TextArea` 替换为 `CanvasTextEditor`。
- **EditorStore**: Weaver 的编辑状态 Store，管理 `openDocs/activeId/draft/saveState/undoStack`。外部通过 `setContent(text)/setCaret(offset)` 接收编辑器事件。

## Success Criteria

### Measurable Outcomes

- **SC-001**: 集成后 Weaver 编译通过（`devecocli build` ERROR:0），仅保留已有 API 废弃 WARN。
- **SC-002**: 新建文稿后可在编辑区输入/删除文本，内容变化实时反映在字数统计与自动保存流程中。
- **SC-003**: 切稿纸主题（素白/青笺/茶墨/夜读）后编辑器视觉立即更新，无手动刷新操作。
- **SC-004**: 打开多篇文稿并切换，每篇的正文与光标位置正确恢复，无内容混串或丢失。
- **SC-005**: 导出/导入功能在替换后正常工作，导出的 TXT/MD/HTML/JSON 内容与编辑器正文一致。

## Assumptions

- FlowText 源码位于 `/storage/Users/currentUser/Documents/DevEcoStudioProjects/FlowTextTest/flowtext/src/main/ets/editor/`，将复制到 Weaver 的 `entry/src/main/ets/editor/` 下作为内联源码。
- Weaver 的构建系统使用单 entry 模块，FlowText 源码放在 `entry/src/main/ets/editor/flowtext/` 子目录中。
- FlowText 的所有任务（T001-T018）已在 FlowTextTest 项目中通过构建 + 真机验证，其组件代码本身稳定可用。
- 集成后 FlowText 的 `DIAG_ENABLED` 诊断开关保持 `true`（方便后续真机排查），后续可改为编译时常量控制。
- 当前集成只覆盖正文编辑区，不包括搜索替换、章节大纲等辅助面板。

## Open Questions

- [NEEDS CLARIFICATION: FlowText 的 `onCaretChange(offset)` 回调是否足够覆盖 Weaver 的所有光标相关需求？Weaver 当前只使用 `setCaret(offset)`，但未来可能需要选区信息。]
- [NEEDS CLARIFICATION: FlowText 的滚动处理 — Weaver 当前没有显式滚动管理（TextArea 自动处理），FlowText 的 `scrollY` 管理是否需要 Weaver 侧额外处理？]
