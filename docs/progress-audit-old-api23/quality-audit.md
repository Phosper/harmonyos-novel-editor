> **归档说明（2026-10-18 迁移）**：本报告生成于旧工作区 `/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`（API 23 副本，源码停在 2026-10-06）。当前工程为 `SDK26Target/Weaver`（API 26，含 10-13/10-17 优化与 10-18 编辑器修复），因此文中**构建、验证与代码规模结论已过时**；功能缺口类结论仅供参考，行动前请以当前源码重新审计。

# Weaver 代码质量审计（ArkTS 语法红线 / 废弃接口 / 工程质量）

> **审计对象**：`/mnt/linux_share/storage/Users/currentUser/Documents/DevEcoStudioProjects/Weaver`
> HarmonyOS ArkTS（Stage 模型，状态管理 V2 为主 + FlowText 编辑器 V1 边界），单 `entry` 模块
> `compileSdkVersion / compatibleSdkVersion = 6.1.0(23)`，`bundleName = com.chungu.weaver`
> **审计时间**：2026-10-18 02:20–03:00（Asia/Shanghai）
> **审计性质**：**只读审计**。未修改 `entry/src/**`、`spec/**`、`build-profile.json5`、`oh-package.json5`、`code-linter.json5` 中任何字节；唯一写入为本文件。
> **扫描范围**：`entry/src/main/ets/**/*.ets`（82 文件 / 13,928 行）+ `entry/src/ohosTest/**/*.ets`（7 文件 / 281 行）。

---

## 1. 结论先行

| 审计问题 | 结论 |
|---|---|
| **是否可构建？** | **可以。** 仓库内 6 次 hvigor 调用全部 `BUILD SUCCESSFUL`、`BUILD FAILED` 0 次、`ArkTS:ERROR` 0 条。真正的 HAP 构建最近一次为 **2026-10-06 17:22:05**（`CompileArkTS 21.2s → PackageHap → SignHap`）；2026-10-08 的三次"成功"只跑了 `:entry:compileNative`（1 ms 空任务），不含 ArkTS 编译，不能作为本轮代码的编译证据。 |
| **阻塞项（Blocker）** | **0 个。** 无编译级 ArkTS 红线违规，无缺失 import、无自造语法。 |
| **ArkTS 红线** | **0 处确证违规。** `any`/`unknown` 显式使用 0、对象展开 0、解构声明/参数/赋值 0、`var` 0、`Record<>` 0、`@Entry build()` 顶部 `const` 0、`@Observed` 错误 import 0、`@Builder` 返回值误用 0。 |
| **废弃 API** | **2 处仍在**（`px2vp` 1 处、`router.replaceUrl` 1 处），均为 WARN 级，**不阻塞构建**。历史清单中的 `router.pushUrl/show/getParams/back`、`AlertDialog + textInput`、`matchMediaSync`、`TextPicker` 旧 `onChange`、`Row/Column.wrapContent()` 在当前源码中**已全部为 0**。 |
| **WARN 是否阻塞构建？** | **不阻塞。** 3 次完整 HAP 构建各产生 **37 条唯一 WARN**（日志累计 111 条），每次都以 `BUILD SUCCESSFUL` 结束并正常产出签名 HAP。WARN 构成为：`Function may throw exceptions` 34 条 + 废弃 API 2 条 + `READ_PASTEBOARD` 权限提示 1 条，**无一条 ERROR**。 |
| **遗留风险（Top 3）** | ① `module.json5` **未声明任何权限**，导致 `pasteboard.getData()` 读系统剪贴板必然失败，跨应用粘贴静默退化为应用内缓冲（功能缺口，非崩溃）；② 9 处 `.catch(() => {})` + 8 处静默 catch 让 IME/剪贴板/DB 失败不可观测；③ 37 处非令牌化硬编码颜色，暗色主题下有回归风险。 |
| **综合评级** | **B+（可交付，技术债集中在"观测性 + 设计令牌收口 + 死代码清理"，无结构性风险）。** |

---

## 2. 审计方法与可复核性

### 2.1 技能执行记录（按任务要求依次加载）

| 技能 | 按其流程执行的部分 | 本机限制与替代 |
|---|---|---|
| `hmos-arkts-deprecated-interface-checker` | 项目分析（读 `build-profile.json5` / `module.json5` / `code-linter.json5`）→ 静态语法检查 → 按 P0/P1/P2 分级出报告 | 技能 Step 0 依赖 `codegenie-mcp`（本机无 MCP server），按任务指令改走**本地静态扫描**；技能自带的 `references/deprecated-api-reference.md` 已逐条比对 |
| `arkts-grammar-standards` | 按 `references/restrictions.md` 的 `arkts-no-*` 规则集逐条 grep（any/unknown、解构、展开、`var`、`Record`、类型查询、`delete/in`、`as` 断言、Sendable 等） | 纯知识型技能，无需工具链，直接可用 |
| `deveco-studio-codelinter` | 按其 Step 1 校验仓库既有 `code-linter.json5`（`@performance/recommended` + `@typescript-eslint/recommended` + 13 条 `@security/*` error 覆盖）→ Step 2 命令 → Step 3 JSON 解读口径 → Step 4 修复建议 | 本机无 `devecocli` / DevEco Studio，`node <DevEco>/plugins/codelinter/run/index.js` 不存在；改跑**技能生态内自带的 `linter-cli`**（见 2.3），并把官方 CLI 写成第 6 节「设备侧命令卡」 |

