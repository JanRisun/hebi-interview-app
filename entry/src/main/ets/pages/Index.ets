// 底部 4 Tab 主框架：素材 / 速记卡 / 真题模考 / 个人中心
import { CategoryView } from './Category';
import { FlashcardView } from './Flashcard';
import { PracticeView } from './Practice';
import { ProfileView } from './Profile';
import { FONT, SPACE } from '../utils/Theme';

@Entry
@Component
struct Index {
  @State current: number = 0;

  // 自定义底部 Tab 按钮（emoji 图标 + 文字，选中高亮品牌色）
  @Builder tabBarItem(idx: number, icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
      Text(label)
        .fontSize(FONT.mini)
        .fontColor(this.current === idx ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .margin({ top: SPACE.xs })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          CategoryView()
        }.tabBar(this.tabBarItem(0, '📚', '素材'))

        TabContent() {
          FlashcardView()
        }.tabBar(this.tabBarItem(1, '🃏', '速记卡'))

        TabContent() {
          PracticeView()
        }.tabBar(this.tabBarItem(2, '📝', '真题模考'))

        TabContent() {
          ProfileView()
        }.tabBar(this.tabBarItem(3, '👤', '个人中心'))
      }
      .barPosition(BarPosition.End)
      .onChange((idx: number) => {
        this.current = idx;
      })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
