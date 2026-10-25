# 卡片内容改造：工程指南（施工前）

> 配套：`docs/design/card-content-user-journey.md`（旅程与痛点）、`docs/design/canvas-contract.md`（冻结接口）、`docs/design/canvas-implementation-report.md`（已实现与回归）。
> 状态：**设计稿，未改代码**。所有 API 签名为建议，落地前需同步契约与施工单。
> 目标：把“卡片内容”从“只能新增”补成“可捕获、可编辑、可组织、可产出、可撤销、可复用”，并且不再引入前几轮那类数据/焦点/编译回归。

## 0. 范围与非目标

**本轮范围**
- 卡片元信息编辑（标题/别名/标签/一句话）。
- 素材编辑、排序、撤销删除。
- 编辑器选区 → 卡片引文捕获（含来源/偏移/指纹）。
- 写作卡内直接「＋ 章 / ＋ 子卡」。
- 初稿打开/重生成（新建 vs 覆盖）、写作卡自身素材是否入稿。
- 卡片库类型/排序/删除/批量（P1）。
- 移动端键盘、焦点、无障碍（P1）。
- 数据唯一约束与迁移（P0 兜底）。

**暂不做**
- 多人协作/实时同步。
- 版本历史（初稿覆盖的历史版本另议）。
- 卡片类型互转（概念↔写作）——先记录为决策项。
- 图片/PDF 素材（先留字段与 UI 占位，不实现）。
- 卡片级“仅此白板覆盖”的数据模型（需要单独评审）。

## 1. 设计原则

1. **单一编辑面**：点开卡片就是编辑器，不再“只读详情 + 底部追加”。
2. **捕获优先**：内容从编辑器选区/剪贴板/拖入文本进来；手打是兜底，不是主路径。
3. **结构就地编辑**：写作卡内可直接加章、改名、插到指定位置；拖拽是快捷方式。
4. **可逆**：删除/移出/批量操作必须能撤销；不可逆动作要二次确认。
5. **状态显式**：空/加载/保存中/已保存/失败/冲突都有明确 UI，不靠 toast 猜。
6. **共享可见**：跨白板复用的卡在编辑前提示影响范围。

## 2. 现状约束与红线（必须遵守）

### 2.1 ArkTS / ArkUI
- **不支持结构类型**：接口返回值不要赋给 class 变量；不同接口之间不要直接互传（`CanvasRepository`/`AppStores` 已踩过）。
- **struct 成员名不能撞内置属性**：`onDragStart` 等已踩过；守卫已补拖拽事件名，新增成员先跑 `tools/arkts-guard.cjs`。
- **不要主动 `requestFocus`**：祖先默认不可获焦会抛 150002；用 `defaultFocus(true)`/`focusOnTouch(true)`，确需 requestFocus 必须 try/catch。素材抽屉已因此闪退过。
- **V2 状态**：`@Param` 只读；结构变更后强制换数组引用（`refreshPlacements`/`slice()`），否则 ForEach 复用旧子树。
- **禁止** any/unknown、解构、对象展开、`Object.assign`；回调参数显式类型；`build()` 内不写局部变量/console。
- **ForEach 稳定 key**：卡片用 placement.id，行用 cardId；不要用 index。

### 2.2 数据与迁移
- **建表 SQL 是字符串拼接**：每条数组元素只能有一个 `CREATE`；改 DDL 必须跑 `node tools/schema-regression.cjs`。
- **同板同卡唯一**：`canvas_placements` 目前没有唯一约束，历史上产生过重复贴放；本轮必须加唯一索引 + 迁移去重（保留子卡/被引用行，重指向子卡）。
- **父子双语义**：内存 `parentId` = 卡片 id，库 `parent_id` = 贴放 id；转换只在 Repository。
- **备份 v2**：新增字段必须可选、旧备份可恢复；恢复时 id 重映射（topic/canvas/placement/chapter）。

### 2.3 窗口与输入
- 2in1 原生三键：顶栏/抽屉/浮层右侧必须留 `captionInset`；注意 `captionInset` 目前只在 `freeWindowMode` 下非 0，最大化窗口需放宽判据（决策项）。
- 全局 `KeyboardAvoidMode.NONE`：输入控件自己避让。抽屉底部表单必须按 `keyboardHeight` 上移，或整页改 `RESIZE`（需评估编辑器）。
- 窗口拖动只在 `TouchType.Down` + `isDesktopWindow()` 调 `startWindowMove`。

## 3. 领域模型与 API 变更

### 3.1 卡片元信息编辑

