> **归档说明（2026-10-18 迁移）**：本报告生成于旧工作区 `/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`（API 23 副本，源码停在 2026-10-06）。当前工程为 `SDK26Target/Weaver`（API 26，含 10-13/10-17 优化与 10-18 编辑器修复），因此文中**构建、验证与代码规模结论已过时**；功能缺口类结论仅供参考，行动前请以当前源码重新审计。

# Weaver 构建 / 产物 / 测试 / 设备验证状态审计

> **审计对象**：`/mnt/linux_share/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`
> HarmonyOS ArkTS（Stage 模型），单 `entry` 模块，`compileSdkVersion 6.1.0(23)` / HarmonyOS 6.1.0
> **审计时间**：2026-10-18 02:20–02:40（Asia/Shanghai）
> **审计性质**：**只读审计**。未修改 `entry/src`、`spec/**`、`build-profile.json5`、`oh-package.json5` 等任何文件；唯一写入为本文件。
> **本机执行能力（已核实，非假设）**：
> - `which node` → `/usr/local/bin/node`，`node -v` → **v22.23.0** ✅
> - `which hvigorw / devecocli / hdc / ohpm` → **全部不存在** ❌
> - `ls /storage` → **No such file or directory**（项目内所有构建期绝对路径均指向 `/storage/...`，本机不可达）❌
> - `oh_modules/@ohos/hypium|hamock` → 是指向 `/storage/...` 的**悬空软链**（`test -e` 失败）❌
>
> 因此：**本次审计不执行、也无法执行任何 HarmonyOS 构建/安装/设备命令，未安装任何工具链。** 下面所有"构建成功/失败"结论均来自既有构建证据（`.hvigor/**`、`entry/build/**`）的解析与交叉验证，不来自本轮执行。技能要求的可执行命令已改写为第 7 节「设备侧命令卡」。

---

## 1. 结论先行

| 审计问题 | 结论 | 关键证据 |
|---|---|---|
| **当前构建是否绿？** | **绿，但"绿的含金量"要打折。** 全部构建日志中 `BUILD SUCCESSFUL` 共 **6 次、`BUILD FAILED` 0 次、`ERROR` 0 个**（`WARN` 111 条）。**但最近 3 次（2026-10-08）不是 HAP 构建**，任务图里只有 `:entry:compileNative`（1 ms 空任务），没有 `assembleHap / CompileArkTS / PackageHap / SignHap`。**真正的 HAP 构建最近一次是 2026-10-06 17:22:05**。 | `build.log:937,1819,2646,2852,2996,3146`；`.hvigor/report/report-20261008*.json` 中 `assembleHap` 计数 = 0、`compileNative` = 1；`.hvigor/cache/last-build-info.json` = `{"_":["compileNative"]}` |
| **产物是否可用？** | **可用（结构完整、达安装级）**。`entry-default-signed.hap` 1,935,547 B / `entry-default-unsigned.hap` 1,893,756 B，均为合法 zip（12 条目），内含 `module.json + ets/modules.abc(950,372 B) + resources.index + resources/*`；`bundleName=com.chungu.weaver`，`versionCode=1000000`，`targetAPIVersion=minAPIVersion=60100023`，`deviceTypes=[phone,tablet,2in1]`。**未在本机做安装级验证**（无 hdc）。 | `entry/build/default/outputs/default/*.hap`（mtime 2026-10-06 17:22:05）；`pack.info`；HAP 内 `module.json` |
| **产物是否落后源码？** | **不落后（mtime 推断）**。HAP mtime `17:22:05` **晚于**最新源码 `EntryAbility.ets 17:17:51`；且 `entry/src` + `AppScope` 下**没有任何文件**晚于该 HAP。⇒ 产物与当前源码**无 mtime 层面的落差**，无需仅因源码变更而重建。⚠️ 仅为 mtime 推断（共享盘 mtime 由构建主机写入，仓库无 `.git`，无法用内容哈希反证）。 | `stat` 对比；`find entry/src AppScope -newermt "2026-10-06 17:22:05"` → 空 |
| **验证覆盖到哪一层？** | **只到"编译期"层。单元测试资产存在但从未执行；设备/UI 验证不可判定。** 测试资产 = 2 套件 / **18 个用例**（`ActsAbilityTest` 1 + `FlowTextRegression` 17），但 `entry/build/default/outputs/` 下**只有 `default/`、没有 `ohosTest/`**（测试 HAP 从未构建）；仓库内**无截图、无 hdc 日志、无测试结果文件**。 | 见第 4、5 节 |

---

## 2. 构建历史（逐次交叉验证）

数据源：`.hvigor/outputs/build-logs/build.log`（3,179 行 / 277,213 B / mtime 2026-10-08 22:20:17，含 7 个 hvigor 调用会话）+ `.hvigor/report/report-*.json` + `.hvigor/cache/*`。

| # | 完成时间（Asia/Shanghai） | 结果 | 耗时 | 任务图（关键任务） | 全量/增量 | ERROR | WARN | 证据 |
|---|---|---|---|---|---|---|---|---|
| 0 | 2026-10-06 15:59:30 | 无 BUILD 行（独立的 `clean` 调用） | — | `:clean` + `:entry:clean` + `:init` | — | 0 | 0 | `build.log:2–151`，`clean` 完成于 `:74`、`:105` |
| 1 | **2026-10-06 15:59:52.355** | **SUCCESSFUL** | 19 s 778 ms | 全链路：`PreBuild→…→CompileArkTS(12 s 574 ms)→PackageHap(67 ms)→SignHap(225 ms)→assembleHap` | **全量**（前置 `clean`，UP-TO-DATE = 0） | **0** | 37 | `build.log:937`；`836`；`908`；`929`；`936` |
| 2 | **2026-10-06 16:24:54.428** | **SUCCESSFUL** | 22 s 533 ms | 15 个任务 UP-TO-DATE；`CompileArkTS(12 s 368 ms)` 重跑 + `PackageHap(79 ms)` + `SignHap(220 ms)` | **增量**（未执行 clean，任务缓存命中） | **0** | 37 | `build.log:1819`；`1715`；`1789`；`1811` |
| 3 | **2026-10-06 17:22:05.659** | **SUCCESSFUL** | 34 s 960 ms | 16 个任务 UP-TO-DATE；`CompileArkTS(21 s 166 ms)` 重跑 + `PackageHap(107 ms)` + `SignHap(212 ms)` | **增量** | **0** | 37 | `build.log:2646`；`2537`；`2616`；`2638`；`2645` |
| 4 | **2026-10-08 22:03:59.743** | SUCCESSFUL | 4 s 852 ms | **仅** `:entry:default@PreBuild`(UP-TO-DATE) + `:entry:compileNative`(1 ms) + `ConfigureCmake`(1 ms) + `BuildNativeWithCmake`(1 ms)。**无 CompileArkTS / PackageHap / SignHap / assembleHap** | **非 HAP 构建**（空任务图） | 0 | 0 | `build.log:2740–2886`、`:2852` |
| 5 | **2026-10-08 22:07:15.118** | SUCCESSFUL | 5 s 239 ms | 同 #4 | 非 HAP 构建 | 0 | 0 | `build.log:2887–3033`、`:2996` |
| 6 | **2026-10-08 22:20:17.233** | SUCCESSFUL | 5 s 224 ms | 同 #4（日志末行亦为"Cache 无需刷新"） | 非 HAP 构建 | 0 | 0 | `build.log:3034–3179`、`:3146` |

