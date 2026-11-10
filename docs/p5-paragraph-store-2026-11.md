# P5 第二步：段落侧车表与迁移（2026-11）

- 状态：**表、DAO、仓储与启动迁移完成并有回归；尚未切换读写路径、尚未接编辑器**
- 依据：[ADR-002](architecture/adr-002-document-session.md) §2.2/§2.5、[P5 第一步](p5-document-model-2026-11.md)
- 边界：`chapters.content + format_runs` 仍是唯一正文事实源；`doc_paragraphs` / `doc_runs` 是侧车，不产生第二个可写端。

## 1. 交付了什么

| 层 | 文件 | 说明 |
| --- | --- | --- |
| Schema | `database/DatabaseHelper.ets` | 新增 `doc_paragraphs`、`doc_runs`、`schema_meta` 三表与两个索引；段落随文稿级联删除，行内样式随段落级联删除 |
| 行映射 | `editor/model/DocumentModel.ets` | `DocParagraphRow` / `DocRunRow` / `DocRows` 与纯函数 `documentRows(model)`；段内偏移与 ordinal 只在这一处换算 |
| DAO | `database/ParagraphDao.ets`、`database/MetaDao.ets` | 段落/行内样式按 doc 删除、写入、按 ordinal/start_off 读回；`schema_meta` 只存一次性任务标记 |
| 仓储 | `repository/ParagraphRepository.ets` | `replaceDocument` 一次事务内“先删 runs、再删 paragraphs、再按序写回”；`loadDocument` 读回 `DocModel` |
| 迁移 | `repository/ParagraphMigration.ets` | 启动时只查“还没有段落侧车”的文稿，逐篇读全文、逐篇独立事务；失败回滚、下次启动继续 |
| 启动接线 | `store/AppStores.ets` | `dbHelper.init` 之后调用迁移；失败只记日志并保留旧正文路径，不阻塞启动 |

## 2. 表与规则

```sql
doc_paragraphs(doc_id, para_id, ordinal, kind, indent, text,
               PRIMARY KEY(doc_id, para_id),
               FOREIGN KEY(doc_id) REFERENCES chapters(id) ON DELETE CASCADE)
doc_runs(doc_id, para_id, start_off, end_off, bold, italic,
         FOREIGN KEY(doc_id, para_id) REFERENCES doc_paragraphs(doc_id, para_id) ON DELETE CASCADE)
schema_meta(meta_key PRIMARY KEY, meta_value, updated_at)
```

- `kind` 沿用 `ParagraphKind`（0 正文 / 1–3 标题 / 4 列表 / 5、6 待办）；`indent` 只对列表/待办有意义。
- `text` 不含换行；空段落也必须有一行，这是“删光正文后继续写”和“标题降级”的前提。
- `doc_runs` 的偏移相对**段首**，不存全文偏移；行内样式只存 bold/italic，段落种类在 `doc_paragraphs`。
- `schema_meta` 的 `paragraph_v1=done` 只表示初次迁移完成；每次启动仍会补后来新增的文稿，因此不会因为标记而漏新稿。

## 3. 迁移顺序

1. `SELECT c.id FROM chapters c LEFT JOIN doc_paragraphs p ON p.doc_id = c.id WHERE p.doc_id IS NULL`；
2. 逐 id 取完整正文（不一次性把全库正文搬进内存）；
3. `createDocument(id, title, content, format_runs)` 按换行拆段、把全文 run 裁成段内 run；
4. `replaceDocument` 在独立事务内删除旧侧车并写回；任一篇失败只回滚该篇，迁移标记不误置；
5. 全部完成后写 `paragraph_v1=done`；下次启动继续查缺补漏。

**明确未做**：读路径仍读 `chapters.content`；写路径仍走 `ChapterDao.saveDraft`；`content_version` 尚未落库；备份 v3 尚未包含段落表；单段 256KB 上限与命令级撤销留到写路径收口。

## 4. 验证

| 检查 | 结果 |
| --- | --- |
| `tools/paragraph-store-regression.cjs` | **10 项**：行映射、按 ordinal 读回、投影往返、空段、替换幂等、主键/外键、级联删除、元数据覆盖、插入顺序 |
| `tools/paragraph-migration-regression.cjs` | **7 项**：首次迁移、空篇、标记、重复运行、迁移后新稿自愈、读回投影、失败回滚 |
| `tools/schema-regression.cjs` | **6 项**（新增段落级联与 14 表断言） |
| `tools/arkts-guard.cjs` | **21 项**，扫描 63 个文件（新增 P5 五个文件） |
| 全量 `tools/verify.sh --skip-build` | 15 个脚本通过，合计 **367 项**；`shell-regression` 57 通过 / 7 失败 |
| `hvigorw clean` + `assembleHap` | **BUILD SUCCESSFUL**，0 ERROR / 113 WARN |
| `hvigorw assembleApp` | **BUILD SUCCESSFUL**；APP 内含 `core_runtime` / `structure_feature` 两个 HSP 与 entry HAP |

`shell-regression` 的 7 项失败已在**未改动的 HEAD 工作树**复现（`aee7f13`），与本次 P5 改动无关；原因是测试正则仍按旧版 `EditorPane` / `CanvasTextEditor` 文本匹配，当前源码已变化/含 CRLF。本轮不把它算作通过，也没有为了绿灯去改无关测试。

**未测**：真机数据库升级、实际启动迁移耗时、编辑器打开/保存切换、设备侧回归；本轮未启动模拟器。

## 5. 下一步

0. 已完成 [P5 第三步：整篇上报时的稳定段落身份](p5-reconcile-2026-11.md)；
1. 已完成 [P5 第四步：保存侧车与读路径切换](p5-write-path-2026-11.md)：`saveDraft` 同事务写章节 + 侧车，`loadOne` 优先读侧车投影；
2. **写路径收口**：`DocumentSession` 在内存持有打开的 `DocModel`，保存只做命令级差异；`DocumentCommandService` 统一写入口；
3. 补 `content_version` 与单段上限，备份 v3 纳入段落表；
4. 完成后再接编辑器命令、撤销与来源锚重映射。
