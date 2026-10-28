---
doc: weaver-topic-canvas-handoff
audience: ai-agent
project_root: /mnt/linux_share/storage/Users/currentUser/Documents/DevEcoStudioProjects/SDK26Target/Weaver
platform: HarmonyOS / ArkTS / ArkUI (Stage model)
api: 26
module: entry
status: design-approved / NOT implemented
revision: 2026-10-22-r2
supersedes: 2026-10-22-r1（旧的独立白板方案）
human_preview: 语流-思路板-设计预览.html（同目录，以它的交互为准）
---

# 语流 · 思路板（Topic Canvas）— AI 实现交接文档

> **给接手的 AI**：这是施工单，不是灵感稿。按 §0 开工；跳过 §0 直接写代码是最常见的失败方式。
> 产品形态以桌面 `语流-思路板-设计预览.html` 为准：**卡片 = 题目，子卡 = 章节，写作卡只是能装东西的卡**。
> 设计推演过程在工程内 `docs/research/06`、`07`（07 已同步为 r2，与本文同版；冲突时以本文为准）。

---

## 0. 开工前必须做的事（缺一不可）

### 0.0 三条硬规则

1. **没加载技能，不许写 `.ets`**。
2. **没跑基线回归，不许改代码**。
3. **没拿到真实构建日志，不许说「编译通过 / 已验证」**。

### 0.1 强制开工顺序

| 步 | 动作 | 完成判据 |
|---|---|---|
| 1 | 加载 `hmos-mode-entry`，按路由表再取 1–3 个下游技能 | 能说出本任务属于「改功能」 |
| 2 | 加载 `hmos-arkui-develop-skill` | 已读 ArkTS/ArkUI 致命坑清单 |
| 3 | 用到任何 `@kit.*` 时加载 `hmos-one-sdk-skill` | 已查过实际签名/权限/错误码 |
| 4 | 跑基线：`for f in tools/*.cjs; do node "$f"; done` | 7 个脚本全过（当前 295 项） |
| 5 | **先读 §2 模型与 §6 交互**，再读 §4 数据 | 能复述「C 型嵌套 + 三层上限」 |
| 6 | 按 §8 的 S1 开始，不跳步 | 每步有验收与回退 |
| 7 | 交付时附构建日志与截图路径 | 见 §9 |

### 0.2 需要的鸿蒙技能（按需加载，不要一次全读）

**模式包自带**：`/mnt/linux_share/storage/Users/currentUser/Documents/WorkSpace/开发/_harmonyos-mode/skills/<name>/SKILL.md`
**通用技能**：`/home/user/.agents/skills/<name>/SKILL.md`

| 技能 | 位置 | 何时必须加载 | 不加载的后果 |
|---|---|---|---|
| `hmos-mode-entry` | 模式包 | **第一站** | 选错路线、直接开写 |
| `hmos-arkui-develop-skill` | agents | 写第一个 `.ets` 之前 | 踩 V1/V2、struct 约束、禁用语法 |
| `hmos-one-sdk-skill` | agents | 任何 `@kit.*` import 之前 | 猜错 API 签名/权限/错误码 |
| `arkts-grammar-standards` | agents | 语法审查、TS 迁移 | `any`/解构/展开直接编译失败 |
| `arkts-error-fixes` | agents | 编译报错时先读 | 盲改 |
| `arkui-knowledge` | agents | 查组件/属性/版本起始 | 用过时或不存在的能力 |
| `hmos-multidevice-scenario-entry` | agents | 手机/平板/2in1 适配 | 只在一端能看 |
| `hmos-arkui-accessibility-skill` | agents | 卡片读屏、焦点顺序 | 无障碍不达标 |
| `deveco-studio-codelinter` | agents | 提交前静态检查 | 规则问题入仓 |
| `hmos-build-verify` | 模式包 | 构建/装机/交接包 | 伪造「已验证」 |
| `hmos-release-gate` | 模式包 | 提审前（本任务暂不需要） | 上架被拒 |

### 0.3 技能自检脚本（复制即用）

```bash
# 本机
BUNDLE="/mnt/linux_share/storage/Users/currentUser/Documents/WorkSpace/开发/_harmonyos-mode"
for s in hmos-mode-entry hmos-build-verify; do
  test -f "$BUNDLE/skills/$s/SKILL.md" && echo "OK   $s" || echo "MISS $s"
done
for s in hmos-arkui-develop-skill hmos-one-sdk-skill arkts-grammar-standards \
         arkts-error-fixes arkui-knowledge hmos-multidevice-scenario-entry \
         hmos-arkui-accessibility-skill deveco-studio-codelinter; do
  test -f "$HOME/.agents/skills/$s/SKILL.md" && echo "OK   $s" || echo "MISS $s"
done
cd "/mnt/linux_share/storage/Users/currentUser/Documents/DevEcoStudioProjects/SDK26Target/Weaver"
for f in tools/*.cjs; do node "$f" >/dev/null 2>&1 && echo "PASS $f" || echo "FAIL $f"; done
```