### 2.1 关键判读

1. **"最近一次是否 ERROR:0"** → **是**。全 3,179 行日志中 `ERROR` 出现 **0 次**；`BUILD FAILED` **0 次**。日志里唯一形似报错的是每个会话各 1 条（共 7 条）的
   `failed to load cangjie to dynamically generate schemas: Error: Cannot find module '@ohos/cangjie-build-support/index'`（首次见 `build.log:24`）——项目为纯 ArkTS、无 Cangjie 源码，该行是 hvigor 加载 Cangjie 支持失败的无害提示，**不影响构建结果**（其后仍 SUCCESSFUL）。
2. **最近 3 次"构建成功"是空转**：任务图仅 `compileNative`，且 `entry/src/main/cpp` **目录不存在**（无 C++ 源码），所以 `compileNative`、`ConfigureCmake`、`BuildNativeWithCmake` 各 1 ms 直接返回。三条独立证据互证：
   - `.hvigor/report/report-202610082203548900.json` / `…2207098780.json` / `…2220120080.json`：`"assembleHap"` 计数 **0**、`"compileNative"` 计数 **1**、`PackageHap/CompileArkTS/SignHap` 均 **0**；而 10-06 的三份 report 中 `"assembleHap"` 计数 1、`PackageHap` 出现 25–27 次。
   - `.hvigor/cache/last-build-info.json`（23 B，mtime 10-08 22:20:17）= `{"_":["compileNative"]}`。
   - HAP 文件 mtime 停在 **10-06 17:22:05**，未被 10-08 的"成功"刷新。
3. **增量判定依据**：`UP-TO-DATE` 任务计数 = build1:0 / build2:15 / build3:16 / build4-6:1；仅 build1 之前执行过 `clean`。
4. **ArkTS 编译实际是"整体重编译"而非真增量**（⚠️ 推断）：build2/build3 的 `CompileArkTS` 耗时 12.4 s / 21.2 s，与 build1 全量（12.6 s）同一量级，未随增量命中而下降。日志中 `incrementalExecution: true`（`build.log:5`）只是打开了增量框架。
5. `WARN` 全部来自 ArkTS 编译期，3 次 HAP 构建各 37 条（合计 111），构成：`Function may throw exceptions. Special handling is required.` 102 条、`ohos.permission.READ_PASTEBOARD` 需申请 3 条、`'replaceUrl' has been deprecated.` 3 条、`'px2vp' has been deprecated.` 3 条。**无一条 ERROR**，与 `spec/flowtext-integration/spec.md:101` 的"ERROR:0，仅保留已有 API 废弃 WARN"一致。

---

## 3. 构建元信息与目录时效

| 证据文件 | 内容 | mtime | 判读 |
|---|---|---|---|
| `.hvigor/cache/meta.json` | `{"compileSdkVersion":"6.1.0(23)","hvigorVersion":"6.23.15-next","toolChainsVersion":"6.1.0.105"}` | 2026-10-08 22:20:17 | 与 `build-profile.json5:22-23`（`6.1.0(23)`）及 HAP 内 `module.json.compileSdkVersion=6.1.0.105` **三方自洽** |
| `.hvigor/cache/last-build-info.json` | `{"_":["compileNative"]}` | 2026-10-08 22:20:17 | ⚠️ **最新构建记录只包含 native 任务**，即"最后一次构建"不含任何 ArkTS/打包环节 |
| `.hvigor/outputs/records/performance-recorder.json` | 5 条 rollup/ets-checker 事件：17:21:35 → 17:22:03 | 2026-10-06 17:22:03 | 只记录 build3 一次 ArkTS 编译；**无任何 10-08 记录**，反证 10-08 未进入 ArkTS 管线 |
| `.hvigor/outputs/sync/output.json` / `taskInfo.json` | 工程同步快照（`SELECT_TARGET=default`） | 2026-10-06 15:59:30 | **12 天未刷新**（10-08 的 native 任务未触发 resync） |
| `.hvigor/cache/task-cache.json` / `file-cache.json` | 任务/文件缓存 | 2026-10-08 22:20:17 | 被 10-08 空转构建刷新，**时间戳新但内容不代表 HAP 状态**（易误导"今天构建过"） |
| `.hvigor/report/` | 6 份构建报告（10-06 ×3 约 300 KB；10-08 ×3 约 101 KB） | 10-06 15:59 / 16:24 / 17:22；10-08 22:03 / 22:07 / 22:20 | 体量差异（300 KB vs 101 KB）与"全量/增量 HAP 构建 vs 空转 native 构建"吻合 |

**结论**：`meta.json` 表明工具链为 hvigor `6.23.15-next` + toolchains `6.1.0.105` + compileSdk `6.1.0(23)`；`last-build-info.json` 与 `performance-recorder.json` 共同证明**"最后一次构建"名不副实**——它没有产出任何 HAP。

---

## 4. 产物与新鲜度

### 4.1 产物清单

