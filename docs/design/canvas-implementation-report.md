# 思路板 · 实现报告（静态完成，未构建）

> 依据：桌面 `AI-README-语流思路板实现.md`（r2）+ `docs/design/canvas-contract.md`。
> 下一轮「卡片内容」改造先读：`docs/design/card-content-user-journey.md`（旅程/痛点）与 `docs/design/card-content-engineering-guide.md`（施工指南）。
> 状态：**代码已落地、10 个 Node 回归全绿（331 项）；构建已通过、装机后暴露出 1 个建表 SQL 拼接错误，已修并补回归；待重新构建安装验证**。本机（OpenEuler）无 java/hvigorw/hdc/ohpm。
> 本文只记录「做了什么、证据是什么、还缺什么」，规格仍以施工单为准。

## 1. 结论

- 五表、DAO/Repository、CanvasStore、四点菜单入口、白板库/卡片库、C 型嵌套画布、素材抽屉、初稿生成器、编辑器选区/定位 API 全部落地。
- 新增 20 个 `.ets`（约 5900 行），编辑 12 个既有文件；`arkts-guard` 扫描面从 38 → 58 个文件、293 条相对导入。
- 本机 9 个脚本合计 **327 项**全过（guard 19 / canvas 11 / data 39 / draft 10 / device 27 / flowtext 127 / import 5 / shell 57 / window 32）。
- **构建、装机、真机手势、性能、无障碍实读全部未验证**；首次 `hvigorw assembleHap` 前不应认为功能可用。

## 2. 交付清单

### 2.1 新增

| 文件 | 行数 | 职责 |
|---|---|---|
| `model/CanvasTypes.ets` | 312 | 冻结：枚举/接口/纯规则（编号、深度、canNest、flatten、attach、remove、reorder） |
| `model/CanvasStoreModels.ets` | 128 | 5 个 `@ObservedV2` 模型 + 备份载荷 |
| `constants/CanvasSpec.ets` | 31 | 卡片宽度、缩进、30/8 阈值、缩放范围、软上限 |
| `database/CanvasBoardDao.ets` 等 5 个 | 123/91/96/103/141 | 五表 DAO（REAL 用 getDouble；素材 IN 查询） |
| `repository/CanvasRepository.ets` | 614 | 五表读写 + 删卡/删书/备份导出恢复（事务） |
| `store/CanvasStore.ets` | 647 | V2 状态、串行写链、相机、父子/排序、素材、白板库 |
| `shell/CanvasTheme.ets` | 262 | 唯一取色点（tokensFor 派生）+ 共享视图类型 |
| `shell/CanvasPane.ets` | 1090 | 画布：相机、命中、张嘴、拖拽、缩放、连线、初稿接线 |
| `shell/TopicCard.ets` | 534 | 概念卡/写作卡、C 型脊线、缩进行、▲▼↗ |
| `shell/CanvasEdges.ets` | 74 | Path 贝塞尔 + 箭头 + 标签 |
| `shell/EvidenceDrawer.ets` | 591 | 素材抽屉、三类素材、跳回原文、移除/删除 |
| `shell/CanvasDest.ets` | 256 | NavDestination、最近白板、两块浮层宿主 |
| `shell/CanvasBoardLibrary.ets` | 217 | 白板库（课程/自由、卡数、新建） |
| `shell/CardLibrary.ets` | ~208 | 全部卡片搜索、放到当前板、N 块白板 |
| `editor/CanvasDraftWriter.ets` | 166 | 大纲 → content + format_runs（不写 `#`） |
| `editor/CanvasSelectionBridge.ets` | 36 | 选区/定位的空值兜底薄封装 |

### 2.2 编辑（既有文件）

| 文件 | 改动 |
|---|---|
| `database/DatabaseHelper.ets` | 5 表 + 6 索引（全 IF NOT EXISTS） |
| `store/BackupTypes.ets` | 备份 v2：五表可选字段 |
| `store/Repos.ets` | `canvasRepo` + 事务字段 |
| `store/AppStores.ets` | `readonly canvas`、init/reloadAll/selectBook/deleteBook/destroy 挂钩、导出/恢复五表、**补 chapterIdMap** |
| `model/index.ets` | 导出画布模型/枚举/规则 |
| `shell/Navigator.ets` | `Routes.CANVAS` + `openCanvas()` |
| `shell/DocListPane.ets` | 四点菜单 `['思路板','导出','导入']`、`@Event onOpenCanvas`、index 重排 |
| `shell/AppShell.ets` / `MobileShell.ets` / `WorkspaceDest.ets` | 三宿主传 `onOpenCanvas`；两处 pageMap 加 CanvasDest；手机「更多」面板补入口 |
| `utils/PreferenceHelper.ets` | `canvas_recent_board` 读写（失败不抛） |
| `editor/flowtext/CanvasTextEditor.ets` | controller 新增 `getSelection/getSelectedText/selectRange/revealOffset`；struct 支撑方法 3 个（已获批） |
| `tools/arkts-guard.cjs` | 新增 T4（17 个画布文件） |
| `tools/shell-regression.cjs` | 2 处菜单正则 + 三宿主/最近白板断言 |
| `tools/data-regression.cjs` | 装具补 5 表 + 11 个画布用例 |

