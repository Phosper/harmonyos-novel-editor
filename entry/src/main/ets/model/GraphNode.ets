// 关系图节点与连线（运行时视图模型，不持久化）
import { CharacterType } from './Character'
import { RelationshipType } from './Relationship'

export interface GraphNode {
  characterId: string
  name: string
  type: CharacterType
  x: number
  y: number
  radius: number
  isHighlighted: boolean
  isDimmed: boolean
}

export interface GraphEdge {
  id: string
  fromId: string
  toId: string
  type: RelationshipType
  label: string
}