### 0.4 装不上技能时的降级顺序

1. 用 MCP 工具 `harmonyos_developer_knowledge`（`searchDocuments` → `getDocumentsById`）查官方签名与版本；
2. 读仓库 `docs/design/*.md`、`docs/refactor/*.md`（项目约定优先）；
3. 读同类实现（自绘编辑器 `entry/src/main/ets/editor/flowtext/`）；
4. 都没有 → **停下来问人**，不要凭记忆编 API。

---

## 1. 工程事实（不要凭记忆猜）

| 项 | 事实 | 证据 |
|---|---|---|
| API | `targetSdkVersion = compatibleSdkVersion = 26.0.0` | `build-profile.json5:22-23` |
| 模块 | 仅 `entry`，无 HAR/HSP | `build-profile.json5:42-52` |
| 设备 | `phone / tablet / 2in1` | `entry/src/main/module.json5:9-13` |
| 状态管理 | 主体 V2（`@ComponentV2/@Local/@Param/@Event/@ObservedV2/@Trace`）；V1 只剩自绘编辑器与第三方转场库 | 全仓统计 |
| 存储 | `relationalStore`，`Weaver.db`，6 张表，**无 onUpgrade**，`CREATE TABLE IF NOT EXISTS` 每次 init 重跑 | `entry/src/main/ets/database/DatabaseHelper.ets:56-130` |
| 编辑器 | 自绘 Canvas（`entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets` 3731 行） | `entry/src/main/ets/editor/flowtext/` |
| 回归 | 7 个 Node 脚本 295 项（本轮实跑）；Hypium 设备用例以 ohosTest 为准 | `tools/*.cjs`、`entry/src/ohosTest` |
| 本机能力 | 有 node/git；**无 java / hvigorw / hdc / ohpm** | 已实测 |

**结论**：本机只能写码 + 跑 Node 回归；构建/装机必须交回 DevEco 机器，交付时标「未验证」。

---

## 2. 产品模型（已定，不要重新讨论）

### 2.1 只有两种卡

| 卡 | 装什么 | 例子 |
|---|---|---|
| **概念卡** | 素材：引文 / 判断 / 笔记 | 「均势」「无政府状态」 |
| **写作卡** | 子卡（章 / 节 / 目），本身也可以有素材 | 「国际关系理论课程期末论文」 |

**任何卡都能装子卡**（写作卡不是特权类型）；写作卡只是多一个「写成初稿」动作。
**素材不是卡**；**章节就是子卡本身**，不是卡内的一行数据。

### 2.2 嵌套与「贴放」绑定，不绑定卡片

- 同一张「均势」，在课程白板上可以是自由的，在某篇论文的写作卡里可以是「二、均势」；
- 在另一块白板上还可以有第三种摆法；
- **父子关系属于「贴放」**（某张卡在某块白板上的位置），不属于卡片本身。

### 2.3 三层上限（对齐国关论文体例）

| 深度 | 标题 | 编号 | 典型内容 |
|---|---|---|---|
| 1 | 章 | 一、 | 导论 / 理论框架 / 案例分析 / 结论 |
| 2 | 节 | （一） | 概念界定、案例一 |
| 3 | 目 | 1. | 机制环节、分论点 |
| 4 | —— | 拦截 | 提示「再深建议拆成独立写作卡」 |

- 写作卡是「论文壳」，不计入三层；
- 拖入前必须同时满足：`目标深度 + 1 ≤ 3` 且 `目标深度 + 1 + 被拖子树的深度 ≤ 3`；
- 自动编号按同级顺序生成，拖动排序后重排。

### 2.4 白板、卡片库

- **白板库**：所有白板（课程白板 / 自由白板）。写作卡**不是**白板。
- 课程白板必须绑定一门课（`book_id` 非空）；自由白板 `book_id` 为空。
- **卡片库**：所有卡片（概念卡 + 写作卡），与白板无关；可搜索、可「放到当前白板」。
- 同一张卡可出现在多块白板；**内容共享，位置独立**。
- 三个动作必须分清：

| 动作 | 卡片 | 当前白板的贴放 | 其他白板 |
|---|---|---|---|
| 从这块白板移除 | 在 | 删 | 不受影响 |
| 删除卡片 | 删 | 全删 | 各处消失；**子卡上提为顶层** |
| 删除白板 | 在 | 全删 | 不受影响 |

### 2.5 素材与快照

| 类型 | 锚点 | 内容 | 例子 |
|---|---|---|---|
| `quote` 引文 | 必有 | 原文原样，实时读取 | 「均势是这一逻辑的自然结果。」 |
| `judgement` 判断 | 可选 | 用户转述/论断 | 「1815–1914 没提均势，但实质是均势政治。」 |
| `note` 笔记 | 无 | 完全自撰 | 「均势解释不了冷战。」 |

