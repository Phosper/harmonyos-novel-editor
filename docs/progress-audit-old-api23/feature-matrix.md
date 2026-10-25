> **归档说明（2026-10-18 迁移）**：本报告生成于旧工作区 `/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`（API 23 副本，源码停在 2026-10-06）。当前工程为 `SDK26Target/Weaver`（API 26，含 10-13/10-17 优化与 10-18 编辑器修复），因此文中**构建、验证与代码规模结论已过时**；功能缺口类结论仅供参考，行动前请以当前源码重新审计。

# Weaver 功能完成度矩阵（规格 → 代码实证）

> **审计对象**：Weaver（HarmonyOS ArkTS 小说编辑器，单 entry 模块）
> **代码基线**：`entry/src/main/ets/` 共 82 个 `.ets`、13,928 行（`find | wc -l` 实测）
> **当前特性**：`spec/feature.json` → `spec/flowtext-sole-editor`
> **审计方式**：只读静态审计（代码 + 规格 + 构建报告），**未修改 `entry/src`、`spec/`、`docs/design/` 任何文件**
> **审计日期**：2026-10-18
> **审计人**：feature-auditor（团队任务 task-1）

---

## 0. 结论速览

| 范围 | 规格宣称 | 审计核定 | 关键判断 |
|---|---|---|---|
| **A. flowtext-sole-editor** | 46/46 已勾选 | **代码 35 项已实现、5 项部分实现、1 项未完成清理、4 项待验证/未核实（T001 设备侧）、1 项构建可核实** | 核心编辑能力（US1–US3、US5–US7）代码齐全且证据充分；**T036/T045/T046 无验证证据**；T008 实现方式与任务描述不一致 |
| **B. flowtext-integration** | 14 完成 / 6 未完成 | 6 项**全部为"待设备验证"性质**，其中 5 项代码链路已具备、1 项（T020）真未完成 | 该规格已被 A 取代（同一层文件已重写），其未勾项不构成功能缺口；文档描述的 `setContent(text)` 链路已过时 |
| **C. mobile-ui-refactor** | 37 完成 / 1 未完成 | **T038 真未完成**；且 US1/US4 的部分交付物（底部页签、分段页签）**已从现有代码中移除** | 规格与代码已脱节：`MobileTabBar`/`MobileSectionTabs` 为**死代码**，`UiStore.mobileTab` 只写不读 |
| **D. ui-spec（2026-10-05）** | 4 主题 + TypeScale + 令牌化 | **主题体系已落地；TypeScale 未落地；令牌化大部分落地（零星硬编码）；稿纸字号可调未落地** | 详见 §5 |
| **E. 功能面（17 项）** | — | 9 已实现 / 6 部分实现 / 2 未实现（素材、关系图为**有数据层无 UI**） | 详见 §6 |

**一句话**：编辑内核（自绘 FlowText）完成度最高且实现扎实；**素材/关系图**与**写作冲刺**是当前最大的功能面缺口；手机端导航规格已被后续"纯纯写作式极简"改版推翻，规格文档未同步。

---

## 1. 审计方法与判定口径

### 1.1 证据来源
1. 规格：`spec/feature.json`、三个特性的 `spec/plan/tasks.md`、`docs/design/ui-spec.md`；
2. 代码：`entry/src/main/ets/{constants,shell,store,pages,database,repository,model,utils,editor,entryability}` 全量清点 + 关键文件逐行核对；
3. 构建证据：`.hvigor/report/*.json`（最后一次 `BUILD SUCCESSFUL` 为 **2026-10-08 22:20:12**）、`entry/build/default/outputs/default/entry-default-signed.hap`（**2026-10-06 17:22**）；
4. 早期基线：`Weaver重构计划.md`、`Weaver重构进展报告_2026-08-12.md`（仅用于追溯"曾实现/已废弃"，其 `components/viewmodel` 目录描述**已被 shell/store 架构取代，不予照抄**）。

### 1.2 判定口径（四级 + 两类结论分离）

| 判定 | 含义 |
|---|---|
| **已实现** | 代码中存在可运行实现，入口可达，有 file:line 证据 |
| **部分实现** | 存在实现但缺一侧（如：有数据层无 UI、有链路无消费端、常驻入口缺失、行为与描述不符） |
| **未实现** | 代码中无实现 |
| **待设备验证** | 代码链路具备，但结论只能由真机/构建验证得出，本次**未获得**该类证据 |
| **未核实** | 无法从代码判断，且无外部证据 |

**本报告严格区分两个维度**：
- **代码状态**＝能读到实现（本次可判定）；
- **验证状态**＝是否通过构建/真机/UI 验证（本次**只有构建报告**，无设备、无截图、无测试记录）。

> ⚠️ 环境限制：本机（OpenEuler）无 `hvigor/hdc/devecocli/ohpm`，本次**未执行任何构建或部署**。构建结论仅来自仓库内既有报告，产物与源码是否严格同源**未核实**。

---

## 2. 规格 A：flowtext-sole-editor（46/46 勾选核定）

勾选统计（`grep -c` 实测）：`[X]`=46、`[ ]`=0、任务号 T001–T046 共 46 项 —— **勾选数量属实，但"勾选=完成"的真伪需逐项核对**。

