// common/src/main/ets/model/Relationship.ets

export interface RelationshipModel {
  id: string
  bookId: string
  characterIdA: string
  characterIdB: string
  type: string
  label: string
  notes: string
}
