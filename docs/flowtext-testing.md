# FlowText 与桌面窗口回归测试

当前工程使用 HarmonyOS API 26，需 DevEco Studio 26.0.0 或配套 Command Line Tools。编辑器用例使用 `ohosTest` 隔离画布；窗口用例启动真实应用、查看引导页，不输入或删除文稿。运行前先保存真实应用草稿，测试时保持模拟器解锁且不操作窗口。下列 API 23 结果为升级前历史记录。

2026-10-06 验证结果：主包、测试包均编译通过；MateBook Pro 2in1 模拟器（HarmonyOS 6.1 / API 23）18 项测试全部通过；本地 33 项回归检查及其中的 766 组 Unicode 官方样例通过。最终源码关闭了诊断日志。

2026-10-13 修复版验证结果：主包与 `ohosTest` 测试包在 SDK 6.1.0 / API 23 编译通过；69 项本地回归检查（含 766 组 Unicode 官方样例）通过；MateBook Pro 2in1 / API 23 模拟器 22 项原生测试全部通过，Failure、Error、Ignore 均为 0。

2026-10-13 桌面标题栏修复验证结果：主包与测试包编译通过；本地回归增至 86 项；MateBook Pro / API 23 分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。原生键盘用例在聚焦、每次输入后等待 UI 空闲，并逐步检查选区，避免把异步输入尚未落定的状态当作结果。

2026-10-13 API 26 构建验证：使用官方 Command Line Tools 26.0.0.851、SDK 26.0.0.105、Hvigor 6.26.8、Node.js 24.14.1、JDK 21，主包与测试包编译通过，86 项本地回归通过。两包的 `compileSdkVersion` 均为 `26.0.0.105`，打包后的最低/目标 API 值均为 `260000026`（API 26 编码）；当前 `compatibleSdkVersion` 为 `26.0.0`，旧 API 23 模拟器不能用于此轮安装测试。

2026-10-14 API 26 最终验证：修复输入法空提交后重新构建主包与测试包，88 项本地检查通过。新建独立 `WeaverAPI26` / MateBook Pro 模拟器，镜像为 HarmonyOS 7.0.0.107；实际设备参数 `const.ohos.apiversion=26`、`const.product.devicetype=2in1`。在 `127.0.0.1:12326` 分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。生产诊断日志已关闭。

2026-10-17 错误检查验证：使用同一 API 26 工具链重新构建主包与测试包，均成功。本地 FlowText 52 项、数据 28 项、外壳与导出 20 项、窗口 17 项、导入 5 项，共 122 项全部通过，另含 766 个 Unicode 样例。在独立 `WeaverAPI26` / API 26 / 2in1 模拟器运行编辑器与文件 I/O 25 项、窗口 3 项，共 28 项，Failure、Error、Ignore 均为 0；该次测试实例使用 2 GiB 内存。

本轮新增用例先重现原错误再验证修复：延迟粘贴在文稿重载、销毁或 activeId 先切换时不能写入新文稿，旧画布的编辑、光标、保存、撤销与重做均检查归属；粘贴替换选区和预上屏范围，撤销/重做后的新输入不合并进旧历史，折叠光标在段首可设置标题。数据测试强制项目、筛选及素材查询乱序，检查当前列表和备份的项目归属；恢复事务已提交后刷新失败仍报告成功，首次默认项目及删除末个项目后的替代项目正常出现在侧栏。文件测试覆盖中文/表情跨块短读、提前 EOF、UTF-8 短写、零写入进度、异常关闭和带格式 TXT 的字面符号保真。

API 26 输入法切换语言时会发送空 `insertText`；无组字状态时空提交应为无操作，不能删除选中文字、清除选区方向、改变格式或写入历史。新增回归在修复前重现 `ABCDE → ABCE`，修复后保留正文及 `3..4` 选区，后续 Shift+Left 继续扩到 `2..4`；空预上屏完成仍能替换原范围。本地 FlowText 回归增至 39 项，总计 88 项。

## 本地逻辑测试

需要 Node.js 24 或以上，在工程根目录执行：

```powershell
node tools/flowtext-regression.cjs
node tools/data-regression.cjs
node tools/shell-regression.cjs
node tools/window-regression.cjs
node tools/import-regression.cjs
```

