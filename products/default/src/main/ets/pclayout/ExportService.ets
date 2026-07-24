// ExportService.ets — Three-format export service for Weaver PC layout
import { picker, fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'

export class ExportService {

  static async exportTxt(content: string, title: string): Promise<boolean> {
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [title + '.txt']
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
      const saveResult: Array<string> = await documentPicker.save(options)
      if (saveResult.length === 0) return false
      const uri: string = saveResult[0]
      const plainText: string = ExportService.stripMarkdown(content)
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE)
      fileIo.writeSync(file.fd, plainText)
      fileIo.closeSync(file)
      return true
    } catch (e) {
      const err: BusinessError = e as BusinessError
      console.error('TXT export failed: ' + err.message)
      return false
    }
  }

  static async exportMd(content: string, title: string): Promise<boolean> {
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [title + '.md']
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
      const saveResult: Array<string> = await documentPicker.save(options)
      if (saveResult.length === 0) return false
      const uri: string = saveResult[0]
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE)
      fileIo.writeSync(file.fd, content)
      fileIo.closeSync(file)
      return true
    } catch (e) {
      const err: BusinessError = e as BusinessError
      console.error('MD export failed: ' + err.message)
      return false
    }
  }

  static async exportJson(bookName: string, content: string, chaptersJson: string): Promise<boolean> {
    try {
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions()
      options.newFileNames = [bookName + '_backup.json']
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
      const saveResult: Array<string> = await documentPicker.save(options)
      if (saveResult.length === 0) return false
      const uri: string = saveResult[0]
      const exportData: Record<string, Object> = {
        'bookName': bookName,
        'exportedAt': Date.now(),
        'content': content,
        'data': chaptersJson
      }
      const jsonStr: string = JSON.stringify(exportData)
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE)
      fileIo.writeSync(file.fd, jsonStr)
      fileIo.closeSync(file)
      return true
    } catch (e) {
      const err: BusinessError = e as BusinessError
      console.error('JSON export failed: ' + err.message)
      return false
    }
  }

  static stripMarkdown(md: string): string {
    let result: string = md
    // Strip heading prefixes
    result = result.replace(new RegExp('^#{1,6} ', 'gm'), '')
    // Strip bold/italic/underline markers
    result = result.replace(new RegExp('\\*\\*', 'g'), '')
    result = result.replace(new RegExp('\\*', 'g'), '')
    result = result.replace(new RegExp('__', 'g'), '')
    // Strip quote and list prefixes
    result = result.replace(new RegExp('^> ', 'gm'), '')
    result = result.replace(new RegExp('^- ', 'gm'), '')
    return result
  }
}