> 技能 Step 0 要求"先询问用户检查哪些规则集"，本会话为委派子任务、无交互通道，故**沿用仓库已提交的 `code-linter.json5` 规则集**（不新增、不修改该文件）。

### 2.2 静态扫描规则与命中数（可直接复跑）

所有命令在仓库根目录执行；`M=entry/src/main/ets`，`T=entry/src/ohosTest`。

| # | 目标 | grep 正则（`grep -rnE ... --include='*.ets'`） | 命中 | 定性 |
|---|---|---|---|---|
| 1 | router 废弃方法 | `router\.(pushUrl\|replaceUrl\|show\|getParams\|back\|pushNamedRoute\|replaceNamedRoute)` | **1** | 确证（`replaceUrl`） |
| 2 | AlertDialog 旧用法 | `AlertDialog` | **0** | 已清零 |
| 3 | matchMediaSync | `matchMediaSync\|matchMedia` | **0** | 已清零 |
| 4 | wrapContent | `wrapContent` | **0** | 已清零 |
| 5 | TextPicker | `TextPicker` | **0** | 已清零 |
| 6 | 全局 px2vp/vp2px | `px2vp\|vp2px` | **5 行**（2 行代码 + 3 行注释） | 确证 1（`SafeArea:25`） |
| 7 | any / unknown | `:\s*(any\|unknown)\b\|<any>\|as any` | **0** | 无违规 |
| 8 | 对象字面量展开 | `\{\s*\.\.\.` | **1（注释内）** | 无违规 |
| 9 | 解构声明 | `^\s*(const\|let)\s*[\{\[]` | **0** | 无违规 |
| 10 | `var` | `^\s*var\s` | **0** | 无违规 |
| 11 | `Record<` | `Record<` | **0** | 无违规 |
| 12 | 动态执行 | `\beval\(\|\bwith\s*\(` | **0** | 无违规 |
| 13 | 硬编码颜色 | `'#[0-9A-Fa-f]{3,8}'` | **154 处 / 10 文件** | 117 在 DesignTokens（合法源头），**37 在源头之外** |
| 14 | TODO / FIXME / XXX / HACK | `TODO\|FIXME\|XXX\|HACK` | **0** | 无占位 |
| 15 | 空 catch 块 | 自研 Python 括号配对扫描（见 2.4） | **3 空 + 8 静默 + 28 仅日志** | 确证 |
| 16 | 空 promise catch | `\.catch\(\(\s*\w*\s*\)\s*=>\s*\{\s*\}\s*\)` | **9** | 确证 |
| 17 | 非空断言 | `\w!\.` | **3**（`this.store!`） | 确证 |
| 18 | 未使用 import | 自研脚本：解析 import 名后在全文件正文匹配 | **5** | 确证 |
| 19 | 死导出符号 | 自研脚本：导出名 × 全仓（排除本文件）× 本文件出现次数 | **22**（15 死导出 + 1 死组件 + 6 过度导出） | 确证 |
| 20 | 空 `Row() { }` 占位 | `Row\(\) \{ \}` | **5** | 确证（低） |

### 2.3 本地 linter-cli 实跑（技能生态自带工具，**非**官方 CodeLinter）

本机确有可运行的轻量 ArkTS 检查器：
`/home/user/.agents/skills/hmos-arkts-knowledge-retriever/linter-cli/bin/linter-cli.js`（Node v22.23.0，`node_modules/typescript` 为 OpenHarmony 定制版，已就绪）。

```bash
# 逐个文件跑 82 个主源码（单文件模式，缓存复用）
for f in $(find entry/src/main/ets -name '*.ets'); do
  node /home/user/.agents/skills/hmos-arkts-knowledge-retriever/linter-cli/bin/linter-cli.js \
    --input "$PWD/$f" --cache-dir /tmp/linter-cache
done
```

**实跑结果（原始输出 1,496 行，已存 `/tmp/linter-main.log`）**：

| 输出类别 | 条数 | 判读 |
|---|---|---|
| `Cannot find module '@kit.*'` | 452 | **环境噪声**：未提供 `--sdk-path`，SDK 类型声明缺失 |
| `arkts-no-any-unknown`（"Use explicit types…"） | 143 条 / **21 处唯一** | **全部为 SDK 缺类型导致的隐式 any**，已逐行核验：`const canvas = ctx.canvas`（GlyphRenderer:99）、`new drawing.Brush()`（7 处）、`new text.ParagraphBuilder(...)`（2 处）、`(err, data) =>` 未标注回调形参（8 处）。**源码里没有一个显式 `any`/`unknown`**（与第 7 项 grep 互证） |
| `getUIContext API supported since SDK 11, current compatible SDK is 10` | 48 | **环境噪声**：无 SDK 时默认按 API 10 判定；项目实际 6.1.0(23)，`getUIContext()` 完全合法 |
| `getModifierKeyState supported since SDK 12 … 10` | 14 | 同上，噪声（`CanvasTextEditor.ets:1115/1122` 用法正确） |
| `Property 'context' does not exist on type 'EntryAbility'` | 4 | **环境噪声**：`EntryAbility extends UIAbility`，`this.context` 是 `UIAbility` 标准属性（`EntryAbility.ets:11/73/74/81`） |

