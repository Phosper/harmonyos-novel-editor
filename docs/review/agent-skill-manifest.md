# Agent 评审技能依赖清单

> 用途：专家用 Agent（DSH / 鸿蒙开发模式）评审本项目时，按需加载哪些技能、从哪里下载。
> 校验时间：2026-10-25。链接与 commit 均为当时 `git ls-remote`/HTTP 实测；仓库可能更新，建议锁定 commit。
> 未找到公开地址的技能会明确标注，**不提供猜测链接**。

## 1. 安装约定

Agent 技能目录：`~/.agents/skills/<skill-name>/SKILL.md`。

```bash
mkdir -p ~/.agents/skills

# 方式 A：git clone（推荐，便于锁 commit）
git clone --depth 1 https://atomgit.com/openharmony-skills/<name>.git ~/.agents/skills/<name>

# 方式 B：zip
curl -L -o /tmp/<name>.zip \
  https://atomgit.com/openharmony-skills/<name>/archive/refs/heads/main.zip
unzip -q /tmp/<name>.zip -d /tmp/skill-dl
mv /tmp/skill-dl/<name>-main ~/.agents/skills/<name>
```

总仓（包含多设备、ArkTS/ArkUI、测试等大部分技能）：

```bash
git clone --depth 1 https://gitcode.com/atomicservice/harmonyos-agent-skills.git
# 例：把 ArkUI 开发技能拷进技能目录
cp -R harmonyos-agent-skills/04-development/01-application-framework/ArkUI/hmos-arkui-develop-skill \
  ~/.agents/skills/
```

组织页（可浏览其它技能）：<https://atomgit.com/openharmony-skills>

## 2. 必装（评审/构建/崩溃诊断闭环）

| 技能 | 评审用途 | 下载地址 | 实测 commit |
|---|---|---|---|
| `hmos-arkui-develop-skill` | ArkTS/ArkUI 写法、禁用语法、V2 状态、常见坑 | <https://atomgit.com/openharmony-skills/hmos-arkui-develop-skill> | `f153efde` |
| `hmos-arkts-syntax-checker` | 编译失败时定位/修复 ArkTS 语法 | <https://atomgit.com/openharmony-skills/hmos-arkts-syntax-checker> | `961649a2` |
| `hmos-arkui-knowledge-retriever` | ArkUI 组件/属性/版本检索 | <https://atomgit.com/openharmony-skills/hmos-arkui-knowledge-retriever> | `2b401511` |
| `hmos-arkts-knowledge-retriever` | ArkTS 语言/API/错误码检索 | <https://atomgit.com/openharmony-skills/hmos-arkts-knowledge-retriever> | `36f58160` |
| `hmos-jscrash-analysis` | JS Crash（本项目曾出现 150002 焦点崩溃） | <https://atomgit.com/openharmony-skills/hmos-jscrash-analysis> | `148df0ca` |
| `hmos-appfreeze-analysis` | 卡死/ANR/主线程阻塞 | <https://atomgit.com/openharmony-skills/hmos-appfreeze-analysis> | `9eed5dc6` |
| `hmos-build-verify` | hvigor/hdc 构建、安装、启动验证 | **未找到公开仓库**（随 DSH 鸿蒙开发模式内置） | — |
| `hmos-one-sdk-skill` | `@kit.*` API 签名/错误码/权限 | **未找到公开仓库**（随模式内置；可用官方文档替代） | — |
| `hmos-mode-entry` | 鸿蒙任务分诊与技能路由 | **未找到公开仓库**（随模式内置） | — |

## 3. 按评审维度选用

### 多设备 / 窗口

| 技能 | 用途 | 地址 | commit |
|---|---|---|---|
| `hmos-multidevice-screen-window-size` | 断点、分栏、窗口尺寸 | <https://atomgit.com/openharmony-skills/hmos-multidevice-screen-window-size> | `752773a4` |
| `hmos-multidevice-avoid-areas` | 安全区/状态栏/键盘遮挡 | <https://atomgit.com/openharmony-skills/hmos-multidevice-avoid-areas> | `d7143c85` |
| `hmos-multidevice-interaction-methods` | 触摸/鼠标/键盘/右键 | <https://atomgit.com/openharmony-skills/hmos-multidevice-interaction-methods> | `e86b93b1` |
| `hmos-multidevice-fold-state` | 折叠态/悬停态 | <https://atomgit.com/openharmony-skills/hmos-multidevice-fold-state> | `4c9690bc` |

