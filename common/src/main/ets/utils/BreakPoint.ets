// common/src/main/ets/utils/BreakPoint.ets

export enum BreakPoint {
  SM = 0,
  MD = 1,
  LG = 2
}

export function updateBreakPoint(width: number): void {
  if (width < 600) {
    AppStorage.setOrCreate('currentBreakPoint', BreakPoint.SM)
  } else if (width < 840) {
    AppStorage.setOrCreate('currentBreakPoint', BreakPoint.MD)
  } else {
    AppStorage.setOrCreate('currentBreakPoint', BreakPoint.LG)
  }
}
