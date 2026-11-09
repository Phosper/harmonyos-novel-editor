# ADR-003：共享运行时、功能契约与挂载

- 状态：**提议（待你批准）**；对应交接稿 A-805、决策 D05/D06
- 日期：2026-11
- 影响：模块划分、依赖方向、动态挂载、安装态与窗口态

## 1. 背景

当前只有一个 `entry` 模块：所有能力（写作、思路板、素材、关系）都在主包里，
`AppStores` 启动即加载全部数据，`Repos` 导出仓储单例供任意 UI 直接 import，
`AppShell` 静态 import 可选页面并用 `app.ui.canvasOpen` 这类全局布尔切换（H01–H08）。

目标：不装任何扩展也能完整写作；扩展按需获取、按会话挂载；**同一篇文稿只有一个会话与保存链**。

## 2. 决策

### 2.1 包划分（建议名）

| 包 | 类型 | 装/加载 | 放什么 | 绝不放什么 |
| --- | --- | --- | --- | --- |
| `entry` | HAP | 随应用安装 | 窗口/生命周期、根路由、FlowText 宿主、基础文稿 UI、功能目录与安装反馈 | 可选功能的页面实现 |
| `core_runtime` | HSP | 始终安装 | DocumentSession/命令服务、仓储、备份、附件、宿主运行服务 | 对任何可选包的依赖 |
| `feature_contracts` | HAR | 编译期共用 | 类型、接口、纯规则（编号/深度/校验） | **单例、注册表、可变全局状态** |
| `structure_feature` | HSP | 按需 | 大纲、文稿绑定导图、Pitch（单屏） | 第二套正文编辑器 |
| `board_feature` | HSP | 按需 | 思路板、卡片库、语义关系 | 证据/卡片的持久化协议（归 core） |
| `novel_feature` | HSP | 按需 | 人物/设定、卷章场景、时间线 | 正文存储 |
| `research_feature` | HSP | 按需 | 文献库、PDF 批注、引用处理 | 引用标记的持久化协议（归 core） |

### 2.2 依赖方向（硬约束）

```
entry ─┬─> core_runtime ──> feature_contracts
       └─> feature_contracts
optional HSP ──> core_runtime + feature_contracts      （不得依赖 entry，不得互相依赖）
```

- 反向依赖一律编译期禁止；`entry` 不得被任何包 import。
- 契约包无状态：多包各自编译一份也不会产生"两份运行状态"。
- 跨包共享运行状态**只能**由 `core_runtime` 注入（验证 MT19：两个 HSP 编辑同一 Document）。

### 2.3 HostServices（可选包唯一能拿到的能力）

| 能力 | 形态 | 约束 |
| --- | --- | --- |
| 文稿读取/命令 | `readProjection(docId)` + `dispatch(command)` | 命令带目标与预期版本；过期返回失败 |
| 实体解析 | `resolveEntity(kind, id)` | 只读；失效返回带可读标签的降级对象 |
| 附件 | `openAttachment(id)` | 返回句柄/路径，生命周期由调用方释放 |
| 来源锚 | `resolveAnchor(anchor)` | 复用 P1 的四态结果 |
| 导航 | `openFeatureRoute(name, params)` / `back()` | 参数只传身份与返回令牌 |
| 环境快照 | `theme() / window() / inputModality()` | 只读快照，不暴露 UiStore |
| 订阅 | `subscribe(scope, cb) → lease` | `lease.dispose()` 只清本次订阅 |

明确禁止：向可选包公开 `AppStores`、`UiStore` 或正文 DAO。

### 2.4 FeatureSession 生命周期

```
open(intent) → 校验能力/目标 → （缺包则安装）→ 挂载 Surface → ready
   → update(patch)（显式推送，不靠隐式全局）
   → hide()/show()
   → checkpoint()（必须保存的内容，同步语义）
   → dispose()（幂等：解除订阅、释放节点/句柄/计时器）
```

- `ready` 之前不得假定 UI 可用；`dispose` 不等于卸载包，也不清数据。
- 关闭时"必须保存"的内容走 `checkpoint()`，不能只发起异步调用就消失。