## 3. 验证证据（本机，工程根目录）

```text
arkts-guard.cjs              → 19 checks passed (58 files scanned, 293 imports, 2 warnings)
canvas-regression.cjs        → 11 checks passed
data-regression.cjs          → 39 checks passed（28 旧 + 11 画布）
draft-regression.cjs         → 10 checks passed
flowtext-regression.cjs      → 127 checks passed（未掉项）
shell-regression.cjs         → 57 checks passed（未掉项）
device-profile-regression.cjs→ 27 checks passed
import-regression.cjs        → 5 checks passed
window-regression.cjs        → 32 checks passed
```

## 4. 数据流与接线

```text
四点菜单（DocListPane）
  → onOpenCanvas → openCanvasAnimated(ctx)：app.ui.canvasOpen = true（geometryTransition）
  → AppShell 顶层分支直接渲染 CanvasDest（铺满整个窗口，不再占第三栏/路由）
      ├ CanvasBoardLibrary（切板/新建）
      ├ CardLibrary（搜索/放到当前板）
      └ CanvasPane
          ├ 相机：app.canvas.panX/panY/zoom
          ├ TopicCard（C 型 + 行）
          ├ CanvasEdges（端点取卡/行矩形）
          └ EvidenceDrawer（素材/跳回原文/移除/删除）
                └ 写成初稿：CanvasDraftWriter → chapterRepo.createChapter(MD)
                    → saveDraft(content+runsJson) → setCardDocId → openChapter → nav.pop()
```

## 5. 关键决策与偏差（需要知道）

| # | 决策 | 原因 | 影响 |
|---|---|---|---|
| 1 | **父子的双语义**：内存/纯规则 `parentId` = 卡片 id；库 `parent_id` = 贴放 id；转换只在 Repository | 冻结规则按卡 id 写、契约表按贴放 id 写 | 后续改表/改规则必须先改契约；备份保持库内原形 |
| 2 | 层叠用 `placement.order`，不用 `z` | 只有 addPlacement 写 z，attach/detach 不维护 | 刚拖出的卡在顶层末尾，视觉在最上 |
| 3 | 备份**不导出自由白板** | 否则每本书备份都复制一份全局板 | 自由板内容不随书迁移；需产品确认 |
| 4 | 重生成**总是新建**文稿，`docId` 指向最新 | 避免覆盖丢稿；覆盖+撤销留待 P3b | 旧稿保留，卡片只记最新 |
| 5 | 写作卡自身素材**不进初稿** | 规格 §6.6 只遍历子卡 | 需要时再扩 `rootCardId` |
| 6 | 抽屉新增「从这块白板移除」 | 规格 §2.4 的第三种动作 | 移除 ≠ 删除；子卡上提 |
| 7 | `@ObservedV2 class implements *Data` 首次使用 | 让 Store 模型直接喂纯规则 | 若 hvigor 拒绝：删 `implements` 子句，结构类型仍可用 |

## 6. 已知缺口（不阻塞首跑，但要排期）

| 缺口 | 现状 | 建议 |
|---|---|---|
| 白板重命名 | 新建只有默认名 | 白板库长按/右键加改名 |
| 抽屉开合态 | `@Local`，断点切换会丢 | 需要时移入 CanvasStore |
| 卡片折叠 `collapsed` | 字段有、UI 未接 | P2 |
| 键盘 ▲▼ | 行可聚焦、Enter 打开；上下移未接 | P2 |
| 画布空白关抽屉 | 靠 ✕/Esc/切卡 | 需要命中测试区分空白 |
| 卡片标题/标签编辑 | 抽屉只读 | 需要 `updateCard` UI |
| 按落点 y 重排大纲 | 纯规则只有 delta | 先加 `canvasMoveToIndex` 再开放 |
| 软上限/世界尺寸提示 | 常量在、未接 UI | P2 |
| 跨书/全局白板 | 表结构支持，UI 未开放 | P3 |
| 图片素材 | 未做 | 产品确认后 P2 |

## 7. 构建交接包（必须回传）

```bash
# DevEco 机器（Windows / PowerShell，工程根目录）
./hvigorw.bat clean --no-daemon
./hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
./hvigorw.bat --mode module -p module=entry@ohosTest assembleHap --no-daemon
```

回传：
1. 三条命令的完整日志（首尾各 50 行，尤其首批 `ArkTS:ERROR`）；
2. `entry/build/default/outputs/` 产物列表；
3. hvigor / SDK / DevEco 版本；
4. 若失败：文件名 + 行号 + 错误码 + 前后 5 行。

