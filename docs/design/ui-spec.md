# Weaver UI 设计规范 v1 —— 极简纸墨（全局重构基线）

> 目的：把"好看"落成**可执行、可核实**的规则，让全局 UI 一致、干净、沉浸。
> 落地方式：先审定本规范 → 再全局改造。
> ⚠️ 说明：当前环境**无原生视觉**（看图/截图不可用），"美观"最终由**人工肉眼验收**；本规范负责把一致性做成客观标准。

---

## 1. 设计原则

1. **内容优先**：正文/文稿是主角，界面元素克制、退后。
2. **少即是多**：去彩色顶栏、去冗余边框与色块、去堆叠分割线。
3. **单一来源**：颜色/字号/间距/圆角/动效**全部来自 `DesignTokens.ets`**，页面不得硬编码。
4. **明暗一致**：同一语义令牌在明/暗主题下映射不同值，切换不"穿帮"。
5. **触感统一**：按压=hoverBg、选中=activeBg、分割线=divider，全应用一致。

---

## 2. 主题体系（新增：全局主题）

现状：只有"深/浅 + 编辑器稿纸主题"两套，各自为政。
目标：**一套全局主题预设**驱动整站配色；编辑器稿纸随全局主题联动。

| 主题 | 类型 | 说明 |
|---|---|---|
| **极简纸墨**（默认） | 浅 | 近白纸 + 近黑墨，单一"墨色"强调，最克制 |
| **温暖米纸** | 浅 | 米黄纸 + 深褐字，暖、护眼、阅读感 |
| **青笺** | 浅 | 淡青绿纸，清爽 |
| **夜读** | 深 | 纯黑/近黑分层，浅字 |

- `brand` 语义 = **墨（浅主题）/ 纸白（深主题）**，用于主按钮与需要强调的文字；交互选中用 `activeBg` 淡墨。
- 设置有「主题」入口（列全部预设 + 跟随系统深浅）。
- 编辑器正文字号/行距仍由「稿纸字号/行距」独立可调（沿用 `PAPER_THEMES` 的字号字段），但**纸色随全局主题**。

---

## 3. 设计令牌（Tokens）

### 3.1 颜色（语义 → 各主题取值）

| 令牌 | 极简纸墨(浅) | 温暖米纸(浅) | 青笺(浅) | 夜读(深) | 用途 |
|---|---|---|---|---|---|
| brand | `#1C1C1E` | `#4A3A2A` | `#2A3A2A` | `#EDEDED` | 主按钮/强调 |
| brandPressed | `#000000` | `#332619` | `#1B271B` | `#FFFFFF` | 按下态 |
| onBrand | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#1C1C1E` | 主按钮文字 |
| bgPrimary | `#FFFFFF` | `#F7F1E6` | `#F1F6F0` | `#000000` | 全局背景 |
| bgSurface | `#F6F6F7` | `#EFE7D8` | `#E8F0E6` | `#1C1C1E` | 分组/工具条底 |
| bgCard | `#FFFFFF` | `#FDF9F1` | `#FAFDF9` | `#141416` | 卡片/弹窗 |
| sidebarBg | `#FAFAFB` | `#F2EBDE` | `#EDF3EB` | `#0D0D0E` | 侧栏/面板 |
| toolbarBg | `#FFFFFF` | `#FBF6EC` | `#F8FCF7` | `#141416` | 顶部工具条 |
| listBg | `#FFFFFF` | `#FDF9F1` | `#FAFDF9` | `#000000` | 列表背景 |
| editorBg | `#FFFFFF` | `#F7F1E6` | `#F1F6F0` | `#1A1A1C` | 编辑区背景 |
| textPrimary | `#1C1C1E` | `#2E2418` | `#1F2A1F` | `#EDEDED` | 一级文字 |
| textSecondary | `#6E6E73` | `#6B5B45` | `#4F6350` | `#9A9A9F` | 二级文字 |
| textTertiary | `#A6A6AB` | `#9C8B72` | `#85968A` | `#6E6E73` | 三级/占位 |
| divider | `#ECECEE` | `#E3D8C4` | `#DCE7DA` | `#2A2A2C` | 分割线 |
| activeBg | `#0F1C1C1E` | `#142E2418` | `#142A3A2A` | `#1FEDEDED` | 选中态 |
| hoverBg | `#081C1C1E` | `#0D2E2418` | `#0D2A3A2A` | `#14EDEDED` | 按压态 |
| danger | `#D70015` | `#B3261E` | `#B3261E` | `#FF6961` | 危险 |
| warning | `#B25000` | `#8A5A00` | `#8A5A00` | `#FFB340` | 警示 |
| success | `#248A3D` | `#3F7D34` | `#3F7D34` | `#63D471` | 成功 |