新增（Store）：
```ts
interface CanvasCardPatch {
  title?: string
  aliases?: string
  tags?: string
  summary?: string
}
updateCard(cardId: string, patch: CanvasCardPatch): Promise<boolean>
```
- 校验：`title.trim()` 非空，长度 ≤ 80；`aliases` ≤ 200；`tags` 统一逗号分隔、去重、trim；`summary` ≤ 500。
- 写 `updatedAt`；乐观更新 + 入队落库；失败回滚并保留草稿。
- 共享提示：若 `occurrences(cardId).length > 1`，编辑区顶部显示“此卡在 N 块白板使用，修改会同步”。
- 类型能力：概念卡显示“别名/标签/一句话”；写作卡显示“一句话/目标/截止”？——先复用 summary，标签可隐藏（决策项）。

仓储：`CanvasRepository.updateCard(card)` 已有；补 `updateEvidence`。

### 3.2 素材编辑 / 排序 / 撤销

新增：
```ts
updateEvidence(evidenceId: string, input: CanvasEvidenceInput): Promise<boolean>
reorderEvidence(cardId: string, evidenceId: string, delta: number): Promise<void>
```
- `topic_evidence` 增加 `ord INTEGER NOT NULL DEFAULT 0`（`ensureColumns` 补列），按 `ord, createdAt` 排序；旧数据 ord=0，按 createdAt 回填。
- 编辑引文时保留 `docId/offsets/fingerprint/sourceLabel`；只改文本时更新 `quoteText` 并重算 fingerprint。
- 删除：先从内存移除并弹 5 秒撤销条；5 秒后才真正落库（或先软删 `deleted_at`）。推荐“延迟落库 + 撤销窗口”，简单且不污染查询。
- 排序：▲▼ 按钮 + 拖拽（P1）；上行/下行交换 ord，批量写。

### 3.3 引文捕获

新增服务（不放进 UI 组件）：
```ts
interface CaptureRequest {
  docId: string
  docTitle: string
  start: number
  end: number
  quoteText: string
}
class CanvasCaptureService {
  static fromSelection(controller, docId, docTitle): CaptureRequest | undefined
  static fingerprint(text: string): string   // FNV-1a/64 或等价稳定哈希
  static paragraphIndex(text: string, offset: number): number
}
```
- 入口：编辑器工具条按钮 + 选中文字浮层（二选一，决策项）+ 快捷键（桌面）。
- 流程：选中 → 选卡/新建卡 → `addEvidence(cardId, QUOTE, payload)` → toast “已加入「卡名」” + 撤销。
- `sourceLabel`：`docTitle + ' · 第 N 段'`（或章节名）。
- 跨文稿：若当前打开的不是 `docId`，先 `openChapter` 再 `reveal`；失败提示“原文已移动/修改”。
- 指纹不一致时仍跳转，但 toast “原文可能已修改”。

### 3.4 写作卡就地加章

- 写作卡底部/行区顶部加「＋ 章」；点击弹出轻量输入（标题，默认“第 N 章”）。
- 确认后：`createCard(CONCEPT, title)` → `addPlacement` 到父卡下方（或不可见临时点）→ `attachCard(newId, writingId)`。
- 子卡行内加「＋」插入同级下一章；行内双击改名（调 `updateCard`）。
- 深度上限 3：到 3 时隐藏「＋」，并提示“拆成独立写作卡”。
- 需要 Store 提供 `addChildCard(parentCardId, title, kind)` 组合命令，保证“建卡+贴放+挂父”一次成功/失败回滚。

### 3.5 初稿闭环

- **先修回归**：`CanvasPane.writeDraft` 目前仍 `nav.pop()`；全窗口下应 `closeCanvasAnimated()` 再 `openChapter`。
- 新增 `openDraft(cardId)`：`docId !== ''` → `openChapter(docId)` + 关画布；`docId === ''` → 禁用并提示“还没有初稿”。
- 重生成：
  - 弹窗三选一：「新建一篇」（默认）/「覆盖当前初稿」/「取消」。
  - 覆盖：`saveDraft(docId, content, 0, runsJson)` + 二次确认；保留旧内容到回收站或提示不可撤销（决策项）。
- 写作卡自身素材：
  - 生成前弹“包含写作卡自己的素材？”勾选（默认关）；`CanvasDraftWriter` 增加 `rootEvidence` 入参。
- 生成后：卡片显示“初稿 · 打开”，并记录 `docId`；列表/卡片同步刷新。

### 3.6 数据唯一性

- 迁移：先 `normalizeDuplicates`（已有，补重指向）→ 再建
  `CREATE UNIQUE INDEX IF NOT EXISTS ux_placement_card ON canvas_placements(canvas_id, topic_id)`。