### 交互 / 架构 / 动画

| 技能 | 用途 | 地址 | commit |
|---|---|---|---|
| `hmos-arkui-longtake-transition` | 一镜到底、geometryTransition、自定义转场 | <https://atomgit.com/openharmony-skills/hmos-arkui-longtake-transition> | `6c4798b9` |
| `hmos-arkui-statemgt-migration` | V1/V2 状态管理与混用 | <https://atomgit.com/openharmony-skills/hmos-arkui-statemgt-migration> | `54976c60` |
| `hmos-arkui-mvvm-pattern` | 分层/状态归属评审 | <https://atomgit.com/openharmony-skills/hmos-arkui-mvvm-pattern> | `a1fbb230` |
| `hmos-arkts-deprecated-interface-checker` | 废弃 API 清理 | <https://atomgit.com/openharmony-skills/hmos-arkts-deprecated-interface-checker> | `e56f52e9` |
| `hmos-arkui-accessibility-skill` | 无障碍标签/走焦 | **未找到公开仓库**（随模式内置） | — |
| `hmos-arkui-navigation-transition` | Navigation 转场（若评审路由改造） | **未找到公开仓库**（随模式内置） | — |
| `hmos-arkui-scenario-development` | ArkUI 场景化开发/排障 | **未找到公开仓库**（随模式内置） | — |

### 内存 / 测试 / 工具链

| 技能 | 用途 | 地址 | commit |
|---|---|---|---|
| `hmos-memleak-analysis` | 静态内存泄漏审查 | <https://atomgit.com/openharmony-skills/hmos-memleak-analysis> | `bdc80312` |
| `hmos-jsleak-analysis` | rawheap/heapsnapshot 泄漏 | <https://atomgit.com/openharmony-skills/hmos-jsleak-analysis> | `23883c6c` |
| `hmos-instrument-test` | Instrument Test | <https://atomgit.com/openharmony-skills/hmos-instrument-test> | `16311970` |
| `hmos-local-test` | Local Test | <https://atomgit.com/openharmony-skills/hmos-local-test> | `8904ee8e` |
| `deveco-studio-hvigor` | hvigor 构建命令 | <https://atomgit.com/openharmony-skills/deveco-studio-hvigor> | `1af80109` |
| `deveco-studio-hilog` | hilog 日志分析 | <https://atomgit.com/openharmony-skills/deveco-studio-hilog> | `63774ae4` |
| `deveco-studio-verify` | 设备安装/UI 验证 | <https://atomgit.com/openharmony-skills/deveco-studio-verify> | `b28f223d` |
| `deveco-studio-codelinter` | CodeLinter 静态检查 | <https://atomgit.com/openharmony-skills/deveco-studio-codelinter> | `5fac6ff9` |
| `hmos-release-gate` | 提审前 P0 检查（可选） | **未找到公开仓库**（随模式内置） | — |

## 4. 建议的最小评审组合

1. **只做代码/架构评审（不构建）**
   `hmos-arkui-develop-skill` + `hmos-arkts-knowledge-retriever` + `hmos-arkui-mvvm-pattern` + `hmos-arkts-deprecated-interface-checker`
2. **要跑构建/真机**
   上述 + `hmos-build-verify`（或 `deveco-studio-hvigor`/`deveco-studio-verify`/`deveco-studio-hilog`）
3. **要审交互/多设备**
   上述 + `hmos-multidevice-*` 四件套 + `hmos-arkui-longtake-transition`
4. **出崩溃/卡死问题**
   上述 + `hmos-jscrash-analysis` / `hmos-appfreeze-analysis`

## 5. 官方文档（技能覆盖不到时）

- HarmonyOS 开发者文档：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/>
- ArkTS 入门：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started>
- hvigor 命令行构建：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app>
- hdc：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hdc>
- hilog：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hilog>

## 6. 说明

- 标注“未找到公开仓库”的技能是本 DSH「鸿蒙开发模式」内置能力，**不要从上面的 AtomGit 链接猜测安装**。
- 各仓库 license/版本策略不同，商用前请自行确认；本清单只提供评审期安装指引。
- 若专家使用别的 Agent 运行时，技能格式（`SKILL.md` + references）可能需要转换，请以目标运行时文档为准。
