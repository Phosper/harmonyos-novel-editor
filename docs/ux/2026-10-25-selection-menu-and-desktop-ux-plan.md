# 语流｜桌面/移动交互与选区浮层优化方案

- 基线：`05d7ce2`（本轮改动见文末"实现落点"）
- 输入依据：`Yuliu_desktop_UX_review_agent.md`（D01–D13、长文流畅性、T01–T12）＋ 本轮新增需求「多选文字后弹出的菜单视觉粗糙、体验差」
- 约束：不改动既有功能与交互语义；不引入未验证的系统 Symbol 名称；本机无 hvigor/hdc，**未做真机与编译验证**。

---

## 一、问题梳理

### 1.1 本轮新增（菜单）

| 编号 | 问题 | 现状证据（`entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets`） |
| --- | --- | --- |
| M01 | 布局拥挤：11 项平铺两行、无分组，撤销/重做与剪贴板混排 | `selectionMenu()` 两个 `Row` + `ForEach`，无分隔线 |
| M02 | 尺寸写死：`menuW=320 / menuH=88` 估算定位，实际文本撑开后与估算不一致，靠边会压住或留大空隙 | `showSelectionMenu()` 旧实现 |
| M03 | 命中区偏小：`padding 12/9`、13vp 字，桌面勉强、触摸不足 44vp | 旧 `Text` 项 |
| M04 | 无阴影/无边框：纯 `#E61F2329` 深色块直接贴在纸上，缺少层次 | 旧实现硬编码色值 |
| M05 | 不跟随主题：深色主题下仍是同一块深色、与卡片/原生菜单不在同一色族 | 旧实现硬编码 `#FFFFFF`/`#E61F2329` |
| M06 | 箭头是 `▼/▲` 字形，字体缺字形会变豆腐块；箭头不指向选区起点 | 旧实现 |
| M07 | 无进入/退出动效 | 条件渲染，无 `transition` |
| M08 | 桌面拖选后**自动**弹菜单，方向键随即变成菜单导航，用户无法继续微调选区（对应审议 D04） | `finishMouseSelection()` / `selectWordAt()` |

### 1.2 审议文件所列（D01–D13）

| 编号 | 优先级 | 问题（摘要） | 本轮状态 |
| --- | --- | --- | --- |
| D01 | 高 | 查找替换/一键排版走 `applyExternalContent`，`runsJson` 被清空 → 未命中范围的格式一起丢失 | 待实施（批次 A） |
| D02 | 高 | "查找"实为批量替换：无匹配计数、无上一处/下一处、无当前匹配高亮 | 待实施（批次 B） |
| D03 | 高 | 保存异常（FAILED/TOO_LARGE）在主界面被压成"编辑中"，无重试/导出出口 | 待实施（批次 A） |
| D04 | 高 | 拖选后自动弹菜单，方向键被菜单接管 | **本轮已修**（桌面不再自动弹，见 §2.2） |
| D05 | 高 | `onWindowActivated` 无条件 `focus()`，可能抢走查找框/改名框焦点 | 待实施（批次 A） |
| D06 | 中 | 改名：进入不聚焦、Esc 无处理、失败静默、保存归属只读 `activeId` | 待实施（批次 B） |
| D07 | 中 | 续写会话不闭环：不恢复上次文稿/选区/阅读锚点；专注切换只共享几何 | 待实施（批次 C） |
| D08 | 中 | 章节结构无整理入口（排序/移动项目/项目改名）；`EditorStore.reorder` 不是章节顺序 | 待实施（批次 C） |
| D09 | 中 | 电脑窗口变窄直接切 `MobileShell`，操作模型随之切换 | 待实施（批次 C） |
| D10 | 中 | 工具条收纳后丢入口；L2/L3 无 H3；`rowWidth` 未计选区新增按钮；闲置 30% 不透明度 | 待实施（批次 D） |
| D11 | 中 | 设置藏在"请登录"后面，本机昵称被称作登录 | 待实施（批次 D） |
| D12 | 中 | 全局键盘路径不完整（列表/项目行、全局快捷键、可见焦点） | 部分（菜单项已有可见焦点描边，见 §2.2）；其余待实施 |
| D13 | 中 | 全局文库的"看见范围"与"新建/导出"动作范围不一致 | 待实施（批次 C） |
| 长文 | 风险 | 帧率/输入延迟无实测；`updateDocPreview` 全文 `countChars`；无滚动条；PageUp/Down 只滚屏 | 待量测（批次 D） |

