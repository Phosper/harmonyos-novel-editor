# 编辑器「文字漂移 / 多选异常」修复报告

> **日期**：2026-10-18
> **工程**：`SDK26Target/Weaver`（API 26，单 entry，FlowText 自绘编辑器）
> **范围**：`entry/src/main/ets/editor/flowtext/**` 的坐标/选区/滚动/预上屏链路 + 本地与原生回归；**未改数据库、宿主 props、外壳 V2 状态**。
> **验证**：本机本地回归 **130 项全过**（FlowText 60 + 数据 28 + 外壳 20 + 窗口 17 + 导入 5）；设备侧构建/Hypium 由用户在鸿蒙主机执行（命令见 §4）。

---

## 1. 问题与根因

### 1.1 文字漂移（横向/纵向、输入与布局变化）

| # | 复现路径 | 根因（修复前） | 证据 |
|---|---|---|---|
| D1 | 一行含多个 run（中英回退字体、加粗/斜体/标题分段）→ 后续文字压到行首或重叠；点击后半段定位到前半段；高亮与字形错位 | `TextLayoutEngine.buildLayoutLine` 把每个 run 的 `runOffsetX` 固定为 `0`，又把 `run.getPositions()` 直接当行内绝对 x。OH 的 `Run.getPositions` 在整段塑形时含段落/行绝对偏移，在 `createLine` 裁剪行时可能被 rebase；两种基准混用时必错位 | 修复前 `runOffsetX = 0`；OH `RunBaseImpl::getPositions`/`Run::paint`/`Run.cpp` |
| D2 | 长文中部改字号/行距/主题 → 页面跳回顶部 | `onThemeChanged`：`cache=null → ensureEngine（新 cache height=0）→ clampScroll`；`onAreaChange` 同样先 clamp。空 cache 的 `contentHeight()=0` 把 `scrollY` 夹到 0 | 旧 `onThemeChanged`/`onAreaChange` 顺序 |
| D3 | 拖宽/缩窄窗口、旋转、跨屏 → 内容整体跳动/回到顶部 | 引擎重建只比较 `viewWidthVp`，忽略密度 `pxPerVp`、字号/行高/行距；密度变化后排版 px 与画布 vp 换算不一致；且重建后未保留阅读锚点 | 旧 `ensureEngine` 的 `engineWidth` |
| D4 | 5 万字滚到接近底部、底部连续换行 → 视口回弹 | `maxScrollVp/clampScroll` 用 `contentHeight()` 的"平均行高 × 剩余字数"估算；惰性排版推进后估算变化，上限变化把 scrollY 夹回 | 旧 `contentHeight/maxScrollVp` |
| D5 | 点击远处后立即输入/拖选/双击 → 光标先到新位置又被拉回旧目标；改字号/重建引擎后光标冻结不闪 | `afterEdit`/选区开始不取消 `caretAnimator`；`ensureEngine` 直接 `stop()` 不触发 onFinish，`caretAnimating` 永远为 true，`relayout` 跳过光标重算、闪烁被守卫 | 旧 `animateCaretMove/ensureEngine` |
| D6 | 中文拼音组字时预览文字与正文同色、无法区分；若启用旧 `drawPreview` 还会整体下移 4-6vp | `drawNow` 把 `preview` 位置传了 `null`，`previewCache` 的预览文字按正文色绘制；`drawPreview` 成为死代码，且其基线用 `caret.y + lineHeight*0.8` 与真实行基线不一致 | 旧 `drawNow`（preview=null）+ `drawPreview` |
| D7 | 打字机模式每敲一个字整屏跳半行 | `ensureCaretVisible(CENTER)` 每键严格把当前行居中，scrollY 瞬时改；无中间带/动画 | 旧 `ensureCaretVisible` |

### 1.2 多选异常

