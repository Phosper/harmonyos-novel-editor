// 设备能力快照与分流（T2）
//
// 三条**正交**判据，互不替代（见 docs/refactor/multidevice-interaction-refactor.md §1）：
//   1. 布局层级 LayoutTier —— 只由**窗口宽度断点**决定（BreakPoint / WidthBreakpoint）；
//   2. 设备形态 DeviceClass —— 只决定 chrome 与命中区风格（手机/平板/电脑），不决定断点；
//   3. 输入形态 InputModality —— 决定 hover / 右键 / 快捷键 / 焦点策略。
//
// 电脑模式（自由窗口）的唯一判据是 `window.isInFreeWindowMode()`（API 22）；
// `deviceInfo.deviceType` 只用于 DeviceClass 归类，**禁止**参与布局断点或 chrome 分支
// （CodeLinter `one-multi-breakpoint-check`；平板电脑模式 / MatePad Edge 与 PC 同走桌面 chrome）。
//
// 监听统一收口：windowSizeChange / freeWindowModeChange / avoidAreaChange / windowStatusChange
// 全部在本模块注册一次，UI 侧只订阅 `onChange`。避免 AppShell、标题栏各自注册造成
// 重复刷新与解绑遗漏。
import { window } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'
import { BreakPoint, breakPointFrom } from './BreakPoint'
import { readSafeArea, safeTopVp, safeBottomVp, watchSafeArea } from './SafeArea'
import { DESKTOP_CHROME_HEIGHT_VP, readTitleButtonWidthVp } from './DesktopWindowChrome'
import { Logger } from './Logger'

/** 设备形态：只决定 chrome 风格与命中区，不决定布局断点 */
export enum DeviceClass {
  PHONE = 0,
  TABLET = 1,
  PC = 2
}

/** 输入形态：决定 hover / 右键 / 快捷键 / 焦点策略 */
export enum InputModality {
  TOUCH = 0,
  POINTER = 1,
  MIXED = 2
}

/** 布局层级：由断点唯一决定 */
export enum LayoutTier {
  SINGLE = 0,
  DOUBLE = 1,
  TRIPLE = 2
}

/**
 * 一次设备快照：**不可变语义**，读的时候整体替换，不就地改字段
 * （就地改会让订阅方无法判断"是否真的变了"）。
 */
export class DeviceSnapshot {
  deviceClass: DeviceClass = DeviceClass.PHONE
  /** window.isInFreeWindowMode()：PC 与平板电脑模式（MatePad Edge）均为 true */
  freeWindow: boolean = false
  /** window.WindowStatusType（FLOATING / MAXIMIZE / FULL_SCREEN / SPLIT_SCREEN） */
  windowStatus: number = 0
  breakPoint: BreakPoint = BreakPoint.SM
  modality: InputModality = InputModality.TOUCH
  /** 顶部标题栏高度（含安全区，vp）；0 表示当前没有自绘标题栏 */
  chromeHeightVp: number = 0
  /** 原生三键区宽度（保留原生三键时内容需右避让，vp） */
  titleButtonWidthVp: number = 0
  safeTopVp: number = 0
  safeBottomVp: number = 0

  /** SINGLE: SM；DOUBLE: MD；TRIPLE: LG */
  get tier(): LayoutTier {
    if (this.breakPoint === BreakPoint.SM) {
      return LayoutTier.SINGLE
    }
    if (this.breakPoint === BreakPoint.MD) {
      return LayoutTier.DOUBLE
    }
    return LayoutTier.TRIPLE
  }

  /** 是否走桌面沉浸标题栏（自由窗口模式 = PC 与平板电脑模式） */
  get isDesktopChrome(): boolean {
    return this.freeWindow
  }

  /** 是否键鼠优先（决定 hover / 右键 / 焦点环 / 快捷键）；MIXED 不算键鼠优先 */
  get pointerPrimary(): boolean {
    return this.modality === InputModality.POINTER
  }
}

