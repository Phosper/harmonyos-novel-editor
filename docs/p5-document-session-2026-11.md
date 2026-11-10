# P5 第五步：DocumentSession 缓存（2026-11）

- 状态：**打开文稿的段落模型进入进程内会话；保存不再每次重读整篇侧车**
- 依据：[ADR-002](architecture/adr-002-document-session.md) §2.1/§2.2、[P5 第四步](p5-write-path-2026-11.md)
- 边界：缓存只服务"已由 `loadOne` 打开的文稿"；落库仍由 `ChapterRepository` + 保存队列完成，不是第二个写入口。

## 1. 做了什么

| 文件 | 说明 |
| --- | --- |
| `repository/DocumentSession.ets` | `Map<docId, DocModel>` + `persisted` 标记；`put/get/isPersisted/evict/clear/size` |
| `ChapterRepository.loadOne` | 侧车可用（投影正文一致）时缓存真实模型；侧车缺失/过期时缓存由旧正文建立的 fallback 模型，并标记未落库 |
| `ChapterRepository.saveDraft` | 有缓存时直接用会话模型对齐 id；缓存标记未落库（新稿/旧稿首次保存）时 `oldModel = null` 走整篇插入；提交成功后更新缓存 |
| `ChapterRepository.hardDelete` | 删除时释放该文稿会话 |
| `EditorStore` | 关闭标签、丢弃文稿、`reset` 时 `evict` / `clear` |

保存路径现在的顺序：

1. `loadOne` 读侧车/旧正文 → 建立 `DocModel` → 入会话；
2. 编辑期间 `EditorStore` 只维护整篇文本与格式边车；
3. `saveDraft` 从会话取旧模型 → `reconcileDocument` 保留 id → 事务写章节 + 差异侧车 → 提交后替换会话模型；
4. 关闭/删除/重置时释放会话，避免内存随标签增长。

## 2. 验证

| 检查 | 结果 |
| --- | --- |
| `tools/paragraph-migration-regression.cjs` | 15 → **16 项**：新增"打开后保存复用会话模型，不再读整篇侧车"；含 evict 后回库重读 |
| `tools/data-regression.cjs` | 49 → **50 项**：新增关闭标签/`reset` 释放会话 |
| 全量 `tools/verify.sh --skip-build` | 15 个脚本通过，合计 **383 项**；`shell-regression` 仍为既有的 57 通过 / 7 失败 |
| `hvigorw assembleHap` | **BUILD SUCCESSFUL**，0 ERROR |
| `tools/arkts-guard.cjs` | **21 项通过**，扫描 64 个文件 |

未测：真机长文保存耗时、多个窗口/页面共享同一文稿、IME 组字中间态、备份恢复后的首次打开；本轮未启动模拟器。

## 3. 已知限制

1. 会话在 `entry` 的 repository 层，不是 ADR-003 期望的 `core_runtime` 进程级服务；当前单窗口可用，跨 HSP 共享会话还没做；
2. 保存仍按"整篇文本 → 段落模型"做 O(n) 对齐；命令级增量还没接；
3. `content_version` 未落库；`OpenDoc.rev` 仍只承担保存时序；
4. 命令级撤销、备份 v3、单段上限、R2 共享卡 membership 仍未做；
5. 多窗口同时打开同一文稿时，各窗口缓存不共享；当前应用未承诺该场景。

## 4. 下一步

1. 把 `DocumentSession` 与命令服务迁到 `core_runtime`，由宿主服务提供，避免跨包多份运行时；
2. 引入 `contentVersion` / 命令级撤销，保存只传命令；
3. 备份 v3 纳入段落表；共享卡 membership（ADR-001）；
4. 设备可用后跑真机保存、长文、IME 与多窗口用例。