### 2.1 Phase 1–2（Setup / Foundational）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T001 | 建立构建/真机基线 | `.hvigor/report/report-202610082220120080.json` 含 `BUILD SUCCESSFUL in 5 s 224 ms`；`entry-default-signed.hap` 存在（2026-10-06 17:22） | **构建可核实 / 设备未核实** |
| T002 | 复用 `DIAG_ENABLED` 预留量化输出点 | `editor/flowtext/CanvasTextEditor.ets:43`（`DIAG_ENABLED`）、`:1556`（`diag()`）、`:39`（scroll/center/anim/fmt 标签约定） | 已实现 |
| T003 | 新增 `ScrollPolicy`/`StyleKind` | `model/EditorTypes.ets:43`（ScrollPolicy NORMAL/CENTER）、`:51`（StyleKind BOLD/ITALIC/HEADING_1..3/BODY） | 已实现 |
| T004 | 扩展 `TextEditorHost` 契约 | `editor/TextEditorHost.ets:41`(typewriter)、`:43`(scrollPolicy)、`:48`(loadFormat)、`:53/:55/:57`(onSelectionChange/onFormatChange/onScrollState)、`:33`(contentRev) | 已实现 |
| T005 | 扩展 `CanvasTextEditor` props/回调 | `CanvasTextEditor.ets:203-213`（6 个 `@Watch` 主题 Prop + typewriter/scrollPolicy）、`:227-229`（onScrollState/onRequestSave 等） | 已实现 |
| T006 | `EditorPane` 单一渲染路径装配 | `shell/EditorPane.ets:50`（唯一 `TextEditorHost({...})`，无原生分支） | 已实现 |

### 2.2 Phase 3 — US1 打字机 / 动画（7 项）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T007 | `ensureCaretVisible(policy)` 程序化滚动 | `CanvasTextEditor.ets:1989`（NORMAL 分支滚动到可见区）、`:2023`（`clampScroll` 钳制） | 已实现 |
| T008 | CENTER：**"当前段中心"对齐视口中心** | `CanvasTextEditor.ets:1999`：`target = caretTop - (viewHeight - caretH)/2` → **居中的是光标所在"行"的框，不是"段"的中心** | **部分实现（与描述不符）** |
| T009 | 宿主驱动 typewriter/scrollPolicy（默认关/NORMAL） | `TextEditorHost.ets:41-43`；`EditorPane.ets:53-54`（`typewriter ? CENTER : NORMAL`）；`UiStore.ets:66` 默认 `false` | 已实现 |
| T010 | 接入 `createEditAnimations` + `drawAnimatedGlyph` | `CanvasTextEditor.ets:1469`（`GlyphAnimator.createEditAnimations`）、`:1494`（`runGlyphAnimation`）；`GlyphRenderer.ets:189`（`drawAnimatedGlyph`） | 已实现 |
| T011 | 行位移过渡动画 | `animation/GlyphAnimator.ets:52`（`createEditAnimations`），跨行 `dy > rowThreshold` 时做短时滑动（`:100-118`，上限 `MAX_SLIDES=80`） | 已实现 |
| T012 | 打字机开关入口（默认关） | `UiStore.ets:66`/`:68`（`toggleTypewriter`）；`pages/dest/SettingsDest.ets:48-49`；`shell/SettingsPanel.ets:36-37`；宽屏 `EditorPane.ets:180-184` | 已实现 |
| T013 | 居中偏差/动画量化日志 | `CanvasTextEditor.ets:2017`（`scroll policy=... caretY=... scrollY=... max=...`）、`:1444`（`perf relayout=...ms`） | 已实现 |

### 2.3 Phase 4 — US2 IME / 光标 / 选区（6 项）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T014 | 订阅 IME 预上屏 → `PreviewTextManager.update` | `ime/ImeBridge.ets:81`（**attach 前** `registerPreviewListeners()`，`:84` 才 `attach`）、`:87-88`（`setPreviewText`/`finishTextPreview` 注册） | 已实现 |
| T015 | 提交时机 `commit` → 写入正文 | `CanvasTextEditor.ets:988-990`（`onPreviewFinish` → `insertExternalText`）、`:979-986`（预上屏更新 + 重绘）、`:1599-1602`（draw 时传 preview） | 已实现 |
| T016 | 选区手柄模型/锚点/grapheme 对齐 | `interaction/SelectionManager.ets:87`（`beginHandleDrag`）、`:92`（`updateHandleDrag`）、`:16`（`setSource` 按字符边界收敛） | 已实现 |
| T017 | 手柄绘制（形状 + 命中区） | `render/GlyphRenderer.ets:244`（`drawHandles`：圆头 + 细柄）、`:104`（选区非空即绘制） | 已实现 |
| T018 | 手柄命中与拖动（**任务标注文件：EditorGesture.ets**） | 命中 `CanvasTextEditor.ets:1619`（`handleAt`）、拖动 `:1720-1731`；`interaction/EditorGesture.ets` 仅 27 行（`tap`/`isDrag`） | 已实现（**实现位置与任务标注不符**） |
| T019 | `onSelectionChange` 经宿主上抛供工具栏态 | 链路齐：`CanvasTextEditor.emitSelection` → `TextEditorHost.ets:53` → `EditorPane.ets:62`；**消费端为空实现**（注释"Phase A：仅承载选区态"） | **部分实现** |