> **结论**：本地 linter **可用但只能证明"没有明显 ArkTS 语法错误"**，不能替代带 SDK 的 `CompileArkTS`/CodeLinter。**未采信其 any/版本类告警为真实缺陷**，上述噪声一条都没有写进问题清单。官方 CLI 结果须由设备侧产出（第 6 节）。

### 2.4 自研辅助脚本（只读，已核对，脚本未入库）

- `/tmp/audit.py`：去注释后做括号配对，输出 catch 块分类（`EMPTY` / 静默 / 仅日志）与方法长度。
- `/tmp/func2.py`：正则识别方法声明 + 括号配对，输出 ≥70 行方法（已剔除 `if/for/switch` 等关键字误命中）。
- `/tmp/unused.py`：import 名与正文比对；私字段名与全文出现次数比对（后者因"属性以 `this.x` 形式经对象字面量传递"误报率高，**人工复核后只采信 3 条**）。
- `/tmp/dup.py`：跨文件 6 行滑窗重复块检测。

---

## 3. 问题清单

> 严重度定义：**P0 阻塞** = 编译/构建/启动失败；**P1 中** = 功能退化、运行期失败风险、官方已废弃将被移除；**P2 低** = 规范/可维护性/死代码/硬编码。
> 全部为**只给建议、不改代码**。

### 3.1 P0 阻塞项：0

无。

### 3.2 P1 中（6 条 / 22 处）

| ID | 位置 | 规则 | 问题 | 修复建议 |
|---|---|---|---|---|
| Q-01 | `entry/src/main/ets/utils/SafeArea.ets:25` | ArkTS 废弃 API（`'px2vp' has been deprecated.`） | 使用**全局** `px2vp(px)`，官方已标记废弃（API 12+ 推荐 `UIContext.px2vp`） | 由调用方注入 `UIContext`（`AppShell` 内 `this.getUIContext()`），或改为 `densityPixels` 显式换算；保留现有 `try/catch` 的 1:1 退化 |
| Q-02 | `entry/src/main/ets/pages/GuideSwiperPage.ets:61` | ArkTS 废弃 API（`'replaceUrl' has been deprecated.`） | 全仓**唯一**遗留的 `router` 调用；其余导航已统一到 `shell/Navigator.ets` + `Navigation` | 改为 `uiContext.getRouter().replaceUrl(...)`，或直接 `nav.replacePath({ name: Routes.… })` 与全站路由统一 |
| Q-03 | `entry/src/main/ets/editor/flowtext/CanvasTextEditor.ets:521-522`（`:479 setData` 不受影响） | 权限 / 运行期（WARN：`To use this API, you need to apply for the permissions: ohos.permission.READ_PASTEBOARD`） | `board.getData()` 读系统剪贴板需要 `ohos.permission.READ_PASTEBOARD`（user_grant），但 `entry/src/main/module.json5` **整份没有 `requestPermissions` 段**，全仓 grep 该权限 = 0。⇒ 跨应用粘贴**必然失败**，`.catch` 里静默回退到应用内 `appClipboard`，用户会粘贴到过期内容且无提示 | 二选一：① `module.json5` 声明 `ohos.permission.READ_PASTEBOARD` 并在首启 `requestPermissionsFromUser`；② 显式采用"粘贴安全控件"（`PasteButton`）拿临时授权，无需静态权限；同时在 `.catch` 里 toast「跨应用粘贴不可用，已粘贴应用内最近复制」，不要静默 |
| Q-04 | `editor/flowtext/ime/ImeBridge.ets:63,71,77,81,83,84`；`shell/EditorPane.ets:266,433,435` | 工程质量：异常吞噬 | **9 处 `.catch(() => {})`**（IME attach/detach/updateCursor/changeSelection/show/hide、剪贴板写入、格式落库）。失败后既无日志也无 UI 反馈，输入法或持久化异常将无法定位 | 统一改为 `.catch((e: BusinessError) => Logger.warn('[ImeBridge] op failed: ' + e.code + ' ' + e.message))`；`setChapterFormat` 失败需回滚 UI 选中态 |
| Q-05 | `database/BaseDao.ets:76,86`；`editor/flowtext/CanvasTextEditor.ets:529,539,1123`；`editor/flowtext/render/TextLayoutEngine.ets:149`；`utils/ImportService.ets:78`；`utils/SafeArea.ets:26` | 工程质量：catch 只吞不记 | 8 处静默回退（返回 `''`/`0`/`[]`/`false`/原名/原 px），**无任何日志**。DB 列读失败会被当成"空字符串"写回，属于静默数据损坏路径 | `BaseDao.safeGetString/safeGetLong` 至少在 `catch` 内 `Logger.warn('col read failed: ' + col)`；`TextLayoutEngine` 返回空布局应 `diag` 一次；其余保留回退但补一行日志 |
| Q-06 | `shell/WorkspaceDest.ets:23`；`editor/flowtext/CanvasTextEditor.ets:209` | ArkUI API 面：无用参数/属性 | `@Param showBack` 被 `AppShell.ets:377`、`MobileShell.ets:233` 两处传入，但 `WorkspaceDest` 内部**从未读取**；`@Prop placeholder` 声明后**从未渲染**（真正的 placeholder 走 `TextEditorHost.ets:39/140`）。属于"看起来可配置、实际无效"的误导性 API | 删除两个装饰字段及两处传参；若确实需要返回按钮，则在 `WorkspaceDest` 里消费 `showBack` |