**首批最可能的编译错误（按概率）**：
1. `@ObservedV2 class ... implements`（见 §5-7，删 implements 即可）；
2. `enqueue<T>` 泛型 + `this.writeChain.then(work)` 的类型推断；
3. `CanvasPaneParams` / `CanvasPane` 的 `@Require @Param` 与对象字面量；
4. `forEach/map` 回调参数漏显式类型（守卫不查编译器级别）；
5. `Path().commands()` 的字符串拼装与 `Text` 叠加层的 `position` 类型。

## 8. 设备验证（三形态，未做）

```bash
# 设备 shell
hdc install -r entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.chungu.weaver
hdc shell hilog -r && hdc shell hilog | grep -i "weaver\|jscrash"
```

必测：
- 手机：四点菜单进板、拖卡成章、行拖出、双指缩放、抽屉全屏；
- 平板/折叠：断点切换后相机与选中是否保持（相机在 store、选中在 store；抽屉开合会丢）；
- 2in1：滚轮平移、Ctrl+滚轮缩放、Enter 打开行、Esc 关抽屉；
- 真机校准：`CanvasPane` 的 `bodyTop` 基准常量（行命中/连线端点依赖它）；
- 性能：80 卡 + 60 连线，拖拽/缩放 10 秒帧率。

## 9. 未验证项（全部）

1. **未编译**：ArkTS 编译期问题一个都没排除。
2. **未装机**：安装、启动、路由、数据库建表、备份恢复都没跑过。
3. **未截图**：视觉、C 型脊线、缩进行、张嘴缺口都未见过真机效果。
4. **未测手势**：卡片/行手势优先级、按钮误触、捏合锚点。
5. **未测性能**：拖帧 O(卡×行) 命中、点阵重绘、300+ 节点。
6. **未测无障碍**：读屏文案、焦点顺序。
7. `revealOffset` 的滚动/打字机/IME 位置未验证。
8. DDL 从未真正执行；`@ObservedV2 implements` 未过编译器。


---

## 10. 构建第 1 轮（2026-10-23，DevEco 机器日志）

结果：`COMPILE RESULT:FAIL {ERROR:7 WARN:109}`，全部为可修问题；本机已按日志修复，等待第二轮。

| # | 错误码 | 位置 | 根因 | 修复 |
|---|---|---|---|---|
| 1 | 10605030 `arkts-no-structural-typing` | `CanvasRepository.ets:177` | `canvasFindPlacement` 返回 `CanvasPlacementData`，被赋给 `CanvasPlacementItem` 变量（接口→类，ArkTS 不允许） | 变量类型改为 `CanvasPlacementData` |
| 2 | 10605030 | `AppStores.ets:552` | `BackupPayloadLoose` 直接传给 `CanvasBackupLooseBundle` 形参（两个接口结构相同但名义不同） | 显式组装 `CanvasBackupLooseBundle` 对象再传 |
| 3 | 10505001 | `TopicCard.ets:46` | `@Event onDragStart` 与 `CustomComponent.onDragStart` 同名 | 改名 `onCardDragStart`（含两处调用） |
| 4 | 10505001 | `TopicCard.ets:283` | `KeyCode` 未导入 | 新增 `import { KeyCode } from '@kit.InputKit'` |
| 5 | 10505001 | `TopicCard.ets:525` | 同上 | 同上 |
| 6 | 10505001 | `CanvasPane.ets:473` | 私有方法 `onDragStart` 与内置属性同名 | 改名 `onCardDragStart`（含参数名与调用） |
| 7 | — | 日志计数 7，仅列出 6 条 | 待第二轮确认（可能是重复计数或未回显项） | 第二轮日志确认 |

附带改动：
- `tools/arkts-guard.cjs` 的保留名补入 `onDragStart / onDragEnter / onDragMove / onDragLeave / onDragEnd / onDrop`，防止再次写回同名成员。
- 修复后本机 9 个脚本仍 **327 项全过**；guard 19 项、扫描 58 文件。

**第二轮请回传**：同样的 `assembleHap` 日志（首尾各 50 行）；若仍有错，按「错误码 + 文件:行」贴回。


---

## 11. 运行时故障：数据库初始化失败（2026-10-23，已修）

现象（真机截图）：启动即显示「数据初始化失败 / SQLite: Generic error. Possible causes: Insert failed or the updated data does not exist.」

### 11.1 根因

`DatabaseHelper.createTables` 的 SQL 数组里，`relationships` 表结尾多写了一行 `' )' + ',' +`，导致 `relationships` 与 `topics` **被拼成同一条 SQL**：

```sql
CREATE TABLE IF NOT EXISTS relationships (...);
CREATE TABLE IF NOT EXISTS topics (...);   -- 被粘在上一条后面，没有独立数组元素
```