/** 设备形态归类：**只**用于 chrome 与命中区风格，不参与断点判断 */
export function detectDeviceClass(): DeviceClass {
  let type: string = ''
  try {
    type = deviceInfo.deviceType
  } catch (e) {
    // 极少数裁剪设备上 deviceInfo 不可用：按手机（最保守）归类
    Logger.warn('DeviceProfile: read deviceType failed ' + String(e))
  }
  if (type === '2in1' || type === 'pc') {
    return DeviceClass.PC
  }
  if (type === 'tablet') {
    return DeviceClass.TABLET
  }
  return DeviceClass.PHONE
}

/**
 * 平台能力：PC（2in1）没有传统状态栏/导航条。
 *
 * 这是**平台能力**判断（决定某组系统栏 API 是否可用），不是布局断点，
 * 因此集中在本模块读取 deviceType；其它模块不要再直接读 deviceType。
 */
export function isPcPlatform(): boolean {
  return detectDeviceClass() === DeviceClass.PC
}

/**
 * 输入形态推导。
 *
 * 没有官方"当前是否接了鼠标"的一次性查询（inputDevice 只能按设备枚举且需要权限/时序），
 * 因此按**形态基线 + 实测校正**两步走：
 *   基线：电脑（2in1）= 键鼠优先；平板 = 触摸（含 MatePad Edge 电脑模式）；手机 = 触摸；
 *   校正：一旦真的收到鼠标/笔输入（hover / 按下 / 滚轮 → notePointerActivity），永久升级为键鼠优先。
 * MIXED 保留给后续"触摸+指针都常用"的细分场景，当前不作为键鼠优先（pointerPrimary 只认 POINTER），
 * 这样纯触摸平板不会被误开 hover-only 交互，而接了键鼠的设备第一次悬停/点击后即生效。
 */
export function modalityFor(cls: DeviceClass, freeWindow: boolean, pointerSeen: boolean): InputModality {
  // 实测优先：只要真的收到过鼠标/手写笔输入，就按键鼠优先（平板外接键鼠、MatePad Edge 电脑模式）
  if (pointerSeen) {
    return InputModality.POINTER
  }
  // 电脑（2in1）默认就是键鼠设备
  if (cls === DeviceClass.PC) {
    return InputModality.POINTER
  }
  // 平板的自由窗口（电脑模式）**不等于**键鼠：MatePad Edge 电脑模式仍可纯触摸使用。
  // 基线按触摸处理，第一次 hover/鼠标按下由 notePointerActivity() 升级为 POINTER，
  // 避免纯触摸平板被误开 hover-only / 指针光标 / 桌面工具条。
  return InputModality.TOUCH
}

/**
 * 设备能力服务（进程内单例，见文件末尾 `deviceProfile`）。
 *
 * 生命周期：EntryAbility 写入 `AppStorage('mainWindow')` → AppShell `aboutToAppear` 里
 * `attach(uiContext, window)`。窗口级监听只绑一次（bound 幂等），不随页面反复挂载/卸载，
 * 页面卸载时只摘掉自己的 `onChange` 订阅（返回的 disposer）。
 */
export class DeviceProfileService {
  private snap: DeviceSnapshot = new DeviceSnapshot()
  private changeListeners: Array<(snap: DeviceSnapshot) => void> = []
  private activeListeners: Array<() => void> = []
  private win: window.Window | null = null
  private ui: UIContext | null = null
  private bound: boolean = false
  private safeDisposer: (() => void) | null = null
  private freeListener: ((isFree: boolean) => void) | null = null
  private sizeListener: ((size: window.Size) => void) | null = null
  private statusListener: ((status: window.WindowStatusType) => void) | null = null
  /** isInFreeWindowMode 是否可用（API < 22 或裁剪设备上只警告一次） */
  private freeWindowProbeOk: boolean = true
  /** 是否真的收到过鼠标/笔输入（用于把 MIXED/TOUCH 校正为键鼠优先） */
  private pointerSeen: boolean = false

  get snapshot(): DeviceSnapshot {
    return this.snap
  }