### 2.4 Phase 5 — US3 行内格式（8 项）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T020 | runs 模型（非重叠/排序/不变式） | `model/TextDocument.ets:183`（`setRuns`）、`:203`（`toggleInline`）、`:232`（`toggleHeading`）、`:371`（`normalizeRuns` 合并排序）、`:406/:420`（插入平移/删除收缩） | 已实现 |
| T021 | 布局按 run 差异化样式 | `render/TextLayoutEngine.ets:174`（BOLD→`W700`、ITALIC→`ITALIC`、标题放大）、`:197-211`（分段 `pushStyle`，格式边界断 run） | 已实现 |
| T022 | 渲染层按 run 绘制 | `GlyphRenderer.ets:132-186`（逐 run `TextBlob`，动画字形单独插值绘制） | 已实现 |
| T023 | `toggleInlineStyle`/`toggleParagraphStyle` | `CanvasTextEditor.ets:1291`/`:1307`（组件内）、`:174`/`:181`（Controller 转发） | 已实现 |
| T024 | 格式参与撤销/重做与回灌 | `store/EditorStore.ets:186`（`setEditorState` 带 runsJson）、`:258`（`remember`）、`:282-298`（`stepHistory` 还原 `runsJson`）、`StoreModels.ets:86`（`HistoryEntry.runsJson`） | 已实现 |
| T025 | 格式持久化落库（边车，旧数据纯文本） | `database/DatabaseHelper.ets:14`（`format_runs` 幂等加列）、`:64`（建表列）、`ChapterDao.ets:65/:84/:117`、`model/Chapter.ets:28`、`FormatCodec`（`:11` encode/`:21` decode，空串=无格式） | 已实现 |
| T026 | 格式工具栏入口 | `EditorPane.ets:156-184`（宽屏 quickBar：粗/斜/标题）；手机端经选区浮层 `CanvasTextEditor.ets:311-355`（粗/斜/标题）；`EditorPane.mobileToolBar` 定义于 `:389` 但**从未被调用** | **部分实现** |
| T027 | 导出对行内格式的处理 | `utils/ExportService.ets:29`（`renderChapter`）、`:60`（`applyMarkdown`：标题 `#` + 行内 `**`/`*`）、`:135`（`renderBook`） | 已实现（但备份恢复丢失格式，见 §7-G4） |

### 2.5 Phase 6–8 — US4/US5/US6（9 项）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T028 | 修复 `onRequestSave` 未触发 | `CanvasTextEditor.ets:878-886`（`releaseEditorFocus` 内触发 `onRequestSave`）；`:743-744`（容器 `onBlur`）、`:154`（Controller.blur） | 已实现 |
| T029 | 切文稿/切后台/回灌正文与光标恢复 | `TextEditorHost.ets:86-110`（`onContentRevChanged` 回灌，含格式）、`:113-127`（`reload` 按 docId 载入 + focus） | 已实现 |
| T030 | 主题/字号/行距变更立即重排 | `CanvasTextEditor.ets:203-208`（6 个 `@Prop @Watch('onThemeChanged')`）、`:897`（同步主题 + 重建引擎 + `relayout`）、`:1330`（`ensureEngine`） | 已实现 |
| T031 | 导入/导出/排版/查找替换与新格式兼容 | 导入 `ImportService.ets:31`；导出见 T027；排版 `EditorPane.ets:274`；替换 `:289` | **部分实现**：`applyExternalContent` 会清空 `runsJson`（`EditorStore.ets:249`），排版/全量替换后格式静默丢失 |
| T032 | 滚动状态上报 | `CanvasTextEditor.ets:1766-1769`（`onScrollState(dy<0?1:-1)`）→ `TextEditorHost.ets:57` → `EditorPane.ets:69` → `UiStore.noteScroll:76` | 已实现 |
| T033 | 复用 `immersive` 隐藏/恢复 chrome | `UiStore.ets:76-86`（`noteScroll`）、`:51-64`（`noteTyping` 3.5s 恢复）；`shell/WorkspaceDest.ets:243`（顶栏 180ms 收放）、`EditorPane.ets:184-188`（快捷条 180ms） | 已实现（**宽屏 `isWide` 直接 return，始终不隐藏**，`UiStore.ets:77-79`） |
| T034 | 视口限域渲染 | `GlyphRenderer.ets:124`（逐行 `yOffset` 与 `viewport.top/bottom` 比对后 `continue`）、`:230`（选区同样裁剪）、`:253`（手柄裁剪） | 已实现 |
| T035 | 增量布局 + 失效范围收敛（含格式版本键） | `render/LayoutCache.ets:38`（`applyEdit` 按段落回退）、`:48`（`invalidateFrom`）、`:31`（`ensureOffset` 懒排版）、`:63`（`formatVersion` 参与失效判定） | 已实现 |
| T036 | 5 万字性能测量与调优 | 仅有埋点（`CanvasTextEditor.ets:1444` `perf relayout`）；**仓库无任何测量数据** | **未核实（待设备）** |

### 2.6 Phase 9–11 — US7 / Polish / Verification（7 项）

| 任务 | 规格要求（摘要） | 代码证据 | 判定 |
|---|---|---|---|
| T037 | 移除 `EditorPane` 原生引擎分支 | `EditorPane.ets:50` 为唯一渲染路径；全文件无 `TextArea`/`RichEditor` | 已实现 |
| T038 | 删除 `RichTextEditorHost.ets` 及全部引用 | `find` 全仓（排除 `oh_modules/.hvigor`）**无此文件**；`grep -rn RichTextEditorHost entry/ spec/ docs/` **0 命中** | 已实现 |
| T039 | 移除 `EditorEngine` 枚举与 prefs `engine` 键 | `grep -rn "EditorEngine\|editorEngine\|setEditorEngine"` **0 命中**；残留仅 `utils/PreferenceHelper.ets:13` 常量 `KEY_ENGINE`（已无读写调用） | 已实现（残留常量） |
| T040 | 移除设置页"正文编辑引擎"项 | `SettingsDest.ets` 全文仅"主题"+"打字机"两组；`SettingsPanel.ets` 同 | 已实现 |
| T041 | 清理 flowtext 死代码与未用 import | 仍存在：`EditorPane.ets:389` `mobileToolBar`（不可达）、`MobileShell.ets:20` 未使用 import、`GlyphRenderer.ets:335` `legacyOffsetToX` | **未完成** |
| T042 | 更新特性/迁移文档 | `spec/flowtext-sole-editor/IMPLEMENTATION_NOTES.md`（能力→文件映射、DB 迁移、移除项、诊断） | 已实现 |
| T043 | `DIAG_ENABLED` 与标签一致性 | `CanvasTextEditor.ets:43`（开关）、`:39`（tag 约定）、`:1556`（统一出口 `diag()`） | 部分实现（标签均为自由字符串，无枚举收口） |
| T044 | 构建并修复编译错误 | `.hvigor/report/*` 6 份均含 `BUILD SUCCESSFUL`（末次 2026-10-08 22:20） | **可核实（历史报告）** |
| T045 | 部署到真机 | 有 HAP 产物（2026-10-06 17:22）；**无部署记录、无设备日志、本机无 `hdc`** | **未核实** |
| T046 | 逐故事 UI 验证 | 仓库内**无任何截图/验证记录**（`find -name '*.png'` 仅命中应用图标资源） | **未核实** |