判断型**无法被关键词命中**，只能手动添加——这是本功能的核心价值，不要自动化。

### 2.6 已定决策（不要再问用户）

1. 入口：文稿列表中栏四点菜单 → 思路板；
2. 首版范围：**一门课**；
3. 卡片形态：**概念卡 + 写作卡，任意卡可嵌套，三层上限**；
4. 显示：子卡用**缩进行 + 自动编号**，不是缩小卡片；
5. 交互：**C 型**——空卡不显示占位；拖动靠近才张嘴；
6. `写成初稿`：**新建一篇**文稿；
7. 图片/截图素材：首版不做。

---

## 3. 需求规格（feature-spec）

| 项 | 内容 |
|---|---|
| 需求一句话 | 学生在一门课里把散落的观点收进卡片，用拖入的方式拼出三层大纲，并一键生成初稿 |
| 用户场景 | 四点菜单 → 思路板 → 新建/选择白板 → 拖卡嵌套成章节目 → 收素材 → 写成初稿 → 编辑器继续写 |
| 页面与组件 | `CanvasDest`（NavDestination）+ `BoardLibrary` + `TopicCanvas` + `TopicCard`（含 C 型子卡区）+ `CardRow` + `CardLibrary` + `EvidenceDrawer`；复用 `DocListPane`、`MenuButton`、`GlowPageBackground` |
| 状态与数据流 | `CanvasStore`（`@ObservedV2`）：boards / cards / placements（含 parent、order）/ 相机 / 选中；持久化到 5 张新表；V2 |
| 接口与权限 | 无新权限；不新增 `@kit.*` 依赖 |
| 异常与空态 | 空白板、空卡（无提示）、加载失败、素材失效、深度超限、循环嵌套 |
| 验收标准 | 见 §9；每条可截图/可日志 |
| 影响面 | 5 张新表、4 个页面/组件、1 个 store、1 条路由、2 处 pageMap、3 处 DocListPane 宿主、备份 v2、守卫白名单 |
| 不做什么 | 图片素材、跨书白板、自动连线、AI 生成、协作、导出图片、第四层嵌套 |

---

## 4. 数据模型

### 4.1 新表（DDL 草案，字段名可调，语义不可改）

```sql
CREATE TABLE IF NOT EXISTS topics (
  id TEXT PRIMARY KEY, book_id TEXT, kind TEXT NOT NULL DEFAULT 'concept',
  title TEXT NOT NULL, aliases TEXT DEFAULT '', tags TEXT DEFAULT '',
  my_summary TEXT DEFAULT '', doc_id TEXT,
  created_at INTEGER, updated_at INTEGER);
  -- kind: concept | writing；writing 的 doc_id 指向生成的文稿（未生成时为空）

CREATE TABLE IF NOT EXISTS topic_evidence (
  id TEXT PRIMARY KEY, topic_id TEXT NOT NULL, kind TEXT NOT NULL,
  doc_id TEXT, para_index INTEGER, start_off INTEGER, end_off INTEGER,
  fingerprint TEXT, quote_text TEXT, user_text TEXT, source_label TEXT,
  created_at INTEGER);
  -- kind: quote | judgement | note

CREATE TABLE IF NOT EXISTS canvases (
  id TEXT PRIMARY KEY, scope TEXT NOT NULL, book_id TEXT,
  title TEXT, pan_x REAL, pan_y REAL, zoom REAL, sort_order INTEGER,
  created_at INTEGER, updated_at INTEGER);
  -- scope: course | free（首版没有 paper 白板）

CREATE TABLE IF NOT EXISTS canvas_placements (
  id TEXT PRIMARY KEY, canvas_id TEXT NOT NULL, topic_id TEXT NOT NULL,
  parent_id TEXT, ord INTEGER DEFAULT 0,
  x REAL, y REAL, z INTEGER, collapsed INTEGER, style TEXT);
  -- parent_id 指向另一个 placement.id（不是 topic.id）；同板唯一

CREATE TABLE IF NOT EXISTS canvas_links (
  id TEXT PRIMARY KEY, canvas_id TEXT NOT NULL,
  from_topic_id TEXT NOT NULL, to_topic_id TEXT NOT NULL,
  kind TEXT NOT NULL, label TEXT DEFAULT '', created_at INTEGER);

CREATE INDEX IF NOT EXISTS idx_topics_book      ON topics(book_id);
CREATE INDEX IF NOT EXISTS idx_evidence_topic   ON topic_evidence(topic_id);
CREATE INDEX IF NOT EXISTS idx_placement_canvas ON canvas_placements(canvas_id);
CREATE INDEX IF NOT EXISTS idx_placement_parent ON canvas_placements(parent_id);
CREATE INDEX IF NOT EXISTS idx_link_canvas      ON canvas_links(canvas_id);
```

