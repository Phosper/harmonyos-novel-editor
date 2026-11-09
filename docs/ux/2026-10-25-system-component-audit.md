# 系统组件审计（语流 / 2026-10-25）

- 基线：本轮改动之后的工作区（未提交）
- 触发：用户明确要求「开发鸿蒙项目优先使用系统自带组件；查不到系统等价物要先告知并等批准，才能自绘」
- 方法：`grep` 全仓 `entry/src/main/ets`（124 个 .ets）+ 逐文件人工核对；只统计**UI 呈现层**，不含业务逻辑
- 结论：**绝大多数交互已经是系统组件**；本轮删除 2 个"零引用"的自绘导航组件（底部页签、分段页签）、给 1 处浮片补上系统材质；另有 4 处「系统有等价物但需要取舍」列给你拍板，4 处「必须自绘」写明理由

## 一、已经在用系统组件（无需改动）

| 场景 | 系统组件 | 位置 |
| --- | --- | --- |
| 右键/长按菜单 | `bindContextMenu` + `Menu`/`MenuItem`/`MenuItemGroup` | `DocListPane` 文稿行、`ProjectSidebar` 项目行、`CanvasTextEditor` 选区菜单 |
| 下拉菜单 | `bindMenu` + `Menu` | `EditorTools` 段落菜单、`DocListPane` 更多、`MenuButton` |
| 半模态 | `bindSheet`（`SheetType.CENTER`） | 设置、搜索替换等 5 处 |
| 悬浮提示 | `bindPopup` | `TopActionButton` 悬停提示 |
| 提示/对话框 | `promptAction.showToast/showDialog/showActionMenu` | 全仓 31 处 |
| 弹窗按钮 | `Button` | 各处 |
| 输入 | `TextInput` / `TextArea` / `Search` | 9 / 1 / 3 处 |
| 开关 | `Toggle(ToggleType.Switch)` | `SettingsPanel` |
| 进度 | `Progress` | 加载/导入 |
| 滚动 | `List` / `Scroll` / `Swiper` + `scrollBar` / `edgeEffect` | 列表、引导页 |
| 滑动操作 | `swipeAction` | 文稿行左滑 |
| 窗口原生按钮 | 系统标题栏三键（`readTitleButtonWidthVp` 只量宽度） | `DesktopTitleBar` |
| 材质/光感 | `uiMaterial`（34 处）、`systemMaterial`（9 处）、`backgroundBlurStyle`（6 处）封装在 `MaterialSurface`/`LightTokens` | 全局 |

## 二、本轮改动

| 项 | 位置 | 改动 |
| --- | --- | --- |
| 未使用的自绘分段控件 | `shell/MobileSectionTabs.ets`（无任何调用方） | **删除**（系统等价物：`SegmentButton`；本组件本就是死代码，既有审计也建议删除） |
| 未渲染的自绘底部页签 | `shell/MobileTabBar.ets` + `MobileShell.tabItems()`（组件从未被实例化、`tabItems()` 从未被调用） | **删除**（系统等价物：`Tabs` + `TabContent`；这是被"极简改版"废掉的旧设计残留） |
| 「选中 N 字 / 加到卡片」浮片 | `shell/EditorPane.ets` `selectionPill()` | 不透明卡片 → **系统材质** `backgroundBlurStyle(BlurStyle.COMPONENT_THICK)` + `WeaverRadii.MD`；顺带修正阴影误用 `divider`（浅色下几乎不可见）为 `#1F000000` |
| **A2** 弹窗改系统组件 | `shell/AppShell.ets`（删除 `shell/InputDialog.ets`） | 自绘遮罩 + 玻璃卡片 → **系统 `CustomContentDialog`**：`CustomDialogController` 打开、`@Monitor('dialogWatch.dialog')` 驱动；标题/辅助文本/按钮/圆角/材质/动效全由系统提供；删除失败后自动重开并保留输入 |
| **A3** 图标改系统组件 | `shell/DocListPane.ets`、`shell/SettingsPanel.ets` | `Text('★')` → `SymbolGlyph(sys.symbol.star)`；`Text('✓')` → `Radio`（单选语义 + 无障碍文本）。`TopicCard` 的 ▲▼↗ 仍是字形：chevron/arrow 类符号名本机无法校验，需在 DevEco 确认后替换 |
| **A4** 动作块改系统组件 | `shell/EditorPane.ets` `selectionPill()` | 手绘"小圆角底色文字" → 系统 `Chip`（自带最小尺寸、按下态、无障碍语义） |

