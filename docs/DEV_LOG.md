# Weaver 开发日志

## 2026-07-26

### 完成内容
- 关联图与资料库问题排查

### 问题分析详情

---

#### 问题1：右键 onNodeRightClick 不触发  ✅ 已确认存在

**根因**：GraphCanvas.ets 的 PanGesture（fingers:1, Horizontal|Vertical）在 Windows 上会捕获所有鼠标按钮的按下事件，包括右键。ArkUI 手势识别优先级高于 onMouse 回调，PanGesture 先消费事件，导致 onMouse 里的 MouseButton.Right 分支收不到事件。

**影响文件**：features/relationship/src/main/ets/components/GraphCanvas.ets

**额外发现**：RelationshipTabPage.ets（第 351-354 行）根本没有传入 onNodeRightClick 回调——这个页面完全没用右键菜单。

**修复方向**（自然语言描述）：
- GraphCanvas.ets：在 PanGesture 的 onActionStart 里检查 event.button === MouseButton.Right，如果是右键则 return 不处理，让 onMouse 的右键分支正常工作
- 或者：移除 PanGesture，改用 onMouse 同时处理拖拽和点击——但会丢失手势冲突消解
- 或者（推荐）：给 Canvas 加 .onContextMenu 回调，ArkUI 的右键菜单事件走这个，不和手势系统抢

---

#### 问题2：连线后弹窗出不来 / 弹窗位置不对  ✅ 已确认存在

**根因**：弹窗用的是条件渲染（`if (this.showRelForm)` + `.position({ x: '30%', y: '30%' })`），不是 bindPopup。硬编码百分比位置相对于 Stack 容器，不会跟随鼠标或节点位置。

**关联表单**（buildRelForm）和删除关系列表（buildRelListView）都用绝对定位，位置固定。

**影响文件**：products/default/src/main/ets/pclayout/PcEditorZone.ets（第 706-719 行）

**修复方向**：
- 改用 bindPopup，placement 设成 Placement.Bottom 或 Placement.TopStart
- 或者动态计算位置：从鼠标事件坐标或节点 screen 坐标换算百分比/像素值

---

#### 问题3：删除关系列表 bindPopup 还没确认绑上去  ✅ 确认——没用 bindPopup

**确认**：showRelList 用的也是条件渲染 + `.position({ x: '25%', y: '25%' })`，没有 bindPopup。和问题 2 同性质。

---

#### 问题4：onGraphNodeTap 里 isConnecting = false 已经加了  ✅ 已实现

**确认**：PcEditorZone.ets 第 1134 行已实现：
```typescript
this.isConnecting = false
this.connectFromId = ''
```

---

#### 问题5：世界观卡片点击编辑（C栏切换到 detail 视图）  ⚠️ 基础链路可用，有潜在问题

**现状**：世界观卡片 onClick 调用 onEditWorldDetail(ws.id)，PcShell 中设置 editorViewMode = MATERIAL_DETAIL + selectedDetailType = 'world' + selectedWorldId。buildWorldDetailView() 存在。

**潜在问题**：
1. buildWorldDetailView 中的返回按钮做了两件事：`this.showCharForm = false; this.onBackToMaterial()`，其中 showCharForm 和世界观编辑无关（世界观编辑没有用 bindPopup）
2. 世界观编辑没有"保存"按钮，TextArea 的 onChange 直接调用 onUpdateWorld——这意味着每次打字都写 DB，可能频繁

**影响文件**：
- PcEditorZone.ets（第 642-647 行世界卡片点击、第 1178-1203 行 buildWorldDetailView）
- PcShell.ets（第 531-536 行 onEditWorldDetail）

---

#### 问题6：人物表单 ID 生成  ✅ 已实现

**确认**：saveChar() 第 1319 行：`id: this.isNewChar ? IdGenerator.generate() : this.editingCharId` 正确处理新建/编辑分支。

buildCharDetailView 保存按钮（第 1262 行）用的 `this.selectedCharId`，这是编辑已有角色的路径，正确。

**IdGenerator 实现**：common/src/main/ets/utils/IdGenerator.ets — 用 util.generateRandomUUID() 生成 UUID。

---

#### 问题7：连线后高亮状态不消失  ⚠️ 严重问题

**根因**：GraphCanvas 的 `@Watch('onGraphChanged')` 只挂在 `nodes` 和 `edges` 上。`@Link isConnecting` 变化时不会触发重绘。

流程：
1. startConnecting() → isConnecting=true → GraphCanvas 在 drawNodes() 画出绿色环（第 134-141 行）
2. 用户点击目标节点 → onGraphNodeTap() → isConnecting=false, connectFromId='', showRelForm=true
3. isConnecting=false 但 draw() 没有被调用 → canvas 上还画着绿色环
4. 弹窗消失后绿色环仍在

**影响文件**：features/relationship/src/main/ets/components/GraphCanvas.ets（第 33-34 行 @Link 无 @Watch）

**修复方向**：
- 给 isConnecting 加 @Watch 调用 draw()
- 或者每次 isConnecting 变化时浅拷贝 nodes 数组触发 nodes@Watch
- 或者在 PcEditorZone 的 onGraphNodeTap/cancelConnecting 里显式触发 graphNodes 引用变更
