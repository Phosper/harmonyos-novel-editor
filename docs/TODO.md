# Weaver TODO

## 优先级 P0（阻塞问题，用户正在体验）

### [P0] 连线后高亮状态不消失
**文件**：features/relationship/src/main/ets/components/GraphCanvas.ets
**问题**：@Link isConnecting 无 @Watch，状态变化时不触发重绘
**修复方案**：
1. 给 isConnecting 加 @Watch('onIsConnectingChanged')，onIsConnectingChanged 里调 draw()
2. 或每次设置 isConnecting 时浅拷贝 graphNodes 触发 nodes@Watch

---

## 优先级 P1（功能缺陷）

### [P1] 右键 onNodeRightClick 不触发
**文件**：features/relationship/src/main/ets/components/GraphCanvas.ets
**问题**：PanGesture(fingers:1) 在 Windows 上拦截右键事件
**修复方案**：PanGesture.onActionStart 检查 event.button === Right 时直接 return，或加 onContextMenu 处理

### [P1] RelationshipTabPage 没有右键菜单
**文件**：products/default/src/main/ets/pages/RelationshipTabPage.ets
**问题**：onNodeRightClick 未传入，画布右键无反应
**修复方案**：传入 onNodeRightClick 回调处理

### [P1] 弹窗位置不准确
**文件**：PcEditorZone.ets（第 702-718 行）
**问题**：关系表单和关系列表用硬编码百分比位置
**修复方案**：使用 bindPopup 替代条件渲染，或根据鼠标事件坐标计算位置

---

## 优先级 P2（可用性问题）

### [P2] RelationshipTabPage 没有提供 onNodeRightClick
**文件**：products/default/src/main/ets/pages/RelationshipTabPage.ets
**问题**：独立关系图页面没有右键功能
**修复方案**：添加 onNodeRightClick 传入参数，实现右键菜单

---

## 已完成

- [x] onGraphNodeTap 里 isConnecting = false 已实现（PcEditorZone.ets 第 1134 行）
- [x] 人物表单 ID 生成用 IdGenerator.generate()（saveChar 第 1319 行）
- [x] checkRelList bindPopup 已确认：没用 bindPopup，用条件渲染（PcEditorZone.ets 第 713-719 行）
- [x] 世界观卡片点击编辑基础链路可用（onClick → onEditWorldDetail → MATERIAL_DETAIL）
