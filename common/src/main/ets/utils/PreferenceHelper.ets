// common/src/main/ets/utils/PreferenceHelper.ets
import { preferences } from '@kit.ArkData'

const PREF_NAME: string = 'weaver_prefs'

export class PrefKeys {
  static readonly MODE: string              = 'weaver_mode'
  static readonly GUIDED: string            = 'weaver_guided'
  static readonly LAST_BOOK_ID: string      = 'last_book_id'
  static readonly LAST_CHAPTER_ID: string   = 'last_chapter_id'
  static readonly PAPER_THEME: string       = 'paper_theme'
  static readonly PRIVACY_SHIELD: string    = 'privacy_shield'
  static readonly FONT_SIZE: string         = 'font_size'
  static readonly PAPER_BG: string          = 'paper_background'
  static readonly PAPER_TEXT: string        = 'paper_text_color'
  static readonly PANEL_STATE: string       = 'panel_fold_state'
}

export class PreferenceHelper {
  private prefs: preferences.Preferences | null = null
  private static instance: PreferenceHelper | null = null

  static getInstance(): PreferenceHelper {
    if (!PreferenceHelper.instance) {
      PreferenceHelper.instance = new PreferenceHelper()
    }
    return PreferenceHelper.instance
  }

  async init(context: Context): Promise<void> {
    if (this.prefs) {
      return
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME)
  }

  isInitialized(): boolean {
    return this.prefs !== null
  }

  private ensurePrefs(): void {
    if (this.prefs === null) {
      throw new Error('Preferences not initialized. Call init() first.')
    }
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    this.ensurePrefs()
    const value: string = await this.prefs!.get(key, defaultValue) as string
    return value
  }

  async setString(key: string, value: string): Promise<void> {
    this.ensurePrefs()
    await this.prefs!.put(key, value)
    await this.prefs!.flush()
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    this.ensurePrefs()
    const value: boolean = await this.prefs!.get(key, defaultValue) as boolean
    return value
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    this.ensurePrefs()
    await this.prefs!.put(key, value)
    await this.prefs!.flush()
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    this.ensurePrefs()
    const value: number = await this.prefs!.get(key, defaultValue) as number
    return value
  }

  async setNumber(key: string, value: number): Promise<void> {
    this.ensurePrefs()
    await this.prefs!.put(key, value)
    await this.prefs!.flush()
  }

  // ===== Convenience methods =====

  async getMode(): Promise<string> {
    return await this.getString(PrefKeys.MODE, 'normal')
  }

  async setMode(mode: string): Promise<void> {
    await this.setString(PrefKeys.MODE, mode)
  }

  async isFirstLaunch(): Promise<boolean> {
    const guided: boolean = await this.getBoolean(PrefKeys.GUIDED, false)
    return !guided
  }

  async setGuided(): Promise<void> {
    await this.setBoolean(PrefKeys.GUIDED, true)
  }

  async getLastBookId(): Promise<string> {
    return await this.getString(PrefKeys.LAST_BOOK_ID, '')
  }

  async setLastBookId(bookId: string): Promise<void> {
    await this.setString(PrefKeys.LAST_BOOK_ID, bookId)
  }

  async getLastChapterId(): Promise<string> {
    return await this.getString(PrefKeys.LAST_CHAPTER_ID, '')
  }

  async setLastChapterId(chapterId: string): Promise<void> {
    await this.setString(PrefKeys.LAST_CHAPTER_ID, chapterId)
  }
}