- 启动时若索引创建失败（仍有重复），记录日志并跳过，不阻塞启动（与当前 DDL 容错策略一致）。
- `addPlacement` 内部串行查重 + 唯一索引兜底；插入冲突时回读已有行。
- 备份恢复：按 `(canvasId, cardId)` 去重，保留子卡。

## 4. 状态与命令

### 4.1 保存状态机

```text
idle → dirty → saving → saved
                 └→ error（保留草稿，可重试）
```
- 字段失焦或 500ms 防抖触发保存；同一卡串行。
- 顶部显示“保存中/已保存/保存失败·重试”；失败不关闭抽屉。
- 关闭抽屉时若有 dirty：先 flush，失败则弹“留在本页/放弃修改”。

### 4.2 撤销

- 范围：删除素材、删除卡、从白板移除、批量操作、覆盖初稿（可选）。
- 实现：`CanvasUndoStack`（容量 20），记录“操作前快照 + 反向命令”；撤销时重新落库并刷新。
- UI：底部 snackbar 5 秒，带“撤销”；连续操作合并为一条。
- 不做全局 undo/redo 时间线；编辑器 undo 保持独立。

### 4.3 捕获服务

- 只依赖 `CanvasTextEditorController` 与 `app.editor`；不持有状态。
- 失败分类：无选区/选区跨段/文档未打开/偏移失效；分别给不同提示。
- 埋点：`capture_start/success/fail(reason)`。

## 5. UI 规格

### 5.1 抽屉 = 卡片编辑器

布局（宽屏 392vp，手机全屏）：
1. 头部：标题（可编辑）、类型徽标、共享提示、关闭。
2. 元信息区（可折叠）：别名、标签、一句话。
3. 素材区：三组（引文/判断/笔记），组头带计数与「＋」；空组不显示。
4. 结构区（写作卡）：子卡数、打开初稿/重生成。
5. 底部固定：主按钮「＋ 添加素材」；危险区折叠为「更多」菜单（移出/删除）。

字段规格：
- 标题：单行、≤80、失焦保存；空则回退旧值并提示。
- 别名/标签：chip 输入（逗号/回车确认）；标签可删。
- 一句话：多行 3 行、≤500、字数提示。

素材行：
- 点击进入编辑态（原地或弹层）；引文显示出处与“跳回原文”；判断/笔记显示类型色条。
- 行尾「…」：编辑/上移/下移/删除。
- 删除后 snackbar 撤销。

### 5.2 编辑器捕获入口

- 工具条按钮「加到卡片」（图标 + 文案，桌面显示快捷键）。
- 选中文字后浮层：`加到卡片` / `复制`；浮层不遮挡选区。
- 选卡面板：最近使用 + 搜索 +「新建卡片」；显示卡片类型与所在板数。
- 成功后不跳走，保持阅读位置；toast 可撤销。

### 5.3 写作卡「＋ 章」

- 写作卡底部按钮「＋ 章」；行区顶部也放一个轻量「＋」。
- 输入弹层：标题（默认“第 N 章”）、类型固定概念卡；确认后立即出现在行尾并进入改名态。
- 深度到 3：隐藏按钮，提示“已到最深层，建议拆成独立写作卡”。

### 5.4 卡片库

- 行：类型徽标（概念/写作）、标题、别名、N 块白板、最近使用。
- 排序：最近使用/创建时间/标题；筛选：全部/概念/写作/当前板。
- 操作：放到当前板、从当前板移除、复制、删除（二次确认）、批量选择。
- 新建表单：标题 + 类型 + 一句话（可选）；创建后可直接“继续添加素材”。

### 5.5 上下文菜单

| 对象 | 桌面 | 触摸 | 菜单项 |
|---|---|---|---|
| 卡片 | 右键 | 长按 | 打开、重命名、复制、从白板移除、删除 |
| 行 | 右键 | 长按 | 打开子卡、重命名、上移/下移、移出、删除 |
| 素材 | 右键 | 长按 | 编辑、上移/下移、复制、删除 |
| 白板 | 右键 | 长按 | 重命名、删除、导出（后续） |

### 5.6 初稿

- 写作卡底部：`初稿` 状态（未生成/已生成）+「打开初稿」+「重新生成」。
- 重生成弹窗：新建/覆盖/取消；覆盖需二次确认并提示是否保留旧稿。
- 生成中禁用按钮，显示进度；失败保留原状态。

### 5.7 移动端 / 键盘 / 无障碍