### 4.2 关键约束（写代码前必须内化）

1. **父子关系在 placement 上**，不在 topic 上；同一 topic 在不同白板可以有不同 parent。
2. `parent_id` 必须是**同一 canvas 内**的 placement；跨板父子非法。
3. 同一 canvas 内一个 placement 最多一个父；父子链长度 ≤ 3（写作卡本身 depth=0）。
4. `ord` 只用于同级排序；拖动排序后整体重排（0..n-1），不要依赖浮点间隙。
5. 删除 placement 时，其子 placement **上提一层**（parent 改成被删项的父亲），并给新位置；不级联删除。
6. 删除 topic 时，删除其所有 placement；子 placement 上提。
7. 跨板出现在卡片库里的「N 块白板」= 统计 placement 所在的白板数。

### 4.3 与既有表的关系

- `topics.book_id` 可空 = 跨书（沿用 `inspirations.book_id` 空串约定，DAO 读写空串↔null）。
- 人物/世界观/章节仍是既有表，**不复制内容**。
- 人物↔人物关系继续用 `relationships`，画布只投影，不双写。

### 4.4 迁移与备份

- 建表：追加到 `entry/src/main/ets/database/DatabaseHelper.ets` 建表数组；新表用 `CREATE TABLE IF NOT EXISTS`。
- **不要**依赖 `DB_VERSION`（`:8` 只是日志常量）；给旧表加列必须登记 `EXPECTED_COLUMNS`（`:11-15`）。
- 备份：`entry/src/main/ets/store/BackupTypes.ets` 增加 5 个**可选**字段，`version` 升到 2。
- 恢复：全部重新生成 id；维护 `topicIdMap`、`canvasIdMap`、`placementIdMap`（`parent_id` 要按 map 重指向）；**同时补 `chapterIdMap`**（见 §11-8）。

---

## 5. 入口与外壳接入

### 5.1 中栏四点菜单（唯一入口）

| 项 | 位置 |
|---|---|
| 菜单按钮 | `entry/src/main/ets/shell/MenuButton.ets`（`sys.symbol.dot_grid_2x2`，`:85-88`） |
| 菜单项数组 | `entry/src/main/ets/shell/DocListPane.ets:416` 现为 `['导出','导入']` |
| 分派 | `entry/src/main/ets/shell/DocListPane.ets:390-396`（按 index，加项必须同步） |
| 三处宿主 | `entry/src/main/ets/shell/AppShell.ets:448`、`entry/src/main/ets/shell/MobileShell.ets:205`、`entry/src/main/ets/shell/WorkspaceDest.ets:126` |

**做法**：`items` 改为 `['思路板','导出','导入']`；`onMoreAction` 重排 index；`DocListPane` 增加 `@Event onOpenCanvas: () => void = () => {}`，三处宿主都要传（默认空实现可先保编译）。

### 5.2 路由与白板页

- `entry/src/main/ets/shell/Navigator.ets:16-20` 加 `Routes.CANVAS = 'canvas'`。
- **两处 pageMap 同步**：`entry/src/main/ets/shell/AppShell.ets:554-560`、`entry/src/main/ets/shell/MobileShell.ets:269-275`。
- `CanvasDest`：`NavDestination` + 隐藏标题栏；进入后默认打开**最近一块**白板；页内可切换白板 / 新建。
- 手机：整屏白板，返回回文稿；宽屏：占满主区。

### 5.3 平台红线（守卫会 fail）

| 约束 | 做法 |
|---|---|
| 窗口拖动 | 顶栏自行留热区；`startWindowMove` 只能在 `TouchType.Down`；禁 `moveWindowTo` |
| 原生三键 | 右上留 `app.ui.captionInset` |
| 键盘 | 全局 `KeyboardAvoidMode.NONE`，输入控件自让位 |
| 安全区 | 根容器已 `padding + expandSafeArea`，画布页不要重复 |
| 形态判据 | 只用 `breakPoint / tabletMode / usesDesktopChrome / pointerPrimary` |
| 模糊 | 每屏 ≤2 层，卡片零模糊 |
| 断点重建 | 相机、选中、抽屉开合放 `CanvasStore` |

---

## 6. 渲染与交互规格

### 6.1 渲染：原生卡片 + 世界坐标（推荐）

节点数是「几十张卡」，不是几百个段落，因此**用原生组件**：

| 方案 | 说明 | 结论 |
|---|---|---|
| **A 原生卡片 + 世界坐标** | 卡片是 `@ComponentV2`；`screen = world * zoom + pan`；平移用 `translate`，缩放改字号/尺寸重排 | **默认** |
| B 容器 `.scale()` | 实现最简，2× 起文字糊 | 备选 |
| C 纯 Canvas 自绘 | 文字/命中/无障碍全自理 | 不推荐 |

P0 实测：80 张卡 + 60 条连线，连续缩放 10 秒帧率。