真实执行时第一条就语法错误（`near "CREATE": syntax error`），`topics` 从未创建；随后 `CREATE INDEX idx_topics_book ON topics(book_id)` 报 `no such table: topics`，`init()` 抛错，UI 显示初始化失败。ArkTS 编译器不校验 SQL 字符串，所以构建能过。

### 11.2 修复

`entry/src/main/ets/database/DatabaseHelper.ets`：把 `' )' + ',' +` 改为 `' )',`，让 `topics` 成为独立语句。

### 11.3 回归（新增）

`tools/schema-regression.cjs`（Node 内置 `node:sqlite`，4 项）：
1. 每条语句只含一个 `CREATE`（专防这次这种“两句粘一起”）；
2. 空库完整建表 + 重复执行幂等 + 11 表/6 索引齐全；
3. 旧库（仅 books/chapters）升级后 11 表齐全；
4. 画布外键能拦截悬空贴放，合法贴放能写入。

本机全量：**10 个脚本 331 项全过**（原 327 + schema 4）。

### 11.4 现场数据影响

首轮失败只创建了 `topic_evidence / canvases / canvas_placements / canvas_links`，缺 `topics` 与 `idx_topics_book`；没有任何业务数据写入。重新构建安装后 `CREATE TABLE IF NOT EXISTS topics` 会补齐，无需清库。

### 11.5 下一步

用同一条 `assembleHap` 命令重新构建 → 覆盖安装（保留数据）→ 启动；若仍失败，回传 hilog 里 `Database init failed` 或 `Schema upgrade failed: <sql>` 行。


---

## 12. 全窗口与一镜到底（2026-10-23 第二轮 UI 修复）

真机第一版暴露两个问题：画布只在第三栏、顶栏右侧控件压到系统窗口三键。

### 12.1 改动

| 项 | 改动 |
|---|---|
| 全窗口 | 新增 `UiStore.canvasOpen`；`AppShell.mainLayout` 顶层分支：`if (app.ui.canvasOpen) CanvasDest(...)`，盖住侧栏与文稿列表 |
| 一镜到底 | 新增 `shell/CanvasTransition.ets`：`CANVAS_SURFACE_ID` 共享元素 + `animateTo(springMotion(0.6,0.85), 340ms)`；源=wideBody 内容列 / MobileShell 外壳，目标=CanvasDest 根容器 |
| 关闭 | 顶栏新增 ✕；手机保留返回条；`pages/Index.ets` 新增 `onBackPress()`：`canvasOpen` 时播放逆向转场并消费返回键 |
| 三键避让 | `CanvasPaneParams.captionInset`，顶栏右侧 padding = `14 + captionInset` |
| 窗口拖动 | CanvasPane 标题区兼作拖动热区（`TouchType.Down` + `isDesktopWindow` 才调 `startWindowMove`） |
| 路由清理 | 删除 `Routes.CANVAS`、两处 pageMap 的 canvas 分支；`openCanvas()` 改为 `openCanvasAnimated(ctx)` |

### 12.2 证据

- 本机 10 个脚本 **331 项全过**；guard 扫描 59 文件（新增 CanvasTransition）。
- shell-regression 更新为 `openCanvasAnimated(this.getUIContext())`，并新增 6 条断言（全窗口分支 / geometryTransition / 两个转场函数 / captionInset / onBackPress）。

### 12.3 仍未验证

- 未重新构建/装机：`geometryTransition` 在「条件分支替换整棵子树」时是否按预期插值、返回键在 2in1 是否被 Index 捕获，都需要真机确认。
- 一镜到底的起止矩形取的是**内容列**（不含左侧栏），视觉上是“内容区长大盖住侧栏”；若想要“从四点按钮长出”，需要把 id 移到入口按钮上再调。


---

## 13. 新建卡片入口（2026-10-23 补，r5）

**问题**：`CanvasStore.createCard` 已实现，但 UI 没有任何调用点。空库时卡片库只有搜索与「放到当前白板」，新用户无法创建第一张卡。

**修复**：卡片库（`shell/CardLibrary.ets`）顶部加「＋ 新建卡片」：
- 输入标题（必填，trim 后非空才可点创建）；
- 选择类型：概念卡 / 写作卡；
- 创建 → `app.canvas.createCard(kind, title)` → 成功后交给 `onAdd(card.id)`，
  由 `CanvasDest.placeCard` 按默认落点贴到当前白板并关闭卡片库。

空态文案改为「从卡片库新建或放一张卡」/「打开卡片库 · 新建 / 放卡」。

**仍未做**：新建时不能填别名/标签/我的一句话（进抽屉补）；写作卡创建后是空卡（把卡拖进去即成章）；创建后不支持撤销。

**验证**：guard 19（59 文件）、shell 57（新增 2 条断言：`createCard` 调用与「＋ 新建卡片」文案）；全量 331 项。


