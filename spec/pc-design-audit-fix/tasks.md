# Tasks: Weavr PC 端 HarmonyOS Design 审查整改

**Input**: Design documents from `spec/pc-design-audit-fix/`
**Prerequisites**: plan.md, spec.md

**Verification Scope**: `build+ui` — 编译构建 + 部署 + 每用户故事的 UI 界面验证

**Tests**: 未请求自动化测试；验证通过 Phase 9 的编译构建、部署和 UI 验证完成

**Organization**: 按用户故事分阶段组织，每个故事可独立实现和验证

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行执行（不同文件，无依赖）
- **[Story]**: 所属用户故事（US1-US5）
- 所有描述包含目标文件完整路径

## Path Conventions

- **PC 布局组件**: `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\`
- **入口文件**: `D:\Project_code\Weaver\products\default\src\main\ets\entryability\`
- **页面文件**: `D:\Project_code\Weaver\products\default\src\main\ets\pages\`
- **公共模块**: `D:\Project_code\Weaver\common\src\main\ets\`
- **资源文件**: `D:\Project_code\Weaver\products\default\src\main\resources\`

---

## Phase 1: Setup (共享基础设施)

**Purpose**: 建立交互常量和新 Token，为后续所有用户故事提供基础

- [X] T001 Create `PcInteraction` class with press/hover timing constants in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDesignTokens.ets`
- [X] T002 Add `EMPHASIZE_DIMMED` token as forward-compatible replacement for legacy `INFO` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDesignTokens.ets`

---

## Phase 2: Foundational (阻塞性前提)

**Purpose**: 深色模式基础设施 — 所有用户故事依赖的全局能力。必须在本阶段完成后才能开始任何用户故事。

**⚠️ CRITICAL**: 没有本阶段的基础，US1-US5 的组件无法获取正确的运行时色彩值。

- [X] T003 Add `colorMode` AppStorage initialization based on `ConfigurationConstant.ColorMode` in `D:\Project_code\Weaver\products\default\src\main\ets\entryability\MainAbility.ets`
- [X] T004 Implement dual-mode `PcColors` resolution function (light/dark value per token) in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDesignTokens.ets`
- [X] T005 Supplement PC dark mode resource color entries in `D:\Project_code\Weaver\products\default\src\main\resources\dark\element\color.json`

**Checkpoint**: 双模式色彩体系就绪 — 用户故事可实现

---

## Phase 3: User Story 1 — 完整的 PC 输入反馈体验 (Priority: P1) 🎯 MVP

**Goal**: 所有可交互元素拥有按压/悬停/键盘焦点三态反馈

**Independent Test**: 在 2in1 设备上点击任意按钮立即看到视觉变化；鼠标划过元素出现 hover 效果；Tab 键按侧栏→列表→编辑区顺序移动焦点

### 按压反馈 (Press)

- [X] T006 [P] [US1] Add `stateStyles({ pressed, normal })` press feedback to all Buttons and list rows in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`
- [X] T007 [P] [US1] Add `stateStyles({ pressed, normal })` press feedback to segment buttons and doc cards in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T008 [P] [US1] Add `stateStyles({ pressed, normal })` press feedback to toolbar buttons, tab close buttons, and action buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T009 [P] [US1] Add `stateStyles({ pressed, normal })` press feedback to quick-action buttons and send button in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`
- [X] T010 [P] [US1] Add `stateStyles({ pressed, normal })` press feedback to collapsed Rail icon buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`

### 悬停反馈 (Hover)

- [X] T011 [P] [US1] Add `onHover` hover state with 100ms background transition to list items and project rows in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`
- [X] T012 [P] [US1] Add `onHover` hover state to doc cards and search input border in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T013 [P] [US1] Add `onHover` hover state to toolbar buttons, tab bar close buttons, and status bar badge in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T014 [P] [US1] Add `onHover` hover state to quick-action buttons and close button in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`
- [X] T015 [P] [US1] Add `onHover` hover state to collapsed Rail icon buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`

### 键盘焦点 (Focus)

- [X] T016 [US1] Add `focusable(true)` and `focusBorder` to sidebar nav items and project list in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`
- [X] T017 [US1] Add `focusable(true)` and `focusBorder` to segment buttons, doc cards, and search input in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T018 [US1] Add `focusable(true)` and `focusBorder` to toolbar buttons and action buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T019 [US1] Add `focusable(true)` and `focusBorder` to quick-action buttons and input in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`