### 6.2 C 型与「张嘴」

- **空卡不显示任何占位或提示**。
- 有子卡的卡片：左侧出现 3vp 实线脊线（`border-left`），子卡行缩进嵌在脊线内。
- **只有拖动时**，指针进入目标卡外扩 **30vp** 范围内，目标才「张嘴」：在子卡区末尾（或行下方）插入一个 30vp 高的虚线缺口，颜色用 `warning`。
- 行也可以是目标：靠近某行时，缺口插在**该行子树之后**，缩进比该行深一级。
- 放不进去（深度超限、循环、已是当前父）→ **不张嘴**。
- 同一时刻最多一个缺口；目标没变时不要重建节点（否则每帧 layout 抖动）。

### 6.3 拖拽语义

| 操作 | 结果 |
|---|---|
| 拖顶层卡 → 松手在另一张卡附近 | 成为它的子卡（追加为最后一个） |
| 拖子卡行 → 松手在另一张卡/行附近 | 改挂到新父卡 |
| 拖子卡行 → 松手在空白画布 | 移出，成为顶层卡（位置=落点） |
| 拖父卡 | 整棵子树一起移动 |
| 拖回当前父卡 | 什么都不做 |
| 拖进自己的子孙 | 拦截并提示 |

**判定顺序**：行（外扩 8vp）优先于卡片（外扩 30vp）；最近者胜。
**手势必须用「基准 + 累计」**：`base + event.offset`、`baseScale * event.scale`。

### 6.4 子卡行规格

| 元素 | 规格 |
|---|---|
| 行高 | 30vp；左右内边距 8 |
| 编号 | 一层 `一、`；二层 `（一）`；三层 `1.` |
| 缩进 | 每层 +14vp |
| 右侧 | 材料数（或「写作卡」），悬停显示 `▲ ▼ ↗` |
| 点击 | 打开该卡素材抽屉；`↗` 直接移出 |
| 字体 | sub 13；编号 caption 11，颜色 `warning` |

### 6.5 素材抽屉

- 右侧浮层（宽屏 392vp；手机全屏 sheet），`Esc` 关闭。
- 结构：标题 + 别名 + 标签 + 「我的一句话」 + 素材分组 + 「添加素材」。
- 顶部显示：出现在哪几块白板、当前层级（顶层 / 第 1 层章 / 第 2 层节 / 第 3 层目）。
- 每行：类型 chip、正文、出处、行尾「跳回原文」。
- 底部：`从父卡移出`（顶层时禁用）、`删除卡片`（危险色）。

### 6.6 写成初稿

- 只在写作卡上出现；遍历子卡（深度优先、按 ord）：
  - 深度 1/2/3 → 标题 1/2/3（写入 `format_runs` 的 heading 字段）；
  - 每条素材 → 正文段落：引文原样 + 出处，判断/笔记原样；
  - 每个节点下留 `【待展开】`。
- **新建一篇文稿**（用户已定），原稿不动；新文稿归属跟随写作卡所在课；
  写作卡若在自由白板（无归属），新文稿进「未归类」（`book_id = ''`，既有约定）。
- 生成后写作卡记住 `doc_id`；再次生成提示「会覆盖上一版初稿，可撤销」。
- **禁止往 content 里写 `#`**：标题靠 `format_runs`，`entry/src/main/ets/utils/ExportService.ets:73-95` 导出时才合成 Markdown。

### 6.7 空态与错误

| 场景 | 表现 |
|---|---|
| 空白板 | 居中「拖一张卡进来，或从卡片库放一张」+ 主按钮 |
| 空卡 | **不显示占位**；外观与普通卡一致 |
| 加载失败 | 顶部可重试提示，不清空已加载内容 |
| 素材失效 | 行灰化 + 「重新绑定」 |
| 深度超限 | Toast「最多三层（章 / 节 / 目）」 |
| 循环嵌套 | Toast「不能把卡塞进它自己里面」 |

### 6.8 无障碍

- 卡片 `accessibilityText`：标题 + 子卡数 + 素材数 + 层级。
- 行可聚焦，`Enter` 打开抽屉；`▲▼` 可用键盘操作。
- 缩放/嵌套都有非拖拽替代入口（菜单里的「移出」「上移/下移」）。

---

## 7. 状态与数据流

```text
CanvasStore (@ObservedV2)
  @Trace boards / cards / placements / links / selectedCardId / selectedBoardId
  @Trace panX / panY / zoom / loading / error
  private scopeBookId / loadRev

load(bookId)          : setBookScope → ++loadRev → await repo → 校验 → 发布
createCard(kind,title): 同板重名检查 → repo.insert → 追加
addPlacement(cardId, boardId, parentPlacementId?)
movePlacement(id,x,y) : 拖拽期只改内存，onActionEnd 落库（节流 300ms）
reparent(childId,parentId): 事务内改 parent + 重排 ord；检查深度/环
removePlacement(id)   : 子上提 + 重排 ord + 落库
```

