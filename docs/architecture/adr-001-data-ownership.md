# ADR-001：数据所有权与删除语义

- 状态：**提议（待你批准）**；对应交接稿 A-001、决策 D04/D08
- 日期：2026-11
- 影响：schema、备份格式、删除流程、思路板与工具包边界

## 1. 背景

现在所有内容都挂在 `book_id` 上：卡片（`topics`）、白板（`canvases`）、人物、文稿……删除项目时
`CanvasRepository.deleteBookScopeRows` 会把该项目的卡片连同它在**别的项目白板上的贴放**一起删掉。
这就是交接稿复现的 R2：A 项目里建的卡被 B 项目复用，删 A 时 B 的板子上那张卡也没了。

同时备份只覆盖"当前项目"，共享卡片、自由白板、将来的文献与附件都不在包里（F05）。

## 2. 决策

### 2.1 两个层级

| 层级 | 含义 | 例子 |
| --- | --- | --- |
| Workspace（本地空间） | 这台设备上的全部内容边界；**没有云端账户含义** | 所有卡片、证据、文献、人物 |
| Project（项目） | 组织单位：把条目"收进"某个项目，并拥有自己的私有内容 | 文稿、白板、贴放、语义连线、演讲安排 |

一句话：**Project 决定"归谁组织"，Workspace 决定"内容属于谁"。**

### 2.2 谁归谁

| 实体 | 归属 | 删除项目时 |
| --- | --- | --- |
| Document（文稿正文） | Project 私有 | 随项目进回收站 → 保留 N 天后清理 |
| Board / Placement / SemanticLink | Project 私有（自由板归 Workspace） | 删 |
| PitchPlan / PitchSession | Project 私有 | 删 |
| Character / WorldSetting / Inspiration | **Workspace 共享** | 只删"项目收录关系" |
| Card（卡片） | **Workspace 共享** | 只删收录关系；卡本身保留 |
| Evidence（证据/摘录） | **Workspace 共享**，独立于 Card | 保留 |
| ResearchItem / Attachment（将来） | Workspace 共享 | 保留 |

### 2.3 成员关系表

新增 `project_items(project_id TEXT, item_kind TEXT, item_id TEXT, added_at INTEGER, PRIMARY KEY(project_id, item_kind, item_id))`。

- "项目里能看到哪些共享条目"只由这张表决定。
- `cards.book_id` 保留，但语义改为**只读的 created_by_project**（用于显示出处、审计），**不再参与删除与查询过滤**。
- 自由板 `canvases.book_id = ''` 不变。

### 2.4 删除语义矩阵

| 操作 | 动什么 | 不动什么 |
| --- | --- | --- |
| 删除项目 | 该项目文稿（回收站）、白板/贴放/连线、`project_items` 中该项目的行 | 共享卡片、证据、人物、文献；其他项目 |
| 删除卡片 | 卡片本体 + 它**在所有板**上的贴放 + 它的证据（若证据只属于它） | 其他卡片；引用它的文稿正文（保留可读降级） |
| 从白板移除 | 只删当前板的 placement；子项上提 | 卡片本体、其他板 |
| 删除文稿 | 回收站 → 保留期后清理 | 卡片、证据（其 `doc_id` 变失效，跳源时提示重新定位） |
| 删除证据 | 证据本体 | 卡片、文稿 |

> 证据归属：现在 `topic_evidence.topic_id NOT NULL` 表示"证据只属于一张卡"。
> 本 ADR 决定**保留该约束**（改造成本最低），但把它理解为"证据的创建者"；
> 多卡复用同一来源的能力放到 M6 的 `EvidenceUse`（同一证据多处使用），不在本轮改。

### 2.5 备份范围

备份 = Workspace 全量：项目与文稿、共享卡片与证据、自由板、`project_items`、
已交付扩展数据（小说/文献）、附件清单（ID/摘要/字节数/相对位置）。

- `schemaVersion` / `contentModelVersion` / `formatVersion` 分开记录。
- 恢复原空间保留原 ID；"导入副本"重映射完整引用图（现有 `restoreBundle` 的规则）。
- 较新的未知格式：**拒绝或隔离保留原包**，不忽略字段后报成功。

### 2.6 开发期变更方式

不发版、无真实用户数据 → **一次性重建**：新表建好后把旧 `cards.book_id` 灌进 `created_by_project`、
把所有现存卡片补一条 `project_items`。不写长期迁移框架。重建前自动导出一份 JSON 备份。

## 3. 后果

- `CanvasRepository.deleteBookScopeRows` 改写：不再 `cardDao.delete(card)`，只删 `project_items` 行。
- 卡片查询从 `WHERE book_id = ?` 改为 `JOIN project_items`（或 `UNION` 自由板）。
- 备份 v3 载荷结构变化，`BackupTypes` 与恢复路径同步。
- 侧栏"项目卡数"改为按 membership 统计。
- 需要新回归：U03（A 建卡、B 与自由板复用、删 A）、T06、T14、U05/U06。

## 4. 本 ADR 不决定

1. 卡片"仅此项目覆盖"（同一 `item_id` 在两个项目有不同标题）——暂不做。
2. 同一张卡在**同一块板**上出现多个实例（多实例模型）——仍是一卡一贴放。
3. 云端同步、协作、CRDT。
4. 文献与附件的具体表结构（M6 再定，本 ADR 只锁归属与删除规则）。

## 5. 验收

| 用例 | 期望 |
| --- | --- |
| U03 | A 建卡 → B 与自由板复用 → 删 A：其他板仍在，卡片内容仍可编辑 |
| T06 | 同卡两块板：改名两处同步，位置互不影响 |
| T14/U05 | 备份含共享卡片与自由板；恢复后引用一致 |
| U06 | 截断/较新格式/导入副本：明确拒绝或报告，不产生假成功 |