| 文件 | 大小 | mtime（Asia/Shanghai） | 说明 |
|---|---|---|---|
| `entry/build/default/outputs/default/entry-default-signed.hap` | **1,935,547 B**（≈1.85 MiB） | **2026-10-06 17:22:05.641** | 已签名，安装/运行用此包 |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | **1,893,756 B**（≈1.81 MiB） | **2026-10-06 17:22:05.401** | 未签名（差 41,791 B ≈ 签名块） |
| `entry/build/default/outputs/default/pack.info` | 570 B | 2026-10-06 15:59:35 | 由 build1 的 `MakePackInfo` 生成，后续构建 UP-TO-DATE |
| `entry/build/default/outputs/default/mapping/` | 目录 | 2026-10-06 15:59 | obfuscation 未启用（`entry/build-profile.json5:16` `enable:false`），目录为空壳 |

`pack.info`（全文）：

```json
{"summary":{"app":{"bundleName":"com.chungu.weaver","bundleType":"app","version":{"code":1000000,"name":"1.0.0"}},
"modules":[{"mainAbility":"EntryAbility","deviceType":["phone","tablet","2in1"],"distro":{"moduleType":"entry","installationFree":false,"deliveryWithInstall":true,"moduleName":"entry"},"apiVersion":{"compatible":23,"releaseType":"Release","target":23}}]},
"packages":[{"deviceType":["phone","tablet","2in1"],"moduleType":"entry","deliveryWithInstall":true,"name":"entry-default"}]}
```

**HAP 内部结构**（用 Python `zipfile` 直接读，未解压落盘）：12 个条目 —
`module.json`(1,375 B) / `ets/modules.abc`(950,372 B) / `ets/sourceMaps.map`(529,428 B，77 个模块条目) / `ets/symbolMap.map`(281,210 B) / `resources.index`(1,086 B) / `pack.info`(570 B) / 4 个 media 资源 / `main_pages.json` / `pkgContextInfo.json`。
`module.json`：`bundleName=com.chungu.weaver`、`versionCode=1000000`、`versionName=1.0.0`、`min/targetAPIVersion=60100023`、`compileSdkVersion=6.1.0.105`、`module.name=entry`、`mainElement=EntryAbility`、`deviceTypes=[phone,tablet,2in1]`、`abilities[0]=EntryAbility(exported:true, entity.system.home)`。
**无 `libs/` 目录** —— 与"无 `cpp/`、无 native 库"一致。

### 4.2 路径归属：产物不是本机产出

`entry/build/config/buildConfig.json`（2,386 B，mtime 2026-10-06 16:24:27）所有绝对路径都指向 `/storage/...`：

```json
"Path": "/storage/Users/currentUser/develop/deveco_tools/node/bin/",
"projectProfilePath": "/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver/build-profile.json5",
"aceModuleRoot": "/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver/entry/src/main/ets",
...（共 12 个绝对路径，全部同前缀）
"watchMode": "true"，"hapMode": "false"，patchConfig.mode = "hotReload"
```

- `/storage` 在**本机不存在**（`ls /storage` → No such file）。本机看到的同一份数据挂在 `/mnt/linux_share/storage`。
- `build.log` 里 hvigor 本体与 SDK 亦在 `/storage/Users/currentUser/develop/deveco_tools/{hvigor,sdk,node}`（如 `build.log:24–43` 的 `Require stack`）。
- 根 `build-profile.json5:8,11,13` 的 `certpath / profile / storeFile` 同样是 `/storage/Users/currentUser/Documents/ohos/config/default_Weaver*.{cer,p7b,p12}`，本机不可达。
- `oh_modules/@ohos/hypium`、`@ohos/hamock` 是指向 `/storage/...` 的软链，**本机为悬空链接**。

⇒ **判定**：这批产物由**另一台把共享盘挂在 `/storage` 的鸿蒙构建主机（DevEco 工具链 `deveco_tools`）**产出；本 OpenEuler 机既无该工具链也无法解析依赖，**不可复现构建，也不应把本机当作构建证据来源**。`buildConfig.json` 的 `watchMode=true / patchConfig.hotReload` 说明这份配置来自一次带预览/热重载语义的 ArkTS 编译（build2，16:24），仅作编译期参数留痕，不影响产物本身。

### 4.3 新鲜度：产物 vs 源码

| 对象 | 时间 |
|---|---|
| `entry/build/default/outputs/default/entry-default-signed.hap` | **2026-10-06 17:22:05.641** |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 2026-10-06 17:22:05.401 |
| 最新源码 ① `entry/src/main/ets/entryability/EntryAbility.ets` | **2026-10-06 17:17:51.881** |
| 最新源码 ② `entry/src/main/ets/shell/WorkspaceDest.ets` | 2026-10-06 17:17:00.482 |
| 最新源码 ③ `entry/src/main/ets/store/UiStore.ets` | 2026-10-06 17:14:46.174 |
| `find entry/src AppScope -newermt "2026-10-06 17:22:05"` | **无结果（0 个文件）** |
| 源码规模 | `entry/src/main/ets/**/*.ets` = **82** 个；`entry/src` 全部文件 = 101 个 |

**结论：产物不落后于源码，无需仅因源码变更而重建**——HAP 比最新 `.ets` 晚 **4 分 13 秒**，且 build3 的 `CompileArkTS` 窗口（17:21:35–17:22:03，见 `performance-recorder.json`）完整覆盖了 17:17:51 的最后一次编辑。

⚠️ **推断标注与边界**：
1. 该结论**仅基于 mtime**。共享盘 mtime 由构建主机写入，可信度高于本机改动，但仓库**无 `.git`**，无法用内容哈希证明 HAP 内的 `modules.abc` 就是当前源码的编译结果。
2. HAP 内 `ets/sourceMaps.map` 只有 77 个模块条目，磁盘有 82 个 `.ets`；6 个未单独出现（`model/GraphNode`、`model/Inspiration`、`model/index`、`shell/MobileSectionTabs`、`shell/MobileTabBar`、`store/BackupTypes`）。这 6 个**全部 mtime = 2026-10-06 15:51:43**（早于构建），且其中 `MobileTabBar` 被 `MobileShell.ets:20` 显式 import、`AppStores` 被 `EntryAbility.ets` 等 10 处 import —— 说明 **sourceMaps 的 key 不是"逐源文件的完整清单"（rollup 合并所致）**，因此它**不能**用来做逐文件内容一致性证明，本次不据此下结论。是否属不可达死代码，归 feature/quality 审计范畴。
3. 若近期有人在**其他挂载点/其他分支**改过源码而未同步到共享盘，则本结论不成立；重建成本很低，见第 7 节命令卡步骤 1。

