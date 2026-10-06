# Weaver 鸿蒙小说编辑器 — 代码评审与重构计划

> 范围：对 `/storage/Users/currentUser/Desktop/Weaver/Weaver/` 全部源码做**只读评审**，不修改任何代码。
> 目标产物：本报告（问题诊断 + 架构优化 + 解耦方向 + 可维护性改进 + 优先级排序）。
> 评审依据：通读 56 个源 `.ets`、8 个 `.ts`、33 个 `.json5` 及 `.md` 文档，结合 `grep` 精确定位。

---

## 一、项目架构现状概览

**工程形态**：标准 HarmonyOS（ArkTS/ArkUI）多模块工程，分层为
`common`（共享 HAR：模型 / DAO 抽象 / 持久化单例 / 工具 / 常量）
→ `features/{editor, material, relationship, settings, agent}`（特性 HAR，经 `@ohos/xxx` 别名引用）
→ `products/default`（应用壳 + 页面 + PC 三栏布局）。

**技术栈关键事实**：
- 持久层：RDB（`relationalStore`，6 张表 + 版本迁移）+ Preferences（轻量键值）+ 文件系统导出（用户主动触发）。
- 状态层：`AppStorage`（全局）+ `@Observed class WeaverViewModel`（核心可观察模型）+ 各组件 `@State/@Prop/@Link`。
- 导航：`router` 仅 push 7 个已注册二级页到 PC 壳之上；PC 壳内部靠 `EditorViewMode` 枚举做"视图状态机"切换。
- 运行时实际是 **PC 三栏壳独占**：`pages/Index.ets` 永远只渲染 `PcShell()`。

**一句话健康度结论**：
> 分层骨架（model / dao / feature / product）方向正确，但**业务与 UI 在页面层严重耦合**、**存在上帝对象与状态三重存储**、**DAO 层大量复制粘贴**、**数据迁移静默吞异常**、**资源与类型未收口**，且**手机端 4 个 Tab 页是已废弃的不可达平行实现**。代码可跑，但可维护性、可测试性、可演进性均偏弱。

---

## 二、现有代码问题诊断（按严重度）

### 2.1【严重】上帝对象 `WeaverViewModel` + 状态三重存储
- `products/default/.../pclayout/WeaverViewModel.ets`：`@Observed` 类同时持有 **6 个 DAO 实例 + 撤销栈 + 自动保存定时器 + 写作冲刺定时器 + 全部 UI 状态**（数据访问与视图模型未分离）。
- `PcShell.ets:21` `new WeaverViewModel()`，并在 `:24-57` 又定义 ~33 个 `@State` 镜像同一份数据，靠 `syncFromVm()`（`:102`）逐字段手动同步 → **VM 字段 ↔ PcShell.@State ↔ PcEditorZone.@Prop 三份状态并存**，易失同步、难以推理。
- 注：ArkUI 的 `@Observed` 不会自动驱动嵌套子组件重渲染，这正是引入 `syncFromVm()` 的"补丁"根源。

### 2.2【严重】UI 与持久层紧耦合（~39–50 处 `new XxxDao()` 直接写在组件里）
- 典型：`SideDrawer.ets:24,34,40,56,72,85`（同组件内重复 new）；`AgentSheet.ets:68,69,87,107`（UI 组件内直接 new Dao 写"写作统计/人物概览"业务逻辑 + 硬编码中文 prompt）；`MaterialTabPage.ets`、`RelationshipTabPage.ets`、`EditorPage.ets`、`InspirationListPage.ets` 等。
- 后果：业务逻辑无法脱离 UI 单测；换存储实现需改动大量视图代码。

### 2.3【严重】数据迁移静默吞异常（数据丢失风险）
- `common/.../database/DatabaseHelper.ets:107,110,113,116,119,122,143,159,178,195` 约 **10 个空 `catch (e) {}`** 包裹 ALTER/RENAME/CREATE/INSERT 迁移 SQL，失败被静默吞掉。
- `WeaverViewModel.clearAllData`（`:95-101`）、`SideDrawer.ets:65,79`、`ChapterDao.safeGetLong`（`:384`）同样吞异常。
- 风险：schema 升级失败不报错，可能静默损坏或丢数据。

### 2.4【高】巨型组件 + 巨型 prop-drilling
- `PcEditorZone.ets`：72KB，**48 个 `@State`** + ~40 个 `@Prop`/回调（如 `:40-56` 大量 no-op 默认实现，仅引用参数压制告警），`build()` 承载编辑器 + 素材表单 + 关系图。
- 重渲染面过大，单点改动波及全局，难以并行开发。

