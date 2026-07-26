// Index.ets — App Shell: always PC layout
import { PcShell } from '../pclayout/PcShell'

@Entry
@Component
struct Index {
  build() {
    Column() {
      PcShell()
    }
  }
}
