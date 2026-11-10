// 功能包状态查询（ADR-003 §2.6 的 PackageState 第一层）
//
// 只回答一个问题：**这个功能包现在在不在设备上**。
// 不负责下载/安装（那是应用市场按需包 + moduleInstallManager 的事，需要真机验证）。
//
// 防御原则：任何查询失败都返回 UNKNOWN，界面显示"未知"，绝不假装"已安装"。
import { bundleManager } from '@kit.AbilityKit'
import { FeatureDescriptor, FeatureId } from 'feature_contracts'
import { featureCatalog } from './CoreRuntime'

export enum FeatureState {
  /** 模块清单里能找到该模块 */
  INSTALLED = 0,
  /** 查不到模块信息（清单不含它 / 接口不可用）：不下"未安装"的结论 */
  UNKNOWN = 2
}

export class FeatureStatus {
  descriptor: FeatureDescriptor
  state: FeatureState = FeatureState.UNKNOWN

  constructor(descriptor: FeatureDescriptor, state: FeatureState) {
    this.descriptor = descriptor
    this.state = state
  }
}

/** 当前应用包含的模块名（HAP + HSP）；查不到返回 null */
function installedModuleNames(): Set<string> | null {
  try {
    // 只查模块清单（HAP 标志在这个 SDK 上同时覆盖随包的 HSP；
    // 若某天清单里不再包含 HSP，这里会退化成"状态未知"，不会谎报"未安装"）
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE)
    const names: Set<string> = new Set<string>()
    const modules = info.hapModulesInfo
    if (modules === undefined || modules === null) {
      return null
    }
    for (let i: number = 0; i < modules.length; i++) {
      names.add(modules[i].name)
    }
    return names
  } catch (e) {
    return null
  }
}

/** 某个功能包的状态 */
export function featureState(id: FeatureId): FeatureStatus {
  const catalog: FeatureDescriptor[] = featureCatalog()
  let target: FeatureDescriptor | null = null
  for (let i: number = 0; i < catalog.length; i++) {
    if (catalog[i].id === id) {
      target = catalog[i]
      break
    }
  }
  if (target === null) {
    return new FeatureStatus(new FeatureDescriptor(), FeatureState.UNKNOWN)
  }
  const names: Set<string> | null = installedModuleNames()
  if (names === null) {
    return new FeatureStatus(target, FeatureState.UNKNOWN)
  }
  const state: FeatureState = names.has(target.moduleName) ? FeatureState.INSTALLED : FeatureState.UNKNOWN
  return new FeatureStatus(target, state)
}

/** 功能目录 + 每个包在本机的状态（设置页"扩展功能"用） */
export function featureStatuses(): FeatureStatus[] {
  const catalog: FeatureDescriptor[] = featureCatalog()
  const names: Set<string> | null = installedModuleNames()
  const out: FeatureStatus[] = []
  for (let i: number = 0; i < catalog.length; i++) {
    let state: FeatureState = FeatureState.UNKNOWN
    if (names !== null && names.has(catalog[i].moduleName)) {
      state = FeatureState.INSTALLED
    }
    out.push(new FeatureStatus(catalog[i], state))
  }
  return out
}

/** 给人看的一句话 */
export function featureStateLabel(state: FeatureState): string {
  if (state === FeatureState.INSTALLED) {
    return '已安装'
  }
  return '状态未知'
}