**Checkpoint**: 输入三态在所有 PC 组件中完整可用 — US1 可独立验证

---

## Phase 4: User Story 2 — 标题栏融合与纵向空间解放 (Priority: P1) 🎯 MVP

**Goal**: 隐藏系统标题栏，新建自定义标题栏组件，释放 ~80vp 编辑区空间

**Independent Test**: 2in1 设备上窗口无系统标题栏，顶部有统一自定义标题栏，可拖拽移动，编辑区高度增加

- [X] T020 [US2] Create custom title bar component with app branding and drag-to-move support in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcTitleBar.ets`
- [X] T021 [US2] Add `setWindowDecorVisible(false)` and `setWindowSystemBarProperties` calls in `D:\Project_code\Weaver\products\default\src\main\ets\entryability\MainAbility.ets`
- [X] T022 [US2] Integrate `PcTitleBar` into shell layout and remove `statusBarHeight` + `win.getAvoidArea` logic in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`
- [X] T023 [P] [US2] Remove `statusBarPad` and simplify top padding in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`
- [X] T024 [P] [US2] Remove `statusBarPad` and simplify top padding in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`

**Checkpoint**: 标题栏融合完成，编辑区纵向空间释放 — US2 可独立验证

---

## Phase 5: User Story 3 — 深色模式支持 (Priority: P2)

**Goal**: 系统切换深色模式时，PC 布局全自动适配深色配色

**Independent Test**: 切换系统深色模式，PC 布局在 300ms 内过渡为深色；切换回浅色，恢复

- [X] T025 [US3] Subscribe to `onConfigurationUpdate` for colorMode changes and broadcast via AppStorage in `D:\Project_code\Weaver\products\default\src\main\ets\entryability\MainAbility.ets`
- [X] T026 [US3] Apply dual-mode color resolution to PcShell and PcTitleBar in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets` and `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcTitleBar.ets`
- [X] T027 [P] [US3] Apply dual-mode color resolution to sidebar and doc list in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets` and `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T028 [P] [US3] Apply dual-mode color resolution to editor zone in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T029 [P] [US3] Apply dual-mode color resolution to agent panel in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`

**Checkpoint**: 深色模式全布局覆盖 — US3 可独立验证

---

## Phase 6: User Story 4 — 无障碍与色彩体系一致性 (Priority: P3)

**Goal**: 图标按钮有读屏语义；历史 GREEN Token 清理；手机/PC 端统一蓝色强调色

**Independent Test**: 屏幕朗读器为所有图标按钮播报正确功能描述；grep 搜索无旧 Token 名称

### Token 清理与统一