### 3.3 P2 低（11 条，可维护性 / 规范）

| ID | 位置 | 规则 | 问题 | 修复建议 |
|---|---|---|---|---|
| Q-07 | 14 个符号 + 1 个死组件文件 | 死代码（全仓零引用，已排除 `export` 被内部使用的情况） | `constants/DesignTokens.ets:117 tokens`、`:122 TypeScale`、`:220 graphNodeColor`、`:242 graphEdgeColor`、`:262 graphEdgeDashed`、`:267 characterTypeName`、`:279 relationshipTypeName`、`:290 worldCategoryName`；`shell/Navigator.ets:61 leaveWorkspaceIfEmpty`、`:68 backToRoot`；`utils/BreakPoint.ets:28 isNarrowTier`、`:33 isMediumTier`、`:38 isWideTier`；`utils/TimeUtil.ets:2 formatDateTime`；**整文件死组件** `shell/MobileSectionTabs.ets`（50 行，无任何 import/引用） | 删除或移入 `archive/`；图/角色命名类 helper 若为后续功能预留，加 `@deprecated` + 归属说明，避免"以为在用" |
| Q-08 | `editor/flowtext/CanvasTextEditor.ets:315-348`(12)、`:206-208`(3)、`editor/TextEditorHost.ets:36-38`(3)、`editor/flowtext/theme/EditorTheme.ets`(6)、`utils/SystemBars.ets:18,22,72`(4)、`store/StoreModels.ets:16,39,66`(3)、`shell/DocListPane.ets:188`、`shell/EditorPane.ets:227`、`shell/InputDialog.ets:79`、`shell/WorkspaceDest.ets:114`（合计 **37 处**） | 设计令牌（硬编码 `#RRGGBB`） | 颜色未走 `DesignTokens`。尤其：遮罩色 `#66000000` 已在 `SystemBars.ets:18` 导出为 `OVERLAY_MASK_COLOR`（且该常量**全仓零引用**），`EditorPane:227`/`InputDialog:79`/`WorkspaceDest:114` 仍各自手写；`CanvasTextEditor` 选择菜单 12 处 `'#FFFFFF'` 在暗色主题下不会随主题变化 | ① 三处遮罩改用 `OVERLAY_MASK_COLOR`；② 菜单前景色改用 `tokensFor(themeId).onBrand` / 新增 `menuOnDark` 令牌；③ `TextEditorHost` / `CanvasTextEditor` 的 `@Prop` 默认值改引用令牌，仅保留"无主题上下文时的兜底"注释 |
| Q-09 | `repository/MaterialRepository.ets:5,7,9`；`shell/MobileShell.ets:20`；`shell/WorkspaceDest.ets:12` | 未使用 import | `IdGenerator`、`CharacterType`、`WorldCategory`、`MobileTabBar`、`WeaverRadii` 导入后零使用 | 直接删除（`@typescript-eslint/no-unused-vars` 会在设备侧 lint 报出） |
| Q-10 | 11 个方法 ≥ 70 行 | 函数过长 | `CanvasTextEditor.handleTouch` **152** / `:build` **137** / `applyKeyCommand` **117** / `registerImeCallbacks` **75**；`MarkdownRenderer.toHtmlBody` **127**；`EditorPane.build` **119**；`AppStores.importBackupText` **101**；`ProjectSidebar.build` **99**；`DatabaseHelper.createTables` **86**；`WorkspaceDest.build` **79**；`EntryAbility.onWindowStageCreate` **77** | 优先拆 `handleTouch`（手势判定/光标落位/选区分支可各成一函数）与 `importBackupText`（解析/ID 重映射/落库三段）；`build` 类超长属 ArkUI 常态，可抽 `@Builder` 子段 |
| Q-11 | `colors(): WeaverColorSet` ×**15** | 重复代码 | `GuideSwiperPage:35,54`、`SettingsDest:12`、`AppShell:164`、`DocListPane:24,98`、`EditorPane:31`、`InputDialog:27`、`MobileSectionTabs:14`、`MobileShell:30`、`MobileTabBar:24`、`PcWindowBar:11`、`ProjectSidebar:18`、`SettingsPanel:7`、`WorkspaceDest:37` 完全相同（`return tokensFor(<themeId>)`） | ArkUI struct 无法共享方法，建议收敛为 `@Computed get colors()`（V2）或在 `DesignTokens` 提供 `colorsOf(app)` 单例缓存；至少把 15 份实现统一成同一表达式 |
| Q-12 | `database/BookDao.ets:37-44`、`ChapterDao.ets`(同上模式)、`CharacterDao.ets:67-73`、`InspirationDao.ets:36-43`、`RelationshipDao.ets:55-59`、`WorldSettingDao.ets:60-74` | 重复代码（DAO 模板） | 6 个 DAO 的 `update`/`delete` 都是同一套 `valueBucket.updated_at = Date.now(); newPredicates(); equalTo('id', …); updateRow`；滑窗检测到 46 个跨文件 6 行重复块，绝大多数落在 `database/` | 上提到 `BaseDao.updateById(table, id, values)` / `deleteById(table, id)`；`ChapterDao` 特有逻辑（排序、trash）再覆写 |
| Q-13 | `database/DatabaseHelper.ets:128,153,169` | 非空断言 | `this.store!.executeSql(...)` / `this.store!.querySql(...)` 三处；`store` 为 `RdbStore \| null`，断言绕过空检查 | 改为 `const s = this.store; if (s === null) { throw new Error('store not ready') } await s.executeSql(...)` |
| Q-14 | `editor/flowtext/ime/ImeBridge.ets:61,122`；`CanvasTextEditor.ets:1558` | 日志规范 | 3 处绕过 `utils/Logger.ets` 直接用 `console.error/warn/info`（`ImeBridge` 两处为 catch 内；`CanvasTextEditor:1558` 为显式诊断通道，注释已说明理由） | `ImeBridge` 两处改走 `Logger`；`CanvasTextEditor` 的 `DIAG_TAG` 保留但注释标明"仅调试期，release 可关" |
| Q-15 | `pages/dest/SettingsDest.ets:34,47`；`shell/SettingsPanel.ets:24,35`；`shell/PcWindowBar.ets:78` | ArkUI 写法 | 用 `Row() { }.layoutWeight(1)` 当弹性占位（5 处） | 改用 `Blank()`（语义化、更少布局节点） |
| Q-16 | `shell/AppShell.ets:375`；`shell/MobileShell.ets:231`；`utils/ExportService.ets:210`；`utils/PreferenceHelper.ets:38,60` | 严格类型（`Object`） | `param: Object`（Navigation 目标页 builder，属官方约定签名，可豁免）、`payload: Object`、`const val: Object = await prefs.get(...)` | 前两处保留并加注释说明是框架签名；`PreferenceHelper` 改 `preferences.ValueType` 显式类型，去掉 `as string` 断言 |
| Q-17 | `entry/src/ohosTest/**`（7 文件 / 281 行） | 测试覆盖 | 主/测行数比 **2.0%**；仅 `FlowText` 回归 17 用例（41 个 `expect`）+ 模板 `Ability.test`(1 用例，空生命周期钩子)；`store/`、`database/`、`repository/`、`utils/` **零测试** | 优先补 3 类纯逻辑测试：`FormatCodec` 编解码往返、`BaseDao.safeGet*` 空列、`MarkdownRenderer` 转义；DAO 可用 `ohosTest` 的 `beforeAll` 建临时库 |

