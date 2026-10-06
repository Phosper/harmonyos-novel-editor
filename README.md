# Weaver

HarmonyOS / ArkTS 小说写作应用。当前开发基线为 `Weaver.zip` 中的新版，旧版已归档，不再作为功能验收标准。

## 工程结构

- `entry/src/main/ets/editor/flowtext/`：FlowText 自绘正文编辑器
- `entry/src/main/ets/shell/`：手机、平板及宽屏界面
- `entry/src/main/ets/store/`：项目、编辑器、素材、关系和界面状态
- `entry/src/main/ets/repository/`、`database/`：仓储和数据库访问
- `docs/`、`spec/`：新版设计、研究和实现记录

## 打开与构建

使用支持 HarmonyOS SDK 6.1.0（API 23）的 DevEco Studio 打开本目录，重新同步项目依赖。工程仅包含一个 `entry` 模块。

队友机器的构建缓存、已安装依赖、`local.properties` 和个人签名配置未迁入。安装到设备前，请在本机配置签名。

本次切换保留了 Git 历史和原始压缩包。FlowText 已补充字素边界、选区、排版索引、输入法生命周期和格式事务等修复；回归测试与 DevEco 设备测试的运行方法见 [FlowText 测试说明](docs/flowtext-testing.md)。