  /** 绑定 UIContext 与主窗口并立即产出一份快照；幂等，可重复调用 */
  attach(ui: UIContext, w: window.Window): void {
    if (this.win !== null && this.win !== w) {
      this.releaseWindow()
    }
    this.ui = ui
    this.win = w
    try {
      // 全屏布局已由 EntryAbility 开启；此处按**入参窗口**读避让区才拿得到真实值
      // （显式传窗口，不依赖 AppStorage 的写入时序）
      readSafeArea(w)
    } catch (e) {
      Logger.warn('DeviceProfile: readSafeArea failed ' + String(e))
    }
    if (!this.bound) {
      this.bindWindow(w)
      this.bound = true
    }
    if (this.safeDisposer === null) {
      // avoidAreaChange 也统一收口到这里（SafeArea 内部只允许一个监听）
      this.safeDisposer = watchSafeArea(() => {
        this.refresh()
      }, w)
    }
    this.refresh()
  }

  /** 解绑全部窗口监听（窗口销毁时调用；页面级卸载只需释放自己拿到的 disposer） */
  detach(): void {
    this.releaseWindow()
    this.changeListeners = []
    this.activeListeners = []
  }

  /** 切换窗口时保留页面订阅，仅释放旧窗口的监听。 */
  private releaseWindow(): void {
    const w: window.Window | null = this.win
    if (w !== null && this.bound) {
      try {
        if (this.freeListener !== null) {
          w.off('freeWindowModeChange', this.freeListener)
        }
      } catch (e) {
        Logger.warn('DeviceProfile: off freeWindowModeChange failed ' + String(e))
      }
      try {
        if (this.sizeListener !== null) {
          w.off('windowSizeChange', this.sizeListener)
        }
      } catch (e) {
        Logger.warn('DeviceProfile: off windowSizeChange failed ' + String(e))
      }
      try {
        if (this.statusListener !== null) {
          w.off('windowStatusChange', this.statusListener)
        }
      } catch (e) {
        Logger.warn('DeviceProfile: off windowStatusChange failed ' + String(e))
      }
    }
    if (this.safeDisposer !== null) {
      this.safeDisposer()
      this.safeDisposer = null
    }
    this.bound = false
    this.win = null
    this.ui = null
    this.freeListener = null
    this.sizeListener = null
    this.statusListener = null
    this.freeWindowProbeOk = true
  }

  /** 重读全部判据并广播一份新快照 */
  refresh(): void {
    const next: DeviceSnapshot = new DeviceSnapshot()
    next.deviceClass = detectDeviceClass()
    next.freeWindow = this.readFreeWindow()
    next.windowStatus = this.readWindowStatus()
    next.breakPoint = this.readBreakPoint()
    next.modality = modalityFor(next.deviceClass, next.freeWindow, this.pointerSeen)
    next.safeTopVp = safeTopVp()
    next.safeBottomVp = safeBottomVp()
    // 标题栏高度**含**安全区：AppShell 只按 chromeHeight 让位，不再叠加 safeTop（防双算）
    next.chromeHeightVp = next.freeWindow ? DESKTOP_CHROME_HEIGHT_VP + next.safeTopVp : 0
    next.titleButtonWidthVp = this.readTitleButtonWidth()
    this.snap = next
    this.emit()
  }

  /** 订阅快照变化；返回的 disposer 在页面 aboutToDisappear 调用 */
  onChange(cb: (snap: DeviceSnapshot) => void): () => void {
    this.changeListeners.push(cb)
    return (): void => {
      const index: number = this.changeListeners.indexOf(cb)
      if (index >= 0) {
        this.changeListeners.splice(index, 1)
      }
    }
  }

  /**
   * 订阅"窗口重新激活"（windowStageEvent = ACTIVE）。
   * AppStorage 不是响应式的，编辑器无法用 @StorageProp 监听，故由本模块转成订阅函数。
   */
  onWindowActivated(cb: () => void): () => void {
    this.activeListeners.push(cb)
    return (): void => {
      const index: number = this.activeListeners.indexOf(cb)
      if (index >= 0) {
        this.activeListeners.splice(index, 1)
      }
    }
  }