---

## 5. 测试资产清点

### 5.1 资产清单

| 资产 | 路径 | 内容 | 覆盖能力 | 证据 |
|---|---|---|---|---|
| 测试入口 | `entry/src/ohosTest/ets/test/List.test.ets` | 聚合 `abilityTest()` + `flowTextTest()` | — | 6 行 |
| 套件 A | `entry/src/ohosTest/ets/test/Ability.test.ets` | `describe('ActsAbilityTest')`，**1 个用例** `assertContain` | 仅 hypium 冒烟（字符串断言），**无业务断言** | `:5`、`:25-33` |
| 套件 B | `entry/src/ohosTest/ets/test/FlowText.test.ets` | `describe('FlowTextRegression')`，**17 个用例** | 见 5.2 | `:22` |
| 共享夹具 | `entry/src/ohosTest/ets/test/FlowTextFixture.ets` | 静态 `CanvasTextEditorController` + `ready/savedText/savedCaret/savedRuns/selectionStart/selectionEnd` | 供 UI 回调回填断言 | 11 行 |
| 测试 Ability | `entry/src/ohosTest/ets/testability/TestAbility.ets` | `onWindowStageCreate` → `loadContent('testability/pages/Index')` → **`setTimeout(300ms)`** → `Hypium.hypiumTest(...)` | 触发 hypium | `:10-12` |
| 测试页 | `entry/src/ohosTest/ets/testability/pages/Index.ets` | 挂载 `CanvasTextEditor`（`controller: FlowTextFixture.controller`），`onAppear` 置 `FlowTextFixture.ready = true` | 真机渲染夹具 | `:10-23` |
| 测试 Runner | `entry/src/ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets` | `startAbility({bundleName, moduleName:'entry_test', abilityName:'TestAbility'})` | `aa test` 入口 | `:6-10` |
| 测试模块配置 | `entry/src/ohosTest/module.json5` | `name=entry_test`、`type=feature`、`deviceTypes=[phone,tablet,2in1]`、`pages=$profile:test_pages`、`abilities=[TestAbility]` | 测试包元信息 | `:4-21` |
| 测试页表 | `entry/src/ohosTest/resources/base/profile/test_pages.json` | `{"src":["testability/pages/Index"]}` | — | — |
| 构建目标 | `entry/build-profile.json5:29-31` | `targets: [{name:"default"}, {name:"ohosTest"}]` | 声明了测试 target | — |
| 测试框架依赖 | `oh-package.json5`（根）`devDependencies` | `@ohos/hypium 1.0.19`、`@ohos/hamock 1.0.0` | — | — |
| 依赖锁 | `oh-package-lock.json5` | 同上两版本，含 integrity（sha512），resolved 指向 `ohpm.openharmony.cn` | — | — |
| 已装依赖 | `oh_modules/@ohos/{hypium,hamock}` | **软链 → `/storage/...`（本机悬空）** | 本机无法解析 | `test -e` 失败 |

### 5.2 `FlowTextRegression` 17 个用例覆盖了什么

| # | 用例（`FlowText.test.ets` 行号） | 覆盖能力 |
|---|---|---|
| 1 | `nativeApiContract`（23） | `@ohos.graphics.text` typeset/line/glyphRun 契约（行断点、字符串索引→偏移、glyph range） |
| 2 | `graphemeDeletionPreservesPrefix`（31） | 字素簇删除：emoji / 增补平面（甲𠮷）/ ZWJ 家庭 / 肤色 / 区域旗帜 / 组合重音 |
| 3 | `selectionAnchorSurvivesRepeatedExtension`（40） | 选区锚点 vs head 方向语义 |
| 4 | `mixedBoldSelectionFillsGaps`（48） | 行内格式 run 的缺口填充与非重叠合并 |
| 5 | `previewRangeAndCommitSnapshot`（54） | IME 预上屏（preview）区间 + commit 后文本/偏移/isComposing |
| 6 | `nativeMixedTextIndicesAndCaret`（62） | 中文+emoji+连字混排下每字素 caret 的 X 与 native `getOffsetForStringIndex` 对齐（<0.01） |
| 7 | `nativeBlankAndTrailingParagraphs`（87） | 空文档 1 行、`A\n\n` 3 行、末段起始索引 |
| 8 | `nativeWidthChangeReflowsText`（93） | 宽度变化重排（100 vs 480） |
| 9 | `nativeNarrowWrapKeepsEmojiClustersWhole`（97） | 极窄（12vp）换行不劈裂 emoji 簇、行首尾均为字素边界 |
| 10 | `nativeWordBoundaryAfterEmojiUsesDocumentOffsets`（106） | emoji 后单词范围用文档偏移（`[2,7]`） |
| 11 | `nativeHeadingMetricsReserveEnoughHeight`（111） | 标题行高 ≥ ascent+descent 且 > 正文 |
| 12 | `nativeDensityKeepsVpCoordinates`（118） | density 1 vs 2 时宽度保持 vp 坐标（差 <2） |
| 13 | `nativeBidiAndLigaturesHaveFiniteGeometry`（123） | 连字（office/affine/ffi）+ 希伯来/阿拉伯 RTL 的 caret 几何有限且高 >0 |
| 14 | `nativeIncrementalLayoutRetainsEarlierParagraph`（136） | `LayoutCache.applyEdit` 后前段对象复用（引用相等）、末段索引正确 |
| 15 | `canvasControllerClearsSelectionAndDeletesOnlyEmoji`（144） | 控制器级：删 emoji 不删前缀、光标尾插；**依赖 `FlowTextFixture.ready`** |
| 16 | `canvasControllerRestoresAndShiftsFormat`（152） | run 随插入右移、`onEdit` 回调回填 `savedText/savedCaret/savedRuns` |
| 17 | `canvasPhysicalKeyboardSelectionAndEmojiBackspace`（160） | `Driver/ON/KeyCode` 真机按键：Shift+Left 连按扩展选区、Left 折叠、DEL 删 emoji |

**合计：2 个 describe / 18 个 `it` 用例。**

