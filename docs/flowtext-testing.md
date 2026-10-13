# FlowText 与桌面窗口回归测试

使用 DevEco Studio 6.1、HarmonyOS SDK 6.1.0 / API 23。编辑器用例使用 `ohosTest` 隔离画布；窗口用例启动真实应用、查看引导页，不输入或删除文稿。运行前先保存真实应用草稿，测试时保持模拟器解锁且不操作窗口。

2026-10-06 验证结果：主包、测试包均编译通过；MateBook Pro 2in1 模拟器（HarmonyOS 6.1 / API 23）18 项测试全部通过；本地 33 项回归检查及其中的 766 组 Unicode 官方样例通过。最终源码关闭了诊断日志。

2026-10-13 修复版验证结果：主包与 `ohosTest` 测试包在 SDK 6.1.0 / API 23 编译通过；69 项本地回归检查（含 766 组 Unicode 官方样例）通过；MateBook Pro 2in1 / API 23 模拟器 22 项原生测试全部通过，Failure、Error、Ignore 均为 0。

2026-10-13 桌面标题栏修复验证结果：主包与测试包编译通过；本地回归增至 86 项；MateBook Pro / API 23 分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。原生键盘用例在聚焦、每次输入后等待 UI 空闲，并逐步检查选区，避免把异步输入尚未落定的状态当作结果。

## 本地逻辑测试

需要 Node.js 24 或以上，在工程根目录执行：

```powershell
node tools/flowtext-regression.cjs
node tools/data-regression.cjs
node tools/shell-regression.cjs
node tools/window-regression.cjs
```

执行实际 ArkTS 模型和选定组件方法，图形与输入法接口使用受控替身。覆盖误删、选区方向、加载恢复、格式事务、跨文稿历史、组合态、缓存、动画和连接竞态；另执行 Unicode 17 官方 766 组字素边界样例。此测试不能替代系统字体和输入法验证。

2026-10-13 的新增回归：FlowText 37 项、数据层 19 项、外壳与文件导出 13 项。数据层运行实际 DAO、仓储和状态类，覆盖恢复事务与自动保存隔离、保存失败/超限保留草稿、保存队列、导出内存快照、格式恢复、异步选稿与新建项目重试；外壳测试运行实际事件方法，并用真实本地文件验证覆盖截断与资源关闭。数据库、系统选择器和界面生命周期在这些本地测试中仍使用受控替身。

桌面窗口 17 项运行实际配置函数、窗口按钮方法和 EntryAbility 生命周期，覆盖内容加载后配置、前台重配、销毁与旧窗口回调、手机和平板排除、原生标题/三键/顶部热区独立失败处理、仅左键拖动，以及最大化和还原成功之后才重新应用隐藏设置。

## DevEco 编译和设备测试

在 DevEco 完成依赖同步，启动已有模拟器或连接设备，查看 `hdc list targets`，然后执行：

运行 UI 用例前先进入模拟器桌面，确保屏幕已解锁；锁屏会阻止测试画布显示与获得焦点。

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/DevEco Studio' -Device '127.0.0.1:5555'
```

`DevEcoRoot` 和 `Device` 换成自己的路径和目标。仅编译可加 `-BuildOnly`。脚本分别构建主包和 `ohosTest`，安装后分组执行编辑器与窗口 Hypium 用例，每组从关闭应用的状态启动，单用例超时为 20 秒。根据完整汇总判断 Failure、Error、Ignore 均为 0 且 Pass 等于 Tests run，避免误把系统命令退出码 0 当成全部通过。两组日志分别保存到 `tools/.test-results/device-tests.log`、`window-tests.log`。

设备测试使用真实 ArkGraphics2D 排版、CanvasTextEditor 和系统键盘事件，覆盖混排索引、表情、复杂文字、标题度量、密度换算、空段落、换行、宽度变化、格式同步和键盘选择。实际手机需配置自己的调试签名。

新增四项原生排版用例：原生行内索引契约、窗口外格式不得重复正文、非零窗口起点与 emoji 偏移换算、多段落跨越 4000 码元窗口。跨窗口用例同时检查软折行与后续窗口的点击/光标往返。实际执行结果应检查 Hypium 的汇总，而不是只依据测试包编译成功。

三个原生桌面用例验证真实 EntryAbility：内容加载后隐藏系统标题与三键；自绘按钮最大化、顶部鼠标悬停/点击、再还原，均不出现系统标题；窄窗口仍保留自绘按钮并可用鼠标拖动，引导页保留窗口控制。窗口用例只在 2in1 设备执行。

系统常驻标题、右上角三键和全屏顶部热区需要分别配置，依据见[华为沉浸式窗口适配说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1089)。隐藏配置须在内容加载后调用，最大化与还原完成后重新应用；自绘 36vp 高度不传给原生装饰高度接口。

键盘测试还验证框架焦点。Canvas 本身不能获焦，编辑器使用可获焦子节点和 `tabStop` 容器；依据见[华为焦点控制文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/ts-universal-attributes-focus-V14)。

Unicode 数据可用 `python tools/generate-grapheme-data.py` 从已保存数据重新生成；只有更新数据时才需要 `--download`。数据版权与许可见 `tools/unicode/LICENSE.txt`。

尚需单独验收：不同厂商中文输入法的候选交互、手机触摸手柄、五万字持续输入帧率与内存、读屏编辑能力。通过这些回归用例不代表所有设备体验已经验收。
