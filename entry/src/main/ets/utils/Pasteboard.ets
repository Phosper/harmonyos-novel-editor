// 系统剪贴板读取授权（ohos.permission.READ_PASTEBOARD）
//
// 该权限是 user_grant：只在 module.json5 里声明还不够，运行时必须向用户申请；
// 未授权时 getData() 拿不到内容，编辑器的「粘贴」会退回应用内缓冲（appClipboard）。
//
// 策略：整个进程只问一次。用户拒绝后不再反复弹窗（系统本身也不会再弹），
// 由调用方按「只能粘贴应用内内容」降级。
import { abilityAccessCtrl, bundleManager, common, Permissions, PermissionRequestResult } from '@kit.AbilityKit'
import { Logger } from './Logger'

const READ_PASTEBOARD: Permissions = 'ohos.permission.READ_PASTEBOARD'

/** 用户是否已经做过选择（同意/拒绝）：同一次启动内只申请一次 */
let decided: boolean = false
let allowed: boolean = false

export class PasteboardAccess {
  /** 当前会话是否已获授权（未申请过恒为 false，不要用它代替 ensure） */
  static get granted(): boolean {
    return allowed
  }

  /**
   * 确保拿到读剪贴板的授权。
   * @param context 宿主 Context（`UIContext.getHostContext()`）；为空时直接按未授权处理
   * @returns 是否可读系统剪贴板；任何异常都返回 false（由调用方降级，不抛给 UI）
   */
  static async ensure(context: common.Context | undefined): Promise<boolean> {
    if (decided) {
      return allowed
    }
    if (context === undefined) {
      decided = true
      return false
    }
    try {
      const manager = abilityAccessCtrl.createAtManager()
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
      const status = manager.checkAccessTokenSync(info.appInfo.accessTokenId, READ_PASTEBOARD)
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        decided = true
        allowed = true
        return true
      }
      const result: PermissionRequestResult =
        await manager.requestPermissionsFromUser(context, [READ_PASTEBOARD])
      allowed = result.authResults.length > 0 && result.authResults[0] === 0
      decided = true
      Logger.info('PasteboardAccess granted=' + allowed.toString())
      return allowed
    } catch (e) {
      // 申请失败不能影响编辑：按未授权降级，下次启动再试
      Logger.warn('PasteboardAccess ensure failed: ' + String(e))
      decided = true
      allowed = false
      return false
    }
  }
}
