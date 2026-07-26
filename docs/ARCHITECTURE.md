# Weaver 架构文档

## 关系图模块

### 组件树

```
PcShell (products/default/src/main/ets/pclayout/PcShell.ets)
  └─ PcEditorZone (PcEditorZone.ets)
       └─ GraphCanvas (features/relationship/src/main/ets/components/GraphCanvas.ets)
            └─ Canvas (自绘节点/边/连线高亮)
            └─ PanGesture (拖拽画布/连线)
            └─ PinchGesture (缩放)
            └─ TapGesture (单节点点击)
            └─ LongPressGesture (长按呼菜单)
            └─ onMouse (悬停检测 + 右键菜单)

RelationshipTabPage (pages/RelationshipTabPage.ets)
  └─ GraphCanvas (同上)
```

### 数据流

**状态集中管理**：PcEditorZone 持有所有图状态（@State），通过 @Link 传给 GraphCanvas：
- nodes / edges → @Link @Watch('onGraphChanged') → 触发重绘
- panOffsetX, panOffsetY → 拖拽偏移
- canvasScale → 缩放比例
- selectedRelId → 选中边高亮
- isConnecting / connectFromId → 连线模式高亮
- onNodeTap / onNodeLongPress / onNodeRightClick / onSwipeConnect / onDoubleTapCanvas → 回调

**数据来源**：PcShell.buildGraphData() 从 vm.charactersList + vm.relationships 构建 GraphNode[] / GraphEdge[]，通过 Prop 传给 PcEditorZone。

### 关键问题

1. **高亮不消失**：isConnecting 无 @Watch，变化时不触发重绘
2. **右键被拦截**：PanGesture(fingers:1) 在 Windows 上拦截右键
3. **弹窗硬编码**：关系表单/删除列表用条件渲染 + 固定百分比位置