执行实际 ArkTS 模型和选定组件方法，图形与输入法接口使用受控替身。覆盖误删、选区方向、加载恢复、格式事务、跨文稿历史、组合态、缓存、动画和连接竞态；另执行 Unicode 17 官方 766 组字素边界样例。此测试不能替代系统字体和输入法验证。

2026-10-13 的新增回归：FlowText 37 项、数据层 19 项、外壳与文件导出 13 项。数据层运行实际 DAO、仓储和状态类，覆盖恢复事务与自动保存隔离、保存失败/超限保留草稿、保存队列、导出内存快照、格式恢复、异步选稿与新建项目重试；外壳测试运行实际事件方法，并用真实本地文件验证覆盖截断与资源关闭。数据库、系统选择器和界面生命周期在这些本地测试中仍使用受控替身。

桌面窗口 17 项运行实际配置函数、窗口按钮方法和 EntryAbility 生命周期，覆盖内容加载后配置、前台重配、销毁与旧窗口回调、手机和平板排除、原生标题/三键/顶部热区独立失败处理、仅左键拖动，以及最大化和还原成功之后才重新应用隐藏设置。

文件导入回归运行实际 ImportService，以真实临时文件强制短读，检查跨块 UTF-8 中文和表情、提前 EOF、读取异常与句柄关闭、字节上限以及取消选择。原生测试另读取超过 64 KiB 的临时文稿，验证实际 HarmonyOS 文件指针和解码行为；TXT 导出也检查带格式正文中的字面标记不丢失。测试只读写自行创建的临时文件。

## DevEco 编译和设备测试

在配套工具中完成依赖同步，启动 API 26 或以上的模拟器或连接设备，查看 `hdc list targets`，然后执行：

运行 UI 用例前先进入模拟器桌面，确保屏幕已解锁；锁屏会阻止测试画布显示与获得焦点。

