# P4 只读导图（结构包）记录（2026-11）

- 状态：**代码完成、构建可证；真机未验证**（本机看不到设备，见 §4）
- 依据：用户确认"先做只读导图"；[ADR-003](architecture/adr-003-runtime-contract.md)（分包与挂载）、[ADR-002](architecture/adr-002-document-session.md)（大纲从标题派生、不建第二棵可编辑的树）
- 范围：**桌面 / MatePad Edge 电脑模式优先**；手机端排版等结构工具补全后再做

## 1. 做了什么

| 层 | 文件 | 说明 |
| --- | --- | --- |
| 契约（HAR） | [OutlineLayout.ets](../feature_contracts/src/main/ets/contracts/OutlineLayout.ets) | 大纲节点/快照、`buildOutline`（层级栈建树）、`layoutOutline`（叶子排 y、父节点取中点、x 按深度）、`outlineParents`（连线用）。全部纯函数，无 import |
| 宿主服务（HSP） | [OutlineService.ets](../core_runtime/src/main/ets/host/OutlineService.ets) | `publish / current / requestReveal / takeReveal / clear`：宿主导图之间的唯一通道 |
| 宿主侧抽取 | [OutlineExtract.ets](../entry/src/main/ets/editor/OutlineExtract.ets) | 正文 + 格式边车 → 标题列表 → 快照（按"覆盖段首的 run"取种类，行内加粗切碎也不丢） |
| 功能包（HSP） | [StructurePage.ets](../structure_feature/src/main/ets/pages/StructurePage.ets) | 只读导图：树形布局 + 贝塞尔连线 + 点主题回正文；空态引导；主题色由宿主注入 |
| 宿主接线 | `EditorPane`（标题行「导图」入口）、`AppShell`（全窗口分支 + 关闭后定位）、`UiStore.structureOpen`、`Index`（返回键先关导图） | 打开前 publish，关闭时 take |

## 2. 一条完整的用户路径

1. 在正文里把几句设成 H1–H3；
2. 点标题行右侧「导图」→ 整窗显示这棵树（根是文稿名，子节点按标题层级缩进）；
3. 点任意主题 → 关闭导图，正文滚动到该标题并把光标放过去；
4. 没有标题时显示空态，引导先设标题。

## 3. 与 ADR-003 的一处偏差（需要知道）

ADR-003 期望"整页功能走系统路由"。本轮改为**宿主直接 import 组件**（`from 'structure_feature'`），原因：

- 系统路由要 `router_map.json` + Navigation 的 `navDestination` 配合，失败表现是**空白页**；
- 本机看不到设备，无法确认路由是否真的渲染；
- 直接 import 的组件同样在独立 HSP 里（`.app` 中已确认打进去），包边界与依赖方向不变。

因此 `router_map` 作为**第二种入口**留到设备可用时补（对应交接稿 A-802）。这是可撤销的临时选择，不影响后续拆包。

## 4. 验证

| 项 | 结果 |
| --- | --- |
| clean 构建 | 0 ERROR / **105 WARN**（未新增告警；`ScrollDirection.Free` 已换成嵌套 Scroll） |
| APP 产物 | `hsp=2`：`core_runtime` + `structure_feature` |
| 回归 | 383 → **391 项**（新增 outline 6 项、modules 4 → 6 项） |
| 纯逻辑 | 建树层级、布局坐标、加粗切碎后仍识别标题、空大纲、快照根节点 |

未测（必须有设备）：
- 导图页在三形态下的实际排版（预期桌面可用，手机先不做）；
- 点主题 → 关闭 → 正文定位的完整链路；
- 长文稿（100+ 标题）滚动与绘制；
- 与输入法/焦点切换的相互影响。

## 5. 真机首轮反馈与修正（2026-11）

首轮截图暴露：**连线几乎没画出来**（只在根节点右侧留下一小段），整张图看起来是断开的。

根因与修法：

| 症状 | 处理 |
| --- | --- |
| `Path().commands()` 画出的曲线只剩一小段 | 连线改为 **Canvas + `CanvasRenderingContext2D`** 绘制（官方文档确认默认单位就是 vp，与布局坐标同一套；思路板点阵背景也是这个画法）。`Path` 的 commands 与组件尺寸单位在真机上不一致，不再使用 |
| 列间距偏挤（节点宽 220、列距 268，连线只有 48vp 可画） | `OUTLINE_COL_GAP` 268 → **300**，曲线有 80vp 空间 |
| 连线层抢命中 | Canvas 显式 `hitTestBehavior(HitTestMode.None)` + `accessibilityLevel('no')` |

仍未验证：修正后的真机观感（等下一张截图/复跑）。

## 5.1 真机第二轮：连线偏移/丢失的真正原因（2026-11）

第二轮截图（76% 与 100% 各一张）暴露两件事：**连线整体偏上、缩放后节点不动**，76% 时只剩根节点附近一小段线。