## 三、系统有等价物、但需要你拍板（我未擅自改）

| # | 现状（自绘） | 系统等价物 | 取舍 / 风险 |
| --- | --- | --- | --- |
| A1 | ~~`MobileTabBar`~~ / ~~`MobileSectionTabs`~~：均**零引用**（已删除） | `Tabs` + `TabContent` / `SegmentButton` | 不需要再改：手机端当前是"项目 / 文稿"两栏扁平结构，没有底部页签。若以后要做底栏，直接用系统 `Tabs`，不要再自绘 |
| A2 | ~~`InputDialog` 自绘弹窗~~ **已完成** | `CustomDialogController` + `CustomContentDialog` | 已替换；失败重开会保留输入，`dialogPending` 仍然防止重复提交 |
| A3 | ~~`Text('★')`、`Text('✓')`~~ **已完成**；剩 `TopicCard` 的 `Text('▲')`/`Text('▼')`/`Text('↗')`（行上移/下移/跳转） | `SymbolGlyph` 的 chevron/arrow 名称 | 前两项已换系统组件；后三个符号名（候选 `chevron_up`/`chevron_down`/`arrow_up_right`）**本机无法校验**，猜错会编译失败。请在 DevEco 确认名称，或批准我改成文字按钮（"上移/下移/详情"） |
| A4 | ~~自绘动作块~~ **已完成** | 系统 `Chip` | "加到卡片"改为 Chip；外层 Row 仍负责"选中 N 字 + 动作"的排版（容器不是控件） |
| A5 | 画布内选区手柄、光标、列表符号 | 无（系统选区手柄只服务系统文本组件） | 自绘编辑器内部元素，**无系统等价物**；已按几何绘制并记录在 `docs/flowtext-testing.md` |

## 四、必须保留自绘（已写明理由）

| 项 | 原因 |
| --- | --- |
| `CanvasTextEditor`（正文、选区、光标、动画） | 系统 `Text`/`RichEditor` 无法满足：按段落种类排版（悬挂缩进/项目符号）、自定义命中与光标亲和性、打字机缩放、字形级动画、IME 预上屏的精确控制 |
| `CanvasPane` 思路板 / `TopicCard` | 自由画布与连线是业务核心，系统无等价物 |
| `MaterialSurface` 的 `linearGradient`/`radialGradient` | **降级兜底**：设备不支持实时模糊时用「薄纱 + 描边 + 静态渐变」复刻光感；`arkts-guard` 有「材质降级必须显式」的断言。系统支持时走 `uiMaterial`/`backgroundBlurStyle` |
| 「沉浸光感」页面底 | 系统没有"整页光晕"组件；用 `radialGradient` 绘制光晕 + 内容层透明，属于视觉实现而非控件复刻 |

## 五、规则落地

1. 已写入长期记忆（`~/.dsh/memories/MEMORY.md`，2026-10-25 条）：**先用系统组件；查不到系统等价物先告知并等批准；自绘必须写理由与降级方案**。
2. 今后流程：`grep/MCP/官方文档确认系统组件 → 能覆盖就用 → 不能覆盖先给出"无系统等价物 + 候选方案"→ 等批准`。
3. 系统组件默认带沉浸光感；自绘浮层必须显式补 `backgroundBlurStyle` 或 `uiMaterial`，不得用纯色卡片硬顶。

## 六、验收清单

- [ ] 设置/文稿列表/项目列表/选区菜单的弹层全部是系统 `Menu`/`Sheet`/`Dialog`（无自绘卡片）。
- [ ] 「选中 N 字 / 加到卡片」浮片在浅色/深色下都有材质与阴影，不再"贴纸感"。
- [ ] 全仓不再存在未使用的自绘控件文件（`MobileSectionTabs`、`MobileTabBar` 已删，`MobileTab` 状态仍被 `titleText()` 使用）。
- [ ] A1–A4 四项由你决定后，按同一套验收（系统组件 + 材质 + 键盘可达性 + 无障碍文本）。
- [ ] 保留自绘的四处（Canvas 编辑器、思路板、材质降级、页面光晕）在代码注释与文档中都能查到理由。