新建 API 26 电脑模拟器首次安装应用后，系统可能询问是否自动添加至桌面。先处理该系统提示再运行 UI 用例，否则它会遮挡测试画布。官方模拟器实例名只接受字母、数字、空格、下划线和加号；本次使用 `WeaverAPI26`。

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -Device '<hdc list targets 中的设备>'
```

`DevEcoRoot` 可为 DevEco Studio 或 Command Line Tools 根目录，`Device` 换成实际设备；CLI 未带 JDK 时用 `JavaRoot` 指定本机 JDK 21。仅编译可加 `-BuildOnly`。脚本检查实际 SDK 不低于目标 API、设备 API 不低于最低兼容版本，条件不符时拒绝构建或安装。脚本分别构建主包和 `ohosTest`，安装后分组执行编辑器与窗口 Hypium 用例，每组从关闭应用的状态启动，单用例超时为 20 秒。根据完整汇总判断 Failure、Error、Ignore 均为 0 且 Pass 等于 Tests run，避免误把系统命令退出码 0 当成全部通过。两组日志分别保存到 `tools/.test-results/device-tests.log`、`window-tests.log`。

设备测试使用真实 ArkGraphics2D 排版、CanvasTextEditor 和系统键盘事件，覆盖混排索引、表情、复杂文字、标题度量、密度换算、空段落、换行、宽度变化、格式同步和键盘选择。实际手机需配置自己的调试签名。

新增四项原生排版用例：原生行内索引契约、窗口外格式不得重复正文、非零窗口起点与 emoji 偏移换算、多段落跨越 4000 码元窗口。跨窗口用例同时检查软折行与后续窗口的点击/光标往返。实际执行结果应检查 Hypium 的汇总，而不是只依据测试包编译成功。

三个原生桌面用例验证真实 EntryAbility：内容加载后隐藏系统标题与三键；自绘按钮最大化、顶部鼠标悬停/点击、再还原，均不出现系统标题；窄窗口仍保留自绘按钮并可用鼠标拖动，引导页保留窗口控制。窗口用例只在 2in1 设备执行。

系统常驻标题、右上角三键和全屏顶部热区需要分别配置，依据见[华为沉浸式窗口适配说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1089)。隐藏配置须在内容加载后调用，最大化与还原完成后重新应用；自绘 36vp 高度不传给原生装饰高度接口。

键盘测试还验证框架焦点。Canvas 本身不能获焦，编辑器使用可获焦子节点和 `tabStop` 容器；依据见[华为焦点控制文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/ts-universal-attributes-focus-V14)。

连续按键测试在隔离页面观察每一组目标键和修饰键的实际 Up，最多等待 5 秒，然后等待 UI 空闲并检查原来的严格选区结果。每组只注入一次，未确认释放时不开始下一组；UI 空闲本身不能保证注入序列处理完。相关实现见 [UITest 组合键序列](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/core/ui_action.h) 和 [系统事件注入](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/server/system_ui_controller.cpp)。

Unicode 数据可用 `python tools/generate-grapheme-data.py` 从已保存数据重新生成；只有更新数据时才需要 `--download`。数据版权与许可见 `tools/unicode/LICENSE.txt`。

尚需单独验收：不同厂商中文输入法的候选交互、手机触摸手柄、五万字持续输入帧率与内存、读屏编辑能力。通过这些回归用例不代表所有设备体验已经验收。

## 2026-10-18 文字漂移与多选异常修复

本轮针对"字形/光标/选区几何不一致、滚动跳变、多选手势状态残留"做修复，新增回归一律先能复现旧错误，再验证修复。

**本地回归**：FlowText 60 项（新增 8 项）、数据 28、外壳 20、窗口 17、导入 5，合计 **130 项**全部通过；仍含 Unicode 17 官方 766 组字素样例。

新增/加强的检查：
- `multi-run lines get their own line-relative origin`：多 run 行的 run 原点由 `line.getOffsetForStringIndex` 反推，run 内字形用 `positions[i].x - positions[0].x` 归一；点击落在第二个 run 时不再误判到第一个 run。
- `selection stores anchor/head; handle crossing never swaps identity`：选区只存 anchor/head，start/end 由 min/max 派生；手柄越界只改自己的端点，方向由 headAffinity 表达。
- `caret affinity picks the same visual side as the selection highlight`：软换行边界 DOWNSTREAM 贴上一行行尾、UPSTREAM 贴下一行行首；光标盒与 `lineBox` 一致。
- `dragging a selection keeps the drawn caret at head`：拖选/反向拖选时绘制光标跟随 head，而不是停在锚点。
- `Ctrl+A updates caret, callbacks and IME once`：全选同步 caret/选区回调/IME 上报。
- `clampScroll never resets to top while the layout cache is still empty`：改字号/改宽度重建引擎时不再把 scrollY 夹回 0。
- `undo/redo reload preserves scroll; document switch resets it`：撤销/重做回灌保留滚动位置，换文稿才回到文首。
- `preview text is drawn once, in the same run origin and baseline`：预上屏只画一次，字形总数与正文一致（旧 `drawNow` 未传 preview，预览与正文同色；`drawPreview` 为死代码且基线偏移）。

**新增原生用例**（`entry/src/ohosTest/ets/test/FlowText.test.ets`）：多 run 行原点、软换行 affinity、caret 与 lineBox 一致性、手柄越界身份固定。运行方式不变：

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -BuildOnly
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -Device '<hdc list targets 的设备>'
```

**手工验收清单（每项保存 before/after 截图或录屏到 `artifacts/`）**：
1. 中英混排/加粗/标题行：文字不重叠，点击定位准确，选区与字形对齐。
2. 长文中部改字号/行距：不跳回顶部，光标仍在视口内。
3. 切换四套主题：不跳回顶部，字形基线不跳。
4. 拖宽/缩窄窗口、旋转、开关侧栏：重排后阅读位置保持。
5. 五万字滚到底 + 底部连续回车：无回弹；fling 到边界立即停。
6. 中文拼音组字：预览只出现一次、与正文同基线；提交无跳动。
7. 正向/反向拖选：光标在 head 端，高亮跟随；松手只弹一次菜单。
8. 长按选词后继续拖动：从词边界扩展，不重置为按下点。
9. 拖动两端手柄并越过对端：方向翻转、不跳变；拖到屏幕边缘自动滚动且选区不滞后。
10. Ctrl+A / Shift+方向键 / Home/End / 三击：选区、光标、工具栏态同步。
11. 跨空行/跨段/标题行选区：空行有高亮、行间无缝、标题行高亮与光标同高。
12. 触摸 Cancel（来电/返回手势）、鼠标拖出窗口释放：无残留选区/菜单/卡住。

**本轮残余风险**：RTL/bidi 的 run 原点仍只按 LTR 近似；`changeSelection` 仍要求整篇文本（已做 32ms 节流）；惰性排版的锚点恢复为近似（±1 行）；真实设备上的字体回退/手柄手感需按上述清单人工确认。

