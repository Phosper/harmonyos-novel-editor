# P5 第三步：整篇上报时的稳定段落身份（2026-11）

- 状态：**已接入保存路径与读路径**（见 [P5 第四步](p5-write-path-2026-11.md)）；纯函数本身有独立回归
- 依据：[ADR-002](architecture/adr-002-document-session.md) §2.5（身份规则）、[P5 第二步](p5-paragraph-store-2026-11.md)
- 为什么先做这一层：编辑器目前每次上报整篇 `text + format_runs`，没有逐段命令。若直接在保存时 `createDocument` 重建，段落 id 会按行号重排，大纲/导图/来源锚刚拿到的稳定身份立刻失效。

## 1. 做了什么

[DocumentModel.ets](../entry/src/main/ets/editor/model/DocumentModel.ets) 新增：

```ts
reconcileDocument(oldModel, docId, title, text, runsJson): DocModel
```

规则：

| 变化 | id 处理 |
| --- | --- |
| 连续输入/改写一段 | 公共前缀/后缀保留；变化窗口内同长度按位置保留 id |
| 插入一段 | 新段拿新 id，前后段 id 不动 |
| 删除一段 | 删除段的 id 消失，其余段 id 不动 |
| 一段拆多段 | 左段保留原 id，右段新建 |
| 多段合一段 | 保留左段 id |
| 大窗口粘贴/整篇替换 | 不做大 LCS；按位置保留前 min 段，其余新建 |
| 行内样式 | `DocInlineRun.paraId` 随段落 id 重映射，粗体/斜体不丢 |

- 只有变化窗口超过 200×200 才放弃 LCS；普通编辑与少量增删都在窗口内完成。
- 仍然明确不是最终命令服务：撤销/重做恢复旧文本时可能给恢复段新 id，命令级撤销落地后由命令记录恢复原身份。

## 2. 验证

| 检查 | 结果 |
| --- | --- |
| `tools/document-model-regression.cjs` | 10 → **16 项**：新增改写、插入、删除、分裂、合并、行内样式重映射 6 项 |
| 全量 `tools/verify.sh --skip-build` | 15 个脚本通过，合计 **373 项**；`shell-regression` 仍为既有的 57 通过 / 7 失败 |
| `hvigorw assembleHap` | **BUILD SUCCESSFUL**，0 ERROR |

未测：真实编辑器每键上报的文本/格式组合、IME 组字中间态、撤销后的 id 变化；本轮未启动模拟器。

## 3. 下一步（已部分完成）

已完成并记录在 [P5 第四步](p5-write-path-2026-11.md)：

1. `ordinal` 按实数使用，插入取相邻中点；
2. `ChapterRepository.saveDraft` 同事务更新 `chapters` + 侧车，差异写入；
3. `loadOne` 优先读侧车投影，缺失/不一致回退旧正文；
4. `updateContent` 也走同一写入口。

仍未做：`DocumentSession` 内存模型（避免每次保存读整篇）、`content_version`、单段上限、备份 v3、命令级撤销。
