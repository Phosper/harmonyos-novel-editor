// 用户首选项（轻量 KV）—— 模式、首启、稿纸主题、深色模式
import { preferences } from '@kit.ArkData'
import { Logger } from './Logger'
import { BookMode } from '../model/Book'

const PREF_NAME: string = 'weaver_prefs'
const KEY_GUIDED: string = 'weaver_guided'
const KEY_MODE: string = 'weaver_mode'
const KEY_PAPER: string = 'weaver_paper'
const KEY_PAPER_LIGHT: string = 'weaver_paper_light'
const KEY_DARK: string = 'weaver_dark'
const KEY_DARK_EXPLICIT: string = 'weaver_dark_explicit'
const KEY_ENGINE: string = 'weaver_engine'
const KEY_THEME: string = 'weaver_theme'
const KEY_NICK: string = 'weaver_nickname'
const KEY_AVATAR: string = 'weaver_avatar'

export class PreferenceHelper {
  private static instance: PreferenceHelper | null = null
  private prefs: preferences.Preferences | null = null

  static getInstance(): PreferenceHelper {
    if (!PreferenceHelper.instance) {
      PreferenceHelper.instance = new PreferenceHelper()
    }
    return PreferenceHelper.instance
  }

  async init(context: Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, PREF_NAME)
    } catch (e) {
      Logger.error('PreferenceHelper init failed: ' + String(e))
    }
  }

  private async getString(key: string, def: string): Promise<string> {
    if (!this.prefs) return def
    try {
      const val: Object = await this.prefs.get(key, def)
      if (typeof val === 'string') return val
      return def
    } catch (e) {
      Logger.error('PreferenceHelper getString failed: ' + String(e))
      return def
    }
  }

  private async putString(key: string, value: string): Promise<void> {
    if (!this.prefs) return
    try {
      await this.prefs.put(key, value)
      await this.prefs.flush()
    } catch (e) {
      Logger.error('PreferenceHelper putString failed: ' + String(e))
    }
  }

  private async getBool(key: string, def: boolean): Promise<boolean> {
    if (!this.prefs) return def
    try {
      const val: Object = await this.prefs.get(key, def)
      if (typeof val === 'boolean') return val
      return def
    } catch (e) {
      Logger.error('PreferenceHelper getBool failed: ' + String(e))
      return def
    }
  }

  private async putBool(key: string, value: boolean): Promise<void> {
    if (!this.prefs) return
    try {
      await this.prefs.put(key, value)
      await this.prefs.flush()
    } catch (e) {
      Logger.error('PreferenceHelper putBool failed: ' + String(e))
    }
  }

  async isFirstLaunch(): Promise<boolean> {
    return !(await this.getBool(KEY_GUIDED, false))
  }

  async setGuided(): Promise<void> {
    await this.putBool(KEY_GUIDED, true)
  }

  /**
   * 读取写作模式。已统一为专业版：旧版本存过 'normal'，
   * 这里一律返回 PROFESSIONAL，避免历史数据把界面带回旧模式。
   */
  async getMode(): Promise<BookMode> {
    return BookMode.PROFESSIONAL
  }

  async setMode(mode: BookMode): Promise<void> {
    await this.putString(KEY_MODE, mode)
  }

  async getPaperTheme(): Promise<string> {
    return this.getString(KEY_PAPER, 'default')
  }

  async setPaperTheme(id: string): Promise<void> {
    await this.putString(KEY_PAPER, id)
  }

  /**
   * 上一次选择的浅色稿纸。深色模式会自动切到"夜读"，切回时用它还原，
   * 避免每次进出深色都把用户挑的稿纸吃掉。
   */
  async getPaperLight(): Promise<string> {
    return this.getString(KEY_PAPER_LIGHT, 'default')
  }

  async setPaperLight(id: string): Promise<void> {
    await this.putString(KEY_PAPER_LIGHT, id)
  }

  async getDarkMode(): Promise<boolean> {
    return this.getBool(KEY_DARK, false)
  }

  async setDarkMode(on: boolean): Promise<void> {
    await this.putBool(KEY_DARK, on)
    await this.putBool(KEY_DARK_EXPLICIT, true)
  }

  /** 用户是否在设置里显式选过深色模式；选过之后就不再跟随系统 */
  async isDarkExplicit(): Promise<boolean> {
    return this.getBool(KEY_DARK_EXPLICIT, false)
  }

  /** 全局主题 id（DesignTokens.THEMES；空串 = 未设置，走旧数据回退） */
  async getThemeId(): Promise<string> {
    return this.getString(KEY_THEME, '')
  }

  async setThemeId(id: string): Promise<void> {
    await this.putString(KEY_THEME, id)
  }

  /**
   * 本地账号昵称（空串 = 未登录）。
   * 账号服务尚未接入：先在本机记住一个身份，侧栏左下角据此显示头像 + 昵称；
   * 将来换成 Account Kit 时，只需把 UiStore.signIn 换成服务端身份写入。
   */
  async getNickname(): Promise<string> {
    return this.getString(KEY_NICK, '')
  }

  async setNickname(name: string): Promise<void> {
    await this.putString(KEY_NICK, name)
  }

  /** 自定义头像在沙箱里的绝对路径（空串 = 用系统占位人像） */
  async getAvatarPath(): Promise<string> {
    return this.getString(KEY_AVATAR, '')
  }

  async setAvatarPath(path: string): Promise<void> {
    await this.putString(KEY_AVATAR, path)
  }
}

export const prefs: PreferenceHelper = PreferenceHelper.getInstance()