---

## 二、优化方案

### 2.1 选区菜单（M01–M07）：桌面用系统菜单，触摸用可折行浮条

> 2026-10-25 第三版（依据真机截图 + 用户意见）：首版"两行横条"与次版"自绘竖排"都有同一个硬伤——**浮层由我们定位，溢出时被窗口裁切**；而系统本就提供带沉浸材质、自动边缘避让、`labelInfo` 快捷键位的菜单组件，自绘等于重复实现且更难做好。

**桌面（键鼠）：`bindContextMenu` + 系统 `Menu`**

```ts
.bindContextMenu(this.systemSelectionMenu, ResponseType.RightClick)

Menu() {
  MenuItemGroup() {                 // 撤销 / 重做
    MenuItem({ content: '撤销', labelInfo: 'Ctrl+Z' }).onClick(...)
    MenuItem({ content: '重做', labelInfo: 'Ctrl+Shift+Z' }).onClick(...)
  }
  MenuItemGroup() { /* 粗体 / 斜体 / 标题（Ctrl+B / Ctrl+I） */ }
  MenuItemGroup() { /* 复制 / 剪切 / 粘贴 / 全选（Ctrl+C/X/V/A） */ }
  MenuItemGroup() { /* 查找 Ctrl+F / 复制到系统 */ }
}
```

- **溢出交给系统**：菜单在指针位置弹出，靠边自动换向/内收，不再越出窗口（截图里右侧被裁的根因：自绘浮层用自身 `viewWidthVp` 夹取，而它与可见列宽不一致）。
- **观感交给系统**：沉浸材质/模糊、圆角、阴影、出现消失动效、键盘可达性由系统统一提供，与备忘录右键菜单同族。
- 快捷键提示用 `labelInfo`（系统渲染在右侧，正是备忘录 `Ctrl+C` 的位置）；分节用 `MenuItemGroup()`。

**触摸：自绘浮条（系统没有"抬手即弹"的触发方式）**

- 项高 44vp、最小宽 56vp、字号 14vp；按 `viewWidth − 16` 贪心折行：360vp → 3 行、320vp → 3 行、240vp → 4 行，**任何宽度都不裁切**；
- 定位 X 夹在 `[8, viewWidth − 宽度 − 8]`、Y 夹在视口内 —— 靠边时**自动向中间移位**；
- 表面 `bgCard`、1vp `divider` 边框、阴影 `radius 20 / offsetY 8`、外圆角 **16**、项圆角 **10**；
- 小三角为旋转 45° 方块（12vp），跟随选区起点；出现 120ms 淡入、关闭即时。

### 2.3 尺寸/定位（M02）

不再写死 `320×88`：

- `menuItemWidth(label) = max(itemMinWidth, label.length × fontSize + 14)`
- `menuRowWidth = Σ itemWidth + gap + groupGap×2 + 1`
- `menuBodyWidth = max(两行) + padding×2`，`menuBodyHeight = padding×2 + itemHeight×2 + gap`
- 定位：`x = clamp(anchorX - caretSize/2 - padding, 8, viewW - bodyW - 8)`；优先在上方（`anchorTop - bodyH - caret/2 - 6`），放不下转下方；下方仍溢出则贴底。

### 2.4 主题一致性（M05）

- 新增 5 个 `@Prop`：`menuSurfaceColor / menuBorderColor / menuTextColor / menuAccentColor / menuActiveBgColor`，由 `EditorPane` 用 `colors().bgCard / divider / textPrimary / brand / activeBg` 注入，经 `TextEditorHost` 透传。
- 结果：亮/暗主题、青笺/桃笺等主题下浮层与卡片、原生菜单同色族，不再有"临时深色块"。

### 2.5 图标（M01 的延伸）

本轮**未引入** `SymbolGlyph`，原因：本机无 SDK，`sys.symbol.*` 名称无法校验，错误名称会直接编译失败。落地步骤（批次 A2）：