**A 汇总**：已实现 **35**、部分实现 **5**（T008/T019/T026/T031/T043）、未完成 **1**（T041）、未核实 **4**（T001 设备侧/T036/T045/T046）、构建可核实 **1**（T044）。核心 US1–US3/US5–US7 的代码实现**属实**；US6 性能门限与全部真机验证**无证据**。

---

## 3. 规格 B：flowtext-integration（14 完成 / 6 未完成）

该规格是"把 FlowText 复制进 Weaver 并替换 TextArea"的**前一阶段**工程任务，其产物文件（`TextEditorHost.ets`、`EditorPane.ets`）后来被 A 规格重写。核定：**6 个未勾项全部是"验证类/部署类"，不构成功能缺口**。

| 任务 | 性质 | 代码链路现状 | 判定 |
|---|---|---|---|
| T009 | 验证：编辑器内编辑流 → `EditorStore` | `CanvasTextEditor.ets:1451`（`onEdit` 上报 text/runs/caret）→ `EditorPane.ets:118` → `EditorStore.ets:186` | **待设备验证（链路具备）** |
| T010 | 验证：保存流 `flushDoc` → `updateContent` | `EditorStore.ets:340-366`：`updateContent` → `updateCaretOffset` → `updateFormatRuns` | **待设备验证（链路具备）** |
| T011 | 验证：撤销/重做链路 | ⚠️ 文档描述的 `setContent(text)` 已不再是主链路；现为 `setEditorState(text, runsJson, caret)`（`EditorStore.ets:186`）→ `remember:258` → `undoStack` | **待设备验证（链路具备，文档过时）** |
| T012 | 验证：多标签切换 | `TextEditorHost.ets:113-127` `reload()` 按 `docId` 载入正文+光标+格式 | **待设备验证（链路具备）** |
| T013 | 验证：关闭/重开恢复 | 同上 + `loadCaret`（`EditorPane.ets:109-115`）+ `updateCaretOffset` 落库 | **待设备验证（链路具备）** |
| T020 | 部署到设备 | 明确记载"无设备可用"；仅有 HAP 产物 | **真未完成（部署）** |

**B 结论**：这 6 项不宜计入"功能未实现"。真正未完成的是**验证动作**本身（T009–T013 缺一次真机回归、T020 缺设备），与 A 规格的 T045/T046 是同一个证据缺口。

---

## 4. 规格 C：mobile-ui-refactor（37 完成 / 1 未完成）

### 4.1 T038 判定：真未完成（跨断点 UI 验证）

任务原文已自述：US1/US2/US3 已实机截图复核，**US4（sm↔md↔lg 跨断点）未执行**，原因是 `verify_ui` 后端不可用、本机无法把窗口宽度推过 600/840vp。仓库内亦无截图留存。
**判定：真未完成**（属验证缺口，非实现缺口；`sm/md/lg` 三档布局代码均存在）。

### 4.2 关键发现：US1/US4 的交付物已被后续改版移除（规格与代码脱节）

审计发现 `mobile-ui-refactor/tasks.md` 的 T011–T014、T028 描述的"底部页签主导航 + md 分段页签"**在现有代码中不存在**：

| 证据 | 事实 |
|---|---|
| `shell/MobileShell.ets:38-43` | `tabItems()` 注释"只保留 项目/文稿 —— 砍掉素材与关系图"，且该函数**无调用者** |
| `shell/MobileShell.ets:88-98`（`narrowHome`） | 注释「**取消"项目"页与底部页签**；主页即文稿列表」；build 只有 `titleBar()` + `docList()` |
| `shell/MobileShell.ets:20` | `import { MobileTabBar, MobileTabItem }` —— **导入但从未渲染** |
| `shell/MobileTabBar.ets` / `MobileSectionTabs.ets` | 组件完整（56vp 底栏、选中指示条、a11y），但**全仓 0 处引用**（死代码） |
| `store/UiStore.ets:44` | `mobileTab` 只被 `MobileShell.titleText()` 读取，无页签写入路径 |
| `shell/MobileShell.ets:105-118`（`mediumHome`） | md 只剩"文稿列表"，注释"素材/关系图已按新设计移除"，不再是 T028 要求的"侧栏 + 内容（含分段页签）" |

**判断**：这不是"勾选造假"，而是**规格完成后又被新设计推翻**（`docs/design/ui-spec.md` 附录 2026-10-05 "纯纯写作"启示 + `WorkspaceDest.ets:1-10` 的极简改版）。旧任务勾选在当时可能属实，但**对当前代码不再成立**，且规格文档未同步。

