# 审计报告落地说明（2026-10-25）

> 审计基线：`848cd67`（《Weaver 画布交互旅程审议报告》）
> 本轮按用户“按审计报告更新代码”的授权修改；报告原文的 `implementation_authorized: false` 是上一轮约束，本轮以用户指令为准。
> **仍未重新构建/真机验证**。

## 1. 已落地

| 审计项 | 改动 | 代码位置 |
|---|---|---|
| J01 先配置容器 | 无白板空态改为「开始整理思路」：直接创建课程白板 + 一张「未命名提纲」写作卡并打开详情，不再先开管理面板/先选类型 | `shell/CanvasDest.ets` startFirstBoard |
| J02 摘录难找回 | 卡片库新增「打开」（不上板也能看/改）、「待整理」筛选（只看未上板） | `shell/CardLibrary.ets` kindFilter=3 / onOpen |
| J03 预览≠结果 | 新增 `canvasAttachAt` 按最终兄弟位置插入；行落点分三段：上/下边缘=同级前插/后插，中间=挂成子卡（保留章→节→目嵌套）。预览用 `previewIndex`（展开行位置），落库用 `insertIndex`（兄弟位置），两者分离 | `model/CanvasTypes.ets`、`store/CanvasStore.ets` `attachCardAt`、`shell/CanvasPane.ets` hitTest/onDragFinish、`CanvasTheme.ets` CanvasHitResult |
| J04 章节重名 | 建卡不再拒绝同板同名；章节默认名取现有「第 N 章」最大编号 +1；失败提示区分“已到最深层”和“一般失败” | `store/CanvasStore.ets` createCard、`shell/CanvasPane.ets` nextChapterTitle/addChapter |
| J05 空间/结构混在一次拖动 | 行上下边缘=同级前插/后插，行中间=挂子卡；卡片拖到卡片仍表示“加入该卡”。**“加入提纲”菜单/纯移动模式未做** | `shell/CanvasPane.ets` |
| J06 放卡不在视野 | 新增视口尺寸；单张/批量按**当前视口中心网格**落点（不再固定 120+28）；卡片库已上板卡提供「定位」并把相机移过去 | `store/CanvasStore.ets` viewport/focusCard、`shell/CanvasDest.ets` placePoint、`shell/CardLibrary.ets` onLocate |
| J07 生成不透明 | 生成弹窗增加前 4 项提纲预览、素材数、“生成是快照”说明；已有文稿时「打开文稿」为主按钮，「新建副本」为次按钮，「覆盖现有文稿」为危险按钮；“根卡素材”改为“把这张卡自己的素材写入开篇” | `shell/CanvasPane.ets` draftDialog/draftPreviewLines |
| J08 跳回来源 | 同文稿分支也先收起画布；跨文稿保持“打开→关画布→定位” | `shell/EvidenceDrawer.ets` jumpToSourceAsync |
| UI02 复制语义 | `duplicateCard` 改为**含素材完整复制**；菜单/卡片库文案改为「复制（含素材）」 | `store/CanvasStore.ets` duplicateCard、`shell/CardLibrary.ets`、`shell/CanvasPane.ets` |

## 2. 验证

```text
canvas 13 / data 49 / draft 14 / shell 59 / schema 5
flowtext 127 / import 5 / device 27 / window 32 / guard 19（61 文件）
合计 350 项全过
```

新增回归：
- 纯规则：`canvasAttachAt` 中间插入、同父重排（含索引回退）。
- 数据：同板同名允许、复制含素材、删卡/移出撤销。
- 外壳：落点/待整理/定位/生成预览/同文稿跳回收画布。

**未构建、未装机。** 审计报告本身也要求真机任务脚本 T1–T6 验证，尚未执行。

## 3. 尚未落地（需要产品决定或下一轮）

| 项 | 原因 / 现状 |
|---|---|
| J05 “加入提纲”菜单、普通拖动只移动 | 需要产品确认“空间移动 vs 结构修改”的默认；当前拖到卡片上仍会嵌套 |
| J02 保存后“查看/改目标”、重复收集提示 | 需要捕获流程的状态模型（待整理/已加入提纲）与 toast 交互 |
| J07 完整生成预览、版本/副本策略、人工正文保护 | 当前只加摘要预览；覆盖仍靠二次按钮，无版本历史 |
| J08 返回原卡、来源失效处理、短时高亮 | 需要编辑器侧“返回画布并定位卡片”的桥与来源校验 |
| UI01 品牌顺序、详情渐进展示、去掉阴影/胶囊 | 视觉与信息架构改造，建议在真机验证后做 |
| J05/J08 手势替代的完整键盘/菜单路径 | 目前有 ▲▼、行内 ✎、卡片菜单；缺“移动到第 N 项” |
| 同板多处引用实例模型 | 当前仍是一卡一贴放，报告已列为需另审 |

## 4. 仍需注意

- `canvasAttachAt` 的 index 语义是“最终兄弟列表位置”；同父移动时内部已做索引回退。
- 行落点用相对高度分段（<28% / >72% 为同级插入，中间为嵌套）；真机需确认 30vp 行高下的手感。
- `CanvasHitResult.previewIndex` 与 `insertIndex` 分离：前者给缺口，后者给落库。
- 批量放卡按视口网格排，8 张以上可能仍在屏幕外；已提示用「定位」找回，未做“适合全部”。
- 章节默认名只保证“第 N 章”不撞已有编号；用户仍可手动改成同名（身份由 id 区分）。
- 构建/真机未复跑，ArkTS 编译风险仍存在。