1. 在 DevEco 机器上确认符号名（SDK 的 `sysResource` 或预览器补全）；
2. 只使用已验证名称，按行分组接入：
   - 剪贴板：`scissors`（剪切）/ `doc_on_doc`（复制）/ `clipboard`（粘贴）/ `checkmark_circle`（全选）—— **候选名，待校验**；
   - 格式：`bold` / `italic` / `textformat`（仓库已在用，可先用）；
   - 历史与导航：`undo` / `redo` / `magnifyingglass`（仓库已在用）；
   - 分享：`square_and_pencil`（仓库已在用）。
3. 版式：图标 15/16vp + 文字 11/12vp 两行竖排，项高不变（38/44），命中区不缩小。

### 2.6 审议问题（D01–D13）的实施设计要点

- **D01 格式保留**：`replaceAll` 改为"按匹配区间映射偏移"——先按旧文本匹配区间构造 `(oldStart, oldEnd, newLen)` 列表，再把 `runs` 逐个映射：区间外整体平移，区间内的 run 收缩/删除，跨越区间的 run 拆分；不做整篇 `runsJson=''`。验收：变长/变短/跨段/列表/emoji/连续撤销重做。
- **D02 查找条**：非模态 `SearchBar`（`bgSurface`、`radius 12/16`、高 36/44），显示 `当前/总数`，Enter／Shift+Enter 跳转，Esc 关闭并恢复选区；替换折叠在右侧"替换"按钮展开。匹配高亮沿用 `SelectionInfo`（不改文档模型），仅新增"当前匹配"状态。
- **D03 保存状态**：`docStatus()` 按 `activeDoc.saveState` 输出"保存中/已保存/保存失败/超出单篇上限"，异常用 `danger` 常驻 + 点击展开"重试 / 导出草稿 / 拆分说明"；全局异常在侧栏项目行加红点计数。
- **D05 焦点归属**：`TextEditorHost` 记录失活前语义焦点（正文/查找/改名/对话框），`onWindowActivated` 只恢复原焦点；无记录时才回正文。
- **D06 改名**：进入即 `focus()` + 全选；Enter 提交、Esc 还原；失败保留输入并提示；保存绑定进入时的 `docId`。
- **D07 会话恢复**：每项目记 `lastDocId`；每文稿分别存 `caret / selection / 阅读锚点`（阅读锚点只在滚动时更新，不标 dirty）；"回到编辑处/返回上个位置"两个显式动作。
- **D08 章节结构**：行菜单加"上移/下移/移到项目"，项目菜单加"重命名"；导出顺序与目录一致校验。
- **D09 窄窗**：`mainLayout` 的断点分支改为"先收栏位、后换宿主"，键鼠语义与快捷键在窄窗保持不变。
- **D10 工具条**：任何档位保留"更多"；H3 进更多；`rowWidth` 计入选区动作；闲置不透明度不低于 0.55；撤销/重做按 `canUndo/canRedo` 禁用。
- **D11 设置入口**：侧栏固定"设置"行（齿轮 + 文字），账号改称"个人资料（本机）"。
- **D12 键盘**：全局命令（新建/打开/搜索/导入导出/设置）＋ 列表行方向键/Enter/可见焦点；菜单快捷键提示统一标注。
- **D13 范围可见**：全局文库下"新建"显示目标项目并可切换；导出面板写明项目名/文稿名与数量。
- **长文量测**：按 1k/1万/5万中文、纯文本与混排各测输入延迟、p95/p99 帧时、长任务、内存；`updateDocPreview` 与 `wordCount` 改为增量或闲时合并；补滚动条与 PageUp/Down 语义（是否移动 caret 需产品定）。

---

## 三、桌面端 / 移动端圆角规范

圆角按**输入形态**分档（`pointerPrimary`），不是按屏幕宽度：同一台 2in1 接鼠标时用桌面档，取鼠标后用手触摸时用移动档。

| 组件 / 状态 | 桌面（键鼠） | 移动（触摸） | 令牌 / 取值位置 |
| --- | --- | --- | --- |
| 选区菜单（桌面右键＝系统 `Menu`） | **8**（显式 `.radius(8)`） | — | 官方默认值：2in1 为 8vp、**其他设备 20vp**；平板形态跑电脑模式会落到 20vp，故显式钉成桌面档 |
| 选区浮条（电脑模式/键鼠） | **12**（项 8，行高 38） | — | `selectionMenuMetrics(true)`：`desktopMode \|\| pointerPrimary` |
| 选区浮条（纯触摸） | — | **16**（项 10，行高 44） | `selectionMenuMetrics(false)` |