### 4.3 tasks.md 引用的文件已不存在（路径级失效）

| 任务 | 引用文件 | 现状 |
|---|---|---|
| T022 | `shell/MaterialPane.ets` | **不存在** |
| T023 | `shell/GraphPane.ets` | **不存在** |
| T025 | `pages/dest/CharacterDetailDest.ets`、`WorldSettingDetailDest.ets`、`InspirationCreateDest.ets` | **均不存在**（`pages/dest/` 仅剩 `SettingsDest.ets`） |
| T011/T022/T023 的"素材/关系图面板" | — | 无任何替代实现（见 §6-6/7） |

### 4.4 C 结论
- **T038：真未完成**（跨断点 + lg 零回归无截图证据）；
- **T011–T014、T028 的勾选对当前代码不成立**（能力被移除，非缺失实现）；
- **T020–T026 中 4 个文件路径已失效**，其中"素材/关系图"面板的消失是**真实功能缺口**（§6）。

---

## 5. 对照 `docs/design/ui-spec.md` 的落地核对

> ui-spec 内部存在一处自相矛盾：§3.1 表格写 `夜读 bgPrimary=#000000`，但附录（2026-10-05 竞品实测）要求"深色用柔和深灰 `#282828` 而非纯黑（已改夜读主题）"。**代码采用 #282828**，与附录一致，§3.1 表格已过时。

| 规范条目 | 规范要求 | 代码证据 | 判定 |
|---|---|---|---|
| **4 套主题预设** | 极简纸墨/温暖米纸/青笺/夜读 | `constants/DesignTokens.ets:99-104`（`THEMES`：`ink`/`warm`/`green`/`dark`）、`INK/WARM/GREEN/NIGHT` 四套语义色集（`:60-96`） | **规范已落地** |
| `themeById`/`tokensFor` 单一入口 | 页面统一取色 | `DesignTokens.ets:106`（`themeById`）、`:112`（`tokensFor`）；各页面 `private colors()` 均走 `tokensFor(app.ui.themeId)` | **规范已落地** |
| 全局 `themeId` + 持久化 | UiStore 引入 themeId | `store/UiStore.ets:27`、`:167`（`setTheme` 写 `prefs.setThemeId`）、`:210-231`（`loadFromPrefs`）；`PreferenceHelper.ets:134-138` | **规范已落地** |
| 设置页「主题」入口（列全部预设） | 4 预设可点选 | `pages/dest/SettingsDest.ets:31-42`（ForEach THEMES + ✓ 选中态）；`shell/SettingsPanel.ets:22-35`（弹层版同款） | **规范已落地** |
| 「跟随系统深浅」入口 | 设置中可显式选择 | **设置页无该开关**；仅隐式跟随：`EntryAbility.ets:105-113` + `UiStore.applySystemDarkMode:186` 依赖 `prefs.isDarkExplicit()`，而 `setDarkMode`（唯一写显式标记的入口，`UiStore.ets:178`）**全仓无调用者** | **部分落地**（仅自动跟随，无显式入口） |
| 编辑器纸色随全局主题联动 | 纸色派生自主题 | `shell/EditorPane.ets:86-88`：`textColor=colors().textPrimary`、`bgColor=colors().editorBg`、`caretColor=colors().brand`；字号/行距仍取 `paperTheme` | **规范已落地** |
| 稿纸字号/行距独立可调 | "仍由稿纸字号/行距独立可调" | `UiStore.paperTheme:31` 与 `setPaperTheme:194` 存在，但**无任何 UI 调用者**（grep 全仓）；`PAPER_THEMES`（`DesignTokens.ets:318`）的 `backgroundColor/textColor` 已成为死字段 | **未落地**（能力缺失） |
| **`TypeScale`** | display/title/headline/body/sub/caption/micro | `DesignTokens.ets:122-135` 已定义 7 档 + 行高；**全仓 0 处引用**（`grep -rn TypeScale` 仅命中定义行）；页面字号全部为字面量（如 `fontSize(15)`/`fontSize(13)`） | **未落地**（仅定义） |
| `WeaverSpacing` | 4/8/12/16/24/32；页边距 16 | `DesignTokens.ets:147-166`；使用点：`EditorPane.ets:346`（TOOLBAR_H）、`MobileShell.ets:163`（TITLEBAR_H）、`AppShell.ets` 多处 | **部分落地**（栏高走 token，页面内边距多为字面量 16） |
| `WeaverRadii` 收敛 4 档 | XS/S/M/L，**废弃 XXL** | `DesignTokens.ets:137-145`：仍保留 `XL=20`、`XXL=32`（与"收敛为 4 档"不符）；实际使用以 `SM/XS/LG` 为主 | **部分落地** |
| 页面颜色令牌化（禁硬编码） | 除编辑器 canvas 外不得硬编码色值 | 主页面已走 tokens；残留硬编码：`EditorPane.ets:227`、`InputDialog.ets:79`、`WorkspaceDest.ets:114`（scrim `#66000000`，而 `SystemBars.ets:18` 已有 `OVERLAY_MASK_COLOR` 未被复用）、`DocListPane.ets:188`（删除按钮 `#FFFFFF`，语义上应取 `onBrand`）、`CanvasTextEditor.ets:311-355` 选区浮层（编辑器内，可豁免） | **部分落地** |
| 深色下无"亮块穿帮" | 禁止浅色硬编码块 | 深色主题色集完整（`NIGHT`），页面未见浅色实心块；导出用 HTML 模板（`MarkdownRenderer.ets:167-175`）固定浅色，属导出产物 | **基本落地** |
| 正文对比度 ≥ 4.5:1 | 客观对比度门限 | 无测量工具/无记录 | **未核实** |
| 动效 120/180/260ms EaseOut | 顶栏/工具条收放 180ms | `WorkspaceDest.ets:243`、`EditorPane.ets:186-187` 均 `180ms + EaseOut`；`animation/AnimationSpec.ets` 另有光标/字形曲线 | **基本落地** |
| 极简（不用阴影） | 1px divider + 背景层次 | 全仓未见 `shadow()` 使用，层级用 `bgPrimary/bgSurface/bgCard` + divider | **规范已落地** |