### 5.3 覆盖缺口（对"覆盖了哪些能力"的否定性结论）

- ❌ **没有 BookDao / CRUD 测试**：全仓 `ohosTest` 无任何 `BookDao`、`DatabaseHelper`、`ChapterDao` 引用。任务摘要中假设的"BookDao CRUD 覆盖"**不存在**。
- ❌ 无持久化测试：`chapters.format_runs` 幂等加列（`IMPLEMENTATION_NOTES.md` 声称的 `ensureColumns()` 兼容方案）、`FormatCodec` 编解码、备份/恢复均无用例。
- ❌ 无 `EditorStore` 事务/防抖落库、`ExportService` markdown 导出的用例。
- ❌ 无页面/导航级用例（除夹具页 `FlowTextTestPage` 本身）；`MobileShell` 底部页签、断点切换无自动化。
- ✅ 强项在 **FlowText 排版/字素/IME/格式** 这一层，17 个用例里 11 个直接打真实 native 排版引擎，属高价值真机测试。

### 5.4 能否在设备侧跑起来？

**能，但从未跑过，且首次构建存在未知风险。**

- 需要设备侧两步产物：`default` HAP（承载 `com.chungu.weaver` 主包）+ `ohosTest` HAP（`entry_test` 测试模块，`TestAbility`/`OpenHarmonyTestRunner`）。
- 当前 `entry/build/default/outputs/` 下**只有 `default/`**，**没有 `ohosTest/`** ⇒ 测试 HAP 从未构建、测试从未执行（也解释了为何 `tools/.test-results/` 不存在）。
- 首次构建 `ohosTest` target 可能暴露编译错误：`FlowTextFixture.ets` 跨目录引用 `main/ets/...`，`FlowText.test.ets` 依赖 `@kit.TestKit` 的 `Driver/ON` 与 `@kit.InputKit` 的 `KeyCode`，这些在 test target 下的可用性**尚未被任何构建验证过**。
- `TestAbility.ets:10-12` 用**固定 300 ms 延时**才启动 hypium，而 `Index.ets:23` 在 `onAppear` 里置 `ready=true`。设备/模拟器负载高时 `FlowTextFixture.ready` 可能仍为 `false`，使用例 15（`:144`）出现**假失败**。
- 用例 17（`:160`）依赖物理键盘按键合成（`triggerCombineKeys`），模拟器行为与真机可能不一致，建议真机或 2in1 上跑。

---

## 6. 设备验证痕迹与结论

### 6.1 检索范围与方法

- 全仓（排除 `.hvigor/` 大日志、`oh_modules`、`.git`）grep：`hdc`、`snapshot_display`、`screenshot`、`dumpLayout`、`uitest uiInput`、`aa start`、`install -r`、`devecocli run`、`verify_ui`、`aa test`。
- 文件型证据检索：`*.png|jpg|jpeg|webp`、`*hilog*`、`*faultlog*`、`*.log`（`.hvigor` 之外）、`tools/.test-results/`。

### 6.2 找到的痕迹（全部为"计划/脚本/陈述"，无产物）

| 痕迹 | 位置 | 性质 |
|---|---|---|
| 设备测试脚本（**从未运行**） | `tools/Test-FlowText.ps1` | 完整闭环脚本：要求 `-DevEcoRoot`，校验 `node.exe/hvigorw.js/hdc.exe` 存在，构建 `default`+`ohosTest` 两个 HAP，`hdc -t $Device install`，`hdc shell aa test -b com.chungu.weaver -m entry_test -s unittest OpenHarmonyTestRunner -w 60`，并用正则 `Tests run: [1-9]\d*, Failure: 0, Error: 0, Pass: [1-9]\d*, Ignore: 0` 判定。**`tools/.test-results/` 目录不存在 ⇒ 从未执行成功过** |
| 明确"无设备"的自述 | `spec/flowtext-integration/tasks.md:132` | T020 **未勾选**："⚠️ No device available; HAP built successfully at `/storage/.../entry-default-unsigned.hap`" |
| 部分 UI 验证的自述 | `spec/mobile-ui-refactor/tasks.md:140-141` | T038 **未勾选**，备注："US1/US2/US3 已实机截图复核通过（US2 修复了一个 showActionMenu 空 color 导致的运行时崩溃）；US4 … 未执行——`verify_ui` 后端不可用（Connect server failed）…`lg` 零回归仅完成静态代码复核" |
| 已完成部署+UI 验证的自述 | `spec/flowtext-sole-editor/tasks.md:175-176` | T045/T046 **已勾选**（"运行 `devecocli run --skip-build`"、"invoke verify_ui，逐用户故事覆盖…"），**但无任何截图/日志/结果文件** |
| "禁止使用 hdc"的环境约束 | `spec/mobile-ui-refactor/tasks.md:141` | 说明当时环境有 `devecocli` 而无合法 `hdc` 通道，验证只能走 `verify_ui` |
| 历史真机崩溃记录（他人转述） | `.workbuddy/memory/2026-08-13.md:24,35` | "编译已通过（ERROR:0），但真机（HUAWEI MatePad Edge）运行崩溃，jscrash 日志…"、"沙箱无 hvigor，需用户重新 assembleHap 验证" |
| 反复出现的"待真机验证" | `.workbuddy/memory/2026-10-02.md:38,105,286,362`；`MEMORY.md:7` | 明示"构建工具链在沙箱不可用，只能静态核查 + 用户真机验证" |
| 视觉验证不可用的自述 | `docs/design/ui-spec.md:5` | "当前环境**无原生视觉**（看图/截图不可用）… 最终由人工肉眼验收" |

### 6.3 未找到的痕迹（关键否定证据）

- ❌ **截图 0 张**：全仓 `*.png/jpg/jpeg/webp` 只有 8 个**应用资源图**（`AppScope/resources/base/media/*`、`entry/src/main/resources/base/media/*` 及其 intermediates 副本），**没有任何验证截图**，也没有 `screenshots/` 目录。
- ❌ **hdc 日志 0 个**：无 `*.log`、无 hilog/faultlog 导出文件（`.hvigor` 之外）。
- ❌ **测试结果 0 个**：无 `tools/.test-results/`、无 `test_result.txt`、无 `coverage/`。
- ❌ **ohosTest 产物 0 个**：`entry/build/default/outputs/` 只有 `default/`。
- ⚠️ **自述互相矛盾**：`flowtext-integration` 说"无设备"，`flowtext-sole-editor` 却勾选"已部署 + 已 verify_ui"，`mobile-ui-refactor` 说"US1–3 截图通过、US4 不可用"。三者描述的是不同时间点的不同环境，但**都未留下可复核产物**。

