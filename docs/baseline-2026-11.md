# 本地基线记录（2026-11）

- 提交：`c1780dd`，标签 `v0.9-local`（父提交 `05d7ce2`）
- 含义：这是**本地工作区**的基线，包含 2026-10-25 交互轮次；交接稿审核的是 `05d7ce2`，两者行号不同，定位一律用函数名。
- 本文件只记录**本机能验证**的部分；设备项在文末列为未测。

## 1. 环境

| 项 | 值 |
| --- | --- |
| 工具链 | `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0`（Command Line Tools） |
| SDK | `26.0.0.105`（`sdk/default/sdk-pkg.json`，apiVersion 26） |
| hvigor | `7.26.11` |
| Node | `v24.18.1` |
| Java | 未安装（本次构建不需要） |
| 设备 | 无（`hdc list targets` 为 `[Empty]`） |

一条命令复跑（构建 + 10 组回归）：

```bash
./tools/verify.sh                 # 全部
./tools/verify.sh --skip-build    # 只跑回归
./tools/verify.sh --tests-only    # 只构建测试包
```

## 2. 构建结果

| 项 | 结果 |
| --- | --- |
| 主包 `assembleHap`（clean 后） | `BUILD SUCCESSFUL`，**0 ERROR / 114 WARN** |
| 测试包 `entry@ohosTest` | `BUILD SUCCESSFUL` |
| 产物 | `entry/build/default/outputs/default/entry-default-signed.hap`、`.../ohosTest/entry-ohosTest-signed.hap` |

> `verify.sh` 判定 `errors=0` 才算通过；增量构建时 `warnings` 会是 0（未重新编译），脚本会提示用 `hvigorw clean` 复跑取准确值。

## 3. 告警分类（114 条）

| 条数 | 告警 | 处理建议 | 归属 |
| ---: | --- | --- | --- |
| 46 | `Function may throw exceptions. Special handling is required.` | 逐处补 `try/catch` 或确认已在调用方兜住 | P2，随触碰文件改 |
| 27 | `'px2vp' has been deprecated` | 主要来自 `thirdparty/ezcustomtransition`（24 条）；改 `UIContext` 换算或封装 | P2/P4 |
| 17 | `'animateTo' has been deprecated` | 改用 `this.getUIContext().animateTo` | P2 |
| **9** | `The '@Monitor' decorator needs to monitor the state variables that exist` | **D-01，功能可能失效，见 §3.1** | **P1** |
| 6 | `'vp2px' has been deprecated` | 同 `px2vp` | P2 |
| 4 | `'fontSize' has been deprecated` | 改用 `fontSize` 资源/新签名 | P2 |
| 1 | `READ_PASTEBOARD` 权限缺失 | D-11，声明权限 | P1 |
| 1 | `This API is unavailable to phone, tablet, 2in1` | `SystemBars`：已按 `isPcPlatform()` 跳过，属预期 | 不改 |
| 1 | `This API is unavailable to 2in1` | 同上 | 不改 |
| 1 + 1 | `showToast` / `showDialog` 已废弃 | 改 `getUIContext().getPromptAction()` | P2 |

### 3.1 九处 `@Monitor`（D-01）

| 文件:行 | 监听路径 | 本该做的事 |
| --- | --- | --- |
| `shell/EditorPane.ets:71` | `app.ui.findRequestTick` | 顶栏「查找」打开查找面板 |
| `shell/EditorPane.ets:80` | `app.editor.historyVersion` | 撤销/重做按钮态 |
| `shell/EditorPane.ets:87` | `app.editor.contentRev` | 撤销/重做后刷新中栏摘要 |
| `shell/EditorTools.ets:56` | `app.ui.selectionTick` | 工具组闲置淡出复位 |
| `shell/CanvasPane.ets:1212` | `params.boardId` | 切板（当前由 `CanvasDest` 直接调 `selectBoard`，冗余） |
| `shell/CanvasPane.ets:1220` | `app.ui.themeId` | 切主题重绘点阵背景 |
| `shell/AppShell.ets:79` | `app.editor.historyVersion` | 顶栏撤销/重做禁用态（`appBar()` 为死代码） |
| `shell/AppShell.ets:121` | `app.ui.immersiveEditing` | 退出沉浸后补回 `WORKSPACE` 路由 |
| `shell/DesktopTitleBar.ets:80` | `app.ui.themeId` | 原生三键配色（组件已不在主壳渲染） |

正确写法在工程内已有先例：`shell/AppShell.ets:77` 的 `@Local dialogWatch: UiStore = app.ui` + `@Monitor('dialogWatch.dialog')`。

## 4. 回归计数（367 项）

| 脚本 | 项数 |
| --- | ---: |
| `arkts-guard.cjs` | 19 |
| `canvas-regression.cjs` | 13 |
| `data-regression.cjs` | 49 |
| `device-profile-regression.cjs` | 27 |
| `draft-regression.cjs` | 14 |
| `flowtext-regression.cjs` | 141 |
| `import-regression.cjs` | 5 |
| `schema-regression.cjs` | 5 |
| `shell-regression.cjs` | 62 |
| `window-regression.cjs` | 32 |
| **合计** | **367** |

`arkts-guard` 扫描 58 个文件、293 条相对导入，另有 2 条既有 console 警告（不影响退出码）。

## 5. 未测项（不冒充通过）

1. 真机中文输入法（组字、候选、方向键让位）。
2. 安装 / 覆盖安装 / 按需模块下载与卸载。
3. 平板与 2in1 的窗口三键避让、自由窗口切换。
4. 跨应用粘贴（`READ_PASTEBOARD` 未声明前只能走应用内兜底）。
5. 5 万字长文的输入延迟与帧率。
6. Hypium 28 项（`Ability 3 + FlowText 22 + WindowChrome 3`）：已能编译进测试包，未执行。
7. 三份手工清单：`docs/design/canvas-e2e-checklist.md`、`docs/refactor/multidevice-self-test.md`、`docs/flowtext-testing.md`。

## 6. 本次基线同时完成的工程卫生

- `core.fileMode=false`：此前 243 个"已修改"里 142 个只是权限位从 755 变 644，现已不再出现在 diff 中。
- 2026-10-25 交互轮次已提交，工作区干净。
- 新增 `docs/architecture/feature-ownership.md`（P0 功能归属表）。
