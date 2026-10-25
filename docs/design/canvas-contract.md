# 思路板 · 实现契约（冻结）

> 规格来源：桌面 `AI-README-语流思路板实现.md`（r2）。本文件只补充**文件所有权、接口签名、并行边界**。
> 任何一方不得修改「冻结文件」；接口如需变更，先改本文件并通知 Lead。

## 0. 冻结文件（只读）

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/model/CanvasTypes.ets` | 枚举、数据接口、纯规则（编号/深度/嵌套/展开/重排） |
| `entry/src/main/ets/constants/CanvasSpec.ets` | 尺寸与阈值 |
| `tools/canvas-regression.cjs` | 纯规则回归（11 项） |

## 1. 文件所有权（并行写作用域）

| 工作流 | 只能写这些文件 | 只读依赖 |
|---|---|---|
| **A 数据层** | `model/CanvasStoreModels.ets`、`database/Canvas*Dao.ets`（5 个）、`repository/CanvasRepository.ets`、`store/CanvasStore.ets`；编辑 `database/DatabaseHelper.ets`、`store/BackupTypes.ets`、`store/Repos.ets`、`store/AppStores.ets`、`model/index.ets`、`tools/data-regression.cjs` | CanvasTypes、CanvasSpec、现有 DAO/Repo/Store |
| **B 画布与卡片** | `shell/CanvasPane.ets`、`shell/TopicCard.ets`、`shell/CanvasEdges.ets`、`shell/EvidenceDrawer.ets`、`shell/CanvasTheme.ets` | CanvasTypes、CanvasSpec、CanvasStore 契约 |
| **C 外壳与库** | `shell/CanvasDest.ets`、`shell/CanvasBoardLibrary.ets`、`shell/CardLibrary.ets`；编辑 `shell/Navigator.ets`、`shell/DocListPane.ets`、`shell/AppShell.ets`、`shell/MobileShell.ets`、`shell/WorkspaceDest.ets`、`tools/arkts-guard.cjs` | B 的 CanvasPane 签名、Store 契约 |
| **D 编辑器桥** | `editor/CanvasDraftWriter.ets`、`editor/CanvasSelectionBridge.ets`；编辑 `editor/flowtext/CanvasTextEditor.ets`（仅 controller 区）；新增 `tools/draft-regression.cjs` | CanvasTypes、FormatCodec、现有 controller |
| **Lead** | 冻结文件、契约、集成修复、最终审计 | 全部 |

> 冲突处理：发现别人文件有错 → 不改，写进回报；Lead 统一改。

## 2. Store 契约（A 实现，B/C 按此调用）

文件：`entry/src/main/ets/store/CanvasStore.ets`

```ts
@ObservedV2
export class CanvasStore {
  @Trace boards: CanvasBoardItem[] = []
  @Trace cards: CanvasCardItem[] = []
  @Trace placements: CanvasPlacementItem[] = []   // 当前白板的全部贴放
  @Trace links: CanvasLinkItem[] = []
  @Trace currentBoardId: string = ''
  @Trace selectedCardId: string = ''
  @Trace panX: number = 0
  @Trace panY: number = 0
  @Trace zoom: number = 1
  @Trace loading: boolean = false
  @Trace error: string = ''

  setBookScope(bookId: string): void
  async load(): Promise<void>                    // 载入 boards + 当前板 placements/links + 全部 cards
  async selectBoard(boardId: string): Promise<void>
  async createBoard(scope: CanvasBoardScope, title: string): Promise<CanvasBoardItem | undefined>
  async createCard(kind: CanvasCardKind, title: string): Promise<CanvasCardItem | undefined>
  async deleteCard(cardId: string): Promise<void>
  async addPlacement(cardId: string, x: number, y: number): Promise<void>
  async movePlacement(cardId: string, x: number, y: number): Promise<void>
  async attachCard(cardId: string, parentCardId: string): Promise<boolean>   // 内部查 canNest
  async detachCard(cardId: string): Promise<void>
  async reorderCard(cardId: string, delta: number): Promise<void>
  async saveViewport(): Promise<void>
  async addEvidence(cardId: string, kind: CanvasEvidenceKind, payload: CanvasEvidenceInput): Promise<void>
  async deleteEvidence(evidenceId: string): Promise<void>
  async addLink(fromCardId: string, toCardId: string, kind: CanvasLinkKind, label: string): Promise<void>
  async deleteLink(linkId: string): Promise<void>