- [X] T030 [US4] Delete legacy `GREEN`, `GREEN_DEEP`, `GREEN_SOFT`, `LINE_2`, `INFO` tokens from `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDesignTokens.ets`
- [X] T031 [P] [US4] Replace all legacy token references with new equivalents in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\WeaverViewModel.ets`
- [X] T032 [P] [US4] Replace all legacy token references with new equivalents in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets` and `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T033 [US4] Update `SemanticColors.INTERACTIVE_PRIMARY` from green #7AB75F to blue #007DFF in `D:\Project_code\Weaver\common\src\main\ets\constants\Colors.ets`
- [X] T034 [US4] Update tab label selected color to use unified blue token in `D:\Project_code\Weaver\products\default\src\main\ets\pages\Index.ets`

### 无障碍语义标签

- [X] T035 [P] [US4] Add `accessibilityText` labels to all icon-only buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`
- [X] T036 [P] [US4] Add `accessibilityText` labels to all icon-only buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcDocList.ets`
- [X] T037 [P] [US4] Add `accessibilityText` labels to all icon-only buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T038 [P] [US4] Add `accessibilityText` labels to all icon-only buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcAgentPanel.ets`
- [X] T039 [P] [US4] Add `accessibilityText` labels to collapsed Rail icon buttons in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`

**Checkpoint**: Token 体系清洁统一，无障碍标注完整 — US4 可独立验证

---

## Phase 7: User Story 5 — 视觉精致度抛光 (Priority: P3)

**Goal**: 折叠导轨激活指示、查找栏平滑动画、折叠按钮 Flex 布局修正

**Independent Test**: 折叠侧栏可见激活指示器；查找栏出现/消失有滑入动画；折叠按钮位置稳定

- [X] T040 [US5] Enable active library indicator visibility (remove `opacity(0)`) on collapsed Rail icons linked to `activeLibId` in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcShell.ets`
- [X] T041 [US5] Replace find bar `OPACITY`-only transition with combined `translate + OPACITY` asymmetric transition in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcEditorZone.ets`
- [X] T042 [US5] Move sidebar fold button from `position()` absolute coordinate into standard Flex Row layout in `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\PcSidebar.ets`

**Checkpoint**: 视觉效果精致度达标 — US5 可独立验证

---

## Phase 8: Polish (跨故事打磨)

**Purpose**: 全局一致性校验和清理收尾

- [X] T043 Run global grep for legacy token names (GREEN, GREEN_DEEP, GREEN_SOFT, LINE_2, INFO) across entire `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\` — confirm zero matches
- [X] T044 Verify no remaining `position()` absolute coordinate hacks and no hardcoded non-Token color values exist in any PC layout component under `D:\Project_code\Weaver\products\default\src\main\ets\pclayout\`

---

## Phase 9: Verification (编译 + 部署 + UI 验证)

<!-- verification_scope: build+ui -->

**Purpose**: 编译构建、部署到设备、并对每个用户故事执行 UI 界面验证

- [X] T045 Build project and fix all compilation errors (invoke `build_project`; iterate fix → build until success) for project at `D:\Project_code\Weaver`
- [X] T046 Deploy application to device/emulator (invoke `start_app`) for project at `D:\Project_code\Weaver`
- [X] T047 Run UI verification against deployed application (invoke `verify_ui` per user story): verify US1 (press/hover/focus visual feedback), US2 (title bar + drag), US3 (dark mode toggle), US4 (accessibility labels + color consistency), US5 (rail indicator + find bar animation + layout stability)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，即刻开始
- **Foundational (Phase 2)**: 依赖 Setup 完成 — 阻塞所有用户故事
- **US1-US5 (Phase 3-7)**: 全部依赖 Foundational 完成；用户故事之间可并行
- **Polish (Phase 8)**: 依赖所有用户故事完成
- **Verification (Phase 9)**: 依赖 Polish 完成

### Within Each User Story

- 按压反馈 → 焦点反馈（焦点依赖该组件已有可交互元素）
- 悬停反馈与按压/焦点可并行
- Token 删除 → Token 引用替换
- 标题栏组件创建 → Shell 集成 → 子组件 statusBarPad 移除

### Parallel Opportunities

- 所有标记 [P] 的任务操作不同文件，完全独立可并行
- US1-US5 五个用户故事可在 Foundational 完成后并行推进
- 同一 US 内不同组件的同类任务（如 T006-T010）完全可并行

## Parallel Example: User Story 1 Press Feedback

```text
# 五个组件的按压反馈同时启动:
Task: "Add stateStyles press feedback to PcSidebar.ets"
Task: "Add stateStyles press feedback to PcDocList.ets"
Task: "Add stateStyles press feedback to PcEditorZone.ets"
Task: "Add stateStyles press feedback to PcAgentPanel.ets"
Task: "Add stateStyles press feedback to PcShell.ets"
# 以上五个操作不同文件，零冲突
```

## Implementation Strategy

### MVP First (US1 + US2)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1 (输入反馈) → 独立验证
4. Complete Phase 4: User Story 2 (标题栏融合) → 独立验证
5. **STOP**: US1 + US2 = 核心交互体验 + 空间释放，已构成可用 MVP

### Incremental Delivery

1. Setup + Foundational → 色彩基础设施就绪
2. + US1 → 输入反馈完整 → 可演示
3. + US2 → 标题栏融合 → 可演示（MVP）
4. + US3 → 深色模式 → 可演示
5. + US4 → 无障碍+色彩统一 → 可演示
6. + US5 → 视觉精致度 → 可演示
7. + Polish + Verification → 交付

---

## Notes

- [P] 标记的任务操作不同文件，无依赖冲突，可完全并行
- [Story] 标签将任务映射到具体用户故事，支持需求追溯
- 每个用户故事在 checkpoint 处可独立验证，不依赖后续故事
- T045 编译失败时可进入修复循环（最多 10 次迭代）
- T047 UI 验证对每个用户故事进行最多 3 次验证尝试（初始 + 2 次修复→重验证）
- 建议每个用户故事或逻辑组完成后提交一次 commit
- 总任务数 47：Setup 2 + Foundational 3 + US1 14 + US2 5 + US3 5 + US4 10 + US5 3 + Polish 2 + Verification 3