---

## 14. 点击卡片闪退：requestFocus 150002（2026-10-23 已修）

**日志**（MatePad Edge / HarmonyOS 7.0.0.109 / debug / Version 1.0.0）：
`Reason: Error`、`Error name: Error`、`Error message: This component has unfocusable ancestor.`、`Error code: 150002`；
栈顶应用帧 `entry/src/main/ets/shell/EvidenceDrawer.ets:38:48`，调用方向 `libtimer → napi_call_function → UIContext.requestFocus`。

**根因**：抽屉 `aboutToAppear` 里用 `setTimeout(..., 30)` 主动
`getFocusController().requestFocus('canvas-drawer-root')`。ArkUI 要求目标节点的**祖先链可获焦**；
抽屉挂在默认不可获焦的容器里，`requestFocus` 抛 150002。异常发生在定时器回调中，无人捕获 → jscrash。

**修复**：
- 删除主动 `requestFocus`；
- 抽屉根保留 `.focusable(true)` 并加 `.defaultFocus(true)`（不抛异常，能获焦就获焦）；
- Esc 降级为“能获焦时生效”，✕ 仍是主路径；
- `shell-regression` 增加两条断言：`EvidenceDrawer` 不得出现 `requestFocus(`、必须有 `defaultFocus(true)`。

**同类风险**：编辑器里的 `requestFocus`（`CanvasTextEditor.ets:1379`）本来就在 try/catch 内，安全。
其他人写焦点逻辑时：**requestFocus 一定包 try/catch，或改用 defaultFocus / focusOnTouch**。


---

## 15. 三键避让补齐 + 白板快捷建卡（2026-10-23，r7）

### 15.1 三键避让

上一轮只给 `CanvasPane` 顶栏加了 `captionInset`，**漏了素材抽屉**：抽屉是右侧全高浮层，头部 ✕ 正好落在系统关闭按钮下面（用户截图）。
修复：`EvidenceDrawer` 新增 `@Param captionInset`，头部右侧 padding = `DRAWER_PAD + captionInset`；`CanvasPane` 把自己的 `params.captionInset` 传下去。

> 注意：`UiStore.captionInset` 目前在 `freeWindowMode=false` 时返回 0。若最大化窗口下仍被三键盖住，需要把判据放宽为「`titleButtonWidthVp > 0` 也算」；等这轮真机截图确认。

### 15.2 白板快捷建卡

顶栏新增「＋ 卡片」：
- 点开在画布右上角弹小面板（不离开白板、不打开卡片库）；
- 输入标题、选概念卡/写作卡，点「创建」；
- `app.canvas.createCard` → `addPlacement` 到**当前视口中心**（世界坐标反算），完成后提示并收起面板；
- 打开面板时会先关掉素材抽屉，避免叠层。

限制：仍只收标题 + 类型；别名/标签/摘要进抽屉再补；创建后不支持撤销。


---

## 16. 概念卡放进写作卡后看不出（2026-10-23，r8）

**预期**：概念卡拖进写作卡后，写作卡应出现一条缩进行「一、建构主义」，副标题变成「1 章 · …」，底部「1 章」。
**实测**：看起来没有变化，无法判断卡里有没有东西。

**根因（两个叠加）**：
1. `doAttach` 只原地改 `parentId`（`@Trace` 字段）就结束。`ForEach` 用 placement id 做稳定 key，写作卡子树可能复用旧的 `rows`，`TopicCard` 的 `rows`/计数没有跟着刷新；
2. `CanvasPane.onDragFinish` 在 `attachCard` 的 Promise 还没返回时就弹「已放进」，即使 attach 失败也显示成功，进一步掩盖了问题。

**修复**：
- `CanvasStore.doAttach` / `doDetach` 落库后 `await refreshPlacements()`，强制换掉 `placements` 数组引用；
- `doReorder` 写完 ord 后 `this.placements = this.placements.slice()`，让顺序变更可见；
- `onDragFinish` 把 toast 移到 `attachCard().then(ok => …)` 里：成功才说「已放进」，失败说「这张卡放不进」；
- 写作卡副标题在 `rows.length > 0` 时追加「· 含 N 张子卡」，即使行被遮挡也能一眼确认；
- `canvas-regression` 新增「概念卡放进写作卡 → 出现在子卡行且 depth=1」用例（12 项）。

**未验证**：未重新构建/装机。若重装后仍看不到行，请先确认拖放时有没有「已放进」提示，并回传 hilog 里 `attachCard` 相关行。


---

## 17. 移出后残留、再拖又回去（2026-10-23，r9）

**现象**：从写作卡移出概念卡后，写作卡里仍显示子卡行；再拖这张卡，又回到写作卡里。

