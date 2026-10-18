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

2026-10-18 修复自绘编辑器的文字漂移与多选异常：多 run 行按行 API 归一 run 原点（不再叠在行首）、改字号/主题/窗口宽度不再把滚动夹回顶部、滚动上限改用已排版精确高度、预上屏只画一次、拖选/手柄光标跟随 head、长按选词后拖动从词边界扩展、选区高亮与光标统一行盒并补空行、Ctrl+A 同步、触摸 Cancel 复位、IME 上报去抖。本地回归增至 **130 项**（FlowText 60 + 数据 28 + 外壳 20 + 窗口 17 + 导入 5），全部通过；设备侧构建与原生用例待按测试说明执行。详见 [修复报告](docs/editor-drift-selection-fix.md)。

2026-10-18 完成多端交互重构与沉浸视觉升级：编辑器输入统一为 `EditCommand → EditorCommandRouter` 命令层（新增 `entry/src/main/ets/editor/interaction/`），新增 `utils/DeviceProfile.ets` 以窗口宽度断点、设备形态、输入形态三条正交判据统一分流，新增 `shell/DesktopTitleBar.ets` 沉浸标题栏（48vp、自由窗口模式判定、系统原生三键 + 拖拽 + 后台落库）与 `shell/MaterialSurface.ets`、`constants/LightTokens.ets` 沉浸光感（四主题、FULL/REDUCED/OFF 三级降级、每屏 ≤2 层实时模糊）；`PcWindowBar` 保留为兼容薄壳。本地回归增至 **224 项**（FlowText 97 + 窗口 32 + 设备分流 25 + ArkTS 静态守卫 17 + 数据 28 + 外壳 20 + 导入 5），`node tools/*.cjs` 全部通过。本机无 SDK/模拟器，**尚未编译、未跑设备用例**；手机 / 平板 / PC(2in1) / MatePad Edge 电脑模式的逐条自测步骤、预期结果、失败判定与 Hypium 判定条件见 [多端自测清单](docs/refactor/multidevice-self-test.md)，改动文件与关键行号见 [改动清单](docs/refactor/change-list.md)。

2026-10-18 第三轮交互 / UI：鼠标点击光标不再播放弹簧动画（手指点按保留），光标改为余弦 alpha 呼吸（0.5–1、2.4s，替代 600ms 硬闪烁）；编辑器内部工具条上移到窗口顶栏（撤销/重做、B/I/H、查找、打字机、专注写作 + 低频「⋯」），顶栏副标题统一显示章节·字数·保存状态；新增窗口内沉浸编辑（顶栏按钮 / F11 / 移动端「更多」进入，桌面顶栏与移动端浮动按钮退出），正文按 880vp 宽度居中铺开。打字机模式新增段落视觉层级：当前段 1.08×、相邻行 0.98×、逐行 -0.02 至 0.90×，切换段落用 180ms 缓动同步过渡缩放与淡化（仅绘制层，不触发重排）。

命令行工具包不包含 JDK，可通过 `-JavaRoot` 指定本机 JDK 21。路径按自己的安装目录替换：

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -BuildOnly
```

脚本在构建前检查实际 SDK，在安装前检查设备 API。API 23 开发工具或模拟器不能用于当前最低 API 26 的工程。

上述脚本需要 DevEco Studio / 命令行工具链与设备。本机（OpenEuler，无 SDK）只能执行不依赖工具的 Node 回归与静态守卫：

```bash
for f in tools/*.cjs; do node "$f" || echo "FAILED $f"; done
```

期望 7 个脚本全部通过、合计 224 项。设备侧四形态（键鼠输入、沉浸标题栏、沉浸光感、手机/平板触摸不回退）按 [多端自测清单](docs/refactor/multidevice-self-test.md) 执行；构建命令与 Hypium 通过条件（`Failure:0 Error:0 Ignore:0` 且 `Pass == Tests run`）见该文档 §1。

来包新增了窗口排版、绘制缓存、列表读取裁剪与保存修订号保护；其原始审查报告保存在 [2026-10-13 来包报告](docs/reviews/upstream-review-2026-10-13.html)。该报告保留部分修改前结论，验证结果需以当前源码的测试为准。

FlowText 此前已补充字素边界、选区、排版索引、输入法生命周期和格式事务等修复；回归测试与 DevEco 设备测试的运行方法见 [FlowText 测试说明](docs/flowtext-testing.md)。