| # | 复现路径 | 根因（修复前） | 证据 |
|---|---|---|---|
| M1 | 拖选/反向拖选/手柄拖动 → 高亮在动，光标竖条停在起点 | `emitSelection` 只更新 `doc` 的 selection/caret，未更新绘制用的 `this.caret` | 旧 `emitSelection` |
| M2 | 长按选中一个词后不松手继续拖 → 选区从按下点重新开始，词选区丢失 | Move 超过阈值时无条件 `selMgr.beginDrag(pressOffset)`；没有"词选区"状态 | 旧 `handleTouch` Move |
| M3 | 双击后旧光标动画继续，选区与光标互相打架 | 双击/三击/长按前未 `cancelCaretAnimation` | 旧 `selectWordAt/selectParagraphAt` |
| M4 | 手柄越过对端 → 选区方向错乱/手柄身份交换 | `updateHandleDrag` 在越界时交换 `handleDragging` 并重写 anchor/head；选区同时存 start/end 与 anchor/head 两份真相 | 旧 `SelectionManager` |
| M5 | 软换行边界 → 高亮结束在上一行行尾、光标画在下一行行首 | `caretPositionFor` 在 `offset===line.endIndex===next.startIndex` 时固定选下一行；高亮对上一行取 `line.width`；缺少 upstream/downstream affinity | 旧 `caretPositionFor` |
| M6 | Ctrl+A / 浮层"全选" → 全文高亮但光标不动、工具栏选区态不更新 | `SELECT_ALL` 只 setSelection + drawNow + reportSelection；未更新绘制 caret/未走 `emitSelection` | 旧 `applyKeyCommand` |
| M7 | 拖选过程中菜单跟着手指逐帧移动；滚动后菜单不更新 | Move 每帧 `showSelectionMenu()`；fling 不隐藏；菜单不随滚动重算 | 旧 `handleTouch` |
| M8 | 触摸被系统取消、鼠标拖出组件后释放 → 手势卡住/残留选区 | 未处理 `TouchType.Cancel`；`mouseSelecting` 只在组件内 Release 复位；双击只看时间不看位移 | 旧 `handleTouch/onMouse` |
| M9 | 空行/标题行选区：空行无高亮、标题行高亮与光标高度不一致 | `drawSelection` 跳过 `startIndex===endIndex`；高亮用 `line.yOffset..+height`，光标用 `baseline-ascent + max(fontSize,...)` 两套几何 | 旧 `drawSelection/caretPositionFor` |

---

## 2. 代码修改说明（文件 → 关键点）

### 2.1 `render/TextLayoutEngine.ets`
- 新增 `offsetXVp(line, scalarIndex)`（`TextLayoutEngine.ets:326`）：`line.getOffsetForStringIndex` → px 转 vp，异常回 0。
- `buildLayoutLine`（`:384`）：`runOffsetX = offsetXVp(line, range.start)`；字形 x 改为 `positions[g].x - positions[0].x`（纯 run 内位移）。无论原生 positions 是"行内绝对/段落绝对/run 局部"，绘制结果都是 **行原点 + run 原点 + 字形位移**，消除多 run 叠在行首与重复偏移。

### 2.2 `interaction/HitTester.ets`
- 新增 `lineBox(line)`（`:111`）：`top = baseline - ascent`、`height = ascent + descent`（ascent 取绝对值；leading 恒 0），光标/高亮/手柄统一。
- `caretPositionFor(..., affinity)`（`:129`）：软换行边界 DOWNSTREAM 取上一行行尾、UPSTREAM 取下一行行首；y/height 用 `lineBox`。
- `hitTestRaw` 兜底与 `offsetToX`：多 run 行用 `runOffsetX + run.positions[g]`，返回值做 `Number.isFinite` 兜底。

### 2.3 `interaction/SelectionManager.ets`
- 单一事实源改为 **anchor/head**（`:43`），start/end 由 `min/max` 派生；`headAffinity` 由方向推导。
- `updateHandleDrag`（`:116`）：handle 1 只改 anchor、handle 2 只改 head，越界不交换身份（对齐 OH `TextSelectController`）。
- 新增 `startOffset/endOffset` 派生 getter；`selection` 缓存对象每次读取重算。

