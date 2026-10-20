# FlowText 与桌面窗口回归测试

当前工程使用 HarmonyOS API 26，需 DevEco Studio 26.0.0 或配套 Command Line Tools。编辑器用例使用 `ohosTest` 隔离画布；窗口用例启动真实应用、查看引导页，不输入或删除文稿。运行前先保存真实应用草稿，测试时保持模拟器解锁且不操作窗口。下列 API 23 结果为升级前历史记录。

2026-10-06 验证结果：主包、测试包均编译通过；MateBook Pro 2in1 模拟器（HarmonyOS 6.1 / API 23）18 项测试全部通过；本地 33 项回归检查及其中的 766 组 Unicode 官方样例通过。最终源码关闭了诊断日志。

2026-10-13 修复版验证结果：主包与 `ohosTest` 测试包在 SDK 6.1.0 / API 23 编译通过；69 项本地回归检查（含 766 组 Unicode 官方样例）通过；MateBook Pro 2in1 / API 23 模拟器 22 项原生测试全部通过，Failure、Error、Ignore 均为 0。

2026-10-13 桌面标题栏修复验证结果：主包与测试包编译通过；本地回归增至 86 项；MateBook Pro / API 23 分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。原生键盘用例在聚焦、每次输入后等待 UI 空闲，并逐步检查选区，避免把异步输入尚未落定的状态当作结果。

2026-10-13 API 26 构建验证：使用官方 Command Line Tools 26.0.0.851、SDK 26.0.0.105、Hvigor 6.26.8、Node.js 24.14.1、JDK 21，主包与测试包编译通过，86 项本地回归通过。两包的 `compileSdkVersion` 均为 `26.0.0.105`，打包后的最低/目标 API 值均为 `260000026`（API 26 编码）；当前 `compatibleSdkVersion` 为 `26.0.0`，旧 API 23 模拟器不能用于此轮安装测试。

2026-10-14 API 26 最终验证：修复输入法空提交后重新构建主包与测试包，88 项本地检查通过。新建独立 `WeaverAPI26` / MateBook Pro 模拟器，镜像为 HarmonyOS 7.0.0.107；实际设备参数 `const.ohos.apiversion=26`、`const.product.devicetype=2in1`。在 `127.0.0.1:12326` 分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。生产诊断日志已关闭。

2026-10-17 错误检查验证：使用同一 API 26 工具链重新构建主包与测试包，均成功。本地 FlowText 52 项、数据 28 项、外壳与导出 20 项、窗口 17 项、导入 5 项，共 122 项全部通过，另含 766 个 Unicode 样例。在独立 `WeaverAPI26` / API 26 / 2in1 模拟器运行编辑器与文件 I/O 25 项、窗口 3 项，共 28 项，Failure、Error、Ignore 均为 0；该次测试实例使用 2 GiB 内存。

2026-10-20 来包整合本地验证：FlowText 110 项、数据 28 项、外壳与导出 20 项、窗口 38 项、导入 5 项、设备分流 28 项、ArkTS 静态守卫 17 项，共 246 项全部通过，另含 766 个 Unicode 样例。静态守卫有两组既有编辑器诊断日志警告。新增检查覆盖快速输入回声队列、换稿隔离、同长度预览、AltGr/Meta/数字与标点键盘兜底、软换行两侧点击、打字机缩放命中、局部与行相对两类字形坐标的实际绘制位置、完整选区格式、重命名归属、窗口重建与当前显示器密度；本地替身仍不能替代真实系统字体、输入法与触摸验证。

同日使用官方 Command Line Tools 26.0.0.851、SDK 26.0.0.105、Hvigor 6.26.8、Node.js 24.14.1、JDK 21 编译最终主包与测试包，均成功。在空白 `WeaverMerge20261020` / MateBook Pro / HarmonyOS 7.0.0.107 / API 26 / 2 GiB 实例（`127.0.0.1:12327`）分组运行编辑器与文件 I/O 29 项、桌面窗口 3 项，共 32 项全部通过，Failure、Error、Ignore 均为 0。原生多 run 用例确认该运行时各 run 的原始最小 x 均为 0，补原点后绘制位置与原生行位置一致。手机、平板、第三方输入法、长文输入性能与读屏体验仍需单独验收。

