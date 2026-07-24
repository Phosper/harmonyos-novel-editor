# Implementation Plan: Weavr 核心功能修复（存储 + 按钮 + 导出）

**Input**: Feature specification from `spec/core-functionality-fix/spec.md`

## Summary

为 Weavr PC 端三分栏布局补齐核心功能：将自动保存从 800ms 防抖改为 60 秒定时周期保存并增加错误重试；修复 15+ 个空壳按钮使其产生实际行为（搜索/格式化/查找替换/撤销恢复/写作模式/冲刺/Rail 导航/AI 提示）；新增 TXT/Markdown/JSON 三格式导出能力。

全部改动限制在现有 PC 布局组件和 ViewModel 中，新增 1 个导出服务文件。遵循现有 `pclayout/` 架构模式，不引入新模块。

## Technical Context

**Language/Version**: ArkTS (HarmonyOS API Level 22, SDK 6.0.2)
**Primary Dependencies**: @kit.ArkUI (TextArea caretPosition, onTextSelectionChange, Scroll controller, setInterval/clearInterval), @kit.CoreFileKit (picker.DocumentViewPicker, fileIo), @kit.AbilityKit (UIAbilityContext), 现有项目模块 (@ohos/common, @ohos/editor, @ohos/material)
**Storage**: 现有 SQLite (Weaver.db) 保持不变；新增文件导出到用户选择的公共目录
**Testing**: build_project 编译验证 + 人工交互验证
**Target Platform**: HarmonyOS 6.0.2, phone/tablet/2in1，PC 布局阈值 ≥ 840vp
**Project Type**: 现有 HarmonyOS 多模块项目
**Performance Goals**: 搜索 < 200ms，查找 < 200ms，撤销 < 50ms，保存写入 < 100ms
**Constraints**: 不修改数据库 schema，不引入新模块依赖，纯文本 Markdown 标记方案
**Scale/Scope**: 6 个现有文件修改 + 1 个新文件，~500 行新增代码

## Project Structure

### Documentation (this feature)

```text
spec/core-functionality-fix/
├── spec.md              # 需求规格
└── plan.md              # 本文件
```

### Source Code (repository root)

```text
D:\Project_code\Weaver\
├── products/default/src/main/ets/
│   ├── pclayout/
│   │   ├── WeaverViewModel.ets       # [修改] +autoSaveTimer, +editHistory, +saveState, +sprintTimer
│   │   ├── PcShell.ets              # [修改] Rail 图标 onClick, 传递 search/filter 回调
│   │   ├── PcDocList.ets            # [修改] 搜索实时筛选, 传递搜索文本到 ViewModel
│   │   ├── PcEditorZone.ets         # [修改] 格式化按钮逻辑, 查找替换逻辑, 写作模式实现
│   │   ├── PcAgentPanel.ets         # [修改] 发送/快捷按钮显示占位提示
│   │   └── ExportService.ets        # [新建] 三格式导出服务
│   └── entryability/
│       └── MainAbility.ets          # [修改] +UIAbilityContext 缓存供导出使用
```

**Structure Decision**: 遵循现有项目架构。所有核心逻辑放入 `WeaverViewModel.ets`（已在 PcShell 中实例化且通过 @Observed 驱动 UI），导出服务独立为 `ExportService.ets`（单一职责，可复用）。不创建新模块，不引入 MVVM 重构。

## Complexity Tracking

无 Constitution 违规。改动聚焦于在现有架构内实现缺失功能，不增加架构复杂度。

## Research & Decisions

### 决策 1: 自动保存 → setInterval 定时器

- **Decision**: `WeaverViewModel` 中维护一个 `private autoSaveTimer: number`，在 `init()` 后调用 `setInterval(() => this.performAutoSave(), 60000)`。组件销毁时通过 `PcShell.aboutToDisappear` 回调 `vm.destroy()` 清除定时器。
- **Rationale**: `setInterval` 是 HarmonyOS 全局 API（无需导入），语义清晰。60 秒固定间隔比防抖更适合"写作中持续保存"场景。
- **Alternatives considered**: 周期性 `setTimeout` 链 — 代码更冗长但功能等价，无优势。Worker 线程 — 过度设计，数据库写入本身异步。

### 决策 2: 保存状态机 → SaveState 枚举

