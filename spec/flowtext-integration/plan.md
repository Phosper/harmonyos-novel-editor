# Implementation Plan: FlowText Integration — 自绘编辑器接入 Weaver

**Input**: Feature specification from `spec/flowtext-integration/spec.md`

## Summary

将 BitFun（潜）完成的 FlowText 自绘文本编辑器（Canvas + ArkGraphics2D 字形级排版 + IME Kit）以源码模块形式集成到 Weaver 项目中，替换 `TextEditorHost.ets` 中的系统 `TextArea` 实现。保持对外契约不变（`TextEditorHost` 的 props/callbacks 签名不改），使 Weaver 正文编辑获得精确点击定位、平滑光标移动、字符增删动画、连贯换行/回行等能力。

## Technical Context

**Language/Version**: ArkTS / SDK 6.1.0(23)  
**Primary Dependencies**: FlowText 自绘编辑器（Canvas + DrawingRenderingContext + IME Kit + @ohos.graphics.text），已在 FlowTextTest 项目通过构建+真机验证  
**Storage**: 不变 — Weaver 现有 RDB（relationalStore）+ Preferences  
**Testing**: 构建验证（`devecocli build`），真机运行  
**Target Platform**: HarmonyOS (OpenHarmony), 手机/平板/2in1  
**Project Type**: 鸿蒙原生 ArkTS 应用（单 entry 模块）  
**Performance Goals**: 正文编辑流畅（FlowText 已实现字形级排版缓存 + 增量重排 + 弹簧动画）  
**Constraints**: 
- FlowText 是 V1 `@Component`，Weaver 应用层是 V2 `@ComponentV2` — 通过现有的 V1 `TextEditorHost` 桥接层处理
- FlowText 使用 px 单位（`DrawingRenderingContext(LengthMetricsUnit.PX)`），内部有 `pxPerVp` 换算
- `TextEditorHost` 的 props/callbacks 签名必须保持向后兼容
**Scale/Scope**: 仅替换正文编辑区，不涉及搜索替换、章节大纲等辅助面板

## Project Structure

### Documentation (this feature)

```text
spec/flowtext-integration/
├── spec.md              # 需求规格 (Phase 1 output)
├── plan.md              # 架构设计 (This file)
└── tasks.md             # 任务分解 (Phase 3 output)
```

### Source Code (修改后的 Weaver 项目结构)

```text
entry/src/main/ets/
├── editor/
│   ├── TextEditorHost.ets          # [修改] 替换 TextArea → CanvasTextEditor
│   └── flowtext/                   # [新增] FlowText 源码拷贝
│       ├── CanvasTextEditor.ets     # 自绘编辑器主组件
│       ├── model/
│       │   ├── TextDocument.ets
│       │   └── EditorTypes.ets
│       ├── theme/
│       │   └── EditorTheme.ets
│       ├── render/
│       │   ├── TextLayoutEngine.ets
│       │   ├── LayoutCache.ets
│       │   └── GlyphRenderer.ets
│       ├── animation/
│       │   ├── GlyphAnimator.ets
│       │   ├── EditorAnimator.ets
│       │   └── AnimationSpec.ets
│       ├── interaction/
│       │   ├── HitTester.ets
│       │   ├── CursorState.ets
│       │   ├── SelectionManager.ets
│       │   └── EditorGesture.ets
│       └── ime/
│           ├── ImeBridge.ets
│           └── PreviewTextManager.ets
└── ...（其余文件不变）
```

**Structure Decision**: FlowText 源码作为内联子目录放入 Weaver 的 `editor/` 下，与 `TextEditorHost.ets` 同级。原因是：
1. BitFun 规划的第一阶段即为「源码模块」集成，后续第二阶段再改为闭源 HAR
2. 内联源码可直接编译，无需额外配置 HAR 模块构建链路
3. Weaver 当前是单 entry 模块，引入 HAR 需要新增模块配置和依赖声明

## Complexity Tracking

N/A — 本项目为单模块内的文件级修改，不涉及跨模块/仓库/语言的架构复杂度。

## Research & Decisions

### R1: FlowText 源码集成方式

- **Decision**: 拷贝 FlowText 源码到 `entry/src/main/ets/editor/flowtext/` 目录
- **Rationale**: BitFun 规划的两阶段策略（源码模块 → 闭源 HAR），第一阶段源码集成最快、无额外构建配置风险。所有 import 路径改为 `'../flowtext/xxx'` 相对引用。
- **Alternatives considered**: 
  - 在 `build-profile.json5` 中添加 `flowtext` 为独立 HAR 模块，用 `oh-package.json5` 声明本地依赖。但需更多配置改动，且与「第一阶段源码模块」规划不一致。
  - 在 Weaver 项目中用 `npm link`/`ohpm link` 方式引用 FlowTextTest 内的模块。但 DevEco 项目中跨项目链接不可靠。

### R2: V1/V2 状态管理边界

- **Decision**: 保持现有 `TextEditorHost` 作为 V1 桥接层，**不**将 FlowText 改为 V2
- **Rationale**: FlowText 当前是 V1 `@Component`，其内部状态管理（`@State buffer`、`@Prop` 等）与 V1 模型绑定。Weaver 应用层（`EditorPane`）使用 V2，通过传基本类型 props（`fontSize/textColor/bgColor/caretColor`）和回调函数（`onTextChange/onCaretChange`）与 V1 桥接。这个模式在当前的 `TextArea` 实现中已运行正常。
- **Alternatives considered**: 将 FlowText 改为 V2 需要大规模重构其内部状态管理，会引入回归风险。

### R3: docId 变化处理策略