测试启动改为等待隔离页面与画布实际就绪；电脑测试页使用电脑输入模式，背景测试窗口隐藏自身原生三键，避免全屏主窗口的控件检查误纳背景按钮。窗口用例使用稳定控件 ID、实际标题区域和状态等待，仍严格检查隐藏原生标题、最大化/还原、顶部悬停、窄窗拖动与引导页控制。耗时同步排版探针放在交互用例之后，逐字形范围检查保留，避免先阻塞页面与输入处理。

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
node tools/device-profile-regression.cjs
node tools/arkts-guard.cjs
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

`DevEcoRoot` 可为 DevEco Studio 或 Command Line Tools 根目录，`Device` 换成实际设备；CLI 未带 JDK 时用 `JavaRoot` 指定本机 JDK 21。仅编译可加 `-BuildOnly`。脚本检查实际 SDK 不低于目标 API、设备 API 不低于最低兼容版本，条件不符时拒绝构建或安装。脚本分别构建主包和 `ohosTest`，安装后分组执行编辑器与窗口 Hypium 用例，每组从关闭应用的状态启动，异步单用例向框架传入 20 秒超时，每组命令最多等待 180 秒，以容纳长文同步原生排版探针。根据完整汇总判断 Failure、Error、Ignore 均为 0 且 Pass 等于 Tests run，避免误把系统命令退出码 0 当成全部通过。两组日志分别保存到 `tools/.test-results/device-tests.log`、`window-tests.log`。

设备测试使用真实 ArkGraphics2D 排版、CanvasTextEditor 和系统键盘事件，覆盖混排索引、表情、复杂文字、标题度量、密度换算、空段落、换行、宽度变化、格式同步和键盘选择。实际手机需配置自己的调试签名。

新增四项原生排版用例：原生行内索引契约、窗口外格式不得重复正文、非零窗口起点与 emoji 偏移换算、多段落跨越 4000 码元窗口。跨窗口用例同时检查软折行与后续窗口的点击/光标往返。实际执行结果应检查 Hypium 的汇总，而不是只依据测试包编译成功。

三个原生桌面用例验证真实 EntryAbility：内容加载后隐藏系统标题与三键；自绘按钮最大化、顶部鼠标悬停/点击、再还原，均不出现系统标题；窄窗口仍保留自绘按钮并可用鼠标拖动，引导页保留窗口控制。窗口用例只在 2in1 设备执行。

系统常驻标题、右上角三键和全屏顶部热区需要分别配置，依据见[华为沉浸式窗口适配说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1089)。隐藏配置须在内容加载后调用，最大化与还原完成后重新应用；当前自绘标题栏为 48vp，原生装饰尺寸通过独立配置函数设置。原生三键保持隐藏，自绘关闭按钮先严格保存，保存失败时保留窗口与草稿。

键盘测试还验证框架焦点。Canvas 本身不能获焦，编辑器使用可获焦子节点和 `tabStop` 容器；依据见[华为焦点控制文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/ts-universal-attributes-focus-V14)。

连续按键测试在隔离页面观察每一组目标键和修饰键的实际 Up，最多等待 5 秒，然后等待 UI 空闲并检查原来的严格选区结果。每组只注入一次，未确认释放时不开始下一组；UI 空闲本身不能保证注入序列处理完。相关实现见 [UITest 组合键序列](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/core/ui_action.h) 和 [系统事件注入](https://github.com/openharmony/testfwk_arkxtest/blob/master/uitest/server/system_ui_controller.cpp)。

Unicode 数据可用 `python tools/generate-grapheme-data.py` 从已保存数据重新生成；只有更新数据时才需要 `--download`。数据版权与许可见 `tools/unicode/LICENSE.txt`。

尚需单独验收：不同厂商中文输入法的候选交互、手机触摸手柄、五万字持续输入帧率与内存、读屏编辑能力。通过这些回归用例不代表所有设备体验已经验收。