### 2.5 OpenIntent（一次打开请求）

字段：`intentId / windowId / projectId / docId 或 entityId / surface / 请求代次 / 返回令牌`；
捕获类操作额外带**不可变快照**（文本 + 版本）。

- 窗口/项目/目标在安装期间变化 → 该 intent 作废，迟到完成不得跳页。
- 路由参数只传身份与令牌，不传可变对象或整篇正文。

### 2.6 四种状态分开管

| 维度 | 取值 | 作用域 |
| --- | --- | --- |
| PackageState | 未安装 / 获取中 / 已安装 / 不兼容 | 安装实例 |
| RuntimeState | 未加载 / 加载中 / 可用 / 激活失败 | 当前进程 |
| SurfaceState | 创建中 / 已挂载 / 隐藏 / 已释放 | 某窗口某位置 |
| ProjectPreference | 项目启用/隐藏哪些工具 | 项目 |

不允许用一个 `enabled: boolean` 同时表达这四件事。

### 2.7 挂载位置分五类

| 位置 | 适合 | 载体 |
| --- | --- | --- |
| 全窗口目的地 | 思路板、文献库、独立阅读 | 根级系统路由（`router_map`）+ NavDestination |
| 工作区主视图 | 大纲、导图 | WorkspaceSurface 受控构建（不新开草稿） |
| 编辑旁栏 | 人物、证据、引文 | InspectorSurface（正文会话不销毁） |
| 短时选择 | 选卡、选文献 | 宿主 Dialog/Sheet，关闭后恢复选区 |
| 观众窗口 | Pitch 高级播放 | 独立窗口 + 只读快照 |

**当前 `Navigation` 在多栏结构里，注册新路由只会替换内容区**；因此需要一个宿主级功能导航层，
把"文稿多栏工作台"当成它的一个目的地，而不是继续往 `AppShell` 加布尔分支。

## 3. 从现有代码迁移的顺序

1. **抽契约**：把 `CanvasTypes` 的纯规则、`SourceAnchor`、`MarkdownBlocks` 等无状态模块搬进 `feature_contracts`（只搬纯函数）。
2. **抽核心**：`DocumentSession` + 命令服务 + 仓储 + 备份进 `core_runtime`；`AppStores` 退化为"外壳编排"，不再被可选包引用。
3. **建原样**：先用一个"空壳" `structure_feature` HSP（只有一个占位完整页）打通系统路由与安装态。
4. **接旁栏**：`InspectorSurface` 先接一个只读面板（如人物卡片），验证正文不销毁、IME 不被抢。
5. **搬可选 UI**：思路板 → HSP；小说/文献按 M5/M6。

每一步都必须保持 `entry` 单独可编译、可写正文；**先证伪再拆全**。

## 4. 后果

- `AppStores` 的六片 Store 需要重新划分：文稿相关进 `core_runtime`，UI 状态留在 `entry`。
- `Repos` 单例不再对外导出；可选包只能通过 HostServices。
- 构建配置（`build-profile.json5`、`oh-package.json5`、`module.json5`、`router_map.json`）要逐项核对。
- 需要真机验证：安装/卸载/断网/迟到完成/双窗口（MT01–MT12、MT19、MT20）。

## 5. 本 ADR 不决定

1. 具体的下载/安装 API 封装（`moduleInstallManager` 仍需按目标 SDK 适配验证）。
2. 应用插件（独立更新）路线：区分但不承诺。
3. 视觉稿与窗口标题栏样式。
4. Pitch 的双屏/外接实现（A-809 单独验证）。

## 6. 验收

| 用例 | 期望 |
| --- | --- |
| MT01 | 只装基础包：新建、中文写作、保存重开完整可用 |
| MT03/MT04 | 下载→安装→打开；取消/失败不白屏、原文与选区安全 |
| MT05–MT09 | 并发请求合并；切文稿后迟到完成不跳页；激活失败可回退 |
| MT10/MT11 | 跨包整页可达；旁栏打开不销毁正文会话 |
| MT19 | 两个 HSP 同时读写同一 Document：一个会话、一条保存链 |
| MT20 | 两个窗口各自的功能会话互不干扰 |