**ui-spec 总结论**：**「主题体系 + 设置入口 + 稿纸联动」= 规范已落地**；**「TypeScale + 稿纸字号可调」= 未落地**；**「令牌化」= 大部分落地、有 4 处可清理的硬编码 + XXL 未废弃**；对比度需真机/工具核实。

---

## 6. 功能面清点（17 项）

| # | 功能 | 代码入口（file:line） | 状态 | 缺口说明 |
|---|---|---|---|---|
| 1 | 书稿（项目）CRUD | `store/AppStores.ets:100`（createBook）、`:109`（deleteBook）、`:88`（selectBook）；UI `shell/ProjectSidebar.ets` | **部分实现** | **无重命名入口**：`repository/BookRepository.ets:22` `renameBook` 全仓 0 调用 |
| 2 | 章节（文稿）CRUD | `AppStores.ets:135`（create）、`:188`（rename）、`:199`（回收站）、`:208`（硬删）、`:217`（恢复）、`:246`（TXT/MD）；UI `shell/DocListPane.ets:142-180`（长按菜单） | 已实现 | — |
| 3 | 自动保存 | `store/EditorStore.ets:306`（debounce）、`:316`（安全网定时器）、`:340`（flushDoc）；`EntryAbility.ets:118`（退后台）、`EditorStore.ets:378`（flushAll） | 已实现 | 无保存失败重试上限说明 |
| 4 | 撤销/重做 | `EditorStore.ets:258`（remember，带时间窗合并）、`:274/:278`（undo/redo）、`:282`（stepHistory）；UI `EditorPane.ets:190-200`、`WorkspaceDest.ets:160-166`、键盘 `ime/KeyboardHandler.ets:111-117` | 已实现 | — |
| 5 | 写作冲刺（字数目标/计时） | **全仓 0 命中**（`grep 冲刺\|sprint`） | **未实现** | `Weaver重构进展报告_2026-08-12.md §2.1` 称旧 `WeaverViewModel` 已含"写作冲刺定时器"，**重构后未迁移**（回归） |
| 6 | 素材（人物/世界观/灵感） | 数据层：`store/MaterialStore.ets:57-143`、`repository/MaterialRepository.ets`、`database/{Character,WorldSetting,Inspiration}Dao.ets`；**UI：无** | **未实现（仅数据层）** | `MaterialPane.ets` 不存在；`Navigator.openSection:49` **无调用者**；`UiStore.view`（`UiStore.ets:88`）**只写不读**；`NEW_CHARACTER`/`NEW_WORLD` 对话框类型（`UiStore.ets:18/20`）**无任何发起者**（`AppShell.dialogView` 无法被触发） |
| 7 | 关系图 | 数据层：`store/RelationStore.ets:20`（load）、`:39`（rebuild 建图）、`model/GraphNode.ets`、`DesignTokens.ets` `graphNodeColor/graphEdgeColor`；**UI：无** | **未实现（仅数据层）** | 无 GraphPane/Canvas；`AppStores.showGraph:311` 只改状态位；`Routes.WORKSPACE` 注释仍写"编辑器+素材+关系图"（`Navigator.ets:15`）与实现不符 |
| 8 | 导入（txt/md/html/json） | `utils/ImportService.ets:31`（picker）、`:34`（后缀过滤）、`:66-68`（类型判定）；`AppStores.ets:326`（importFiles） | 已实现 | 入口：lg `AppShell.ets:336`、sm/md `MobileShell.ets:202` |
| 9 | 导出（txt/md/html/json 备份） | `utils/ExportService.ets:29`（单篇）、`:135`（整本）、`AppShell.ets:476-540`（6 项菜单） | 已实现 | — |
| 10 | 备份恢复 | `AppStores.ets:386`（importBackupText：新项目 + ID 重映射 + 事务）、`:489`（exportBackupData） | **部分实现** | **恢复侧未写 `formatRuns`**（`AppStores.ets:444-456` 的 ChapterModel 无该字段）→ 行内格式经备份往返后丢失 |
| 11 | 查找替换 | `EditorPane.ets:289`（replaceAll 全量替换）、`:196-232`（浮层）；选区"查找"`CanvasTextEditor.ets:365` | **部分实现** | **只有"全部替换"**，无"查找下一个/替换当前" |
| 12 | 一键排版 | `EditorPane.ets:274`（runFormat）→ `utils/TextFormat.ets:79`；`WorkspaceDest.ets:170` | **部分实现** | `applyExternalContent`（`EditorStore.ets:241-256`）会 `doc.runsJson=''` → **排版后行内格式静默丢失** |
| 13 | 引导页 | `pages/GuideSwiperPage.ets`（4 页 Swiper）；首启路由 `EntryAbility.ets:93` | 已实现 | 引导页不提供模式选择（已统一专业版，属刻意简化） |
| 14 | 设置 | `pages/dest/SettingsDest.ets`（主题 + 打字机）、`shell/SettingsPanel.ets`（弹层同款）、`WorkspaceDest.ets:141-153` | **部分实现** | 缺：稿纸字号/行距、跟随系统开关、备份/恢复入口、关于/版本 |
| 15 | PC/平板/手机三形态外壳（lg/md/sm） | 断点来源 `AppShell.ets:119`（`getWindowWidthBreakpoint`）+ `utils/BreakPoint.ets:17`；分发 `AppShell.ets:259-266`；lg `wideBody():272`（SideBarContainer AUTO + Navigation + PcWindowBar）、md `MobileShell.ets:116`（SideBarContainer Embed）、sm `MobileShell.ets:88`（单列 + push 工作区） | 已实现 | md/sm 的底栏/分段页签已移除（§4.2）；无 xs 档单独处理（映射进 SM） |
| 16 | 沉浸式滚动 | `UiStore.ets:76`（noteScroll）、`:51`（noteTyping）；`WorkspaceDest.ets:243`、`EditorPane.ets:184`（180ms 收放） | **部分实现** | 宽屏 `isWide` 直接 return（`UiStore.ets:77`）→ **PC/平板滚动不隐藏 chrome**，与 US5"正文滚动隐藏顶栏"表述不符（属既定取舍，规格未注明） |
| 17 | 字数统计 | `EditorStore.ets:88`（wordCount）、`utils/TextLimit.ets`（`countChars` 按字素）、UI `EditorPane.ets:142-151`（浮动字数） | 已实现 | — |