### 2.5【高】DAO 层大量重复
- 6 个 DAO（`Book/Chapter/Character/WorldSetting/Inspiration/Relationship`）的 `getStore/insert/update/delete/queryById/queryByBook/queryAll/rowToModel` 骨架**逐字复制**。
- `ChapterDao.ets:117-292` 约 **17 个查询方法仅谓词不同**，应参数化为单一 `query(predicates)`。
- 空值读取三种不统一写法：`ChapterDao.safeGetLong`（`:384`）/`CharacterDao.getColumnString`（`:118`）/`InspirationDao.isColumnNull`（`:43`）。

### 2.6【中】双重调色板 + 硬编码资源
- 两套调色板且取值冲突：`common/.../constants/Colors.ets`（`StatusColors.ERROR='#C0392B'`、`GraphColors.LINE_POSITIVE='#A4CE92'`、`SemanticColors.INTERACTIVE_PRIMARY='#007DFF'`）vs `PcDesignTokens.ets`（`DANGER='#FA2A2D'`、`ACCENT_LIME='#7AB75F'`、`EMPHASIZE='#007DFF'`）。
- 命名易混同文件内：`PcColors`（类）/`pcColors`（函数）/`PcColorSet`（接口）。
- 仅 `GuideSwiperPage.ets` 用 `$r()`；其余 **~156 处 `Text('中文')` 硬编码文案**，未抽 `string.json`，无法 i18n。
- 魔法值：`PcEditorZone.ets:382` 写死 `'#0D000000'`；多处硬编间距/字号而非 `PcRadii`/`PcSpacing`。

### 2.7【中】弱类型（`string` 当枚举）
- `Book.mode`、`CharacterModel.characterType`、`RelationshipModel.type`、`GraphNode/Edge.type` 均为裸 `string`（散落如 `SideDrawer.ets:44`、`WeaverViewModel.ets:129,145`、`Relationship.ets`）。应改 `enum` 并集中常量。
- `update()` 方法签名四态不一：`ChapterDao.update(id,title,content)` vs `CharacterDao.update(id,model)` 等，调用方易错。
- 正面：模型均为 `interface`、源码**无 `any`**。

### 2.8【中】孤儿页面 + 桩代码
- **孤儿（不可达）**：`pages/EditorPage.ets`、`MaterialTabPage.ets`、`RelationshipTabPage.ets`、`MyTabPage.ets` 未在 `main_pages.json` 注册、也未被 import，运行时永不加载；其中 `EditorPage`/`MaterialTabPage` 与 PC 流 `PcEditorZone`/`WeaverViewModel` 功能高度重叠，是**已废弃的平行实现**。
- **桩**：`EditorToolbar.ets`、`ThemeSelector.ets`、`ModeSwitch.ets`（仅 `Text('... stub')`）、`GraphGestureHandler.ets`（空 `Stack()`）、`AgentSheet` 的 AI 返回固定文案"AI 功能开发中，敬请期待"。

### 2.9【中】ArkTS 性能反模式
- 全仓**零 `LazyForEach`**（grep 为 0），大量 `ForEach` 用于可能增长的列表（`PcDocList:169`、`MaterialTabPage:199,235,277,305`、`RelationshipTabPage:281,381`），缺虚拟化。
- `AgentSheet.ets:50` `setTimeout(...,100)` hack 滚动；`PcEditorZone.ets:700,708` 残留 `console.info` 调试日志。
- 无 `eval`/`Function`/`Reflect`（正面）。

### 2.10【低】死代码 / 命名冲突
- `CharacterCard.ets:2` 死导入 `GreenColors`；`PcEditorZone.ets:40-120` 约 40 个 no-op 默认回调。

### 2.11【低】零自动化测试
- 无 `*.test.ets`/`*.spec.ets`/test 目录；`hypium` 仅作依赖存在、源码 0 处 import。当前架构（Dao 嵌 UI、`AppStorage` 全局态、上帝组件）使单测难以落地。

---

## 三、架构优化建议（目标态）

**核心思路：补强 MVVM 分层，把"数据访问"与"UI"彻底切开，把"单一真相源"收口。**