**根因：同一块白板上，同一张卡存在两条贴放记录。**
- 一条是子卡（`parent_id` 指向写作卡的贴放），一条是顶层；
- 写作卡的子卡行读的是子卡那条，画布上又能看到顶层那条——截图里「行 + 独立卡」同时存在；
- `doDetach` 原来用 `placementOf(cardId)` 取**第一条**，如果第一条是顶层，`parent_id === ''` 直接 return，子卡那条没被清掉 → 残留；
- 再拖顶层那条放进写作卡时，`attachCard` 又给同一张卡加了父子关系，看起来就是“自动回去”。

**重复记录从哪来**：`addPlacement` 的存在性检查在入队之前，快速双击「放到当前白板」/「＋ 卡片」时两次都看到“还没上板”，于是插入两条（表上也没有唯一约束）。

**修复**：
- `CanvasRepository.normalizeDuplicates`：读贴放时按 `canvasId|cardId` 收敛，**优先保留有父的那条（子卡）**，多余行从库里删掉并记日志；不同白板不受影响。旧数据在下次加载时自动清理。
- `CanvasStore.doDetach`：只找 `parentId !== ''` 的那条来移出，不再被顶层重复行挡住。
- `CanvasStore.doAttach`：若该卡已经在目标父卡下，直接返回 false（防重复挂）。
- `CanvasStore.addPlacement`：加 `addingCards` 在途集合，挡住连点造成的第二条插入。
- `tools/data-regression.cjs` 新增用例：种一条重复顶层贴放 → 加载后只剩子卡那条、重复行被删；再 detach → 子卡行清空、卡回到顶层。

**数据影响**：清理只删“同板同卡”的多余贴放行，卡片、素材、连线都不动；若两条都是顶层，保留先到的那条（位置可能取第一条）。

**验证**：data 40 项、canvas 12 项，全量 333 项；未重新构建/装机。


### 17.1 追加：重复的是“父卡”时会孤立子卡（r9.1）

r9 的去重只按“子卡优先”选保留行，没处理**重复的是写作卡本身**的情况：
写作卡有两条贴放（pcA / pcB），子卡的 `parent_id` 指向 pcB，去重却留下 pcA、删掉 pcB ——
子卡父引用落空，`toCardParents` 把它降级成顶层，写作卡里的行就消失了（看起来就是“问题又出现”）。

修复：
- 删除重复行前，把它名下的子卡 `parent_id` 改指保留行（内存 + 库），并记
  `Canvas: repointed child <child> from <loser> to <winner>`；
- `removePlacementFromBoard` 的读也走同一套去重；
- attach/detach 各补一条 `Canvas: attached/detached <cardId>` 日志，便于确认动作是否真的执行。

**注意**：如果 r9 已经在设备上跑过并孤立了某条子卡，父 id 已经丢失，代码无法自动推断；
需要把这组关系**重新拖一次**，之后不会再出现。新数据不会再被孤立。


---

## 18. M0：初稿闭环回归修复（2026-10-24，代码完成，待构建）

**改动**
- `shell/CanvasPane.ets:773`：`writeDraft` 去掉路由时代的 `nav.pop()`，改为
  `app.openChapter → ensureWorkspace → closeCanvasAnimated`；全窗口下回到编辑器而不是弹路由栈。
- `shell/CanvasPane.ets:783/795`：新增 `openDraft/openDraftDoc`：有 `docId` 才允许打开；
  加载文稿 → 确保工作区在栈上 → 播放关闭转场；文稿不存在时 toast，不关闭画布。
- `shell/TopicCard.ets:60/416`：写作卡底部在 `docId !== ''` 时显示「打开初稿」；
  新增 `@Event onOpenDraft`，由 `CanvasPane` 接上。

**验证（本机，未构建/装机）**
- `shell-regression` 57 项通过，新增 4 条断言：不再出现 `nav.pop()`、写初稿走
  `closeCanvasAnimated`、存在 `openDraft`、TopicCard 暴露 `onOpenDraft`。
- 全量 10 个脚本 **334 项**通过；guard 59 文件。

**待真机确认**
1. 生成初稿后画布是否平滑收回并显示新文稿；
2. 再次进入思路板，写作卡是否出现「打开初稿」，点击是否回到同一篇；
3. 从初稿返回时路由栈是否正常（不应多一层/少一层）。


---

## 19. M1：卡片可编辑 + 素材编辑/撤销（2026-10-24，代码完成，待构建）

**交付**
- 卡片元信息可编辑：标题、别名、标签、一句话；失焦/回车保存，空白标题拒绝并回退；
  顶部显示“保存中/已保存/保存失败”；跨白板卡片显示“此卡在 N 块白板使用，修改会同步”。
  - `model/CanvasStoreModels.ets` 新增 `CanvasCardPatch`
  - `store/CanvasStore.ets:211` `updateCard`：乐观更新 + 失败回滚
  - `shell/EvidenceDrawer.ets:81` `saveCard`：无变化不写库，关闭抽屉前 flush
