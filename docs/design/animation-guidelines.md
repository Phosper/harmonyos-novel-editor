# HarmonyOS 动效规范与 Weaver 落地（项目记忆）

> 记录日期：2026-10-21。后续改任何过渡/动画前先读本页，避免再出现“有动画但生硬”或“瞬间切换”。

## 官方依据

- [动效总览](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-animation-0000001750078484)
- [动效设计原则](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/animation-design-principles-0000001750237392)
- [动效属性（时长/曲线/帧率）](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/animation-attributes-0000001797117229)

## 原则（官方原文提炼）

1. **自然流畅**：帧率稳定、响应及时、跟手。
2. **简洁高效**：元素运动尽量少，减少不必要路径。
3. **快速响应**：短动画 150ms、局部 200ms、长距离不超过 350ms；不要用过长的位移。
4. **运动一致**：同一类动作使用同一路径/曲线，避免分散视觉焦点。
5. **隐藏等待**：用运动过渡减少等待焦虑。
6. **凸显品牌**：特效要克制，服务品牌调性。

## 时长与曲线（官方数据）

| 场景 | 时长 | 曲线 |
|---|---|---|
| 纯颜色变化 | 100ms | 线性/缓出均可 |
| 小范围（开关/图标） | 150ms | 标准曲线 |
| 局部（删除一条列表、侧栏） | 200–250ms | **标准曲线** `cubic-bezier(0.40, 0.00, 0.20, 1.00)` |
| 全屏（打开图片） | 350ms | 标准/减速 |

曲线选择：
- **标准曲线**：物体始终在视线内、起止都静止（侧栏收放、Tab、Switch）——本项目侧栏必须用它；
- **减速曲线**：从视线外新出现（弹框）；
- **加速曲线**：物体离场（窗口出场、卡片删除）；
- **弹性曲线**：可打断的物理运动；用 `springMotion(response, dampingFraction, overlapDuration)`，需要无缝打断/继承速度时使用。

**不要**对所有动画统一用 `EaseOut`：它一开始就接近峰值速度，物体在视线内收放时会显得“猛地启动、尾巴拖沓”，这是侧栏 180ms EaseOut 显得生硬的原因。

## 本项目令牌（`constants/Motion.ets`）

- `fast = 120ms`：hover/选中/颜色；
- `normal = 200ms`：面板、局部状态；
- `sidebar = 240ms`：侧栏/专注面结构变化；
- `slow = 300ms`：页面级结构；
- `standardCurve = 'cubic-bezier(0.40, 0.00, 0.20, 1.00)'`。
- 侧栏宽度使用 **临界阻尼弹簧** `curves.springMotion(0.4, 1.0, 0)`（无回弹、可自然打断）；
  内层透明度/位移用 180ms 标准曲线（展开延迟 40ms），形成“先柔和退场、再让位”的分阶段节奏。

## 侧栏实现要点（2026-10-21）

- 不再使用 `SideBarContainer.showSideBar` 直接翻状态（那是瞬时布局切换）；
- 宽屏 `wideBody` 自绘 Row：
  - 外层宽度 `showSidebar ? sideBarWidthVp() : 0`；
  - 内层 `ProjectSidebar` 固定宽度 + 外层 `clip(true)`，避免文字逐帧换行；
  - `opacity 1→0`、`translate x 0→-12`；
  - 外层宽度：`animation({ duration: Motion.sidebar, curve: curves.springMotion(0.4, 1.0, 0) })`；
  - 内层透明度/位移：180ms 标准曲线，展开时 delay 40ms；
  - 关闭后 `.enabled(false)`，避免隐藏内容被键盘/读屏聚焦；
  - 内容区 Navigation 常驻、`layoutWeight(1)`，不重建、不丢状态。

## 检查清单

- 起止是否静止？是 → 标准曲线；从视线外进入 → 减速；离场 → 加速。
- 时长是否在官方区间？局部 200–250ms，长距离 ≤350ms。
- 是否只动画颜色/透明度/位移/宽度，没有无意义的布局抖动？
- 是否可打断？可打断优先 spring；但宽度动画不要用欠阻尼，避免内容回弹。
- 关闭/隐藏的元素是否 `enabled(false)`，避免焦点落到不可见区域？


## 专注模式（2026-10-21）

- 专注面是独立 `FocusWorkspace`（每次进入重新挂载，入场在 `aboutToAppear` 自触发）；头部：`专注写作` 小标签 + 文稿标题 + 字数/保存态 + 退出专注胶囊；
- 正文隐藏重复标题，760vp 阅读列；入场用 `opacity 0.94→1 / scale 0.99→1 / translateY 8→0`，未完成态仍可见，避免空白页；
- 退出按钮先淡出/收缩 220ms 再恢复工作台；F11 之外的入口都走该动画；
- 空文稿占位文字已移入 Canvas，与光标同一行/基线/左边距（不再用 Text 叠加层）。


## 编辑器动效原则（2026-10-21）

- **内容即时、光标连续**：字符增删与 IME 上屏同帧完成，不做逐字入场/退场/让位动画；
  动画预算全部给光标。
- **光标**：临界阻尼弹簧（刚度 2400 / 阻尼 98，ω≈49）；**按输入节奏分流**：
  快速重复（<90ms）、大跨度编辑（>2.5 字符）、方向键连按（<80ms）一律同帧到位，
  只有慢速敲字与单字符删改播 140ms 弹簧；点击/方向键 160–200ms。
  动画期间常亮，落定后恢复呼吸。
- **选区拖动**：1:1 跟手，禁止任何插值（先停光标动画）。
- **滚动**：与光标动画解耦；滚轮按帧合并（后续 P1）。

## 一镜到底转场（2026-10-21）

- 用 `@hmanimations/ezcustomtransition`（Apache-2.0）的实现，**源码随仓库放在
  `entry/src/main/ets/thirdparty/ezcustomtransition/`**，不依赖 ohpm 安装，构建可离线复现；
- 触发：文稿列表行的 `ListItem` 带 `.id('doc_row_' + id)`；点击时 `generateLongTakeParam`
  抓行截图与几何，经 `LongTakeBridge` 暂存，`pushPath(WORKSPACE, { longTakeTransitionParam })` 消费；
- 目标：`WorkspaceDest` 用 `LongTakeTransitionDelegate` 包裹原内容，`onReady` 里
  `longTakeSession.init(...)`（`pop: nav.pop()`），动画期间背景取
  `longTakeSession.navDestinationBgColor`；返回手势与窗口尺寸变化由库接管
  （1.0.0 在库内 `WindowUtils` 监听 `windowSizeChange`，目标页无需 `setNewSize`）；
- 范围：只在**真的发生页面推进**的形态启用 —— 手机/平板（`MobileShell`）与
  窄窗下 AppShell 的列表→工作区；**宽屏三栏**工作区是常驻栏，不抓参数、走默认转场；
- 交互保护：转场期间 `Navigation.enabled(false)`（`navInteractive`），结束恢复；
- 配置变更：`MyAbilityStage.onConfigurationUpdate` → `ezCustomTransition.onConfigurationChanged()`。

## 顶部操作图标（2026-10-21 修订）

参考华为电子邮件（标准电脑）：顶栏只放**裸 Symbol 图标**，40vp 视觉基准 / 44·48vp 热区 / 20vp 图标 /
间距 12vp；静态完全透明，只有 hover·焦点·按下时浮出极淡圆底（120ms，无缩放、无位移），
**不再使用任何玻璃材质**。原生三键颜色跟随应用主题。详情见 [`top-action-buttons.md`](top-action-buttons.md)。
