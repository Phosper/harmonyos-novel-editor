# ADR-002：正文会话、段落身份与命令

- 状态：**提议（待你批准）**；对应交接稿 A-002、决策 D01/D02/D03/D10
- 日期：2026-11
- 影响：正文存储、编辑入口、撤销、大纲/导图、来源锚、备份

## 1. 背景

1. **正文只有一个可写端**是后面所有功能的前提：大纲改标题、导图移章节、插入引文、生成初稿，
   都必须落到同一份正文上，否则会出现两套内容互相覆盖（R1 就是"绕过内存草稿直接写库"）。
2. **正文没有段落身份**：现在只有 `chapters.content`（一整段 TEXT）与 `format_runs`（偏移边车）。
   大纲/导图需要"稳定节点"，偏移一改就散架（F02）。
3. **版本语义混在一起**：`OpenDoc.rev` 同时被光标、正文、保存当"修订号"，任何一处变化都让它自增，
   没法回答"内容版本变了吗"。

## 2. 决策

### 2.1 一个会话、一个命令入口

```
UI（编辑区/大纲/导图/初稿/引用）
        │  只发命令（带目标 docId 与预期版本）
        ▼
DocumentSession（进程内单例，core_runtime 提供）
        │  校验版本 → 应用命令 → 递增 contentVersion → 通知订阅者
        ▼
DocumentCommandService（所有正文修改的唯一写入口）
        │  段落级变更 + 撤销记录
        ▼
Repository（paragraphs / documents）
        │
        ▼
保存队列（复用现有防抖 + 安全网 + 修订号守卫）
```
规则：
- 任何 UI 不得直接调用 `chapterRepo.saveDraft`（P1 已用守卫禁止生成稿直写；本 ADR 把范围扩到全部正文写入）。
- 命令返回"成功/版本过期/目标不存在"，**不抛给 UI 线程**。
- 会话只活在当前进程；窗口关闭不清数据，只释放订阅。

### 2.2 持久化模型

| 表 | 字段 | 说明 |
| --- | --- | --- |
| `documents` | id, project_id, title, kind, content_snapshot, content_version, word_count, caret, created_at, updated_at, flags… | 元信息 + **派生**快照 |
| `paragraphs` | doc_id, para_id, ordinal, kind, text, PRIMARY KEY(doc_id, para_id) | 一行一段；`ordinal` 决定顺序 |
| `paragraph_runs` | doc_id, para_id, start_off, end_off, bold, italic | 段内行内样式（相对**段内**偏移） |

- `kind` = 现行 `ParagraphKind`（0 正文 / 1–3 标题 / 4 列表 / 5、6 待办）。
- `content_snapshot` 只由命令服务在提交后生成，用于搜索、旧接口兼容与导出；**允许重建**，不当事实源。
- 空段落必须保留（`text=''` 也要有一行）——这是"标题降级/删除后仍能继续写"的前提。
- 行内引用（引文簇）在 M6 增加 `inline_refs(doc_id, para_id, start_off, end_off, ref_id)`；
  本 ADR 只预留"段内偏移"这一层，不现在建表。

### 2.3 投影（给 FlowText 用）

FlowText 继续吃 `text + FormatRun[]`（不重写编辑器内核）：

- `project()` 把段落表拼成 `text`（段间 `\n`），并把 `kind`/行内样式换算成**全文偏移**的 `FormatRun[]`；
- 同时返回 `paraIndexMap[]`（每段 `paraId` ↔ `[start,end]`），供光标/选区 ↔ 段落身份互转；
- 编辑后由会话从"改动的段落"反向增量更新（不重建全文 runs）。

明确：**投影是派生物**，不是第二个可写端；只在会话内部生成。

### 2.4 三种版本各管一件事

| 版本 | 谁递增 | 用途 |
| --- | --- | --- |
| `contentVersion` | 每次正文/格式变化 | 命令校验、锚点失效判断、导图刷新 |
| `uiRevision` | 每次"打开/切换/请求" | 丢弃迟到的异步结果（现有 `openRequestRev` 一类） |
| `saveRevision` | 每次落库快照 | 防止"落库期间又输入"被误清 dirty（现有 `doc.rev` 的职责） |

