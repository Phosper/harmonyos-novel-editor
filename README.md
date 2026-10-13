# Weaver

HarmonyOS / ArkTS 小说写作应用。当前源码基线为 2026-10-13 收到的 `Weaver(1).zip`；此前的 `Weaver.zip` 与 Git 历史保留供对照。

## 工程结构

- `entry/src/main/ets/editor/flowtext/`：FlowText 自绘正文编辑器
- `entry/src/main/ets/shell/`：手机、平板及宽屏界面
- `entry/src/main/ets/store/`：项目、编辑器、素材、关系和界面状态
- `entry/src/main/ets/repository/`、`database/`：仓储和数据库访问
- `docs/`、`spec/`：新版设计、研究和实现记录

## 打开与构建

使用支持 HarmonyOS SDK 6.1.0（API 23）的 DevEco Studio 打开本目录，重新同步项目依赖。工程仅包含一个 `entry` 模块。

工程继续采用本机已验证的 SDK 6.1.0（API 23）与构建工具配置。来包中的 `26.0.0` 工具链配置、构建缓存、已安装依赖、`local.properties` 和个人签名配置未迁入。安装到设备前，请在本机配置签名。

来包新增了窗口排版、绘制缓存、列表读取裁剪与保存修订号保护；其原始审查报告保存在 [2026-10-13 来包报告](docs/reviews/upstream-review-2026-10-13.html)。该报告保留部分修改前结论，验证结果需以当前源码的测试为准。

FlowText 此前已补充字素边界、选区、排版索引、输入法生命周期和格式事务等修复；回归测试与 DevEco 设备测试的运行方法见 [FlowText 测试说明](docs/flowtext-testing.md)。