> 规则：**明主题禁止出现"在深色下成亮块"的浅色硬编码**；一律取语义令牌。

### 3.2 字体与层级（新增 `TypeScale`）

| 名称 | 字号/行高 | 字重 | 用途 |
|---|---|---|---|
| display | 24 / 32 | Medium | 页面大标题、空态标题 |
| title | 17 / 24 | Medium | 页面/弹窗标题 |
| headline | 16 / 24 | Medium | 卡片标题、列表主行 |
| body | 15 / 24 | Regular | 正文说明、输入 |
| sub | 13 / 20 | Regular | 辅助信息 |
| caption | 12 / 16 | Regular | 次要说明、页签文字 |
| micro | 11 / 14 | Regular | 角标、极次要 |

> 编辑器正文字号/行距**不走此表**，由稿纸主题（`PAPER_THEMES`）决定。

### 3.3 间距（4 基准，复用 `WeaverSpacing`）

`4 / 8 / 12 / 16 / 24 / 32`。页面左右边距统一 **16**；分组块间距 **24**；列表项内边距 **上下 12 / 左右 16**。

### 3.4 圆角（收敛为 4 档）

`XS 4`（芯片/小标签）、`S 8`（输入/按钮/浮层）、`M 12`（列表卡/分区块）、`L 16`（卡片/弹窗）。
（废弃 XXL 大圆角，保持克制。）

### 3.5 尺寸（栏高/控件高）

| 元素 | 值 |
|---|---|
| 顶栏（宽屏/手机） | 48 / 56 |
| 工具条 | 44 |
| 底部页签栏 | 56 |
| 列表项 | 56 |
| 按钮（主/次） | 44 / 40 |
| 输入框 | 44 |
| 图标 | 24（行内 20） |

### 3.6 动效

快 `120ms` / 标准 `180ms` / 慢 `260ms`，曲线 `EaseOut`。顶栏与工具条收放 = 180ms。

### 3.7 层级与阴影

**极简：尽量不用阴影**——用 `1px divider` + 背景层次（bgPrimary↔bgSurface↔bgCard）表达层级。
弹窗/浮层可用 scrim `#66000000`；浮层本体用深底浅字（见组件）。

---

## 4. 组件规范

| 组件 | 规范 |
|---|---|
| **主按钮** | brand 填充 / onBrand 文字 / 圆角 S / 高 44 / 字号 body；按下 brandPressed |
| **次按钮** | 透明底 + 1px `divider` 描边 / textPrimary 文字 / 高 40 / 圆角 S |
| **文字按钮** | brand 文字 / 无底 / 左右内边距 8；用于"更多/查找"等 |
| **危险按钮** | danger 文字或描边 |
| **卡片** | bgCard / 圆角 L / 无边框或 1px divider / 内边距 16 / 间距 12 |
| **列表项** | 高 56 / 左右 16 / 主行 headline / 副行 sub(textTertiary) / 底部 1px divider（末条无）/ 按压 hoverBg |
| **输入框** | 高 44 / bgSurface / 圆角 S / 内边距 12 / 无边框 / 聚焦 activeBg |
| **对话框** | 宽 88%（max 460）/ 圆角 L / bgCard / 标题 title / 正文 body / 按钮右对齐 / scrim `#66000000` |
| **顶栏** | 高 48/56 / bgCard / 底 1px divider / 标题 title / 动作图标 24 |
| **底部页签** | 高 56 / bgCard / 顶 1px divider / 选中 brand + 指示条(20×3, 圆角) / 未选 textTertiary / 图标 24 + 文字 caption |
| **分段控件** | 芯片式：高 28 / 圆角 全圆 / 选中 activeBg + brand 文字 / 未选 textSecondary |
| **面板（目录/侧栏）** | 宽 82%（手机）/ 240（宽屏）/ bgSurface / 顶部标题 title / 列表项同上 |
| **空态** | 居中 / 图标 48 textTertiary / 标题 headline / 说明 sub / 主按钮 |
| **Toast** | 深底浅字 `rgba(0,0,0,.85)` / 圆角 S / 居中 / ~1.5s |
| **选区浮层** | 深底浅字 / 圆角 S / 双行 11 项 / 带箭头 |
| **分割线** | 1px `divider`；分组间隔用 bgSurface 8vp 条带 |

---

## 5. 页面改造清单