### 6.4 结论（三选一）

> ### **整体判定：不可判定（Inconclusive）**
> 三份 spec 的"UI 验证/部署"任务**无法被证实，也无法被证伪**。仓库内**没有任何可复核的执行产物**（截图/日志/测试结果/测试 HAP 一律缺失），只有 Markdown 里的勾选与文字陈述；而这些陈述本身互相矛盾——一份明确写"无设备"（`spec/flowtext-integration/tasks.md:132`），另一份勾选了"已部署 + verify_ui"（`spec/flowtext-sole-editor/tasks.md:175-176`）。

分 spec 细分：

| Spec | 部署/UI 验证任务 | 判定 | 依据 |
|---|---|---|---|
| `flowtext-integration` | T019 构建 ✅ / T020 部署 ❌ | **未执行**（明确记录无设备） | `tasks.md:131-132`；且该 spec 的 `verification_scope: build-only`（`:127`），UI 验证本就不在范围内 |
| `mobile-ui-refactor` | T036 构建 ✅ / T037 部署 ✅ / T038 UI 验证 ❌ | **不可判定**（声称 US1–US3 截图通过，US4 明确未执行；零截图证据） | `tasks.md:138-141` |
| `flowtext-sole-editor` | T044 构建 ✅ / T045 部署 ✅ / T046 UI 验证 ✅ | **不可判定**（勾选完成但零产物，且与环境自述冲突） | `tasks.md:174-176` |

**为什么不能判"已验证"**：无截图、无 hdc 日志、无测试结果文件、无 `ohosTest` 产物 —— 违反 `deveco-studio-verify` 技能的验证检查清单（"关键步骤已截图留痕 / 日志已收集 / 验证报告已生成"三项全不满足）。
**为什么不能判"未执行"**：`.workbuddy/memory/2026-08-13.md:24` 记录了用户真机（HUAWEI MatePad Edge）jscrash 的具体报错，属"确实上过设备"的间接证据；`tools/Test-FlowText.ps1` 也说明设备通道曾被认真准备过。只是**证据不在仓内**。

---

## 7. 设备侧待执行命令卡

> 全部命令**须在装有 DevEco Studio（含 `hvigorw`/`hdc`/SDK 6.1.0(23)）的鸿蒙主机上执行**，本 OpenEuler 机不具备条件（见文首）。`$DEVECO` 为 DevEco Studio 安装根目录，`$PROJ` 为工程根目录（鸿蒙主机上通常形如 `/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`）。
> 依据技能：`deveco-studio-hvigor`（构建命令与判据）、`deveco-studio-verify`（设备验证）、`hmos-local-test`（测试执行）。

### 步骤 0 · 环境自检

```bash
node "$DEVECO/tools/hvigor/bin/hvigorw.js" --version     # 期望: 6.23.15-next
echo "$DEVECO_SDK_HOME"                                   # 期望: $DEVECO/sdk
hdc list targets                                          # 期望: 至少 1 行设备 id（如 127.0.0.1:5555）
```

- **期望输出**：hvigor 版本 `6.23.15-next`；`hdc list targets` 非空。
- **失败判据**：`hvigorw.js` 不存在 / `hdc` 不存在 / `hdc list targets` 输出 `[Empty]` → 无设备，转"无设备替代方案"。

### 步骤 1 · 重建 HAP（刷新产物，顺带验证"当前源码可编译"）

```bash
cd "$PROJ"
node "$DEVECO/tools/hvigor/bin/hvigorw.js" assembleHap \
  --mode module -p module=entry@default -p buildMode=debug --no-daemon
```

- **期望输出**：末行 `BUILD SUCCESSFUL in ...`；日志内 `ERROR` 计数 **0**（`WARN` 允许，已知 37 条）；`entry/build/default/outputs/default/entry-default-signed.hap` 与 `-unsigned.hap` 的 **mtime 被刷新到当前时间**、大小仍在 ≈1.9 MB 量级。
- **失败判据**：出现 `BUILD FAILED` / `ERROR:` / 退出码 ≠ 0 / **HAP mtime 未变**（出现"假绿"：只跑了 native 空任务，参见本报告第 2.1 节）。
- **注意**：必须用 `assembleHap`（或 `devecocli build`）。若只看到 `compileNative` 完成，**不算构建成功**。

### 步骤 2 · 构建测试 HAP（当前完全缺失）

```bash
cd "$PROJ"
node "$DEVECO/tools/hvigor/bin/hvigorw.js" assembleHap \
  --mode module -p product=default -p module=entry@ohosTest --no-daemon
```

- **期望输出**：`BUILD SUCCESSFUL`，且新出现 `entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap`（或同名 unsigned）。
- **失败判据**：`entry/build/default/outputs/ohosTest/` 未生成；或报 `Cannot find module '@ohos/hypium'`（依赖未 install → 先 `ohpm install`）；或 `FlowText.test.ets` 引用的 `Driver/ON`/`KeyCode` 在 test target 下不可用（属真实缺陷，需记录并修复）。

### 步骤 3 · 安装并执行 18 个单元用例（hypium / ohosTest，instrument 形态）

```bash
hdc -t <device_id> install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <device_id> install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc -t <device_id> shell aa test -b com.chungu.weaver -m entry_test \
  -s unittest OpenHarmonyTestRunner -w 60
```

- **期望输出**：`install bundle successfully` ×2；末尾汇总形如 `Tests run: 18, Failure: 0, Error: 0, Pass: 18, Ignore: 0`。
- **失败判据**：`install` 未出现 `install bundle successfully`；`aa test` 超时；`Failure` / `Error` 计数 > 0；`Tests run` 计数 ≠ 18（少跑说明 `List.test.ets` 未聚合或 `TestAbility` 300 ms 延时导致夹具未 ready）。
- **已知风险**：用例 `canvasControllerClearsSelectionAndDeletesOnlyEmoji`（`FlowText.test.ets:144`）依赖夹具 ready，慢设备可能假失败——若怀疑假失败，先手动 `hdc shell aa start -a TestAbility -b com.chungu.weaver -m entry_test` 观察测试页是否渲染，再复跑。
- ⚠️ `hdc shell param set persist.ace.testmode.enabled 1` 是**持久化**系统参数，仅在测试模拟器上开启，用完必须 `... 0` 复位（见 `deveco-studio-verify` 警告）；本流程的 `aa test` 不强制需要它。

