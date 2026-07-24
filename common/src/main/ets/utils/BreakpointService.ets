// BreakpointService.ets — Singleton window size monitor
import { window } from '@kit.ArkUI'

export enum BreakPointType {
  SM = 0,
  MD = 1,
  LG = 2
}

function calcBreakPoint(width: number): BreakPointType {
  if (width < 600) return BreakPointType.SM
  if (width < 840) return BreakPointType.MD
  return BreakPointType.LG
}

export class BreakpointService {
  private static instance: BreakpointService | null = null
  private initialized: boolean = false

  static getInstance(): BreakpointService {
    if (BreakpointService.instance === null) {
      BreakpointService.instance = new BreakpointService()
    }
    return BreakpointService.instance
  }

  init(win: window.Window): void {
    if (this.initialized) return
    this.initialized = true
    const rect: window.Rect = win.getWindowProperties().windowRect
    AppStorage.setOrCreate('currentBreakPoint', calcBreakPoint(rect.width))
    AppStorage.setOrCreate('windowWidth', rect.width)
    win.on('windowSizeChange', (size: window.Size) => {
      AppStorage.setOrCreate('currentBreakPoint', calcBreakPoint(size.width))
      AppStorage.setOrCreate('windowWidth', size.width)
    })
  }
}