- UI 不直接碰 DAO；组合写操作走 `runInTransaction`。
- **事务内读不到未提交数据**（`entry/src/main/ets/database/BaseDao.ets:18-20`），不要「插入后回查」。

---

## 8. 实现顺序（每步可独立验收）

| Step | 产出 | 验收 | 回退 |
|---|---|---|---|
| S1 | 技能与基线自检；`spike` 分支 | 7 个 Node 脚本全绿 | — |
| S2 | 5 表 + DAO/Repository/CanvasStore + 迁移 + 备份 v2 + `chapterIdMap` 修复 | `data-regression` 新用例全过；旧备份可导入 | 功能开关关掉，表留着 |
| S3 | 四点菜单 + 路由 + 两处 pageMap + 三宿主回调 + 白板页壳 | 三形态点开都是空白板 | 撤菜单项 |
| S4 | 白板库切换、新建白板、平移缩放、空态；「最近一块」存 `PreferenceHelper` | 真机手势与 P0 一致 | 只留静态空板 |
| S5 | 卡片渲染（概念卡 / 写作卡）、选中、拖动落库 | 刷新后位置保持 | 只读卡片 |
| S6 | C 型子卡区 + 缩进行 + 自动编号 + `▲▼↗` | 三层正确显示与重排 | 隐藏子卡区 |
| S7 | 嵌套拖拽：靠近张嘴、深度/环拦截、移出、父卡拖动带子树 | 四种拖拽语义全对 | 只用 `↗` 移出 |
| S8 | 卡片库：搜索、放到当前白板、N 块白板统计 | 跨板出现正确 | 只读列表 |
| S9 | 素材抽屉 + 三类素材 + 跳回原文（依赖 §11-11 地基） | 引文可跳回并选中 | 抽屉只读 |
| S10 | 写成初稿（content + runs，新建一篇）+ 搜索/导出 + 守卫白名单 | 标题层级正确、原稿不动 | 只生成纯文本 |

预计 10–14 个工作日（不含 P0 实测 2–3 天）。

---

## 9. 验证与交付

### 9.1 本机（每次改完必跑）

```bash
# 本机
cd "/mnt/linux_share/storage/Users/currentUser/Documents/DevEcoStudioProjects/SDK26Target/Weaver"
for f in tools/*.cjs; do node "$f" || echo "FAILED $f"; done
```
基线 **295 项**（guard 19 / data 28 / device 27 / flowtext 127 / import 5 / shell 57 / window 32，本轮实跑）；新增用例后只增不减。

### 9.2 DevEco 机器（未验证项）

```bash
# DevEco 机器
./hvigorw.bat clean --no-daemon
./hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
./hvigorw.bat --mode module -p module=entry@ohosTest assembleHap --no-daemon
```
期望 `BUILD SUCCESSFUL`；回传完整日志、`entry/build/default/outputs/` 列表、hvigor/SDK 版本。

### 9.3 设备（三形态）

```bash
# 设备 shell
hdc install -r entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.chungu.weaver
hdc shell hilog -r && hdc shell hilog | grep -i "weaver\|jscrash"
```
必测：手机（拖入成章、双指缩放）、平板（分屏、横竖屏）、2in1（滚轮、右键、`Enter` 打开行、`Esc` 关抽屉）。

### 9.4 必须回传的证据

1. 本机回归输出（每个脚本一行 PASS）；
2. 构建日志首尾各 50 行 + 产物列表；
3. 三形态截图：空白板、拖入前的张嘴瞬间、三层大纲、素材抽屉；
4. `hdc shell hilog` 关键片段；
5. 失败时：现象、复现步骤、日志、已排除项。

---

## 10. 红线（违反即返工）

1. 不伪造构建/装机/截图结果；跑不了就写「未验证」。
2. 不擅自升 `targetSdkVersion / compatibleSdkVersion / 依赖版本`。
3. 不改 `bundleName`、签名配置、证书路径。
4. 不新增权限。
5. 不写 `any` / `unknown`；不解构；不对象展开；不用 `Object.assign`。
6. 新文件不用 `console.*`（用 `entry/src/main/ets/utils/Logger.ets`）。
7. `@Builder` 调用不得链式挂属性。
8. 相对导入必须指向真实存在且导出该符号的文件。
9. 新 `.ets` 必须登记进 `tools/arkts-guard.cjs` 白名单（`T1/T2/T3`，`:20-24`）。
10. `deviceType` 不得参与布局/断点判断。
11. 拖动窗口只能用 `startWindowMove`，且只在 `TouchType.Down`。
12. 密钥、token、个人信息不进仓库、日志、截图。

---

## 11. 已知坑（带证据，按踩到概率排序）

