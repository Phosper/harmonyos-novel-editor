# P5 第四步：保存侧车与读路径切换（2026-11）

- 状态：**保存时同事务写章节行与段落侧车；打开文稿优先读侧车投影，缺失/不一致回退旧正文**；打开的文稿由 [P5 第五步 DocumentSession](p5-document-session-2026-11.md) 缓存
- 依据：[ADR-002](architecture/adr-002-document-session.md) §2.1/§2.5、[P5 第三步](p5-reconcile-2026-11.md)
- 边界：`chapters.content` 仍是旧接口与导出的事实源；侧车由同一次保存维持，不产生第二个写入口。

## 1. 做了什么

| 层 | 文件 | 说明 |
| --- | --- | --- |
| 身份对齐 | `DocumentModel.reconcileDocument` | 整篇上报时保留旧 `para_id`；插入/删除只改变化窗口，拆分/合并按 ADR 规则 |
| 排序 | `DocParagraph.ordinal` | 改为按实数使用；新段取相邻中点，避免每次回车重排后续所有行 |
| DAO | `ParagraphDao` / `ParagraphRunDao` | 增加按段更新、删除、按段删 runs；`BaseDao.safeGetDouble` 读回小数 ordinal |
| 仓储 | `ParagraphRepository.saveModel` | 差异写入：只插入/更新/删除变化的段落，只重写 runs 变化的段落 |
| 章节仓储 | `ChapterRepository` | `saveDraft` 在一个事务内更新 `chapters` + 段落侧车；`updateContent` 也走同一入口；`loadOne` 优先读侧车投影 |
| 兜底 | `ChapterRepository.loadOne` | 侧车缺失或投影正文与 `chapters.content` 不一致时回退旧正文并记日志 |

写路径顺序：

1. 读旧侧车模型（新稿/未迁移稿为 null）；
2. `reconcileDocument` 生成新模型并保留 id/ordinal；
3. 开事务：`ChapterDao.saveDraft` 更新章节行 → `ParagraphRepository.saveModel` 差异写侧车 → commit；
4. 任一步失败整体 rollback，`EditorStore` 保留 dirty 并重试。

## 2. 验证

| 检查 | 结果 |
| --- | --- |
| `tools/paragraph-migration-regression.cjs` | 7 → **15 项**：新增优先读侧车、改写/插入/删除/分裂/合并保持 id、`updateContent` 维护侧车、侧车失败时章节回滚 |
| `tools/data-regression.cjs` | **49 项通过**；替身补齐段落三表并让事务内更新仍触发既有延迟/失败钩子 |
| `tools/document-model-regression.cjs` | **16 项**（身份对齐 + ordinal 规则） |
| 全量 `tools/verify.sh --skip-build` | 15 个脚本通过，合计 **381 项**；`shell-regression` 仍为既有的 57 通过 / 7 失败 |
| `hvigorw clean` + `assembleHap` | **BUILD SUCCESSFUL**，0 ERROR / 113 WARN |
| `hvigorw assembleApp` | **BUILD SUCCESSFUL**；APP 内含 entry HAP + `core_runtime` / `structure_feature` 两个 HSP |

未测：真机保存延迟、14 万字长文的每次保存开销、IME 组字中间态、备份恢复后的首次打开；本轮未启动模拟器。

## 3. 已知限制（下一步）

1. **每次保存都读整篇侧车**：已由 `DocumentSession` 对**打开的文稿**缓解；未打开文稿（导入/备份/直接保存）仍回库读一次。完整命令级增量还没接；
2. `content_version` 还没有落库，`OpenDoc.rev` 仍承担保存时序；
3. 命令级撤销尚未落地：撤销恢复旧文本时，恢复段可能拿到新 id；
4. 备份 v3 还没有包含段落表；单段 256KB 上限未加；
5. 真实设备上的保存/打开/IME 交互未验收。

下一步：把 `DocumentSession` 与命令服务迁到 `core_runtime`，保存只传命令；随后补 `content_version`、备份 v3、命令级撤销与 R2 共享卡 membership。