---

## 7. 缺口清单（按严重度）

| ID | 缺口 | 严重度 | 证据 | 性质 |
|---|---|---|---|---|
| **G1** | **素材（人物/世界观/灵感）无任何 UI**，`ui.view` 只写不读、`openSection` 无调用者、`NEW_CHARACTER/NEW_WORLD` 对话框无发起者 | **高** | `Navigator.ets:49`；`UiStore.ets:88`；`AppStores.ets:306-314`；`shell/` 无 MaterialPane | 功能缺失（数据层完好） |
| **G2** | **关系图无任何 UI**（节点/边/配色已具备） | **高** | `RelationStore.ets:39`；无 GraphPane | 功能缺失 |
| **G3** | **写作冲刺未迁移**（旧版有，重构后 0 命中） | **高** | `grep 冲刺\|sprint` = 0；`进展报告_2026-08-12 §2.1` | 功能回归 |
| **G4** | **备份恢复丢行内格式**（导出带 `formatRuns`，恢复不写） | 中 | `AppStores.ets:444-456` 对比 `ExportService.ets:52-56` | 数据不一致 |
| **G5** | **一键排版/全部替换静默清空格式** | 中 | `EditorStore.ets:249`（`doc.runsJson = ''`） | 数据丢失（无提示） |
| **G6** | **稿纸字号/行距不可调**（`setPaperTheme` 无 UI 调用者） | 中 | `UiStore.ets:194`；`grep setPaperTheme` 仅定义 | 规格（ui-spec §2）未落地 |
| **G7** | **`TypeScale` 定义后 0 引用**，字号全是字面量 | 中 | `DesignTokens.ets:122`；`grep TypeScale` 仅 1 命中 | 规范未执行 |
| **G8** | **T008 打字机为"行居中"而非"段居中"**，与任务描述/US1-SC-002（段中心 ±10% 视口高）不一致；长段落可能超差 | 中 | `CanvasTextEditor.ets:1999` | 行为与规格偏差（需实测定性） |
| **G9** | **查找替换仅"全部替换"** | 中 | `EditorPane.ets:274-320` | 功能不完整 |
| **G10** | **手机端底部页签/分段页签被移除**，两组件成死代码；`mobileTab` 无写入路径 | 中 | `MobileShell.ets:20,38-43,88-98`；`MobileTabBar.ets`/`MobileSectionTabs.ets` 0 引用 | 规格与代码脱节 |
| **G11** | **项目重命名无入口**（`renameBook` 未接线） | 低 | `BookRepository.ets:22` 0 调用 | 功能不完整 |
| **G12** | **死代码/残留**：`EditorPane.mobileToolBar:389`（不可达）、`PreferenceHelper.KEY_ENGINE:13`、`PAPER_THEMES` 颜色字段、`Navigator.openSection/hasWorkspace/backToRoot/leaveWorkspaceIfEmpty`、`GlyphRenderer.legacyOffsetToX:335` | 低 | 见各 file:line | 卫生问题（T041 未完成） |
| **G13** | **深色主题可能被系统浅色覆盖**：`setTheme` 不写"显式选择"标记，`setDarkMode` 无调用者；用户选"夜读"后系统切回浅色会触发 `applySystemDarkMode(false)` → 回落 `lastLightThemeId` | 低（静态推断，待验证） | `UiStore.ets:167-192`；`PreferenceHelper.ets:129` | 潜在缺陷 |

---

## 8. 必须由设备验证的清单

| # | 验证点 | 对应任务/规格 | 依据缺口 |
|---|---|---|---|
| V1 | 打字机居中：段中心偏差 ≤ ±10% 视口高、滚动无跳变 | US1 / T008 / SC-002 | 实现为行居中，**必须实测判定是否可接受** |
| V2 | 字符入场/消退/换行滑动动画连续、无跳动 | US1 / T010/T011 / SC-003 | 代码具备，无视觉证据 |
| V3 | IME 预上屏、候选提交、200 字中英混排+emoji 一致率 | US2 / T014/T015 / SC-004 | 无设备 |
| V4 | 选区手柄拖动、长按选词、三击选段 | US2 / T016–T018 | 无设备 |
| V5 | 5 万字：输入 <50ms、滚动 ≥50fps、无卡死/白屏 | US6 / T036 / SC-006 | **仓库无任何测量数据** |
| V6 | sm↔md↔lg 跨断点切换 + lg 零回归截图 | mobile-US4 / T038 | **T038 未完成** |
| V7 | 四主题 × 明暗对比度 ≥4.5:1、无亮块穿帮 | ui-spec §6.4/§8 | 无测量 |
| V8 | 格式保存→重开一致率、格式撤销/重做、备份恢复后格式 | US3 / SC-005 | G4 已静态确认恢复丢格式 |
| V9 | 渲染性能（`perf relayout` 日志）与滚动诊断 | T036/T043 | 需 `DIAG_ENABLED=true` 真机跑 |
| V10 | 一次完整构建复现（源码↔产物同源） | T044 / T045 | 本机无 hvigor，仅有历史报告 |