### 3.4 疑似需人工判读（**不作为确证问题计数**）

| ID | 位置 | 现象 | 需要谁判读 |
|---|---|---|---|
| S-01 | `shell/DocListPane.ets:186` `@Builder swipeDelete(item: DocItem)` | ArkTS 惯用红线是"自定义 class 实例作 `@Builder` 首参（按值传递，对象换引用不刷新）"。此处 `DocItem` 是 `@ObservedV2` + `@Trace` 字段（`StoreModels.ets:12-23`），**字段级变更能刷新**，只有当列表项被整体替换成新实例时才可能滞后 | 需真机滑动删除/恢复验证；若已知只在原地改字段，可接受；否则改传 `id: string` 或 `$$` |
| S-02 | `editor/flowtext/theme/EditorTheme.ets:21-36`（6 处 hex） | Canvas 2D 渲染层需要**具体颜色值**（`drawing.Brush.setColor`），未必适合运行时主题字符串 | 设计/架构确认：是否把 Canvas 主题也纳入 DesignTokens（可导出 `EditorColorSet`） |
| S-03 | `store/StoreModels.ets:16,39,66` `'#007DFF'` | 数据模型默认色（文稿封面色/项目色），`DesignTokens.ets` 已有 `DOC_TAB_COLORS[0] = '#007DFF'` | 判是否为"数据默认值"而非"UI 令牌"；若属 UI，改引用常量 |
| S-04 | `editor/flowtext/CanvasTextEditor.ets:319-341` 12 处 `'#FFFFFF'` | 选择菜单在**暗色主题**下是否仍应为白字？当前写死白，深色背景下可能低对比 | 视觉确认（无障碍对比度 ≥ 4.5:1） |
| S-05 | `editor/flowtext/render/TextLayoutEngine.ets:149` `catch { return [] }` | 布局引擎失败返回空数组，调用方会把文档渲染成空白页且无提示 | 产品决策：空白页 + toast，还是上抛由 `CanvasTextEditor` 兜底重试 |
| S-06 | `shell/AppShell.ets:551`、`shell/EditorPane.ets:254` 的 `showToast` | 构建日志对两处报 `Function may throw exceptions.`，当前无 try/catch | 属提示类 WARN，可接受；若要清零须包 `try/catch`（不建议为消 WARN 加噪音） |
| S-07 | 本地 linter 报的 **21 处** `arkts-no-any-unknown` | 已逐行核验为 SDK 缺类型导致的隐式 any（`ctx.canvas`、`drawing.Brush`、`text.ParagraphBuilder`、`(err, data)` 回调），**非源码 `any`** | 已判读完毕，结论：**不计入问题**；仅设备侧带 SDK 的 CodeLinter 结果为准 |

---

## 4. 代码规模统计（bash 实测，非估算）

### 4.1 总量