- **Decision**: 使用 `CanvasTextEditorController` 替代 `@Watch('onDocChanged')` 驱动
- **Rationale**: FlowText 的 `CanvasTextEditor` 通过 `controller.setText(text)` 加载正文，且通过 `@Prop docId` + `controller` 模式比 `@Watch` 更可控。具体实现：在 `EditorPane` 中维护一个 `controller` 引用，`docId` 变化时调用 `controller.setText(loadText(docId))` 和 `controller.setCaretPosition(loadCaret(docId))`。
- **Alternatives considered**: 通过 `CanvasTextEditor` 的 `@Prop fontSize` 模式传 `docId`。但 FlowText 没有 `docId` prop，且将文档标识作为 prop 会导致不必要的重渲染。

### R4: onTextChange 回调适配

- **Decision**: 在 `EditorPane` 的 `onTextChange` 回调中忽略 FlowText 的 `version` 参数
- **Rationale**: FlowText 的 `onTextChange` 签名是 `(text: string, version: number) => void`，而 Weaver 的 `EditorStore.setContent(text)` 只关心文本内容。在 `EditorPane` 中适配：`onTextChange: (text, version) => { this.app.editor.setContent(text) }`。
- **Alternatives considered**: 修改 FlowText 去掉 version 参数。但 version 对 FlowText 内部的排版缓存管理有用，保留它更合理。

### R5: 主题同步机制

- **Decision**: 当 Weaver 的稿纸主题/深色模式变化时，通过更新 `EditorPane` 传给 `TextEditorHost` 的 props 驱动 FlowText 重绘
- **Rationale**: FlowText 的 `CanvasTextEditor` 通过 `@Prop` 接收 `fontSize/caretColor` 等视觉参数。Weaver 的 `EditorPane` 在 `build()` 中读取 `app.ui.paperTheme` 和 `colors()` 计算这些值。由于 V2 的 `@Param`/`@Trace` 会在属性变化时自动更新子组件，主题切换会自动触发 FlowText 重绘。
- **注意**: FlowText 的 `backgroundColor` 和 `textColor` 不在 props 中，而是在 `EditorTheme` 中。需要在 `aboutToAppear` 或 `onAreaChange` 时同步 `EditorTheme`。

## Data Model

本 feature 不引入新的数据模型。涉及以下现有模型的变化：

### TextEditorHost（改造后的契约）

| 方向 | 名称 | 类型 | 说明 |
|------|------|------|------|
| 输入 | docId | string | 文稿标识（变化时重载正文） |
| 输入 | fontSize | number | 字号（vp） |
| 输入 | lineHeight | number | 行高（vp，= fontSize × lineHeightRatio） |
| 输入 | textColor | string | 正文字色（#RRGGBB） |
| 输入 | bgColor | string | 编辑区背景色（#RRGGBB） |
| 输入 | caretColor | string | 光标色（#RRGGBB） |
| 输入 | placeholder | string | 占位文案 |
| 输入 | loadText | (docId: string) => string | 同步取回正文 |
| 输入 | loadCaret | (docId: string) => number | 同步取回光标位置 |
| 输出 | onTextChange | (text: string) => void | 正文变化回调 |
| 输出 | onCaretChange | (offset: number) => void | 光标变化回调 |
| 输出 | onRequestSave | () => void | 请求保存 |

**变化说明**: 契约签名保持不变。内部实现从 `TextArea` + `TextAreaController` 改为 `CanvasTextEditor` + `CanvasTextEditorController`。

## Contracts & Interfaces

### 内部接口（FlowText → TextEditorHost）

```
CanvasTextEditor Props:
  fontSize: number         ← EditorPane 传入 (paperTheme.fontSize)
  lineHeight: number       ← EditorPane 传入 (paperLineHeightVp)
  lineSpacing: number      ← 固定值 4
  caretColor: string       ← EditorPane 传入 (colors().brand)
  placeholder: string      ← EditorPane 传入

CanvasTextEditorController Methods:
  setText(text: string)    ← docId 变化时加载正文
  getText(): string        ← (暂不使用)
  setCaretPosition(offset) ← docId 变化时恢复光标
  focus()                  ← 编辑器获得焦点
  blur()                   ← 编辑器失去焦点

Callbacks:
  onTextChange(text, version)  → EditorPane.onTextChange(text)
  onCaretChange(offset)        → EditorPane.onCaretChange(offset)
```

### 外部接口（EditorPane → TextEditorHost — 不变）

```
TextEditorHost Props:
  docId/fontSize/lineHeight/textColor/bgColor/caretColor/placeholder

TextEditorHost Callbacks:
  loadText(docId) / loadCaret(docId) / onTextChange(text) / onCaretChange(offset) / onRequestSave()
```

### FlowText 源码导入路径映射（从 TextEditorHost.ets 视角）

| FlowTextTest 原始路径 | Weaver 目标路径 |
|---|---|
| `flowtext/src/main/ets/editor/CanvasTextEditor.ets` | `editor/flowtext/CanvasTextEditor.ets` |
| `flowtext/src/main/ets/editor/model/TextDocument.ets` | `editor/flowtext/model/TextDocument.ets` |
| `flowtext/src/main/ets/editor/model/EditorTypes.ets` | `editor/flowtext/model/EditorTypes.ets` |
| `flowtext/src/main/ets/editor/theme/EditorTheme.ets` | `editor/flowtext/theme/EditorTheme.ets` |
| `flowtext/src/main/ets/editor/render/*` | `editor/flowtext/render/*` |
| `flowtext/src/main/ets/editor/animation/*` | `editor/flowtext/animation/*` |
| `flowtext/src/main/ets/editor/interaction/*` | `editor/flowtext/interaction/*` |
| `flowtext/src/main/ets/editor/ime/*` | `editor/flowtext/ime/*` |
