# FlowText Sole Editor — 实现说明与迁移说明

> 本文件为 T042 交付物，记录本特性的落地要点与对既有系统的迁移说明。

## 一句话
正文编辑面已由「原生 RichEditor / 自绘 FlowText 二选一」收敛为**唯一自绘实现**（FlowText），
并补齐了打字机居中跟随、字符级动画、编辑正确性（IME 预上屏/提交、选区手柄）与行内格式（粗/斜/标题）。

## 关键落地点
| 能力 | 位置 |
|---|---|
| 打字机居中/滚动跟随 | `editor/flowtext/CanvasTextEditor.ets` 的 `ensureCaretVisible(policy)` / `effectivePolicy()` |
| 字符级动画 | `afterEdit` 调用 `GlyphAnimator.createEditAnimations` + `runGlyphAnimation` |
| IME 预上屏/提交 | `ime/ImeBridge.ets`（`setPreviewText`/`finishTextPreview`，须在 `attach` 前订阅） |
| 选区手柄 | `interaction/SelectionManager.ets`（手柄拖动）+ `render/GlyphRenderer.ets`（`drawHandles`） |
| 行内格式模型 | `model/TextDocument.ets`（runs：非重叠、按偏移排序、随编辑平移/收缩） |
| 格式排版 | `render/TextLayoutEngine.ets`（按 run `pushStyle`；标题放大、粗 W700、斜 ITALIC） |
| 格式命令 | `CanvasTextEditor.toggleInlineStyle/toggleParagraphStyle`（经控制器 + `EditorPane` 工具栏） |
| 格式持久化 | `chapters.format_runs` 列（`DatabaseHelper.ensureColumns` 幂等加列）+ `FormatCodec` 紧凑编解码 |
| 导出格式 | `utils/ExportService.ets`（`sourceOf/applyMarkdown`，行内 `**`/`*` 与标题 `#`） |
| 滚动即沉浸 | `store/UiStore.ets` `noteScroll` + `EditorPane` 接入 |
| 失焦落库 | `CanvasTextEditor.releaseEditorFocus` → `onRequestSave` → `EditorStore.flushActive` |

## 迁移说明（向后兼容）
- 数据库：`chapters` 表新增 `format_runs TEXT NOT NULL DEFAULT ''`，由**幂等 `ensureColumns()`** 对旧库自动 `ALTER`，**无需数据迁移**。
- 旧文稿（无格式边车，空串）按**纯文本**打开与编辑，保存后按需写入。
- 移除项：`RichTextEditorHost.ets`（已删除）、`EditorEngine` 枚举、`UiStore.editorEngine/setEditorEngine`、设置页「正文编辑引擎」项、Preferences `engine` 键的读写。
- 契约：`TextEditorHost` 对外 props/callbacks 保持兼容，新增项均为可选（`typewriter`/`scrollPolicy`/`loadFormat`/`onSelectionChange`/`onFormatChange`/`onScrollState`/`onControllerReady`）。

## 诊断
- `CanvasTextEditor` 保留 `DIAG_ENABLED`（`FlowTextDiag`）；本特性新增量化标签：`scroll`（滚动偏移/居中）、`perf relayout=…ms`（重排耗时，供 5 万字性能核对）。