| 指标 | 数值 | 命令 |
|---|---|---|
| 主代码 `.ets` 文件数 | **82** | `find entry/src/main/ets -name '*.ets' \| wc -l` |
| 主代码总行数 | **13,928** | `find entry/src/main/ets -name '*.ets' -print0 \| xargs -0 cat \| wc -l` |
| 测试 `.ets` 文件数 | **7** | `find entry/src/ohosTest -name '*.ets' \| wc -l` |
| 测试总行数 | **281** | 同上 `cat \| wc -l` |
| 合计 | **89 文件 / 14,209 行** | — |
| 平均文件规模 | **169.9 行/文件** | 13,928 ÷ 82 |
| 测试/主代码行数比 | **2.0%**（281 / 13,928） | — |
| 手写代码行数（剔除生成文件） | **12,333** | 13,928 − 1,595（`UnicodeGraphemeData.ets`，文件头注明 `Generated by tools/generate-grapheme-data.py`） |
| 注释与空行密度（抽样） | 约 32%（`CanvasTextEditor` 2,041 行中约 650 行注释/空行） | 人工抽样 |

### 4.2 各目录占比（主代码，按行数降序）

| 目录 | 文件数 | 行数 | 占比 | 说明 |
|---|---:|---:|---:|---|
| `editor/` | 22 | 6,463 | **46.4%** | FlowText 编辑器（Canvas 渲染/布局/IME/手势） |
| `shell/` | 12 | 2,443 | **17.5%** | 壳层：AppShell / 手机壳 / 分栏 / 对话框 |
| `store/` | 9 | 1,725 | **12.4%** | V2 状态（AppStores/Editor/Project/Material） |
| `utils/` | 14 | 1,221 | **8.8%** | 导入导出/日志/偏好/安全区/断点 |
| `database/` | 8 | 974 | **7.0%** | RDB 封装 + 6 个 DAO |
| `constants/` | 1 | 328 | **2.4%** | `DesignTokens.ets`（117 处颜色定义，单一来源） |
| `repository/` | 4 | 326 | **2.3%** | 仓储聚合层 |
| `pages/` | 3 | 176 | **1.3%** | `@Entry` 仅 2 个（Index / GuideSwiperPage） |
| `model/` | 8 | 145 | **1.0%** | 纯数据类/枚举 |
| `entryability/` | 1 | 127 | **0.9%** | `EntryAbility` 生命周期 |
| **合计** | **82** | **13,928** | **100%** | — |

> 结构判读：`editor/` 单目录占近半壁，其中 `CanvasTextEditor.ets` 一个文件 2,041 行 = 主代码的 14.7%，是唯一的"巨型组件"，也是长函数、硬编码色、空 catch 的集中地。`pages/` 仅 1.3% 说明这是"壳 + 单工作台"架构、而非多页面路由型应用——与 `router` 只剩 1 处相印证。

### 4.3 最大 5 个文件

| # | 文件 | 行数 | 占主代码 | 性质 |
|---|---|---:|---:|---|
| 1 | `editor/flowtext/CanvasTextEditor.ets` | 2,041 | 14.7% | 手写，**需重点拆分** |
| 2 | `editor/flowtext/model/UnicodeGraphemeData.ets` | 1,595 | 11.5% | **生成代码**（Unicode 17.0 字素表），勿改 |
| 3 | `shell/EditorPane.ets` | 572 | 4.1% | 手写 |
| 4 | `shell/AppShell.ets` | 553 | 4.0% | 手写 |
| 5 | `store/AppStores.ets` | 523 | 3.8% | 手写 |

### 4.4 测试构成

| 文件 | 行数 | 用例 | 备注 |
|---|---:|---:|---|
| `ohosTest/ets/test/FlowText.test.ets` | 177 | **17 个 `it` / 41 个 `expect`** | 覆盖字素删除、选区锚点、格式合并、预览提交、原生排版契约等，**有效回归** |
| `ohosTest/ets/test/Ability.test.ets` | 34 | 1 | DevEco 模板（空 `beforeAll/beforeEach/…` + 1 个 `assertContain`） |
| `ohosTest/ets/test/FlowTextFixture.ets` | 11 | — | 测试夹具 |
| `ohosTest/ets/test/List.test.ets` | 7 | — | 套件聚合 |
| `ohosTest/ets/testability/**` + `testrunner/**` | 52 | — | 模板基础设施 |
| **合计** | **281** | **18** | 主/测比例 **2.0%** |

---

## 5. WARN 复核（逐条对齐当前源码）

### 5.1 证据链

| 证据 | 内容 |
|---|---|
| `.hvigor/outputs/build-logs/build.log`（3,179 行，mtime 2026-10-08 22:20:17） | 6 个 hvigor 会话：**`BUILD SUCCESSFUL` × 6、`BUILD FAILED` × 0**；`ArkTS:ERROR` × 0 |
| 3 次完整 HAP 构建（10-06 15:59 / 16:24 / 17:22） | 每次 **37 条** `ArkTS:WARN`（日志累计 111 条），全部 `SUCCESSFUL` 且产出签名 HAP |
| 最近一次 HAP 构建 | **2026-10-06 17:22:05**，`CompileArkTS 21s166ms → PackageHap 107ms → SignHap 212ms` |
| 2026-10-08 三次"成功" | 任务图仅 `PreBuild(UP-TO-DATE) + compileNative(1ms)`，**无 `CompileArkTS`**，故 0 条 WARN —— 属增量空转，不能作为编译证据 |
| 源码时效 | `find entry/src -newermt '2026-10-06 17:22'` → **空**。最后改动为 `WorkspaceDest.ets`/`EntryAbility.ets` 17:17，**早于**最后一次完整编译 ⇒ 日志里的行号与当前行号**一一对应** |