### 步骤 4 · 运行态 + UI 取证（替代不可用的 `verify_ui`）

```bash
hdc -t <id> shell aa start -a EntryAbility -b com.chungu.weaver
hdc -t <id> shell hilog -x -n 400 | grep -Ei "jscrash|FaultLogger|FlowTextDiag|ERROR"
hdc -t <id> shell snapshot_display -f /data/local/tmp/weaver_main.jpeg
hdc -t <id> file recv /data/local/tmp/weaver_main.jpeg ./artifacts/weaver_main.jpeg
hdc -t <id> shell uitest dumpLayout -p /data/local/tmp/layout.txt
hdc -t <id> file recv /data/local/tmp/layout.txt ./artifacts/layout.txt
```

- **期望输出**：进程存活；hilog 无 `jscrash`/`FATAL`（`FlowTextDiag` 可按需打开）；截图非黑屏/非纯白，能看出底部页签与正文；`layout.txt` 含页签文字节点。
- **失败判据**：`aa start` 报 `error: failed to start ability`；hilog 出现 `Reason:Error`/`SIGSEGV`；截图全黑或与预期页面对不上；`dumpLayout` 为空。
- **取证纪律**：把截图/日志存进仓库 `artifacts/`（本报告建议新增目录），否则 spec 里的"已截图复核通过"永远不可审计。

### 步骤 5 · 一键脚本（仓库已有，从未运行）

```powershell
# Windows / PowerShell，DevEco 主机
pwsh -File tools/Test-FlowText.ps1 -DevEcoRoot "D:\AI\DevEco Studio" -Device <device_id>
# 只构建不跑设备：
pwsh -File tools/Test-FlowText.ps1 -DevEcoRoot "D:\AI\DevEco Studio" -BuildOnly
```

- 该脚本已内置步骤 1+2+3 与正则判据（`tools/Test-FlowText.ps1:26-50`），产物落到 `tools/.test-results/{default,ohosTest}-build.log`、`{default,ohosTest}-install.log`、`device-tests.log`。
- **失败判据**：脚本抛 `$target build failed` / `install failed` / `FlowText device regression failed`；或 `tools/.test-results/` 未生成。

### 6' · 无设备时的替代方案（本机已实测可用 1 项）

| 方案 | 命令 | 覆盖 | 本机实测 |
|---|---|---|---|
| **离线逻辑回归（33 项）** | `node tools/flowtext-regression.cjs` | 用 `node:module.stripTypeScriptTypes` 直接跑工程 `.ets` 源码的 model/interaction/render/animation/IME/store 纯逻辑（native 排版、graphics、IME 控制器为可控 double） | ✅ **本次审计实际执行**：node v22.23.0 → `FlowText regression: 33 checks passed`（退出码 0，未创建任何文件）。**局限**：不覆盖 ArkUI 渲染、系统 IME、真机焦点/物理键盘、数据库 |
| 构建期静态检查 | `devecocli check lint` / CodeLinter（`code-linter.json5` 已配置） | 静态规则 | ❌ 本机无 devecocli |
| 字素表再生成 | `python3 tools/generate-grapheme-data.py` | Unicode 字素数据一致性 | 未运行（会写文件，超本次只读范围） |
| 设备日志 | `hdc shell hilog -x -n 400` | 运行时崩溃/异常 | ❌ 无 hdc、无设备，**不可替代** |

> 说明：`node tools/flowtext-regression.cjs` 是本机**唯一**可执行的验证手段；它证明 FlowText 纯逻辑层当前自洽，**但不能**替代真机 UI/渲染/数据库验证。

---

## 8. 风险与建议（按优先级）