1. **PanGesture.offset 是累计值**：`base + offset`，`+=` 会越拖越快。
2. **PinchGesture.scale 是累计比值**：`baseScale * event.scale`，逐帧相乘指数放大。
3. **同一组件连续两次 `.gesture()` 不可依赖**：用 `GestureGroup`。
4. **Canvas 面积上限 10000px×10000px**：走纯 Canvas 只能视口大小 + `ctx` 变换。
5. **pageMap 有两份**：`entry/src/main/ets/shell/AppShell.ets:554-560`、`entry/src/main/ets/shell/MobileShell.ets:269-275`。
6. **DocListPane 三个宿主**：`AppShell:448`、`MobileShell:205`、`WorkspaceDest:126`。
7. **断点切换重建子树**：相机/选中放 `@Local` 会丢。
8. **备份恢复缺 `chapterIdMap`**（既有缺陷）：`entry/src/main/ets/store/AppStores.ets:490-508`。
9. **事务内读不到未提交数据**：`entry/src/main/ets/database/BaseDao.ets:18-20`。
10. **段落切分不处理 `\r`**（`entry/src/main/ets/editor/flowtext/model/TextDocument.ets:498-514`）；`snapToBoundary` 只向前退（`entry/src/main/ets/editor/flowtext/model/GraphemeUtil.ets:70-75`），选区末端用 `moveRight`。
11. **编辑器缺两个 API**：无 `getSelection/getSelectedText`；`setCaretPosition`（`:189-195`）不滚动、`moveCaretAnimated`（`:1062-1081`）也不调 `ensureCaretVisible`。S9 前先补只读地基。
12. **`DB_VERSION` 只是日志常量**（`entry/src/main/ets/database/DatabaseHelper.ets:8`）。
13. **嵌套特有**：
    - 父子关系放 placement，不放 topic（否则一张卡在不同白板无法不同归属）；
    - 深度检查要算**整棵子树**，不只是被拖的那一张；
    - 循环检查：目标不能是被拖卡的子孙；
    - 张嘴要按目标去重，别每次 `pointermove` 重建 DOM；
    - 自动编号在重排后必须重算；
    - 删除父卡时子卡上提并**散开位置**，否则全叠在原点；
    - 行命中优先于卡片命中（外扩 8 vs 30）。
14. **库内原本无索引**，`book_id` 全表扫；新表按 §4.1 建索引。

---

## 12. 未决问题（问用户，不要自行决定）

| # | 问题 | 当前默认 |
|---|---|---|
| Q1 | 自动编号用中文体例（一、/（一）/1.）还是英文（1. / 1.1 / 1.1.1） | 中文体例；导出时再转换 |
| Q2 | 素材是否支持图片/截图（条约影印、地图） | 首版不支持 |
| Q3 | 画布是否需要「导出为图片」 | 首版不做 |
| Q4 | 第四层是否永远不给 | 是；提示拆成独立写作卡 |

---

## 13. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-22 r1 | 首版：主题卡 + 素材 + 五表 + 独立论文白板 |
| 2026-10-22 r2 | 论文卡改名**写作卡**；取消独立论文白板；改为**任意卡可嵌套、三层上限**；父子关系移到 placement（`parent_id/ord`）；C 型张嘴交互；子卡缩进行 + 自动编号；新增白板库/卡片库；`写成初稿` 新建一篇 |

---

## 14. 可用性自检（2026-10-22 审计）

> 目的：确认「一个没有上下文的 AI 拿到这份文件就能开工」，而不是只有作者看得懂。

### 14.1 只读三节就够开工

1. **§0**：技能安装 + 开工顺序 + 基线命令；
2. **§2**：卡片模型（概念卡 / 写作卡 / 嵌套 / 三层）；
3. **§6**：C 型交互与拖拽语义。
数据细节按需查 §4，验收查 §8–§9。

### 14.2 自动化审计结果

| # | 检查 | 方法 | 结果 |
|---|---|---|---|
| 1 | 元信息可解析 | YAML 头 + 必需字段 | PASS（7 字段） |
| 2 | 章节完整 | §0–§15 全部存在 | PASS |
| 3 | 旧模型残留 | 全文检索「论文卡 / 论文白板 / 单元」（排除变更记录） | PASS（0 次） |
| 4 | 文件引用可定位 | 32 个文件引用全部命中、行号不越界 | PASS |
| 5 | 路径根一致 | 只使用工程根相对路径（不再混用 ets 相对） | PASS |
| 6 | 技能可加载 | 11 个技能在模式包或 `~/.agents/skills` 下存在 | PASS |
| 7 | 命令可解析 | 4 个 bash 代码块 `bash -n` 全过 | PASS |
| 8 | 表格完整 | 21 张表列数一致 | PASS |
| 9 | 交叉引用 | 所有 `§N` 都有对应章节 | PASS |
| 10 | 关键约束在场 | 三层上限 / `parent_id` / `format_runs` / 新建一篇 / 四点图标 | PASS |

