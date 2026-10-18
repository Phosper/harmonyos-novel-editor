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