---

## 9. 结论

1. **flowtext-sole-editor（当前特性）代码完成度高且诚实**。46 项勾选中，**35 项可逐行落到实现**（另 1 项 T044 有历史构建报告佐证）；打字机滚动（`CanvasTextEditor.ets:1989`）、字符动画（`GlyphAnimator.ets:52` + `GlyphRenderer.ets:189`）、IME 预上屏（`ImeBridge.ets:81-88` + `CanvasTextEditor.ets:979-990`）、选区手柄（`SelectionManager.ets:87-92` + `GlyphRenderer.ets:244`）、行内格式全链路（`TextDocument → TextLayoutEngine → GlyphRenderer → format_runs → ExportService`）、视口限域（`GlyphRenderer.ets:124`）、增量布局（`LayoutCache.ets:38-63`）均有明确证据；`RichTextEditorHost.ets` 已删除、`EditorEngine` 枚举与设置项已移除（T038–T040 属实）。
2. **但"勾选 ≠ 已验证"**。T036（5 万字性能）、T045（部署）、T046（UI 验证）**没有任何证据**；T008 的实现是"光标行居中"而非任务描述的"段居中"，属**行为偏差**而非缺失。5 项（T008/T019/T026/T031/T043）为部分实现，T041 死代码清理未完成。
3. **flowtext-integration 的 6 个未勾项是"验证/部署"缺口，不是功能缺口**；其文档描述的 `setContent` 链路已被 `setEditorState(text, runs, caret)` 取代，建议整份规格标注为"已归档"。
4. **mobile-ui-refactor 的勾选与当前代码已脱节**：手机端底部页签/分段页签被后续极简改版删除（`MobileTabBar`/`MobileSectionTabs` 成死代码，`UiStore.mobileTab` 只写不读），tasks.md 引用的 4 个文件已不存在。**T038 确实未完成**；建议按"规格已变更"重写，而不是按"实现缺失"补工。
5. **ui-spec 落地程度：主题体系已落地（4 套预设 + 设置入口 + 稿纸联动 + 零阴影 + 180ms 动效），TypeScale 未落地（0 引用），令牌化大面落地但仍有 4 处可清理硬编码与未废弃的 XXL，稿纸字号/行距可调能力缺失**。深色语义色与附录一致（`#282828`），§3.1 表格已过时。
6. **最大功能缺口不在编辑器，而在"编辑器之外"**：素材（人物/世界观/灵感）与关系图**数据层完整、UI 全缺**，加上写作冲刺未迁移 —— 这三项使"小说编辑器"的设定管理能力实际不可用，应作为下一阶段第一优先级。
7. **验证层面的统一结论**：当前仓库只有**构建证据**（末次 `BUILD SUCCESSFUL` 2026-10-08 22:20）与 **HAP 产物**（2026-10-06 17:22），**无部署记录、无截图、无测试报告**。任何"已通过真机/UI 验证"的表述都只能以任务文档自述为依据，本次审计**不予背书**。

---

## 附：审计证据索引（关键 file:line）

- 编辑器内核：`editor/flowtext/CanvasTextEditor.ets:1989`（scroll）、`:1999`（CENTER）、`:1449`（afterEdit）、`:1469`（动画）、`:1588`（drawNow）、`:979-990`（IME）
- 渲染：`render/GlyphRenderer.ets:124`（视口裁剪）、`:244`（手柄）、`:189`（动画字形）
- 排版：`render/LayoutCache.ets:38-63`；`render/TextLayoutEngine.ets:174-211`
- 模型：`model/TextDocument.ets:183-442`（runs 不变式）；`model/EditorTypes.ets:43/51/67`
- IME：`ime/ImeBridge.ets:81-88`；`ime/PreviewTextManager.ets:8-37`
- 交互：`interaction/SelectionManager.ets:87-92`；`interaction/HitTester.ets:19-53`；`interaction/EditorGesture.ets`（27 行）
- 宿主：`editor/TextEditorHost.ets:33-127`
- 状态：`store/EditorStore.ets:186/241/258/282/306/340`；`store/UiStore.ets:27/66/76/167-196`；`store/StoreModels.ets:86`
- 外壳：`shell/AppShell.ets:119/259-272/476`；`shell/MobileShell.ets:38-43/88/116/202`；`shell/WorkspaceDest.ets:32/141/243`；`shell/EditorPane.ets:43-50/156/274/289/341/389`
- 数据：`database/DatabaseHelper.ets:14/64`；`database/ChapterDao.ets:65/84/117`；`store/AppStores.ets:326/386/489`
- 令牌：`constants/DesignTokens.ets:57/99/106/122/137/147/170/318`
- 设置：`pages/dest/SettingsDest.ets:31-49`；`shell/SettingsPanel.ets:22-37`
- 构建：`.hvigor/report/report-202610082220120080.json`（BUILD SUCCESSFUL）；`entry/build/default/outputs/default/entry-default-signed.hap`
