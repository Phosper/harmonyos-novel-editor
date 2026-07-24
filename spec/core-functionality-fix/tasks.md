# Tasks: Weavr 核心功能修复（存储 + 按钮 + 导出）

**Input**: Design documents from `spec/core-functionality-fix/`
**Prerequisites**: plan.md, spec.md

**Verification Scope**: `build+ui` — 编译构建 + 部署 + 每用户故事的 UI 界面验证

**Tests**: 未请求自动化测试；验证通过 Phase 10 的编译、部署和 UI 验证完成

**Organization**: 按用户故事分组，每个故事可独立实现和验证

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行执行（不同文件，无依赖）
- **[Story]**: 所属用户故事（US1-US6）
- 所有描述包含目标文件完整路径

## Path Conventions

- **PC 布局**: `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\`
- **入口**: `D:\Project_code\Weaver\products\default\src\main\ets\entryability\`

---

## Phase 1: Setup

**Purpose**: 基础枚举和数据结构定义

- [X] T001 Add `SaveState` enum (IDLE/SAVING/FAILED) to `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`

---

## Phase 2: Foundational

**Purpose**: 编辑历史和上下文基础设施——所有 US 依赖

- [X] T002 Add undo/redo stacks (`undoStack: string[]`, `redoStack: string[]`, max 100) and `pushUndoState()`/`undo()`/`redo()` methods to `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`
- [X] T003 Cache `UIAbilityContext` via AppStorage for file export in `D:\Project_code\Weaver\products\default\src\main\ets\entryability\MainAbility.ets`

**Checkpoint**: 基础设施就绪

---

## Phase 3: User Story 1 — 可靠的定时自动保存 (Priority: P1) 🎯 MVP

**Goal**: 60s 周期保存 + 3 次重试 + 状态展示

**Independent Test**: 编辑文稿等待 60s → 状态栏显示"已保存"；模拟失败 → 显示"保存失败（点击重试）"

- [X] T004 [US1] Implement `startAutoSave()` using `setInterval(60000)`, add `SaveState` state management, and `performAutoSave()` method in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`
- [X] T005 [US1] Implement retry logic (max 3 retries at 5s intervals) and `retrySave()` manual trigger in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`
- [X] T006 [US1] Update status bar to display save state text and retry tap area in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T007 [US1] Add `destroy()` method to clear timers, call from `PcShell.aboutToDisappear` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets` and `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`

**Checkpoint**: 自动保存可独立验证

---

## Phase 4: User Story 2 — 可用的搜索与查找替换 (Priority: P1) 🎯 MVP

**Goal**: 文稿列表实时搜索 + 编辑器查找替换导航

**Independent Test**: 搜索框输入 → 列表筛选；查找栏输入 → 跳到首个匹配 → 显示"1/N"

- [X] T008 [US2] Implement `searchDocs(query: string): DocListItem[]` filter method in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`
- [X] T009 [US2] Wire search `TextInput.onChange` to filter `docItems` in real-time in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T010 [US2] Implement `findAll()` matches logic using `String.indexOf` loop and store `matchPositions` array in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T011 [US2] Wire find navigation (up/down arrows) with `caretPosition` and match counter display in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T012 [US2] Wire replace and replaceAll buttons with content slice manipulation and undo state push in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`

**Checkpoint**: 搜索和查找替换可独立验证

---

## Phase 5: User Story 3 — 可用的文本格式化 (Priority: P1) 🎯 MVP

**Goal**: B/I/U/H1-H3/引用/列表 + 撤销恢复完整可用

**Independent Test**: 选中文字点 B → 出现 `**文字**`；点撤销 → 还原

- [X] T013 [US3] Implement inline formatting (B/I/U markers `**` `*` `__`) using `onTextSelectionChange` + content slice in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T014 [US3] Implement heading formatting (H1/H2/H3 line-start `#` `##` `###` prefix, cycle on repeat) in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T015 [US3] Implement quote (`> `) and list (`- `) line prefix formatting with multi-line support in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T016 [US3] Wire undo button to `WeaverViewModel.undo()` with history push before each format operation in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T017 [US3] Wire redo button to `WeaverViewModel.redo()` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`

**Checkpoint**: 格式化和撤销恢复可独立验证

---

## Phase 6: User Story 4 — 文稿导出（TXT + JSON + Markdown） (Priority: P2)

**Goal**: 三格式导出通过系统文件保存对话框完成

**Independent Test**: 导出 TXT → 系统弹出保存对话框 → 保存后文件管理器打开确认内容

- [X] T018 [US4] Create `ExportService` class with `exportTxt()` method using `picker.DocumentViewPicker.save()` + `fileIo.writeSync()` to strip Markdown and write plain text in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\ExportService.ets`
- [X] T019 [US4] Add `exportMd()` method preserving Markdown formatting in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\ExportService.ets`
- [X] T020 [US4] Add `exportJson()` method serializing full book data (chapters + characters + worldSettings + inspirations + relationships) with `JSON.stringify()` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\ExportService.ets`
- [X] T021 [US4] Add export trigger UI (toolbar button or menu) calling ExportService methods with current context and data from ViewModel in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`

**Checkpoint**: 三格式导出可独立验证

---

## Phase 7: User Story 5 — 写作增强功能（模式 + 专注计时 + Rail 导航） (Priority: P2)

**Goal**: 打字机/聚焦/沉浸模式生效，专注计时可用，Rail 图标可导航

**Independent Test**: 点打字机 → 输入时自动居中；点 Rail ★ → 切换到收藏文库

- [X] T022 [US5] Implement typewriter mode using Scroll controller to keep current line vertically centered in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T023 [US5] Implement spotlight mode reducing non-current paragraph opacity to 0.3 in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T024 [US5] Implement zen mode toggling panel visibility via existing `toggleFullscreen` integration in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T025 [US5] Implement focus timer (renamed from sprint, 25min countdown) using `setInterval` with pause/resume and display in status bar in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets` and `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T026 [US5] Add `onClick` handlers to collapsed Rail icons (≡→all, ★→fav, ✦→insp) calling `changeSidebarLib` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`