## 列表 / 待办段落（渲染 A 阶段，2026-10-22）

**范围**：段落种类渲染与命中（• 列表、○ 待办、✓ 已完成 + 删除线、悬挂缩进、点符号切换完成态）、工具栏段落下拉、Markdown 导出、**回车语义**（列表段回车续列表并继承层级、空列表项回车退出列表）。**Tab 改层级 / Backspace 降级**仍未接线（当前 Tab 有意交还系统做焦点遍历，改动需同步调整既有快捷键契约用例），下一阶段单独提交。

**数据模型**
- 段落种类存于 `FormatRun.heading`：`0` 正文、`1/2/3` 标题、`4` 列表、`5` 待办、`6` 已完成待办（`ParagraphKind.TODO_DONE`）。层级存于 `FormatRun.indent`（0–2，上限由 `EditorTypes.MAX_LIST_LEVEL` 单点定义）。
- 段落属性区间**含段末换行符**（`TextDocument.paragraphAttrsBounds`），否则空段落没有字符可承载属性。
- 段落种类查询只认"带段落语义"的 run（`heading`/`indent` 非 0）：行内加粗/斜体切出的 `heading=0` 分段不会再把列表读成正文（该边界有专门回归）。
- 删除段内全部文字会**保留**该段的列表/待办种类（下次输入仍在列表里）；文档**末尾**的空段落没有换行符，属性以"待生效"形式暂存，第一批字符插入时落成真实 run，并随"在它之前发生的插入"平移。

**项目符号绘制（纯几何，不依赖字体字形）**
- `•` = 实心圆点（层级越深越小：0.20em / 0.15em / 0.10em）；`○` = 空心圆环（`drawing.Pen` 描边，直径约 0.8em）；`✓` = 同一圆环 + 对勾路径（`drawing.Path` + `drawCircle`/`drawPath`）。
- 上一版用字体里的 `• ○ ✓` 字形画，设备默认字体缺 `✓` 时勾选后整块空白（"符号消失"），因此改为几何绘制；`✓` 与圆环共用同一坐标中心，字号/密度变化自动跟随。已完成项仍叠加文字删除线。

**排版/绘制几何**
- 文本列左偏移 `inset = indent × 24vp + (isList ? 字号 × 1.2 : 0)`；**首行与软折行续行共用同一 inset**（悬挂缩进），项目符号只画在段落首行。
- 折行宽度 = 列宽 − inset（`TextLayoutEngine.availableWidthPx`）；回归里用替身记录 `getLineBreak(start, width)` 实际收到的宽度，确认列表段真的按 356.8px（400 − 43.2）断行，正文段仍是 400px。
- 命中/光标/选区/字形动画全部走同一 inset：`hitTestRaw` 减 inset、`offsetToX` 加 inset、空行选区与占位文字从 `paddingLeft + inset` 起算、`GlyphAnimator` 的字形坐标加 inset。
- 打字机缩放的上界取 `列宽 / (inset + 行宽)`：缩放轴心是列左边缘，inset 本身也会被放大。

**导出**
- Markdown 导出按种类分派：标题 1–3 → `#`×n；列表 → `- `；待办 → `- [ ] `；已完成 → `- [x] `，层级用两个空格缩进。旧实现直接 `'######'.substring(0, level)`，会让列表段变成 `####`–`######` 假标题（已修，并有导出回归）。

**本轮本地回归**（本机 OpenEuler，Node v22.23.0，三套均 exit=0）
- `node tools/arkts-guard.cjs` → 19 项通过（38 文件，2 条历史 console 警告）
- `node tools/flowtext-regression.cjs` → **127 项通过**（原 98 + 29：indent 往返与保留、层级钳制、空末段待生效与平移、空文档段落种类、删空保留列表、行内 run 不遮蔽段落种类、列表 inset/悬挂缩进/折行宽度收窄、命中与光标 inset、符号/删除线绘制、工具栏开关语义、混选统一设种类、回车续列表/继承层级/段中分裂/空项退出/单事务、段首插入不丢样式、圆点单击只切一次/文字区不消费/空待办项可勾/列表符号不响应）
- `node tools/shell-regression.cjs` → **54 项通过**（⋯ 菜单扩为 8 项；新增列表/待办 Markdown 导出断言）