### 2.4 `render/GlyphRenderer.ets`
- `drawText(..., preview)`（`:143`）：删除死代码 `drawPreview`；`drawNow` 现在把 preview 真正传入，预上屏与正文共用同一 run 原点/基线，按 `[start, start + text.length)` 分段用 `previewBrush` 着色，**只画一遍**。
- `drawSelection`（`:333`）：使用 `lineBox`；相邻已选行顶边接上一行底边（无缝）；空行补 `max(8, fontSize*0.5)` 宽；零宽矩形跳过。
- `drawCaret`（`:412`）使用统一光标盒；删除 `legacyOffsetToX` 与预上屏浮层缓存。
- `runHasPreview`（`:220`）只对与预览区间相交的 run 走慢路径。

### 2.5 `CanvasTextEditor.ets`
- 引擎重建键 `engineSignature()`（`ensureEngine` `:1432`）：宽度 + `pxPerVp` + 字号/行高/行距 + 内边距；重建前停光标/滚动动画，丢弃旧 `previewCache`。
- `refreshDensity()`（`:1605`）：`vp2px(1)` 变化即刷新并强制重建（跨屏/系统缩放）。
- `captureViewAnchor()/relayoutPreservingAnchor()`（`:1552`）：以"光标在视口中的屏幕 y"恢复阅读位置；`onAreaChange`/`onThemeChanged` 不再先 `clampScroll`。
- `ensureLayoutThroughY()`（`:1515`）：滚动/光标揭示前先把排版扩展到目标 y；`clampScroll`/`ensureCaretVisible` 只用 `cache.height` 精确值，删除估算路径（`contentHeight` 已移除）。
- `ensureCaretVisible()`（`:2362`）：普通模式只越界才滚 + 边距；打字机改为 `[0.35H,0.65H]` 中间带，离开才居中；`scrollToAnimated()`（`:2414`）160ms ease-out。
- `stopCaretAnimation()`：显式复位 `caretAnimating`；`afterEdit`/选区开始/重建引擎/重排前调用。
- `syncSelectionToCaret()`（`:1869`）：选区变化后同步 doc selection、绘制 caret= head、affinity。
- `emitSelection(force)`（`:1851`）/`reportSelection(force)`：`(文本长度,start,end)` 去重 + 32ms 节流；`reportCursor` 按 left/top 去重。
- `handleTouch()`（`:1967`）重写：Down 固定 `pressOffset`；长按词选区继续拖 = 词 ∪ 手指区间；手柄身份固定；拖选不逐帧弹菜单；Up 只弹一次；新增 `TouchType.Cancel` 全量复位；`autoScrollForHandleDrag` 先滚再命中。
- `onMouse`/`onHover`：鼠标拖选复用同一 anchor/head，caret 跟随 head；拖出组件用 `onHover(false)` 收口。
- `selectAllText()`（`:610`）：Ctrl+A/浮层全选统一收口（caret=end、选区回调、IME、绘制）。
- 预上屏：组字期间 `relayout` 不再用主 cache 覆盖 preview lines；提交时 `oldLines` 为预览行，差分不产生入场动画。
- 载入/回灌：`loadDocument` 新增 `preserveView`；撤销/重做（`TextEditorHost.onContentRevChanged`）传 true 保留滚动位置，仅当 caret 离开视口才滚；切换文稿仍回文首。首帧/载入的光标揭示用 `instantScroll` 直接落位，不做可见滚动动画。

### 2.6 `editor/TextEditorHost.ets`
- `onContentRevChanged` 回灌时调用 `setDocument(text, runs, caret, true)`（保留滚动位置）；`reload()` 换文稿仍用默认 false。