- **Decision**: 引入 `enum SaveState { IDLE, SAVING, FAILED }`，UI 根据状态显示不同文本和样式。失败时启动 3 次重试（`setTimeout` 链，间隔 5s）。
- **Rationale**: 清晰的三态模型覆盖所有保存路径。用户可区分"保存中"和"保存失败"，并手动触发重试。
- **Alternatives considered**: Boolean `isSaving` — 无法区分失败状态。Promise chain — 语义过于复杂，定时器链更直观。

### 决策 3: 搜索 → 客户端实时筛选

- **Decision**: `PcDocList` 监听 `searchText` 的 `onChange`，每次变化时调用 `WeaverViewModel.searchDocs(query)` 返回过滤后的 `DocListItem[]`，通过已有的 `docItems` @Prop 显示。
- **Rationale**: 搜索在内存中完成（chapters 数组已加载），无需数据库查询。200ms 内可完成（chapters 数量 < 1000）。
- **Alternatives considered**: 数据库 LIKE 查询 — 需要新增 DAO 方法，且每次输入触发 I/O，无必要。

### 决策 4: 格式化 → 纯字符串 Markdown 标记

- **Decision**: B → `**...**`, I → `*...*`, U → `__...__`, H1-H3 → `#`/`##`/`###` 行首前缀, 引用 → `> ` 行首, 列表 → `- ` 行首。通过 `onTextSelectionChange` 获取光标/选区位置，直接对 `editorContent` 字符串进行 slice + 拼接。
- **Rationale**: TextArea 不支持富文本。Markdown 标记是写作工具的通用方式（Ulysses、iA Writer、Typora 均支持），且后续可扩展 Markdown 预览渲染。
- **Alternatives considered**: RichText / Span 组件 — 需要替换整个编辑器架构，工作量巨大且与 ContentChange 通知的纯文本模型冲突。

### 决策 5: 撤销/恢复 → 字符串栈

- **Decision**: `WeaverViewModel` 中维护 `private undoStack: string[]` 和 `private redoStack: string[]`（最大深度 100）。每次格式化操作前 `undoStack.push(currentContent)`。撤销时 `redoStack.push(currentContent); editorContent = undoStack.pop()`。恢复时反向操作。
- **Rationale**: 最简洁的撤销实现。字符串快照在章节级文本量（< 100KB）下内存开销可忽略。
- **Alternatives considered**: 操作日志（command pattern） — 更精确但实现复杂度高 3-5 倍，对纯文本编辑器性价比低。

### 决策 6: 查找替换 → indexOf + caretPosition

- **Decision**: 使用 `String.indexOf` 在 `editorContent` 中查找所有匹配位置构建 `matchPositions: number[]`。导航时用 `TextArea` 的 `caretPosition` 跳转到匹配位置并选中（通过 TextAreaController）。替换时 `content.slice(0, pos) + replaceText + content.slice(pos + searchLen)`。
- **Rationale**: `indexOf` 是原生方法，性能最佳。`caretPosition` 是 TextArea 的公开 API。
- **Alternatives considered**: RegExp — 需要转义用户输入，增加复杂度和注入风险。

### 决策 7: 导出 → DocumentViewPicker + fileIo

- **Decision**: 新增 `ExportService` 类。`exportTxt(chapter)` 和 `exportMd(chapter)` 打开系统保存对话框，用户选择路径后通过 `fileIo.writeSync` 写入。`exportJson(book, data)` 序列化整个书库为 JSON。
- **Rationale**: HarmonyOS 官方推荐的文件导出模式。用户在系统 UI 中选择保存位置，应用无需存储权限。
- **Alternatives considered**: 直接写入沙箱再分享 — 用户无法控制文件位置，体验差。

### 决策 8: 写作模式 → Scroll + Opacity

- **Decision**: 打字机模式 — 使用 Scroll 控制器的 `scrollEdge` 保持当前行居中。聚焦模式 — 用 `opacity(0.3)` 降低非当前段落。沉浸模式 — 复用已有的 `toggleFullscreen()` 逻辑。
- **Rationale**: 最小化实现。打字机和聚焦是 CSS 级别的视觉效果，不涉及内容变更。沉浸模式已有 toggle 骨架。

## Data Model

### SaveState 枚举

```text
enum SaveState {
  IDLE,    // 已保存，显示"已保存"
  SAVING,  // 保存中，显示"保存中..."
  FAILED   // 失败，显示"保存失败（点击重试）"
}
```