| # | 风险 | 影响 | 建议 / 处置 |
|---|---|---|---|
| **R1** | **"BUILD SUCCESSFUL" 语义陷阱**：最近 3 次"成功"是 `compileNative` 空转（无 cpp，1 ms 返回），HAP 未被更新 | 任何人只看 `build.log` 尾部或 `task-cache.json` mtime，都会误以为"10-08 构建过、产物是最新的" | 把**验收判据改为「HAP mtime 变化 + 输出目录出现新文件」**，而不是日志里的 SUCCESSFUL；CI 里加一步 `stat -c %Y entry/build/default/outputs/default/entry-default-signed.hap` 并与构建开始时间比较 |
| **R2** | **ohosTest 从未构建** | 18 个用例的**可编译性本身未被验证**；首次跑可能出现编译错误（跨目录引用 main、`@kit.TestKit`/`@kit.InputKit` 在 test target 的可用性） | 设备侧先只执行命令卡**步骤 2**（`-BuildOnly`），把编译问题与运行问题分离；预计这是最先踩的坑 |
| **R3** | **验证证据不可审计**：3 份 spec 的"截图通过/verify_ui 通过"无任何产物，且互相矛盾 | 交付状态无法对外声明；`spec/mobile-ui-refactor/tasks.md:140` 的 T038 与 `flowtext-sole-editor/tasks.md:176` 的 T046 属"声称完成但不可复核" | 新建 `artifacts/`（截图+layout+hilog+test_result）并入版本库；在 spec 的任务里**引用产物相对路径**，无产物不得勾选 |
| **R4** | **测试夹具时序脆弱**：`TestAbility.ets:10-12` 固定 300 ms 后启动 hypium，`Index.ets:23` 才在 `onAppear` 置 ready | 慢设备/模拟器上用例 15 会**假失败**，容易被误判为产品缺陷 | 改为轮询等待（如 50 ms × 100 次探测 `FlowTextFixture.ready`）后再 `hypiumTest`，或把 ready 断言挪到 `beforeAll` 并配超时 |
| **R5** | **数据层零覆盖**：无 BookDao/ChapterDao/DatabaseHelper/FormatCodec/备份恢复用例 | `IMPLEMENTATION_NOTES.md` 声称的 `format_runs` 幂等 `ALTER` 兼容方案、旧库升级路径**无任何自动化验证**，属最高回归风险 | 补 `BookDao CRUD` + `ensureColumns()` 旧库升级 + `FormatCodec` 往返 3 组用例（可复用 `ohosTest` 的 `abilityDelegator` 取 `context.databaseDir` 建临时库） |
| **R6** | **产物可用性只到"结构完整"**：本机无 hdc，未做安装/启动/首帧验证 | HAP 可能是"能打包但不能装/不能起"（历史上曾出现 `showActionMenu` 空 color 导致运行时崩溃，见 `spec/mobile-ui-refactor/tasks.md:141`） | 设备侧执行命令卡步骤 3+4，至少拿到"安装成功 + `aa start` 成功 + hilog 无 jscrash + 1 张截图"四件套 |
| **R7** | **签名材料不可复核**：`build-profile.json5:8,11,13` 的 cer/p7b/p12 在 `/storage/...`，本机不存在 | 无法验证签名证书链、无法在本机重签；换机器/换证书后产物不可比 | 在鸿蒙主机上执行 `hap-sign-tool verify-app`（或 DevEco 签名校验），把结果贴进验收记录；签名材料路径避免硬编码绝对路径（改用工程内 `signing/` + `.gitignore`） |
| **R8** | **共享盘双挂载点**：同一数据在构建主机为 `/storage/...`、在本机为 `/mnt/linux_share/storage/...` | 任何绝对路径（`buildConfig.json`、`sync/output.json`、`oh_modules` 软链）在本机无效；`ohpm install` 在本机会产生不可用软链 | 文档与脚本统一用**工程相对路径**；跨机审计时明确"路径存在性"判定（本报告第 4.2 节的做法）作为**产物来源归属**的证据 |
| **R9** | 增量编译名不副实：`CompileArkTS` 每次都 12–21 s 整体重编译（⚠️ 推断，基于耗时同量级） | 改一行动辄 20 s+；`hvigorw` 的 incremental 实际未生效 | 排查 `arkCompileCachePath`（`build.log:559`）/ `cachePath`（`:598`）是否被清理，或 `buildConfig.json` 的 `watchMode=true` 干扰；必要时固定 `--no-daemon` 并核对 `execution.incremental` 配置 |

---

## 附录 A · 证据索引

| 证据 | 路径 | 关键位置 |
|---|---|---|
| 构建日志 | `.hvigor/outputs/build-logs/build.log` | `937/1819/2646`（HAP 构建 SUCCESSFUL）；`2852/2996/3146`（native 空转 SUCCESSFUL）；`74/105`（clean）；`836/1715/2537`（CompileArkTS）；`908/1789/2616`（PackageHap）；`929/1811/2638`（SignHap）；`24`（cangjie 无害报错） |
| 构建元信息 | `.hvigor/cache/meta.json` | hvigor 6.23.15-next / toolChains 6.1.0.105 / compileSdk 6.1.0(23) |
| 最近构建记录 | `.hvigor/cache/last-build-info.json` | `{"_":["compileNative"]}` |
| ArkTS 编译性能 | `.hvigor/outputs/records/performance-recorder.json` | 17:21:35–17:22:03，仅 build3 |
| 构建报告 | `.hvigor/report/report-2026100{6,8}*.json` | 10-08 三份：`assembleHap=0, compileNative=1` |
| 工程同步 | `.hvigor/outputs/sync/{output,taskInfo}.json` | 2026-10-06 15:59:30（12 天未刷新） |
| 产物 | `entry/build/default/outputs/default/` | signed 1,935,547 B / unsigned 1,893,756 B，mtime 17:22:05 |
| 打包元信息 | `entry/build/default/outputs/default/pack.info` | bundleName/versionCode/deviceType/apiVersion |
| 编译期路径 | `entry/build/config/buildConfig.json` | 12 个 `/storage/...` 绝对路径；`watchMode=true` |
| 签名配置 | `build-profile.json5:3-17` | cer/p7b/p12 均在 `/storage/...` |
| 测试资产 | `entry/src/ohosTest/**` | `test/{Ability,FlowText,List}.test.ets`、`FlowTextFixture.ets`、`testability/**`、`module.json5` |
| 测试依赖 | `oh-package.json5`、`oh-package-lock.json5`、`oh_modules/@ohos/*` | hypium 1.0.19 / hamock 1.0.0；本机软链悬空 |
| 设备脚本 | `tools/Test-FlowText.ps1` | `:26-50` 构建+安装+`aa test`+正则判据；`tools/.test-results/` 不存在 |
| 离线回归 | `tools/flowtext-regression.cjs` | 本次实跑：`FlowText regression: 33 checks passed` |
| Spec 验证任务 | `spec/flowtext-integration/tasks.md:131-132`；`spec/mobile-ui-refactor/tasks.md:138-141`；`spec/flowtext-sole-editor/tasks.md:174-176` | 勾选状态与自述 |
| 环境自述 | `.workbuddy/memory/MEMORY.md:7`；`2026-08-13.md:24,35`；`2026-10-02.md:38,105`；`docs/design/ui-spec.md:5` | 沙箱无工具链 / 真机 jscrash / 无原生视觉 |

## 附录 B · 本报告结论的置信度

| 结论 | 置信度 | 理由 |
|---|---|---|
| 6 次 SUCCESSFUL、0 次 FAILED、0 个 ERROR | **高** | 直接计数，日志唯一来源，无歧义 |
| 最近 3 次不是 HAP 构建 | **高** | 三源互证（build.log 任务图 / report JSON 任务计数 / last-build-info + HAP mtime 未变） |
| 产物不落后源码 | **中**（mtime 推断） | 无 `.git`、无内容哈希；但"无任何文件晚于 HAP"是很强的 mtime 证据 |
| 产物来源非本机 | **高** | `/storage` 本机不存在 + 软链悬空 + buildConfig 全绝对路径 |
| 测试 18 用例、2 套件 | **高** | 逐行计数 |
| 测试从未在设备执行 | **高**（否定性证据完整） | 无 ohosTest 产物、无 .test-results、无结果文件、无日志 |
| 设备 UI 验证"不可判定" | **高** | 证据缺口 + spec 自相矛盾，二者都指向"不可判定"而非任一极 |
