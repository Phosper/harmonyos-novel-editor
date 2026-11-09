# 功能归属与分包边界（P0）

- 基线：本地工作区（`05d7ce2` + 2026-10-25 未提交轮次），不是交接稿审核的提交版。
- 目的：在动任何目录、建任何包之前，先把"必须随应用安装的基础功能"与"以后可按需获取的功能"划清，并给出**代码可见**的依据。
- 结论只到"归属"这一层：具体包怎么切、谁依赖谁，在 P3 三份 ADR 里定。

## 1. 判定规则

1. **没有它就不能写作 / 保存 / 找回** → 基础（随应用安装）。
2. **它产生"被多个项目共用"的内容**（卡片、证据、人物、文献） → 数据放基础，界面放可选。
3. **它只是"换一种方式看同一篇正文"**（大纲、导图、演讲） → 属于工作区里的一个视图，不是独立包。
4. 补充规则（来自已复现的 R2）：**删除项目只能删"组织关系"，不能删"内容本体"**。

判定顺序：先问"卸载它之后，用户还能不能打开并继续写昨天那篇稿"；不能 → 基础。

## 2. 归属表

"删掉会怎样"一列只写在代码里能看到的后果，不含推测。

| # | 功能 | 现状入口（代码） | 归属 | 删掉 / 不装时会怎样 |
| --- | --- | --- | --- | --- |
| 1 | 正文读写、保存、撤销 | [EditorStore.ets](entry/src/main/ets/store/EditorStore.ets)、[CanvasTextEditor.ets](entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets) | 基础 | 无法写作。整个编辑链（IML 输入、排版、撤销、自动保存）都在这两层 |
| 2 | 项目 / 文稿列表 / 文库 / 搜索 | [ProjectStore.ets](entry/src/main/ets/store/ProjectStore.ets)、`DocListPane`、`ProjectSidebar` | 基础 | 无法选择或找回文稿；`AppShell.openRecentForMobile`、`openLibraryChapter` 全部失效 |
| 3 | 导出 / 导入 / JSON 备份 | `AppShell.doExport`、`AppStores.importFiles/importBackupText`、`ExportService`、`ImportService` | 基础 | 数据无法离开设备；备份载荷少 11 张表。关闭窗口前的 `flushAllStrict` 与之无关，仍可用 |
| 4 | 设置 / 主题 / 窗口与设备分流 | [UiStore.ets](entry/src/main/ets/store/UiStore.ets)、`DesignTokens`、[DeviceProfile.ets](entry/src/main/ets/utils/DeviceProfile.ets) | 基础 | 主题与稿纸无法持久化（`loadFromPrefs` 在 `init` 里）；断点/自由窗口判定失效，三形态布局退化成一套 |
| 5 | 思路板（白板/卡片/嵌套/连线/素材/初稿） | [CanvasStore.ets](entry/src/main/ets/store/CanvasStore.ets)、`CanvasRepository`、`CanvasPane`、`CanvasDest`、`TopicCard`、`EvidenceDrawer`、`CardLibrary` | **可选（board）** | 写作、导出、备份、设置仍可用。具体失效点见 §3；备份会少 `topics/topic_evidence/canvases/canvas_placements/canvas_links` |
| 6 | 卡片 / 证据的**数据** | `topics`、`topic_evidence`、`canvas_*` 五表 + `CanvasRepository` | **基础（数据）** | 若随 UI 一起删：备份丢五表；将来文献/学术也无法复用它。故数据留核心，UI 可卸 |
| 7 | 人物 / 世界观 / 灵感 / 关系的**数据** | [MaterialStore.ets](entry/src/main/ets/store/MaterialStore.ets)、[RelationStore.ets](entry/src/main/ets/store/RelationStore.ets)、`MaterialRepository`、`RelationshipRepository` | **基础（数据）** | 备份少 4 张表；删人物时关系级联（`relationships` 外键）失效。目前**没有界面**，删数据对写作无影响 |
| 8 | 人物 / 世界观 / 灵感的**界面** | 不存在（`EditorViewMode.MATERIAL` 只有枚举与死代码跳转） | 可选（novel / research） | 现在就没有入口，不装等于现状；不要为它单独造包 |
| 9 | 大纲 | 不存在；标题信息只存于 `FormatRun.heading`（1–3） | 可选（structure），视图形态 | 无影响（尚未实现） |
| 10 | 文稿绑定导图 | 不存在 | 可选（structure），视图形态 | 无影响（尚未实现） |
| 11 | 演讲（首期单屏） | 不存在 | 可选（structure） | 无影响（尚未实现） |
| 12 | 小说卷章场景 | 不存在；只有 `characters` / `world_settings` 两张表和 `BookMode` | 可选（novel） | 无影响（尚未实现）；正文仍是普通文稿 |
| 13 | 文献 / 引用 / PDF | 不存在；证据表已有 `docId/paraIndex/指纹` 可复用 | 可选（research） | 无影响（尚未实现） |
| 14 | 跨项目打开文稿 | [AppStores.openLibraryChapter](entry/src/main/ets/store/AppStores.ets) | 基础（能力） | 文库列表点其它项目的文稿会打不开；将来"跳回来源"也依赖它 |

## 3. 思路板不装时的失效点（逐条可验证）

