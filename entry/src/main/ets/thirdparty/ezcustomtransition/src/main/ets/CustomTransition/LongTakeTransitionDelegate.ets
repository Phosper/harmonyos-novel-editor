import { LongTakeSession } from '../sessions/LongTakeSession';
import { LongTakeTransitionType } from '../Constants/ezCustomTransitionConstants';
import { CardLongTakeDelegate } from './CardLongTakeDelegate';
import { ImageLongTakeDelegate } from './ImageLongTakeDelegate';

@Component
export struct LongTakeTransitionDelegate{
  @BuilderParam contentBuilder: () => void;

  @ObjectLink longTakeSession: LongTakeSession;

  build() {
    if (this.longTakeSession.type == LongTakeTransitionType.CardLongTake) {
      CardLongTakeDelegate({
        longTakeSession: this.longTakeSession,
        contentBuilder: (): void => {
          this.contentBuilder();
        }
      })
    } else {
      ImageLongTakeDelegate({
        longTakeSession: this.longTakeSession,
        contentBuilder: (): void => {
          this.contentBuilder();
        }
      })
    }
  }
}