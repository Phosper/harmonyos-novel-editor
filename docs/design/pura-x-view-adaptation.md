# Pura X View（阔直板）特殊适配清单

> 依据华为《阔直板应用开发》文章整理，对照本工程当前实现。设备特征：440×744vp、16:9.5、
> 四边圆角更大、顶部避让区更高、屏幕高度小于常规直板机。

## 已适配

| # | Pura X View 特征 | 本工程做法 | 代码落点 |
|---|---|---|---|
| 1 | 原生竖屏宽屏（440vp） | 走 `WidthBreakpoint.SM` → 移动外壳单列，宽度交给布局自适应，不写死列宽 | `BreakPoint` / `MobileShell` |
| 2 | 屏幕高度仅 744vp | `DeviceSnapshot.shortScreen = height < 800 && !freeWindow`；设置半模态在短屏用 `SheetSize.MEDIUM`，避免被截断 | `DeviceProfile` / `AppShell.bindSheet` |
| 3 | 四边圆角更大 | 通过 `Display.getRoundedCorner()`（API 23）读取四角最大半径，存入 `cornerRadiusVp` / `ui.cornerRadius`，供贴边控件让位 | `DeviceProfile.readScreenMetrics` |
| 4 | 顶部避让区更高 | 全链路动态读 `TYPE_SYSTEM` 避让高度（`safeTop`），**无任何状态栏高度硬编码** | `SafeArea` / `AppShell.topInset` |
| 5 | 窗口沉浸 | 根背景 `expandSafeArea` 铺到状态栏/导航条，内容另算 padding（防双算）；全屏布局在内容加载后二次下发 | `Index` / `AppShell` / `EntryAbility` |
| 6 | 弹框截断 | 输入弹窗 `constraintSize({ maxHeight: '90%' })`；设置面板短屏降为 MEDIUM 并内部滚动 | `InputDialog` / `AppShell` |
| 7 | 横屏方向 | `orientation: "auto_rotation"`；横屏走 MD 断点两栏 | `module.json5` |
| 7b | 阔直板形态识别 | `wideBar`：min/max 短边 400–520、长边 700–800、比例 < 1.9，**横竖屏都识别** | `DeviceProfile.isWideBar` |
| 7c | 横竖屏紧凑 chrome | 顶栏 40、工具行 44、编辑顶栏 48；左右用 `cornerInset=clamp(圆角,16,28)` 让位大圆角 | `MobileShell` / `EditorPane` / `WorkspaceDest` |
| 8 | 视频自适应沉浸 | 不适用：应用无视频播放 | — |

## 待办 / 需产品确认

| # | 项 | 说明 |
|---|---|---|
| A | 滑动隐藏顶/底栏 | 文章推荐的短屏沉浸手段：滚动时隐藏标题栏与底部页签，最大化可视区。需改 `MobileShell` 的滚动联动，属交互变更，建议产品确认后再做 |
| B | 增强启动页 | 当前已配 `startWindowIcon` + `startWindowBackground`；如需启动图随窗口自适应填充，需补增强启动页（drawable）配置 |
| C | 圆角边距细化 | 圆角值已进快照；目前主要控件都在安全区内，横屏/贴边按钮场景可按 `cornerRadiusVp` 增加 8–12vp 边距 |

## 横屏专项（已做）

| 项 | 做法 |
|---|---|
| 识别 | 用 min/max 判定，旋转后仍识别为阔直板（单测覆盖 440×744 ↔ 744×440） |
| 布局 | 横屏宽 744 → MD 断点 → 两栏；高度 440 → `shortScreen` 仍为真 |
| Chrome | 顶栏 40 / 工具行 44 / 编辑顶栏 48，横竖屏一致 |
| 弹层 | 半模态 MEDIUM + 内部滚动；输入弹窗 90% 高度约束 |
| 圆角 | 左右 `cornerInset` 让位 |

## 验证要点（设备侧）

1. 冷启动：启动页/首屏铺满，无白边或截断；
2. 顶部状态栏与内容不重叠（`safeTop` 随设备变化）；
3. 打开设置半模态：面板完整可见、可滚动到底、不被 744vp 高度截断；
4. 长按/右键菜单与弹窗不被圆角裁切；
5. 旋转到横屏：三栏/单列按断点切换，不出现空白或错位。
