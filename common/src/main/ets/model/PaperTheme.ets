// common/src/main/ets/model/PaperTheme.ets

export interface PaperTheme {
  id: string
  name: string
  type: 'preset_color' | 'preset_grid' | 'custom_image'
  backgroundColor: string
  customImagePath: string
  gridType: 'none' | 'grid' | 'horizontal'
  gridColor: string | null
  textColor: string
  needsOverlay: boolean
  overlayColor: string
  overlayOpacity: number
}