  // 同步查询（UI 直接用，内部基于 placements）
  childrenOf(parentCardId: string): CanvasPlacementItem[]
  depthOf(cardId: string): number
  cardOf(cardId: string): CanvasCardItem | undefined
  cardsOnBoard(): CanvasCardItem[]
  occurrences(cardId: string): string[]          // 出现在哪些白板标题
  canNest(dragCardId: string, targetCardId: string): boolean
}
```

`CanvasEvidenceInput`（A 定义在 StoreModels）：`{ docId: string; paraIndex: number; startOff: number; endOff: number; fingerprint: string; quoteText: string; userText: string; sourceLabel: string }`

## 3. 组件契约

```ts
// B 提供
@interface CanvasPaneParams {
  boardId: string
  onOpenCard: (cardId: string) => void
  onOpenBoardList: () => void
  onOpenCardLibrary: () => void
}
@ComponentV2 export struct CanvasPane { @Require @Param params: CanvasPaneParams }

// C 提供
@ComponentV2 export struct CanvasDest { @Param showBack: boolean = false }
@ComponentV2 export struct CanvasBoardLibrary { @Param onSelect: (boardId: string) => void; @Param onClose: () => void }
@ComponentV2 export struct CardLibrary { @Param onAdd: (cardId: string) => void; @Param onClose: () => void }
```

> ArkTS 不允许内联对象字面量类型作为 @Param；回调统一用 `@Event` 或显式接口字段。

## 4. 数据表（A 建表，字段名不可改）

```sql
topics(id, book_id, kind, title, aliases, tags, my_summary, doc_id, created_at, updated_at)
topic_evidence(id, topic_id, kind, doc_id, para_index, start_off, end_off, fingerprint,
               quote_text, user_text, source_label, created_at)
