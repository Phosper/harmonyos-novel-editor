# Weaver

HarmonyOS / ArkTS 小说写作应用。当前源码基线为 2026-10-13 收到的 `Weaver(1).zip`；此前的 `Weaver.zip` 与 Git 历史保留供对照。

## 工程结构

- `entry/src/main/ets/editor/flowtext/`：FlowText 自绘正文编辑器
- `entry/src/main/ets/shell/`：手机、平板及宽屏界面
- `entry/src/main/ets/store/`：项目、编辑器、素材、关系和界面状态
- `entry/src/main/ets/repository/`、`database/`：仓储和数据库访问
- `docs/`、`spec/`：新版设计、研究和实现记录

## 打开与构建

使用 DevEco Studio 26.0.0 或匹配的命令行工具链及 HarmonyOS SDK 26.0.0 打开本目录，重新同步项目依赖。工程仅包含一个 `entry` 模块。

当前目标版本 `targetSdkVersion` 和最低兼容版本 `compatibleSdkVersion` 均为 `26.0.0`（API 26）。`oh-package.json5` 与 `hvigor/hvigor-config.json5` 的 `modelVersion` 均为 `26.0.0`。配套版本以 [DevEco Studio 26.0.0 官方发布说明](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-2600) 为准；本次实际使用官方 Command Line Tools 26.0.0.851、SDK 26.0.0.105、Hvigor 6.26.8、Node.js 24.14.1。

2026-10-14 已使用上述 API 26 工具链构建主包和测试包；两包中的 `compileSdkVersion` 均为 `26.0.0.105`，目标和最低 API 元数据均为 API 26。88 项本地回归通过；独立 MateBook Pro / HarmonyOS 7.0.0.107 / API 26 模拟器分组运行编辑器 22 项、桌面窗口 3 项，全部通过，Failure、Error、Ignore 均为 0。升级验证中同时修复了输入法空提交删除选中文字的问题。个人签名、`local.properties`、构建缓存与已安装依赖不从来包迁入；安装到真实设备前，请在本机配置签名。

2026-10-17 错误检查后，修复项目切换与备份混数据、恢复成功后刷新失败误报、默认项目侧栏缺失、异步粘贴与迟到编辑事件跨文稿写入、粘贴选区替换、撤销后的历史合并、段首标题，以及文件短读/短写与 TXT 字面符号丢失。122 项本地检查和 28 项 API 26 原生测试全部通过，主包与测试包重新编译成功；详细范围与运行方法见测试说明。

命令行工具包不包含 JDK，可通过 `-JavaRoot` 指定本机 JDK 21。路径按自己的安装目录替换：

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -BuildOnly
```

脚本在构建前检查实际 SDK，在安装前检查设备 API。API 23 开发工具或模拟器不能用于当前最低 API 26 的工程。

来包新增了窗口排版、绘制缓存、列表读取裁剪与保存修订号保护；其原始审查报告保存在 [2026-10-13 来包报告](docs/reviews/upstream-review-2026-10-13.html)。该报告保留部分修改前结论，验证结果需以当前源码的测试为准。

FlowText 此前已补充字素边界、选区、排版索引、输入法生命周期和格式事务等修复；回归测试与 DevEco 设备测试的运行方法见 [FlowText 测试说明](docs/flowtext-testing.md)。
