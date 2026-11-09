# P4 分包骨架记录（2026-11）

- 状态：**骨架完成、构建可证；安装态与挂载未验证（无设备）**
- 依据：[ADR-003](architecture/adr-003-runtime-contract.md)；本阶段只做"最小纵向切片"的第一层
- 起点：`55c66da`

## 1. 建了什么

| 模块 | 类型 | 内容 | 作用 |
| --- | --- | --- | --- |
| `feature_contracts` | **HAR**（静态） | [FeatureContracts.ets](feature_contracts/src/main/ets/contracts/FeatureContracts.ets)：`FeatureId`、`SurfaceKind`、`FeatureError`、`FeatureDescriptor`、`OpenIntent`、`SubscriptionLease`、两个纯函数 | 无状态契约；entry 与所有功能包共用同一套类型 |
| `core_runtime` | **HSP**（动态共享） | [CoreRuntime.ets](core_runtime/src/main/ets/host/CoreRuntime.ets)：`HOST_API_VERSION`、`featureCatalog()`、`findFeature()` | 常驻核心；P5 在这里接 `DocumentSession`，不新增第二个单例 |
| `entry` | HAP | 依赖上面两个模块；`AppShell` 启动时读一次 `featureCatalog()` 并记日志 | 证明"入口 → HSP → HAR"链路在编译期与运行期都成立 |

依赖方向（已用守卫锁定）：`entry → core_runtime → feature_contracts`，
`feature_contracts` 不得反向依赖，也不得导出可变共享状态。

## 2. 本地证据

| 证据 | 结果 |
| --- | --- |
| `hvigorw assembleHap` | BUILD SUCCESSFUL，0 ERROR / 105 WARN |
| `hvigorw assembleApp` | BUILD SUCCESSFUL |
| APP 产物内容 | `core_runtime-default.hsp`（约 89 KB）+ `entry-default.hap` + `pack.info` |
| `pack.info` | 列出入参两个模块：`moduleType: entry` 与 `moduleType: shared` |
| 回归 | 367 → **383 项**（新增 `modules-regression` 4 项） |

### 踩到的坑（值得记下来）

第一次 `assembleApp` 出来的 `.app` 里**只有 HAP，没有 HSP** —— 原因是 `build-profile.json5` 的模块条目
少了 `targets.applyToProducts`：模块会被编译，但不会被打进当前产品。补上后 HSP 才出现。

因此 `tools/verify.sh` 现在会**额外做一次 APP 打包**并检查 `.app` 里至少有一个 `.hsp`，
这就是"有没有真的按包发出去"的门槛，而不是只看 HAP 构建成功。

## 3. 明确还没做（P4 剩余）

| 项 | 为什么现在不做 |
| --- | --- |
| 一个真实按需 HSP 页面 + 系统路由（`router_map.json`） | 需要设备验证"按名跳转"与"未安装时的降级"；本机只能证明能编译 |
| 正文旁栏（InspectorSurface） | 需要先有"正文不销毁、IME 不抢焦点"的真机验证 |
| 安装/下载状态与合并并发请求 | 依赖 `moduleInstallManager`，必须真机 + 商店侧配置 |
| 功能目录 UI | 数据已就绪（`featureCatalog()`），等路由与外框一起做，避免先画一个点不动的列表 |

## 4. 下一步（设备可用后按顺序）

1. 装 APP（`hdc install -r build/outputs/default/Weaver-default-signed.app`），确认启动正常、日志里有
   `Feature catalog entries=4`；
2. 加一个 `structure_feature` HSP 占位页 + `router_map.json`，验证整页路由；
3. 加 `InspectorSurface`，验证旁栏打开时正文会话不重建；
4. 再谈"未安装 → 下载 → 安装 → 打开"的真实状态机（MT03–MT09）。

设备侧验收用例见交接稿 MT01–MT12、MT19；本文件不重复。
