# FlowText 回归测试

使用 DevEco Studio 6.1、HarmonyOS SDK 6.1.0 / API 23。测试页面位于 `ohosTest`，不写入用户文稿。

2026-10-06 验证结果：主包、测试包均编译通过；MateBook Pro 2in1 模拟器（HarmonyOS 6.1 / API 23）18 项测试全部通过；本地 33 项回归检查及其中的 766 组 Unicode 官方样例通过。最终源码关闭了诊断日志。

2026-10-13 修复版验证结果：主包与 `ohosTest` 测试包在 SDK 6.1.0 / API 23 编译通过；69 项本地回归检查（含 766 组 Unicode 官方样例）通过；MateBook Pro 2in1 / API 23 模拟器 22 项原生测试全部通过，Failure、Error、Ignore 均为 0。

## 本地逻辑测试

需要 Node.js 24 或以上，在工程根目录执行：

```powershell
node tools/flowtext-regression.cjs
node tools/data-regression.cjs
node tools/shell-regression.cjs
```

执行实际 ArkTS 模型和选定组件方法，图形与输入法接口使用受控替身。覆盖误删、选区方向、加载恢复、格式事务、跨文稿历史、组合态、缓存、动画和连接竞态；另执行 Unicode 17 官方 766 组字素边界样例。此测试不能替代系统字体和输入法验证。

2026-10-13 的新增回归：FlowText 37 项、数据层 19 项、外壳与文件导出 13 项。数据层运行实际 DAO、仓储和状态类，覆盖恢复事务与自动保存隔离、保存失败/超限保留草稿、保存队列、导出内存快照、格式恢复、异步选稿与新建项目重试；外壳测试运行实际事件方法，并用真实本地文件验证覆盖截断与资源关闭。数据库、系统选择器和界面生命周期在这些本地测试中仍使用受控替身。

## DevEco 编译和设备测试

在 DevEco 完成依赖同步，启动已有模拟器或连接设备，查看 `hdc list targets`，然后执行：

运行 UI 用例前先进入模拟器桌面，确保屏幕已解锁；锁屏会阻止测试画布显示与获得焦点。

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/DevEco Studio' -Device '127.0.0.1:5555'
```

`DevEcoRoot` 和 `Device` 换成自己的路径和目标。仅编译可加 `-BuildOnly`。脚本分别构建主包和 `ohosTest`，安装并执行 Hypium；根据测试汇总的 Failure / Error 判断结果，避免误把系统命令退出码 0 当成全部通过。日志保存到 `tools/.test-results/`。

设备测试使用真实 ArkGraphics2D 排版、CanvasTextEditor 和系统键盘事件，覆盖混排索引、表情、复杂文字、标题度量、密度换算、空段落、换行、宽度变化、格式同步和键盘选择。实际手机需配置自己的调试签名。

新增四项原生排版用例：原生行内索引契约、窗口外格式不得重复正文、非零窗口起点与 emoji 偏移换算、多段落跨越 4000 码元窗口。跨窗口用例同时检查软折行与后续窗口的点击/光标往返。实际执行结果应检查 Hypium 的汇总，而不是只依据测试包编译成功。

键盘测试还验证框架焦点。Canvas 本身不能获焦，编辑器使用可获焦子节点和 `tabStop` 容器；依据见[华为焦点控制文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/ts-universal-attributes-focus-V14)。

Unicode 数据可用 `python tools/generate-grapheme-data.py` 从已保存数据重新生成；只有更新数据时才需要 `--download`。数据版权与许可见 `tools/unicode/LICENSE.txt`。

尚需单独验收：不同厂商中文输入法的候选交互、手机触摸手柄、五万字持续输入帧率与内存、读屏编辑能力。通过这些回归用例不代表所有设备体验已经验收。