`OpenDoc.rev` 退役：光标移动不再影响内容版本。

### 2.5 命令集与身份规则

命令（最小集）：`InsertText`、`DeleteRange`、`SplitParagraph`、`MergeParagraph`、`SetParagraphKind`、
`ApplyInlineStyle`、`MoveSection`、`ReplaceGenerated`、`InsertCitation`（M6 预留）。

| 编辑 | 身份规则 |
| --- | --- |
| 段内输入/格式 | `para_id` 不变，`contentVersion++` |
| 分裂段落 | 左段保留 `para_id`，右段新建；引用/锚点按新边界重映射 |
| 合并段落 | 保留左段 id；右段的行内 run 与锚点并入左段并平移 |
| 移动章节 | 整节（标题段 + 下属段）一起移动，`para_id` 不变；**一次命令、一次撤销** |
| 复制段落/主题 | 新 `para_id`，内部引用按"复制"规则新建或保留（M6 细化） |
| 标题降级为正文 | `para_id` 不变，`kind` 改 0；导图上的覆盖项标"待处理"，不静默丢弃 |
| 折叠/缩放/主题 | 只改视图状态，`contentVersion` 不变 |

### 2.6 撤销

- 撤销单位 = 一次命令；记录"被替换的区间快照 + 段落身份"，**不再整篇快照**。
- 连续输入仍按 600ms 合并；`historyBoundary` 逻辑保留。
- 撤销/重做同样经命令服务应用，保证与保存队列、锚点、导图一致。

### 2.7 来源锚

`SourceAnchor` 改为：`docId + paraId + 段内 start/end + fingerprint + 摘录快照`。

- 解析顺序：`paraId` 命中 → 段内偏移核验 → 失败则全文文字搜索（复用 P1 的 `SourceAnchorResolver` 四态）。
- 段落被合并/分裂时，命令服务同步重映射锚点；无法映射的标"缺失"，不盲跳。

### 2.8 容量与降级

- 保留"单文档总字节 ≤ 1.75MB"的守卫（现有 `TextLimit`），改为按段落累计校验；
- 新增"单段落上限"（建议 256KB）防止一行标题塞满全文；
- 超限时命令返回 `TOO_LARGE`，由 UI 提示拆分，不写半截。

## 3. 迁移步骤（开发期一次性重建）

1. 建新表；把 `chapters` 按 `\n` 切成段落，`format_runs` 的全文偏移换算成段内偏移；
2. 生成 `documents.content_snapshot` 与 `content_version = 1`；
3. 旧 `chapters` 保留只读一个版本周期（便于对照），不参与运行；
4. 删除旧读写路径：`ChapterDao.saveDraft/updateContent` 收进命令服务内部。

## 4. 后果

- `EditorStore` 从"持有正文"降级为"持有会话引用 + 保存状态"。
- `TextEditorHost` 契约不变（仍传 docId/contentRev/loadText），但 `loadText` 改为读投影缓存。
- 备份 v3 需要同时导出段落表；恢复时重建 `para_id` 映射并重指向锚点。
- 现有 141 项 FlowText 回归必须全绿；新增 U01/U02 用例。

## 5. 本 ADR 不决定

1. 大纲/导图的具体交互（A-101/A-102）。
2. 行内引用的完整 CSL 模型（M6）。
3. 协同编辑、CRDT、事件溯源。
4. 段落表的物理分库/分文件（当前一个库足够）。

## 6. 验收

| 用例 | 期望 |
| --- | --- |
| U01 | 文稿已打开且 dirty 时生成/覆盖初稿：一次受控替换、一次撤销，自动保存不回写旧稿 |
| U02 | 重名标题、分裂/合并、复制、重排后保存重开：稳定身份与子树内容保持 |
| T02 | 三级标题在大纲提升/缩进/重排：正文、树、导图顺序一致 |
| MT12–MT14 | 大纲/导图/正文来回切换、IME 预上屏、各视图 Enter/Tab/Esc/Ctrl+Z 上下文正确 |