- 素材可就地编辑：点击「编辑」在行内展开 TextArea，保存只改正文，保留 docId/偏移/指纹/出处。
  - `database/CanvasEvidenceDao.ets:61` `updateText`
  - `repository/CanvasRepository.ets` `updateEvidenceText`
  - `store/CanvasStore.ets:251` `updateEvidenceText`
- 删除素材可撤销：删除后画布底部出现 5 秒“撤销”条；撤销按原 id 写回。
  - `store/CanvasStore.ets:504/523/534` `deleteEvidence/offerUndo/performUndo`
  - `repository/CanvasRepository.restoreEvidence`
  - `shell/CanvasPane.ets:1164/1284` `undoBar`

**验证（本机）**
- data-regression **44 项**（新增 3：updateCard、updateEvidenceText、删除+撤销）
- shell-regression 57 项（新增 6 条 M1 断言）
- 全量 10 个脚本 **337 项**；guard 59 文件。

**未做 / 已知限制**
- 本轮撤销只覆盖**素材删除**；删卡/移出白板/批量/覆盖初稿的撤销按 D6 放到 M4/M5。
- 编辑引文正文后**没有重算 fingerprint**（M2 捕获服务一起补）。
- 卡片标题在抽屉里编辑；卡片/行上的双击改名留到 M5。
- 未构建、未装机；TextInput/TextArea 在 392vp 抽屉与手机全屏下的换行、键盘遮挡需真机确认。


---

## 20. M2–M4：捕获、加章、初稿闭环（2026-10-24，代码完成，待构建）

### M2 选区 → 加到卡片
- 新增纯计算层 `editor/CanvasCapture.ets`：偏移夹取、段号、出处、FNV-1a 指纹、payload 生成；Node 回归可执行。
- 新增选卡面板 `shell/CardPicker.ets`：搜索已有卡 / 新建概念卡；**捕获不上板**。
- `shell/EditorPane.ets`：选中文字后右上浮层「选中 N 字 · 加到卡片」；`CardPicker` 落 `addEvidence(QUOTE, …)`。
- `shell/EditorTools.ets`：宽工具条在选区存在时显示「加到卡片」；精简档 ⋯ 菜单加同名项。
- 落库字段：`docId / paraIndex / startOff / endOff / fingerprint / quoteText / sourceLabel`。
- 测试：draft-regression 新增段号/出处/指纹用例；capture 空选区返回 undefined。

### M3 写作卡内直接加章
- `CanvasStore.addChildCard(parent, title, x, y)`：建卡 → 贴到当前板 → 挂父，一次调用。
- `TopicCard` 写作卡底部新增「＋ 添加一章」；默认标题「第 N 章」，落在父卡右下再挂入。
- 失败（深度到 3/不能嵌套）toast 提示；新卡留在顶层，不丢内容。
- 测试：data-regression 新增 addChildCard（建卡/贴放/挂父一次完成）。

### M4 初稿闭环
- 「写成初稿」改为弹窗：显示章数、可选「包含写作卡自己的素材」（默认关）、
  「新建一篇」/「覆盖当前初稿」/「取消」。
- `CanvasDraftWriter` 新增 `rootEvidence`：写作卡自身素材放在所有章节之前，不写标题。
- 覆盖：`chapterRepo.loadOne` 先存旧稿快照 → `saveDraft` 覆盖 → 打开文稿 → 关闭画布；
  旧稿通过全局撤销条恢复（5 秒）。
- 撤销条从 `CanvasPane` 提升到 `pages/Index.ets`，画布关闭/编辑器/列表都可见。

**验证（本机）**
- data 45 / draft 14 / shell 57 / canvas 12 / 其余不变；全量 **342 项**；guard 61 文件。
- 新增断言：捕获入口、选卡面板、加章、初稿弹窗、rootEvidence、全局撤销条。

**未验证 / 已知限制**
- 未构建、未装机。浮层位置（编辑器右上）、选卡面板在手机全屏/键盘下的高度需真机调。
- 跨文稿「跳回原文」仍未自动打开目标文稿（会提示先打开）；留到 M6。
- 覆盖初稿的撤销只恢复正文+格式边车，不恢复光标位置；撤销后需重新打开文稿才看到旧稿。
- 删卡/移出白板/批量的撤销仍未做（D6 剩余部分，M5）。
- 捕获未做“跨段选择”的段号合并语义，暂按起点段号记录。


---

## 21. M5/M6（部分）：卡片库管理、跨文稿跳回、键盘避让（2026-10-24，代码完成，待构建）

### 21.1 卡片库管理（M5 部分）
- 类型徽标（概念/写作）+ 类型筛选（全部/概念/写作）+ 排序（最近/标题）。
- 行内动作：复制、从当前白板移除、删除（两击确认）。
- `CanvasStore.duplicateCard`：复制 kind/标题/别名/标签/一句话，**不复制素材**。
- 位置：`shell/CardLibrary.ets:39/142/245/253`、`store/CanvasStore.ets:208`。

