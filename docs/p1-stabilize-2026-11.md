+# P1 止血记录（2026-11）
+
+- 起点：`v0.9-local`（`c1780dd`）+ P0 基线工具（`e0b9260`）
+- 本阶段只修**会造成数据丢失或功能明显失效**的问题，不碰架构、不搬目录、不建包。
+- 未测项集中在设备侧，见文末；本地结论均为 `./tools/verify.sh` 实测。
+
+## 1. 改了什么
+
+| 编号 | 问题 | 修法 | 位置 |
+| --- | --- | --- | --- |
+| D-01 | 9 处 `@Monitor` 以模块级单例 `app.*` 为根，编译器告警且运行期很可能不触发（顶栏「查找」点了没反应） | 改为 `@Local watch: X = app.x` + `@Monitor('watch.field')`（仓库内 `AppShell` 的既有写法）；`CanvasPane` 里监听普通接口对象 `params.boardId` 的那条直接删除（切板本就由 `CanvasDest` 调 store） | `EditorPane`、`EditorTools`、`CanvasPane`、`AppShell`、`DesktopTitleBar` |
+| D-02 | 生成/覆盖初稿直接 `chapterRepo.saveDraft` 写库，绕过打开中的内存草稿 → 自动保存把旧稿写回（R1） | 新增 `EditorStore.applyGeneratedContent(docId, content, runsJson)`：一次可撤销编辑 + `contentRev++` 回灌画布；`CanvasPane` 改为「先 openChapter → 命令写入 → flushDoc」，撤销条也走同一条命令 | [EditorStore.ets](entry/src/main/ets/store/EditorStore.ets)、[CanvasPane.ets](entry/src/main/ets/shell/CanvasPane.ets) |
+| D-04 | 跳回原文直接用旧偏移，不核对；跨文稿用固定 `setTimeout(360)` 猜编辑器就绪（R3） | 新增纯函数 `SourceAnchorResolver`（EXACT / RELOCATED / AMBIGUOUS / MISSING）；跳源改为**条件轮询**等待编辑器（控制器已绑定且文稿匹配，上限约 2 秒），命中后选中摘录区间；找不到就明说 | [SourceAnchor.ets](entry/src/main/ets/utils/SourceAnchor.ets)、[EvidenceDrawer.ets](entry/src/main/ets/shell/EvidenceDrawer.ets) |
+| D-05 | Markdown 导入不认标题，导出又加 `#`，往返变成 `# # 标题`（R4） | 新增 `MarkdownBlocks`：导入时把 1–3 级标题/列表/待办转成段落标注并从正文剥离（四级以上保持原文，不静默改）；导出侧对"已带同类标记"的行跳过前缀 | [MarkdownBlocks.ets](entry/src/main/ets/utils/MarkdownBlocks.ets)、`ExportService`、`AppStores.importFiles` |
+| D-11 | 未声明 `READ_PASTEBOARD`，跨应用粘贴只能走应用内缓冲 | `module.json5` 声明（user_grant，带 reason/usedScene）+ 新增 `PasteboardAccess`：首次粘贴时校验并申请一次，拒绝后降级到应用内缓冲，不抛错 | [Pasteboard.ets](entry/src/main/ets/utils/Pasteboard.ets)、`module.json5`、`CanvasTextEditor.pasteAtCaret` |
| D-10 | 死代码：从未挂载的 `AppShell.appBar()`、`Navigator` 4 个零调用函数、`FocusWorkspace.entered` 只写不读 + 重复背景色、`TopicCard` 行上两个右键监听（后者覆盖前者）、`SettingsPanel` 绕过打字机写入口、`Index` 与 `AppShell` 两层光感 | 逐项删除或接线（详见提交）；`Navigator` 只留 `nav / hasWorkspace / ensureWorkspace` | 见提交 diff |
+
+## 2. 新增/更新的回归
+
+| 脚本 | 变化 | 覆盖点 |
+| --- | --- | --- |
+| `arkts-guard` | 19 → **21** | 新增「`@Monitor` 根必须是组件状态变量」（扫全仓，禁止 `app.*` 作根）；新增「生成稿必须走 `EditorStore` 命令」（禁止 `chapterRepo.saveDraft` 直写） |
+| `import-regression` | 5 → **7** | Markdown 块级解析（标记剥离 + 段落标注位置）；往返不叠加 `#`（含历史脏数据只还原一层） |
+| `draft-regression` | 14 → **20** | 来源锚四态：精确 / 前插段落重定位 / 重复文字取最近并提示核对 / 文字改掉明确失败 / 无快照老数据不盲跳 / 只有指纹仍可确认 |
+| `shell-regression` | 62（内容更新） | 对话框监听改用 `uiWatch`；工具组只由编辑区承载；跳源必须核验锚点且无固定 360ms；专注页无只写不读的入场状态 |
+| `flowtext-regression` | 141（内容更新） | 粘贴现在先异步申请权限：沙箱替身 + 足够的微任务收敛，原有 7 条粘贴用例语义不变 |
+
+合计：**377 项**（原 367 + 10）。
+
+## 3. 构建结果（clean 后）
+
+| 项 | P0 基线 | P1 之后 |
+| --- | --- | --- |
+| 错误 | 0 | **0** |
+| 告警 | 114 | **105** |
+| 其中 `@Monitor` | 9 | **0** |
+
+剩余告警分类不变：`Function may throw` 46、`px2vp` 27、`animateTo` 17、`vp2px` 6、`fontSize` 4、废弃 `showToast/showDialog` 各 1、`READ_PASTEBOARD` 提示 1（权限已声明并在首次粘贴时申请，编译器只按调用点提示）、`SystemBars` 的设备不可用提示 2（代码已按平台跳过，属预期）。这些进 P2/P4 分批处理。
+
+## 4. 未测项（不冒充通过）
+
+1. `@Monitor` 修复后，顶栏「查找」是否真的能打开面板（需真机点一次）。
+2. 覆盖初稿后的撤销条（5 秒内点「撤销」）在真机上的表现；内存草稿与库是否始终一致。
+3. `READ_PASTEBOARD` 的授权弹窗时序：首次粘贴会先弹权限框，授权后才插入内容；拒绝后只能粘贴应用内内容。
+4. 来源锚在真实长文里的定位精度（跨段摘录、摘录首尾有空白）。
+5. 跨应用粘贴、中文输入法与粘贴混用。
+
+## 5. 本轮明确没做（留给后续阶段）
+
+- `MobileShell` 两份重复的 `Navigation` 配置、`mobileTab` 不可达分支：属结构性重构，随 P4 动态挂载一起做。
+- `MaterialSurface` 里零引用的 4 个 modifier：无害，等旁栏/整页接入时按需删除或复用。
+- `AppStores.showMaterials/showGraph` 与 `EditorViewMode.MATERIAL/GRAPH`：视图已不存在，随 P5 数据会话化一起清。
+- 46 条 `Function may throw`：逐处补 `try/catch` 属 P2，且需要判断哪些确实会抛。
