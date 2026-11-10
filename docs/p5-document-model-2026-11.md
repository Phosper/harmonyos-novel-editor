# P5 第一步：段落身份与结构编辑（2026-11）

- 状态：**语义层、段落侧车、保存写通、读路径与 DocumentSession 缓存完成并有回归；尚未接命令级编辑器会话**
- 后续：[P5 第二步：段落侧车表与迁移](p5-paragraph-store-2026-11.md) · [P5 第四步：保存侧车与读路径切换](p5-write-path-2026-11.md) · [P5 第五步：DocumentSession](p5-document-session-2026-11.md)
- 依据：[ADR-002](architecture/adr-002-document-session.md) §2.5（身份规则）
- 为什么先做这一层：大纲/导图要从"只读"变"可编辑"，必须先能回答"拖动这个标题时，哪几段正文跟着走"。

## 1. 交付了什么

[DocumentModel.ets](../entry/src/main/ets/editor/model/DocumentModel.ets)（纯计算，无 DB、无 UI）：

| 能力 | 规则 |
| --- | --- |
| `createDocument(text, runsJson)` | 按换行切段，段落种类/层级取"覆盖段首的那条 run"，行内样式裁到段内。**这同时是旧数据的迁移函数** |
| `project(model)` | 段落 → `text + FormatRun[] + 段落跨度`，编辑器内核不用改 |
| `splitParagraph` | 左段**保留原 id**，右段新建 id；跨切点的行内样式一分为二；右段继承种类/层级 |
| `mergeParagraphs` | 保留**左段 id**，右段样式平移到左段后删除；相邻同一样式自动归一 |
| `setParagraphKind` | 切回正文/标题时把列表层级归零（避免残留缩进） |
| `changeIndent` | 只对列表/待办生效，钳制 0–2 |
| `sectionRange` / `moveSection` | "一节 = 标题 + 直到下一个同级或更高级标题"；移动后**一个 id 都不变** |
| `paragraphIdAt` | 全局偏移 → 段落 id（段尾归本段），给光标/锚点用 |

## 2. 验证

`tools/document-model-regression.cjs` **10 项**：

1. 解析：段落切分、种类、层级、行内样式归属；
2. 投影：文本与 run 还原、段落跨度首尾相接；
3. 分裂：id 保留/新建、粗体一分为二；
4. 合并：保留左 id、样式平移并归一；
5. 段首分裂只插入空段；
6. 改种类时缩进归零；
7. 缩进只对列表生效且钳制；
8. 一节的范围（H1 覆盖全篇 / H2 到下一个 H2 / 正文自成一段）；
9. 移动整节：顺序变化但 **id 序列不变**；
10. 偏移定位（段尾归本段、越界归最后一段）。

构建 0 错误 / 111 警告（与本阶段前持平）；回归 401 → **411 项**。

## 3. 与 ADR 的一处实现取舍

ADR-002 把文档表叫 `documents`。本轮**不改名**，仍用现有 `chapters` 作"文档表"
（它已经有 title/content/format_runs/caret 等文档级字段），段落做成侧车表 `doc_paragraphs` / `doc_runs`。

理由：改名会牵动仓储、备份、导出、画布引用等一大片，收益只是名字；而"段落有稳定 id"这个真正目标不受影响。
如果以后要改名，可以在同一层做视图映射。

## 4. 明确还没做（下一步）

| 项 | 为什么现在不做 |
| --- | --- |
| 命令级增量 | 当前保存仍按整篇文本对齐；`DocumentSession` 已缓存打开的模型，但还没有逐命令增量与跨 HSP 共享 |
| 撤销记录（命令级） | 依赖命令落地；普通整篇撤销仍可能给恢复段新 id |
| 接进编辑器的段落命令 | 编辑器现在每键上报整篇文本；改成段落命令要动 IME 与撤销，必须在有设备时做 |
| `content_version` / 单段上限 / 备份 v3 | 与命令服务、备份协议一起确定，避免先落一版错语义 |

下一步顺序：**命令服务迁入 core_runtime → `content_version` 与备份 v3 → 共享卡 membership（ADR-001）**。
段落表、迁移、写通、读路径与会话缓存已完成，见 [P5 第二步](p5-paragraph-store-2026-11.md)、[P5 第四步](p5-write-path-2026-11.md) 与 [P5 第五步](p5-document-session-2026-11.md)。

## 5. 为什么这一步值得单独提交

它把"结构编辑的语义"从 UI 与数据库里剥离出来，可以纯 Node 回归。
后面无论用 SQLite 还是换存储，这套规则（谁保留 id、样式怎么跟着走）都不用重写。
