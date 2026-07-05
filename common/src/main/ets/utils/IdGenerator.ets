// common/src/main/ets/utils/IdGenerator.ets
import { util } from '@kit.ArkTS'

export class IdGenerator {
  static generate(): string {
    return util.generateRandomUUID()
  }
}
