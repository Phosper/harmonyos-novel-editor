# Weaver(4) 完整新版对齐与可靠性迁回

日期：2026-10-28。用户指出此前模拟器界面仍像旧版后，重新以完整来包建立基准。本记录取代“局部菜单、标题和预览已整合”作为当前版本状态；旧记录保留历史验证范围。

## 来源与顺序

先独立构建并运行 `Weaver(4).zip`，核对工作台、半模态设置、编辑器和专注往返，再用其完整 main/AppScope 源码作为工作区底稿，逐方法迁回已验证的可靠性保护。

- 原 ZIP SHA-256：`2D9CCEA9E42140429A6B48695F2550AE5EE55663C46C7B6C03EB8FADDC885938`。
- 独立原包：`tools/.test-results/weaver4-pristine/`，214 个正式文件及逐文件哈希清单。仅调整独立构建的个人签名设置，记录在 `BASELINE_ENVIRONMENT.json`；未改原包业务源码。
- 原工作区完整主源码与测试快照：`tools/.test-results/workspace-before-weaver4/`；原跟踪改动另存补丁。未清除原工程或模拟器数据。
- 实际工作区以新版 138 个 main/AppScope 文件为底稿；保留现有模块、API 26、包名、权限、依赖版本和本机工程配置，不迁入 ZIP 的 Git、凭据、依赖或构建缓存。

## 当前保留的新版能力

融合到各 Pane 的工具头、原生窗口三键及避让、行内标题、三级标题/列表/待办及缩进、独立专注工作区与转场、半模态设置、本机昵称头像、键盘和折叠/短屏/圆角适配。

新版 `format_runs` 是六字段；旧五字段仍可读，缩进默认为 0。光标 affinity 沿用新版定义：`DOWNSTREAM` 指前视觉行末，`UPSTREAM` 指后视觉行首。可靠性方法和旧测试均按该语义迁移。

## 迁回的保护

- 导入归属、事务写入、ID 映射、失败汇总、异步新建/开稿/恢复保护及文件短读短写处理。
- 120 条、约 16 MiB 共用撤销历史预算，草稿预览、保存修订与重开身份保护。
- 输入法回声隔离、预上屏独立缓存、字素边界、拖选、软换行光标及分段长文排版，兼容列表段落提供器。
- 动态密度、窗口替换后的监听释放、编辑焦点归属、行内与列表重命名的项目/文稿/代次保护。
- 原生关闭等待严格保存；保存失败阻止关闭，提供重试、导出和明确放弃。失败回调必须返回阻止关闭，不能 reject。
- TXT 的 HTML 导出保留字面符号、空白、内联/标题格式、列表缩进与待办状态；Markdown 导出保留原包实现。

## 实际验证

证据目录：`tools/.test-results/weaver4-baseline-validation/`。

- 独立原包 7 组、295 项回归实际通过，API 26 主包构建、安装和运行成功。
- 原包截图与布局树：`desktop/00-pristine-launch` 至 `07-pristine-focus-return`。
- 整合版 9 组、432 项本地检查全部通过：FlowText 167、数据 59、外壳/导出 71、窗口 54、导入 5、设备状态 32、分段排版 11、IME 14、ArkTS 守卫 19；另含 766 个 Unicode 官方样例。结果与日志在 `merged-local-results.json` 及 `merged-*.cjs.log`。
- API 26 主包和设备测试包均构建、安装成功，日志为 `merged-default-build.log`、`merged-ohosTest-build.log` 和两份 install log。主包 SHA-256 为 `CF63EF68CE185DCAEC9FBDFD65A3B44A387A50C10E2B01BCA8667D8F08E8D788`。
- 实际原生回归 39 项通过，Failure / Error / Ignore 均为 0：编辑与文件 33（`merged-device-editor-retry.log`）、跨段落窗口长文 1（`merged-device-native-layout.log`）、新版窗口 5（`merged-device-window.log`）。窗口包括原生三键与最大化/恢复、Pane 拖动与窄窗引导、专注胶囊/Esc 两次往返，以及待办格式严格保存后关签重开。
- 初次设备测试在 TestAbility 页面挂载前超时并记录 `THREAD_BLOCK_6S`，未执行 Hypium；日志 `merged-device-editor.log` 与 `merged-fixture-appfreeze.log` 保留。后续发现设备熄屏锁定，唤醒后 39 项全部通过；没有有效目标线程栈，不能据此断言冻结由熄屏或编辑器某模块造成，时间/证据边界在 `merged-fixture-freeze-analysis.json`。脚本已在每组 UI 测试前唤醒设备。
- 31 个关键 UI、编辑模型与第三方转场文件和独立原包一致（忽略换行/BOM），哈希审核见 `final-ui-source-audit.json`。`git diff --check` 通过。
- 整合版工作台、半模态设置、编辑器、专注及退出已实际核对画面，截图/布局树为 `desktop/17-merged-final-workspace`、`18-merged-final-settings`、`19-merged-final-editor`、`20-merged-final-focus`、`21-merged-final-editor-maximized`。此前截图通道曾持续黑屏，保留数据冷启动后恢复；`08` 是旧帧，`09`–`15` 黑屏图片不充当视觉验收证据。

## 验证边界

独立模拟器 `Weaver4Baseline26`，HarmonyOS 7.0.0.107 / API 26 / 2in1。原生用例在 `127.0.0.1:5557` 执行；保留数据冷启动后自动分配为 `127.0.0.1:5555`，同时核实只有该实例运行，不能按端口把它认成旧 `WeaverAPI26`。该设备只含合成测试数据；旧模拟器数据保留。设备套件只删除自身创建的临时文稿，熄屏超时临时设置已恢复。

旧轮次曾出现 `THREAD_BLOCK_6S`，本轮测试启动阶段也有一次，不能因重跑通过而抹去。跨段落窗口长文用例耗时约 40.36 秒，验证最终排版结果，不是输入帧率。分段布局回归通过不等于五万字输入帧率验收；单个原生排版调用仍不可中断。手机、平板、折叠屏、真实鼠标与真实中文输入法尚需分别实测。

关闭失败、重试与取消保护有本地异常注入回归，尚未在设备注入存储失败。构建告警与原生设备失败须如实记录，不用历史通过替代。

思路板仍以 r2 设计为依据，本轮未开始其数据表或页面实现。