### 5.2 37 条唯一 WARN 的构成与当前位置（全部仍然存在）

| 类别 | 条数 | 文件:行 |
|---|---:|---|
| `Function may throw exceptions. Special handling is required.` | **34** | `database/BaseDao.ets:44,46,49,56,57,59,62`（7）<br>`database/ChapterDao.ets:207,209,213,219,222,225,241,243,249`（9）<br>`database/DatabaseHelper.ets:201`（1）<br>`editor/flowtext/ime/ImeBridge.ets:88,89,90,91,93,94,95,96,97`（9）<br>`entryability/EntryAbility.ets:25`（1）<br>`shell/AppShell.ets:551`（1）<br>`shell/EditorPane.ets:254,529`（2）<br>`utils/ImportService.ets:87,89,100,109`（4） |
| `'px2vp' has been deprecated.` | 1 | `utils/SafeArea.ets:25` |
| `'replaceUrl' has been deprecated.` | 1 | `pages/GuideSwiperPage.ets:61` |
| `To use this API, you need to apply for the permissions: ohos.permission.READ_PASTEBOARD` | 1 | `editor/flowtext/CanvasTextEditor.ets:522` |
| **合计** | **37** | 9 个文件 |

### 5.3 明确结论

1. **当前 WARN 不阻塞构建。** 37 条 WARN 与 `BUILD SUCCESSFUL` 在**同一次构建中并存达 3 次**，并正常完成 `PackageHap` + `SignHap`；`ArkTS:ERROR` 计数为 0。ArkTS 编译器把"废弃 API / 可能抛异常 / 权限提示"归为 `WARN`，不参与失败判定。
2. **历史 WARN 触发点全部仍在。** 37 条逐条按当前源码行号核对，**无一条被修复、也无新增**（源码自 2026-10-06 17:17 未变）。因此"约 38–42 个 WARN"的历史口径可精确收敛为 **37 条唯一 WARN**（日志 111 条 = 37 × 3 次完整构建）。
3. **WARN 的实质风险不在"能否构建"，而在"能否发现故障"**：34 条 may-throw 指向的 RDB/IME/Toast 调用**大多没有 try/catch**（`BaseDao.queryRows`、`ImeBridge.registerListeners`、`ImportService.readText` 等）。它们运行期失败时会以未捕获异常形式炸在业务层，建议按 Q-04/Q-05 补日志与降级，而**不是**为了消 WARN 去无脑包 `try/catch`。
4. **若要复核当前源码的真实编译态**，必须在设备侧跑一次**全量** `devecocli build`（或 `hvigorw clean assembleHap`），因为 2026-10-08 的增量空转无法证明 ArkTS 编译仍然通过——虽然源码未变、缓存有效，结论可信度很高，但严格意义上仍需一次全量。期望结果：`BUILD SUCCESSFUL`，`ArkTS:ERROR 0`，`ArkTS:WARN 37`。

---

## 6. 设备侧命令卡（本机无法执行，交鸿蒙 PC / 用户终端）

> 本机（OpenEuler ARM64）实测：`node v22.23.0` ✅；`hvigorw` / `hvigor` / `devecocli` / `ohpm` / `hdc` **全部不存在** ❌；`/storage/...` 不可达 ❌。以下命令**均未在本机执行**，未安装任何工具链，未伪造任何 lint 输出。

### 6.1 前置检查

```bash
cd /path/to/Weaver
devecocli --version                      # 期望输出 6.x
test -f build-profile.json5 && echo OK    # 项目根判定
cat code-linter.json5                     # 已提交规则集：@performance/recommended + @typescript-eslint/recommended + 13 条 @security error
```

### 6.2 命令 A：`devecocli check lint`（推荐，官方 CLI）

```bash
# A1 基本检查（使用仓库自带 code-linter.json5）
devecocli check lint .

# A2 JSON 输出到文件（审计留档）
devecocli check lint --format json --output-path /tmp/weaver-lint.json .

# A3 显式指定配置 + 只看增量（CI 门禁）
devecocli check lint --config-path ./code-linter.json5 --incremental --format json \
  --output-path /tmp/weaver-lint-inc.json .

# A4 自动修复（仅 QuickFix 支持的规则，执行前先备份/commit）
devecocli check lint --fix .
```

**期望输出**（`--format json`，与技能 Step 3 的 schema 一致）：

```json
[
  {
    "filePath": "/…/entry/src/main/ets/repository/MaterialRepository.ets",
    "messages": [
      { "line": 5, "column": 10, "severity": "warn",
        "message": "'IdGenerator' is defined but never used.",
        "rule": "@typescript-eslint/no-unused-vars" }
    ]
  }
]
```

**失败判据（任一成立即视为不通过）**：

