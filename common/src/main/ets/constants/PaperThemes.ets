// common/src/main/ets/constants/PaperThemes.ets
import type { PaperTheme } from '../model/PaperTheme'

export const PRESET_THEMES: PaperTheme[] = [
  {
    id: 'white',
    name: '纯白',
    type: 'preset_color',
    backgroundColor: '#FFFFFF',
    customImagePath: '',
    gridType: 'none',
    gridColor: null,
    textColor: '#1A1A1A',
    needsOverlay: false,
    overlayColor: '#FFFFFF',
    overlayOpacity: 0
  },
  {
    id: 'cream',
    name: '羊皮纸',
    type: 'preset_color',
    backgroundColor: '#FBF6E8',
    customImagePath: '',
    gridType: 'none',
    gridColor: null,
    textColor: '#1A1A1A',
    needsOverlay: false,
    overlayColor: '#FFFFFF',
    overlayOpacity: 0
  },
  {
    id: 'green_light',
    name: '淡绿护眼',
    type: 'preset_color',
    backgroundColor: '#EDF5EA',
    customImagePath: '',
    gridType: 'none',
    gridColor: null,
    textColor: '#1A1A1A',
    needsOverlay: false,
    overlayColor: '#FFFFFF',
    overlayOpacity: 0
  },
  {
    id: 'manuscript_grid',
    name: '方格稿纸',
    type: 'preset_grid',
    backgroundColor: '#FFFFFF',
    customImagePath: '',
    gridType: 'grid',
    gridColor: '#D3E9CB',
    textColor: '#1A1A1A',
    needsOverlay: false,
    overlayColor: '#FFFFFF',
    overlayOpacity: 0
  }
]

export const DEFAULT_THEME: PaperTheme = PRESET_THEMES[0]