**边界行为（本轮已固化）**
- 文档以换行开头：首行是空段落，`paragraphBounds(0)` 必须返回 `[0,0]`（旧实现会算出 `[1,0]` 的非法区间，导致首段属性读写全错、排版把空首行读成第二段样式）。
- 删除换行合并两段：合并段跟随**前一段**的段落属性，后一段的残留属性不会"复活"。
- 全选到文末且末段为空：空末段同样获得段落种类（走待生效路径），继续输入仍在列表里。
- 在末尾空列表项之前插入/删除字符：待生效属性跟着平移，不会被清掉或落到别的段落。
- 点待办圆点 = 切换完成态，走唯一入口 `toggleTodoAtMarker`：PC/2in1 上一次单击会同时派发 `onMouse(Press)` 与合成的 `onTouch(Up)`，同段落 120ms 内的第二次派发被识别为同一次点击（否则 5→6→5，表现为"单击没反应、只能长按"）。列表的 • 不响应点击；按在圆点上也不再启动长按选词（否则按住稍久就变成选词、勾选失效）。
- 回车（输入法 `insertText('\n')` / 软键盘回车 / 物理键盘 Enter 汇到同一处）：列表段回车后新段继承种类与层级，原段保留符号；空列表项回车只退出列表、不新增段落。"换行 + 继承段落种类"在同一个编辑事务里完成，撤销一次整体回退。

**已知限制 / 未验证**
- "空末段待生效属性"是瞬态：不参与 `onEdit` 历史与落库，空列表项不打字就切走或撤销会丢失（IME 组字期间已搬到预览克隆，不会闪烁）。键盘阶段一并做成文档级状态。
- 项目符号/✓/删除线是 Canvas 自绘（几何图形，不依赖字体），读屏目前读不到"列表/已勾选"语义（无 `accessibilityVirtualNode`）。真机上圆环线宽（0.085em）与对勾比例是否符合 HarmonyOS Symbol 观感，需要截图确认。
- 本地回归脚本的 `EditorStore` 落库路径没有真正执行：`compile()` 会剥掉 import，`exceedsContentLimit` / `chapterRepo` 在 vm 里缺失，`flushActive` 每次都走进 catch。因此本地用例验证的是内存态历史栈与格式侧车，**不是入库**；落库仍需 `ohosTest` 原生用例。
- 未在真机验证：符号在真实字体的落位与大小（默认字体缺 `✓`/`○` 会显示豆腐块）、手指点符号的手感、24vp 缩进与删除线粗细的观感、多设备（手机/平板/折叠）下的显示效果。设备侧执行方式同上一节 `tools/Test-FlowText.ps1`。

## 输入法与选择滚动修正（2026-10-25）

**A. 电脑模式：方向键让位给输入法**

- 现象：中文输入时按 ↑/↓，正文光标在跳，输入法候选词不动。
- 根因：`shouldConsumePreIme`（`interaction/InputArbiter.ets`）对**所有**走位键无条件 `return true`（① onKeyPreIme 阶段先于输入法）；而"组字态"只认 `previewMgr.isComposing`——部分桌面输入法把候选窗画在自己的窗口里、不回传预上屏文本，于是组字态被判定为 false，方向键在 ① 就被编辑器吃掉。
- 修法：`shouldConsumePreIme` 增加第 4 个参数 `imeFirstArrows`；键鼠形态（`desktopMode || pointerPrimary`）下四个方向键不在 ① 消费，交给输入法移动候选词；输入法不消费时按键会继续走到 ③ `onKeyEvent`，由编辑器移动光标（与字符键/数字键同一套兜底）。Home/End/PgUp/PgDn 仍由编辑器在 ① 截获；Ctrl+方向是词移动，不会被让出。组字态（`composing`）下所有走位键与 Esc 都放行，触摸形态行为不变。

**B. 拖选 / 长按扩选：贴边自动滚动**

- 现象：长按选到屏幕边缘后，手指停住就不再滚，选不到视口外的文字。
- 修法：`updateAutoScrollSelection` 在拖选/长按扩选时检测是否进入上下边缘带（`max(36vp, 1.5×行高)`），进入后用 60ms 定时器持续滚动；每个 tick 都用**滚动后的坐标**重新命中并扩展选区，所以手指不动也能一直选下去。离开边缘、抬手、Cancel、鼠标收口、组件卸载都会停表。手柄拖拽保留原有 1:1 跟随。

