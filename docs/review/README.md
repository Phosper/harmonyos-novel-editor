# Weaver 代码评审包（思路板 / 卡片内容）

> 评审对象：HarmonyOS / ArkTS / ArkUI（Stage 模型，API 26，`entry` 单模块）。
> 评审重点：思路板（Topic Canvas）与「卡片内容」新增能力，以及它们在既有写作应用里的集成方式。
> 本目录是评审入口，不替代实现文档。

## 1. 先看什么

| 顺序 | 文件 | 作用 |
|---|---|---|
| 1 | `docs/design/canvas-contract.md` | 冻结契约：Store/组件签名、五表 DDL、ArkTS 约束 |
| 2 | `docs/design/canvas-implementation-report.md` | 实际交付、M0–M6 变更、验证记录与已知限制 |
| 3 | `docs/design/card-content-user-journey.md` | 用户旅程、痛点、决策记录 |
| 4 | `docs/design/card-content-engineering-guide.md` | 改造工程指南与里程碑 |
| 5 | `docs/design/canvas-e2e-checklist.md` | 真机完整流程验收清单 |
| 6 | `docs/review/agent-skill-manifest.md` | 专家使用 Agent 评审时的技能依赖与下载地址 |

## 2. 新增/重点代码地图

| 层 | 路径 | 说明 |
|---|---|---|
| 模型/纯规则 | `entry/src/main/ets/model/CanvasTypes.ets` | 编号、深度、嵌套、展开、重排（冻结） |
| 模型/可观察 | `entry/src/main/ets/model/CanvasStoreModels.ets` | `@ObservedV2` 五表模型、补丁接口 |
| 数据 | `entry/src/main/ets/database/Canvas*Dao.ets` | 五表 DAO；唯一索引预检 |
| 仓储 | `entry/src/main/ets/repository/CanvasRepository.ets` | 父子双语义转换、快照/恢复、去重 |
| 状态 | `entry/src/main/ets/store/CanvasStore.ets` | 串行写链、选择、相机、撤销 |
| 画布 UI | `entry/src/main/ets/shell/CanvasPane.ets` | 相机/命中/拖拽/菜单/初稿弹窗 |
| 卡片 UI | `entry/src/main/ets/shell/TopicCard.ets` | C 型嵌套、行、长按/右键入口 |
| 抽屉 | `entry/src/main/ets/shell/EvidenceDrawer.ets` | 卡片编辑器、素材、跳回原文 |
| 卡片库 | `entry/src/main/ets/shell/CardLibrary.ets` | 全库、筛选/排序/批量/复制/删除 |
| 捕获 | `entry/src/main/ets/editor/CanvasCapture.ets` | 选区→引文纯计算（可 Node 回归） |
| 初稿 | `entry/src/main/ets/editor/CanvasDraftWriter.ets` | 大纲→正文+format_runs |
| 转场 | `entry/src/main/ets/shell/CanvasTransition.ets` | 全窗口一镜到底 id/动画 |

## 3. 构建与静态验证

```bash
# 工程根目录
./hvigorw.bat clean --no-daemon
./hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

```bash
# 不依赖 SDK 的 Node 回归（10 个脚本）
for f in tools/*.cjs; do node "$f" || exit 1; done
```

截至提交快照：
- Node 回归 **346 项**通过；`arkts-guard` 扫描 61 个文件。
- 最后一次真机构建尝试在 `CanvasStore.deleteCard` 的可空窄化处失败，**该处已修但尚未复跑构建**；评审请先跑一次 `assembleHap`。
- 设备上的完整交互（长按/右键、撤销快照、键盘避让、跨文稿跳回）尚未验证。

## 4. 评审关注点（建议）

1. **ArkTS 约束**：无 `any/unknown`、无解构/对象展开、结构类型、`@Param` 只读、ForEach 稳定 key。
2. **父子双语义**：内存 `parentId` = 卡片 id，库 `parent_id` = 贴放 id；转换只在 Repository。
3. **数据一致性**：同板同卡唯一索引、重复贴放读侧收敛、删卡/移出快照恢复。
4. **撤销模型**：5 秒内存快照；覆盖初稿/删卡/移出/素材删除；无全量 redo。
5. **焦点/键盘**：禁止主动 `requestFocus`（150002 闪退）；抽屉键盘避让。
6. **多设备**：2in1 三键 `captionInset`、手机全屏抽屉、平板断点。
7. **性能**：100+ 卡、命中测试 O(卡×行)、撤销快照整板读写。

## 5. 已知限制（评审时请按“已知”处理）

- 所有交互为静态完成，**未在提交前完成一次真机全流程验证**。
- 批量删除的撤销未做；批量仅支持“放到白板”。
- 跨段选择按起点段号记录。
- 覆盖初稿撤销不恢复光标位置。
- 无障碍仅补关键字段标签，未做完整走焦顺序。
- 唯一索引在旧库有重复时先跳过，等读侧清理后下次启动再建。
- `docs/design/canvas-implementation-report.md` 的 M0–M6 小节含逐项限制。

## 6. 安全与隐私

- 仓库不包含签名私钥、token、证书；数据库为本地 `relationalStore`。
- 若评审需要真机日志，请使用 `hdc shell hilog`，不要提交含个人内容的截图/文本。