> 修正说明：此前只看 `pointerPrimary`，电脑模式（`desktopMode=true` 而鼠标未触发指针窗口）会落到移动档圆角（16）。
> 现已改为 `desktopMode || pointerPrimary` 判定桌面档；同时 `shouldAutoOpenSelectionMenu()` 用同一判定（电脑模式不自动弹浮条，右键走系统菜单）。
| 选区浮层小三角 | 10（边长） | 12 | 同上 → `caretSize` |
| 原生菜单 / 右键菜单（Menu） | 12 | 16 | 既有：`EditorTools.paragraphMenuView`(12) / DocListPane.rowMenu(tablet 16) |
| 工具栏图标热区 | 圆角 8（方形 40/44） | 圆形 44/56 | `topIconMetrics()` |
| 卡片 / 列表行 | 12 | 16 | `WeaverRadii.MD` / `LG` |
| 半模态 / 设置面板 | 16 | 16（顶部 20） | `WeaverRadii.LG/XL` |
| 输入框 / 搜索框 | 8 | 12 | `WeaverRadii.SM/MD` |
| 徽标 / 标签（字数、项目名） | 4 | 6 | `WeaverRadii.XS`（触摸 +2） |

规则：

1. 桌面圆角一律 ≤12，移动一律 ≥16（同一层级），避免"桌面显笨、移动显硬"；
2 嵌套时内圆角 = 外圆角 − 内边距（浮层 12/16 配 8/10 即此关系），不做"内外同值"；
3. 圆形只用于图标热区与头像，不给文字容器用圆角半径 = 高度/2。

---

## 四、实现要点

### 4.1 文件与组件

| 文件 | 改动 |
| --- | --- |
| `constants/DesignTokens.ets` | 新增 `SelectionMenuMetrics` 接口与 `selectionMenuMetrics(pointerPrimary)`（桌面/触摸两套圆角、项高、阴影） |
| `editor/flowtext/CanvasTextEditor.ets` | 重写 `selectionMenu()`（分组 + 分隔线 + 主题色 + 阴影/边框 + 旋转方块箭头 + 过渡动效）；`menuMetrics/menuItemWidth/menuRowWidth/menuBodyWidth/menuBodyHeight`；`showSelectionMenu()` 改为度量驱动定位 + 视口夹取 + 箭头跟随选区；新增 `shouldAutoOpenSelectionMenu()`；`selectWordAt(..., openMenu)`；桌面双击不弹菜单 |
| `editor/TextEditorHost.ets` | 透传 5 个菜单配色 `@Prop` |
| `shell/EditorPane.ets` | 用 `colors()` 注入菜单配色（`bgCard/divider/textPrimary/brand/activeBg`） |
| `tools/flowtext-regression.cjs` | 载入 `DesignTokens`；新增 3 条断言（两端圆角/命中区分档、菜单几何随度量变化、桌面不自动弹） |

### 4.1.1 实现落点（本轮，供 review 用）

| 位置 | 内容 |
| --- | --- |
| `constants/DesignTokens.ets:210` | `SelectionMenuMetrics` 接口（圆角/项高/阴影/箭头等 12 个字段） |
| `constants/DesignTokens.ets:237` | `selectionMenuMetrics(pointerPrimary)`：桌面 12/8/38/14，触摸 16/10/44/20 |
| `CanvasTextEditor.ets:49` | `SELECTION_MENU_LABELS` 常量（标签唯一来源，避免每次 build 重建数组） |
| `CanvasTextEditor.ets:612` | `menuMetrics / menuItemWidth / menuRowWidth / menuBodyWidth / menuBodyHeight` |
| `CanvasTextEditor.ets:644` | `menuItem()`：主题色 + 44/38 命中高 + 圆角 + 悬停/键盘高亮 + 桌面 1vp 品牌描边 |
| `CanvasTextEditor.ets:670/680` | 分组分隔线、无描边旋转方块箭头 |
| `CanvasTextEditor.ets:690` | `selectionMenu()`：两行分组布局（撤销/重做 │ 粗/斜/标题；复制/剪切/粘贴/全选 │ 查找/复制到系统） |
| `CanvasTextEditor.ets:753` | `showSelectionMenu()`：度量驱动定位 + 视口夹取 + 箭头跟随选区 |
| `CanvasTextEditor.ets:3375/3395` | `finishMouseSelection()` 与 `shouldAutoOpenSelectionMenu()`：桌面不自动弹 |
| `CanvasTextEditor.ets:3428` | `selectWordAt(..., openMenu)`：双击选词不弹菜单，右键仍弹 |
| `TextEditorHost.ets:45/170`、`EditorPane.ets:196` | 菜单配色 5 个 `@Prop` 透传与主题注入 |