**Checkpoint**: 写作增强功能可独立验证

---

## Phase 8: User Story 6 — AI 伴侣交互占位 (Priority: P3)

**Goal**: 发送和快捷按钮显示"功能开发中"提示而非丢弃输入

**Independent Test**: 发送消息 → 显示占位提示

- [X] T027 [US6] Replace `onSend` no-op with push user message + placeholder AI response in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`
- [X] T028 [US6] Replace `quickAction` hardcoded echo with placeholder AI response in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`

**Checkpoint**: AI 占位可独立验证

---

## Phase 9: Polish

**Purpose**: 全局校验

- [X] T029 Verify all buttons in PC layout have functional onClick (no no-op handlers remaining) across `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\`
- [X] T030 Verify timer cleanup: `destroy()` called in `PcShell.aboutToDisappear`, no orphaned intervals

---

## Phase 10: Verification

<!-- verification_scope: build+ui -->

**Purpose**: 编译构建、部署、UI 验证

- [ ] T031 Build project and fix all compilation errors (iterate fix→build until success) for project at `D:\Project_code\Weaver`
- [ ] T032 Deploy application to device/emulator for project at `D:\Project_code\Weaver`
- [ ] T033 Run UI verification per user story: US1 (save state transitions in status bar), US2 (search filter + find/replace navigation), US3 (formatting markers appear + undo/redo), US4 (export dialog opens + file saved), US5 (typewriter scroll + spotlight opacity + zen hide + focus timer countdown + Rail navigation), US6 (AI placeholder response)

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup → Foundational → US1/US2/US3 (P1 stories, parallel once Foundational done) → US4/US5 (P2) → US6 (P3) → Polish → Verification

### Within Each User Story

- US1: T004→T005→T006 (save logic → retry → UI), T007 parallel
- US2: T008 (VM query) → T009 (list UI); T010→T011→T012 (find logic chain)
- US3: T013/T014/T015 (formatting types, parallel) → T016→T017 (undo/redo depends on format ops existing)
- US4: T018/T019/T020 (export methods, parallel) → T021 (UI trigger)
- US5: T022/T023/T024/T025 (modes + timer, all parallel different logic) → T026 (shell rail)
- US6: T027/T028 parallel

## Parallel Example: US3 Formatting

```text
# 三个格式化类型同时启动:
Task: "Implement inline formatting (B/I/U) in PcEditorZone.ets"
Task: "Implement heading formatting (H1/H2/H3) in PcEditorZone.ets"
Task: "Implement quote/list formatting in PcEditorZone.ets"
# 同一文件但不同方法，可顺序执行
# 完成后启动 undo/redo:
Task: "Wire undo button"
Task: "Wire redo button"
```

## Implementation Strategy

### MVP First (US1 + US2 + US3)

1. Phase 1-2: Setup + Foundational
2. Phase 3: US1 (auto-save) → 验证
3. Phase 4: US2 (search + find/replace) → 验证
4. Phase 5: US3 (formatting + undo/redo) → 验证
5. **STOP**: US1+US2+US3 = 保存+搜索+格式化，核心写作功能已可用

### Incremental

1. + US4 → 导出能力
2. + US5 → 写作增强
3. + US6 → AI 占位
4. + Polish + Verification → 交付

---

## Notes

- [P] 任务操作不同文件或不同方法，可并行
- [Story] 标签映射到 spec.md 用户故事
- 每个 Phase 的 checkpoint 后执行 build_project 验证编译
- T031 编译失败可进入修复循环（最多 10 次迭代）
- T033 UI 验证每用户故事最多 3 次尝试
- 总任务数 33: Setup 1 + Foundational 2 + US1 4 + US2 5 + US3 5 + US4 4 + US5 5 + US6 2 + Polish 2 + Verification 3