- 抽屉底部表单：`translate({ y: -keyboardHeight })` 或滚动区 `paddingBottom`，保证输入框在 IME 之上。
- 底部操作条固定，内容区独立滚动；危险按钮不与“保存”相邻。
- 焦点：打开抽屉时 `defaultFocus(true)` 到标题（不要 requestFocus）；Tab 顺序：标题→别名→标签→一句话→素材→底部。
- 触控目标 ≥ 40vp；行内 ▲▼↗ 在窄屏可收进「…」。
- 读屏：字段 label、素材类型/出处、保存态都要可读；拖拽提供“上移/下移/移出”替代。

## 6. 文件级改动清单

| 阶段 | 文件 | 改动 |
|---|---|---|
| P0 | `shell/CanvasPane.ets` | `writeDraft` 去掉 `nav.pop()`，改 `closeCanvasAnimated`；初稿打开/重生成入口 |
| P0 | `shell/EvidenceDrawer.ets` | 升级编辑器：字段可编辑、保存态、素材编辑/排序/撤销、危险区 |
| P0 | `store/CanvasStore.ets` | `updateCard`、`updateEvidence`、`reorderEvidence`、`addChildCard`、undo 栈 |
| P0 | `repository/CanvasRepository.ets` | `updateEvidence`、初稿覆盖、唯一约束冲突处理 |
| P0 | `editor/CanvasSelectionBridge.ets` | 补 capture 辅助（选区→payload），接到 UI |
| P0 | `shell/EditorPane.ets` / `EditorTools.ets` | 「加到卡片」按钮/浮层 |
| P0 | `database/CanvasEvidenceDao.ets` | `ord` 列、update、reorder |
| P1 | `shell/CardLibrary.ets` | 类型徽标、排序、删除/复制、批量、从板移除 |
| P1 | `shell/TopicCard.ets` | 卡片/行上下文菜单入口、双击改名 |
| P1 | `shell/CanvasPane.ets` | 右键/长按菜单、连线入口（若保留） |
| P1 | `store/CanvasStore.ets` | 批量操作、共享提示 |
| P2 | `database/DatabaseHelper.ets` | 唯一索引 + 迁移 |
| P2 | `utils/PreferenceHelper.ets` | 卡片库排序/最近使用偏好 |
| P2 | `tools/*.cjs` | 新回归、guard 白名单 |

> 冻结文件 `model/CanvasTypes.ets` 不轻易改；若加 `ord` 排序/类型能力，先改契约再动。

## 7. 数据迁移

1. `topic_evidence` 加 `ord`（IF NOT EXISTS 检查后 ALTER），按 `created_at` 回填。
2. `canvas_placements` 去重（子卡优先/重指向）→ 建唯一索引；失败只记日志。
3. `topics` 可选加 `summary` 已有；不改。
4. 备份 version 升到 3（新增 ord/可选字段），旧备份按默认值恢复。
5. 迁移必须可重复执行；每次启动校验列存在。

## 8. 错误处理 / 日志 / 埋点

- 统一 `Logger`，禁止 console。
- 关键日志：`capture.success/fail`、`card.update`、`evidence.update`、`draft.overwrite`、`placement.dedupe`。
- 用户可见错误：短句 + 可重试；不要暴露 SQL/堆栈。
- 埋点：旅程文档 §6 的指标；事件名稳定，参数不含正文。

## 9. 测试矩阵

### 9.1 纯规则
- 现有 canvas 12 项保持；新增“加章插入位置/深度上限”。

### 9.2 数据
- 更新卡片字段：标题/别名/标签/一句话落库、updatedAt。
- 更新素材：文本/来源保留；ord 排序。
- 捕获：偏移/段号/指纹正确；跨文稿。
- 唯一约束：重复插入被拒；迁移去重+重指向。
- 初稿覆盖：旧内容替换、wordCount 更新。
- 撤销：删除素材/卡后恢复（含贴放/父子/连线）。

### 9.3 静态/UI
- guard：新成员不撞内置名、无 requestFocus、无 any/解构、导入闭环。
- shell-regression：入口存在（加到卡片、＋章、打开初稿）、captionInset、键盘避让断言。

### 9.4 设备
- 手机/平板/2in1：抽屉宽窄、键盘、三键、右键/长按。
- IME：底部表单不被遮挡；Esc 在 IME 打开时不误关。
- 长文本：5000 字素材、100 卡、拖拽帧率。
- 无障碍：读屏顺序、字段标签。

### 9.5 手工旅程脚本
按旅程文档 J1–J7 各一条，记录步骤数与卡点；P0 完成前不通过。

## 10. 实施顺序与里程碑