### EditHistory 模型

```text
undoStack: string[]   // 最大 100，新操作 push，撤销 pop → redoStack
redoStack: string[]   // 撤销时 push，新操作时清空
```

### SprintTimer 模型

```text
sprintRemaining: number    // 剩余秒数，初始 1500 (25min)
sprintRunning: boolean     // 是否运行中
sprintTimerId: number      // setInterval ID
```

## Contracts & Interfaces

### 修改: WeaverViewModel — 新增方法和状态

```text
// 自动保存
private autoSaveTimer: number
private saveRetryCount: number
saveState: SaveState
startAutoSave(): void          // 启动 60s 定时器
performAutoSave(): Promise<void>  // 执行保存 + 重试逻辑
retrySave(): void              // 手动重试
destroy(): void                // 清除所有定时器

// 撤销恢复
private undoStack: string[]
private redoStack: string[]
pushUndoState(): void          // 记录当前内容快照
undo(): void                   // 回退
redo(): void                   // 前进

// 搜索
searchDocs(query: string): DocListItem[]  // 返回筛选后的文稿列表

// 格式化（在 PcEditorZone 中通过 onContentChange + 字符串操作实现）

// 冲刺
sprintRemaining: number
sprintRunning: boolean
startSprint(): void            // 启动 25min 倒计时
pauseSprint(): void
resetSprint(): void
```

### 新建: ExportService

**文件**: `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\ExportService.ets`

```text
class ExportService {
  static async exportTxt(context: Context, chapter: ChapterModel): Promise<boolean>
  static async exportMd(context: Context, chapter: ChapterModel): Promise<boolean>
  static async exportJson(context: Context, bookName: string, 
    chapters: ChapterModel[], characters: CharacterModel[],
    worldSettings: WorldSettingModel[], inspirations: InspirationModel[],
    relationships: RelationshipModel[]): Promise<boolean>
}
```

每个方法内部流程:
1. 构造 `picker.DocumentSaveOptions` + `newFileNames`
2. 调用 `new picker.DocumentViewPicker().save(options)` → 获取 URI
3. 内容序列化（TXT: 纯文本, MD: 保留标记, JSON: JSON.stringify）
4. `fileIo.openSync(uri, READ_WRITE)` + `fileIo.writeSync(fd, content)` + `fileIo.closeSync(fd)`
5. 返回 true（成功）或 false（失败/用户取消）

### 修改: PcEditorZone — 格式化按钮逻辑

每个格式化按钮的 onClick 改为调用对应方法，内部执行:

```text
1. 读取 onTextSelectionChange 记录的光标/选区位置
2. 对 editorContent 字符串进行 slice + 拼接插入标记
3. 调用 onContentChange 更新内容到 ViewModel
4. ViewModel.pushUndoState() 记录快照
5. 用 caretPosition 恢复光标到正确位置
```

### 修改: PcEditorZone — 查找替换逻辑

```text
查找按钮 (↑↓):
  1. 如有变化: matchPositions = findAll(editorContent, findInputText)
  2. currentMatchIndex = (currentMatchIndex +/- 1) % matchPositions.length
  3. caretPosition = matchPositions[currentMatchIndex]
  4. 更新计数器 display = "${currentMatchIndex+1}/${matchPositions.length}"

替换按钮:
  1. editorContent = editorContent.slice(0, pos) + replaceInputText + editorContent.slice(pos + searchLen)
  2. 重新计算 matchPositions
  3. pushUndoState()

全部替换:
  1. editorContent = editorContent.replaceAll(findInputText, replaceInputText) (或用 while indexOf循环)
  2. pushUndoState()
  3. 显示"已替换 N 处"
```

### 修改: PcShell — Rail 图标 onClick

```text
折叠 Rail 的 ≡/★/✦ 图标添加 onClick:
  ≡ → onChangeLib('all')
  ★ → onChangeLib('fav')
  ✦ → onChangeLib('insp')
```

### 修改: PcAgentPanel — 占位提示

```text
onSend 替换为:
  1. push user message to messages
  2. push ai message: { role: 'ai', text: 'AI 功能开发中，敬请期待' }

quickAction 替换为:
  push { role: 'ai', text: 'AI 功能开发中，敬请期待' }
```