| 文件 | 现状问题 | 目标 |
|---|---|---|
| `constants/DesignTokens.ets` | 仅明/暗两套；蓝色品牌与"纸墨"不符 | 增设**主题预设**（上表 4 套）+ `TypeScale` + 补齐语义令牌 |
| `store/UiStore.ets` | 只有 `darkMode` + 仅编辑器的 `paperTheme` | 引入 `themeId`（全局主题）；编辑纸色由主题派生 |
| `pages/dest/SettingsDest.ets` | 设置分组零散 | 主题入口 + 统一分组卡片与行规 |
| `shell/AppShell.ets` | 三栏/对话框硬编码零散 | 统一 token；对话框统一规范 |
| `shell/MobileShell.ets` / `MobileTabBar.ets` / `MobileSectionTabs.ets` | 底栏/分段样式不一 | 统一底栏与分段规范 |
| `shell/WorkspaceDest.ets` | 顶栏/滑出面板 | 顶栏 56 + divider；面板 bgSurface |
| `shell/EditorPane.ets` | 条数多、芯片样式杂 | 精简为"状态条 + 动作条"；芯片统一 |
| `shell/DocListPane.ets` | 列表项样式 | 统一列表项 56 + 分割线 + 紧凑两行 |
| `shell/ProjectSidebar.ets` | 侧栏 | 统一 240 宽 + 列表项 |
| `shell/InputDialog.ets` | 弹窗 | 统一对话框规范 |
| `shell/PcWindowBar.ets` | PC 标题栏 | 统一顶栏规范 |
| `pages/GuideSwiperPage.ets` | 引导页 | 极简引导风格 |

---

## 6. 全局一致性规则（强制）

1. **颜色/间距/圆角/字号只能来自 `DesignTokens`**；页面禁止硬编码 hex 与魔数（编辑器 canvas 内部除外，走 `EditorTheme`）。
2. 页面左右边距统一 16；栏高统一（3.5）。
3. 交互反馈统一：按压 `hoverBg`、选中 `activeBg`、分割 `divider`。
4. 正文对比度 ≥ **4.5:1**；禁用纯装饰性彩色块。
5. 深色下不得出现浅色硬编码亮块。

---

## 7. 落地步骤

1. 扩展 `DesignTokens`（主题预设 + `TypeScale` + 语义补齐 + `themeById()`）。
2. `UiStore` 增加 `themeId` 与持久化；设置页加「主题」入口；编辑器纸色随主题。
3. 逐页替换为 token（按 §5 顺序），每页可独立构建验证。
4. 全局审查：检索硬编码色值/间距并清零（编辑器 canvas 除外）。

---

## 8. 验收标准

- **客观**：全局无硬编码颜色（`DesignTokens`/编辑器主题除外）；间距/圆角/字号均用 token；四主题 + 明暗切换一致且对比度达标、无亮块穿帮。
- **主观**：由用户肉眼验收"统一、干净、沉浸"（本环境无视觉，此项必须人工确认）。

---

## 附：竞品实测 —— 纯纯写作（真机 2026-10-05）

- 环境：鸿蒙 **Android 兼容容器**（窗口 `shell_assistant3`），包 `com.drakeet.purewriter`，入口 `WriterActivity`；Android 兼容 App 的 `ui layout` **只有 resource id 与坐标、无文本**，配色靠**截图取色**（python+PIL）。
- **编辑页结构极简**（全部节点）：
  `android.widget.ImageView#id/background`（整屏纸）→ `mainPager` → `writerRecyclerView` → `frameLayout` → `EditText#id/title`（高 156px ≈ 54vp，顶） + `EditText#id/content`（**满屏**）；浮标 `TextView#id/wordCount`（右上角 `[950,304,1054,359]`）。
  → **没有工具栏、没有 FAB、没有分割线**。
- **实测色板（深色）**：背景 `#282828`（**柔和深灰**，非纯黑）；正文/标题文字 `#F2F2F2`；字数浮标底色 `#1A1A1A`；顶栏与正文**完全同底**（title 区域主色同为 `#282828`）。
- **给 Weaver 的启示（已落地到编辑页）**：
  1. 极简 = **一整块平面 + 字**：顶栏/正文**同底色**、**去分割线**。
  2. 深色用**柔和深灰**（`#282828`）而非纯黑（已改 `夜读` 主题）。
  3. 几乎不用强调色；状态（字数等）用**小号弱化浮标**。
  4. 其余功能收进 `⋮` 菜单，编辑页不常驻工具栏。
- Weaver 落地验证：编辑页顶栏/状态条/快捷条/正文**取色一致**（同一主色），呈现单一平面。