逐条查证（不再靠猜）：

| 现象 | 证据 | 结论 |
| --- | --- | --- |
| `Path().commands()` 只画一小段 | SDK 声明 `component/path.d.ts`：`commands` 的 **Default unit: px** | 首轮判断"单位不一致"是对的，原因就是 px/vp 混用；`Path` 不能再用于 vp 布局 |
| `Canvas` 画出来还是偏 | `CanvasRenderingContext2D` 默认单位确实是 vp（`canvas.d.ts` 全篇 `Default unit: vp`），坐标没错；错的是**时机**——画布是独立绘制面，尺寸/就绪都晚于节点布局，缩放的一瞬"节点已重排、线还按旧尺寸画" | Canvas 这种"自己拉一块面再画"的模型与 vp 布局天生有一帧时差 |
| 缩放后节点不动 | `ForEach` 的键是 `paraId`，缩放不改变身份 → 键不变 → ArkUI **复用旧子组件、不再执行构建函数**，`.position()` 与 `.width(OUTLINE_NODE_W * scale)` 都停在旧值 | 键必须带"布局版本"，否则任何"同一批节点换位置"都渲染不出来 |

修法（`02a8b51` 之后的重做）：

- 契约包新增 `OutlineWire` + `outlineWires()`：把每条贝塞尔连线**采样成 12 段**，算出最小包围盒（含 2vp 描边余量）与相对坐标点序列。纯函数，Node 可回归。
- 渲染层改用 **`Polyline`**（不是 Canvas、不是 Path）：`Polyline.points` 的单位是 **vp**（`polyline.d.ts` 写明），与节点的 `.position()` 同一套坐标、同一次布局 → 结构上不可能错位，也不再需要 `onReady / onAreaChange / setTimeout` 重画。
- 节点与连线的 `ForEach` 键都拼上 `layoutRev`（每次 `applySnapshot` +1），保证重排一定重建。
- 回归：`outline-regression` 9 → **11 项**（采样点不越界、端点贴合、包围盒随缩放收窄、水平线不会被压成 0 高）；全仓 456 → **458 项**。

顺带发现（未改，另案）：思路板 `shell/CanvasEdges.ets` 仍用 `Path().commands()` 传 vp 坐标，按上面的证据，DPR ≠ 1 时那里的连线也会整体缩小。若用户反馈思路板连线偏小，同一套 `Polyline` 换法即可。

## 5.2 M3：组织与形态（2026-11）

按 `docs/design/mindmap-plan-2026-11.html` 的 M3 做了一半（拖拽重排没做，见下），同时把思路板连线一起修了。

| 能力 | 做法 | 验证 |
| --- | --- | --- |
| 折叠/展开 | 视图集合按 `paraId` 存（不进正文、不进版本号）；有子节点的节点外侧出现徽标：展开显示「−」、折叠显示子节点数量（幕布做法）；空格键折叠选中的一节；折叠后出现「展开全部」 | 回归 4 项（数量不受折叠影响、折叠后子树不参与布局） |
| 左右均衡布局 | 照 markmap 的 `splitBranches`：一级主题按"叶子权重补到较轻的一侧"分左右，更深层继承父级；左侧按根中心镜像（列间距与连线长度和右侧一致）；只有一侧有主题时退回全向右 | 回归 3 项（两侧都有、左侧不越界、右侧几何与旧版完全一致） |
| 连线跟着朝向 | `outlineConnectors` 按子节点 `side` 决定端点：朝右是「父右缘 → 子左缘」，朝左镜像成「父左缘 → 子右缘」 | 回归断言端点镜像 |
| 思路板连线 | `CanvasEdges` 的 `Path().commands()`（px）换成采样 `Polyline`（vp）：曲线 16 段 + 箭头三点折线，共用包围盒 | 构建 + 静态回归；**真机未测** |

还没做（M3 剩下的）：

- **拖拽重排**：需要"上/中/下三区判定 + 长按再拖"来避开外层滚动与卡片手势的竞争（方案稿 §09 列为高风险项），本轮不做；键盘 `Alt+↑↓` 已经能搬整节。
- **视口裁剪**：节点仍是全量实例化（`ForEach` 全建）。左右均衡后地图更宽，200+ 标题时才需要，留到 M4 一起做（配合连线增量重绘）。

## 6. 下一步

1. 设备可用后先跑一遍上面的 4 条未测项；
2. 补 `router_map` 第二入口（A-802），确认"按名跳转"与"未安装降级"；
3. 进 P5：段落稳定身份 → 导图才能从"只读"升级为"可编辑"（拖动节点带走整节正文）。

## 7. 已列入计划但未开工

**EPUB 导入**：见计划 `p7-epub`。要点：按章拆分文稿、保留书名/作者/目录顺序，图片与样式降级为纯文本并明确提示；放在 P7 专业工具阶段与导入管线一起做。