1. **引入 Repository 层（关键解耦点）**
   - 在 `features/*/data` 之上加 `Repository`（如 `BookRepository`、`ChapterRepository`、`MaterialRepository`、`RelationshipRepository`）。Repository 持有 DAO、对外暴露用例级方法（`getBookWithChapters`、`saveDraft`、`toggleFavorite`），UI/ViewModel **只依赖 Repository 接口**，不再 `new Dao()`。
   - 用轻量**依赖注入 / 服务定位**（模块级单例或构造注入）替代散落的 `new XxxDao()`。

2. **状态管理统一（消除状态三重存储）**
   - 推荐方案：**单一可观察 Store（AppStorage 仅放真正全局项：colorMode / breakpoint / mode）+ 聚焦的 ViewModel**。
   - 用 ArkUI 状态管理 V2（`@ObservedV2`/`@Trace`）或把 `WeaverViewModel` 拆成多个 `@Observed` 子模型（见 2.1/四），让子组件直接 `@ObjectLink` 订阅细粒度字段，**删除 `PcShell` 的 ~33 个镜像 `@State` 与 `syncFromVm()`**。

3. **导航统一**
   - PC 壳内部视图切换保留 `EditorViewMode` 状态机（合理）；跨页流转统一用 `Navigation` 组件 + `NavPathStack`，替代零散 `router.pushUrl`，便于传参与回溯。

4. **设计令牌单一来源**
   - 合并两套调色板为 `common/.../constants/Colors.ets`（或独立 `DesignTokens`），`PcDesignTokens.ets` 仅引用、不重新定义；统一 `PcColors`/`pcColors`/`PcColorSet` 命名（建议只留 `PcColors` 类 + `PcColorSet` 接口）。

5. **模块边界收紧**
   - `ExportService`（文件 IO）从 `pclayout/` 移到 `features/editor` 或独立 `features/io`；`AgentSheet` 的业务统计逻辑抽到 ViewModel/Repository。

---

## 四、模块解耦方向

| 解耦项 | 现状 | 目标 |
|---|---|---|
| 持久访问 | UI 内 `new Dao()` ~39–50 处 | 经 Repository 接口，DI 注入 |
| `WeaverViewModel` | 上帝对象（6 DAO+定时器+UI 态） | 拆为 `BookVM` / `EditorVM`（含撤销/自动保存/冲刺）/ `MaterialVM` / `GraphVM`，各自 `@Observed` |
| `PcEditorZone` | 48 `@State` + 40 prop 巨型组件 | 拆为 `EditorPane` / `MaterialPane` / `GraphPane` / `FindReplaceBar` 子组件，通过 `@ObjectLink` 订阅细分 VM |
| `ExportService` | 置于 `pclayout/` | 移入 `features/editor` 或独立 IO 模块 |
| 孤儿手机页 | 4 个不可达平行实现 | **建议删除**（与 PC 流重叠）；若需手机端，改为响应式布局复用同一套 ViewModel/组件，而非重写 |
| 错误/日志 | 散落空 catch | 统一 `Logger` + `DatabaseHelper` 迁移失败**上抛/告警**，禁止空 catch |
| `common` 复用 | 部分常量/工具重复 | `Colors`/`BreakPoint`/`IdGenerator` 收口到 `common`，feature 不重定义 |

---

## 五、可维护性改进措施

1. **`BaseDao<T>` 泛型基类**：把 6 个 DAO 复制的 CRUD 骨架抽到 `common/.../database/BaseDao.ets`，子类只覆写 `tableName`/`rowToModel`/`fromModel`；`ChapterDao` 的 17 个查询收敛为 `query(predicates)` + 少量语义化封装。
2. **统一 null 读取 helper**：`BaseDao.getColumnValue(...)` 替代三种写法。
3. **枚举化**：`BookMode`/`CharacterType`/`RelationshipType`/`GraphNodeType` 改为 `enum`，集中常量。
4. **资源外置**：中文文案抽 `string.json`，颜色/间距/圆角抽 `color.json`/`PcSpacing`/`PcRadii`，支持 i18n 与主题。
5. **命名规范**：消除 `PcColors`/`pcColors`/`PcColorSet` 近名冲突；统一 `update(model)` 签名形态。
6. **虚拟化**：列表改 `LazyForEach` + `IDataSource`（文库、章节、灵感、关系节点）。
7. **清理**：删孤儿页 / 桩（或显式标注 `@Preview` 待办）；移除死导入、no-op 回调、调试 `console.info`、`setTimeout` hack。
8. **测试基建**：用 `hypium` 为 `BaseDao`/`Repository`/`ViewModel` 用例写单测（纯逻辑层，不依赖 UI 线程），CI 跑通。