| 判据 | 阈值 | 说明 |
|---|---|---|
| `severity == "error"` 条数 | **必须 = 0** | 与历史 `BUILD SUCCESSFUL` 一致；出现即阻塞 |
| 退出码（加 `-e error,warn` 时） | **0 为通过**；`4`=仅 error；`6`=error+warn；`2`/`3`=warn/suggestion | 见技能 `--exit-on` 三位二进制表 |
| `@security/*` 违规 | **= 0**（仓库把 13 条安全规则设为 `error`） | 加密算法不合规属供应链风险 |
| `@typescript-eslint/no-unused-vars` | 期望命中 **5**（Q-09 的 5 个未用 import） | 多于 5 说明有新引入的死 import |
| `@typescript-eslint/no-explicit-any` | 期望 **0** | 本地无 SDK 跑出的 21 处已判定为噪声；带 SDK 应为 0 |
| `@performance/*` | 记录数量即可，不设硬门 | 历史 WARN 中不含 performance 规则 |

### 6.3 命令 B：DevEco Studio 内置 codelinter（技能原生流程）

```bash
# B1 探测入口（三平台）
#   macOS  : /Applications/DevEco-Studio.app/Contents/plugins/codelinter/run/index.js
#   Win    : %LOCALAPPDATA%\Huawei\DevEco Studio\plugins\codelinter\run\index.js
#            C:\Program Files\Huawei\DevEco Studio\plugins\codelinter\run\index.js
#   Linux  : <DevEco 安装目录>/plugins/codelinter/run/index.js
CODELINTER="/Applications/DevEco-Studio.app/Contents/plugins/codelinter/run/index.js"

# B2 检查 + JSON 落盘
node "$CODELINTER" -c ./code-linter.json5 -f json -o /tmp/weaver-lint2.json /path/to/Weaver

# B3 门禁模式（error+warn 非零退出）
node "$CODELINTER" -c ./code-linter.json5 -f json -o /tmp/weaver-lint-gate.json \
  -e error,warn /path/to/Weaver
echo "exit=$?"
```

**期望输出**：控制台打印按文件分组的 `📁 文件 → 🟡 第N行 规则 消息`；`-o` 指定时控制台静默、结果只落文件。
**失败判据**：`exit != 0`（`-e error,warn` 下 error+warn 任一存在即 `6`）、JSON 中 `"severity":"error"` 存在、或进程非 0 退出且无 JSON 产物（多为配置/Node 版本错误）。

### 6.4 命令 C：全量构建复核（验证 37 条 WARN 与 ERROR:0）

```bash
cd /path/to/Weaver
hvigorw clean --no-daemon
hvigorw assembleHap --mode module -p product=default --no-daemon 2>&1 | tee /tmp/weaver-build.log

# 判据
grep -c "ArkTS:ERROR" /tmp/weaver-build.log               # 期望 0
grep -c "ArkTS:WARN File:" /tmp/weaver-build.log          # 期望 37
grep -c "BUILD SUCCESSFUL" /tmp/weaver-build.log          # 期望 1
```

> 替代：`devecocli build`（默认 `--product default --build-mode debug`）。产物应刷新 `entry/build/default/outputs/default/entry-default-signed.hap` 的 mtime，否则说明仍是缓存空转。

### 6.5 命令 D：本机已实跑的本地 linter（可复现 2.3 节结论）

```bash
for f in $(find entry/src/main/ets -name '*.ets'); do
  node /home/user/.agents/skills/hmos-arkts-knowledge-retriever/linter-cli/bin/linter-cli.js \
    --input "$PWD/$f" --cache-dir /tmp/linter-cache
done > /tmp/linter-main.log 2>&1
grep -o 'arkts-[a-z-]*' /tmp/linter-main.log | sort | uniq -c   # 期望：143 arkts-no-any-unknown（全部 SDK 噪声）
```

> 在有 SDK 的机器上，把 `--input` 换成单文件并补 `--sdk-path "<DevEco>/sdk/default"`，即可消掉 452 条模块解析噪声，再判断是否仍有真实 ArkTS 诊断。

---

## 7. 修复优先级建议（不改代码，仅排序）

1. **P1-①（功能）** 补 `ohos.permission.READ_PASTEBOARD` 或改用 `PasteButton`（Q-03）——这是唯一会让**用户感知功能缺失**的项。
2. **P1-②（观测性）** 9 处 `.catch(() => {})` + 8 处静默 catch 补 `Logger`（Q-04/Q-05）——成本最低、收益最大。
3. **P1-③（技术债）** 2 处废弃 API 迁移（Q-01/Q-02），可直接把 WARN 从 37 降到 35。
4. **P1-④（API 面）** 删 `showBack` / `placeholder` 两个无效装饰字段（Q-06）。
5. **P2（收口）** 死代码（Q-07）→ 未用 import（Q-09）→ 遮罩色复用 `OVERLAY_MASK_COLOR`（Q-08）→ `colors()` 15 份收敛（Q-11）。
6. **不建议为"消 WARN"而批量包 `try/catch`**：34 条 may-throw 中多数应通过"调用点显式处理 + 日志"解决，而非把异常吞掉。

---

### 附：本次审计的边界声明

- **未执行**：任何 hvigor / devecocli / ohpm / hdc 命令；未安装工具链；未修改 `entry/src/**`、`spec/**`、构建配置。
- **未采信**：本地无 SDK 的 linter 输出的 21 处 any、48+14 条版本告警、4 条 `EntryAbility.context` 报错（均已逐行证伪）。
- **未能验证**：真机运行期行为（剪贴板权限实际报错码、暗色主题下 Canvas 配色对比度、`swipeDelete` 刷新时序），需设备侧或人眼判读，已列为 S-01…S-06。
