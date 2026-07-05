// GraphGestureHandler.ets — Gesture handling for graph canvas (inlined in RelationshipTabPage for MVP)
import type { GraphNode } from './GraphCanvas'

@Component
export struct GraphGestureHandler {
  @Link nodes: GraphNode[]

  build() {
    Stack()
      .width('100%').height('100%')
  }
}