| 失效点 | 代码位置 | 说明 |
| --- | --- | --- |
| 外壳多一个布尔分支 | [AppShell.ets:396](entry/src/main/ets/shell/AppShell.ets#L396) `if (app.ui.canvasOpen) CanvasDest(...)` | 静态 import 了 `CanvasDest`，可选页无法从主包摘除 |
| 文稿列表"更多"菜单少一项 | `DocListPane` 的四点菜单 `onOpenCanvas` | 入口直接写死 |
| 编辑区"加到卡片"失效 | [EditorPane.ets:18-21](entry/src/main/ets/shell/EditorPane.ets#L18) import `CardPicker` / `CanvasCapture` / `CanvasTypes` | **编辑核心反向依赖可选能力**，是最需要先拆的一处 |
| 启动多加载一次 | `AppStores.reloadAll` 已 `canvas.load()`，`CanvasDest.boot` 再 `load()` 一次 | 同一份数据进画布加载两遍 |
| 备份少五表 | `AppStores.exportBackupData` 的 canvasBundle | 与"备份覆盖完整作品"目标冲突，P5 一并解决 |
| 全局撤销条少一类 | [Index.ets](entry/src/main/ets/pages/Index.ets) 读 `app.canvas.undoLabel` | 可空转，但需要在拆包时改成贡献点 |

## 4. 目标依赖方向

```
entry（外壳：窗口、路由、FlowText 宿主、功能目录）
  ├─ 依赖 core_runtime（会话、命令、仓储、备份、附件）
  ├─ 依赖 feature_contracts（纯类型/无状态规则）
  └─ 按需加载 structure / board / novel / research（HSP）
        └─ 只允许依赖 core_runtime + feature_contracts
core_runtime / feature_contracts 不得反向依赖 entry 或任何可选包
```

规则：**契约包不放单例与可变状态**（多包会各持一份）；**可选包不碰正文 DAO**，只通过 `HostServices` 发命令。

## 5. 现状违规清单（P3 要逐条给责任层）

编号沿用交接稿 H01–H08，后面是本地版的位置与后果。

| 编号 | 现状 | 位置 | 后果 |
| --- | --- | --- | --- |
| V01 (H01) | 启动即把项目/素材/关系/思路板全部加载；进画布再加载一次 | `AppStores.reloadAll`、`CanvasDest.boot` | 无法"按需"，冷启动成本随功能增长；画布双读 |
| V02 (H02) | 外壳静态 import 可选页并用布尔切换 | `AppShell` 顶部 import + `canvasOpen` 分支 | 可选功能无法从主包摘除；每加一个功能多一个全局布尔 |
| V03 (H03) | 编辑页静态依赖选卡与捕获 | `EditorPane` 顶部 import | 写作核心被可选能力绑住，删除即编译失败 |
| V04 (H04) | 只有一个全局 `NavPathStack`，两份 `pageMap`，无跨包路由表 | `Navigator`、`AppShell.pageMap`、`MobileShell.pageMap` | 新增整页功能只能继续加分支；无法用系统路由跨包 |
| V05 (H05) | 全局 UI 状态承载"会话" | `UiStore.canvasOpen`、`UiStore.editorController` | 包状态 / 窗口状态 / Surface 状态混成一个布尔与一个控制器引用 |
| V06 (H06) | 视口双写：两个组件卸载都保存 | `CanvasDest.aboutToDisappear`、`CanvasPane.aboutToDisappear` | 同一次退出写两遍；将来旁栏会加剧 |
| V07 (H07) | 全局关掉键盘避让 | `AppShell.aboutToAppear` 的 `setKeyboardAvoidMode(NONE)` | 旁栏/面板无法各自定义遮挡策略 |
| V08 (H08) | UI 直接抓仓储单例 | [Repos.ets](entry/src/main/ets/store/Repos.ets) 导出 5 个仓储 + `app` 单例 | 拆包后无法注入，多个包会各持一份"同名单例" |

现状事实（本轮 grep 复核）：全仓 0 处动态 `import()`；无 `router_map.json`；`entry/oh-package.json5` 依赖为空；顶层只有 `entry` 一个模块。所以"按需挂载"目前**完全不存在**，不是"已有但没开"。

## 6. 交给 P3 的问题（本文件不做决定）

1. 卡片与文献的共享边界：`Card` 归 workspace 后，`book_id` 保留为"创建者"还是彻底移除？
2. 段落身份落地后，`chapters.content` 是保留为派生快照（搜索/导出用），还是彻底删除？
3. `feature_contracts` 里允许放哪些纯规则：`CanvasTypes` 的编号/深度规则要不要搬进去（board 与 structure 都要用）？
4. 主题与断点这类"跨包环境"由谁提供：`HostServices` 快照，还是 `AppStorage`？
5. 旁栏与整页的边界：大纲/导图算工作区视图（不占路由），文献库算整页（占路由）——是否两种都先做？

## 7. 这张表怎么复核（不靠读文档）

- 任选一行，删掉它的入口（例如注释掉 `DocListPane` 的"思路板"菜单项）→ 重编译 → 看是否还有别处引用该能力。
- 反向检查：`grep -rn "from '.*Canvas" entry/src/main/ets` 应只剩 `AppShell`、`EditorPane`、`Index`、`Canvas*` 自身。
- 每次改动后跑 `tools/verify.sh`（构建 + 10 组回归），确认没有回归。

## 8. 一页结论

1. **必须常驻四条链**：写作链（FlowText + EditorStore）、组织链（ProjectStore + 列表）、数据安全链（导出/导入/备份）、外观与分流链（UiStore + DesignTokens + DeviceProfile）。
2. **可以后装**：思路板、大纲、导图、演讲、小说界面、文献界面。
3. **共享数据必须常驻**：卡片/证据/人物/文献的数据层在核心，界面按需；删除项目只删组织关系。
4. **现在挡着拆包的是 8 处**（§5），其中 `EditorPane` 硬依赖捕获入口（V03）与外壳静态 import（V02）最该先处理；它们是 P4 样机的直接障碍。