**本轮本地回归**：`flowtext-regression` 132 项（新增 5：组字态让位、键鼠方向键让位、③ 兜底移动光标、贴边滚动持续滚/松手停）；其余套件数字不变。

**未验证**：真机桌面输入法在"未组字态"是否会消费方向键（不消费时靠 ③ 兜底移动光标，这条依赖平台按键派发顺序）；Shift+方向扩选在键鼠形态下同样先经输入法；贴边滚动速度（60ms/步、约 0.8 行）与长按选词边界的交互；候选窗整页翻页手感。

## 交互卡顿与桌面/触摸适配（2026-10-25 第二轮）

**1. 拖选/滚动卡顿**
- 根因：鼠标（120Hz）与触控板的每个 Move / axis 事件都直接 `drawNow`（清屏 + 整个视口重画），并且每次都 `emitSelection` 写 store（caret / `selectionTick` / 输入法 `changeSelection`），工具栏与列表跟着每秒上百次重算。
- 修法：新增 `requestDraw()` 把高频重绘合并到 16ms 一帧（手势收口 `flushDraw()` 立即补齐）；拖选期间选区/光标上报按 60ms 限频、滚轮按 32ms 限频，抬手仍 `emitSelection(true)`。

**2. 动画互相叠加**
- 根因：光标呼吸定时器在光标弹簧 / 惯性滚动 / 平滑滚动期间也会重绘（同一帧画两次）；波形两端 alpha 变化 <0.02 的帧也照画。
- 修法：`caretAnimating / scrollAnimating / flingTimer` 期间呼吸不重绘；alpha 变化 <0.02 跳过；`scrollToAnimated` 加 `scrollAnimating` 标记。
- 另外：零距离光标移动（IME 回声 / 选区同步）不再跑整段弹簧，直接落定；占位文字颜色的十六进制解析按字符串缓存，不再每帧 `parseColor`。

**3. 桌面与触摸的差异**
- 鼠标拖选时轻微上下移动会把视图滚走 → 桌面边缘带由 1.5 行收窄到 **14vp**，并要求在边缘**停留 180ms** 才起滚；触摸保持 36vp 宽边带（手指抖动需要容错）。
- 桌面此前没有双击选词（触摸有双击/三击，鼠标只有右键）→ 鼠标 Press 单独做连击判定（400ms / 6vp），双击按词选中并弹出操作浮层；触摸的连击计数与鼠标互不干扰。

**本轮本地回归**：`flowtext-regression` 136 项（新增 6：重绘合并/上报限频、鼠标/触摸边缘带、鼠标停留 dwell、零距离弹簧跳过、占位色缓存）。

**未验证**：真机帧率（无 Profiler 数据，无法量化"卡顿"改善幅度）；180ms 停留等待的手感；双击选词与右键选词的叠加行为；触控板 axis 事件的 32ms 上报限频是否影响光标跟随感。

## 指针拖选松手后选区回跳（2026-10-25 第三轮）

- 现象：鼠标（含触控板）拖动选中超出原选区的文字，松手瞬间选区又跳回按下点/最初的词。
- 根因：PC/2in1 上一次鼠标拖动会**同时**派发 `onMouse`（Move/Release，真正做拖选）与合成的 `onTouch(Up)`；而触摸 Up 分支的 `wasDragging` 只由**触摸** Move 置位，恒为 false，于是又走了一遍"点按落光标"→ `selMgr.collapse(pressOffset)`，把刚拖出来的选区收回按下点。
- 修法：
  - `handleTouch` 在识别出"鼠标操作的合成副本"时整体让位（`isSyntheticTouch()`：鼠标按下进行中，或按下/抬起在 300ms 内），按下/拖动/抬起/长按/选词全部由 `onMouse` 负责；
  - 触摸 Up 的点按分支再加一道 `shouldHandleTapUp(wasDragging, pointerUp)` 守卫（纯触摸才落光标，且保留弹簧动画）；
  - `onMouse Press` 复用 `placeCaretImmediately()`（指针点击立即落位、不跑弹簧），并清掉可能在触摸 Down 阶段残留的长按定时器与词选区锚点。
- 回归：`flowtext-regression` 138 项（新增 3：合成副本识别跨长按拖动、Up 点按守卫、指针点击立即落位原有断言保留）。
- 未验证：真机上"触摸屏 + 鼠标"混用（鼠标悬停后立刻用手点）是否会在 300ms 窗口内被误判为合成副本。