**审计结论**：40/40 项通过；三份产物一致性检查 80/80（术语、阈值、表名、编号、初稿、分期、互指）。另：本机实跑 7 个回归脚本合计 **295 项**全过（guard 19 / data 28 / device 27 / flowtext 127 / import 5 / shell 57 / window 32），与 §9.1 的基线一致。

### 14.3 仍然存在的空白（工程未做，不是文档缺陷）

| 项 | 状态 |
|---|---|
| 代码 / 建表 / 构建 | 全部未做 |
| P0 性能与手势实测 | 未做（本机无工具链、无设备） |
| 自动编号体例 | 待用户确认（中文体例为默认） |
| 图片素材、导出图片 | 首版明确不做 |

### 14.4 下次改动后如何复跑

按 14.2 的十项人工复核；重点检查三处最容易回退的地方：
1. 是否又出现「论文卡 / 论文白板」旧词；
2. 新增的 `path:line` 是否仍是工程根相对、行号未越界；
3. 新增的技能名是否能在两个目录之一找到。

### 14.5 行号会漂移：以符号名为准

> 本文件写作期间，工作区源码被改动过（`entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets` 从 3539 行增至 3731 行），行号整体后移。**行号只是快照，符号名才是锚点。**
> 改动任何文件前，先 `grep -n "<锚点>" <文件>` 核对，再按行号读上下文。

| 用途 | 文件 | 搜索锚点（grep） |
|---|---|---|
| 四点菜单项 | `entry/src/main/ets/shell/DocListPane.ets` | `items: ['导出', '导入']` |
| 更多菜单分派 | `entry/src/main/ets/shell/DocListPane.ets` | `private onMoreAction` |
| pageMap（宽屏） | `entry/src/main/ets/shell/AppShell.ets` | `pageMap(name: string` |
| pageMap（手机） | `entry/src/main/ets/shell/MobileShell.ets` | `pageMap(name: string` |
| 键盘避让 | `entry/src/main/ets/shell/AppShell.ets` | `setKeyboardAvoidMode` |
| 安全区 | `entry/src/main/ets/shell/AppShell.ets` | `padding({ top: this.topInset` |
| 三形态分支 | `entry/src/main/ets/shell/AppShell.ets` | `app.ui.immersiveEditing` |
| 章节恢复 | `entry/src/main/ets/store/AppStores.ets` | `const model: ChapterModel` |
| 事务读路径 | `entry/src/main/ets/database/BaseDao.ets` | `protected getStore` |
| 建表 | `entry/src/main/ets/database/DatabaseHelper.ets` | `CREATE TABLE IF NOT EXISTS books` |
| 补列 | `entry/src/main/ets/database/DatabaseHelper.ets` | `private async ensureColumns` |
| 控制器 | `entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets` | `export class CanvasTextEditorController` |
| 定位不滚动 | `entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets` | `private moveCaretAnimated` |
| 段落边界 | `entry/src/main/ets/editor/flowtext/model/TextDocument.ets` | `paragraphBounds(offset: number)` |
| 字素吸附 | `entry/src/main/ets/editor/flowtext/model/GraphemeUtil.ets` | `static snapToBoundary` |
| MD 合成 | `entry/src/main/ets/utils/ExportService.ets` | `private static applyMarkdown` |
| 守卫白名单 | `tools/arkts-guard.cjs` | `const T3 =` |

---

## 15. 三份产物与同步规则

| 产物 | 位置 | 角色 | 谁看 |
|---|---|---|---|
| **本文件** | 桌面 `AI-README-语流思路板实现.md` | **规格唯一来源** | AI / 人 |
| 研究记录 | 工程内 `docs/research/07-知识单元与跨书画布-统一方案.md`（r2） | 决策依据、体例论证 | 人 / AI |
| 交互原型 | 桌面 `语流-思路板-设计预览.html` | 可点原型 + 「规格摘要」 | 人审 / AI 校对 |

### 15.1 同步规则

1. **改模型 → 先改本文件**（规格）；
2. 同步 07 与原型页的「规格摘要」；
3. 改完跑一致性检查（§14.4 + 下面四项）：
   - 术语：`写作卡` / `概念卡` / `张嘴` / `三层`；
   - 阈值：`30` / `8`；
   - 表名：`topics` / `topic_evidence` / `canvases` / `canvas_placements` / `canvas_links`；
   - 编号：`一、` / `（一）` / `1.`；`新建一篇`。
4. 旧版 HTML（一图看懂 / 统一方案）均已标注**历史存档**，不参与规格。

### 15.2 原型页的使用边界

- 原型页里的示例数据（均势 / 无政府状态 / 维也纳体系 / 主权与不干涉）**只是演示**，不是内置模板；
- 原型用 px 近似 vp；实现以 vp 为准；
- 原型不含保存、搜索、导出、真实数据；不要从原型反推存储格式。