---

## 六、重构优先级排序（分阶段路线图）

> 原则：**先止血（不改进行为，只降风险）→ 再消重 → 后解耦 → 收类型/资源 → 上性能/测试**。每阶段保持可编译、可运行。

### P0 止血（低风险，建议首批）
- 目标：消除静默数据风险与明显脏代码，**不改运行行为**。
- 动作：`DatabaseHelper` 空 catch 改为 `Logger.error` + 上抛；删除 `CharacterCard` 死导入、`PcEditorZone` 调试日志与 no-op 空回调（若函数确未接，先标注 `// TODO`）；`setTimeout` hack 加注释/替换方案。
- 关键文件：`DatabaseHelper.ets`、`WeaverViewModel.ets`、`PcEditorZone.ets`、`SideDrawer.ets`、`AgentSheet.ets`。
- 验收：编译通过；迁移失败能在日志可见。

### P1 消重（中风险）
- 目标：砍掉复制粘贴，缩小变更面。
- 动作：抽 `BaseDao<T>`；`ChapterDao` 查询收敛；统一 null 读取；合并双调色板为单一 `common` 令牌。
- 关键文件：`features/*/data/*Dao.ets`、`common/.../constants/Colors.ets`、`PcDesignTokens.ets`。
- 验收：6 个 DAO 总行数显著下降；颜色引用无冲突。

### P2 解耦（高风险，核心收益）
- 目标：UI 与数据分离，消除上帝对象与三重状态。
- 动作：建 `Repository` 层 + DI；`WeaverViewModel` 拆为 4 个聚焦 VM；`PcEditorZone` 拆子组件并用 `@ObjectLink`；删 `PcShell.syncFromVm()` 与镜像 `@State`；`ExportService` 移模块；处理孤儿页（删/复活）。
- 关键文件：`WeaverViewModel.ets`、`PcShell.ets`、`PcEditorZone.ets`、`features/*/data/*Repository.ets`、`ExportService.ets`、4 个孤儿页。
- 验收：组件内 `new Dao()` 归零；单组件状态量减少；功能等价回归。

### P3 类型 / 资源收口（中风险）
- 目标：提升类型安全与可本地化。
- 动作：枚举化 `mode`/`type` 等；中文文案外置 `string.json`；间距/圆角令牌化。
- 关键文件：各 `model/*.ets`、`common/.../constants/*`、`resources/base/element/string.json`。
- 验收：`string.json` 覆盖主要文案；无裸 `string` 枚举。

### P4 性能 / 测试（中风险，收尾）
- 目标：可扩展与可持续。
- 动作：列表改 `LazyForEach`；落地 `hypium` 单测（Repository/ViewModel/BaseDao）。
- 关键文件：各列表页、`*Repository.ets`、`*Vm.ets`、新增 `test/`。
- 验收：大列表滑动流畅；核心逻辑有单测覆盖。

---

## 七、关键文件清单（重构重点）

- `common/src/main/ets/database/DatabaseHelper.ets` — 迁移空 catch、建表（P0/P1）
- `common/src/main/ets/database/BaseDao.ets`（**新增**）— DAO 基类（P1）
- `features/*/src/main/ets/data/*Dao.ets` — 继承 BaseDao、收敛查询（P1）
- `features/*/src/main/ets/data/*Repository.ets`（**新增**）— 解耦层（P2）
- `products/default/.../pclayout/WeaverViewModel.ets` — 拆 VM（P2）
- `products/default/.../pclayout/PcShell.ets` — 删镜像态/`syncFromVm`（P2）
- `products/default/.../pclayout/PcEditorZone.ets` — 拆子组件（P2）
- `products/default/.../pclayout/ExportService.ets` — 移模块（P2）
- `products/default/.../pclayout/PcDesignTokens.ets` + `common/.../constants/Colors.ets` — 合并令牌（P1）
- `products/default/src/main/ets/pages/{EditorPage,MaterialTabPage,RelationshipTabPage,MyTabPage}.ets` — 孤儿页处置（P2）
- `common/src/main/ets/model/*.ets` — 枚举化（P3）
- `products/default/src/main/resources/base/element/string.json`（**新增/扩充**）— 文案外置（P3）
- `test/`（**新增**）— hypium 单测（P4）

---

*本计划为只读评审产物，不含任何代码改动。若批准，建议从 P0 起逐阶段执行并保持每阶段可编译。*
