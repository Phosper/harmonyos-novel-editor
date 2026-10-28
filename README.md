# Weaver

后续对话与开发请先阅读 [代码与思路板设计依据](docs/PROJECT_CONTEXT.md) 和根目录 [项目规则](AGENTS.md)。当前以 `Weaver(4).zip` 完整新版主源码为底稿，迁回已验证的可靠性修复；来源、快照、验证与剩余边界见 [完整新版对齐记录](docs/weaver4-realignment-2026-10-28.md)。思路板现行规格为 2026-10-22 r2，原件已在项目内存档。

第一轮可靠性改进已修复导入归属与失败处理、慢新建打开错稿、TXT 的 HTML 导出及字素选词；该轮 317 项回归和 766 个 Unicode 样例通过，范围见 [改进记录](docs/improvements-2026-10-27.md)。

2026-10-28 完整新版对齐完成：保留融合工具头、原生三键、列表/待办、头像设置及专注转场，同时迁回数据、保存、输入、撤销和长文排版保护。432 项本地检查、766 个 Unicode 样例、API 26 两包构建及 39 项隔离模拟器原生用例通过，实际画面已核对。首次测试启动冻结和长文性能边界如实保留在上述完整对齐记录中。

以下为历史进展。2026-10-28 界面第一批整合完成：原生菜单、正文标题和实时列表预览已接入，并修复撤销按钮未刷新的问题。342 项本地回归、766 个 Unicode 样例及 37 项 API 26 模拟器原生用例通过，主包和测试包编译成功。长文测试曾触发主线程超时，性能尚未验收；其他设备与真实鼠标也待补测。详见 [本轮验证记录](docs/integration-2026-10-28.md)。

HarmonyOS / ArkTS 写作应用。Git 历史以 [JoukoPuro/Weaver](https://github.com/JoukoPuro/Weaver) 的 `master` 提交 `66a5483` 为基线，曾迁入本地整合与编辑器优化（`029a834`、`8ce11d1`）。JoukoPuro 原始历史、界面特色和文档保留；此前 Phosper 版本保留在独立分支供对照。迁移范围见 [JoukoPuro 整合说明](docs/joukopuro-integration-2026-10-21.md)。

2026-10-21 整合验证：297 项本地检查、766 个 Unicode 样例及 37 项 API 26 模拟器原生测试全部通过，主包与测试包构建成功。主要远端已改为 JoukoPuro，旧仓库保留为 `phosper`；本次整合保存在本地分支，未推送远端。

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

2026-10-20 将 `Weaver(2).zip` 与已同步的 `origin/master`（`1fb4f76`）择优整合。采用统一编辑命令、键鼠与触摸分流、多设备窗口适配、光感材质及性能降级、顶栏编辑工具、专注与打字机模式，以及滚动位置、软换行光标和选区同步改进。保留仓库已有的文稿归属、异步保存、备份、文件短读短写及空 IME 提交保护。

整合时补上来包的关闭保存确认、窗口监听清理、重命名文稿归属、输入法预览和回声隔离、键盘布局与焦点保护，并使打字机模式的点击坐标与缩放一致。实屏检查发现部分原生字形 run 返回局部坐标，现按原生行位置补原点，已有行坐标与字形偏移继续保留，避免混排文字重叠。个人签名、来包 Git 历史、依赖和构建缓存均不迁入；来包文档中的历史验证声明不作为本次验证结果。当前验证范围见 [测试说明](docs/flowtext-testing.md)。

来包整合验证：246 项本地检查（另含 766 个 Unicode 样例）通过；API 26 主包与测试包编译成功；在空白 MateBook Pro / HarmonyOS 7.0.0.107 / API 26 模拟器分组执行 32 项原生测试，全部通过，Failure、Error、Ignore 均为 0。

同日继续优化正文编辑器：中文预上屏复用未改动段落，并与正式文稿隔离排版状态；全选立即更新完整范围，远距离光标跳转按行数与时间预算分段排版。输入法选区同步只保留一个在途请求和最新待报状态，失败有限重试；撤销与重做共用 120 条、约 16 MiB 字符串载荷预算，单个超大恢复点允许独占超限以保留一次撤销。换稿、编辑、失焦及手动滚动会取消旧跳转；软换行边界与删空预上屏均有回归保护。紧接远跳的视觉行导航会先补齐当前行；单次原生行或段落窗口调用仍不可中断，尚不代表五万字输入帧率已验收。

编辑器优化验证：289 项本地检查及 766 个 Unicode 样例通过，API 26 主包与测试包编译成功；同一独立模拟器分组运行编辑器与文件 32 项、跨窗口长文排版 1 项、桌面窗口 3 项，共 36 项全部通过，Failure、Error、Ignore 均为 0。

命令行工具包不包含 JDK，可通过 `-JavaRoot` 指定本机 JDK 21。路径按自己的安装目录替换：

```powershell
./tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -BuildOnly
```

脚本统一运行本地回归并构建主包与测试包，在构建前检查实际 SDK，在安装前检查设备 API。API 23 开发工具或模拟器不能用于当前最低 API 26 的工程。

上述脚本需要 DevEco Studio / 命令行工具链与设备。当前 Windows 环境已配置 API 26 工具链和隔离模拟器；其他不带 SDK 的环境可以执行 Node 回归与静态守卫：

```bash
for f in tools/*.cjs; do node "$f" || echo "FAILED $f"; done
```

当前期望 9 个脚本全部通过、合计 432 项（另含 766 个 Unicode 样例）；最新版整合的实际运行结果见上述对齐记录。设备侧四形态（键鼠输入、沉浸标题栏、沉浸光感、手机/平板触摸不回退）按 [多端自测清单](docs/refactor/multidevice-self-test.md) 执行；构建命令与 Hypium 通过条件（`Failure:0 Error:0 Ignore:0` 且 `Pass == Tests run`）见该文档 §1。

来包新增了窗口排版、绘制缓存、列表读取裁剪与保存修订号保护；其原始审查报告保存在 [2026-10-13 来包报告](docs/reviews/upstream-review-2026-10-13.html)。该报告保留部分修改前结论，验证结果需以当前源码的测试为准。

FlowText 此前已补充字素边界、选区、排版索引、输入法生命周期和格式事务等修复；回归测试与 DevEco 设备测试的运行方法见 [FlowText 测试说明](docs/flowtext-testing.md)。