### 21.2 跨文稿跳回（M6 部分）
- `EvidenceDrawer.jumpToSource` 改为 async：目标文稿未打开时先 `openChapter` → `ensureWorkspace` →
  `closeCanvasAnimated`，360ms 后 `revealOffset`；失败 toast。
- 位置：`shell/EvidenceDrawer.ets:224/228`。

### 21.3 移动端键盘（M6 部分）
- 抽屉根在窄屏按 `app.ui.keyboardHeight` 加底部 padding，底部添加表单随键盘上移。
- 位置：`shell/EvidenceDrawer.ets:731`。

**验证（本机）**
- data 46（新增 duplicateCard）/ draft 14 / shell 57 / canvas 12 / 其余不变；全量 **343 项**；guard 61 文件。
- 新增断言：筛选/复制/两击删除/移出、跨文稿跳回、键盘 padding。

**仍未做（下一批）**
- 卡片/行的右键/长按菜单、行内双击改名（M5）。
- 批量选择与批量加入/移除（M5）。
- 删卡/移出白板/批量的撤销（D6 剩余）。
- `canvas_placements` 唯一索引迁移（M6；现有读侧去重已兜底）。
- 无障碍标签/走焦顺序、真机键盘实测（M6）。


---

## 22. M5/M6 收尾：批量放卡、唯一索引、无障碍（2026-10-24，代码完成，待构建）

### 22.1 卡片库批量
- 头部「选择」进入多选；行首 ✓/○；底部「已选 N 张 · 放到当前白板」。
- `CanvasDest.placeCards` 串行排队放卡，全部完成后再关抽屉。
- 位置：`shell/CardLibrary.ets`（selecting/selectedIds/onAddMany）、`shell/CanvasDest.ets`（placeCards）。

### 22.2 唯一索引的安全迁移
- `DatabaseHelper.ensurePlacementUniqueIndex`：先查同板同卡是否还有重复；
  没有才建 `ux_placement_card`，有则记日志跳过，等本轮读侧 `normalizeDuplicates` 清完、下次启动再建。
- 这样既有重复数据不会把启动流程炸掉，新数据最终会被唯一索引兜底。
- 位置：`database/DatabaseHelper.ets`（init 内调用）。

### 22.3 无障碍
- 抽屉编辑字段补 `accessibilityText`：卡片标题/别名/标签/一句话、素材编辑。
- 批量选择圈补“选择卡片/取消选择”。

**验证（本机）**
- schema 5（新增唯一索引预检断言）/ data 46 / shell 57 / 其余不变；全量 **344 项**；guard 61 文件。

**仍未做**
- 卡片/行右键/长按菜单、行内双击改名。
- 删卡/移出白板/批量的撤销。
- 真机验证：批量放卡位置、唯一索引在旧库上的实际效果、键盘/跨文稿跳回。


---

## 23. M5/M6 收尾：卡片菜单、行内改名、删卡/移出撤销（2026-10-24，代码完成，待构建）

### 23.1 卡片菜单与改名
- 卡片：长按（触屏）/右键（桌面）打开「卡片操作」：打开、重命名、复制、从这块白板移除、删除。
- 行：行尾新增「✎」直接重命名子卡；行右键同样打开卡片菜单。
- 重命名弹窗：`CanvasPane.renameDialog`，保存调 `updateCard`；空标题不落库。
- 位置：`shell/TopicCard.ets`（`onCardMenu/onRenameCard`、`LongPressGesture`、`onMouse`）、
  `shell/CanvasPane.ets`（`cardMenuPanel/renameDialog`）。

### 23.2 撤销补齐
- 删卡：删除前快照「卡片 + 受影响白板全部贴放/连线 + 素材」，撤销按原 id 恢复并重载。
- 从白板移除：快照整块板的贴放，撤销恢复贴放与子卡父链。
- 覆盖初稿：旧正文 + 格式边车快照，撤销恢复。
- 素材删除：已有。
- 位置：`repository/CanvasRepository.snapshotCard/restoreCardSnapshot/snapshotBoardPlacements/restoreBoardPlacements`；
  `store/CanvasStore.deleteCard/removePlacement/offerUndo/performUndo`；全局撤销条在 `pages/Index.ets`。

**验证（本机）**
- data 48（新增删卡撤销、移出撤销）；shell 57；schema 5；canvas 12；draft 14；
  全量 **346 项**；guard 61 文件。

**仍未做**
- 批量删除的撤销（当前批量只做“放到白板”，没有批量删除）。
- 全量无障碍走焦顺序。
- 真机验证全部交互（菜单长按/右键、撤销恢复、键盘、跨文稿跳回）。