### 2.7 测试与文档
- `tools/flowtext-regression.cjs`：EditorProbe 增加新方法；新增 8 项检查（多 run 原点、anchor/head 越界、affinity、拖选 caret=head、Ctrl+A、空 cache 不归零、预上屏只画一次、撤销/重做保留滚动）。**60 项通过**。
- `entry/src/ohosTest/ets/test/FlowText.test.ets`：新增 4 个原生用例（多 run 行原点、软换行 affinity、caret/lineBox 一致、手柄越界身份固定）。
- `docs/flowtext-testing.md`：新增本轮修复说明、12 项手工验收清单与残余风险。

---

## 3. OpenHarmony 参考点与适配

| 参考 | 依据 | 本项目适配 |
|---|---|---|
| Run 坐标原点与绘制偏移 | `third_party_skia` `RunBaseImpl::getPositions()/paint()`、`Run.cpp`（`positions` 含/不含 `fOffset` 取决于塑形与切行）、`js_run.cpp` 只透传；`Run` 无 offset 访问器 | 不依赖 positions 基准：run 原点用 `line.getOffsetForStringIndex(run.start)`，字形用 `positions[i].x - positions[0].x`；LTR 下对"行内绝对/段落绝对/run 局部"三种情况一致 |
| 选区 anchor/head、手柄身份固定 | ace_engine `TextSelectController`（first/second handle，`GetStartIndex/GetEndIndex` min/max，越界不交换） | `SelectionManager` 以 anchor/head 为唯一事实源；手柄 1=anchor、2=head，越界由 min/max 归一 |
| 拖选时 caret 跟随 head | `rich_editor_pattern.cpp` `UpdateSelector(base,position)+SetCaretPosition(position)` | `syncSelectionToCaret()`；高亮用 start/end，caret 用 head + affinity |
| 长按后拖动扩展词选区，连击 300ms+15vp | `text_base.cpp` TextGestureSelector；`multiple_click_recognizer.h` | `wordSelStart/End` + `extendWordSelection`；双击/三击加位移阈值，拖拽/取消重置 streak |
| 选区矩形逐行合并、空行补宽、caret 用行 metrics、行尾 affinity | `text_base.cpp` rect 合并/`SELECTED_BLANK_LINE_WIDTH`；`text_select_controller.cpp` caret metrics/affinity | `HitTester.lineBox` + `CaretAffinity` + `drawSelection` 行合并/空行补宽 |
| 滚动只越界才滚、内容尺寸以已排版为真值 | `rich_editor_scroll_controller.cpp`；`rich_editor_pattern.cpp` textRect | `ensureLayoutThroughY` + `cache.height` 精确上限；删除估算；CENTER 中间带 + 160ms 动画 |
| 预上屏进入真实排版、不做浮层 | `text_field_pattern.cpp` SetPreviewText/FinishTextPreview；`text_input_client.h` | 保留 `previewCache` 真排版；删除叠加层，改为同基线分段着色；提交不触发入场动画 |
| IME CursorInfo 窗口物理 px + 元组去重 | `capi-inputmethod-cursor-info-capi-h`；`text_field_pattern.cpp` `UpdateCaretInfoStandard` | `reportCursor` 元组去重；`reportSelection` 32ms 节流 + Up 强制 |

> 未照搬：OH 没有"打字机居中"和"惰性排版"的现成实现（`ParagraphManager` 全量），这两项保持自研；CENTER 由"每键严格居中"改为"中间带 + 动画"，避免滚动漂移。