canvases(id, scope, book_id, title, pan_x, pan_y, zoom, sort_order, created_at, updated_at)
canvas_placements(id, canvas_id, topic_id, parent_id, ord, x, y, z, collapsed, style)
canvas_links(id, canvas_id, from_topic_id, to_topic_id, kind, label, created_at)
```

约束：`parent_id` 指向**同板** placement；`ord` 同级排序；删除 placement 子项上提；删除 topic 删全部 placement。

## 5. ArkTS 硬约束（本仓库守卫会拦，编译也会拦）

1. 禁 `any`/`unknown`；禁解构；禁对象展开；禁 `Object.assign`。
2. 回调/箭头函数参数必须显式类型；泛型调用显式类型（`new Map<string, number>()`、`arr.map((x: T): U => ...)`）。
3. 顶层 interface/class 名全局唯一：一律 `Canvas` 前缀。
4. `@ComponentV2` 内只用 `@Local/@Param/@Event/@Monitor/@Computed`；`@Param` 只读；不要用 `@State/@Link`。
5. 成员名不得与通用属性重名（`value/width/height/position/scale/...`）；用业务前缀。
6. `ForEach` 必须给稳定 key；嵌套 ForEach 参数名不得都叫 `item`。
7. `build()` 内不声明局部变量、不 `console`、不改状态。
8. `@Builder` 调用不得链式挂属性。
9. 新文件不得用 `console.*`（用 `utils/Logger.ets`）。
10. 相对导入必须指向真实存在且导出该符号的文件。

## 6. 验证（本机）

```bash
# 本机（工程根目录）
node tools/canvas-regression.cjs
node tools/arkts-guard.cjs
node tools/data-regression.cjs
```

- **不能构建、不能装机**（本机无 java/hvigorw/hdc/ohpm）；不要声称已验证。
- 每个工作流结束时回报：改了哪些文件、跑了哪些命令、结果、未验证项。

## 7. 里程碑

| 里程碑 | 负责 | 依赖 |
|---|---|---|
| M1 数据层可编译（静态） | A | 冻结文件 |
| M2 画布可渲染（静态） | B | M1 的 Store 签名（先按契约写） |
| M3 入口可达（静态） | C | B 的 CanvasPane 签名 |
| M4 初稿生成器（纯逻辑 + 回归） | D | 冻结文件 |
| M5 集成审查 | Lead | M1–M4 |

---

## 8. 实现后的补充（2026-10-23，以实际代码为准）

### 8.1 Store 实际多给了这些成员（B/C 已在用）

| 成员 | 用途 |
|---|---|
| `@Trace evidence` / `evidenceOf(cardId)` / `evidenceCountOf(cardId)` | 素材数与抽屉分组，避免逐卡查询 |
| `@Trace allPlacements` / `occurrences(cardId)` / `boardCardCount(boardId)` | 卡片库「N 块白板」、白板库卡数 |
| `outlineRows()` | 按 ord 深度优先展开（初稿顺序） |
| `removePlacement(cardId)` | 「从这块白板移除」：只删当前板贴放，子项上提 |
| `setCardDocId(cardId, docId)` | 写作卡记住生成的初稿 |
| `boardById` / `pickBoardId` 等私有方法 | 白板选择与最近板 |

`CanvasRepository` 另加 `updateCard(card)`（写回 doc_id）。

### 8.2 `parentId` 的双语义（重要）

- **内存 / UI / 冻结纯规则**：`parentId` = **卡片 id**（`canvasChildren`、`canvasCanNest`、`canvasFlatten` 都按卡 id）。
- **数据库 `canvas_placements.parent_id`**：= **贴放 id**。
- 转换只在 `CanvasRepository`：读侧 `toCardParents()`（找不到父项降级顶层），写侧 `saveStructure(placementId, parentPlacementId, order)`；备份保持库内原形。
- 后续若改契约把库字段改成 `topic_id`，只需改这一处映射与 DDL。

### 8.3 组件实际签名

```ts
export interface CanvasPaneParams {
  boardId: string
  onOpenCard: (cardId: string) => void
  onOpenBoardList: () => void
  onOpenCardLibrary: () => void
  onClose: () => void          // 全窗口页的 ✕，由 CanvasDest 注入一镜到底退出
  captionInset: number         // 2in1 原生三键占位（顶栏右侧避让）
}
@ComponentV2 export struct CanvasPane { @Require @Param params: CanvasPaneParams }
```

- `CanvasDest({ showBack: boolean })`；白板库/卡片库为浮层，不开新路由。
- 快捷建卡：白板顶栏「＋ 卡片」内联表单（标题 + 概念/写作），落点在当前视口中心；卡片库仍是全库入口。
- 新建卡片（卡片库）：`CardLibrary` 内「＋ 新建卡片」→ `app.canvas.createCard(kind, title)` → `onAdd` 贴到当前板。
- **思路板是全窗口分支，不是路由**：`app.ui.canvasOpen` 决定 AppShell 渲染 CanvasDest；
  源（三栏内容区 / 手机外壳）与目标（CanvasDest 根容器）共用 `CANVAS_SURFACE_ID`，
  开/关包在 `animateTo` 里（`shell/CanvasTransition.ets`）；`Routes.CANVAS` 与两处 pageMap 分支已删除。
- 初稿接线在 `CanvasPane.writeDraft`：`canvasFlatten → CanvasDraftWriter.build → chapterRepo.createChapter(MD) → saveDraft(content+runsJson) → setCardDocId → reloadChapters → openChapter → nav.pop()`。

### 8.4 守卫

`tools/arkts-guard.cjs` 新增 `T4`（17 个画布文件），扫描面 38 → 58 文件 / 293 条相对导入；`node tools/arkts-guard.cjs` 19 项通过。

## 9. 已知限制（实现后确认，不阻塞首跑）

| 限制 | 说明 |
|---|---|
| 备份不含自由白板 | 避免每本书复制全局板；需产品确认 |
| 重生成总是新建文稿 | 旧稿保留；覆盖+撤销未做 |
| 写作卡自身素材不进初稿 | 只遍历子卡 |
| 白板无重命名 | 新建只有默认名 |
| 抽屉开合态在 `@Local` | 断点切换会丢 |
| `collapsed` / 键盘 ▲▼ / 空白关抽屉 | 未接 |
| 卡片标题/标签编辑 | 抽屉只读 |
| 按落点 y 重排大纲 | 纯规则只有 delta，缺 `moveToIndex` |
| 图片素材 / 跨书白板 | 未做 |

> 完整交付清单、验证证据与构建交接包见 `docs/design/canvas-implementation-report.md`。
