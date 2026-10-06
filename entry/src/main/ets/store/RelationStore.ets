// 人物关系与关系图数据
import type { CharacterModel } from '../model/Character'
import type { RelationshipModel } from '../model/Relationship'
import { RelationshipType } from '../model/Relationship'
import type { GraphNode, GraphEdge } from '../model/GraphNode'
import { relationRepo } from './Repos'

@ObservedV2
export class RelationStore {
  @Trace relationships: RelationshipModel[] = []
  @Trace nodes: GraphNode[] = []
  @Trace edges: GraphEdge[] = []

  get hasNodes(): boolean {
    return this.nodes.length > 0
  }

  async load(bookId: string, characters: CharacterModel[]): Promise<void> {
    this.relationships = await relationRepo.loadRelationships(bookId)
    this.rebuild(characters)
  }

  async reload(bookId: string, characters: CharacterModel[]): Promise<void> {
    await this.load(bookId, characters)
  }

  /**
   * 依人物 + 关系重建图数据。两端人物有一端已不存在的关系直接丢弃，
   * 避免出现指向空节点的连线。
   */
  rebuild(characters: CharacterModel[]): void {
    const idSet: Set<string> = new Set<string>()
    const nodes: GraphNode[] = []
    for (const c of characters) {
      idSet.add(c.id)
      const node: GraphNode = {
        characterId: c.id,
        name: c.name,
        type: c.characterType,
        x: 0,
        y: 0,
        radius: 34,
        isHighlighted: false,
        isDimmed: false
      }
      nodes.push(node)
    }
    const edges: GraphEdge[] = []
    for (const r of this.relationships) {
      if (!idSet.has(r.characterIdA) || !idSet.has(r.characterIdB)) {
        continue
      }
      const edge: GraphEdge = {
        id: r.id,
        fromId: r.characterIdA,
        toId: r.characterIdB,
        type: r.type,
        label: r.label
      }
      edges.push(edge)
    }
    this.nodes = nodes
    this.edges = edges
  }

  async add(bookId: string, fromId: string, toId: string, type: RelationshipType,
    label: string, notes: string, characters: CharacterModel[]): Promise<void> {
    const created: RelationshipModel = await relationRepo.create(bookId, fromId, toId, type, label, notes)
    this.relationships = this.relationships.concat([created])
    this.rebuild(characters)
  }

  async remove(id: string, characters: CharacterModel[]): Promise<void> {
    await relationRepo.delete(id)
    this.relationships = this.relationships.filter((r: RelationshipModel) => r.id !== id)
    this.rebuild(characters)
  }
}