主要来源（OpenHarmony 开源实现）：
- [third_party_skia `Run.cpp`（positions/fOffset/getOffsets）](https://gitee.com/openharmony/third_party_skia/blob/master/m133/modules/skparagraph/src/Run.cpp)
- [graphic_graphic_2d `RunBaseImpl.cpp`（getPositions/getOffsets/paint）](https://gitee.com/openharmony/third_party_skia/blob/master/m133/modules/skparagraph/src/RunBaseImpl.cpp)
- [graphic_graphic_2d NAPI `js_run.cpp`（getPositions/getOffsets 透传）](https://gitee.com/openharmony/graphic_graphic_2d/blob/master/frameworks/text/interface/mlb/napi/run_napi/js_run.cpp)
- [graphic_graphic_2d NAPI `js_text_line.cpp`（getTextRange/getOffsetForStringIndex/enumerateCaretOffsets）](https://gitee.com/openharmony/graphic_graphic_2d/blob/master/frameworks/text/interface/mlb/napi/text_line_napi/js_text_line.cpp)
- [ace_engine `text_select_controller`（anchor/head、手柄 min/max、caret metrics）](https://gitee.com/openharmony/arkui_ace_engine/blob/master/frameworks/core/components_ng/pattern/text/text_select_controller.cpp)
- [ace_engine `rich_editor_pattern.cpp`（拖选 caret 跟随、affinity）](https://gitee.com/openharmony/arkui_ace_engine/blob/master/frameworks/core/components_ng/pattern/rich_editor/rich_editor_pattern.cpp)
- [ace_engine `text_field_pattern.cpp`（IME preview/cursor 去抖）](https://gitee.com/openharmony/arkui_ace_engine/blob/master/frameworks/core/components_ng/pattern/text_field/text_field_pattern.cpp)


---

## 4. 验证

### 4.1 本机（已完成）
```bash
cd SDK26Target/Weaver
node tools/flowtext-regression.cjs   # FlowText regression: 60 checks passed
node tools/data-regression.cjs       # 28
node tools/shell-regression.cjs      # 20
node tools/window-regression.cjs     # 17
node tools/import-regression.cjs     # 5
```
合计 **130 项通过**；新增 8 项 FlowText 检查覆盖旧缺陷（多 run 叠行首/光标不跟随/滚动归零/预上屏区间误用等）。

### 4.2 设备侧（待用户执行）
```powershell
pwsh tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -BuildOnly
pwsh tools/Test-FlowText.ps1 -DevEcoRoot 'D:/software/CommandLineTools-26.0.0.851' -JavaRoot 'D:/software/DevEco Studio/jbr' -Device '<hdc list targets 的设备>'
```
判据：`BUILD SUCCESSFUL`、HAP mtime 刷新、`ERROR 0`；Hypium `Failure:0 Error:0 Ignore:0`（编辑器组 + 窗口组）。

### 4.3 手工验收
按 `docs/flowtext-testing.md` 的 12 项清单逐项执行，保存 before/after 截图或录屏到 `artifacts/`：
多 run 行渲染、改字号/主题/宽度、五万字滚动、IME 组字、正/反向拖选、长按后拖选、手柄越界、Ctrl+A/Shift+方向键/三击、空行/标题行高亮、Cancel/拖出窗口。

---

## 5. 残余风险与后续

1. **RTL/bidi**：run 原点归一按 LTR 近似；RTL run 的 `positions[0]` 是逻辑首字符（视觉右端），极端混排仍可能有亚像素偏差。后续可用 `getTextDirection()` 分支处理。
2. **`changeSelection` 整篇 IPC**：API 要求整篇文本，五万字仍可能触发大包错误；本轮做 32ms 节流与 Up 强制，未改协议。后续可评估"仅提交时同步"降级。
3. **惰性排版锚点**：`relayoutPreservingAnchor` 以光标屏幕 y 恢复，极端快速缩放/旋转下可能仍有 ≤1 行位移。
4. **字体差异**：不同厂商字体 metrics/回退策略不同，`lineBox` 以引擎返回的 ascent/descent 为准；仍建议真机逐主题确认对比度与基线。
5. **设备证据**：本机无 hdc/模拟器，设备侧结果需在收到构建/Hypium 日志后回填；在此之前只能声明"本地回归 + 静态检查通过"。
6. **打字机体验取舍**：CENTER 中间带阈值 `0.35/0.65`；若希望更"贴中心"，可调带宽，但会重新引入滚动漂移风险。
7. **Ctrl+A 首次成本**：为保证 caret 落在文末，全选会排版到文档末尾（5 万字约 12 个 4000 字窗口），极端长文首次可能有一次百毫秒级停顿；后续可改为"视口内 caret + 后台补齐"。