### 4.2 状态与响应式

- 状态：`menuVisible / menuX / menuY / menuBelow / menuIndex / menuArrowOffset`（已有 + 新增箭头偏移）。键盘高亮与鼠标悬停共用 `menuIndex`，避免两套高亮。
- 响应式：圆角/尺寸只跟 `pointerPrimary`；视口宽度只参与定位夹取（`viewWidthVp/viewHeightVp`），不改变圆角。
- 动效：120ms 标准曲线淡入；关闭无过渡（避免"菜单消失动画"挡住下一次点击）。

### 4.3 兼容与取舍

- 不引入 `SymbolGlyph`（符号名未验证）；不引入新依赖；不改 `menuLabels()` 顺序与 `activateMenuItem()` 索引，保证键盘导航与既有测试不漂移。
- 桌面拖选不自动弹菜单是**行为变更**：右键仍是入口、触摸浮条不变；如希望"桌面也弹但方向键优先给正文"，需在 `handleMenuKey` 里按 Shift/方向键分流，属批次 B 的可选项（本轮未做，避免与 D04 的结论冲突）。
- 阴影在极低端设备可能增加合成开销；若真机掉帧，把 `shadowRadius` 降到 0 并保留边框（只需改 `selectionMenuMetrics`）。

---

## 五、验收清单

### 5.1 本轮（选区浮层）

- [ ] 桌面：拖选/双击后**不弹**菜单，方向键继续移动/扩选；右键弹出菜单。
- [ ] 触摸：长按选词/拖选抬手弹浮条；点击空白处或 Esc 关闭。
- [ ] 亮色（极简纸墨）与深色（夜读）下，浮层表面/边框/文字/高亮与卡片同色族，无突兀深色块。
- [ ] 圆角：桌面 12/8、触摸 16/10（DevEco 预览器切换设备可量）；两端不共用同一套。
- [ ] 命中区：触摸项高 ≥44vp；桌面项高 38vp；连续点按不误触相邻项。
- [ ] 键盘：方向键移动高亮、Enter 执行、Esc 关闭；桌面高亮有 1vp 品牌色描边。
- [ ] 定位：选区在首行/末行/左右边缘时菜单不越界；箭头指向选区起点。
- [ ] 动效：出现 120ms 淡入，无明显跳动；关闭即时。

### 5.2 审议问题（按批次）

| 批次 | 范围 | 验收 |
| --- | --- | --- |
| A | D01/D03/D05 | 替换不改未命中格式；保存异常常驻可重试；切回应用不抢焦点 |
| B | D02/D04/D06 + 菜单键 | 查找可定位并高亮；桌面选区不被菜单接管；改名可取消/重试 |
| C | D07/D08/D09/D13 | 续写位置可恢复；章节可整理；窄窗不换操作模型；范围可解释 |
| D | D10/D11/D12/长文 | 任何宽度都有"更多"；设置有明确入口；键盘可完成主要任务；5 万字量测达标 |

### 5.3 设备侧（需 DevEco 机器）

`hvigorw assembleHap` 编译 → 安装 → 在 2in1（键鼠）与手机/平板（触摸）各跑：

1. 拖选一段 → 看是否弹菜单 → 方向键 → 右键；
2. 长按选词 → 浮条 → 点"复制"→ 粘贴验证；
3. 深色主题重复 1–2；
4. 选区贴顶/贴底 → 菜单方向与箭头；
5. 中文输入法组字 → 方向键选候选（T02）；
6. 记录帧时间与输入延迟（长文 T12），与基线对比。

> 本机（OpenEuler，无 hvigor/hdc）仅完成源码与本地回归：`arkts-guard 19`、`flowtext 141`、`shell 60`、`data 49`、`import 5`、`window 32`、`canvas 13`、`draft 14`、`schema 5`，全部 exit=0。**未编译、未装机、未截图**。