  /** EntryAbility 在 windowStageEvent(ACTIVE) 调用 */
  notifyWindowActivated(): void {
    const copy: Array<() => void> = this.activeListeners.slice()
    for (let i = 0; i < copy.length; i++) {
      const cb: () => void = copy[i]
      try {
        cb()
      } catch (e) {
        Logger.error('DeviceProfile: activated listener failed ' + String(e))
      }
    }
  }

  /** 收到鼠标 / 手写笔输入时调用：把输入形态校正为键鼠优先 */
  notePointerActivity(): void {
    if (this.pointerSeen) {
      return
    }
    this.pointerSeen = true
    this.refresh()
  }

  // ===================== 内部 =====================

  private bindWindow(w: window.Window): void {
    const free: (isFree: boolean) => void = (isFree: boolean): void => {
      // 电脑模式判据变化：同步给 AppStorage（EntryAbility / 其他模块读取）并重算快照
      AppStorage.setOrCreate<boolean>('freeWindowMode', isFree)
      this.refresh()
    }
    this.freeListener = free
    try {
      w.on('freeWindowModeChange', free)
    } catch (e) {
      Logger.warn('DeviceProfile: on freeWindowModeChange failed ' + String(e))
    }

    const size: (newSize: window.Size) => void = (newSize: window.Size): void => {
      // 只重算（断点由 UIContext 提供，尺寸变化后需重新读取断点）
      this.refresh()
    }
    this.sizeListener = size
    try {
      w.on('windowSizeChange', size)
    } catch (e) {
      Logger.warn('DeviceProfile: on windowSizeChange failed ' + String(e))
    }

    const status: (newStatus: window.WindowStatusType) => void = (newStatus: window.WindowStatusType): void => {
      this.refresh()
    }
    this.statusListener = status
    try {
      w.on('windowStatusChange', status)
    } catch (e) {
      Logger.warn('DeviceProfile: on windowStatusChange failed ' + String(e))
    }
  }

  private readFreeWindow(): boolean {
    const w: window.Window | null = this.win
    if (w !== null && this.freeWindowProbeOk) {
      try {
        return w.isInFreeWindowMode()
      } catch (e) {
        // 非自由窗口能力设备（或 API < 22）会抛 1300002/801：只警告一次，降级到 AppStorage
        this.freeWindowProbeOk = false
        Logger.warn('DeviceProfile: isInFreeWindowMode unavailable ' + String(e))
      }
    }
    const stored: boolean | undefined = AppStorage.get<boolean>('freeWindowMode')
    return stored !== undefined ? stored : false
  }

  private readBreakPoint(): BreakPoint {
    const ui: UIContext | null = this.ui
    if (ui !== null) {
      try {
        return breakPointFrom(ui.getWindowWidthBreakpoint())
      } catch (e) {
        Logger.warn('DeviceProfile: getWindowWidthBreakpoint failed ' + String(e))
      }
    }
    return this.snap.breakPoint
  }

  private readWindowStatus(): number {
    const w: window.Window | null = this.win
    if (w === null) {
      return this.snap.windowStatus
    }
    try {
      return w.getWindowStatus()
    } catch (e) {
      Logger.warn('DeviceProfile: getWindowStatus failed ' + String(e))
      return this.snap.windowStatus
    }
  }

  private readTitleButtonWidth(): number {
    const w: window.Window | null = this.win
    return w !== null ? readTitleButtonWidthVp(w) : 0
  }

  private emit(): void {
    const snap: DeviceSnapshot = this.snap
    const copy: Array<(snap: DeviceSnapshot) => void> = this.changeListeners.slice()
    for (let i = 0; i < copy.length; i++) {
      const cb: (snap: DeviceSnapshot) => void = copy[i]
      try {
        cb(snap)
      } catch (e) {
        // 单个订阅方异常不能拖垮其它订阅方（例如标题栏报错不应让 AppShell 停更）
        Logger.error('DeviceProfile: change listener failed ' + String(e))
      }
    }
  }
}

/** 进程内单例：设备形态与断点是全局唯一的，避免各页面各算一套 */
export const deviceProfile: DeviceProfileService = new DeviceProfileService()