| 里程碑 | 内容 | 依赖 | 估算 |
|---|---|---|---|
| M0 回归修复 | `writeDraft` 关闭画布、初稿打开；重复贴放兜底 | 无 | **代码完成 2026-10-24，待构建** |
| M1 可编辑 | 卡片字段编辑 + 保存态；素材编辑/删除撤销 | M0 | **代码完成 2026-10-24（素材撤销），待构建** |
| M2 捕获 | 编辑器「加到卡片」、来源/偏移/指纹、跳回 | M1 | **代码完成 2026-10-24（同文稿跳回），待构建** |
| M3 就地结构 | 写作卡「＋章」、行内改名/插入 | M1 | **代码完成 2026-10-24（＋章）；行内改名留 M5** |
| M4 初稿闭环 | 打开/重生成/覆盖、写作卡素材入稿；覆盖撤销 | M0/M3 | **代码完成 2026-10-24，待构建** |
| M5 卡片库/菜单 | 类型/排序/复制/删除/移出/批量、长按/右键菜单、行内改名、删卡/移出撤销（已完成） | M1 | **完成 2026-10-24（静态）** |
| M6 数据与多端 | 跨文稿跳回、移动键盘、唯一索引、无障碍标签（已完成）；真机与全量走焦（未做） | M1–M5 | **完成 2026-10-24（静态）** |

> 估算按单人熟悉代码计，不含真机等待；每阶段必须带回归与交接包。

## 11. 风险与红线

| 风险 | 影响 | 缓解 |
|---|---|---|
| ArkTS 编译约束 | 返工 | 每步先小改+构建；guard 先行 |
| V2 响应式/ForEach 复用 | 内容不刷新 | 结构变更后换数组引用；加回归 |
| 唯一索引迁移失败 | 启动失败 | 先 dedupe 再建；失败跳过并记录；schema 回归 |
| 撤销实现过重 | 工期膨胀 | 先做“延迟落库+快照”，不做全量命令系统 |
| 键盘避让影响编辑器 | 布局抖动 | 只改抽屉，不动全局；真机验证 |
| 共享编辑语义未定 | 产品返工 | 先只做提示，不改模型 |
| 连线半成品 | 认知负担 | 本轮做决策：补 UI 或移除入口 |

## 12. 决策记录（2026-10-24 已拍板）

| # | 决策 | 结论 | 对施工的影响 |
|---|---|---|---|
| D1 | 引文捕获入口 | **工具条 + 选中浮层** | M2 同时做两处入口；浮层与工具条共用同一个 capture 服务 |
| D2 | 写作卡自身素材 | **生成时勾选，默认不包含** | 生成弹窗增加“包含写作卡自己的素材”开关，默认关 |
| D3 | 重生成初稿 | **默认新建，另提供「覆盖当前初稿」** | 生成弹窗三选一：新建（默认）/覆盖（二次确认）/取消 |
| D4 | 卡片连线 | **本轮不补，P2 再做；不新增任何入口** | 不实现连线创建/删除 UI；`CanvasEdges` 保留但保持空数据；文档标注“未开放”，避免半成品 |
| D5 | 卡片类型互转 | **暂不做** | 不进入本轮任务；记录到 P3 待评审 |
| D6 | 撤销范围 | **删除素材/删除卡/移出白板/批量/覆盖初稿** | Undo 栈只覆盖破坏性操作；字段编辑不进入 undo |
| D7 | 共享卡片编辑 | **编辑前提示“此卡在 N 块白板使用”** | 抽屉编辑区顶部提示；不做“仅此板覆盖”模型 |

### 12.1 由决策带来的范围调整

- **D1**：M2 增加“选中浮层”组件与定位计算；桌面工具条按钮同时存在。
- **D2/D3**：M4 的生成弹窗合并为一个对话框，含“包含写作卡素材”开关与“新建/覆盖”选择；覆盖需二次确认。
- **D4**：本轮**不新增**连线入口；`CanvasEdges` 保留渲染能力但数据为空；在实现报告“已知限制”里写明“连线未开放”。
- **D6**：覆盖初稿也进入撤销范围（覆盖前快照，撤销恢复旧稿）。
- **D7**：仅在 UI 提示，不改数据模型；后续若要做“仅此板覆盖”，单独评审。

## 13. Definition of Done（每个 P0 项）

- 交互：空/加载/保存中/已保存/失败/撤销六态齐全。
- 数据：落库可恢复；重启后一致；备份恢复不丢。
- 回归：对应 data/canvas/shell/guard 用例通过；新增用例只增不减。
- 设备：手机/平板/2in1 各走一遍旅程脚本。
- 交接：构建命令、回传清单、未验证项写进实现报告。
