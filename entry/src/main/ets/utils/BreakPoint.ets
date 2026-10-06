// 断点系统（一多适配）
//
// 只用**窗口宽度**决定断点。官方 CodeLinter 规则 `one-multi-breakpoint-check`
// 明确禁止用设备类型 / 屏幕方向 / 是否可折叠来判断一多断点 —— 之前的实现用
// `deviceInfo.deviceType === '2in1'` 参与布局分支，是违规写法，已移除。
//
// 断点取值来自系统（`UIContext.getWindowWidthBreakpoint()`），不自己写死阈值：
// 官方文档说明"个别设备可根据需求通过产品化配置调整断点阈值"，自己写 vp 阈值会漂移。
// 官方默认阈值供参考：xs <320vp，sm [320,600)，md [600,840)，lg [840,1440)，xl ≥1440。
export enum BreakPoint {
  SM = 0,
  MD = 1,
  LG = 2
}

/** 官方 WidthBreakpoint（xs/sm/md/lg/xl）→ 本应用的三档 */
export function breakPointFrom(bp: WidthBreakpoint): BreakPoint {
  if (bp === WidthBreakpoint.WIDTH_XS || bp === WidthBreakpoint.WIDTH_SM) {
    return BreakPoint.SM
  }
  if (bp === WidthBreakpoint.WIDTH_MD) {
    return BreakPoint.MD
  }
  return BreakPoint.LG
}

/** 手机竖屏档（窄屏）：单列 + 底部页签 */
export function isNarrowTier(bp: BreakPoint): boolean {
  return bp === BreakPoint.SM
}

/** 中等宽度档：手机横屏 / 折叠展开 / 小平板 → 侧栏 + 内容双栏 */
export function isMediumTier(bp: BreakPoint): boolean {
  return bp === BreakPoint.MD
}

/** 宽屏档：平板 / 电脑 → 保持现有三栏（不改动） */
export function isWideTier(bp: BreakPoint): boolean {
  return bp === BreakPoint.LG
}
